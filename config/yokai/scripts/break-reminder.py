"""Persist movement-reminder preferences independently of shell reloads."""
import argparse
import json
import os
from pathlib import Path
import tempfile

DEFAULTS = {'enabled': False, 'intervalMinutes': 45, 'excludedApps': []}


def validate(changes):
    if not isinstance(changes, dict) or changes.keys() - DEFAULTS.keys():
        raise ValueError('Unknown reminder settings')
    result = dict(changes)
    if 'enabled' in result and type(result['enabled']) is not bool:
        raise ValueError('Enabled must be a boolean')
    if 'intervalMinutes' in result:
        interval = result['intervalMinutes']
        if type(interval) is not int or not 1 <= interval <= 1440:
            raise ValueError('Interval must be between 1 and 1440 minutes')
    if 'excludedApps' in result:
        apps = result['excludedApps']
        if not isinstance(apps, list) or len(apps) > 64 or any(
            not isinstance(app, str) or not app.strip() or len(app) > 200 for app in apps
        ):
            raise ValueError('Use up to 64 nonempty application classes')
        result['excludedApps'] = list(dict.fromkeys(app.strip().lower() for app in apps))
    return result


def settings_path():
    state = Path(os.environ.get('XDG_STATE_HOME') or Path.home() / '.local/state')
    return state / 'yokai/break-reminder.json'


def load(path):
    defaults = validate(json.loads(os.environ.get('YOKAI_BREAK_REMINDER_DEFAULTS', '{}')))
    saved = validate(json.loads(path.read_text())) if path.exists() else {}
    return dict(DEFAULTS, **defaults) | saved


def configure(path, settings, changes):
    settings = settings | validate(changes)
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    fd, temporary = tempfile.mkstemp(prefix='.break-reminder-', dir=path.parent)
    try:
        with os.fdopen(fd, 'w') as stream:
            json.dump(settings, stream)
            stream.write('\n')
        os.replace(temporary, path)
    finally:
        Path(temporary).unlink(missing_ok=True)
    return settings


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('action', choices=('status', 'configure'))
    parser.add_argument('changes', nargs='?')
    args = parser.parse_args()
    try:
        path = settings_path()
        settings = load(path)
        if args.action == 'configure':
            settings = configure(path, settings, json.loads(args.changes or '{}'))
        print(json.dumps({'settings': settings}))
    except (ValueError, OSError) as error:
        print(json.dumps({'error': str(error)}))
        return 1
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
