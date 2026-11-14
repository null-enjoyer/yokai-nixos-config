"""Check screenshot cancellation and capture failures without touching the clipboard."""
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

SCRIPT = Path(sys.argv.pop(1))
BASH = shutil.which('bash')


class ScreenshotChecks(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.trace = self.root / 'trace'
        self.image = self.root / 'image'
        commands = {
            'slurp': 'exit "${SELECTOR_STATUS:-0}"' ,
            'grim': 'printf "%s\\n" "grim $*" >> "$TRACE"; exit "${GRIM_STATUS:-0}"',
            'wl-copy': 'cat > "$IMAGE"; echo wl-copy >> "$TRACE"',
            'satty': 'cat > "$IMAGE"; echo "satty $*" >> "$TRACE"',
        }
        commands['slurp'] = 'cat >/dev/null; printf "10,20 30x40\\n"; ' + commands['slurp']
        commands['grim'] = 'printf PNG-DATA; ' + commands['grim']
        for name, body in commands.items():
            path = self.root / name
            path.write_text(f'#!{BASH}\n{body}\n')
            path.chmod(0o755)
        self.env = dict(os.environ, PATH=str(self.root) + os.pathsep + os.environ['PATH'],
                        TRACE=str(self.trace), IMAGE=str(self.image))

    def run_capture(self, kind, **variables):
        return subprocess.run([BASH, str(SCRIPT), kind], env=dict(self.env, **variables),
                              capture_output=True, timeout=5)

    def test_selector_does_not_wait_for_parent_stdin(self):
        process = subprocess.Popen([BASH, str(SCRIPT), 'region'], env=self.env,
                                   stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        try:
            self.assertEqual(process.wait(timeout=3), 0)
            self.assertEqual(self.image.read_bytes(), b'PNG-DATA')
        finally:
            if process.poll() is None:
                process.kill()
            process.communicate(timeout=5)

    def test_cancel_leaves_clipboard_untouched(self):
        self.image.write_bytes(b'previous clipboard')
        result = self.run_capture('region', SELECTOR_STATUS='1')
        self.assertEqual(result.returncode, 0)
        self.assertFalse(self.trace.exists())
        self.assertEqual(self.image.read_bytes(), b'previous clipboard')

    def test_region_copies_selected_geometry(self):
        self.assertEqual(self.run_capture('region').returncode, 0)
        self.assertEqual(self.image.read_bytes(), b'PNG-DATA')
        self.assertEqual(self.trace.read_text().splitlines(), ['grim -g 10,20 30x40 -', 'wl-copy'])

    def test_annotation_receives_image(self):
        self.assertEqual(self.run_capture('annotate').returncode, 0)
        self.assertEqual(self.image.read_bytes(), b'PNG-DATA')
        self.assertIn('satty --filename -', self.trace.read_text())

    def test_capture_failure_is_reported(self):
        self.assertNotEqual(self.run_capture('full', GRIM_STATUS='1').returncode, 0)


unittest.main()
