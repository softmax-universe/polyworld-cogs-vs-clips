#!/usr/bin/env python3
"""Fetch dependencies into a private directory without editing siblings."""
import os
import pathlib
import subprocess

ROOT = pathlib.Path(__file__).resolve().parent.parent
DESTINATION = pathlib.Path(os.environ.get('POLYWORLD_DEPS', ROOT / '.deps')).resolve()
DESTINATION.mkdir(exist_ok=True)
resolved = []
for line in (ROOT / 'dependencies.lock').read_text().splitlines():
    name, version, url, revision = line.split()
    if name == 'polyworld':
        revision = os.environ.get('POLYWORLD_REVISION', revision)
    directory = DESTINATION / name
    if directory.exists() and not (directory / '.git').exists():
        raise SystemExit(f'Dependency must be a Git checkout: {directory}')
    if not directory.exists():
        subprocess.run(['git', 'init', str(directory)], check=True)
        subprocess.run(['git', '-C', str(directory), 'remote', 'add', 'origin', url], check=True)
    current = subprocess.run(['git', '-C', str(directory), 'rev-parse', 'HEAD'], capture_output=True, text=True)
    dirty = subprocess.check_output(['git', '-C', str(directory), 'status', '--porcelain'], text=True)
    if dirty:
        raise SystemExit(f'Refusing to replace modified dependency: {directory}')
    if current.returncode == 0 and current.stdout.strip() == revision:
        resolved.append(f'{name} {version} {url} {revision}')
        continue
    subprocess.run(['git', '-C', str(directory), 'fetch', '--depth=1', url, revision], check=True)
    subprocess.run(['git', '-C', str(directory), 'checkout', '--detach', 'FETCH_HEAD'], check=True)
    sha = subprocess.check_output(['git', '-C', str(directory), 'rev-parse', 'HEAD'], text=True).strip()
    resolved.append(f'{name} {version} {url} {sha}')
(DESTINATION / 'dependencies.lock').write_text('\n'.join(resolved) + '\n')
print(f'Dependencies ready. Set POLYWORLD_DEPS={DESTINATION}')
