# lis-github-actions

Shared, reusable GitHub Actions workflows for the Livestock Information Service (LIS) repositories.

## Actions

Composite actions run as a step inside the caller's own job, so they need no extra runner.

| Action           | Purpose                                                                                                          | Inputs                                                                                                                             |
| ---------------- | ---------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------- |
| `actions/version` | Calculates the SemVer version from the latest stable tag and the branch name; outputs `version`                 | `ref` (empty to use the workspace's existing checkout), `branch`, `release-type` (`prerelease` or `stable`)                        |
| `actions/build-test-dotnet` | Validates and applies the Liquibase changelog against a throwaway PostgreSQL when one exists; builds and tests the solution; once all of that passes, packages the changelog folder with its `db-migration-metadata:1.0.0` metadata and uploads it as `database-migrations-<version>`; packs and uploads NuGet packages when a project is packable; builds, smoke tests and uploads the production image when there is a `Dockerfile`; outputs `has-dockerfile`, `has-liquibase` (a changelog exists at `liquibase-changelog`), `migrations-artifact`, `migrations-artifact-url`, `has-nuget`, `image-ref`, `image-artifact`, `nuget-artifact-url` | `version`, `ref` (empty to use the workspace's existing checkout), `smoke-port` (`3000`), `smoke-env` (one `KEY=VALUE` per line), `smoke-postgres` (`auto`: on when a Liquibase changelog is detected; `true` or `false` to force), `liquibase-changelog` (`changelog/db.changelog.xml`; `liquibase.properties` beside it must set `liquibase.command.username`), `liquibase-version` (`5.0.1`), `liquibase-database` (`dbname`) |
| `actions/build-test-node` | Sets `version` in `package.json`, runs `npm ci`, the build and the tests; packs and uploads the package as `npm-packages-<version>` when `package.json` is not `"private": true`; builds (with a layer cache), smoke tests and uploads the production image when there is a `Dockerfile`; outputs `has-dockerfile`, `has-npm-package`, `image-ref`, `image-artifact`, `npm-artifact-url` | `version`, `ref` (empty to use the workspace's existing checkout), `build-command` (`npm run build --if-present`), `test-command` (`npm test`), `dockerfile` (`./Dockerfile`), `image-target` (`production`), `smoke-port` (`3000`, passed as `PORT` and published on the same host port), `health-path` (`/health`), `smoke-env` (one `KEY=VALUE` per line), `smoke-postgres` (`false`; `true` starts a PostgreSQL sidecar reachable as `postgres`) |
| `actions/publish-nuget` | Checks out the version tag, finds the `nuget-packages-<version>` artifact a successful `prerelease.yml` or `release.yml` run built for that commit, verifies its provenance, waits for that run to succeed and pushes the packages to NuGet.org with trusted publishing; outputs `build-run-id` | `version`, `nuget-username`, `github-token` (`github.token`) |
| `actions/sonar-dotnet` | Builds and tests with coverage under the SonarScanner for .NET and checks the SonarCloud quality gate; skipped for Dependabot pull request validation; outputs `quality-gate-status` | `version`, `ref` (empty to use the workspace's existing checkout, which needs `fetch-depth: 0`), `branch` (empty for pull request analysis), `sonar-exclusions` (`.github/**,tests/Endpoints/**`), `sonar-token` (pass `secrets.LIS_SONAR_TOKEN`), `github-token` (`github.token`) |
| `actions/sonar-node` | Runs `npm ci` and the tests with LCOV coverage, checks `coverage/lcov.info` has source records, analyses with the SonarScanner CLI and checks the SonarCloud quality gate; skipped for Dependabot pull request validation; outputs `quality-gate-status`. The calling repository needs a `sonar-project.properties` with the project key and organisation | `version`, `ref` (empty to use the workspace's existing checkout, which needs `fetch-depth: 0`), `branch` (empty for pull request analysis), `test-command` (`npm run test:coverage`), `sonar-exclusions` (empty to use `sonar-project.properties`), `sonar-token` (pass `secrets.LIS_SONAR_TOKEN`), `github-token` (`github.token`) |
| `actions/tag` | Checks out `ref` with the LIS release GitHub App token, tags it with `version` and pushes the tag, so the push triggers the repository's tag workflows | `version`, `ref`, `app-client-id` (pass `vars.LIS_RELEASE_APP_CLIENT_ID`), `app-private-key` (pass `secrets.LIS_RELEASE_APP_PRIVATE_KEY`) |

With `ref` set, `actions/version` checks out that ref with all history and tags, replacing whatever the
job had checked out. Leave `ref` empty to calculate from a checkout the job already made; the action then
fetches the tags itself.

`actions/build-test-dotnet` names the image artifact `container-image-<commit SHA>` after the commit it
built, which is what `container-publish.yml` looks up, and the NuGet artifact `nuget-packages-<version>`,
which is what `actions/publish-nuget` looks up. It needs `jq`, `python3` and Docker on the runner
(`ubuntu-latest` has them).

An action cannot set job settings, so the job running `actions/publish-nuget` must grant
`actions: read` (to find and download the artifact) and `id-token: write` (for trusted publishing),
and should run in the `release` environment that holds `NUGET_USERNAME`:

```yaml
jobs:
  publish-nuget:
    runs-on: ubuntu-latest
    environment: release
    permissions:
      actions: read
      contents: read
      id-token: write
    steps:
      - uses: DEFRA/lis-github-actions/actions/publish-nuget@0.10.0
        with:
          version: ${{ github.ref_name }}
          nuget-username: ${{ secrets.NUGET_USERNAME }}
```

## Workflows

`workflow_call` workflows replace the per-repository `support-*.yml` copies. A calling repository
keeps thin `pull-request.yml`, `prerelease.yml`, `release.yml` and `publish.yml` trigger workflows
and points each job at a workflow here. Names say how widely a workflow applies: unprefixed
workflows suit every LIS repository (or every service, for `container-publish`), `node-*` and
`dotnet-*` every repository of that language, `node-service-*` and `dotnet-service-*` the services
of that language that ship a container image, and `npm-package-*` the npm packages.

| Workflow                     | Purpose                                                                                                  | Inputs                                                                                                                                    |
| ---------------------------- | -------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------- |
| `node-service-validate.yml`  | Runs the `Build` cake target and, alongside it, builds the production image with a layer cache, smoke tests `/health` and uploads the image | `version`, `ref`, `smoke-port` (`3000`), `smoke-env` (one `KEY=VALUE` per line), `health-path` (`/health`), `dockerfile`, `image-target` |
| `node-sonar.yml`     | Runs tests with coverage and SonarCloud; outputs `quality-gate-status`                                   | `version`, `ref`, `branch`, `test-command` (`npm run test:coverage`); secret `LIS_SONAR_TOKEN`                                            |
| `dotnet-service-validate.yml` | Runs an optional pre-build cake script, the `Build` cake target, builds the image with `PackOnly`, smoke tests and uploads it | `version`, `ref`, `pre-build-cake-script`, `pre-build-cake-target` (`Default`), `smoke-port` (`3000`), `smoke-env`, `smoke-postgres` (`false`), `health-path` |
| `dotnet-sonar.yml`           | Builds, tests with OpenCover coverage and runs SonarCloud; outputs `quality-gate-status`                  | `version`, `ref`, `branch`, `sonar-exclusions`; secret `LIS_SONAR_TOKEN`                                                                  |
| `npm-package-validate.yml`   | Runs the `Build` cake target for an npm package                                                          | `version`, `ref`                                                                                                                          |
| `npm-package-publish.yml`    | Validates the tag, packs the tagged source with the `PackOnly` cake target, checks the packed version and publishes to npmjs with trusted publishing (`latest` for stable, `alpha` for prerelease) | none; the caller's `publish.yml` must grant `id-token: write` |
| `container-publish.yml`      | Pushes the image tested for the tagged commit to ECR and, for stable versions, Docker Hub; optionally packages database migrations to S3 | `migrations-path` (empty to skip); reads `AWS_ACCOUNT_ID` (variable, or `LIS_AWS_ACCOUNT_ID` secret), `AWS_REGION`, `ECR_REPOSITORY` from the caller |

`container-publish.yml` needs the caller's token to carry `actions: read` and `id-token: write`
(plus `contents: read`); a reusable workflow can only reduce the caller's permissions, so the
caller's `publish.yml` must grant them:

```yaml
on:
  push:
    tags:
      - '*.*.*'

permissions:
  actions: read
  contents: read
  id-token: write

jobs:
  publish:
    uses: DEFRA/lis-github-actions/.github/workflows/container-publish.yml@0.1.0
    secrets: inherit
```

The calling repository must contain `version.cake`, `base.cake` and `build.cake` (plus `.nvmrc` and a
`Dockerfile` for Node.js services); the workflows check out the caller and run those scripts there. Secrets and
variables (`LIS_SONAR_TOKEN`, `AWS_*`) resolve in the calling repository, so pass `secrets: inherit`.
Actions cannot read the caller's secrets, so pass them as inputs instead, for example
`app-private-key: ${{ secrets.LIS_RELEASE_APP_PRIVATE_KEY }}` to `actions/tag`.

### Example caller

```yaml
jobs:
  get-version:
    runs-on: ubuntu-latest
    permissions:
      contents: read
    outputs:
      version: ${{ steps.version.outputs.version }}
    steps:
      - id: version
        uses: DEFRA/lis-github-actions/actions/version@0.10.0
        with:
          ref: ${{ github.event.pull_request.head.sha }}
          branch: ${{ github.event.pull_request.head.ref }}
          release-type: prerelease

  validate:
    needs: get-version
    uses: DEFRA/lis-github-actions/.github/workflows/node-service-validate.yml@0.1.0
    with:
      version: ${{ needs.get-version.outputs.version }}
      ref: ${{ github.event.pull_request.head.sha }}
      smoke-port: '3101'
      smoke-env: |
        HUB_JWT_SECRET=ci-smoke-test-hub-jwt-secret-0123456789
        SESSION_COOKIE_PASSWORD=ci-smoke-test-session-cookie-password-0123456789

  sonar-analysis:
    needs: get-version
    uses: DEFRA/lis-github-actions/.github/workflows/node-sonar.yml@0.1.0
    with:
      version: ${{ needs.get-version.outputs.version }}
      ref: ${{ github.event.pull_request.head.sha }}
    secrets: inherit
```

`sonar-analysis` needs only `get-version`: it installs and runs the tests itself, so it has
nothing to wait for from `validate`, and running the two side by side takes the longer of them
off the wall clock rather than the sum. Jobs that gate on both, such as the tag or the required
checks, list both in `needs`.

## Versioning

This repository releases itself with the same pipeline as the services: pushes to
`feature/LREG-*` and `hotfix/LREG-*` branches tag `X.Y.Z-lreg-N.alpha.M` prereleases, merged pull
requests tag the stable `X.Y.Z`.

- Pin the exact stable version (`@0.1.0`), as the repositories do for their npm dependencies, so a
  change here only reaches a pipeline through a reviewed bump; Dependabot's `github-actions`
  ecosystem raises those bumps.
- Pin a prerelease tag while testing a change to these workflows from a service branch.
- `uses:` references cannot be expressions, so the ref is fixed per calling workflow.

## Dependabot

`version.cake` accepts `dependabot/**` branches as a patch bump with the `dependabot` story id, so
Dependabot pull requests pass validation; they are never tagged because the prerelease workflow
only runs for `feature/**` and `hotfix/**` pushes. SonarCloud analysis is skipped on Dependabot
pull requests because the Dependabot secrets store has no `LIS_SONAR_TOKEN`: the Sonar workflows
declare that secret optional (a required secret fails the call itself, before any step can skip)
and skip the scan and quality gate steps for the `dependabot[bot]` actor. Merge them as a user
rather than with `@dependabot merge`, so the release workflow runs with the real secrets and can
tag and publish. The `.github/dependabot.yml` in every LIS repository, this one included, is
managed by `lis-github-monitor`.

## Validation

Workflows are linted with [actionlint](https://github.com/rhysd/actionlint) on every pull
request and branch push. Locally:

```bash
docker run --rm --volume "$PWD:/repo" --workdir /repo rhysd/actionlint:1.7.7 -color
```
