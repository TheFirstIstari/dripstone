# Proposal

## Why

The findings intake from `add-tracker-ui` expects detection to send finished alerts, with
a title, a severity, written evidence and AI prose. Jev, the decision model behind
`Dripstone.AIClient.decide/3`, returns only typed answers:

- `noul`: the probability of yes;
- `choice`: a label, plus its confidence and the probability of every option;
- `score`: an expected level, plus confidence and per-level probabilities.

Jev never writes text. Detection therefore cannot fill the current contract without
inventing values. The interim hookup (`Tracker.record_assessment/1`, the
`scorer_assessment` alert) shows the gap: severity, titles and grouping are
placeholders. The intake needs to accept what detection actually measures, and the app
needs to own how those measurements become alerts.

**Related issues.** This change supersedes #49 (detection integration) and #53 (split
pair questions out of `assess/2`). It keeps the fixes already merged for #59, #63, #65
and #66, and changes the data that #48 (persistence) will store.

## What Changes

**New intake contract.** Detection reports one of three finding kinds, each carrying its
heuristics and Jev's `answers` map exactly as `decide/3` returned it (or `null` when the
AI was unavailable):

- **Account**: one account's posts, with `is_bot`, `spam` and `topic` answers.
- **Group**: up to about 10 accounts, optionally tied to a known network, with
  `coordinated` and `relation` answers and optional per-account `member:<feed>:<handle>`
  answers.
- **Trend**: a known network over time, with `increasing` and `trajectory` answers.

Every finding also carries the time it was observed and the model that answered.

**Alert rules in the app.** Configurable rules turn findings into the existing internal
findings, so de-duplication, re-alerting after a dismissal, respecting analyst edits,
curation and live updates keep working unchanged.

- The rules raise New network, Network growth, Promotion shift and Network reactivation
  alerts, and a new **Coordination rising** trigger.
- Severity, evidence strength and evidence wording are derived from the answer
  probabilities, using configured thresholds.
- The before/after comparisons are computed from what the app stored previously.

**Links with provenance.** Group findings create links between members. The link type is
Jev's `relation` label, and each link records the finding, the question, the model and
the time it came from.

**BREAKING (internal):** the current finding format is no longer accepted from
detection. It remains the internal step between the rules and the intake.

**Link types follow Jev's `relation` labels.** The new types are `repost-ring`,
`shared-link`, `timing-sync` and `audience-overlap`.
- `shared-link` and `timing-sync` replace the existing `shared_link` and
  `synced_posting` types.
- `near_duplicate` and `created_together` stay, but only the sample data produces them.

**The UI shows answers, not prose.**
- The alert detail page and the network page show Jev's answers (question, answer,
  confidence) in place of AI-written rationales and summaries.
- The AI-written summary and rationale areas stay, as placeholders that say no summary
  is available.
- Account signals show a value (for example `Bot-like 81%`) when there is no per-signal
  contribution.

**Scorer fixes.** The scorer's questions follow Jev's schema: `choice` and `score`
questions carry `criteria`. Its questions are split into three sets, one per finding
kind (account, group, trend). The app normalizes `score` answers to 0–1 when it reads
them.

**Removals and rebuilds.**
- The interim `scorer_assessment` trigger and `record_assessment/1` are removed.
- `AssessWorker` and the dev simulator send account findings instead.
- The large sample data stays an internal seed (it is a demo, and is switched off in
  production). The new-format path is exercised by the dev simulator and by the
  showcase corpus (`priv/datasets/showcase/`), which the app can start on instead.

**Docs.** `DETECTION_INTERFACE.md` is rewritten for the new contract, and the stale
vLLM wording in `openspec/config.yaml` is updated to Jev.

**Out of scope:**
- **Not part of this change:** choosing which accounts to send as a group (prescreening),
  persistence (the store stays in memory), and the showcase dataset.
- **Separate changes:** evasion triggers, the Cleared state, watcher corroboration,
  attention signals, the change digest and time-travel reads.
- **Sample-data only:** features that depend on these remain placeholders that only the
  sample data exercises.

## Capabilities

### New Capabilities
None.

### Modified Capabilities
- `alert-intake`: the findings contract becomes account, group and trend findings
  carrying raw Jev answers. App-side alert rules and thresholds are added, links with
  provenance are added, and a Coordination rising trigger is added. The requirements for
  the old contract, for AI-written rationales in findings and for the documented
  contract are replaced. Re-assessing an account keeps its earlier posts. On a repeated
  finding, evidence from answers replaces the earlier answers' evidence instead of
  piling up, and each alert's evidence is capped.
- `alert-inbox`: alert detail shows the answers behind an alert. The AI-written
  rationale becomes a placeholder.
- `network-views`: the AI-written summary becomes a placeholder next to an answers
  panel. The link types in the graph and the shared evidence follow the relation labels.
- `account-views`: the risk signal breakdown allows a value instead of a contribution.
  The linked accounts list uses the relation link types.
- `ai-client`: the question definitions follow Jev's schema (criteria for `choice` and
  `score`), and group calls may include per-account membership questions.

`alert-intake`, `alert-inbox`, `network-views` and `account-views` are defined in the
`add-tracker-ui` change. That change must be archived before this one, so that these
deltas apply to the main specs.

## Impact

- **Code:**
  - `lib/dripstone/tracker/` (finding parsing, a new rules module, intake wiring, link
    struct, sample data, simulator, assessments removal);
  - `lib/dripstone/tracker.ex`;
  - `lib/dripstone/scorer.ex`;
  - `lib/dripstone/workers/assess_worker.ex`;
  - `config/config.exs` (thresholds, trigger catalog);
  - the alert, network and account LiveViews and `tracker_components.ex` (answers panel,
    link legend, signal values).
- **Docs:**
  - `openspec/docs/DETECTION_INTERFACE.md` (moved there from `add-tracker-ui`'s
    `docs/` folder, together with `FEEDS.md` and `TRIGGERS.md`);
  - `openspec/config.yaml`.
- **Detection side (teammate):** sends findings in the new shape. Until prescreening
  exists, only account findings come from live detection; group and trend findings come
  from the sample data and a stub.
- **Dependencies:** none added.
