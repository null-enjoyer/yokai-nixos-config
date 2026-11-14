"""Telegram metadata/auth checks: synthetic TDLib, no account or network access."""
import argparse
import importlib.util
import json
from pathlib import Path
import queue
import stat
import subprocess
import sys
import tempfile
import threading
import unittest
from unittest.mock import patch

arguments = argparse.ArgumentParser(add_help=False, allow_abbrev=False)
arguments.add_argument('--script', type=Path, default=Path(__file__).resolve().parents[1] / 'config/yokai/scripts/telegram_search.py')
options, remaining = arguments.parse_known_args()
sys.argv = [sys.argv[0], *remaining]
SCRIPT = options.script.resolve()
spec = importlib.util.spec_from_file_location('telegram_search', SCRIPT)
telegram = importlib.util.module_from_spec(spec)
spec.loader.exec_module(telegram)
import browser_bridge as bridge


class FakeTd:
    def __init__(self):
        self.sent = []
        self.incoming = queue.Queue()
        self.destroyed = False
        self.threads = set()

    def send(self, message):
        self.threads.add(threading.get_ident())
        self.sent.append(message)
        if message['@type'] == 'close':
            self.incoming.put({'@type': 'updateAuthorizationState', 'authorization_state': {'@type': 'authorizationStateClosed'}})

    def receive(self, timeout):
        self.threads.add(threading.get_ident())
        try:
            return self.incoming.get(timeout=timeout)
        except queue.Empty:
            return None

    def destroy(self):
        self.threads.add(threading.get_ident())
        self.destroyed = True


