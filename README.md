# lis-github-actions

Shared, reusable GitHub Actions workflows for the Livestock Information Service (LIS) repositories.

## Workflows

`workflow_call` workflows replace the per-repository `support-*.yml` copies. A calling repository
keeps thin `pull-request.yml`, `prerelease.yml`, `release.yml` and `publish.yml` trigger workflows
and points each job at a workflow here. Names say how widely a workflow applies: unprefixed
workflows suit every LIS repository (or every service, for `container-publish`), `node-*` and
`dotnet-*` every repository of that language, `node-service-*` and `dotnet-service-*` the services
of that language that ship a container image, and `npm-package-*` the npm packages.

| Workflow                     | Purpose                                                                                                  | Inputs                                                                                                                                    |
| ---------------------------- | -------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------- |
| `version.yml`   | Calculates the SemVer version from the branch name and tags with `version.cake`; outputs `version`       | `ref`, `branch`, `release-type` (`prerelease` or `stable`)                                                                                |
| `node-service-validate.yml`  | Runs the `Build` cake target, builds the production image, smoke tests `/health` and uploads the image   | `version`, `ref`, `smoke-port` (`3000`), `smoke-env` (one `KEY=VALUE` per line), `health-path` (`/health`), `dockerfile`, `image-target` |
| `node-sonar.yml`     | Runs tests with coverage and SonarCloud; outputs `quality-gate-status`                                   | `version`, `ref`, `branch`, `test-command` (`npm run test:coverage`); secret `LIS_SONAR_TOKEN`                                            |
| `tag.yml`       | Tags `ref` with `version` using the LIS release GitHub App                                               | `version`, `ref`                                                                                                                          |
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
variables (`LIS_SONAR_TOKEN`, `LIS_RELEASE_APP_CLIENT_ID`, `LIS_RELEASE_APP_PRIVATE_KEY`,
`AWS_*`) resolve in the calling repository, so pass `secrets: inherit`.

### Example caller

```yaml
jobs:
  get-version:
    uses: DEFRA/lis-github-actions/.github/workflows/version.yml@0.1.0
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
```

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
only runs for `feature/**` and `hotfix/**` pushes. The `.github/dependabot.yml` in every LIS
repository, this one included, is managed by `lis-github-monitor`.

## Validation

Workflows are linted with [actionlint](https://github.com/rhysd/actionlint) on every pull
request and branch push. Locally:

```bash
docker run --rm --volume "$PWD:/repo" --workdir /repo rhysd/actionlint:1.7.7 -color
```
