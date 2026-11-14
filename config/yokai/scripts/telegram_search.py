#!/usr/bin/env python3
"""Separate TDLib session exposing only chat/contact metadata to YŌKAI."""
import argparse
from collections import deque
import ctypes
import json
import os
from pathlib import Path
import queue
import re
import signal
import socket
import socketserver
import stat
import subprocess
import sys
import threading
import time

sys.path.insert(0, str(Path(__file__).resolve().parent))
from browser_bridge import best_variant_match, field_match

MAX_MESSAGE = 65536
MAX_ITEMS = 100000
AUTH_STATES = {
    'authorizationStateWaitPhoneNumber': 'phone',
    'authorizationStateWaitOtherDeviceConfirmation': 'qr',
    'authorizationStateWaitCode': 'code',
    'authorizationStateWaitPassword': 'password',
    'authorizationStateWaitEmailAddress': 'email',
    'authorizationStateWaitEmailCode': 'emailCode',
}
ERRORS = {
    'PHONE_NUMBER_INVALID': 'The phone number is invalid.',
    'PHONE_CODE_INVALID': 'The login code is invalid.',
    'PHONE_CODE_EXPIRED': 'The login code expired. Request another QR code or enter your phone again.',
    'PASSWORD_HASH_INVALID': 'The password is incorrect.',
    'EMAIL_ADDRESS_INVALID': 'The email address is invalid.',
    'EMAIL_CODE_INVALID': 'The email code is invalid.',
    'API_ID_INVALID': 'The Telegram application credentials are invalid.',
    'API_ID_PUBLISHED_FLOOD': 'Telegram rejected these application credentials.',
}


class RequestError(ValueError):
    """A fixed, safe explanation that may be displayed by the local frontend."""


def private_json(path, data):
    temporary = path.with_suffix('.tmp')
    descriptor = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(descriptor, 'w') as output:
        json.dump(data, output, ensure_ascii=False, allow_nan=False)
    os.chmod(temporary, 0o600)
    os.replace(temporary, path)


def credentials(value):
    identifier, secret = value.get('apiId'), value.get('apiHash')
    if type(identifier) is not int or not 0 < identifier < 2**31 or not isinstance(secret, str) or not re.fullmatch(r'[0-9a-fA-F]{32}', secret):
        raise RequestError('Enter a positive API ID and a 32-character hexadecimal API hash.')
    return {'apiId': identifier, 'apiHash': secret.lower()}


def usernames(value):
    names = (value.get('usernames') or {}).get('active_usernames', [])
    return [name for name in names if isinstance(name, str) and re.fullmatch(r'[A-Za-z0-9_]{1,64}', name)][:10]


def phone_number(value):
    phone = value.get('phone_number', '')
    return phone if isinstance(phone, str) and re.fullmatch(r'[0-9]{5,20}', phone) else ''


def clean_title(value):
    return ''.join(character for character in str(value or '')[:512] if ord(character) >= 32 and ord(character) != 127)


def server_post(message):
    # Pinned TDLib MessageId.h: server IDs occupy the upper bits; low 20 bits must be zero.
    identifier = (message or {}).get('id', 0)
    return identifier >> 20 if type(identifier) is int and 0 < identifier < 2**51 and identifier % (1 << 20) == 0 else 0


