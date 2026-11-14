#!/usr/bin/env python3
"""Private clipboard storage shared by wl-paste collectors and the YŌKAI overlay."""
import argparse
from contextlib import contextmanager
import fcntl
import hashlib
import io
import json
import os
from pathlib import Path
import re
import sqlite3
import subprocess
import sys
import tempfile
import time
import warnings

MAX_ENTRY_BYTES = 16 * 1024 * 1024
MAX_HISTORY_BYTES = 128 * 1024 * 1024
MAX_UNPINNED = 500
PREVIEW_CHARACTERS = 16000


def database_path():
    state = Path(os.environ.get('XDG_STATE_HOME') or Path.home() / '.local/state')
    return state / 'yokai/clipboard.sqlite3'


def legacy_database_path():
    cache = Path(os.environ.get('XDG_CACHE_HOME') or Path.home() / '.cache')
    return Path(os.environ.get('CLIPHIST_DB_PATH') or cache / 'cliphist/db')


def entry_id(kind, payload):
    return hashlib.sha256(kind.encode('ascii') + b'\0' + payload).hexdigest()


def image_preview(payload):
    # Decode fully before admitting an image. The thumbnail never inherits metadata.
    from PIL import Image, ImageOps
    with warnings.catch_warnings():
        warnings.simplefilter('error', Image.DecompressionBombWarning)
        with Image.open(io.BytesIO(payload)) as source:
            mime = Image.MIME.get(source.format)
            if not mime or not mime.startswith('image/'):
                raise ValueError('unsupported image')
            width, height = source.size
            if width * height > 32_000_000:
                raise ValueError('image too large')
            source.load()
            preview = ImageOps.exif_transpose(source)
            preview.thumbnail((320, 200))
            preview = preview.convert('RGBA')
            output = io.BytesIO()
            preview.save(output, format='PNG')
    return mime, f'Image · {width} × {height}', output.getvalue()


