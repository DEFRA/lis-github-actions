"""Checks artifacts/provenance.json matches the checked-out commit, PACKAGE_VERSION and BUILD_RUN_ID,
then waits for the run attempt that uploaded the packages to finish successfully.

Reads GH_TOKEN, PACKAGE_VERSION, BUILD_RUN_ID and the standard GITHUB_* variables from the environment.
"""
import json
import os
import re
import subprocess
import sys
import time
import urllib.request

API_URL = os.environ.get('GITHUB_API_URL', 'https://api.github.com')
REPOSITORY = os.environ['GITHUB_REPOSITORY']
PROVENANCE = 'artifacts/provenance.json'
POLL_ATTEMPTS = 60
POLL_INTERVAL_SECONDS = 10


def get(url):
    request = urllib.request.Request(url, headers={
        'Accept': 'application/vnd.github+json',
        'Authorization': f'Bearer {os.environ["GH_TOKEN"]}',
        'X-GitHub-Api-Version': '2022-11-28',
    })
    with urllib.request.urlopen(request) as response:
        return json.load(response)


def fail(message):
    print(message, file=sys.stderr)
    return 1


def main():
    commit = subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip()
    with open(PROVENANCE, encoding='utf-8') as file:
        provenance = json.load(file)

    expected = {
        'commit': commit,
        'version': os.environ['PACKAGE_VERSION'],
        'run_id': os.environ['BUILD_RUN_ID'],
    }
    for field, value in expected.items():
        if provenance.get(field) != value:
            return fail(f'{PROVENANCE} {field} is {provenance.get(field)!r}, expected {value!r}.')

    attempt = str(provenance.get('run_attempt', ''))
    if not re.fullmatch(r'[1-9][0-9]*', attempt):
        return fail(f'{PROVENANCE} run_attempt {attempt!r} is not a positive integer.')

    # Pushing the tag starts this workflow before the tagging run finishes.
    # Check the exact attempt that uploaded the artifact, including on reruns.
    url = f'{API_URL}/repos/{REPOSITORY}/actions/runs/{expected["run_id"]}/attempts/{attempt}'
    for _ in range(POLL_ATTEMPTS):
        run = get(url)
        if run['status'] == 'completed':
            if run['conclusion'] == 'success':
                return 0
            return fail('The package build workflow did not succeed.')
        time.sleep(POLL_INTERVAL_SECONDS)
    return fail('Timed out waiting for package validation to complete.')


if __name__ == '__main__':
    sys.exit(main())