class Metadata:
    """The SDK actor owns this small persisted projection, never message bodies."""

    def __init__(self, directory, load=True):
        self.path = directory / 'metadata.json'
        self.account = None
        self.users, self.chats, self.groups = {}, {}, {}
        self.contacts = set()
        self.dirty = False
        if not load:
            return
        try:
            saved = json.loads(self.path.read_text())
            self.account = saved['account']
            for name in ('users', 'chats', 'groups'):
                setattr(self, name, {int(key): value for key, value in saved.get(name, {}).items()})
            self.contacts = set(saved.get('contacts', []))
            os.chmod(self.path, 0o600)
        except (OSError, ValueError, KeyError, TypeError):
            self.account = None
            self.users, self.chats, self.groups = {}, {}, {}
            self.contacts = set()

    def identify(self, identifier):
        if self.account != identifier:
            self.users.clear()
            self.chats.clear()
            self.groups.clear()
            self.contacts.clear()
            self.account = identifier
            self.dirty = True

    def user(self, user):
        if len(self.users) >= MAX_ITEMS and user['id'] not in self.users:
            return
        self.users[user['id']] = {'title': clean_title(' '.join(filter(None, (user.get('first_name'), user.get('last_name'))))),
                                  'usernames': usernames(user), 'phone': phone_number(user),
                                  'is_contact': user.get('is_contact') is True}
        if user.get('is_contact') is True:
            self.contacts.add(user['id'])
        else:
            self.contacts.discard(user['id'])
        self.dirty = True

    def chat(self, chat):
        if len(self.chats) >= MAX_ITEMS and chat['id'] not in self.chats:
            return
        kind = chat.get('type', {})
        self.chats[chat['id']] = {'title': clean_title(chat.get('title')), 'type': kind.get('@type'),
                                 'user': kind.get('user_id'), 'group': kind.get('supergroup_id'),
                                 'channel': kind.get('is_channel') is True,
                                 'lists': sorted({value.get('@type') for value in chat.get('chat_lists', [])
                                                  if value.get('@type') in ('chatListMain', 'chatListArchive')}),
                                 'post': server_post(chat.get('last_message'))}
        self.dirty = True

    def save(self):
        if self.dirty:
            private_json(self.path, {'account': self.account, 'users': self.users, 'chats': self.chats,
                                    'groups': self.groups, 'contacts': sorted(self.contacts)})
            self.dirty = False

    def rows(self):
        used = set()
        for identifier, chat in self.chats.items():
            if not any(name in ('chatListMain', 'chatListArchive') for name in chat.get('lists', [])):
                continue
            uri, description, terms = '', 'Group', []
            if chat['type'] == 'chatTypePrivate':
                used.add(chat['user'])
                user = self.users.get(chat['user'], {})
                uri = self.user_uri(user)
                terms = user.get('usernames', []) + [user.get('phone', ''), user.get('title', '')]
                description = 'Contact' if chat['user'] in self.contacts else 'Chat'
            elif chat['type'] == 'chatTypeSupergroup':
                names = self.groups.get(chat['group'], {}).get('usernames', [])
                terms = names
                description = 'Channel' if chat['channel'] else 'Group'
                if names:
                    uri = 'tg://resolve?domain=' + names[0]
                elif chat['group'] and 0 < chat['post'] < 2**31:
                    uri = f"tg://privatepost?channel={chat['group']}&post={chat['post']}"
            elif chat['type'] == 'chatTypeSecret':
                description = 'Secret chat · unavailable in Telegram Desktop'
            if not uri and chat['type'] != 'chatTypeSecret':
                description += ' · no supported desktop link'
            yield str(identifier), chat['title'], description, terms, uri
        for identifier in sorted(self.contacts - used):
            user = self.users.get(identifier)
            if user:
                uri = self.user_uri(user)
                yield 'user:' + str(identifier), user['title'], 'Contact' + ('' if uri else ' · no supported desktop link'), user['usernames'] + [user['phone']], uri

    @staticmethod
    def user_uri(user):
        if user.get('usernames'):
            return 'tg://resolve?domain=' + user['usernames'][0]
        if user.get('phone'):
            return 'tg://resolve?phone=' + user['phone']
        return ''

    def search(self, queries):
        if not isinstance(queries, list) or not 1 <= len(queries) <= 8 or any(not isinstance(q, str) or len(q) > 512 for q in queries):
            raise RequestError('Invalid search query.')
        if not queries[0].strip():
            return []
        found = []
        for identifier, title, description, terms, uri in self.rows():
            matches = [max(field_match(query, value) for value in [title, *terms]) for query in queries]
            quality, score, original = best_variant_match(matches)
            if quality >= 0:
                found.append({'kind': 'telegram', 'id': identifier, 'title': title, 'description': description,
                              'icon': 'telegram', 'sourceLabel': 'Telegram', 'score': round(score, 4),
                              'matchQuality': quality, 'originalMatch': original, 'openable': bool(uri)})
        found.sort(key=lambda row: (-row['matchQuality'], -int(row['originalMatch']), -row['score'], row['title'].casefold(), row['id']))
        return found[:20]

    def resolve(self, identifier):
        for current, _, _, _, uri in self.rows():
            if current == identifier:
                if uri:
                    return {'ok': True, 'uri': uri}
                break
        raise RequestError('This chat has no supported Telegram Desktop link.')


