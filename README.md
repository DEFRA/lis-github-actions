# lis-github-actions

Shared, reusable GitHub Actions workflows for the Livestock Information Service (LIS) repositories.

## Node.js service workflows

Five `workflow_call` workflows replace the per-repository `support-*.yml` copies in the Node.js
service repositories (hubs, apps, fakes). A calling repository keeps thin `pull-request.yml`,
`prerelease.yml`, `release.yml` and `publish.yml` trigger workflows and points each job at a
workflow here.

| Workflow                     | Purpose                                                                                                  | Inputs                                                                                                                                    |
| ---------------------------- | -------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------- |
| `node-service-version.yml`   | Calculates the SemVer version from the branch name and tags with `version.cake`; outputs `version`       | `ref`, `branch`, `release-type` (`prerelease` or `stable`)                                                                                |
| `node-service-validate.yml`  | Runs the `Build` cake target, builds the production image, smoke tests `/health` and uploads the image   | `version`, `ref`, `smoke-port` (`3000`), `smoke-env` (one `KEY=VALUE` per line), `health-path` (`/health`), `dockerfile`, `image-target` |
| `node-service-sonar.yml`     | Runs tests with coverage and SonarCloud; outputs `quality-gate-status`                                   | `version`, `ref`, `branch`, `test-command` (`npm run test:coverage`); secret `LIS_SONAR_TOKEN`                                            |
| `node-service-tag.yml`       | Tags `ref` with `version` using the LIS release GitHub App; optionally moves the floating `v<major>` tag | `version`, `ref`, `major-tag` (`false`)                                                                                                   |
| `node-service-publish.yml`   | Pushes the image tested for the tagged commit to ECR and, for stable versions, Docker Hub                | none; reads `AWS_ACCOUNT_ID`, `AWS_REGION`, `ECR_REPOSITORY` from the caller's variables                                                   |

The calling repository must contain `version.cake`, `base.cake`, `build.cake`, `.nvmrc` and a
`Dockerfile`; the workflows check out the caller and run those scripts there. Secrets and
variables (`LIS_SONAR_TOKEN`, `LIS_RELEASE_APP_CLIENT_ID`, `LIS_RELEASE_APP_PRIVATE_KEY`,
`AWS_*`) resolve in the calling repository, so pass `secrets: inherit`.

### Example caller

```yaml
jobs:
  get-version:
    uses: DEFRA/lis-github-actions/.github/workflows/node-service-version.yml@v0
    with:
      ref: ${{ github.event.pull_request.head.sha }}
      branch: ${{ github.event.pull_request.head.ref }}
      release-type: prerelease

  validate:
    needs: get-version
    uses: DEFRA/lis-github-actions/.github/workflows/node-service-validate.yml@v0
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
requests tag the stable `X.Y.Z` and move the floating `v<major>` tag.

- Pin `@v<major>` to pick up fixes automatically.
- Pin a prerelease tag while testing a change to these workflows from a service branch.
- `uses:` references cannot be expressions, so the ref is fixed per calling workflow.

## Validation

Workflows are linted with [actionlint](https://github.com/rhysd/actionlint) on every pull
request and branch push. Locally:

```bash
docker run --rm --volume "$PWD:/repo" --workdir /repo rhysd/actionlint:1.7.7 -color
```
