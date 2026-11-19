"""Finds the newest unexpired ARTIFACT_NAME artifact uploaded by a prerelease push or release pull
request run for the checked-out commit, and writes its artifact-id and run-id to GITHUB_OUTPUT.

A prerelease push run's head_sha is the commit it tagged. A release run is triggered by the pull request
closing, so its head_sha is the pull request's head commit, while the stable tag is on the merge commit
it built; for those runs, the head commit of the merged pull request that produced the tagged commit
matches too.

Reads GH_TOKEN, ARTIFACT_NAME and the standard GITHUB_* variables from the environment.
"""
import json
import os
import re
import subprocess
import sys
import urllib.parse
import urllib.request

API_URL = os.environ.get('GITHUB_API_URL', 'https://api.github.com')
REPOSITORY = os.environ['GITHUB_REPOSITORY']
ARTIFACT_NAME = os.environ['ARTIFACT_NAME']

# PR validation also uploads packages; only publish release builds.
PRERELEASE_RUN = ('.github/workflows/prerelease.yml', 'push')
RELEASE_RUN = ('.github/workflows/release.yml', 'pull_request')


def get(url):
    """Returns the decoded JSON body and the next page URL from the Link header, if any."""
    request = urllib.request.Request(url, headers={
        'Accept': 'application/vnd.github+json',
        'Authorization': f'Bearer {os.environ["GH_TOKEN"]}',
        'X-GitHub-Api-Version': '2022-11-28',
    })
    with urllib.request.urlopen(request) as response:
        body = json.load(response)
        links = response.headers.get('Link') or ''
    next_page = re.search(r'<([^>]+)>;\s*rel="next"', links)
    return body, next_page.group(1) if next_page else None


def list_artifacts():
    query = urllib.parse.urlencode({'name': ARTIFACT_NAME, 'per_page': 100})
    url = f'{API_URL}/repos/{REPOSITORY}/actions/artifacts?{query}'
    while url:
        page, url = get(url)
        yield from page['artifacts']


def merged_pull_request_heads(commit):
    """Returns the head commits of the merged pull requests whose merge commit is commit."""
    heads = set()
    url = f'{API_URL}/repos/{REPOSITORY}/commits/{commit}/pulls?per_page=100'
    while url:
        page, url = get(url)
        heads.update(
            pull['head']['sha'] for pull in page
            if pull.get('merged_at') and pull.get('merge_commit_sha') == commit
        )
    return heads


def is_release_build(run, commit, release_heads):
    if run['status'] == 'completed' and run['conclusion'] != 'success':
        return False
    kind = (run['path'], run['event'])
    if kind == PRERELEASE_RUN:
        return run['head_sha'] == commit
    if kind == RELEASE_RUN:
        return run['head_sha'] == commit or run['head_sha'] in release_heads()
    return False


def main():
    commit = subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip()
    candidates = sorted(
        (a for a in list_artifacts() if a['name'] == ARTIFACT_NAME and not a['expired']),
        key=lambda a: a['created_at'],
        reverse=True,
    )

    # Looked up once, and only when a release run is among the candidates.
    cached_heads = []

    def release_heads():
        if not cached_heads:
            cached_heads.append(merged_pull_request_heads(commit))
            print(f'Merged pull request heads for {commit}: {sorted(cached_heads[0]) or "(none)"}')
        return cached_heads[0]

    for artifact in candidates:
        run_id = artifact['workflow_run']['id']
        run, _ = get(f'{API_URL}/repos/{REPOSITORY}/actions/runs/{run_id}')
        if not is_release_build(run, commit, release_heads):
            continue

        with open(os.environ['GITHUB_OUTPUT'], 'a', encoding='utf-8') as output:
            output.write(f'artifact-id={artifact["id"]}\nrun-id={run_id}\n')

        server_url = os.environ.get('GITHUB_SERVER_URL', 'https://github.com')
        summary = (
            '### Package artifact source\n\n'
            f'Artifact: `{ARTIFACT_NAME}`\n\n'
            f'[Build run]({server_url}/{REPOSITORY}/actions/runs/{run_id})\n'
        )
        print(summary, end='')
        with open(os.environ['GITHUB_STEP_SUMMARY'], 'a', encoding='utf-8') as step_summary:
            step_summary.write(summary)
        return 0

    print(
        f'No unexpired release artifact named {ARTIFACT_NAME} was found. '
        'Rebuild the version before publishing.',
        file=sys.stderr,
    )
    return 1


if __name__ == '__main__':
    sys.exit(main())
