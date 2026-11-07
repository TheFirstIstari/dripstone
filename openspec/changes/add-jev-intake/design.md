# Design

## Context

What `add-tracker-ui` built:

- **The intake.** `Tracker.report_finding/1` → `Finding.cast/2` → `Intake.run/3`, which
  takes one "finished alert" finding and runs inside `SampleStore.change/1`.
  `SampleLoader` replays the sample data through the intake.
- **The interim hookup.** `AssessWorker` → `Scorer.assess/2` → `Tracker.record_assessment/1`
  → `Assessments` raises `scorer_assessment` alerts.

What Jev returns, per the official TypeSafe docs:

- `noul`: `{type, noul}`, the probability of yes, with no confidence.
- `choice`: `{type, choice, confidence, probabilities}`.
- `score`: `{type, score, confidence, legend, probabilities}`, where `score` is an
  expected level from 0 to n−1.

Question names are free-form keys, and one call can carry many questions.

`choice` and `score` questions require `criteria`. A live check on 2026-11-07 against
`jev-1.13-free` through OpenCode, using the key `public` (OpenCode's placeholder for
signed-out free use), confirmed both points:

- A request with `criteria` returned HTTP 200 in about 0.3 s, billed as free. The
  answer shapes matched the TypeSafe docs exactly:
  - `noul`: `{type, noul}`;
  - `choice`: `{type, choice, confidence, probabilities}`;
  - `score`: `{type, score, confidence, legend, probabilities}`, with `score` 2 on a
    0–2 scale.
- The `Scorer`'s current format (`choices:` instead of `criteria`, and a `score` with no
  levels) returned HTTP 422. Today's scorer therefore always falls back to heuristics
  only.

`AIClient` caps the state at 8,000 characters, which limits a group call to about 10
accounts with a few posts each.

The store stays in memory. Every change is a pure function from one `State` to the next.

## Goals / Non-Goals

**Goals:**
- One public intake (`report_finding/1`) taking account, group and trend findings.
- Every internal effect of a finding happens in a single store change: accounts, links,
  network assessment and alerts. A rejected finding changes nothing.
- The existing `Intake` keeps everything it already does (de-duplication, re-alerting,
  respecting analyst changes) without being rewritten.
- The UI reads from the same `Tracker` functions as now.

**Non-Goals:**
- **Detection scheduling and prescreening** (choosing which accounts form a group). That
  belongs to the detection side.
- **Hysteresis and smoothing across findings.** Thresholds are flat for now.
- **Persistence**, and a findings history beyond what provenance needs.

## Decisions

### 1. A new report layer in front of the existing intake
`Dripstone.Tracker.Report` validates the public payload. It is a schemaless changeset,
like `Finding`, and accepts atom or string keys so decoded JSON works.

`Dripstone.Tracker.Rules` is a pure function from the state and a validated report to
`{state, [internal findings], result}`:
- the state includes the account, link and assessment updates;
- each internal finding then goes through the unchanged `Intake.run/3`.

`Finding` becomes internal; its moduledoc says so. `report_finding/1` now means the new
format.

*Alternative considered:* rewriting `Intake` around the new format. Rejected because
`Intake` already enforces the analyst-change, de-duplication and dismissal rules, and
its tests cover them. The rules layer only has to decide *what* to report.

### 2. One finding can raise several alerts
A group finding on a known network can produce both Network growth and Promotion shift.
`report_finding/1` returns this result:

```
{:ok, %{kind:, alerts: [%{action:, alert:}], network_id:, account_ids:, skipped:, reason:}}
```

`reason` is `:below_threshold`, `:predates_dismissal` or `nil`. `SampleStore`
broadcasts one message per alert, plus `{:network_updated, id}` and a new
`{:account_updated, id}`.

### 3. Accounts are identified by feed and handle
`Rules` looks up `(feed_id, handle)` and creates unknown accounts with
`State.next_id(state, "acc")`. It uses a linear scan over about 1,300 accounts. An index
map in `State` is deferred until the scan shows up in profiling.