class ClipboardStore:
    """One command owns one connection; write transactions also own thumbnail files."""

    def __init__(self, path):
        os.umask(0o077)
        self.path = Path(path)
        self.path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        self.path.parent.chmod(0o700)
        self.thumbnails = self.path.parent / 'clipboard-thumbnails'
        self.thumbnails.mkdir(mode=0o700, exist_ok=True)
        self.thumbnails.chmod(0o700)
        self.db = sqlite3.connect(self.path, timeout=10, isolation_level=None)
        self.path.chmod(0o600)
        self.db.row_factory = sqlite3.Row
        self.db.execute('PRAGMA busy_timeout=10000')
        self.db.execute('PRAGMA journal_mode=WAL')
        self.db.execute('PRAGMA synchronous=NORMAL')
        self.db.execute('PRAGMA secure_delete=ON')
        self.db.executescript('''
            CREATE TABLE IF NOT EXISTS entries (
                id TEXT PRIMARY KEY,
                kind TEXT NOT NULL,
                payload BLOB NOT NULL,
                mime TEXT NOT NULL,
                title TEXT NOT NULL,
                size INTEGER NOT NULL,
                pinned INTEGER NOT NULL DEFAULT 0,
                created REAL NOT NULL
            );
            CREATE INDEX IF NOT EXISTS entries_recent ON entries(pinned, created);
            CREATE TABLE IF NOT EXISTS settings (key TEXT PRIMARY KEY, value TEXT NOT NULL);
        ''')

    def close(self):
        self.db.close()

    @contextmanager
    def write(self):
        self.db.execute('BEGIN IMMEDIATE')
        try:
            yield
            self.db.execute('COMMIT')
        except BaseException:
            self.db.execute('ROLLBACK')
            raise

    def setting(self, key):
        row = self.db.execute('SELECT value FROM settings WHERE key=?', (key,)).fetchone()
        return row['value'] if row else '0'

    def set_setting(self, key, value):
        self.db.execute('INSERT OR REPLACE INTO settings VALUES (?, ?)', (key, value))

    def history(self):
        rows = self.db.execute('''
            SELECT id,kind,mime,title,size,pinned,created,
                   CASE WHEN kind='text' THEN substr(payload,1,64000) ELSE NULL END AS preview
            FROM entries ORDER BY pinned DESC, created DESC, id
        ''').fetchall()
        entries = []
        for row in rows:
            item = {key: row[key] for key in ('id', 'kind', 'mime', 'title', 'size', 'created')}
            item['pinned'] = bool(row['pinned'])
            item['text'] = (row['preview'] or b'').decode('utf-8', errors='replace')[:PREVIEW_CHARACTERS]
            item['thumbnail'] = self.thumbnail_path(row['id']).as_uri() if row['kind'] == 'image' else ''
            entries.append(item)
        return {'entries': entries, 'paused': self.setting('paused') == '1'}

    def thumbnail_path(self, identifier):
        return self.thumbnails / (identifier + '.png')

    def store(self, kind, payload, *, importing=False):
        if not payload or len(payload) > MAX_ENTRY_BYTES:
            return {'ok': True, 'stored': False}
        identifier = entry_id(kind, payload)
        with self.write():
            if not importing and self.setting('paused') == '1':
                return {'ok': True, 'stored': False}
            existing = self.db.execute('SELECT id FROM entries WHERE id=?', (identifier,)).fetchone()
            if existing:
                if not importing:
                    self.db.execute('UPDATE entries SET created=? WHERE id=?', (time.time(), identifier))
                return {'ok': True, 'stored': True, 'id': identifier}
            if kind == 'image':
                mime, title, thumbnail = image_preview(payload)
                self.thumbnail_path(identifier).write_bytes(thumbnail)
            else:
                mime = 'text/plain;charset=utf-8'
                title = ' '.join(payload[:4096].decode('utf-8', errors='replace').split())[:100] or 'Text'
            self.db.execute('''INSERT INTO entries(id,kind,payload,mime,title,size,created)
                               VALUES (?, ?, ?, ?, ?, ?, ?)''',
                            (identifier, kind, payload, mime, title, len(payload), time.time()))
            self.prune()
        return {'ok': True, 'stored': True, 'id': identifier}

    def remove(self, identifiers):
        for identifier in identifiers:
            self.db.execute('DELETE FROM entries WHERE id=?', (identifier,))
            self.thumbnail_path(identifier).unlink(missing_ok=True)

    def prune(self):
        rows = self.db.execute('SELECT id,size,pinned FROM entries ORDER BY created DESC, id').fetchall()
        total = sum(row['size'] for row in rows)
        unpinned = sum(not row['pinned'] for row in rows)
        remove = []
        for row in reversed(rows):
            if unpinned <= MAX_UNPINNED and total <= MAX_HISTORY_BYTES:
                break
            if not row['pinned']:
                remove.append(row['id'])
                total -= row['size']
                unpinned -= 1
        self.remove(remove)

    def copy(self, identifier):
        row = self.db.execute('SELECT payload,mime FROM entries WHERE id=?', (identifier,)).fetchone()
        if not row:
            raise ValueError('entry unavailable')
        subprocess.run(['wl-copy', '--type', row['mime']], input=row['payload'], check=True,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=10)
        with self.write():
            self.db.execute('UPDATE entries SET created=? WHERE id=?', (time.time(), identifier))
        return {'ok': True}

    def pin(self, identifier):
        with self.write():
            changed = self.db.execute('UPDATE entries SET pinned=1-pinned WHERE id=?', (identifier,))
            if not changed.rowcount:
                raise ValueError('entry unavailable')
            pinned = bool(self.db.execute('SELECT pinned FROM entries WHERE id=?', (identifier,)).fetchone()[0])
            self.prune()
        return {'ok': True, 'pinned': pinned}

    def delete(self, identifier):
        # Only database-derived identifiers are ever used for filesystem access.
        with self.write():
            row = self.db.execute('SELECT id FROM entries WHERE id=?', (identifier,)).fetchone()
            if row:
                self.remove([row['id']])
        return {'ok': True}

    def clear(self):
        with self.write():
            self.remove([row['id'] for row in self.db.execute('SELECT id FROM entries WHERE pinned=0')])
        return {'ok': True}

    def pause(self):
        with self.write():
            paused = self.setting('paused') != '1'
            self.set_setting('paused', '1' if paused else '0')
        return {'ok': True, 'paused': paused}

    def import_cliphist(self):
        # Serialize cliphist imports without holding the database lock while it runs.
        # A process exit releases flock, so a failed import can retry next startup.
        with (self.path.parent / 'clipboard-import.lock').open('a') as lock:
            try:
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError:
                return {'ok': True, 'imported': 0}
            return self.import_legacy_entries()

    def import_legacy_entries(self):
        if self.setting('cliphist-imported') == '1':
            return {'ok': True, 'imported': 0}
        if not legacy_database_path().is_file():
            with self.write():
                self.set_setting('cliphist-imported', '1')
            return {'ok': True, 'imported': 0}
        listing = cliphist_output(['list'], limit=1024 * 1024)
        # cliphist lists newest first. Import in reverse to retain its recency order.
        lines = [line for line in listing.splitlines() if re.match(rb'^\d+\t', line)][:MAX_UNPINNED]
        imported = 0
        for line in reversed(lines):
            try:
                payload = cliphist_output(['decode'], input=line + b'\n', limit=MAX_ENTRY_BYTES)
                if not payload:
                    continue
                # Cliphist's binary marker is presentation only. Decode to verify images;
                # other binary formats have no supported paste representation here.
                binary = bool(re.match(rb'^\d+\t\[\[ binary data ', line))
                kind = 'image' if binary else 'text'
                result = self.store(kind, payload, importing=True)
                imported += int(result['stored'])
            except (ValueError, OSError, subprocess.SubprocessError):
                continue
        with self.write():
            self.set_setting('cliphist-imported', '1')
        return {'ok': True, 'imported': imported}


