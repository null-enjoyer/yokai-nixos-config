#!/usr/bin/env python3
"""Local Brave history cache and native-messaging bridge for the YŌKAI search."""
import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import select
import shutil
import signal
import socket
import socketserver
import sqlite3
import stat
import struct
import subprocess
import sys
import threading
import time
from urllib.parse import urlsplit, urlunsplit
import uuid

MAX_MESSAGE = 1024 * 1024 - 1
MAX_ITEMS = 100000
NATIVE_TYPES = {'profiles', 'begin', 'chunk', 'commit', 'opened'}


def profiles(root):
    state = json.loads((root / 'Local State').read_text())
    result = []
    for directory, metadata in state.get('profile', {}).get('info_cache', {}).items():
        if valid_directory(directory) and (root / directory).is_dir():
            result.append({'directory': directory, 'name': str(metadata.get('name') or directory)})
    return sorted(result, key=lambda profile: (profile['directory'] != 'Default', profile['directory']))


def valid_directory(value):
    return isinstance(value, str) and value not in ('', '.', '..') and '/' not in value and '\\' not in value and not any(ord(c) < 32 for c in value)


def valid_url(value):
    if not isinstance(value, str) or len(value) > 8192 or any(c.isspace() or ord(c) < 32 or ord(c) == 127 for c in value):
        return False
    try:
        parsed = urlsplit(value)
        return parsed.scheme in ('http', 'https') and bool(parsed.hostname) and parsed.username is None and parsed.password is None and (parsed.port is None or 0 < parsed.port < 65536)
    except ValueError:
        return False


def source_id(value):
    if not isinstance(value, str) or str(uuid.UUID(value)) != value:
        raise ValueError('Invalid browser source identifier')
    return value


def snapshot_id(value):
    if not isinstance(value, str) or not 1 <= len(value) <= 128:
        raise ValueError('Invalid snapshot identifier')
    return value


def history_item(item):
    if not isinstance(item, dict) or not valid_url(item.get('url')):
        return None
    title = item.get('title') or ''
    if not isinstance(title, str) or len(title) > 8192:
        return None
    visited, count = item.get('lastVisitTime', 0), item.get('visitCount', 0)
    if not isinstance(visited, (int, float)) or not math.isfinite(visited) or not 0 <= visited <= 1e16:
        return None
    if not isinstance(count, (int, float)) or not math.isfinite(count) or not 0 <= count <= 1e12:
        return None
    parsed = urlsplit(item['url'])
    path = '/' + '/'.join([segment for segment in parsed.path.split('/') if segment][:3])
    url = urlunsplit((parsed.scheme, parsed.netloc, path, '', ''))
    return (url, title, visited, int(count))


def add_history_item(items, item):
    previous = items.get(item[0])
    if previous is None:
        items[item[0]] = item
        return
    newest = max((previous, item), key=lambda row: (row[2], row[3]))
    items[item[0]] = (item[0], newest[1], max(previous[2], item[2]), max(previous[3], item[3]))


def normalized_history(rows):
    items = {}
    for url, title, visited, count in rows:
        item = history_item({'url': url, 'title': title, 'lastVisitTime': visited, 'visitCount': count})
        if item is not None:
            add_history_item(items, item)
    return items


def fuzzy_score(query, value):
    needle, text = query.strip().lower(), value.lower()
    if not needle:
        return 0
    previous, total = -1, 0
    for character in needle:
        if character.isspace():
            continue
        position = text.find(character, previous + 1)
        if position < 0:
            return -1
        total += 10
        if position == 0 or text[position - 1].isspace() or text[position - 1] in '._/-':
            total += 12
        if position == previous + 1:
            total += 8
        total -= position * 0.1 if previous < 0 else (position - previous - 1) * 0.4
        previous = position
    return total + 1 / (1 + len(text))


def domain_query(query):
    return query.strip().lower().removeprefix('https://').removeprefix('http://').removeprefix('www.').removesuffix('/')


