# CI

## Purpose
Continuous integration pipeline for the project, defined in
`.github/workflows/ci.yml`.

## Requirements

### Requirement: Self-hosted runner
The CI workflow SHALL run on `runs-on: [self-hosted, Linux, X64]`.

#### Scenario: Runner labels
- **WHEN** a push to `main` or a pull request triggers the workflow
- **THEN** the `test` job executes on a self-hosted Linux X64 runner

### Requirement: Test pipeline
The workflow SHALL checkout, set up the toolchain via mise, install deps,
start the `db` compose service, wait with `pg_isready`, run `ecto.setup`,
and run the test suite.

#### Scenario: Pipeline steps
- **WHEN** the `test` job runs
- **THEN** it executes checkout, mise setup, `mix deps.get`,
  `docker compose up -d db`, `pg_isready` wait loop, `MIX_ENV=test mix
  ecto.setup`, and `MIX_ENV=test mix test` in order

### Requirement: Read-only permissions
The workflow SHALL declare `permissions: contents: read`.

#### Scenario: Permissions declared
- **WHEN** a contributor inspects `.github/workflows/ci.yml`
- **THEN** top-level `permissions.contents` is `read`
