"""Focused browser bridge checks using synthetic profiles and temporary state only."""
import argparse
import importlib.util
import io
import json
import os
from pathlib import Path
import select
import stat
import struct
import subprocess
import sys
import tempfile
import threading
import unittest
from unittest.mock import patch
from urllib.parse import urlsplit
import uuid

arguments = argparse.ArgumentParser(add_help=False, allow_abbrev=False)
arguments.add_argument('--script', type=Path,
                       default=Path(__file__).resolve().parents[1] / 'config/yokai/scripts/browser_bridge.py')
options, remaining = arguments.parse_known_args()
sys.argv = [sys.argv[0], *remaining]
SCRIPT = options.script.resolve()
spec = importlib.util.spec_from_file_location('browser_bridge', SCRIPT)
bridge = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bridge)


class BrowserChecks(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='yokai-browser-check-')
        self.root = Path(self.temporary.name)
        self.profiles = self.root / 'profiles'
        self.profiles.mkdir()
        for directory in ('Default', 'Profile 1'):
            (self.profiles / directory).mkdir()
        (self.profiles / 'Local State').write_text(json.dumps({'profile': {'info_cache': {
            'Default': {'name': 'Personal'}, 'Profile 1': {'name': 'Work'}, '../invalid': {'name': 'Invalid'}}}}))
        self.database = self.root / 'state/browser.sqlite3'
        self.socket = self.root / 'browser.sock'
        self.store = bridge.HistoryStore(self.database)
        self.server = bridge.BrowserServer(self.socket, self.store, self.profiles, '/test/brave')
        self.thread = threading.Thread(target=self.server.serve_forever, kwargs={'poll_interval': 0.02}, daemon=True)
        self.thread.start()
        self.clients = []
        self.source = str(uuid.uuid4())

    def tearDown(self):
        for client, reader in self.clients:
            reader.close()
            client.close()
        self.server.shutdown()
        self.server.server_close()
        with self.store.lock:
            self.store.close()
        self.thread.join(timeout=2)
        self.temporary.cleanup()

    def client(self):
        client = bridge.connect(self.socket, 'native')
        reader = client.makefile('rb')
        self.clients.append((client, reader))
        return client, reader

    def exchange(self, port, kind, **data):
        client, reader = port
        request = str(uuid.uuid4())
        client.sendall(bridge.encoded_message({'type': kind, 'requestId': request, **data}) + b'\n')
        response = json.loads(reader.readline())
        self.assertEqual(response['type'], kind)
        self.assertEqual(response['requestId'], request)
        return response

    def begin(self, port, snapshot='one', directory='Default', source=None):
        return self.exchange(port, 'begin', sourceId=source or self.source,
                             profileDirectory=directory, snapshotId=snapshot)

    def chunk(self, port, urls, snapshot='one', source=None):
        return self.exchange(port, 'chunk', sourceId=source or self.source, snapshotId=snapshot,
                             items=[{'url': url, 'title': 'Shop', 'lastVisitTime': 100, 'visitCount': 2} for url in urls])

    def commit(self, port, snapshot='one', source=None):
        return self.exchange(port, 'commit', sourceId=source or self.source, snapshotId=snapshot)

    def test_native_frame_limits_partial_reads_and_clean_eof(self):
        message = {'type': 'profiles', 'requestId': 'α'}
        wire = io.BytesIO()
        bridge.write_frame(wire, message)
        self.assertEqual(bridge.read_frame(io.BytesIO(wire.getvalue())), message)
        self.assertIsNone(bridge.read_frame(io.BytesIO()))
        for malformed in (b'a', struct.pack('<I', bridge.MAX_MESSAGE + 1), struct.pack('<I', 5) + b'{}'):
            with self.assertRaises(ValueError):
                bridge.read_frame(io.BytesIO(malformed))
        with self.assertRaises(ValueError):
            bridge.write_frame(io.BytesIO(), {'data': 'x' * bridge.MAX_MESSAGE})

        class PartialReader(io.BytesIO):
            def read(self, length=-1):
                return super().read(min(length, 2))
        self.assertEqual(bridge.read_frame(PartialReader(wire.getvalue())), message)

    def test_real_native_stdio_frames_multiple_requests_and_caller_validation(self):
        origin = 'chrome-extension://test-id/'
        env = {**os.environ, 'YOKAI_BRAVE_EXTENSION_ID': 'test-id', 'PYTHONDONTWRITEBYTECODE': '1'}
        process = subprocess.Popen([sys.executable, str(SCRIPT), '--socket', str(self.socket), 'native', origin],
                                   stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=env)
        try:
            requests = [
                {'type': 'profiles', 'requestId': 'profiles'},
                {'type': 'begin', 'requestId': 'begin', 'sourceId': self.source,
                 'profileDirectory': 'Default', 'snapshotId': 'pipeline'},
                {'type': 'chunk', 'requestId': 'chunk', 'sourceId': self.source, 'snapshotId': 'pipeline',
                 'items': [{'url': 'https://ozon.ru/', 'title': 'Example shop'}]},
                {'type': 'commit', 'requestId': 'commit', 'sourceId': self.source, 'snapshotId': 'pipeline'},
                {'type': 'open', 'requestId': 'forbidden', 'sourceId': self.source, 'url': 'https://ozon.ru/'},
            ]
            for message in requests:
                bridge.write_frame(process.stdin, message)
            answers = {}
            for _ in requests:
                self.assertTrue(select.select([process.stdout], [], [], 3)[0], 'Native host response timed out')
                response = bridge.read_frame(process.stdout.raw)
                answers[response['requestId']] = response
            self.assertTrue(answers['commit']['ok'])
            self.assertFalse(answers['forbidden']['ok'])
            process.stdin.close()
            process.wait(timeout=3)
            self.assertEqual(process.returncode, 0)
            self.assertEqual(process.stderr.read(), b'', 'Native protocol must keep diagnostics out of stdout')
            self.assertEqual(self.store.search(['ozon'])['results'][0]['title'], 'Example shop')
        finally:
            if process.poll() is None:
                process.kill()
                process.wait()
            process.stdout.close()
            process.stderr.close()
        rejected = subprocess.run([sys.executable, str(SCRIPT), '--socket', str(self.socket),
                                  'native', 'chrome-extension://wrong-id/'],
                                  capture_output=True, timeout=3, env=env)
        self.assertEqual(rejected.returncode, 1)
        self.assertEqual(rejected.stdout, b'')

    def test_atomic_snapshots_stale_generation_disconnect_and_persistence(self):
        port = self.client()
        self.assertTrue(self.begin(port)['ok'])
        self.assertTrue(self.chunk(port, ['https://ozon.ru/'])['ok'])
        self.assertFalse(self.store.search(['ozon'])['ready'])
        self.assertTrue(self.commit(port)['ok'])
        original = self.store.search(['ozon'])['results'][0]['id']
        self.assertTrue(self.begin(port, snapshot='two')['ok'])
        self.chunk(port, ['https://example.com/'], snapshot='two')
        self.assertEqual(self.store.search(['ozon'])['results'][0]['id'], original)
        self.assertFalse(self.commit(port, snapshot='one')['ok'])
        newer = self.client()
        self.begin(newer, snapshot='three')
        self.assertFalse(self.commit(port, snapshot='two')['ok'])
        self.chunk(newer, ['https://ozon.ru/new'], snapshot='three')
        self.commit(newer, snapshot='three')
        self.assertEqual(self.store.search(['ozon'])['results'][0]['url'], 'https://ozon.ru/new')
        self.begin(newer, snapshot='unfinished')
        self.chunk(newer, ['https://example.com/'], snapshot='unfinished')
        restored = bridge.HistoryStore(self.database)
        try:
            self.assertEqual(restored.search(['ozon'])['results'][0]['url'], 'https://ozon.ru/new')
            self.assertEqual(restored.search(['example'])['results'], [])
        finally:
            restored.close()
        self.assertEqual(stat.S_IMODE(self.database.stat().st_mode), 0o600)
        self.assertEqual(stat.S_IMODE(self.socket.stat().st_mode), 0o600)

    def test_normalized_snapshots_merge_across_chunks_and_keep_latest_title(self):
        port = self.client()
        self.begin(port)
        for raw in [
            {'url': 'https://example.org/a/b/c/new?privatequery=one#part', 'title': 'Newest', 'lastVisitTime': 200, 'visitCount': 2},
            {'url': 'https://example.org/a/b/c/old?privatequery=two', 'title': 'Older', 'lastVisitTime': 100, 'visitCount': 9},
        ]:
            self.assertTrue(self.exchange(port, 'chunk', sourceId=self.source, snapshotId='one', items=[raw])['ok'])
        self.commit(port)
        self.assertEqual(self.store.items[self.source], (('https://example.org/a/b/c', 'Newest', 200, 9),))
        self.assertEqual(self.store.search(['privatequery'])['results'], [])
        self.assertEqual(self.store.source_for_open(self.source, 'https://example.org/a/b/c')['profileDirectory'], 'Default')

    def test_existing_cache_is_normalized_when_opened(self):
        database = self.root / 'old-index.sqlite3'
        store = bridge.HistoryStore(database)
        with store.connection:
            store.connection.execute('INSERT INTO sources VALUES (?,?,?,?)', (self.source, 'Default', 'Personal', 1))
            store.connection.executemany('INSERT INTO history VALUES (?,?,?,?,?)', [
                (self.source, 'https://example.org/a/b/c/new?privatequery=x', 'Newest', 200, 2),
                (self.source, 'https://example.org/a/b/c/old#part', 'Older', 100, 9),
            ])
        store.close()
        restored = bridge.HistoryStore(database)
        try:
            self.assertEqual(restored.items[self.source], (('https://example.org/a/b/c', 'Newest', 200, 9),))
            rows = restored.connection.execute('SELECT url FROM history').fetchall()
            self.assertEqual(rows, [('https://example.org/a/b/c',)])
            self.assertEqual(restored.sources[self.source]['updated'], 1)
        finally:
            restored.close()

    def test_search_wrong_layout_blank_dedup_and_unsafe_urls(self):
        port = self.client()
        self.begin(port)
        urls = ['https://ozon.ru/', 'https://ozon.ru/#fragment'] + [f'https://ozon.ru/product/{i}' for i in range(8)]
        urls += ['file:///tmp/private', 'javascript:alert(1)', 'https://user:secret@example.com/', 'https://example.com/\n']
        self.chunk(port, urls)
        self.commit(port)
        found = self.store.search(['щящтюкг', 'ozon.ru'])
        self.assertEqual(len(found['results']), 3)
        self.assertTrue(all(not row['originalMatch'] and row['sourceId'] == self.source for row in found['results']))
        self.assertEqual(self.store.search([''])['results'], [])
        self.assertTrue(self.store.search([''])['ready'])
        self.assertAlmostEqual(bridge.fuzzy_score('ff', 'firefox'), 38.925)
        for url in urls[-4:]:
            with self.assertRaises(ValueError):
                self.server.open_url(self.source, url)
        self.assertEqual(self.exchange(port, 'open', sourceId=self.source, url='https://ozon.ru/')['ok'], False)

    def test_site_search_prioritizes_home_over_recent_products(self):
        home = 'https://www.shop.example/'
        urls = [(home, 'Shop home', 100, 26),
                (home + '?utm_source=recent', 'Shop home', 3000, 5)]
        urls += [(home + f'product/{index}', f'Laptop {index}', 2000 + index, 2)
                 for index in range(8)]
        self.store.commit(self.source, 'Default', 'Personal', {item[0]: item for item in urls})
        for query in ('shop', 'shop.example', 'https://www.shop.example/'):
            found = self.store.search([query])['results']
            self.assertEqual(found[0]['url'], home)
            self.assertEqual(sum(urlsplit(row['url']).path in ('', '/') for row in found), 1)
        products = self.store.search(['laptop'])['results']
        self.assertTrue(products)
        self.assertTrue(all('/product/' in row['url'] for row in products))

    def test_field_quality_boundaries_and_fuzzy_fallback(self):
        cases = [('Тест', ' Тест ', 4), ('тест', 'Привет,Тест!', 3),
                 ('тест', 'Привет Тестовый', 2), ('тест', 'СуперТест', 1),
                 ('тест', 'Т е с т', 0), ('тест', 'Сайт', -1), ('', 'Anything', -1)]
        for query, text, expected in cases:
            with self.subTest(query=query, text=text):
                self.assertEqual(bridge.field_match(query, text)[0], expected)
        for boundary in '.,_/\\-:;()[]{}—–!?"\'@ \t\n':
            self.assertEqual(bridge.field_match('abc', f'x{boundary}abc{boundary}y')[0], 3)

    def test_site_name_alias_keeps_home_before_generic_exact_product_titles(self):
        home = 'https://www.ozon.ru/'
        items = [(home, 'Ozon — интернет-магазин товаров и услуг', 10, 1)]
        items += [(home + f'product/{index}', 'OZON', 1000 + index, 100) for index in range(8)]
        items += [('https://finance.ozon.ru/cards', 'OZON', 2000, 100)]
        self.store.commit(self.source, 'Default', 'Personal', {item[0]: item for item in items})
        for query in ('ozon', 'OZON', 'ozon.ru', 'https://www.ozon.ru/'):
            rows = self.store.search([query])['results']
            self.assertEqual(rows[0]['url'], home)
            self.assertEqual(rows[0]['matchQuality'], 4)
            self.assertEqual(sum(urlsplit(row['url']).hostname == 'www.ozon.ru' for row in rows), 3)

    def test_only_exact_leading_hostname_label_is_a_site_alias(self):
        self.assertEqual(bridge.browser_match('example', 'https://example.co.uk/', 'Store')[0], 4)
        self.assertEqual(bridge.browser_match('example.co.uk', 'https://example.co.uk/', 'Store')[0], 4)
        for query, url, quality in [('co', 'https://example.co.uk/', 3),
                                    ('example', 'https://store.example.co.uk/', 3),
                                    ('exam', 'https://example.co.uk/', 2),
                                    ('exple', 'https://example.co.uk/', 0),
                                    ('Ntcn', 'https://n.t.c.n.site.test/', 0)]:
            self.assertEqual(bridge.browser_match(query, url, 'Store')[0], quality)

    def test_field_quality_prevents_domain_bonus_from_inflating_exact_title(self):
        url = 'https://a.b.c.example/'
        self.store.commit(self.source, 'Default', 'Personal', {url: (url, 'abc', 10, 1)})
        row = self.store.search(['abc'])['results'][0]
        self.assertEqual(row['matchQuality'], 4)
        self.assertEqual(row['score'], round(bridge.field_match('abc', 'abc')[1], 4))
        self.assertTrue(row['originalMatch'])

    def test_primary_variant_wins_equal_quality_even_with_smaller_numeric_score(self):
        url = 'https://store.shop.longer.example/'
        self.store.commit(self.source, 'Default', 'Personal', {url: (url, 'Store', 10, 1)})
        primary = bridge.browser_match('shop', url, 'Store')
        converted = bridge.browser_match('longer', url, 'Store')
        self.assertEqual(primary[0], converted[0])
        self.assertGreater(converted[1], primary[1])
        row = self.store.search(['shop', 'longer'])['results'][0]
        self.assertTrue(row['originalMatch'])
        self.assertEqual(row['score'], round(primary[1], 4))

    def test_exact_original_and_converted_fields_sort_before_weaker_matches(self):
        items = [('https://converted.example/', 'Ntcn', 100, 10),
                 ('https://direct.example/', 'Тест', 1, 1),
                 ('https://weak.example/', 'Т е с т', 1000, 100)]
        self.store.commit(self.source, 'Default', 'Personal', {item[0]: item for item in items})
        rows = self.store.search(['Тест', 'Ntcn'])['results']
        self.assertEqual([row['title'] for row in rows], ['Тест', 'Ntcn', 'Т е с т'])
        self.assertEqual([row['matchQuality'] for row in rows], [4, 4, 0])
        self.assertEqual([row['originalMatch'] for row in rows], [True, False, True])

    def test_snapshot_writes_only_changed_added_and_removed_rows(self):
        items = {f'https://example.com/{index}':
                 (f'https://example.com/{index}', f'Page {index}', 100, 2) for index in range(1000)}
        self.store.commit(self.source, 'Default', 'Personal', items)
        changes = self.store.connection.total_changes
        self.store.commit(self.source, 'Default', 'Personal', dict(items))
        self.assertEqual(self.store.connection.total_changes - changes, 1, 'Only source metadata should change')

        changed_url = 'https://example.com/7'
        items[changed_url] = (changed_url, 'Updated page', 200, 3)
        changes = self.store.connection.total_changes
        self.store.commit(self.source, 'Default', 'Personal', items)
        self.assertEqual(self.store.connection.total_changes - changes, 2, 'Update one history row and metadata')

        del items['https://example.com/8']
        added = 'https://example.com/new'
        items[added] = (added, 'New page', 300, 1)
        changes = self.store.connection.total_changes
        self.store.commit(self.source, 'Default', 'Personal', items)
        self.assertEqual(self.store.connection.total_changes - changes, 3, 'Delete one, add one, update metadata')
        self.assertEqual(dict((item[0], item) for item in self.store.items[self.source]), items)
        restored = bridge.HistoryStore(self.database)
        try:
            self.assertEqual(dict((item[0], item) for item in restored.items[self.source]), items)
        finally:
            restored.close()

    def test_reinstalled_source_replaces_same_profile_and_retires_old_port(self):
        old = self.client()
        self.begin(old)
        self.chunk(old, ['https://ozon.ru/old'])
        self.commit(old)
        self.begin(old, snapshot='unfinished')
        work_source = str(uuid.uuid4())
        work = self.client()
        self.begin(work, directory='Profile 1', source=work_source)
        self.chunk(work, ['https://ozon.ru/work'], source=work_source)
        self.commit(work, source=work_source)
        replacement = str(uuid.uuid4())
        new = self.client()
        self.begin(new, source=replacement)
        self.chunk(new, ['https://ozon.ru/new'], source=replacement)
        self.commit(new, source=replacement)
        found = self.store.search(['ozon'])['results']
        self.assertEqual({row['sourceId'] for row in found}, {replacement, work_source})
        self.assertEqual({row['profileName'] for row in found}, {'Personal', 'Work'})
        self.assertFalse(self.commit(old, snapshot='unfinished')['ok'])
        self.assertFalse(self.begin(old, snapshot='retry')['ok'])
        self.assertFalse(self.begin(self.client(), snapshot='retry')['ok'])
        self.assertNotIn(self.source, self.server.active)
        with self.assertRaises(ValueError):
            self.server.open_url(self.source, 'https://ozon.ru/old')
        restored = bridge.HistoryStore(self.database)
        try:
            self.assertEqual(set(restored.sources), {replacement, work_source})
            self.assertEqual({row['url'] for row in restored.search(['ozon'])['results']},
                             {'https://ozon.ru/new', 'https://ozon.ru/work'})
            self.assertEqual(restored.connection.execute(
                'SELECT COUNT(*) FROM history WHERE source_id=?', (self.source,)).fetchone()[0], 0)
        finally:
            restored.close()

    def test_correct_profile_open_delivery_and_current_session_offline_launch(self):
        port = self.client()
        self.begin(port, directory='Profile 1')
        self.chunk(port, ['https://ozon.ru/'])
        self.commit(port)
        answer = {}
        thread = threading.Thread(target=lambda: answer.update(bridge.request(
            self.socket, {'type': 'open', 'sourceId': self.source, 'url': 'https://ozon.ru/'})))
        thread.start()
        opened = json.loads(port[1].readline())
        self.assertEqual(opened['type'], 'open')
        self.assertEqual(opened['url'], 'https://ozon.ru/')
        port[0].sendall(bridge.encoded_message({'type': 'opened', 'requestId': opened['requestId'], 'ok': True}) + b'\n')
        self.assertTrue(json.loads(port[1].readline())['ok'])
        thread.join(timeout=3)
        self.assertEqual(answer, {'ok': True, 'method': 'extension'})
        # Changing options mid-snapshot must not redirect old results to another profile.
        self.begin(port, snapshot='changed', directory='Default')
        with patch.object(bridge.shutil, 'which', return_value='/test/systemd-run'), patch.object(bridge.subprocess, 'run') as launch:
            self.assertEqual(self.server.open_url(self.source, 'https://ozon.ru/')['method'], 'browser')
            self.assertEqual(launch.call_args.args[0], ['/test/systemd-run', '--user', '--collect',
                             '--property=Type=exec', '--slice=app.slice', '--', '/test/brave',
                             '--profile-directory=Profile 1', 'https://ozon.ru/'])

    def test_profile_validation_empty_snapshot_and_missing_service(self):
        port = self.client()
        choices = self.exchange(port, 'profiles')['profiles']
        self.assertEqual(choices, [{'directory': 'Default', 'name': 'Personal'}, {'directory': 'Profile 1', 'name': 'Work'}])
        self.assertFalse(self.begin(port, directory='../invalid')['ok'])
        self.begin(port)
        self.commit(port)
        self.assertTrue(self.store.search(['ozon'])['ready'])
        self.assertEqual(self.store.search(['ozon'])['results'], [])
        missing = bridge.request(self.root / 'missing.sock', {'type': 'search', 'queries': ['ozon']})
        self.assertFalse(missing['ready'])
        self.assertIn('unavailable', missing['error'])


if __name__ == '__main__':
    unittest.main()
