# Project

## Purpose
Botfarm social tracker built on Elixir Phoenix 1.8 with Postgres 17 and Oban.
Hosted on a CachyOS x86_64 host fronted by Tailscale + Caddy. AI decisions come
from OpenCode Console (Jev); no self-hosted GPU anywhere.

## Requirements

### Requirement: Runtime stack
The system SHALL run on Elixir Phoenix 1.8 with Postgres 17 and Oban for
background jobs, as declared in `mix.exs` and `docker-compose.yml`.

#### Scenario: Stack declaration
- **WHEN** a contributor inspects `mix.exs` and `docker-compose.yml`
- **THEN** Phoenix ~> 1.8, Oban ~> 2.19, and a Postgres 17 `db` service are declared

### Requirement: Host topology
The deployment SHALL use a CachyOS x86_64 host fronted by Cloudflare Tunnel,
with public URL https://dripstone.dev and AI via OpenCode Console over HTTPS
(no GPU node).

#### Scenario: Topology documented
- **WHEN** a contributor reads this spec
- **THEN** the host (CachyOS x86_64), edge (Cloudflare Tunnel), public URL
  (https://dripstone.dev), and AI path (OpenCode Console over HTTPS, no GPU
  node) are identified

### Requirement: AI decisions endpoint
The app SHALL call the Console systemone endpoint with
`{model, state, questions}` using `jev-1.13-free` by default.

#### Scenario: Decision round-trip
- **WHEN** the app posts `{model, state, questions}` to the systemone endpoint
- **THEN** it receives an answers map for the typed questions

### Requirement: Analyst login
The app SHALL have a login page (email + password) built on `mix phx.gen.auth`
(never hand-rolled crypto/sessions); all mutation routes (confirm/dismiss/curation)
and the app shell SHALL require a logged-in analyst; the MVP SHALL have a single
analyst role; session timeout SHALL follow the generator defaults. This replaces
the Cloudflare-Access option for the app gate (edge stays open, app closed).

#### Scenario: Logged-out visitor redirected
- **WHEN** a logged-out visitor hits `/alerts`
- **THEN** they are redirected to the login page

#### Scenario: Logged-in analyst confirms alert
- **WHEN** a logged-in analyst confirms an alert
- **THEN** the confirmation is accepted and recorded

### Requirement: Scraper datasets
Each platform SHALL have a fetcher module behind a shared `fetch_posts(handle, opts)`
behaviour returning `{:ok, posts} | {:error, reason}`; fetchers SHALL respect rate
limits/robots and back off on 429 (no hammering); every fetcher SHALL record real
responses once into versioned corpora under `priv/datasets/<platform>/<date>.jsonl`
via a refresh mix task, and tests SHALL run fixture-first against those files with
zero network. Each JSONL line SHALL be one post object with post fields plus
`fetched_at` (UTC ISO-8601 timestamp of capture) and `source`
(`"<platform>:<handle>"` string identifying origin).

#### Scenario: Refresh writes dated corpus
- **WHEN** the refresh mix task runs for a platform
- **THEN** it writes a new dated corpus file under `priv/datasets/<platform>/<date>.jsonl`

#### Scenario: Suite green with network disabled
- **WHEN** the test suite runs with network disabled
- **THEN** fetcher tests pass against the checked-in corpus fixtures with zero network calls
