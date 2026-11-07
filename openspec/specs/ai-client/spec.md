# AI Client

## Purpose
Minimal client for the internal OpenAI-compatible chat endpoint
(`Dripstone.AIClient`), Req-only, with mock fallback so dev/test/CI never
depend on the GPU box.

## Requirements

### Requirement: Complete contract
`Dripstone.AIClient.complete/2` SHALL POST `{model, messages}` to
`{base}/chat/completions` and return `{:ok, content}` on a 200 response with
a first choice message.

#### Scenario: Successful completion
- **WHEN** the endpoint returns 200 with `choices[0].message.content`
- **THEN** `complete/2` returns `{:ok, content}`

### Requirement: Req-only transport
The client SHALL use Req exclusively with a 30s receive timeout and no
retries, reading the base URL from `INTERNAL_AI_URL` (default
`http://desktop:8000/v1`) and the model from the `:model` opt or
`INTERNAL_AI_MODEL` (default `Qwen/Qwen3-8B-AWQ`).

#### Scenario: Transport configuration
- **WHEN** `complete/2` issues the request
- **THEN** it uses `Req.post` with `receive_timeout: 30_000` and `retry: false`
  against the configured base URL and model

### Requirement: Mock fallback
Any error, non-200 response, or exception SHALL log a `Logger.warning` and
return `{:ok, "[mock] #{prompt}"}`.

#### Scenario: Unreachable host
- **WHEN** `INTERNAL_AI_URL` points at an unreachable host (e.g. `127.0.0.1:9`)
- **THEN** `complete("hello")` returns `{:ok, "[mock] hello"}` (covered by
  `test/dripstone/ai_client_test.exs`)