def cliphist_output(arguments, *, input=None, limit):
    # Anonymous private temporary output keeps oversized cliphist entries out of RAM.
    with tempfile.TemporaryFile() as output:
        subprocess.run(['cliphist', *arguments], input=input, stdout=output,
                       stderr=subprocess.DEVNULL, timeout=20, check=True)
        output.seek(0)
        payload = output.read(limit + 1)
    if len(payload) > limit:
        raise ValueError('legacy entry too large')
    return payload


class JsonArgumentParser(argparse.ArgumentParser):
    def error(self, message):
        raise ValueError('invalid command')


def main(argv=None):
    store = None
    try:
        parser = JsonArgumentParser(description=__doc__)
        commands = parser.add_subparsers(dest='command', required=True)
        commands.add_parser('list')
        collector = commands.add_parser('store')
        collector.add_argument('--kind', choices=('text', 'image'), required=True)
        for name in ('copy', 'pin', 'delete'):
            commands.add_parser(name).add_argument('id')
        for name in ('clear', 'pause', 'import-cliphist'):
            commands.add_parser(name)
        args = parser.parse_args(argv)
        if args.command == 'store' and os.environ.get('CLIPBOARD_STATE') in ('sensitive', 'nil'):
            result = {'ok': True, 'stored': False}
        else:
            store = ClipboardStore(database_path())
            if args.command == 'list':
                result = store.history()
            elif args.command == 'store':
                result = store.store(args.kind, sys.stdin.buffer.read(MAX_ENTRY_BYTES + 1))
            elif args.command in ('copy', 'pin', 'delete'):
                result = getattr(store, args.command)(args.id)
            else:
                result = getattr(store, args.command.replace('-', '_'))()
        print(json.dumps(result, ensure_ascii=True, separators=(',', ':')))
        return 0
    except Exception:
        print(json.dumps({'ok': False, 'error': 'Clipboard command failed'}))
        return 1
    finally:
        if store:
            store.close()


if __name__ == '__main__':
    sys.exit(main())