class TdJson:
    """Only the actor constructs, sends to, receives from and destroys this client."""

    def __init__(self):
        self.library = ctypes.CDLL(os.environ['TDJSON_PATH'])
        self.library.td_json_client_create.restype = ctypes.c_void_p
        self.library.td_json_client_send.argtypes = [ctypes.c_void_p, ctypes.c_char_p]
        self.library.td_json_client_receive.argtypes = [ctypes.c_void_p, ctypes.c_double]
        self.library.td_json_client_receive.restype = ctypes.c_char_p
        self.library.td_json_client_execute.argtypes = [ctypes.c_void_p, ctypes.c_char_p]
        self.library.td_json_client_execute.restype = ctypes.c_char_p
        self.library.td_json_client_destroy.argtypes = [ctypes.c_void_p]
        for value in ({'@type': 'setLogStream', 'log_stream': {'@type': 'logStreamEmpty'}},
                      {'@type': 'setLogVerbosityLevel', 'new_verbosity_level': 0}):
            self.library.td_json_client_execute(None, json.dumps(value).encode())
        self.client = self.library.td_json_client_create()

    def send(self, value):
        self.library.td_json_client_send(self.client, json.dumps(value).encode())

    def receive(self, timeout):
        raw = self.library.td_json_client_receive(self.client, timeout)
        return json.loads(raw) if raw else None

    def destroy(self):
        self.library.td_json_client_destroy(self.client)


