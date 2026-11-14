#!/usr/bin/env python3
"""Persistent network traffic intervals, independent of the desktop overlay."""
import argparse
from contextlib import closing
import json
import os
from pathlib import Path
import signal
import sqlite3
import threading
import time

from metrics import network_counters

INTERVAL = 5
RETENTION = 86400
PERIODS = (900, 3600, 21600, RETENTION)
MAX_INTERVAL = INTERVAL * 3
POINT_COUNT = 180


def database_path():
    state = Path(os.environ.get('XDG_STATE_HOME') or Path.home() / '.local/state')
    return state / 'yokai/network.sqlite3'


def open_writer(path):
    path.parent.mkdir(parents=True, exist_ok=True)
    connection = sqlite3.connect(path, timeout=5)
    connection.execute('PRAGMA journal_mode=WAL')
    connection.execute('PRAGMA synchronous=NORMAL')
    connection.executescript('''
        CREATE TABLE IF NOT EXISTS intervals (
            id INTEGER PRIMARY KEY,
            interface TEXT NOT NULL,
            start REAL NOT NULL,
            end REAL NOT NULL,
            elapsed REAL NOT NULL,
            download INTEGER,
            upload INTEGER
        );
        CREATE INDEX IF NOT EXISTS intervals_interface_end
            ON intervals(interface, end);
        CREATE INDEX IF NOT EXISTS intervals_end ON intervals(end);
    ''')
    return connection


def network_snapshot():
    counters = {}
    for name, values in network_counters().items():
        try:
            identity = int((Path('/sys/class/net') / name / 'ifindex').read_text())
        except (OSError, ValueError):
            # An interface disappearing during the read cannot establish a baseline.
            continue
        counters[name] = (identity, *values)
    return counters


class Sampler:
    """Counter baselines live only for this collector process, never across restarts."""

    def __init__(self):
        self.previous = {}
        self.wall = None
        self.monotonic = None

    def sample(self, counters, wall, monotonic):
        elapsed = monotonic - self.monotonic if self.monotonic is not None else 0
        wall_elapsed = wall - self.wall if self.wall is not None else 0
        uninterrupted = 0 < elapsed <= MAX_INTERVAL and abs(wall_elapsed - elapsed) <= 1
        backwards = self.wall is not None and wall < self.wall
        rows = []
        for name, (identity, received, sent) in counters.items():
            previous = self.previous.get(name)
            if uninterrupted and previous is not None and identity == previous[0]:
                download = received - previous[1] if received >= previous[1] else None
                upload = sent - previous[2] if sent >= previous[2] else None
                rows.append((name, self.wall, wall, elapsed, download, upload))
            else:
                rows.append((name, wall, wall, 0, None, None))
        self.previous, self.wall, self.monotonic = counters, wall, monotonic
        return rows, backwards


def write_sample(connection, rows, now, prune=False, backwards=False):
    with connection:
        # Future timestamps become invalid after a wall clock correction backwards.
        if backwards:
            connection.execute('DELETE FROM intervals WHERE end > ?', (now,))
        connection.executemany('''
            INSERT INTO intervals(interface, start, end, elapsed, download, upload)
            VALUES (?, ?, ?, ?, ?, ?)
        ''', rows)
        if prune:
            connection.execute('DELETE FROM intervals WHERE end <= ?', (now - RETENTION,))


def collect(path):
    stop = threading.Event()
    for signum in (signal.SIGTERM, signal.SIGINT):
        signal.signal(signum, lambda *_: stop.set())
    sampler = Sampler()
    connection = open_writer(path)
    prune_at = 0
    try:
        while not stop.is_set():
            started = time.monotonic()
            try:
                counters = network_snapshot()
            except (OSError, ValueError, IndexError):
                # Losing the source invalidates the baseline, leaving an explicit gap.
                counters = {}
            now = time.time()
            rows, backwards = sampler.sample(counters, now, time.monotonic())
            prune = started >= prune_at
            write_sample(connection, rows, now, prune, backwards)
            if prune:
                prune_at = started + 60
            stop.wait(max(0, INTERVAL - (time.monotonic() - started)))
    finally:
        connection.close()


def empty_history(interface, period, now):
    start = now - period
    width = period / POINT_COUNT
    return {
        'interface': interface, 'period': period, 'start': start, 'end': now,
        'observedSince': None, 'latest': {'download': None, 'upload': None},
        'totals': {'download': 0, 'upload': 0},
        'points': [{'time': start + (index + 0.5) * width,
                    'download': None, 'upload': None} for index in range(POINT_COUNT)],
    }