def field_match(query, value):
    """Compare match quality first, preserving the fuzzy score within each class."""
    needle, text = query.strip().lower(), value.lower()
    score = fuzzy_score(query, value)
    if not needle or score < 0:
        return -1, -1
    if needle == text.strip():
        return 4, score
    quality, position = 0, text.find(needle)
    while position >= 0:
        end = position + len(needle)
        left = position == 0 or word_boundary(text[position - 1])
        right = end == len(text) or word_boundary(text[end])
        quality = max(quality, 3 if left and right else 2 if left else 1)
        if quality == 3:
            break
        position = text.find(needle, position + 1)
    return quality, score


def word_boundary(character):
    return character.isspace() or character in '.,_/\\-:;()[]{}—–!?"\'@'


def best_variant_match(matches):
    """A primary-query match wins ties in quality, including its own score."""
    quality = max(match[0] for match in matches)
    if matches[0][0] == quality:
        return quality, matches[0][1], True
    return quality, max(score for current, score in matches if current == quality), False


def browser_match(query, url, title):
    parsed = urlsplit(url)
    domain = (parsed.hostname or '').removeprefix('www.')
    needle = domain_query(query)
    domain_quality, domain_score = field_match(needle, domain)
    site_name = domain.partition('.')[0]
    if needle == site_name:
        domain_quality, domain_score = max((domain_quality, domain_score), field_match(needle, site_name))
    if domain_quality >= 0:
        domain_score += 30 if needle == domain else 15 if needle in domain else 0
        if parsed.path in ('', '/'):
            # A site-name query should find its home before recent product pages.
            domain_score += 40 if not parsed.query else 25
    return max((domain_quality, domain_score), field_match(query, title), field_match(query, url))