Account findings **merge** the assessed posts into the account's stored posts by
platform post id. A post seen again is updated, and earlier posts are kept, so the
evidence behind earlier findings survives a re-assessment. This carries over the
merge that `Assessments` already does since the #59 fix. Each account keeps its newest
`posts_per_account` posts (config, default 200). Group findings only reference accounts,
creating bare ones if needed.

### 4. Where answers are stored

| On | Field | Holds | Used for |
|---|---|---|---|
| `Account` | `assessment` | `%{answers, model, observed_at}` | the answers panel |
| `Account` | `topic` | the topic label | display |
| `Network` | `assessment` | `%{coordinated, relation, relation_confidence, trajectory, model, observed_at}` | the network assessment panel, the trend rules |
| `Alert` | `answers`, `model`, `observed_at` | the triggering report's answers and when they arrived | the alert detail answers panel |

The interim `Account.assessment` from the scorer hookup is replaced, not kept alongside.

### 5. Answer normalization in one place
`Dripstone.Tracker.Answers` reads the answers:
- `noul` → a float from 0 to 1;
- `choice` → `{label, confidence | nil}`;
- `score` → `score / (levels − 1)`. The number of levels comes from `legend` or
  `probabilities`, falling back to the app's known level count for that question. With
  none of these the answer is malformed.

Confidence is optional, so slightly different answer shapes still parse (see Open
Questions).

Unknown question names are kept but not interpreted. There is a fixed map from relation
labels to atoms, so `String.to_atom/1` is never called on input.

### 6. Rules and severity
The thresholds live in `config :dripstone, Dripstone.Tracker.Rules`; see the
"Configurable thresholds" requirement.

Severity comes from the probability that triggered the alert:

| Alert | Severity from |
|---|---|
| New network, Network growth | `coordinated` |
| Network reactivation, Coordination rising | `increasing`. If only the trajectory is `forming`, the trajectory's confidence. |
| Promotion shift | the network's latest `coordinated`, or Medium if it has none (no AI answer is involved) |

**Group target.**
- If the finding names a `network_id`, it uses that network.
- Otherwise, if more than half the members belong to one network that hasn't been
  merged into another, it uses that network.
- Otherwise it creates a new network.

The ids of networks created by the rules come from `State.next_id(state, "net")`. Their
names are placeholders, `"<Topic> cluster on <feeds>"` or `"Unnamed cluster"`, until
naming is decided.

A below-threshold group finding on a known network still updates the network's
assessment, but raises no alert.

### 7. Links and provenance
`Link` gets:
- the new kinds `:repost_ring`, `:shared_link`, `:timing_sync` and `:audience_overlap`.
  `:synced_posting` becomes `:timing_sync`. `:near_duplicate` and `:created_together`
  stay for sample data.
- a `provenance` list of `%{finding_id, question, model, at}`, newest first.

A coordinated group finding upserts one link per member pair and kind. Strength comes
from `coordinated` using the evidence strength bands. Each link keeps its newest
`provenance_per_link` entries (config, default 20).

Each report gets a `finding-N` id. `State.findings` keeps the latest 500 reports so
provenance can be traced. That limit is in config.

