# AI Client

## Purpose
Client for the OpenCode Console decision endpoint (Jev 1.13, TypeSafe AI)
(`Dripstone.AIClient`), Req-only, with error-tuple fallback so dev/test/CI never
depend on the network.

## Requirements

### Requirement: Decide contract
`Dripstone.AIClient.decide/2` SHALL POST `{model, state, questions}` (typed
questions: `noul` yes/no, `choice` multiple-choice, `score` rubric) to
`{base}/systemone` with `Authorization: Bearer <key>` and return
`{:ok, answers}` on a 200 response carrying an answers map.

#### Scenario: Successful decision
- **WHEN** the endpoint returns 200 with an answers map
- **THEN** `decide/2` returns `{:ok, answers}`

### Requirement: Transport
The client SHALL use Req exclusively, reading the base URL from the environment
(default `https://opencode.ai/inference/systemone/v1`) and the model from the
`:model` opt or environment (default `jev-1.13-free`), with the key from
`OPENCODE_API_KEY` env only (never committed), a 30s receive timeout plus a
short connect timeout, and no retries.

#### Scenario: Transport configuration
- **WHEN** `decide/2` issues the request
- **THEN** it uses `Req.post` with `receive_timeout: 30_000`, a short connect
  timeout, and `retry: false` against the configured base URL, model, and
  bearer key

### Requirement: Paid fallback
Swapping `jev-1.13-free` → `jev-1.13` SHALL require only an env change (model id
+ key with balance), no code change.

#### Scenario: Free tier ends
- **WHEN** the free tier ends and the operator sets the paid model id and a
  funded key via env
- **THEN** decisions flow through `jev-1.13` with no code change

### Requirement: Failure mapping
Any error, non-200 response, or exception SHALL log a `Logger.warning` and
return `{:error, reason}` (callers fall back to heuristics-only, never to fake
answers).

#### Scenario: Unreachable host
- **WHEN** the endpoint is unreachable or returns a non-200 response
- **THEN** `decide/2` logs a warning and returns `{:error, reason}`

### Requirement: Seamless-ops limits
The state payload SHALL be capped (e.g. 8000 chars, well under the 64k
context); only public post data SHALL be sent in `state` (no private user
data, free-tier retention unknown); each call SHALL log model + latency.

#### Scenario: Oversized state is truncated before send
- **WHEN** `decide/2` is called with state exceeding the cap
- **THEN** the state is truncated to the cap before send and the call logs
  model + latency

### Requirement: Key scope and handling
The app SHALL use an OpenCode Console key restricted to Jev models only; the key
value lives exclusively in the local gitignored `.env` (and later in host env /
CI secrets only if a live test is ever added — the suite MUST stay green with no
key via offline doubles); `.env.example` carries only an empty
`OPENCODE_API_KEY=` placeholder; rotating the key is a secret-store change,
never a code change.

#### Scenario: Suite green with no key
- **WHEN** the suite runs with no key set
- **THEN** all tests pass via offline doubles and the app boots with the key
  absent (AI calls fail to `{:error, _}`, everything else works)

### Requirement: Testability
The 200-good-shape and 200-wrong-shape/error-mapping cases SHALL be covered
without network (Bypass or equivalent), per `test/dripstone/ai_client_test.exs`.

#### Scenario: Suite green offline
- **WHEN** the suite runs with no network access
- **THEN** the Bypass-backed decision and error-mapping cases pass

### Requirement: Relationship analysis
`decide/2` SHALL support link-analysis questions over pairs/groups of accounts:
a `noul` question asking whether the accounts are coordinated plus a `choice`
question classifying the relation (e.g. repost-ring, shared-link, timing-sync,
audience-overlap, none). State for these calls SHALL be the accounts' activity
summaries (posts, timestamps, shared domains), still under the 8000-char cap
and public-data-only.

#### Scenario: Two synced accounts return coordinated with relation label
- **WHEN** `decide/2` is called with activity summaries of two timing-synced accounts
- **THEN** it returns `coordinated=true` with a relation label and probability

### Requirement: Trend questions
`decide/2` SHALL accept time-series state (ordered activity summaries with
timestamps) and trend questions: a `noul` (is coordination increasing?) and a
`choice` trajectory label (e.g. forming, stable, fading, none). Same transport,
caps, and error mapping as other questions.

#### Scenario: Six weekly summaries return increasing with forming trajectory
- **WHEN** `decide/2` is called with six ordered weekly activity summaries
- **THEN** it returns `increasing=true` with trajectory `forming`
