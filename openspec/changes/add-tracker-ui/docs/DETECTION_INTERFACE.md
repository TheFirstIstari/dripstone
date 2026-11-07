<!-- Contract doc for the alert-intake capability; examples are parsed by tests. -->
# Detection interface: reporting findings

**Status: draft, to agree with the detection owner.** This is the one contract between
detection (AI plus heuristics) and the app. Change it freely while the detection design
settles; the UI only depends on what the app builds from it.

Detection reports what it found as a **finding**. The app turns findings into alerts,
keeps networks up to date, and handles everything after that: de-duplication,
re-alerting after a dismissal, respecting analyst changes, and live updates.

## Calling it

```elixir
Dripstone.Tracker.report_finding(finding)
# => {:ok, result} | {:error, errors}
```

`finding` is a plain map with **all-atom or all-string keys**, so a decoded JSON payload
works as-is. How detection reaches this call (in-process, an Oban worker, an HTTP
endpoint) is not decided yet; the map is the same either way.

Detection doesn't need to say whether AI analysis or heuristics produced a finding.
Findings combine both, and there is no field for it.

## Interim: scorer assessments (what runs today)

> **Being replaced** by the openspec change `add-jev-intake` (it supersedes issues #49
> and #53). Read `openspec/changes/add-jev-intake/` before building on this section or
> on the finding format above.

Until this contract is agreed, the scorer's output goes straight into the tracker
without being turned into findings:

```
Dripstone.Workers.AssessWorker  (Oban job, args %{"adapter" => "stub_x", "handle" => "..."})
  -> adapter.fetch_posts(handle)
  -> Dripstone.Scorer.assess(posts)        # %{score, labels, ai_answers, source}
  -> Dripstone.Tracker.record_assessment(%{feed_id:, handle:, posts:, assessment:})
```

`record_assessment/1` (see `Dripstone.Tracker.Assessments`):

- creates or updates the account: risk score = `score`, signals = `labels` (no
  per-signal contribution), with `ai_answers` and `source` kept as they are;
- replaces the account's posts with the scored ones;
- raises (or updates) a **`scorer_assessment`** alert on a single-member
  placeholder network named "@handle (unsorted)". The evidence is the raw output,
  one line per value (`source: heuristics_plus_ai`, `is_bot: 0.8`,
  `relation: shared-link`, ...).

Placeholders, to settle in the format discussion: severity (always Medium), the
alert title, evidence strength (always moderate), the one-network-per-account
grouping, and everything findings carry that the scorer doesn't give (network
names, summaries, before/after comparisons, the other four trigger types). In dev,
`DRIPSTONE_SIMULATE=1` queues one of these jobs every 2 minutes.

## Finding fields

| Field | Required | Type | Notes |
|---|---|---|---|
| `trigger` | yes | string | A trigger type id from the catalog (`openspec/changes/add-tracker-ui/docs/TRIGGERS.md`). |
| `severity` | yes | string | `low`, `medium` or `high`. |
| `title` | yes | string | Short headline shown in the alert list, up to 200 characters. |
| `observed_at` | yes | ISO 8601 date-time | When detection observed the evidence. Used for the dismissal rule. |
| `network_id` | one of | string | An existing network this finding is about. |
| `new_network` | one of | object | A newly detected network (see below). Give exactly one of `network_id` and `new_network`. |
| `evidence` | yes | list of objects | At least one item (see below). |
| `ai_rationale` | no | object | `{text, generated_at}`: AI-written explanation, shown labeled as AI-generated. |
| `comparison` | no | object | `{label, before, after}`: shown as before/after values on the alert. |
| `network_updates` | no | object | Changes to an existing network (see below). Only with `network_id`. |

**Evidence item:**

| Field | Required | Notes |
|---|---|---|
| `explanation` | yes | Plain-language description of what was found. |
| `strength` | yes | `weak`, `moderate` or `strong`. |
| `account_ids` | no | Account ids the evidence involves (default `[]`). |
| `kind` | no | `shared_link`, `near_duplicate`, `synced_posting`, `created_together` or `other` (default). Unknown kinds count as `other`. |

**`new_network`:**

| Field | Required | Notes |
|---|---|---|
| `id` | yes | Detection's stable id for the network. Must not already exist. |
| `name` | yes | Name to show until an analyst renames it. |
| `member_ids` | yes | Non-empty list of account ids. |
| `confidence` | yes | Integer 0–100. |
| `platforms` | no | Feed ids, e.g. `["x", "bluesky"]`. |
| `main_domain` | no | The domain the network mainly promotes. |
| `summary` | no | `{text, generated_at}`: AI-written network summary. |
| `evidence` | no | Network-level evidence; defaults to the finding's evidence. |

**`network_updates`** (all optional):

| Field | Notes |
|---|---|
| `add_member_ids` | Accounts that joined. Accounts an analyst removed are skipped. |
| `confidence` | New confidence, 0–100. |
| `main_domain` | New main promoted domain. |
| `name` | New name. Skipped if an analyst has renamed the network. |
| `summary` | New `{text, generated_at}` summary. |

## What the app does with a finding

1. **Stale check.** If the network is dismissed and `observed_at` is at or before the
   dismissal, the finding is ignored (`action: :ignored`, `reason: :predates_dismissal`).
2. **Network.** `new_network` creates a Suspected network. `network_updates` are
   applied to an existing one, except where an analyst's change takes priority.