def summarize(interface, period, now, rows, observed_since):
    result = empty_history(interface, period, now)
    result['observedSince'] = observed_since
    start = result['start']
    width = period / POINT_COUNT
    amounts = [[0.0, 0.0] for _ in result['points']]
    coverage = [[0.0, 0.0] for _ in result['points']]
    spans = [[[None, None], [None, None]] for _ in result['points']]
    observed_spans = [[None, None], [None, None]]
    if rows:
        _, end, elapsed, download, upload = rows[-1]
        if elapsed > 0 and 0 <= now - end <= MAX_INTERVAL:
            result['latest'] = {
                'download': download / elapsed if download is not None else None,
                'upload': upload / elapsed if upload is not None else None,
            }
    for begin, end, elapsed, download, upload in rows:
        if elapsed <= 0 or end <= begin:
            continue
        lower, upper = max(begin, start), min(end, now)
        if upper <= lower:
            continue
        for direction, (key, delta) in enumerate((('download', download), ('upload', upload))):
            if delta is None:
                continue
            observed = observed_spans[direction]
            observed[0] = lower if observed[0] is None else min(observed[0], lower)
            observed[1] = upper if observed[1] is None else max(observed[1], upper)
            # Boundary totals prorate the measured byte delta uniformly over its interval.
            result['totals'][key] += delta * (upper - lower) / (end - begin)
            first = max(0, int((lower - start) / width))
            last = min(POINT_COUNT - 1, int((upper - start) / width))
            for index in range(first, last + 1):
                bin_start = start + index * width
                overlap = max(0, min(upper, bin_start + width) - max(lower, bin_start))
                if overlap <= 0:
                    continue
                amounts[index][direction] += delta / elapsed * overlap
                coverage[index][direction] += overlap
                span = spans[index][direction]
                clipped_begin, clipped_end = max(lower, bin_start), min(upper, bin_start + width)
                span[0] = clipped_begin if span[0] is None else min(span[0], clipped_begin)
                span[1] = clipped_end if span[1] is None else max(span[1], clipped_end)
    gap_markers = set()
    split_points = []
    for index, point in enumerate(result['points']):
        valid_spans = []
        for direction, key in enumerate(('download', 'upload')):
            span = spans[index][direction]
            if coverage[index][direction] >= width - 0.001:
                point[key] = round(amounts[index][direction] / coverage[index][direction], 2)
                valid_spans.append((key, span))
            elif span[0] is not None:
                first, last = observed_spans[direction]
                contiguous = coverage[index][direction] >= span[1] - span[0] - 0.001
                edge = span[0] == first or span[1] == last
                # Only contiguous leading/trailing observations can form partial bins.
                # Internal gaps remain null, even when narrower than a coarse bin.
                if contiguous and edge:
                    point[key] = round(amounts[index][direction] / coverage[index][direction], 2)
                    valid_spans.append((key, span))
                    if span[0] == first and first > start:
                        gap_markers.add((max(start, first - 0.000001), key))
                    if span[1] == last and last < now:
                        gap_markers.add((min(now, last + 0.000001), key))
        if valid_spans:
            shared_start = max(span[0] for _, span in valid_spans)
            shared_end = min(span[1] for _, span in valid_spans)
            if shared_start <= shared_end:
                point['time'] = (shared_start + shared_end) / 2
            else:
                # Independent counter resets can leave disjoint directional spans.
                for key, span in valid_spans:
                    separate = {'time': (span[0] + span[1]) / 2, 'download': None, 'upload': None}
                    separate[key] = point[key]
                    split_points.append(separate)
                point['download'] = point['upload'] = None
    result['points'].extend(split_points)
    result['points'].extend({'time': marker, 'download': None, 'upload': None, 'gap': key}
                            for marker, key in gap_markers)
    result['points'].sort(key=lambda point: point['time'])
    result['totals'] = {key: round(value, 2) for key, value in result['totals'].items()}
    return result


def read_history(path, interface, period, now=None):
    now = time.time() if now is None else now
    empty = empty_history(interface, period, now)
    try:
        if not path.exists():
            return empty
        with closing(sqlite3.connect(path.resolve().as_uri() + '?mode=ro', uri=True, timeout=1)) as connection:
            # Both queries share a snapshot while the collector commits independently.
            connection.execute('BEGIN')
            observed = connection.execute(
                'SELECT MIN(start) FROM intervals WHERE interface = ? AND end > ? AND end <= ?',
                (interface, now - RETENTION, now)).fetchone()[0]
            rows = connection.execute('''
                SELECT start, end, elapsed, download, upload FROM intervals
                WHERE interface = ? AND end >= ? AND start <= ? AND end <= ?
                ORDER BY end, id
            ''', (interface, now - period, now, now)).fetchall()
        return summarize(interface, period, now, rows, observed)
    except (sqlite3.Error, OSError) as error:
        empty['error'] = str(error)
        return empty


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--database', type=Path, default=database_path())
    commands = parser.add_subparsers(dest='command', required=True)
    commands.add_parser('collect')
    reader = commands.add_parser('read')
    reader.add_argument('--interface', required=True)
    reader.add_argument('--period', type=int, choices=PERIODS, required=True)
    args = parser.parse_args()
    if args.command == 'collect':
        collect(args.database)
    else:
        print(json.dumps(read_history(args.database, args.interface, args.period), allow_nan=False))


if __name__ == '__main__':
    main()
