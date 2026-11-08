# CI

## Purpose
Continuous integration pipeline for the project, defined in
`.github/workflows/ci.yml`.

## Requirements

### Requirement: Isolated runner pool
The CI workflow SHALL run on GitHub-hosted `runs-on: ubuntu-latest` so
PR-controlled code NEVER executes on the self-hosted deploy host (which holds
`~/.dripstone-prod.env` and the Docker daemon). Only the deploy workflow may
target the self-hosted `cachyos-x8664` + `deploy` labels.

#### Scenario: Runner labels
- **WHEN** a push to `main` or a pull request triggers the workflow
- **THEN** the `ci` job executes on a GitHub-hosted runner, not the deploy host

### Requirement: Test pipeline
The workflow SHALL checkout, set up the toolchain via mise, install deps,
start the `db` compose service, wait with `pg_isready`, run `ecto.create` +
`ecto.migrate`,
and run the test suite.

#### Scenario: Pipeline steps
- **WHEN** the `ci` job runs
- **THEN** it executes checkout, mise setup, `mix deps.get`,
  `docker compose up -d db`, `pg_isready` wait loop, `MIX_ENV=test mix
  ecto.create`, `MIX_ENV=test mix ecto.migrate`, and `MIX_ENV=test mix test` in order

### Requirement: Read-only permissions
The workflow SHALL declare `permissions: contents: read`.

#### Scenario: Permissions declared
- **WHEN** a contributor inspects `.github/workflows/ci.yml`
- **THEN** top-level `permissions.contents` is `read`
