# Deploy

## Purpose
Production deploy of dripstone.dev on the CachyOS host via user-level Docker +
Cloudflare Tunnel, reproducible from scratch from any checkout of this repo.

## Requirements

### Requirement: Host
Production SHALL run on the CachyOS x86_64 `cachyos-x8664` host on the tailnet,
with everything operating as the unprivileged `powerpc` user with Docker group
access — no sudo required.

#### Scenario: Unprivileged operation
- **WHEN** an operator deploys or maintains production on the host
- **THEN** all Docker, tunnel, and build steps run as the `powerpc` user with no sudo

### Requirement: Tunnel
Public ingress SHALL go through the Cloudflare Tunnel named `dripstone` (id
`bf7406ff-3d84-40df-8903-fe3a90ca836e`), using the `cloudflared` binary in
`~/.local/bin` (GitHub release download) and config
`~/.cloudflared/config.yml` with ingress for `dripstone.dev` and
`www.dripstone.dev` to `http://dripstone-app:4000` plus an `http_status:404`
catch-all; the credentials file stays on the host, never in the repo.

#### Scenario: Tunnel serves the app
- **WHEN** the tunnel runs with the host config
- **THEN** `dripstone.dev` and `www.dripstone.dev` route to the app container
  and unmatched hosts receive 404

### Requirement: DNS
The apex `dripstone.dev` and `www.dripstone.dev` SHALL be CNAMEs to the tunnel
(created via `cloudflared tunnel route dns`).

#### Scenario: DNS points at the tunnel
- **WHEN** an operator inspects DNS for `dripstone.dev` and `www.dripstone.dev`
- **THEN** both resolve as CNAMEs to the tunnel

### Requirement: App container
The `dripstone-app` container SHALL be built from the repo `Dockerfile`
(`dripstone:latest`), run on docker network `dripstone-net` with env from
`~/.dripstone-prod.env` (600 perms): `PHX_SERVER=true`, `PHX_HOST=dripstone.dev`,
`PORT=4000`, host-generated `SECRET_KEY_BASE`, `DATABASE_URL` to the prod db;
`OPENCODE_API_KEY` is optional — absent means AI calls fail to `{:error, _}` and
everything else works; it publishes only `127.0.0.1:4000`, uses restart
`unless-stopped`, and caps logs (`max-size=10m`, `max-file=3`).

#### Scenario: App runs from host env file
- **WHEN** the `dripstone-app` container starts on `dripstone-net`
- **THEN** it serves Phoenix on port 4000 bound to loopback only, reads its env
  from the 600-permission host env file, and restarts unless stopped

### Requirement: DB container
The `dripstone-prod-db` container (`postgres:17-alpine`) SHALL run on
`dripstone-net` with persistent volume `dripstone_prod_pgdata`; database
`dripstone_prod` is created once; schema is applied via
`/app/bin/dripstone eval "Dripstone.Release.migrate"` before (re)start.

#### Scenario: Migrations before start
- **WHEN** the operator redeploys or restarts the app
- **THEN** the migrate eval runs against `dripstone_prod` before the app
  (re)starts

### Requirement: Release files
The repo SHALL carry `Dockerfile`, `.dockerignore`, `lib/dripstone/release.ex`,
and `rel/` (phx.gen.release output) so any checkout builds the same image.

#### Scenario: Reproducible image
- **WHEN** an operator builds from a fresh checkout
- **THEN** `docker build -t dripstone:latest .` produces the release image with
  no extra host-side files needed

### Requirement: Redeploy
Redeploy SHALL go through the `deploy` GitHub workflow — automatically after a
green `ci` run on `main`, or via manual dispatch — which builds
`dripstone:latest`, runs the migrate eval, runs the seed-analysts eval (after
migrate, before recreate; requires `ANALYST_PASSWORD` in the host env),
recreates the `dripstone-app` container, and health-gates local `/` for a 200;
hand-run SSH (`git pull`, rebuild, migrate, restart — no image registry, no
orchestrator) remains as the documented fallback.

#### Scenario: Routine redeploy
- **WHEN** new commits land on `main` or an operator dispatches the workflow
- **THEN** the `deploy` workflow builds the image, migrates, seeds analysts,
  recreates the app container, and gates on a local 200, with hand-run SSH
  available as fallback

### Requirement: Boot survival
The Docker service SHALL be enabled at boot, and the `unless-stopped` policies
SHALL bring app + db + tunnel back after reboot.

#### Scenario: Reboot recovery
- **WHEN** the host reboots
- **THEN** Docker starts at boot and the app, db, and tunnel containers resume
  without manual steps

### Requirement: Backups
Nightly `pg_dump` of `dripstone_prod` off the volume SHALL exist with a tested
restore note (tracks issue #27; required before real data lands).

#### Scenario: Backup and restore documented
- **WHEN** an operator checks backup coverage for `dripstone_prod`
- **THEN** a nightly dump exists and the restore steps are documented and tested

### Requirement: Verification
Local `http://127.0.0.1:4000/` AND public `https://dripstone.dev/` +
`https://www.dripstone.dev/` SHALL return 200.

#### Scenario: Endpoints healthy
- **WHEN** the operator probes the local URL and both public URLs after deploy
- **THEN** all three return 200
