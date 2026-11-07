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
The deployment SHALL use a CachyOS x86_64 host fronted by Tailscale + Caddy,
with AI via OpenCode Console over HTTPS (no GPU node).

#### Scenario: Topology documented
- **WHEN** a contributor reads this spec
- **THEN** the host (CachyOS x86_64), edge (Tailscale + Caddy), and AI path
  (OpenCode Console over HTTPS, no GPU node) are identified

### Requirement: AI decisions endpoint
The app SHALL call the Console systemone endpoint with
`{model, state, questions}` using `jev-1.13-free` by default.

#### Scenario: Decision round-trip
- **WHEN** the app posts `{model, state, questions}` to the systemone endpoint
- **THEN** it receives an answers map for the typed questions
