"""Prints a Markdown summary of the packages in artifacts/npm for the step summary.

Reads PACKAGE_VERSION, SOURCE_REF, ARTIFACT and ARTIFACT_URL from the environment.
"""
import json
import os
from pathlib import Path
import subprocess
import tarfile

print('### npm packages\n')
print('```text')
print(f'Requested version: {os.environ["PACKAGE_VERSION"]}')
print(f'Source ref: {os.environ["SOURCE_REF"] or "(workspace checkout)"}')
commit = subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip()
print(f'Commit: {commit}')
print(f'Artifact: {os.environ["ARTIFACT"]}')
for package in sorted(Path('artifacts/npm').glob('*.tgz')):
    with tarfile.open(package) as archive:
        manifest = json.load(archive.extractfile('package/package.json'))
    print(f'\nPackage: {package.name} ({package.stat().st_size:,} bytes)')
    print(f'  name: {manifest.get("name") or "(none)"}')
    print(f'  version: {manifest.get("version") or "(none)"}')
    print(f'  keywords: {", ".join(manifest.get("keywords") or []) or "(none)"}')
print('```\n')
print(f'[Download workflow artifact]({os.environ["ARTIFACT_URL"]})')