class TelegramActor:
    def __init__(self, directory, transport_factory=TdJson):
        directory.mkdir(parents=True, exist_ok=True, mode=0o700)
        os.chmod(directory, 0o700)
        self.directory, self.transport_factory = directory, transport_factory
        self.metadata = Metadata(directory)
        self.initial_metadata = Metadata(directory, load=False)
        self.transport = None
        self.requests = queue.Queue(maxsize=64)
        self.stopped = threading.Event()
        self.state, self.error = 'credentials', ''
        self.auth_pending = set()
        self.pending, self.serial = {}, 0
        self.identity_known = False
        self.user_fetches = deque()
        self.qr_revision = 0
        self.password_hint = ''
        self.app_credentials = None
        self.qr_path = directory / 'login-qr.png'
        self.qr_path.unlink(missing_ok=True)
        try:
            self.app_credentials = credentials(json.loads((directory / 'credentials.json').read_text()))
            os.chmod(directory / 'credentials.json', 0o600)
        except (OSError, ValueError, TypeError):
            pass
        self.thread = threading.Thread(target=self.run, name='telegram-sdk', daemon=True)

    def status(self):
        result = {'state': self.state, 'ready': self.state == 'ready' and self.identity_known,
                  'busy': bool(self.auth_pending), 'error': self.error,
                  'chatCount': sum(bool(chat.get('lists')) for chat in self.metadata.chats.values()) if self.identity_known else 0}
        if self.state == 'qr' and self.qr_path.exists():
            result.update(qrPath=str(self.qr_path), qrRevision=self.qr_revision)
        if self.state == 'password':
            result['passwordHint'] = self.password_hint
        return result

    def call(self, message):
        if not self.thread.is_alive():
            return {'ok': False, **self.status(), 'results': []}
        answer, completed = {}, threading.Event()
        try:
            self.requests.put_nowait((message, answer, completed))
        except queue.Full:
            return {'ok': False, 'error': 'Telegram is busy. Try again.'}
        if not completed.wait(5):
            return {'ok': False, 'error': 'Telegram did not respond in time.'}
        return answer

    def send(self, kind, purpose=None, **fields):
        self.serial += 1
        token = str(self.serial)
        self.pending[token] = purpose or kind
        if purpose == 'auth' or kind == 'setTdlibParameters':
            self.auth_pending.add(token)
        self.transport.send({'@type': kind, '@extra': token, **fields})

    def initialize(self):
        try:
            self.transport = self.transport_factory()
            self.state = 'phone'
            self.error = ''
        except (OSError, KeyError, RuntimeError):
            self.state, self.error = 'error', 'Telegram SDK could not be initialized.'

    def handle_request(self, message):
        kind = message.get('type')
        if kind == 'status':
            return self.status()
        if kind == 'search':
            status = self.status()
            return {**status, 'results': self.metadata.search(message.get('queries')) if status['ready'] else []}
        if kind == 'resolve':
            if not self.status()['ready']:
                raise RequestError('Telegram is not ready.')
            return self.metadata.resolve(message.get('id'))
        if kind == 'resetCredentials':
            if self.state == 'ready':
                raise RequestError('Application credentials cannot be changed while Telegram is connected.')
            if self.transport is not None:
                self.close_transport()
            (self.directory / 'credentials.json').unlink(missing_ok=True)
            self.qr_path.unlink(missing_ok=True)
            self.app_credentials = None
            self.identity_known = False
            self.initial_metadata = Metadata(self.directory, load=False)
            self.user_fetches.clear()
            self.state, self.error = 'credentials', ''
            return {'ok': True, **self.status()}
        if kind == 'credentials':
            if self.transport is not None and self.state != 'credentials':
                raise RequestError('Telegram application credentials are already configured.')
            configured = credentials(message)
            if self.transport is not None:
                self.close_transport()
            self.app_credentials = configured
            private_json(self.directory / 'credentials.json', self.app_credentials)
            self.initialize()
            return {'ok': self.transport is not None, **self.status()}
        if self.transport is None:
            raise RequestError('Configure Telegram application credentials first.')
        if self.auth_pending:
            raise RequestError('Wait for the current Telegram login request.')
        self.error = ''
        if kind == 'qr' and self.state in ('phone', 'qr', 'code', 'password', 'email', 'emailCode'):
            self.send('requestQrCodeAuthentication', 'auth', other_user_ids=[])
        elif kind == 'phone' and self.state in ('phone', 'qr', 'code', 'password', 'email', 'emailCode'):
            value = message.get('phone')
            if not isinstance(value, str) or not re.fullmatch(r'\+?[0-9]{5,20}', value.strip()):
                raise RequestError('Enter a phone number with its country code.')
            self.send('setAuthenticationPhoneNumber', 'auth', phone_number=value.strip(), settings=None)
        elif kind in ('code', 'password', 'email', 'emailCode') and self.state == kind:
            value = message.get(kind)
            if not isinstance(value, str) or not value or len(value) > 1024 or '\x00' in value:
                raise RequestError('Enter a valid login value.')
            if kind == 'code':
                self.send('checkAuthenticationCode', 'auth', code=value)
            elif kind == 'password':
                self.send('checkAuthenticationPassword', 'auth', password=value)
            elif kind == 'email':
                self.send('setAuthenticationEmailAddress', 'auth', email_address=value)
            else:
                self.send('checkAuthenticationEmailCode', 'auth', code={'@type': 'emailAddressAuthenticationCode', 'code': value})
        else:
            raise RequestError('This login action is not available in the current state.')
        return {'ok': True, **self.status()}

    def authorization(self, value):
        kind = value.get('@type')
        self.error = ''
        self.password_hint = ''
        if kind != 'authorizationStateWaitOtherDeviceConfirmation':
            self.qr_path.unlink(missing_ok=True)
        if kind == 'authorizationStateWaitTdlibParameters':
            database = self.directory / 'tdlib'
            database.mkdir(mode=0o700, exist_ok=True)
            self.send('setTdlibParameters', use_test_dc=False, database_directory=str(database),
                      files_directory=str(database / 'files'), database_encryption_key='',
                      use_file_database=False, use_chat_info_database=True, use_message_database=False,
                      use_secret_chats=False, api_id=self.app_credentials['apiId'], api_hash=self.app_credentials['apiHash'],
                      system_language_code='en', device_model='YŌKAI chat search', system_version='Linux', application_version='1.0')
        elif kind in AUTH_STATES:
            self.state = AUTH_STATES[kind]
            self.identity_known = False
            if self.state == 'password':
                self.password_hint = clean_title(value.get('password_hint'))
            elif self.state == 'qr':
                self.render_qr(value.get('link'))
        elif kind == 'authorizationStateReady':
            self.state = 'ready'
            self.identity_known = False
            self.send('getMe', 'identity')
        elif kind == 'authorizationStateWaitRegistration':
            self.state, self.error = 'error', 'Account registration is not supported. Use an existing Telegram account.'
        elif kind == 'authorizationStateClosed':
            self.state, self.error = 'error', 'The Telegram session closed. Restart the service to reconnect.'
            self.identity_known = False
        elif kind in ('authorizationStateClosing', 'authorizationStateLoggingOut'):
            self.state, self.error = 'error', 'The Telegram session is closing. Restart the service to reconnect.'
            self.identity_known = False
        else:
            self.state, self.error = 'error', 'This Telegram login method is not supported.'

    def render_qr(self, link):
        if not isinstance(link, str) or not link.startswith('tg://login?token=') or len(link) > 4096:
            self.error = 'Telegram returned an invalid QR code.'
            return
        temporary = self.qr_path.with_suffix('.tmp.png')
        try:
            subprocess.run([os.environ.get('QR_ENCODE', 'qrencode'), '-t', 'PNG', '-s', '6', '-m', '3', '-o', str(temporary)],
                           input=link.encode(), stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True, timeout=5)
            os.chmod(temporary, 0o600)
            os.replace(temporary, self.qr_path)
            self.qr_revision += 1
        except (OSError, subprocess.SubprocessError):
            temporary.unlink(missing_ok=True)
            self.error = 'The Telegram QR code could not be rendered.'

    def handle_update(self, value):
        kind = value.get('@type')
        if kind == 'updateAuthorizationState':
            self.authorization(value['authorization_state'])
            return
        token = value.get('@extra')
        purpose = self.pending.pop(token, None)
        self.auth_pending.discard(token)
        if kind == 'error':
            if purpose in ('main', 'archive') and value.get('code') == 404:
                return
            if purpose in ('auth', 'setTdlibParameters', 'identity'):
                raw = value.get('message', '')
                self.error = ERRORS.get(raw, 'Telegram rejected this request. Try again.')
                if isinstance(raw, str) and raw.startswith('FLOOD_WAIT'):
                    self.error = 'Telegram requests a pause before the next login attempt.'
                if purpose == 'setTdlibParameters':
                    self.state = 'credentials'
            return
        if purpose == 'identity' and kind == 'user':
            if self.state != 'ready':
                return
            self.metadata.identify(value['id'])
            for name in ('users', 'chats', 'groups'):
                getattr(self.metadata, name).update(getattr(self.initial_metadata, name))
            self.metadata.contacts.difference_update(self.initial_metadata.users)
            self.metadata.contacts.update(self.initial_metadata.contacts)
            self.initial_metadata = Metadata(self.directory, load=False)
            self.metadata.user(value)
            self.metadata.save()
            self.identity_known = True
            self.send('getContacts', 'contacts')
            for name, chat_list in (('main', 'chatListMain'), ('archive', 'chatListArchive')):
                self.send('loadChats', name, chat_list={'@type': chat_list}, limit=100)
            return
        metadata = self.metadata if self.identity_known else self.initial_metadata
        if purpose in ('main', 'archive') and kind == 'ok':
            self.send('loadChats', purpose, chat_list={'@type': 'chatListMain' if purpose == 'main' else 'chatListArchive'}, limit=100)
        elif purpose == 'contacts' and kind == 'users':
            metadata.contacts = set(value.get('user_ids', [])[:MAX_ITEMS])
            metadata.dirty = True
            self.user_fetches.extend(identifier for identifier in metadata.contacts if identifier not in metadata.users)
        elif kind in ('user', 'updateUser'):
            metadata.user(value if kind == 'user' else value['user'])
        elif kind == 'updateNewChat':
            metadata.chat(value['chat'])
        elif kind in ('updateChatAddedToList', 'updateChatRemovedFromList') and value['chat_id'] in metadata.chats:
            name = value.get('chat_list', {}).get('@type')
            if name in ('chatListMain', 'chatListArchive'):
                chat = metadata.chats[value['chat_id']]
                membership = set(chat.get('lists', []))
                if kind == 'updateChatAddedToList':
                    membership.add(name)
                else:
                    membership.discard(name)
                chat['lists'] = sorted(membership)
                metadata.dirty = True
        elif kind == 'updateChatTitle' and value['chat_id'] in metadata.chats:
            metadata.chats[value['chat_id']]['title'] = clean_title(value.get('title'))
            metadata.dirty = True
        elif kind == 'updateSupergroup':
            group = value['supergroup']
            if len(metadata.groups) >= MAX_ITEMS and group['id'] not in metadata.groups:
                return
            metadata.groups[group['id']] = {'usernames': usernames(group)}
            metadata.dirty = True
        elif kind == 'updateChatLastMessage' and value['chat_id'] in metadata.chats:
            # TDLib includes message content here; retain only its server ID for a desktop link.
            metadata.chats[value['chat_id']]['post'] = server_post(value.get('last_message'))
            metadata.dirty = True

    def run(self):
        if self.app_credentials:
            self.initialize()
        next_save = time.monotonic() + 1
        try:
            while not self.stopped.is_set():
                try:
                    message, answer, completed = self.requests.get(timeout=0 if self.transport else 0.1)
                except queue.Empty:
                    pass
                else:
                    try:
                        answer.update(self.handle_request(message))
                    except RequestError as error:
                        if message.get('type') in ('credentials', 'resetCredentials', 'qr', 'phone', 'code', 'password', 'email', 'emailCode'):
                            self.error = str(error)
                        answer.update(ok=False, **self.status())
                        answer['error'] = str(error)
                    except (ValueError, TypeError, OSError):
                        # Validation messages are fixed strings; never echo SDK/input exceptions.
                        answer.update(ok=False, **self.status())
                        answer['error'] = 'Invalid or unavailable Telegram request.'
                    finally:
                        completed.set()
                if self.transport:
                    update = self.transport.receive(0.05)
                    if update:
                        self.handle_update(update)
                    while self.user_fetches and len(self.pending) < 64:
                        self.send('getUser', user_id=self.user_fetches.popleft())
                if time.monotonic() >= next_save:
                    self.metadata.save()
                    next_save = time.monotonic() + 1
        except (OSError, ValueError, TypeError, KeyError, RuntimeError):
            self.state, self.error = 'error', 'Telegram metadata service encountered an error. Restart it to reconnect.'
        finally:
            if self.transport:
                self.close_transport()
            self.metadata.save()
            self.qr_path.unlink(missing_ok=True)

    def close_transport(self):
        try:
            self.transport.send({'@type': 'close'})
            deadline = time.monotonic() + 2
            while time.monotonic() < deadline:
                update = self.transport.receive(0.05)
                if update and update.get('@type') == 'updateAuthorizationState' and update.get('authorization_state', {}).get('@type') == 'authorizationStateClosed':
                    break
        except (OSError, ValueError, RuntimeError):
            pass
        finally:
            self.transport.destroy()
            self.transport = None
            self.pending.clear()
            self.auth_pending.clear()

    def stop(self):
        self.stopped.set()
        self.thread.join(timeout=4)


