"""Prints a Markdown summary of the packages in artifacts/nuget for the step summary.

Reads PACKAGE_VERSION, SOURCE_REF and ARTIFACT_URL from the environment.
"""
import os
from pathlib import Path
import subprocess
import xml.etree.ElementTree as ET
import zipfile

print('### NuGet packages\n')
print('```text')
print(f'Requested version: {os.environ["PACKAGE_VERSION"]}')
print(f'Source ref: {os.environ["SOURCE_REF"] or "(workspace checkout)"}')
commit = subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip()
print(f'Commit: {commit}')
print(f'Artifact: nuget-packages-{os.environ["PACKAGE_VERSION"]}')
for package in sorted(Path('artifacts/nuget').glob('*.nupkg')):
    with zipfile.ZipFile(package) as archive:
        nuspec = next(name for name in archive.namelist() if name.endswith('.nuspec'))
        root = ET.fromstring(archive.read(nuspec))
        metadata = root.find('{*}metadata')
        print(f'\nPackage: {package.name} ({package.stat().st_size:,} bytes)')
        for field in ('id', 'version', 'tags'):
            value = metadata.findtext(f'{{*}}{field}') or '(none)'
            print(f'  {field}: {value}')
for symbols in sorted(Path('artifacts/nuget').glob('*.snupkg')):
    print(f'\nSymbols: {symbols.name} ({symbols.stat().st_size:,} bytes)')
print('```\n')
print(f'[Download workflow artifact]({os.environ["ARTIFACT_URL"]})')
