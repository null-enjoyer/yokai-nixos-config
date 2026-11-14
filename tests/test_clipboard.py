"""Clipboard persistence checks. No test reads or modifies the live clipboard."""
import importlib.util
from concurrent.futures import ThreadPoolExecutor
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

SCRIPTS = Path(__file__).resolve().parents[1] / 'config/yokai/scripts'
if len(sys.argv) > 2 and sys.argv[1] == '--scripts':
    SCRIPTS = Path(sys.argv[2])
    del sys.argv[1:3]
spec = importlib.util.spec_from_file_location('yokai_clipboard', SCRIPTS / 'clipboard.py')
clipboard = importlib.util.module_from_spec(spec)
spec.loader.exec_module(clipboard)


class ClipboardChecks(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix='yokai-clipboard-check-')
        self.root = Path(self.directory.name)
        self.legacy = self.root / 'legacy-db'
        self.legacy.touch()
        self.environment = patch.dict(os.environ, {'CLIPHIST_DB_PATH': str(self.legacy)})
        self.environment.start()
        self.previous_umask = os.umask(0o077)
        self.store = clipboard.ClipboardStore(self.root / 'yokai/clipboard.sqlite3')

    def tearDown(self):
        self.store.close()
        self.environment.stop()
        self.directory.cleanup()
        os.umask(self.previous_umask)

    def add(self, payload=b'example', kind='text'):
        return self.store.store(kind, payload)['id']

    def test_text_round_trip_preserves_bytes_and_trailing_newlines(self):
        payload = '  пример\ttext\n\n'.encode()
        identifier = self.add(payload)
        with patch.object(clipboard.subprocess, 'run') as run:
            self.assertEqual(self.store.copy(identifier), {'ok': True})
        self.assertEqual(run.call_args.args[0], ['wl-copy', '--type', 'text/plain;charset=utf-8'])
        self.assertEqual(run.call_args.kwargs['input'], payload)
        row = self.store.history()['entries'][0]
        self.assertEqual(row['text'], payload.decode())
        self.assertEqual(row['title'], 'пример text')
        self.assertEqual(row['size'], len(payload))
        self.assertEqual(self.add(b'text'), clipboard.entry_id('text', b'text'))
        self.assertNotEqual(self.add(b'text\n'), clipboard.entry_id('text', b'text'))

    def test_display_preview_is_bounded_but_copy_is_lossless(self):
        payload = ('Я' * 20000 + '\n').encode()
        identifier = self.add(payload)
        self.assertEqual(len(self.store.history()['entries'][0]['text']), 16000)
        with patch.object(clipboard.subprocess, 'run') as run:
            self.store.copy(identifier)
        self.assertEqual(run.call_args.kwargs['input'], payload)

    def test_duplicate_retains_pin_and_moves_to_recent(self):
        with patch.object(clipboard.time, 'time', return_value=10):
            first = self.add(b'first')
        self.store.pin(first)
        with patch.object(clipboard.time, 'time', return_value=20):
            second = self.add(b'second')
        self.assertEqual(self.store.history()['entries'][0]['id'], first)
        self.store.pin(first)
        self.assertEqual(self.store.history()['entries'][0]['id'], second)
        self.store.pin(first)
        with patch.object(clipboard.time, 'time', return_value=30):
            self.assertEqual(self.add(b'first'), first)
        entries = self.store.history()['entries']
        self.assertEqual(len(entries), 2)
        self.assertTrue(entries[0]['pinned'])
        self.assertEqual(entries[0]['created'], 30)

    def test_retention_count_and_size_preserve_pins(self):
        pinned = self.add(b'pinned')
        self.store.pin(pinned)
        with patch.object(clipboard, 'MAX_UNPINNED', 2):
            old = self.add(b'old')
            self.add(b'middle')
            self.add(b'newest')
        ids = {row['id'] for row in self.store.history()['entries']}
        self.assertNotIn(old, ids)
        self.assertIn(pinned, ids)
        with patch.object(clipboard, 'MAX_HISTORY_BYTES', 8):
            newest = self.add(b'zz')
        self.assertEqual({row['id'] for row in self.store.history()['entries']}, {pinned, newest})
        with patch.object(clipboard, 'MAX_ENTRY_BYTES', 2):
            self.assertFalse(self.store.store('text', b'too big')['stored'])

    def test_pause_is_persistent_and_clear_keeps_pins(self):
        pinned = self.add(b'pinned')
        self.store.pin(pinned)
        self.add(b'temporary')
        self.assertTrue(self.store.pause()['paused'])
        self.assertFalse(self.store.store('text', b'ignored')['stored'])
        other = clipboard.ClipboardStore(self.store.path)
        try:
            self.assertTrue(other.history()['paused'])
            self.assertFalse(other.store('text', b'also ignored')['stored'])
        finally:
            other.close()
        self.store.clear()
        self.assertEqual([row['id'] for row in self.store.history()['entries']], [pinned])
        self.assertFalse(self.store.pause()['paused'])
        self.store.delete(pinned)
        self.assertEqual(self.store.history()['entries'], [])

    def test_sensitive_and_nil_never_open_database(self):
        for state in ('sensitive', 'nil'):
            with self.subTest(state=state), patch.dict(os.environ, {'CLIPBOARD_STATE': state}), \
                    patch.object(clipboard, 'ClipboardStore') as constructor, \
                    patch('sys.stdout', new_callable=io.StringIO) as stdout:
                self.assertEqual(clipboard.main(['store', '--kind', 'text']), 0)
                constructor.assert_not_called()
                self.assertEqual(json.loads(stdout.getvalue()), {'ok': True, 'stored': False})

    def test_image_validation_thumbnail_and_copy_mime(self):
        from PIL import Image
        output = io.BytesIO()
        Image.new('RGB', (640, 480), 'red').save(output, 'JPEG')
        payload = output.getvalue()
        identifier = self.add(payload, 'image')
        row = self.store.history()['entries'][0]
        self.assertEqual(row['mime'], 'image/jpeg')
        self.assertEqual(row['text'], '')
        self.assertEqual(row['thumbnail'], self.store.thumbnail_path(identifier).as_uri())
        with Image.open(self.store.thumbnail_path(identifier)) as thumbnail:
            self.assertEqual(thumbnail.format, 'PNG')
            self.assertLessEqual(thumbnail.width, 320)
            self.assertLessEqual(thumbnail.height, 200)
        with patch.object(clipboard.subprocess, 'run') as run:
            self.store.copy(identifier)
        self.assertEqual(run.call_args.args[0][-1], 'image/jpeg')
        self.assertEqual(run.call_args.kwargs['input'], payload)
        with self.assertRaises(OSError):
            self.store.store('image', b'not an image')
        self.store.delete(identifier)
        self.assertFalse(self.store.thumbnail_path(identifier).exists())

    def test_pruning_removes_thumbnail(self):
        from PIL import Image
        output = io.BytesIO()
        Image.new('RGB', (1, 1)).save(output, 'PNG')
        identifier = self.add(output.getvalue(), 'image')
        with patch.object(clipboard, 'MAX_UNPINNED', 1):
            self.add(b'replacement')
        self.assertFalse(self.store.thumbnail_path(identifier).exists())

    def test_migration_is_bounded_idempotent_and_preserves_newer_duplicate(self):
        existing = self.add(b'existing\n')
        created = self.store.history()['entries'][0]['created']
        decoded = {b'2\texisting\n': b'existing\n', b'1\tolder\n': b'older\n'}

        def legacy(arguments, *, input=None, limit):
            if arguments == ['list']:
                return b'3\tnewest\n2\texisting\n1\tolder\n'
            return decoded[input]

        with patch.object(clipboard, 'MAX_UNPINNED', 2), \
                patch.object(clipboard, 'cliphist_output', side_effect=legacy) as source:
            # Keep existing + newest; force bounded import without a real cliphist DB.
            decoded[b'3\tnewest\n'] = b'newest\n'
            self.assertEqual(self.store.import_cliphist()['imported'], 2)
            self.assertEqual(source.call_count, 3)
            self.assertEqual(self.store.import_cliphist()['imported'], 0)
            self.assertEqual(source.call_count, 3)
        rows = self.store.history()['entries']
        self.assertEqual(len(rows), 2)
        self.assertEqual(next(row['created'] for row in rows if row['id'] == existing), created)

    def test_migration_subprocess_never_prints_payload(self):
        def execute(command, **kwargs):
            self.assertEqual(command, ['cliphist', 'decode'])
            self.assertIs(kwargs['stderr'], subprocess.DEVNULL)
            kwargs['stdout'].write(b'private payload\n')
        with patch.object(clipboard.subprocess, 'run', side_effect=execute):
            result = clipboard.cliphist_output(['decode'], input=b'42\n', limit=100)
            self.assertEqual(result, b'private payload\n')
            with self.assertRaises(ValueError):
                clipboard.cliphist_output(['decode'], input=b'42\n', limit=2)

    def test_migration_lock_and_failed_import_retry(self):
        lock_path = self.store.path.parent / 'clipboard-import.lock'
        with lock_path.open('a') as lock, patch.object(clipboard, 'cliphist_output') as source:
            clipboard.fcntl.flock(lock, clipboard.fcntl.LOCK_EX | clipboard.fcntl.LOCK_NB)
            self.assertEqual(self.store.import_cliphist(), {'ok': True, 'imported': 0})
            source.assert_not_called()
        with patch.object(clipboard, 'cliphist_output', side_effect=OSError('not available')):
            with self.assertRaises(OSError):
                self.store.import_cliphist()
        self.assertEqual(self.store.setting('cliphist-imported'), '0')
        with patch.object(clipboard, 'cliphist_output', return_value=b''):
            self.assertEqual(self.store.import_cliphist(), {'ok': True, 'imported': 0})
        self.assertEqual(self.store.setting('cliphist-imported'), '1')

    def test_migration_on_first_install_finishes_without_legacy_database(self):
        self.legacy.unlink()
        with patch.object(clipboard, 'cliphist_output') as source:
            self.assertEqual(self.store.import_cliphist(), {'ok': True, 'imported': 0})
            source.assert_not_called()
        self.assertEqual(self.store.setting('cliphist-imported'), '1')
        self.assertEqual(clipboard.legacy_database_path(), self.legacy)
        with patch.dict(os.environ, {'CLIPHIST_DB_PATH': '', 'XDG_CACHE_HOME': str(self.root)}):
            self.assertEqual(clipboard.legacy_database_path(), self.root / 'cliphist/db')

    def test_database_permissions_and_concurrent_writers(self):
        self.assertEqual(self.store.path.stat().st_mode & 0o777, 0o600)
        self.assertEqual(self.store.path.parent.stat().st_mode & 0o777, 0o700)
        other = clipboard.ClipboardStore(self.store.path)
        try:
            self.add(b'first collector')
            other.store('text', b'second collector')
            self.assertEqual(len(self.store.history()['entries']), 2)
            self.assertEqual(other.db.execute('PRAGMA journal_mode').fetchone()[0], 'wal')
        finally:
            other.close()

        def collect(prefix):
            writer = clipboard.ClipboardStore(self.store.path)
            try:
                for index in range(10):
                    writer.store('text', f'{prefix}-{index}'.encode())
            finally:
                writer.close()

        with ThreadPoolExecutor(max_workers=2) as workers:
            list(workers.map(collect, ('text', 'image-collector')))
        self.assertEqual(len(self.store.history()['entries']), 22)

    def test_cli_errors_are_json_without_private_arguments(self):
        with patch('sys.stdout', new_callable=io.StringIO) as stdout:
            self.assertEqual(clipboard.main(['copy', 'secret-id', 'invalid']), 1)
            self.assertEqual(json.loads(stdout.getvalue()),
                             {'ok': False, 'error': 'Clipboard command failed'})
            self.assertNotIn('secret-id', stdout.getvalue())
        with self.assertRaises(ValueError):
            self.store.copy('missing')
        self.store.delete('../../outside')


if __name__ == '__main__':
    unittest.main()