class HistoryStore:
    """One daemon owns SQLite and swaps complete source snapshots under its lock."""

    def __init__(self, database):
        database.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        self.lock = threading.RLock()
        self.connection = sqlite3.connect(database, check_same_thread=False)
        os.chmod(database, 0o600)
        self.connection.execute('PRAGMA journal_mode=WAL')
        self.connection.executescript('''
            CREATE TABLE IF NOT EXISTS sources (
                id TEXT PRIMARY KEY, profile_directory TEXT NOT NULL,
                name TEXT NOT NULL, updated REAL NOT NULL
            );
            CREATE TABLE IF NOT EXISTS history (
                source_id TEXT NOT NULL, url TEXT NOT NULL, title TEXT NOT NULL,
                visited REAL NOT NULL, visit_count INTEGER NOT NULL,
                PRIMARY KEY(source_id, url)
            );
        ''')
        self.sources = {row[0]: {'profileDirectory': row[1], 'name': row[2], 'updated': row[3]}
                        for row in self.connection.execute('SELECT id,profile_directory,name,updated FROM sources')}
        self.items = {source: tuple(self.connection.execute(
            'SELECT url,title,visited,visit_count FROM history WHERE source_id=?', (source,)))
                      for source in self.sources}

        for source, rows in self.items.items():
            normalized = normalized_history(rows)
            if {row[0]: row for row in rows} != normalized:
                with self.connection:
                    self.connection.execute('DELETE FROM history WHERE source_id=?', (source,))
                    self.connection.executemany('INSERT INTO history VALUES (?,?,?,?,?)',
                                                ((source, *item) for item in normalized.values()))
                self.items[source] = tuple(normalized.values())

    def commit(self, source, directory, name, items):
        updated = time.time()
        items = normalized_history(items.values())
        snapshot = tuple(items.values())
        with self.lock:
            superseded = [identifier for identifier, metadata in self.sources.items()
                          if identifier != source and metadata['profileDirectory'] == directory]
            previous = {item[0]: item for item in self.items.get(source, ())}
            removed = previous.keys() - items.keys()
            changed = [item for url, item in items.items() if previous.get(url) != item]
            with self.connection:
                self.connection.executemany('DELETE FROM history WHERE source_id=?',
                                            ((identifier,) for identifier in superseded))
                self.connection.executemany('DELETE FROM sources WHERE id=?',
                                            ((identifier,) for identifier in superseded))
                self.connection.execute('''
                    INSERT INTO sources VALUES (?,?,?,?)
                    ON CONFLICT(id) DO UPDATE SET
                        profile_directory=excluded.profile_directory,
                        name=excluded.name, updated=excluded.updated
                ''', (source, directory, name, updated))
                self.connection.executemany('DELETE FROM history WHERE source_id=? AND url=?',
                                            ((source, url) for url in removed))
                self.connection.executemany('''
                    INSERT INTO history VALUES (?,?,?,?,?)
                    ON CONFLICT(source_id,url) DO UPDATE SET
                        title=excluded.title, visited=excluded.visited,
                        visit_count=excluded.visit_count
                ''', ((source, *item) for item in changed))
            for identifier in superseded:
                self.sources.pop(identifier)
                self.items.pop(identifier)
            self.sources[source] = {'profileDirectory': directory, 'name': name, 'updated': updated}
            self.items[source] = snapshot
            return superseded

    def search(self, queries):
        if not isinstance(queries, list) or not 1 <= len(queries) <= 8 or any(not isinstance(q, str) or len(q) > 512 for q in queries):
            raise ValueError('Invalid search query')
        with self.lock:
            sources, snapshots = dict(self.sources), dict(self.items)
        response = {'results': [], 'ready': bool(sources), 'busy': False}
        if not queries[0].strip():
            return response
        matches = []
        for source, items in snapshots.items():
            directory = sources[source]['profileDirectory']
            for url, title, visited, count in items:
                if not valid_url(url):
                    continue
                quality, score, original = best_variant_match([browser_match(query, url, title) for query in queries])
                if quality < 0:
                    continue
                result = {'kind': 'browser', 'id': source + ':' + hashlib.sha256(url.encode()).hexdigest()[:20],
                          'title': title, 'url': url, 'sourceId': source, 'sourceLabel': 'Brave',
                          'profileDirectory': directory, 'profileName': sources[source]['name'],
                          'matchQuality': quality, 'score': round(score, 4), 'originalMatch': original}
                matches.append((result, visited, count))
        matches.sort(key=lambda row: (-row[0]['matchQuality'], -int(row[0]['originalMatch']), -row[0]['score'], -row[1], -row[2], row[0]['url']))
        seen, domains = set(), {}
        for result, _, _ in matches:
            key = (result['sourceId'], result['url'])
            parsed = urlsplit(result['url'])
            domain = (result['sourceId'], parsed.hostname)
            if parsed.path in ('', '/') and any(fuzzy_score(domain_query(query), (parsed.hostname or '').removeprefix('www.')) >= 0
                                                for query in queries):
                key = (result['sourceId'], parsed.scheme, (parsed.hostname or '').removeprefix('www.'), parsed.port, '/')
            if key in seen or domains.get(domain, 0) >= 3:
                continue
            response['results'].append(result)
            seen.add(key)
            domains[domain] = domains.get(domain, 0) + 1
            if len(response['results']) == 20:
                break
        return response

    def source_for_open(self, source, url):
        if not valid_url(url):
            raise ValueError('Only HTTP and HTTPS browser results can be opened')
        with self.lock:
            metadata = self.sources.get(source)
            if metadata is None or not any(item[0] == url for item in self.items[source]):
                raise ValueError('Browser result is no longer available')
            return dict(metadata)

    def close(self):
        self.connection.close()


def encoded_message(message):
    data = json.dumps(message, ensure_ascii=False, allow_nan=False).encode()
    if len(data) > MAX_MESSAGE:
        raise ValueError('Browser message is too large')
    return data


