"""Check saved preferences and validation without touching the desktop."""
import importlib.util
import json
import os
from pathlib import Path
import stat
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

script = Path(sys.argv.pop(1))
spec = importlib.util.spec_from_file_location('break_reminder', script)
app = importlib.util.module_from_spec(spec)
spec.loader.exec_module(app)


class Preferences(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.path = Path(directory.name) / 'preferences.json'
        environment = patch.dict(os.environ, {'YOKAI_BREAK_REMINDER_DEFAULTS': '{}'})
        environment.start()
        self.addCleanup(environment.stop)

    def test_defaults_and_saved_overrides(self):
        defaults = {'enabled': True, 'intervalMinutes': 30, 'excludedApps': ['game-client']}
        with patch.dict(os.environ, {'YOKAI_BREAK_REMINDER_DEFAULTS': json.dumps(defaults)}):
            self.assertEqual(app.load(self.path), defaults)
            app.configure(self.path, app.load(self.path), {'intervalMinutes': 60})
            self.assertEqual(app.load(self.path), defaults | {'intervalMinutes': 60})

    def test_writes_are_private_and_preserve_other_settings(self):
        settings = app.configure(self.path, app.load(self.path),
                                 {'enabled': True, 'excludedApps': [' Game-Client ', 'game-client']})
        self.assertEqual(settings['excludedApps'], ['game-client'])
        self.assertEqual(app.load(self.path), settings)
        self.assertEqual(stat.S_IMODE(self.path.stat().st_mode), 0o600)
        self.assertEqual(list(self.path.parent.iterdir()), [self.path])

    def test_invalid_changes_cannot_overwrite_saved_preferences(self):
        app.configure(self.path, app.load(self.path), {'enabled': True})
        before = self.path.read_bytes()
        for changes in [{'enabled': 'yes'}, {'intervalMinutes': True}, {'intervalMinutes': 0},
                        {'intervalMinutes': 1441}, {'excludedApps': '*'},
                        {'excludedApps': ['']}, {'excludedApps': [None]}, {'unexpected': 1}]:
            with self.subTest(changes=changes), self.assertRaises(ValueError):
                app.configure(self.path, app.load(self.path), changes)
            self.assertEqual(self.path.read_bytes(), before)

    def test_cli_roundtrip_uses_xdg_state_directory(self):
        environment = dict(os.environ, XDG_STATE_HOME=str(self.path.parent))
        command = [sys.executable, str(script)]
        configured = subprocess.run(command + ['configure', '{"enabled":true,"intervalMinutes":15}'],
                                    env=environment, capture_output=True, text=True, check=True)
        restarted = subprocess.run(command + ['status'], env=environment,
                                   capture_output=True, text=True, check=True)
        self.assertEqual(json.loads(configured.stdout), json.loads(restarted.stdout))
        self.assertTrue((self.path.parent / 'yokai/break-reminder.json').is_file())


unittest.main()