**Graph cache and history are already handled on main** (the #63 fix):
- `SampleStore` clears the graph cache after every change, so links added by a group
  finding show up the next time the graph is opened.
- `State.add_history/6` keeps the newest 500 entries.

The rules rely on both as they are, with no changes.

### 7a. Evidence on repeated findings
Since the #65 fix, the intake keeps the newest 100 evidence items when a finding merges
into an open alert. With repeated findings, and Jev's answers varying between calls,
that cap would fill with near-identical lines from successive assessments. The rules
mark the evidence they write from answers with a `source` key (`:answers`, internal
only). When a finding merges into an open alert:
- evidence from **answers** replaces the earlier evidence from answers, so the alert
  shows the latest assessment;
- other evidence (heuristics and sample data) is combined and de-duplicated as today;
- the existing cap of 100 newest items still applies.

### 8. Scorer question sets
`Scorer` keeps `score/1` (heuristics). `assess/2` becomes the **account** question set
(`is_bot`, `spam`, `topic`). Two new functions build the other sets:
- `assess_group/2`: `coordinated`, `relation`, and `member:` questions per account;
- `assess_trend/2`: `increasing`, `trajectory`.

Every `choice` and `score` question carries `criteria` with the exact labels the app
expects. `AIClient` is unchanged.

`AssessWorker` builds an account report from the adapter's posts and `assess/2`, then
calls `report_finding/1`. The `model` comes from the configured model id.

### 9. Sample data in the new format
`SampleData` events become account, group and trend reports, with deterministic answers
chosen so the same networks, alerts and decisions as today come out. The analyst
decision and curation events are unchanged.

Things the new path cannot produce are applied as a clearly named
`SampleData.placeholders/1` overlay after the replay:
- AI-written network summaries;
- `near_duplicate` and `created_together` links;
- signal contributions.

That way, the placeholder features keep demo content without the intake pretending to
supply it.

### 10. Dev simulator
The simulator has two jobs:
- every 2 minutes, it queues `AssessWorker` jobs, which are live account findings;
- every 45 seconds, it reports a generated group or trend finding with canned answers
  and no AI call, so network alerts keep arriving in dev.

The feed refresh keeps the 24-hour item window that is already on main (the #66 fix,
`FeedHealth.window_started_at`) unchanged.

### 11. UI
- **A shared `answers_panel` component** in `tracker_components.ex` shows question,
  answer, confidence, model and observed time, or "heuristics only". It is used on alert
  detail, network summary and account detail.
- **Signals** get an optional `value` string, rendered when `contribution` is nil.
- **The link legend and filters** read `Link.kinds/0`, so new kinds only need labels and
  colors.

## Risks / Trade-offs

- **Jev's answers may vary between calls for the same input,** and the docs don't promise
  determinism. A network near a threshold can flip back and forth between findings.
  → The existing de-duplication merges into the open alert. Re-alerts after a dismissal
  still need a finding observed after it. Hysteresis is deferred, and the thresholds are
  configurable.
- **The OpenCode answer shape could change** (it was confirmed live on 2026-11-07, see
  Context). → `confidence` and `probabilities` stay optional in parsing.
- **The `public` key is OpenCode's placeholder for signed-out free use,** not an issued
  key. It may be rate-limited or withdrawn, and the deployed site could lose AI answers.
  → The key stays an environment setting (`OPENCODE_API_KEY`), and a failed call falls
  back to heuristics only. Switching to a team key is a config change.
- **The 8,000-character state cap limits group size.** → The contract recommends at most
  10 accounts; larger groups are the prescreening's job to split.
- **The specs depend on `add-tracker-ui` being archived first,** because its capabilities
  aren't in `openspec/specs/` yet. → Archiving it is the first task.
- **The rules write far more often than today's sample replay,** so stored data could
  grow for the life of the process. → History, evidence and the graph cache are already
  capped or cleared on main. This change caps what it adds: posts per account (§3),
  provenance per link and the findings log (§7).
- **Archiving `add-tracker-ui` moves its `docs/` folder.** Many places in code, tests,
  docs and UI text point at `openspec/changes/add-tracker-ui/docs/`, including the
  `DETECTION_INTERFACE.md` doc test. → Task 1.1 moves the three docs to a stable
  `openspec/docs/` (still under OpenSpec, as the move into the change intended) and
  updates every reference.
- **Rebuilding the sample data is the largest task, and it can drift from today's demo.**
  → The existing sample tests (counts, statuses, the quiet-feed guard) stay and must
  still pass.
- **There is no live source of group or trend findings until prescreening exists.**
  → The simulator stub and the sample data exercise those paths.

## Migration Plan

There is no stored data; the store reloads on restart. Deploying is a normal merge to
`main`, which auto-deploys. Rolling back means reverting the merge. The detection side
switches to the new payload when it starts sending findings; nothing calls the old
format except the code this change replaces.

## Open Questions

- **How networks created from findings are named.** For now they get a placeholder name
  that analysts can rename. A text-writing model or a naming rule can be added later
  without changing the contract.