class TelegramServer(socketserver.UnixStreamServer):
    def __init__(self, path, actor):
        self.actor = actor
        super().__init__(str(path), TelegramClient)
        os.chmod(path, 0o600)


class TelegramClient(socketserver.StreamRequestHandler):
    def handle(self):
        try:
            self.connection.settimeout(5)
            raw = self.rfile.readline(MAX_MESSAGE + 2)
            if not raw.endswith(b'\n') or len(raw) > MAX_MESSAGE:
                raise ValueError()
            message = json.loads(raw)
            if not isinstance(message, dict):
                raise ValueError()
            answer = self.server.actor.call(message)
        except (OSError, ValueError):
            answer = {'ok': False, 'error': 'Invalid Telegram request.'}
        try:
            self.wfile.write(json.dumps(answer, ensure_ascii=False).encode() + b'\n')
        except OSError:
            pass


def request(path, message):
    try:
        data = json.dumps(message, allow_nan=False).encode() + b'\n'
        if len(data) > MAX_MESSAGE:
            raise ValueError()
        with socket.socket(socket.AF_UNIX) as connection:
            connection.settimeout(6)
            connection.connect(str(path))
            connection.sendall(data)
            with connection.makefile('rb') as reader:
                raw = reader.readline(MAX_MESSAGE + 2)
                if not raw or len(raw) > MAX_MESSAGE:
                    raise ValueError()
                return json.loads(raw)
    except (OSError, ValueError):
        return {'ok': False, 'state': 'error', 'ready': False, 'busy': False, 'results': [],
                'error': 'Telegram search service is unavailable.'}