3. **Alert.** If the network already has an **open** alert for the same trigger, the
   finding is merged into it (evidence added, severity raised if higher). Otherwise a
   new open alert is created. On a dismissed network it is marked "previously
   dismissed" and the network goes back to Suspected.
4. **History and live updates.** Changes are recorded in the network's history as
   `System` and pushed to open screens.

## Results

Success:

```elixir
{:ok,
 %{
   action: :created | :merged | :ignored,
   alert: %Dripstone.Tracker.Alert{} | nil,  # nil when ignored
   network_id: "net-example",
   skipped: [%{account_id: "acc-0007", reason: :removed_by_analyst},
             %{field: :name, reason: :set_by_analyst}],
   reason: nil | :predates_dismissal
 }}
```

Rejection, with nothing changed. `errors` maps each field to its messages:

```elixir
{:error, %{trigger: ["unknown trigger \"does-not-exist\""],
           evidence: ["must contain at least one item"]}}
```

| Problem | Error |
|---|---|
| Trigger not in the catalog | `trigger: unknown trigger "…"` |
| No evidence | `evidence: must contain at least one item` |
| Bad evidence item | `evidence: item N: strength must be weak, moderate or strong` (etc.) |
| Severity not low/medium/high | `severity: must be low, medium or high` |
| Missing `trigger`, `severity`, `title` or `observed_at` | `<field>: can't be blank` |
| Unknown `network_id` | `network_id: unknown network "…"` |
| Neither or both of `network_id`/`new_network` | `network_id: give network_id or new_network[, not both]` |
| `new_network` id already used | `new_network: network "…" already exists` |
| `network_updates` with `new_network` | `network_updates: only apply to an existing network_id` |
| Unknown member `new_network.member_ids` / `network_updates.add_member_ids` | `new_network: unknown account "…"` / `network_updates: unknown account "…"` |
| Mixed atom and string keys | `base: keys must be all atoms or all strings` |

## Examples

One per initial trigger type, as JSON. They run in order against an empty app
pre-seeded with tracked accounts acc-0001..acc-0006: the first creates
`net-example`, and the others refer to it.

### `new_network`

```json
{
  "trigger": "new_network",
  "severity": "high",
  "title": "Cluster #0412 detected with 88% confidence",
  "observed_at": "2026-11-01T09:00:00Z",
  "new_network": {
    "id": "net-example",
    "name": "Cluster #0412",
    "member_ids": ["acc-0001", "acc-0002", "acc-0003", "acc-0004"],
    "confidence": 88,
    "platforms": ["x", "bluesky"],
    "main_domain": "deals-a.example",
    "summary": {
      "text": "Four recently created accounts promoting deals-a.example on a fixed schedule.",
      "generated_at": "2026-11-01T09:00:00Z"
    }
  },
  "evidence": [
    {
      "kind": "shared_link",
      "strength": "strong",
      "explanation": "All 4 accounts posted links to deals-a.example.",
      "account_ids": ["acc-0001", "acc-0002", "acc-0003", "acc-0004"]
    },
    {
      "kind": "created_together",
      "strength": "moderate",
      "explanation": "The accounts were created within the same week."
    }
  ],
  "ai_rationale": {
    "text": "New accounts posting the same links on a fixed schedule.",
    "generated_at": "2026-11-01T09:00:00Z"
  }
}
```

### `network_growth`

```json
{
  "trigger": "network_growth",
  "severity": "medium",
  "title": "Cluster #0412 gained 2 accounts",
  "observed_at": "2026-11-03T14:00:00Z",
  "network_id": "net-example",
  "evidence": [
    {
      "kind": "near_duplicate",
      "strength": "strong",
      "explanation": "2 new accounts post the network's promo copy.",
      "account_ids": ["acc-0005", "acc-0006"]
    }
  ],
  "comparison": {"label": "Members", "before": "4", "after": "6"},
  "network_updates": {"add_member_ids": ["acc-0005", "acc-0006"]}
}
```

### `network_reactivation`

```json
{
  "trigger": "network_reactivation",
  "severity": "medium",
  "title": "Cluster #0412 is posting again after 16 days",
  "observed_at": "2026-11-19T20:00:00Z",
  "network_id": "net-example",
  "evidence": [
    {
      "kind": "synced_posting",
      "strength": "strong",
      "explanation": "3 accounts posted within 2 hours after 16 days of silence.",
      "account_ids": ["acc-0001", "acc-0002", "acc-0005"]
    }
  ],
  "comparison": {"label": "Activity", "before": "Silent for 16 days", "after": "3 accounts active in 2 hours"}
}
```

### `promotion_shift`

```json
{
  "trigger": "promotion_shift",
  "severity": "high",
  "title": "Cluster #0412 switched its main promoted domain",
  "observed_at": "2026-11-20T10:00:00Z",
  "network_id": "net-example",
  "evidence": [
    {
      "kind": "shared_link",
      "strength": "strong",
      "explanation": "Share of links to deals-b.example rose from 4% to 55% in 5 days.",
      "account_ids": ["acc-0001", "acc-0002", "acc-0003"]
    },
    {
      "strength": "moderate",
      "explanation": "deals-b.example was registered 3 days before the switch."
    }
  ],
  "ai_rationale": {
    "text": "Same copy and schedule with a newly registered domain: likely the same operator rotating domains.",
    "generated_at": "2026-11-20T10:00:00Z"
  },
  "comparison": {
    "label": "Main promoted domain",
    "before": "deals-a.example (62% of links)",
    "after": "deals-b.example (55% of links)"
  },
  "network_updates": {"main_domain": "deals-b.example", "confidence": 91}
}
```
