#!/usr/bin/env python3
"""Discover folders once, then rank queries with fzf's path-aware fuzzy matcher."""
import json
import os
from pathlib import Path
import subprocess
import sys
import time


def catalog(roots):
    directory = Path(os.environ.get('XDG_CACHE_HOME', Path.home() / '.cache')) / 'yokai'
    cache = directory / 'folders.json'
    names = [str(root) for root in roots]
    try:
        saved = json.loads(cache.read_text())
        if saved['roots'] == names and time.time() - saved['time'] < 30:
            return saved['folders']
    except (OSError, ValueError, KeyError):
        pass
    command = ['fd', '--type', 'd', '--hidden', '--no-ignore', '--print0']
    for excluded in ['.git', 'node_modules', '.cache', '.npm', '.cargo', '.rustup', 'go/pkg/mod', '.local/share/flatpak']:
        command.extend(['--exclude', excluded])
    result = subprocess.run([*command, '--', '.', *names], capture_output=True, text=True, timeout=8, check=True)
    folders = sorted(set([*names, *(path.rstrip('/') for path in result.stdout.split('\0') if path)]))
    directory.mkdir(parents=True, exist_ok=True)
    temporary = directory / f'folders-{os.getpid()}.json'
    temporary.write_text(json.dumps({'roots': names, 'time': time.time(), 'folders': folders}))
    temporary.replace(cache)
    return folders


def search(query, roots):
    roots = [Path(root).expanduser() for root in roots if Path(root).expanduser().is_dir()]
    if not query.strip():
        folders = list(roots)
        for root in roots:
            try:
                folders.extend(path for path in root.iterdir() if not path.name.startswith('.') and path.is_dir())
            except OSError:
                pass
        return sorted(set(str(path) for path in folders), key=str.casefold)[:100]
    if not roots:
        return []
    folders = catalog(roots)
    result = subprocess.run(['fzf', '--filter', query, '--scheme=path', '--read0', '--print0'],
                            input='\0'.join(folders) + '\0', capture_output=True, text=True, timeout=3,
                            env=dict(os.environ, FZF_DEFAULT_OPTS='', FZF_DEFAULT_OPTS_FILE=''))
    if result.returncode not in (0, 1):
        raise RuntimeError(result.stderr)
    return [path for path in result.stdout.split('\0') if path][:100]


if __name__ == '__main__':
    try:
        print(json.dumps({'folders': search(sys.argv[1], sys.argv[2:])}))
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError):
        print(json.dumps({'folders': [], 'error': 'Folder search unavailable'}))
