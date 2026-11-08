# Project

## Purpose
Botfarm social tracker built on Elixir Phoenix 1.8 with Postgres 17 and Oban.
Hosted on a CachyOS x86_64 host fronted by Cloudflare Tunnel. AI decisions
come from OpenCode Console (Jev); no self-hosted GPU anywhere.

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

### Requirement: Findings showcase dataset
The repo SHALL carry a small curated demo corpus under
`priv/datasets/showcase/` with linked accounts, their findings, and the
resulting relation labels, so the demo tells a story end to end (data in →
relations out). It SHALL be hand-built and versioned, separate from the
scraped corpora, and the overview screen SHALL be able to run on it.

#### Scenario: Loading the showcase renders linked networks
- **WHEN** the overview screen loads the showcase corpus
- **THEN** it renders linked networks with relation labels

### Requirement: Temporal dataset rules
Every dataset entity (accounts, edges, posts slices, decisions) SHALL carry
`first_seen_at`, `last_true_at`, `last_checked_at` (all UTC); edges are
immortal, labels versioned by timestamp; time-travel reads (graph as of date T)
SHALL be supported by filtering on those fields.

#### Scenario: Querying a network as of 30 days ago returns then-current edges
- **WHEN** a network is queried as of 30 days ago
- **THEN** it returns its then-current edges

### Requirement: Edge provenance
Every edge SHALL record the finding + question that produced it (finding id,
question name, model, timestamp) to support AI-generated labeling and
wrong-label tracing.

#### Scenario: An edge renders its provenance chain
- **WHEN** an edge is rendered
- **THEN** it shows its provenance chain (finding id, question name, model, timestamp)

### Requirement: Attention signals
Burst activity on quiet accounts SHALL pin slices from pruning and prioritize
Jev budget there; display confidence SHALL be computed at read time from
probability + age since `last_true_at` (no decay writes); each dated corpus
SHALL carry a manifest of what was true when, for reproducible eval.

#### Scenario: A spike pins data and surfaces the account for review
- **WHEN** a burst of activity occurs on a quiet account
- **THEN** its slices are pinned from pruning, Jev budget is prioritized there,
  and the account surfaces for review

### Requirement: Cleared state
Accounts investigated and found false SHALL render as Cleared (distinct from
unknown/uninvestigated) and SHALL stop consuming Jev budget and fetch cycles
until new activity arrives.

#### Scenario: Cleared account with fresh posts re-enters evaluation
- **WHEN** a Cleared account publishes fresh posts
- **THEN** it re-enters evaluation and consumes Jev budget again

### Requirement: Watcher corroboration
Accounts watched by multiple independent users SHALL get a small confidence
bump and pruning protection, weighted low enough that brigading cannot
manufacture truth.

#### Scenario: Third watcher bumps confidence without flipping a label
- **WHEN** a third independent user watches an already-watched account
- **THEN** its confidence bumps slightly without flipping any label alone

### Requirement: Circadian fingerprints
Time-of-day activity histograms, derived from stored timestamps at read time
(no new writes), SHALL feed the heuristics side as a bot signal before Jev
is consulted.

#### Scenario: Schedule-posting account outscores organic one at equal volume
- **WHEN** a schedule-posting account and an organic account with equal volume
  are scored by heuristics
- **THEN** the schedule-posting account scores higher as a bot signal

### Requirement: Change digest
A periodic per-user digest of new edges, flipped labels, and re-alerts SHALL
be produced from versioned history; the Jev-importance threshold decides
digest inclusion vs silent update (same rule as notifications).

#### Scenario: Week with one flipped label produces a one-item digest
- **WHEN** a week yields a single flipped label
- **THEN** the per-user digest contains that one item

### Requirement: Adversarial ledger
Evasion-shaped signals (synchronized renames, simultaneous quiet periods,
cross-platform migration) SHALL be first-class trigger types in the catalog.

#### Scenario: Three linked accounts renaming within an hour fires a trigger
- **WHEN** three linked accounts rename within an hour
- **THEN** an evasion trigger fires from the catalog

### Requirement: Holdout eval
One frozen corpus slice SHALL be excluded from all scorer tuning; metrics
are reported against it.

#### Scenario: Showcase gain with flat holdout reports the flat result
- **WHEN** a scorer change improves showcase metrics but holdout stays flat
- **THEN** the flat holdout result is the one reported

### Requirement: Parallel development
Each GitHub issue SHALL ship as its own PR against main so work proceeds in
parallel; every PR SHALL be CI-green before merge; merge order SHALL follow
the epic's execution waves (dependencies first); a PR SHALL close only its own
issue(s) via keywords and never bundle unrelated fixes.

#### Scenario: Parallel scorer and fetcher PRs merge cleanly
- **WHEN** two contributors open a scorer PR and a fetcher PR the same day
- **THEN** both merge against main with no conflicts and green CI on each