class BrowserServer(socketserver.ThreadingUnixStreamServer):
    daemon_threads = True

    def __init__(self, path, store, profile_root, brave):
        self.store, self.profile_root, self.brave = store, profile_root, brave
        self.lock = threading.RLock()
        self.active, self.generations, self.waiting = {}, {}, {}
        self.retired_sources = set()
        super().__init__(str(path), BrowserClient)
        os.chmod(path, 0o600)

    def open_url(self, source, url):
        metadata = self.store.source_for_open(source_id(source), url)
        directory = metadata['profileDirectory']
        if directory not in {profile['directory'] for profile in profiles(self.profile_root)}:
            raise ValueError('The Brave profile no longer exists')
        request = str(uuid.uuid4())
        event = threading.Event()
        with self.lock:
            client = self.active.get(source)
            if client is not None and client.bound_directory != directory:
                client = None
            self.waiting[request] = {'event': event, 'source': source, 'client': client, 'result': None}
        try:
            if client is not None:
                try:
                    client.send({'type': 'open', 'requestId': request, 'url': url})
                    if event.wait(2):
                        with self.lock:
                            answer = self.waiting[request]['result']
                        if answer and answer.get('ok'):
                            return {'ok': True, 'method': 'extension'}
                        raise ValueError((answer or {}).get('error') or 'Brave could not open the result')
                    # An uncertain delivery could create duplicate tabs if retried externally.
                    raise ValueError('Brave did not confirm opening the result')
                except OSError:
                    pass
            executable = self.brave or shutil.which('brave')
            if not executable:
                raise ValueError('Brave is unavailable')
            launcher = shutil.which('systemd-run')
            if not launcher:
                raise ValueError('The desktop application launcher is unavailable')
            try:
                subprocess.run([launcher, '--user', '--collect', '--property=Type=exec', '--slice=app.slice',
                                '--', executable, '--profile-directory=' + directory, url],
                               stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                               check=True, timeout=3)
            except (subprocess.SubprocessError, OSError):
                raise ValueError('Brave could not be launched in this desktop session') from None
            return {'ok': True, 'method': 'browser'}
        finally:
            with self.lock:
                self.waiting.pop(request, None)


class BrowserClient(socketserver.StreamRequestHandler):
    def setup(self):
        super().setup()
        self.send_lock = threading.Lock()
        self.pending = None
        self.bound_source = None
        self.bound_directory = None
        self.retired = False

    def send(self, message):
        data = encoded_message(message) + b'\n'
        with self.send_lock:
            self.wfile.write(data)
            self.wfile.flush()

    def handle(self):
        try:
            self.connection.settimeout(5)
            hello = self.read_message()
            if hello is None:
                return
            role = hello.get('role') if hello.get('type') == 'hello' else None
            if role not in ('native', 'cli'):
                return
            self.connection.settimeout(None if role == 'native' else 5)
            while True:
                message = self.read_message()
                if message is None:
                    return
                kind = message.get('type')
                try:
                    if role == 'native':
                        if kind not in NATIVE_TYPES:
                            raise ValueError('Unsupported browser message')
                        result = self.native_request(message)
                        result.update(type=kind, requestId=message.get('requestId'))
                    elif kind == 'search':
                        result = self.server.store.search(message.get('queries'))
                    elif kind == 'open':
                        result = self.server.open_url(message.get('sourceId'), message.get('url'))
                    elif kind == 'status':
                        with self.server.lock, self.server.store.lock:
                            result = {'ready': bool(self.server.store.sources), 'busy': False,
                                      'sourceCount': len(self.server.store.sources), 'connectedSources': list(self.server.active)}
                    else:
                        raise ValueError('Unsupported browser request')
                except (ValueError, TypeError, OSError, sqlite3.Error) as error:
                    result = {'ok': False, 'error': str(error)}
                    if role == 'native':
                        result.update(type=kind, requestId=message.get('requestId'))
                self.send(result)
        except (OSError, ValueError, json.JSONDecodeError):
            pass
        finally:
            with self.server.lock:
                for source, client in list(self.server.active.items()):
                    if client is self:
                        del self.server.active[source]
                for waiting in self.server.waiting.values():
                    if waiting['client'] is self:
                        waiting['result'] = {'ok': False, 'error': 'Brave disconnected'}
                        waiting['event'].set()

    def read_message(self):
        raw = self.rfile.readline(MAX_MESSAGE + 2)
        if not raw:
            return None
        if len(raw) > MAX_MESSAGE + 1 or not raw.endswith(b'\n'):
            raise ValueError('Browser message is too large')
        message = json.loads(raw)
        if not isinstance(message, dict):
            raise ValueError('Invalid browser message')
        return message

    def native_request(self, message):
        kind = message['type']
        if kind == 'profiles':
            return {'ok': True, 'profiles': profiles(self.server.profile_root)}
        if kind == 'opened':
            with self.server.lock:
                waiting = self.server.waiting.get(message.get('requestId'))
                if waiting is None or waiting['client'] is not self:
                    raise ValueError('Unknown browser open request')
                waiting['result'] = {'ok': message.get('ok') is True, 'error': str(message.get('error') or '')[:512]}
                waiting['event'].set()
            return {'ok': True}
        source = source_id(message.get('sourceId'))
        snapshot = snapshot_id(message.get('snapshotId'))
        with self.server.lock:
            if self.retired or source in self.server.retired_sources:
                raise ValueError('Browser source was replaced by another extension instance')
            if kind == 'begin':
                directory = message.get('profileDirectory')
                available = {profile['directory']: profile['name'] for profile in profiles(self.server.profile_root)}
                if directory not in available:
                    raise ValueError('Select an existing Brave profile')
                if self.bound_source is not None and self.bound_source != source:
                    raise ValueError('Browser connection cannot change source identity')
                self.bound_source = source
                self.bound_directory = directory
                generation = self.server.generations.get(source, 0) + 1
                self.server.generations[source] = generation
                self.pending = {'source': source, 'snapshot': snapshot, 'generation': generation,
                                'directory': directory, 'name': available[directory], 'items': {}}
                self.server.active[source] = self
                return {'ok': True}
            pending = self.pending
            if pending is None or pending['source'] != source or pending['snapshot'] != snapshot or pending['generation'] != self.server.generations.get(source):
                raise ValueError('Browser snapshot was superseded or not started')
            if kind == 'chunk':
                items = message.get('items')
                if not isinstance(items, list) or len(items) > 1000:
                    raise ValueError('Invalid browser history chunk')
                for raw_item in items:
                    item = history_item(raw_item)
                    if item is not None:
                        add_history_item(pending['items'], item)
                if len(pending['items']) > MAX_ITEMS:
                    self.pending = None
                    raise ValueError('Browser history snapshot is too large')
                return {'ok': True, 'accepted': len(pending['items'])}
            superseded = self.server.store.commit(source, pending['directory'], pending['name'], pending['items'])
            for identifier in superseded:
                self.server.retired_sources.add(identifier)
                previous_client = self.server.active.pop(identifier, None)
                self.server.generations[identifier] = self.server.generations.get(identifier, 0) + 1
                if previous_client is not None:
                    previous_client.retired = True
                    previous_client.pending = None
            self.pending = None
            return {'ok': True, 'count': len(pending['items'])}


