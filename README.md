# Dripstone

Botfarm social tracker. Phoenix 1.8, Postgres 17, Oban for background jobs.

## Live

https://dripstone.dev. It runs on a CachyOS box and reaches the public
internet through a Cloudflare Tunnel.

## Setup

Prereqs: `mise`, Docker.

```sh
mise install
cp .env.example .env
mise run db-up
mise run db-setup
mise run dev
```

Before `db-setup`, put a password (min 12 chars) in `.env` for the seed analyst:

```sh
# Generate one (macOS/Linux), or pick any 12+ char dev-only password:
openssl rand -base64 18
ANALYST_PASSWORD=<dev-only-password>
```

Then open http://localhost:4000.

No key needed for a green suite: with `OPENCODE_API_KEY` unset, AI calls fail to
`{:error, _}` and the app falls back to heuristics; tests stub the AI client.
`mise run test` is green on a fresh clone with an empty `.env`.

`docs/CACHYOS.md` has workstation and runner notes. The old desktop GPU
setup is archived at `docs/archive/desktop.md` and no longer used.

## Data: Live and Demo

Every analyst switches between two datasets from the sidebar (per session, no
restart):

- **Live**: the database, filled only by real detection. In production it starts
  empty. Locally it does too; if your dev database was seeded with sample rows
  before this, run `mix ecto.reset` once (then re-run `mise run db-setup`).
- **Demo**: the sample data plus a simulator raising alerts every ~45 s, kept in
  memory only and never stored. A "Demo data" banner shows while it's on.

## Live discovery (Bluesky and Mastodon)

Two real feeds, no credentials. Bluesky's public Jetstream is streamed, and the public
timelines of a few open Mastodon instances (mostly federated posts; list in config
`Dripstone.Discovery, mastodon_instances`) are polled every 30 s. A link posted by 5+
distinct accounts within 10 minutes becomes a candidate group, whose accounts are
fetched from their home server and assessed by Jev into Live. On in production;
locally:

```sh
DRIPSTONE_DISCOVERY=1 mise run dev
```

Caps (config `Dripstone.Discovery.Caps`): 20 groups an hour, an account at most once
a day, groups trimmed to 10 accounts (`Dripstone.Workers.DiscoverWorker`,
`max_group_size`). Burst settings live in `Dripstone.Discovery.Bursts`. Active live
networks get a trend re-check every 6 hours (Oban Cron).

## AI key

AI decisions come from OpenCode Console, model `jev-1.13-free`.

Each contributor mints their own Jev-scoped key in the Console and puts it
in their own `.env` (gitignored):

```sh
OPENCODE_API_KEY=<your-key>
```

`mise.toml` sets the model and endpoint defaults on purpose but never sets
`OPENCODE_API_KEY`. No key values or tokens belong in the repo.

## Commands

```sh
mise run test   # tests
mise run ci     # lint + build + test, same as CI
mise tasks ls   # all tasks
```

## Work tracking

Work is tracked in GitHub issues under epic #1. The epic body lists the
execution waves; follow that order when picking up issues.

## Specs

`openspec/specs/` is the source of truth for behavior and topology.
Read the project and deploy specs before changing either.

## Deploy

Prod is three containers on the CachyOS host: app, Postgres 17, tunnel.
Redeploys are pull, rebuild, migrate, restart. Full layout, env file
handling, and checks live in `openspec/specs/deploy/spec.md`.
