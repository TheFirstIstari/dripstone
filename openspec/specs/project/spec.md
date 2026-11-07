# Project

## Purpose
Botfarm social tracker built on Elixir Phoenix 1.8 with Postgres 17 and Oban.
Hosted on a CachyOS x86_64 host fronted by Tailscale + Caddy. GPU inference
runs on the `desktop` node (WSL2, RTX 3090) via vLLM with an OpenAI-compatible
API on port 8000.

## Requirements

### Requirement: Runtime stack
The system SHALL run on Elixir Phoenix 1.8 with Postgres 17 and Oban for
background jobs, as declared in `mix.exs` and `docker-compose.yml`.

#### Scenario: Stack declaration
- **WHEN** a contributor inspects `mix.exs` and `docker-compose.yml`
- **THEN** Phoenix ~> 1.8, Oban ~> 2.19, and a Postgres 17 `db` service are declared

### Requirement: Host topology
The deployment SHALL use a CachyOS x86_64 host fronted by Tailscale + Caddy,
with GPU inference offloaded to the `desktop` node.

#### Scenario: Topology documented
- **WHEN** a contributor reads this spec
- **THEN** the host (CachyOS x86_64), edge (Tailscale + Caddy), and GPU node
  (`desktop`, WSL2, RTX 3090) are identified

### Requirement: GPU inference endpoint
The `desktop` node SHALL serve `Qwen/Qwen3-8B-AWQ` via vLLM with
`max-model-len 16384`, `max-num-seqs 16`, prefix caching enabled, and an
OpenAI-compatible API on port 8000.

#### Scenario: Endpoint reachable
- **WHEN** the app calls the internal AI URL with a chat-completions payload
- **THEN** the `desktop:8000` endpoint accepts the OpenAI-compatible request