def connect(path, role, timeout=5):
    connection = socket.socket(socket.AF_UNIX)
    try:
        connection.settimeout(timeout)
        connection.connect(str(path))
        connection.sendall(encoded_message({'type': 'hello', 'role': role}) + b'\n')
    except (OSError, ValueError):
        connection.close()
        raise
    return connection


def request(path, message):
    try:
        with connect(path, 'cli') as connection:
            connection.sendall(encoded_message(message) + b'\n')
            with connection.makefile('rb') as reader:
                raw = reader.readline(MAX_MESSAGE + 2)
                if not raw or len(raw) > MAX_MESSAGE + 1:
                    raise ValueError('Invalid browser service response')
                return json.loads(raw)
    except (OSError, ValueError) as error:
        return {'ok': False, 'ready': False, 'busy': False, 'results': [],
                'error': 'Browser history service is unavailable: ' + str(error)}


def read_frame(reader):
    def exact(length):
        data = bytearray()
        while len(data) < length:
            part = reader.read(length - len(data))
            if not part:
                break
            data.extend(part)
        return bytes(data)

    header = exact(4)
    if not header:
        return None
    if len(header) != 4:
        raise ValueError('Truncated native message header')
    length, = struct.unpack('<I', header)
    if length > MAX_MESSAGE:
        raise ValueError('Native message is too large')
    data = exact(length)
    if len(data) != length:
        raise ValueError('Truncated native message')
    message = json.loads(data)
    if not isinstance(message, dict):
        raise ValueError('Invalid native message')
    return message


def write_frame(writer, message):
    data = encoded_message(message)
    writer.write(struct.pack('<I', len(data)) + data)
    writer.flush()


