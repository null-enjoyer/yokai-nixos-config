"""LAN-only uploads and a versioned shared note."""
import argparse
import ipaddress
import json
import os
from pathlib import Path
import subprocess
import tempfile
import threading
from socketserver import TCPServer
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlsplit

MAX_FILE = 1024 ** 3
MAX_TEXT = 256 * 1024


class TransferServer(ThreadingHTTPServer):
    def server_bind(self):
        # Local transfer must start even when the system DNS resolver is offline.
        TCPServer.server_bind(self)
        self.server_name, self.server_port = self.server_address


class Storage:
    def __init__(self, downloads, state):
        self.downloads, self.state = Path(downloads), Path(state)
        self.downloads.mkdir(parents=True, exist_ok=True)
        self.state.mkdir(parents=True, exist_ok=True, mode=0o700)
        self.lock = threading.Lock()
        self.note = {'version': 0, 'text': ''}
        note_path = self.state / 'note.json'
        if note_path.exists():
            self.note = json.loads(note_path.read_text())

    def update_note(self, data):
        if not isinstance(data.get('text'), str) or len(data['text'].encode()) > MAX_TEXT:
            raise ValueError('Text is too large')
        with self.lock:
            if data.get('version') != self.note['version']:
                return False, dict(self.note)
            note = {'version': self.note['version'] + 1, 'text': data['text']}
            temporary = self.state / 'note.tmp'
            with temporary.open('w') as stream:
                json.dump(note, stream, ensure_ascii=False)
            temporary.chmod(0o600)
            temporary.replace(self.state / 'note.json')
            self.note = note
            return True, dict(note)

    def upload(self, name, stream, length):
        if not name or name in ('.', '..') or Path(name).name != name or '\\' in name or any(ord(c) < 32 for c in name) or len(name.encode()) > 220:
            raise ValueError('Invalid file name')
        if not 0 <= length <= MAX_FILE:
            raise ValueError('Maximum file size is 1 GiB')
        fd, temporary = tempfile.mkstemp(prefix='.lan-drop-', suffix='.part', dir=self.downloads)
        temporary = Path(temporary)
        try:
            with os.fdopen(fd, 'wb') as output:
                remaining = length
                while remaining:
                    block = stream.read(min(1024 * 1024, remaining))
                    if not block:
                        raise ValueError('Transfer interrupted')
                    output.write(block)
                    remaining -= len(block)
            original = Path(name)
            for index in range(1000):
                candidate = self.downloads / (name if index == 0 else f'{original.stem} ({index}){original.suffix}')
                try:
                    os.link(temporary, candidate)
                    return {'name': candidate.name, 'size': length}
                except FileExistsError:
                    continue
            raise ValueError('Too many files with this name')
        finally:
            temporary.unlink(missing_ok=True)


class Handler(BaseHTTPRequestHandler):
    def setup(self):
        super().setup()
        self.connection.settimeout(60)

    def log_message(self, *_args):
        pass

    def reply(self, code, data, mime='application/json; charset=utf-8'):
        body = data if isinstance(data, bytes) else json.dumps(data, ensure_ascii=False).encode()
        self.send_response(code)
        self.send_header('Content-Type', mime)
        self.send_header('Content-Length', str(len(body)))
        self.send_header('Cache-Control', 'no-store')
        self.send_header('X-Content-Type-Options', 'nosniff')
        self.send_header('Referrer-Policy', 'no-referrer')
        self.send_header('X-Frame-Options', 'DENY')
        self.end_headers()
        self.wfile.write(body)

    def allowed(self):
        address = ipaddress.ip_address(self.client_address[0])
        if not (address.is_loopback or address in self.server.network):
            self.reply(403, {'error': 'Access is restricted to the local network'})
            return False
        host = self.headers.get('Host', '')
        origin = self.headers.get('Origin')
        if host not in self.server.hosts or origin and origin != 'http://' + host:
            self.reply(403, {'error': 'Invalid page address'})
            return False
        return True

    def do_GET(self):
        path = urlsplit(self.path).path
        if not self.allowed():
            return
        if path == '/':
            self.reply(200, Path(__file__).with_name('index.html').read_bytes(), 'text/html; charset=utf-8')
        elif path == '/qr.svg':
            url = 'http://' + self.headers['Host'] + '/'
            svg = subprocess.check_output([self.server.qrencode, '-t', 'SVG', '-o', '-', url], timeout=5)
            self.reply(200, svg, 'image/svg+xml')
        elif path == '/api/note':
            with self.server.storage.lock:
                self.reply(200, self.server.storage.note)
        else:
            self.reply(404, {'error': 'Not found'})

    def do_PUT(self):
        path = urlsplit(self.path)
        if not self.allowed():
            return
        try:
            length = int(self.headers.get('Content-Length', '-1'))
            path = urlsplit(self.path)
            if path.path == '/api/upload':
                name = parse_qs(path.query).get('name', [''])[0]
                self.reply(201, self.server.storage.upload(name, self.rfile, length))
            elif path.path == '/api/note':
                if not 0 <= length <= MAX_TEXT + 8192:
                    raise ValueError('Text is too large')
                data = json.loads(self.rfile.read(length))
                if not isinstance(data, dict):
                    raise ValueError('Invalid text')
                success, note = self.server.storage.update_note(data)
                self.reply(200 if success else 409, note)
            else:
                self.reply(404, {'error': 'Not found'})
        except (ValueError, KeyError, OSError) as error:
            self.reply(400, {'error': str(error)})


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--bind', default='127.0.0.1')
    parser.add_argument('--port', type=int, default=8765)
    parser.add_argument('--network', required=True)
    parser.add_argument('--qrencode', default='qrencode')
    parser.add_argument('--downloads', required=True)
    parser.add_argument('--state', required=True)
    args = parser.parse_args()
    try:
        address = ipaddress.IPv4Address(args.bind)
        network = ipaddress.IPv4Network(args.network)
        if address.is_unspecified or address.is_multicast or not (address.is_loopback or address in network):
            raise ValueError('Bind address must be a local IPv4 address within the allowed network')
    except ValueError as error:
        parser.error(str(error))
    server = TransferServer((args.bind, args.port), Handler)
    server.storage = Storage(args.downloads, args.state)
    server.qrencode = args.qrencode
    server.network = network
    port = server.server_address[1]
    server.hosts = {f'{args.bind}:{port}', f'127.0.0.1:{port}', f'localhost:{port}'}
    server.timeout = 30
    print(f'LAN transfer listening on {args.bind}:{port}', flush=True)
    server.serve_forever()


if __name__ == '__main__':
    os.umask(0o077)
    main()
