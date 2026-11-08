<!-- Contract doc for the alert-intake capability; examples are parsed by tests. -->
# Detection interface: reporting findings

This is the one contract between detection (heuristics plus the Jev decision model)
and the app. Detection reports **what it measured**: its heuristics, and Jev's
answers exactly as `Dripstone.AIClient.decide/3` returned them. The app decides what
that means. It turns findings into accounts, links and alerts, and handles everything
after that: de-duplication, re-alerting after a dismissal, respecting analyst changes,
and live updates.

Jev answers typed questions and writes no text, so findings carry no titles, severities
or prose. The app writes those from the answers, using the rules below.

## Calling it

```elixir
Dripstone.Tracker.report_finding(finding)
# => {:ok, result} | {:error, errors}
```

`finding` is a plain map with **all-atom or all-string keys**, so a decoded JSON payload
works as-is. In the app, `Dripstone.Workers.AssessWorker` (an Oban job) is the caller
for account findings. The AI client may only run in jobs like that, never in LiveView
or request processes.

## Finding kinds

Every finding has these fields:

| Field | Required | Type | Notes |
|---|---|---|---|
| `kind` | yes | `"account"`, `"group"` or `"trend"` | Which question set was asked. |
| `observed_at` | yes | ISO 8601 date-time | When detection made the measurement. |
| `model` | no | string | The model that answered, e.g. `"jev-1.13"`. Recorded with links and alerts. |
| `answers` | no | map or `null` | Jev's answers map, untouched. `null` when the AI was unavailable (heuristics only). |
| `heuristics` | no | map | `score` (0–100), `labels` (strings), `domains` (list of `{domain, share}`, share 0–1). |

### Account: one account's posts

| Field | Required | Notes |
|---|---|---|
| `account` | yes | `{feed_id, handle}`. `feed_id` is a registered feed (`x`, `reddit`, ...). Unknown accounts are created. |
| `posts` | no | The assessed posts: `{id, published_at, urls, text}`. They're merged into the account's history by `id`, so earlier posts are kept. |

The app sets the account's risk score from `heuristics.score` and its signals from
`heuristics.labels` plus the `is_bot`, `spam` and `topic` answers. **Account findings
never raise an alert on their own.** Alerts are about networks.

### Group: accounts checked together

| Field | Required | Notes |
|---|---|---|
| `accounts` | yes | Two or more `{feed_id, handle}`. Keep it to about 10, so their activity fits the AI client's 8,000-character state limit. |
| `network_id` | no | The known network these accounts were checked as. Without it, the app uses the network that holds more than half of them, if any. |

### Trend: a known network over time

| Field | Required | Notes |
|---|---|---|
| `network_id` | yes | The network whose activity was summarized. |
| `window` | no | `{from, to}`, for the record. |

## Questions the app understands

Ask them with exactly these names and labels. Every `choice` and `score` question must
carry `criteria` (Jev rejects them otherwise). Answers to any other question are kept
and shown, but don't affect alerts.

| Finding | Question | Type | Labels / levels |
|---|---|---|---|
| account | `is_bot` | `noul` | – |
| account | `spam` | `score` | 3 levels, lowest first (e.g. not spam, somewhat spammy, heavy spam) |
| account | `topic` | `choice` | free labels, e.g. `crypto`, `politics`, `tech`, `sports`, `entertainment`, `other` |
| group | `coordinated` | `noul` | – |
| group | `relation` | `choice` | `repost-ring`, `shared-link`, `timing-sync`, `audience-overlap`, `none` |
| group | `member:<feed_id>:<handle>` | `noul` | optional, one per account: does this account take part? |
| trend | `increasing` | `noul` | – |
| trend | `trajectory` | `choice` | `forming`, `stable`, `fading`, `none` |

The app reads Jev's answer shapes as follows:
- **`noul`** is a probability (0–1).
- **`choice`** is a label, with its `confidence` and `probabilities`.
- **`score`** is an *expected level* from 0 to (levels − 1). The app divides it by the
  highest level to get 0–1.

## Rules

Thresholds are in `config :dripstone, Dripstone.Tracker.Rules`:
- **Yes:** an answer counts as yes at 0.7 or above.
- **Severity:** High at 0.9 or above, Medium at 0.8 or above, otherwise Low.
- **Evidence strength:** Strong at 0.85 or above, Moderate at 0.7 or above, otherwise
  Weak.

| Finding | When | Alert |
|---|---|---|
| group | `coordinated` ≥ yes, no network yet | **New network** with the members (`member:` answers below yes are left out). Confidence = `coordinated` × 100; severity from `coordinated`. The name is a placeholder ("Crypto cluster on X"), which analysts can rename. |
| group | `coordinated` ≥ yes, known network, accounts not yet in it | **Network growth**, with the member count before and after. Accounts an analyst removed are skipped. |
| group | known network, top domain ≥ 50% of links, different from its main domain | **Promotion shift**, with the domain before and after. No AI answer is needed. |
| trend | `increasing` ≥ yes or `trajectory` = `forming`, after `fading` or `none` | **Network reactivation**, with the trajectory before and after |
| trend | the same, otherwise | **Coordination rising** |

A coordinated group also links every pair of members. The link type is the `relation`
label, with no link for `none`, and the strength comes from `coordinated`. Each link
records the finding id, the question, the model and the time.

Each alert's evidence is written by the app from the answers, naming the `model` that
answered (e.g. "jev-1.13: these 4 accounts post in a coordinated way (91%)"). When a finding merges
into an open alert, the newer answers' evidence replaces the older answers' evidence.
Each alert keeps its newest 100 evidence items.

## Results

`{:ok, result}`:

| Key | Meaning |
|---|---|
| `kind` | `:account`, `:group` or `:trend` |
| `finding_id` | The id the app gave the finding (`"finding-12"`), as recorded in link provenance |
| `alerts` | `[%{action: :created | :merged, alert: alert}]`. One finding can raise more than one alert (e.g. growth and a promotion shift). |
| `network_id` | The network concerned, or `nil` |
| `account_ids` | The accounts the finding named (created if new) |
| `skipped` | Updates left out to respect analysts, e.g. `%{account_id: "acc-12", reason: :removed_by_analyst}` |
| `reason` | Why there's no alert: `:below_threshold`, `:no_answers`, `:predates_dismissal` (a finding observed before the network's dismissal), or `nil` |

`{:error, errors}`: the finding was rejected and nothing changed. `errors` maps each
field to its messages. For example, a group of one account with a probability of 1.4:

```elixir
%{
  accounts: ["a group needs at least two different accounts"],
  answers: ["coordinated: noul must be a number from 0 to 1"]
}
```

It's also rejected for:
- an unknown `kind`;
- a missing `observed_at`;
- an unknown feed;
- an unknown or merged `network_id`;
- a trend without a `network_id`;
- malformed heuristics.

## Examples

These run in order against an app that already tracks one network, `net-example`. Its
four members on X are `net_member_1`–`net_member_4`. Its main domain is
`deals-a.example`, and its last trajectory was `fading`. A test reports each example,
so they always match the code.

### Account finding (no alert)

```json
{
  "kind": "account",
  "observed_at": "2026-11-07T19:40:00Z",
  "model": "jev-1.13",
  "account": {"feed_id": "x", "handle": "promo_daily"},
  "posts": [
    {"id": "x1", "published_at": "2026-11-07T10:00:00Z", "urls": ["https://deals.example/a"], "text": "Deal of the day"}
  ],
  "heuristics": {"score": 72, "labels": ["high_link_ratio", "regular_timing"]},
  "answers": {
    "is_bot": {"type": "noul", "noul": 0.83},
    "topic": {"type": "choice", "choice": "shopping", "confidence": 1, "probabilities": {"crypto": 0, "shopping": 1, "other": 0}},
    "spam": {"type": "score", "score": 2, "confidence": 1, "legend": {"0": "not spam", "1": "somewhat spammy", "2": "heavy spam"}, "probabilities": {"0": 0, "1": 0, "2": 1}}
  }
}
```

### Group finding: New network

```json
{
  "kind": "group",
  "observed_at": "2026-11-07T19:41:00Z",
  "model": "jev-1.13",
  "accounts": [
    {"feed_id": "x", "handle": "promo_daily"},
    {"feed_id": "x", "handle": "deal_hunter_88"},
    {"feed_id": "x", "handle": "coupon_cat"},
    {"feed_id": "x", "handle": "just_a_person"}
  ],
  "heuristics": {"domains": [{"domain": "deals.example", "share": 0.62}]},
  "answers": {
    "coordinated": {"type": "noul", "noul": 0.91},
    "relation": {"type": "choice", "choice": "shared-link", "confidence": 0.7, "probabilities": {"repost-ring": 0.1, "shared-link": 0.7, "timing-sync": 0.15, "audience-overlap": 0.05, "none": 0}},
    "member:x:promo_daily": {"type": "noul", "noul": 0.95},
    "member:x:deal_hunter_88": {"type": "noul", "noul": 0.9},
    "member:x:coupon_cat": {"type": "noul", "noul": 0.88},
    "member:x:just_a_person": {"type": "noul", "noul": 0.12}
  }
}
```

### Group finding on a known network: Network growth and Promotion shift

```json
{
  "kind": "group",
  "observed_at": "2026-11-07T19:42:00Z",
  "model": "jev-1.13",
  "network_id": "net-example",
  "accounts": [
    {"feed_id": "x", "handle": "net_member_1"},
    {"feed_id": "x", "handle": "net_member_2"},
    {"feed_id": "x", "handle": "net_member_3"},
    {"feed_id": "x", "handle": "net_member_4"},
    {"feed_id": "x", "handle": "fresh_deals_1"},
    {"feed_id": "x", "handle": "fresh_deals_2"}
  ],
  "heuristics": {"domains": [{"domain": "deals-b.example", "share": 0.55}, {"domain": "deals-a.example", "share": 0.2}]},
  "answers": {
    "coordinated": {"type": "noul", "noul": 0.86},
    "relation": {"type": "choice", "choice": "timing-sync", "confidence": 0.8}
  }
}
```

### Trend finding: Network reactivation

```json
{
  "kind": "trend",
  "observed_at": "2026-11-07T19:43:00Z",
  "model": "jev-1.13",
  "network_id": "net-example",
  "window": {"from": "2026-09-26T00:00:00Z", "to": "2026-11-07T00:00:00Z"},
  "answers": {
    "increasing": {"type": "noul", "noul": 0.78},
    "trajectory": {"type": "choice", "choice": "forming", "confidence": 0.66}
  }
}
```

### Trend finding: Coordination rising

```json
{
  "kind": "trend",
  "observed_at": "2026-11-08T19:43:00Z",
  "model": "jev-1.13",
  "network_id": "net-example",
  "answers": {
    "increasing": {"type": "noul", "noul": 0.92},
    "trajectory": {"type": "choice", "choice": "stable", "confidence": 0.7}
  }
}
```

## Not covered yet

- **Choosing which accounts form a group (prescreening)** is detection's job and isn't
  built yet. Until it is, live detection only sends account findings, and network
  alerts come from the sample data and the dev simulator.
- **The other contract.** The app's internal finding format (`Dripstone.Tracker.Finding`)
  is what the rules produce and what the sample data replays. Detection doesn't send it.