def serve(path, directory):
    os.umask(0o077)
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    if path.exists():
        if not stat.S_ISSOCK(path.stat().st_mode) or path.stat().st_uid != os.getuid():
            raise ValueError()
        try:
            with socket.socket(socket.AF_UNIX) as probe:
                probe.connect(str(path))
        except ConnectionRefusedError:
            path.unlink()
        else:
            raise ValueError()
    actor = TelegramActor(directory)
    server = TelegramServer(path, actor)
    actor.thread.start()
    for signum in (signal.SIGTERM, signal.SIGINT):
        signal.signal(signum, lambda *_: threading.Thread(target=server.shutdown, daemon=True).start())
    try:
        server.serve_forever(poll_interval=0.2)
    finally:
        server.server_close()
        actor.stop()
        path.unlink(missing_ok=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__, allow_abbrev=False)
    runtime = Path(os.environ.get('XDG_RUNTIME_DIR') or f'/run/user/{os.getuid()}')
    state = Path(os.environ.get('XDG_STATE_HOME') or Path.home() / '.local/state')
    parser.add_argument('--socket', type=Path, default=runtime / 'yokai-telegram.sock')
    parser.add_argument('--state', type=Path, default=state / 'yokai/telegram')
    commands = parser.add_subparsers(dest='command', required=True)
    commands.add_parser('serve')
    commands.add_parser('status')
    commands.add_parser('request')
    search = commands.add_parser('search')
    search.add_argument('--queries', required=True)
    arguments = parser.parse_args()
    try:
        if arguments.command == 'serve':
            serve(arguments.socket, arguments.state)
            return
        if arguments.command == 'request':
            raw = sys.stdin.buffer.readline(MAX_MESSAGE + 2)
            if len(raw) > MAX_MESSAGE:
                raise ValueError()
            message = json.loads(raw)
            if not isinstance(message, dict):
                raise ValueError()
        elif arguments.command == 'search':
            message = {'type': 'search', 'queries': json.loads(arguments.queries)}
        else:
            message = {'type': 'status'}
        print(json.dumps(request(arguments.socket, message), ensure_ascii=False))
    except (OSError, ValueError, TypeError):
        print(json.dumps({'ok': False, 'error': 'Invalid or unavailable Telegram request.'}))
        sys.exit(1)


if __name__ == '__main__':
    main()