class TelegramChecks(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='yokai-telegram-check-')
        self.directory = Path(self.temporary.name) / 'state'
        self.td = FakeTd()
        self.factories = 0

        def create():
            self.factories += 1
            return self.td
        self.actor = telegram.TelegramActor(self.directory, create)

    def tearDown(self):
        if self.actor.thread.is_alive():
            self.actor.stop()
        self.temporary.cleanup()

    def authenticate(self):
        return self.actor.handle_request({'type': 'credentials', 'apiId': 123, 'apiHash': 'a' * 32})

    def auth(self, name, **fields):
        self.actor.handle_update({'@type': 'updateAuthorizationState', 'authorization_state': {'@type': name, **fields}})

    def acknowledge(self, result=None):
        sent = self.td.sent[-1]
        self.actor.handle_update({'@type': 'ok', '@extra': sent['@extra'], **(result or {})})

    def ready(self, identifier=1):
        if not self.actor.transport:
            self.authenticate()
        self.auth('authorizationStateReady')
        self.acknowledge({'@type': 'user', 'id': identifier, 'first_name': 'Self'})

    def chat(self, identifier, title, kind, **fields):
        self.actor.handle_update({'@type': 'updateNewChat', 'chat': {'id': identifier, 'title': title,
                                  'type': {'@type': kind, **fields},
                                  'chat_lists': [{'@type': 'chatListMain'}],
                                  'last_message': {'id': 17 << 20, 'content': {'text': 'PRIVATE MESSAGE BODY'}}}})

    def user(self, identifier, name, username='', phone='', is_contact=False):
        self.actor.handle_update({'@type': 'updateUser', 'user': {'id': identifier, 'first_name': name,
                                  'usernames': {'active_usernames': [username]}, 'phone_number': phone,
                                  'is_contact': is_contact}})

    def test_missing_credentials_never_initializes_sdk_and_private_state(self):
        self.actor.thread.start()
        answer = self.actor.call({'type': 'status'})
        self.assertEqual(answer['state'], 'credentials')
        self.assertFalse(answer['ready'])
        self.assertEqual(self.factories, 0)
        self.assertEqual(stat.S_IMODE(self.directory.stat().st_mode), 0o700)
        for identifier, secret in ((True, 'a' * 32), (0, 'a' * 32), (2**31, 'a' * 32), (1, 'bad')):
            rejected = self.actor.call({'type': 'credentials', 'apiId': identifier, 'apiHash': secret})
            self.assertFalse(rejected['ok'])
        self.assertEqual(self.factories, 0)

    def test_credentials_parameters_persistence_and_auth_states(self):
        self.assertTrue(self.authenticate()['ok'])
        self.assertEqual(self.factories, 1)
        self.assertEqual(stat.S_IMODE((self.directory / 'credentials.json').stat().st_mode), 0o600)
        self.auth('authorizationStateWaitTdlibParameters')
        parameters = self.td.sent[-1]
        self.assertFalse(parameters['use_message_database'])
        self.assertFalse(parameters['use_secret_chats'])
        self.assertFalse(parameters['use_file_database'])
        self.assertTrue(parameters['use_chat_info_database'])
        self.acknowledge()
        cases = [('authorizationStateWaitPhoneNumber', 'phone', 'phone', '+1234567890', 'setAuthenticationPhoneNumber'),
                 ('authorizationStateWaitCode', 'code', 'code', 'SECRET-CODE', 'checkAuthenticationCode'),
                 ('authorizationStateWaitPassword', 'password', 'password', 'SECRET-PASSWORD', 'checkAuthenticationPassword'),
                 ('authorizationStateWaitEmailAddress', 'email', 'email', 'private@example.org', 'setAuthenticationEmailAddress'),
                 ('authorizationStateWaitEmailCode', 'emailCode', 'emailCode', 'SECRET-EMAIL-CODE', 'checkAuthenticationEmailCode')]
        for td_state, state, field, value, method in cases:
            self.auth(td_state, password_hint='Hint')
            answer = self.actor.handle_request({'type': field, field: value})
            self.assertEqual(answer['state'], state)
            self.assertTrue(answer['busy'])
            self.assertEqual(self.td.sent[-1]['@type'], method)
            self.assertNotIn(value, json.dumps(answer))
            self.assertNotIn('a' * 32, json.dumps(answer))
            self.acknowledge()
        restored = telegram.TelegramActor(self.directory, lambda: self.fail('Must initialize in actor only'))
        self.assertEqual(restored.app_credentials['apiId'], 123)

    def test_sdk_error_redaction_and_no_registration(self):
        self.authenticate()
        self.auth('authorizationStateWaitCode')
        self.actor.handle_request({'type': 'code', 'code': 'super-private'})
        self.acknowledge({'@type': 'error', 'message': 'RAW secret phone +123 and code super-private', 'code': 400})
        status = self.actor.status()
        self.assertEqual(status['state'], 'code')
        self.assertFalse(status['busy'])
        self.assertNotIn('super-private', json.dumps(status))
        self.assertNotIn('+123', json.dumps(status))
        self.auth('authorizationStateWaitRegistration')
        self.assertEqual(self.actor.status()['state'], 'error')
        self.assertFalse(any(message['@type'] == 'registerUser' for message in self.td.sent))

    def test_auth_validation_error_survives_polling_and_valid_retry_clears_it(self):
        self.actor.thread.start()
        self.assertTrue(self.actor.call({'type': 'credentials', 'apiId': 123, 'apiHash': 'a' * 32})['ok'])
        rejected = self.actor.call({'type': 'phone', 'phone': '+bad'})
        self.assertFalse(rejected['ok'])
        self.assertEqual(rejected['error'], 'Enter a phone number with its country code.')
        self.assertEqual(self.actor.call({'type': 'status'})['error'], rejected['error'])
        self.assertFalse(self.actor.call({'type': 'resolve', 'id': 'missing'})['ok'])
        self.actor.call({'type': 'search', 'queries': ['']})
        self.assertEqual(self.actor.call({'type': 'status'})['error'], rejected['error'], 'Search/resolve must preserve the auth error')
        retry = self.actor.call({'type': 'phone', 'phone': '+1234567890'})
        self.assertTrue(retry['ok'])
        self.assertEqual(retry['error'], '')
        self.assertEqual(self.actor.call({'type': 'status'})['error'], '')

    def test_invalid_application_keys_can_be_corrected_without_manual_state_edits(self):
        self.authenticate()
        self.auth('authorizationStateWaitTdlibParameters')
        self.acknowledge({'@type': 'error', 'message': 'API_ID_INVALID', 'code': 400})
        self.assertEqual(self.actor.status()['state'], 'credentials')
        self.assertTrue(self.actor.handle_request({'type': 'credentials', 'apiId': 456, 'apiHash': 'b' * 32})['ok'])
        self.assertEqual(self.factories, 2)
        self.assertTrue(self.td.destroyed)
        saved = json.loads((self.directory / 'credentials.json').read_text())
        self.assertEqual(saved['apiId'], 456)

    def test_explicit_credentials_reset_closes_only_own_sdk_and_blocks_when_connected(self):
        self.authenticate()
        database = self.directory / 'tdlib'
        database.mkdir()
        (database / 'synthetic-session').write_text('session')
        self.actor.qr_path.write_bytes(b'fake-png')
        answer = self.actor.handle_request({'type': 'resetCredentials'})
        self.assertTrue(answer['ok'])
        self.assertEqual(answer['state'], 'credentials')
        self.assertTrue(self.td.destroyed)
        self.assertFalse((self.directory / 'credentials.json').exists())
        self.assertFalse(self.actor.qr_path.exists())
        self.assertTrue((database / 'synthetic-session').exists())
        self.ready()
        with self.assertRaises(telegram.RequestError):
            self.actor.handle_request({'type': 'resetCredentials'})

    def test_qr_secrets_on_stdin_private_image_refresh_and_removal(self):
        self.authenticate()
        self.actor.handle_request({'type': 'qr'})
        self.assertEqual(self.td.sent[-1]['@type'], 'requestQrCodeAuthentication')
        link = 'tg://login?token=PRIVATE-QR-TOKEN'

        def render(command, **kwargs):
            self.assertNotIn(link, command)
            self.assertEqual(kwargs['input'], link.encode())
            Path(command[-1]).write_bytes(b'fake-png')
        with patch.object(telegram.subprocess, 'run', side_effect=render):
            self.auth('authorizationStateWaitOtherDeviceConfirmation', link=link)
            self.auth('authorizationStateWaitOtherDeviceConfirmation', link=link)
        status = self.actor.status()
        self.assertEqual(status['qrRevision'], 2)
        self.assertNotIn('PRIVATE-QR-TOKEN', json.dumps(status))
        self.assertEqual(stat.S_IMODE(self.actor.qr_path.stat().st_mode), 0o600)
        self.auth('authorizationStateWaitPassword')
        self.assertFalse(self.actor.qr_path.exists())

    def test_metadata_unicode_fuzzy_links_contacts_and_unsupported(self):
        self.ready()
        self.user(10, 'Тестовый пользователь', 'example_user')
        self.user(11, 'Alice Phone', phone='1234567890')
        self.user(12, 'No Link', username='bad&start=payload', phone='1&payload')
        self.chat(100, 'Тестовый пользователь разработчик', 'chatTypePrivate', user_id=10)
        self.chat(101, 'Alice Phone', 'chatTypePrivate', user_id=11)
        self.chat(102, 'No Link', 'chatTypePrivate', user_id=12)
        self.chat(-200, 'Public Group', 'chatTypeSupergroup', supergroup_id=20, is_channel=False)
        self.chat(-201, 'Private Channel', 'chatTypeSupergroup', supergroup_id=21, is_channel=True)
        self.chat(-202, 'Basic Group', 'chatTypeBasicGroup', basic_group_id=22)
        self.actor.handle_update({'@type': 'updateSupergroup', 'supergroup': {'id': 20, 'usernames': {'active_usernames': ['public_test']}}})
        self.assertEqual(self.actor.metadata.resolve('100')['uri'], 'tg://resolve?domain=example_user')
        self.assertEqual(self.actor.metadata.resolve('101')['uri'], 'tg://resolve?phone=1234567890')
        self.assertEqual(self.actor.metadata.resolve('-200')['uri'], 'tg://resolve?domain=public_test')
        self.assertEqual(self.actor.metadata.resolve('-201')['uri'], 'tg://privatepost?channel=21&post=17')
        for identifier in ('102', '-202', 'missing'):
            with self.assertRaises(ValueError):
                self.actor.metadata.resolve(identifier)
        result = self.actor.metadata.search(['testovyy', 'тестовый'])[0]
        self.assertEqual(result['id'], '100')
        self.assertFalse(result['originalMatch'])
        self.assertTrue(result['openable'])
        self.assertEqual(self.actor.metadata.search(['']), [])
        self.assertFalse(self.actor.metadata.search(['basic'])[0]['openable'])
        self.actor.metadata.contacts = {10, 11, 12}
        self.assertEqual(len(list(self.actor.metadata.rows())), 6, 'Contacts with chats must not duplicate')

    def test_exact_chat_beats_a_weak_browser_match_with_homepage_bonus(self):
        self.ready()
        self.chat(100, 'Тест', 'chatTypePrivate', user_id=10)
        self.user(10, 'Тест', 'test_contact')
        store = bridge.HistoryStore(self.directory / 'synthetic-browser.sqlite3')
        try:
            url = 'https://n.t.c.n.site.test/'
            store.commit('synthetic-source', 'Default', 'Synthetic', {url: (url, 'Example website', 100, 10)})
            browser = store.search(['Тест', 'Ntcn'])['results'][0]
        finally:
            store.close()
        chat = self.actor.metadata.search(['Тест', 'Ntcn'])[0]
        self.assertGreater(browser['score'], chat['score'], 'Fixture must give the weak browser match a higher numeric score')
        self.assertEqual(chat['matchQuality'], 4)
        self.assertEqual(browser['matchQuality'], 0)
        ordered = sorted([browser, chat], key=lambda row: (-row['matchQuality'], -int(row['originalMatch']), -row['score']))
        self.assertEqual(ordered[0]['kind'], 'telegram')

    def test_chat_quality_and_primary_variant_ordering(self):
        self.ready()
        for identifier, title in enumerate(('Ntcn', 'Тест', 'Т е с т', 'Привет Тест!', 'Тестовый', 'СуперТест'), 100):
            self.chat(identifier, title, 'chatTypePrivate', user_id=identifier + 1000)
        rows = self.actor.metadata.search(['Тест', 'Ntcn'])
        self.assertEqual([row['title'] for row in rows], ['Тест', 'Ntcn', 'Привет Тест!', 'Тестовый', 'СуперТест', 'Т е с т'])
        self.assertEqual([row['matchQuality'] for row in rows], [4, 4, 3, 2, 1, 0])
        self.assertTrue(rows[0]['originalMatch'])
        self.assertFalse(rows[1]['originalMatch'])

    def test_chat_primary_variant_score_stays_coherent_with_quality(self):
        self.ready()
        self.chat(100, 'Shop', 'chatTypePrivate', user_id=10)
        self.user(10, 'Shop', 'longer')
        row = self.actor.metadata.search(['shop', 'longer'])[0]
        self.assertEqual(row['matchQuality'], 4)
        self.assertTrue(row['originalMatch'])
        self.assertEqual(row['score'], round(bridge.field_match('shop', 'Shop')[1], 4))
        self.assertGreater(bridge.field_match('longer', 'longer')[1], row['score'])

    def test_persistence_drops_message_content_and_account_change_clears_cache(self):
        self.ready(1)
        self.user(10, 'Old Contact', 'old_contact')
        self.chat(100, 'Old Chat', 'chatTypePrivate', user_id=10)
        self.actor.handle_update({'@type': 'updateNewMessage', 'message': {'content': {'text': 'ALSO PRIVATE'}}})
        self.actor.metadata.save()
        wire = (self.directory / 'metadata.json').read_text()
        self.assertNotIn('PRIVATE', wire)
        self.assertNotIn('content', wire)
        restored = telegram.Metadata(self.directory)
        self.assertEqual(restored.search(['old'])[0]['title'], 'Old Chat')
        self.assertEqual(stat.S_IMODE(restored.path.stat().st_mode), 0o600)
        self.ready(2)
        self.assertEqual(self.actor.metadata.account, 2)
        self.assertEqual(self.actor.metadata.search(['old']), [])
        self.assertNotIn('Old Chat', (self.directory / 'metadata.json').read_text())

    def test_initial_updates_before_identity_are_retained_after_confirmation(self):
        self.authenticate()
        self.user(10, 'Initial User', 'initial_user')
        self.chat(100, 'Initial Chat', 'chatTypePrivate', user_id=10)
        self.assertEqual(self.actor.handle_request({'type': 'search', 'queries': ['initial']})['results'], [])
        self.ready()
        self.assertEqual(self.actor.metadata.resolve('100')['uri'], 'tg://resolve?domain=initial_user')

    def test_main_archive_membership_tracks_removal_and_excludes_legacy_cache(self):
        self.ready()
        self.chat(-100, 'Membership Group', 'chatTypeBasicGroup', basic_group_id=10)
        self.assertEqual(len(self.actor.metadata.search(['membership'])), 1)
        self.actor.handle_update({'@type': 'updateChatRemovedFromList', 'chat_id': -100,
                                  'chat_list': {'@type': 'chatListMain'}})
        self.assertEqual(self.actor.metadata.search(['membership']), [])
        self.actor.handle_update({'@type': 'updateChatAddedToList', 'chat_id': -100,
                                  'chat_list': {'@type': 'chatListArchive'}})
        self.assertEqual(len(self.actor.metadata.search(['membership'])), 1)
        self.actor.handle_update({'@type': 'updateChatPosition', 'chat_id': -100,
                                  'position': {'list': {'@type': 'chatListArchive'}, 'order': 0}})
        self.assertEqual(len(self.actor.metadata.search(['membership'])), 1, 'Position does not define membership')
        self.actor.metadata.save()
        restored = telegram.Metadata(self.directory)
        self.assertEqual(restored.chats[-100]['lists'], ['chatListArchive'])
        del restored.chats[-100]['lists']
        restored.dirty = True
        restored.save()
        legacy = telegram.Metadata(self.directory)
        self.assertEqual(legacy.search(['membership']), [], 'Legacy caches need a fresh membership update')
        self.actor.handle_update({'@type': 'updateChatRemovedFromList', 'chat_id': -100,
                                  'chat_list': {'@type': 'chatListArchive'}})
        self.assertEqual(self.actor.status()['chatCount'], 0)

    def test_contact_updates_without_dialog_add_and_remove_search_results(self):
        self.ready()
        self.user(10, 'Dynamic Contact', 'dynamic_contact', is_contact=True)
        self.assertEqual(self.actor.metadata.search(['dynamic'])[0]['id'], 'user:10')
        self.user(10, 'Dynamic Contact', 'dynamic_contact', is_contact=False)
        self.assertEqual(self.actor.metadata.search(['dynamic']), [])
        self.actor.metadata.save()
        self.assertNotIn(10, telegram.Metadata(self.directory).contacts)

    def test_initial_contact_changes_merge_then_contact_list_is_authoritative(self):
        self.ready()
        self.user(10, 'Removed Contact', 'removed_contact', is_contact=True)
        self.auth('authorizationStateReady')
        identity_request = self.td.sent[-1]
        self.user(10, 'Removed Contact', 'removed_contact', is_contact=False)
        self.user(11, 'Initial Contact', 'initial_contact', is_contact=True)
        self.actor.handle_update({'@type': 'user', '@extra': identity_request['@extra'], 'id': 1, 'first_name': 'Self'})
        self.assertNotIn(10, self.actor.metadata.contacts)
        self.assertIn(11, self.actor.metadata.contacts)
        contacts_request = next(message for message in reversed(self.td.sent) if message['@type'] == 'getContacts')
        self.actor.handle_update({'@type': 'users', '@extra': contacts_request['@extra'], 'user_ids': []})
        self.assertEqual(self.actor.metadata.contacts, set())
        self.assertEqual(self.actor.metadata.search(['initial']), [])

    def test_closing_and_logging_out_immediately_disable_search_and_resolution(self):
        for state in ('authorizationStateClosing', 'authorizationStateLoggingOut'):
            self.ready()
            self.chat(100, 'Closing Chat', 'chatTypePrivate', user_id=10)
            self.user(10, 'Closing User', 'closing_user')
            self.assertTrue(self.actor.status()['ready'])
            self.actor.send('getMe', 'identity')
            stale_identity = self.td.sent[-1]
            self.auth(state)
            status = self.actor.status()
            self.assertEqual(status['state'], 'error')
            self.assertFalse(status['ready'])
            self.assertFalse(self.actor.identity_known)
            self.assertEqual(self.actor.handle_request({'type': 'search', 'queries': ['closing']})['results'], [])
            with self.assertRaises(telegram.RequestError):
                self.actor.handle_request({'type': 'resolve', 'id': '100'})
            self.actor.handle_update({'@type': 'user', '@extra': stale_identity['@extra'], 'id': 1, 'first_name': 'Self'})
            self.assertFalse(self.actor.identity_known, 'A late identity response must not undo shutdown')

    def test_loads_main_archive_contacts_without_message_or_read_receipt_requests(self):
        self.ready()
        sent = list(self.td.sent)
        self.assertEqual({message['chat_list']['@type'] for message in sent if message['@type'] == 'loadChats'}, {'chatListMain', 'chatListArchive'})
        self.assertTrue(any(message['@type'] == 'getContacts' for message in sent))
        page = next(message for message in sent if message['@type'] == 'loadChats')
        self.actor.handle_update({'@type': 'ok', '@extra': page['@extra']})
        self.assertEqual(self.td.sent[-1]['@type'], 'loadChats')
        self.acknowledge({'@type': 'error', 'code': 404, 'message': 'Not Found'})
        self.assertEqual(self.actor.error, '')
        allowed = {'getMe', 'getContacts', 'getUser', 'loadChats'}
        self.assertTrue(all(message['@type'] in allowed for message in sent))

    def test_only_server_message_ids_become_private_links(self):
        self.assertEqual(telegram.server_post({'id': 17 << 20}), 17)
        for value in (None, {'id': 0}, {'id': -1}, {'id': (17 << 20) + 1},
                      {'id': (17 << 20) + 2}, {'id': (17 << 20) + 4}, {'id': 2**51}, {'id': '17'}):
            self.assertEqual(telegram.server_post(value), 0)

    def test_socket_cli_and_graceful_actor_stop(self):
        self.actor.thread.start()
        socket = self.directory / 'telegram.sock'
        server = telegram.TelegramServer(socket, self.actor)
        thread = threading.Thread(target=server.serve_forever, kwargs={'poll_interval': 0.02}, daemon=True)
        thread.start()
        try:
            self.assertEqual(stat.S_IMODE(socket.stat().st_mode), 0o600)
            result = subprocess.run([sys.executable, str(SCRIPT), '--socket', str(socket), 'status'], capture_output=True, timeout=3)
            self.assertEqual(json.loads(result.stdout)['state'], 'credentials')
            self.assertEqual(result.stderr, b'')
            answer = telegram.request(socket, {'type': 'credentials', 'apiId': 123, 'apiHash': 'a' * 32})
            self.assertTrue(answer['ok'])
            self.assertTrue(telegram.request(socket, {'type': 'qr'})['ok'])
            rejected = subprocess.run([sys.executable, str(SCRIPT), '--socket', str(socket), 'request'],
                                      input=b'{"type":"password","password":"PRIVATE-CREDENTIAL"}\n', capture_output=True, timeout=3)
            self.assertNotIn(b'PRIVATE-CREDENTIAL', rejected.stdout + rejected.stderr)
            self.assertFalse(json.loads(rejected.stdout)['ok'])
        finally:
            server.shutdown()
            server.server_close()
            thread.join(timeout=2)
        self.actor.stop()
        self.assertFalse(self.actor.thread.is_alive())
        self.assertTrue(self.td.destroyed)
        self.assertEqual(self.td.threads, {self.actor.thread.ident}, 'All SDK calls belong to the actor')
        self.assertEqual(self.td.sent[-1]['@type'], 'close')
        self.assertFalse(self.actor.qr_path.exists())
        self.assertFalse(telegram.request(self.directory / 'missing.sock', {'type': 'status'})['ready'])


if __name__ == '__main__':
    unittest.main()
