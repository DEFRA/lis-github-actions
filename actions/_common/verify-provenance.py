"""Checks artifacts/provenance.json matches the checked-out commit, PACKAGE_VERSION and BUILD_RUN_ID.

It does not wait for the build run: the version tag is only created once that run's build and Sonar
jobs have passed, so the run is still finishing its tag job when this runs.

Reads PACKAGE_VERSION and BUILD_RUN_ID from the environment.
"""
import json
import os
import subprocess
import sys

PROVENANCE = 'artifacts/provenance.json'


def main():
    if not os.path.exists(PROVENANCE):
        print(f'{PROVENANCE} is missing from the artifact. Rebuild the version before publishing.',
              file=sys.stderr)
        return 1

    with open(PROVENANCE, encoding='utf-8') as file:
        provenance = json.load(file)

    expected = {
        'commit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip(),
        'version': os.environ['PACKAGE_VERSION'],
        'run_id': os.environ['BUILD_RUN_ID'],
    }
    for field, value in expected.items():
        if provenance.get(field) != value:
            print(f'{PROVENANCE} {field} is {provenance.get(field)!r}, expected {value!r}.', file=sys.stderr)
            return 1

    print(f'Provenance matches commit {expected["commit"]}, version {expected["version"]} '
          f'and build run {expected["run_id"]}.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