def native(path, origin):
    expected = os.environ.get('YOKAI_BRAVE_EXTENSION_ID')
    if expected and origin != f'chrome-extension://{expected}/':
        raise ValueError('Unexpected native messaging caller')
    with connect(path, 'native') as connection:
        connection.settimeout(None)
        stopped = threading.Event()
        output_lock = threading.Lock()

        def output(message):
            with output_lock:
                write_frame(sys.stdout.buffer, message)

        def receive():
            try:
                with connection.makefile('rb') as reader:
                    while not stopped.is_set():
                        raw = reader.readline(MAX_MESSAGE + 2)
                        if not raw:
                            break
                        if len(raw) > MAX_MESSAGE + 1:
                            raise ValueError('Browser message is too large')
                        output(json.loads(raw))
            except (OSError, ValueError):
                pass
            finally:
                stopped.set()

        thread = threading.Thread(target=receive, daemon=True)
        thread.start()
        try:
            while not stopped.is_set():
                incoming = sys.stdin.buffer.raw
                if not select.select([incoming], [], [], 0.2)[0]:
                    continue
                message = read_frame(incoming)
                if message is None:
                    break
                if not isinstance(message.get('type'), str) or message['type'] not in NATIVE_TYPES:
                    output({'type': message.get('type'), 'requestId': message.get('requestId'),
                            'ok': False, 'error': 'Unsupported browser message'})
                    continue
                connection.sendall(encoded_message(message) + b'\n')
        finally:
            stopped.set()
            try:
                connection.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass
            thread.join(timeout=1)


def serve(path, database, profile_root, brave):
    os.umask(0o077)
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    if path.exists():
        try:
            with socket.socket(socket.AF_UNIX) as probe:
                probe.connect(str(path))
        except ConnectionRefusedError:
            if not stat.S_ISSOCK(path.stat().st_mode) or path.stat().st_uid != os.getuid():
                raise ValueError('Browser socket path is occupied')
            path.unlink()
        else:
            raise ValueError('Browser service is already running')
    store = HistoryStore(database)
    server = BrowserServer(path, store, profile_root, brave)
    for signum in (signal.SIGTERM, signal.SIGINT):
        signal.signal(signum, lambda *_: threading.Thread(target=server.shutdown, daemon=True).start())
    try:
        server.serve_forever(poll_interval=0.2)
    finally:
        server.server_close()
        with store.lock:
            store.close()
        path.unlink(missing_ok=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    runtime = Path(os.environ.get('XDG_RUNTIME_DIR') or f'/run/user/{os.getuid()}')
    state = Path(os.environ.get('XDG_STATE_HOME') or Path.home() / '.local/state')
    parser.add_argument('--socket', type=Path, default=runtime / 'yokai-browser.sock')
    parser.add_argument('--database', type=Path, default=state / 'yokai/browser.sqlite3')
    parser.add_argument('--profiles', type=Path, default=Path.home() / '.config/BraveSoftware/Brave-Browser')
    commands = parser.add_subparsers(dest='command', required=True)
    commands.add_parser('serve')
    host = commands.add_parser('native')
    host.add_argument('origin', nargs='?')
    search = commands.add_parser('search')
    search.add_argument('--queries', required=True)
    opening = commands.add_parser('open')
    opening.add_argument('--source', required=True)
    opening.add_argument('--url', required=True)
    commands.add_parser('status')
    args = parser.parse_args()
    try:
        if args.command == 'serve':
            serve(args.socket, args.database, args.profiles, os.environ.get('BRAVE_PATH'))
            return
        if args.command == 'native':
            native(args.socket, args.origin)
            return
        if args.command == 'search':
            result = request(args.socket, {'type': 'search', 'queries': json.loads(args.queries)})
        elif args.command == 'open':
            result = request(args.socket, {'type': 'open', 'sourceId': args.source, 'url': args.url})
        else:
            result = request(args.socket, {'type': 'status'})
        print(json.dumps(result, ensure_ascii=False, allow_nan=False))
        if result.get('ok') is False or result.get('error'):
            raise SystemExit(1)
    except (OSError, ValueError, sqlite3.Error) as error:
        if args.command in ('serve', 'native'):
            print(str(error), file=sys.stderr)
        else:
            print(json.dumps({'ok': False, 'ready': False, 'busy': False, 'results': [], 'error': str(error)}))
        raise SystemExit(1)


if __name__ == '__main__':
    main()
