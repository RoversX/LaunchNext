#!/usr/bin/env python3
"""Build the production grid with an isolated, in-memory verification entry point."""
import argparse
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--record', action='store_true', help='record only the verification window')
parser.add_argument('--hover-rebuild-only', action='store_true', help='check highlight restoration without requiring display-link animation frames')
parser.add_argument('--guardrails-only', action='store_true', help='check preference migration, merge cleanup, and dissolve bitmap reuse')
args = parser.parse_args()
root = Path(__file__).resolve().parents[2]
with tempfile.TemporaryDirectory(prefix='launchnext-merge-integration-') as temporary:
    work = Path(temporary)
    for name in ['LaunchNext', 'LaunchNext.xcodeproj']:
        shutil.copytree(root / name, work / name)
    for item in root.iterdir():
        if item.name.startswith('.') or item.name in ['LaunchNext', 'LaunchNext.xcodeproj', 'build', 'Archive']:
            continue
        (work / item.name).symlink_to(item, target_is_directory=item.is_dir())
    entry = work / 'LaunchNext/LaunchpadApp.swift'
    original = entry.read_text()
    marker = '@main\nstruct LaunchpadApp'
    if original.count(marker) != 1:
        raise RuntimeError('App entry point changed; update this verifier before running it.')
    entry.write_text(original.replace(marker, 'struct LaunchpadApp', 1))
    shutil.copy2(root / 'scripts/diagnostics/FolderMergeIntegration.swift', work / 'LaunchNext/')
    derived = work / 'DerivedData'
    log = Path('/tmp/launchnext-folder-merge-integration-build.log')
    with log.open('w') as output:
        result = subprocess.run(['xcodebuild', 'build', '-project', str(work / 'LaunchNext.xcodeproj'),
                                 '-scheme', 'LaunchNext', '-configuration', 'Debug',
                                 '-derivedDataPath', str(derived), '-destination', 'platform=macOS',
                                 'CODE_SIGNING_ALLOWED=NO'], stdout=output, stderr=subprocess.STDOUT)
    if result.returncode:
        raise RuntimeError(f'Build failed; see {log}')
    binary = derived / 'Build/Products/Debug/LaunchNext.app/Contents/MacOS/LaunchNext'
    command = [str(binary)] + (['--record'] if args.record else [])
    if args.hover_rebuild_only:
        command.append('--hover-rebuild-only')
    if args.guardrails_only:
        command.append('--guardrails-only')
    environment = dict(os.environ, LLVM_PROFILE_FILE=str(work / "merge-%p.profraw"))
    subprocess.run(command, check=True, timeout=60, env=environment, cwd=work)
