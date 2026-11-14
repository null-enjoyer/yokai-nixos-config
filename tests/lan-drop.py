"""Exercise LAN uploads and shared-note conflicts in temporary storage."""
import http.client
import importlib.util
import io
import json
import os
import shutil
import subprocess
from pathlib import Path
import sys
import tempfile
import threading
import unittest

script = Path(sys.argv.pop(1))
spec = importlib.util.spec_from_file_location('lan_drop', script)
app = importlib.util.module_from_spec(spec)
spec.loader.exec_module(app)


class Transfers(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.storage = app.Storage(self.base / 'downloads', self.base / 'state')
        self.server = app.TransferServer(('127.0.0.1', 0), app.Handler)
        self.server.storage = self.storage
        self.server.qrencode = os.environ.get("QRENCODE", shutil.which("qrencode"))
        self.server.network = app.ipaddress.ip_network('192.0.2.0/24')
        self.server.hosts = {f'127.0.0.1:{self.server.server_port}'}
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.addCleanup(self.stop)

    def stop(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join()

    def request(self, method, path, body=None, **headers):
        connection = http.client.HTTPConnection('127.0.0.1', self.server.server_port, timeout=3)
        connection.request(method, path, body=body, headers=headers)
        response = connection.getresponse()
        data = response.read()
        connection.close()
        return response.status, data

    def test_upload_and_note_require_no_access_code(self):
        self.assertEqual(self.request('GET', '/')[0], 200)
        self.assertEqual(self.request('GET', '/api/note')[0], 200)
        self.assertEqual(self.request('GET', '/api/note', Origin='http://other.example')[0], 403)
        self.assertEqual(self.request('PUT', '/api/upload?name=blocked.txt', body=b'x')[0], 201)
        self.assertEqual((self.storage.downloads / 'blocked.txt').read_bytes(), b'x')

    def test_public_qr_points_to_page_without_token(self):
        code, data = self.request('GET', '/qr.svg')
        self.assertEqual(code, 200)
        self.assertIn(b'<svg', data)

    def test_cross_origin_note_write_rejected(self):
        body = json.dumps({'version': 0, 'text': 'blocked'}).encode()
        code, _ = self.request('PUT', '/api/note', body=body,
                               Origin='http://other.example')
        self.assertEqual(code, 403)
        self.assertEqual(self.storage.note['text'], '')

    def test_unrecognized_host_is_rejected(self):
        self.assertEqual(self.request('GET', '/api/note', Host='other.example')[0], 403)

    def test_only_configured_network_and_loopback_are_allowed(self):
        handler = object.__new__(app.Handler)
        handler.server = self.server
        handler.headers = {'Host': next(iter(self.server.hosts))}
        rejected = []
        handler.reply = lambda status, data: rejected.append(status)
        for address in ('192.0.2.42', '127.0.0.1'):
            handler.client_address = (address, 1234)
            self.assertTrue(handler.allowed())
        handler.client_address = ('198.51.100.42', 1234)
        self.assertFalse(handler.allowed())
        self.assertEqual(rejected, [403])

    def test_server_rejects_unsuitable_network_configuration(self):
        for address, network in [('0.0.0.0', '192.0.2.0/24'),
                                 ('192.0.2.10', '198.51.100.0/24'),
                                 ('::1', '192.0.2.0/24'),
                                 ('127.0.0.1', '::1/128')]:
            with self.subTest(address=address, network=network):
                result = subprocess.run([
                    sys.executable, str(script), '--bind', address,
                    '--network', network, '--downloads', str(self.storage.downloads),
                    '--state', str(self.storage.state)
                ], capture_output=True, timeout=3)
                self.assertEqual(result.returncode, 2)

    def test_uploads_preserve_existing_file(self):
        for expected in ['example.txt', 'example (1).txt']:
            code, data = self.request('PUT', '/api/upload?name=example.txt', body=b'file-content')
            self.assertEqual(code, 201)
            self.assertEqual(json.loads(data)['name'], expected)
            self.assertEqual((self.storage.downloads / expected).read_bytes(), b'file-content')
        self.assertEqual(self.request('GET', '/example.txt')[0], 404)

    def test_paths_and_interrupted_upload(self):
        self.assertEqual(self.request('PUT', '/api/upload?name=..%2Foutside', body=b'x')[0], 400)
        with self.assertRaises(ValueError):
            self.storage.upload('partial.txt', io.BytesIO(b'short'), 99)
        self.assertFalse(any(self.storage.downloads.iterdir()))

    def test_text_sync_conflict_and_persistence(self):
        body = json.dumps({'version': 0, 'text': 'shared text'}).encode()
        code, data = self.request('PUT', '/api/note', body=body)
        self.assertEqual(code, 200)
        self.assertEqual(json.loads(data), {'version': 1, 'text': 'shared text'})
        self.assertEqual(self.request('PUT', '/api/note', body=body)[0], 409)
        code, data = self.request('GET', '/api/note')
        self.assertEqual(json.loads(data)['text'], 'shared text')
        reopened = app.Storage(self.storage.downloads, self.storage.state)
        self.assertEqual(reopened.note, self.storage.note)


unittest.main()
