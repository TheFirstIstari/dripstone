# Tasks

## 1. Groundwork

- [x] 1.1 Move `FEEDS.md`, `TRIGGERS.md` and `DETECTION_INTERFACE.md` from `openspec/changes/add-tracker-ui/docs/` to `openspec/docs/`, and update every reference to the old path in code, tests, docs and UI text (`git grep "add-tracker-ui/docs"`). Then archive `add-tracker-ui` (`openspec archive add-tracker-ui`, CLI pinned to 1.16.0) so its capabilities exist under `openspec/specs/`. Verify that:
  - `git grep "add-tracker-ui/docs"` finds nothing outside this change's own planning files (which describe the move);
  - `mix test` passes, including the doc test;
  - `openspec validate add-jev-intake --strict` passes with no "target spec does not exist" notes.
- [x] 1.2 Update the stale vLLM wording in `openspec/config.yaml` to say detection uses Jev via OpenCode Console. Verify with `openspec context --json`, which shows the new text.
- [x] 1.3 Confirm the answer shape returned by the OpenCode Console proxy. One live call to `jev-1.13-free` with the key `public` (2026-11-07) used a `noul`, a `choice` and a `score` question with `criteria`. It returned HTTP 200 with the documented shapes; the scorer's current format returned HTTP 422 (see design.md Context). Group 2's parsing tests use the recorded shape as a fixture.

## 2. Answers and report validation

- [ ] 2.1 Add `Dripstone.Tracker.Answers` (design §5):
  - `noul` → probability;
  - `choice` → label and optional confidence;
  - `score` → normalized 0–1, with the level count taken from `legend`/`probabilities`, or the app's known question, otherwise rejected as malformed;
  - unknown questions kept;
  - a fixed relation-label map.

  Verify with unit tests covering the spec scenarios ("Score normalized", "Unknown question kept"), out-of-range values, and a `score` with no level count.
- [ ] 2.2 Add `Dripstone.Tracker.Report`, a schemaless changeset for account, group and trend findings (atom or string keys, `answers` allowed to be nil). Verify with unit tests for every rejection in the "Finding validation" requirement (unknown kind, missing time, unknown feed, a group under two accounts, an unknown network, a malformed answer), plus acceptance of decoded JSON.

## 3. Data model

- [ ] 3.1 Extend the structs (design §4, §7, §11):
  - `Account.assessment` and `Account.topic`;
  - `Network.assessment`;
  - `Alert.answers`, `Alert.model` and `Alert.observed_at`;
  - `Signal.value`;
  - `Link` gets the new kinds (with `:synced_posting` renamed to `:timing_sync`) and `provenance`;
  - `State.findings`, capped by config.

  Add the new caps to config (`posts_per_account`, `provenance_per_link`; design §3, §7). Keep the existing history, evidence and graph-cache handling from main as it is. Update every reference to the renamed kind. Verify with `mix compile --warnings-as-errors` and the existing test suite passing.

## 4. Rules and the public intake

- [ ] 4.1 Add `Dripstone.Tracker.Rules` (design §1, §3, §6):
  - account upsert by feed and handle, merging posts by platform post id up to the per-account cap;
  - group target resolution (named network, majority network, or new);
  - the `member:` filter;
  - the New network, Network growth, Promotion shift and Trend rules, with severity and evidence from the configured bands;
  - assessment updates;
  - below-threshold results.

  Add the thresholds to `config.exs` and `Coordination rising` to the trigger catalog. Verify with table-driven unit tests for every scenario in `specs/alert-intake/spec.md`, including "Re-assessment keeps earlier posts".
- [ ] 4.2 Add link upserts with provenance and the `finding-N` ids (design §7). Verify with:
  - the "Link records its origin" and "New links appear without a membership change" scenarios (the latter relies on the store clearing the graph cache, which is already on main);
  - tests that `relation` `none` creates no link;
  - tests that the findings log and link provenance stay within their caps.
- [ ] 4.2a Change the intake's merge into an open alert (design §7a): evidence from answers replaces the earlier evidence from answers, other evidence is combined, and the existing 100-item cap still applies. Verify with the "Repeated finding", "Re-assessed answers replace earlier ones" and "Evidence is capped" scenarios.
- [ ] 4.3 Rewire `Tracker.report_finding/1` and `SampleStore` to run `Report` → `Rules` → `Intake` in one store change, returning the multi-alert result (design §2) and broadcasting per alert plus `{:account_updated, id}`. Make `Finding` internal. Verify with store tests:
  - a group finding raising both growth and a promotion shift gives two broadcasts;
  - a rejected report changes nothing;
  - a stale report after a dismissal is ignored.
- [ ] 4.4 Remove `Tracker.Assessments`, `record_assessment/1` and the `scorer_assessment` trigger. Verify with `mix compile --warnings-as-errors` and a search showing no references remain.
- [ ] 4.5 Rewrite `DETECTION_INTERFACE.md` for the three finding kinds: fields, understood questions with their answer types, rules and thresholds, results, and one example per kind. Update the doc test to report each example through `report_finding/1`. Verify that the doc test passes.

## 5. Scorer and worker

- [ ] 5.1 Give `Scorer` its three question sets (design §8), each `choice` and `score` question carrying `criteria` with the exact labels the intake expects. Add `assess_group/2` and `assess_trend/2`. Verify with offline `Req.Test` tests that assert each request's question definitions (the "Question definitions follow the model's schema" scenarios) and that `member:` keys are generated per account.
- [ ] 5.2 Change `AssessWorker` to build an account report and call `report_finding/1`. Verify with the worker test: with no key it records a heuristics-only account and raises no alert, and an unknown adapter cancels the job.

## 6. Sample data and simulator

- [ ] 6.1 Rebuild `SampleData` events as account, group and trend reports with deterministic answers, plus the `placeholders/1` overlay (summaries, `near_duplicate`/`created_together` links, contributions; design §9). Verify that the existing sample, store and LiveView tests still pass (counts, statuses, the quiet-feed guard), and add a test that every sample alert traces back to a replayed report.
- [ ] 6.2 Update the simulator (design §10): `AssessWorker` jobs every 2 minutes and a canned group or trend report every tick, keeping the existing 24-hour feed item window. Verify that:
  - the simulator tests (with the `enqueue:` option and a manual `:tick`) show a job queued and an `{:alert_raised, _}` broadcast arriving;
  - the existing items-window tests from main still pass.

## 7. UI

- [ ] 7.1 Add the `answers_panel` component and show it on alert detail (answers, model, observed time, or "heuristics only"), with the rationale placeholder when there is none. Verify with LiveView tests for the "Answers behind the alert", "No AI answers" and "No AI-written rationale" scenarios.
- [ ] 7.2 Add the network assessment panel to the network summary (coordinated, relation, trajectory, or "not assessed"), and add the new link types and colors to the graph legend, filters and shared evidence. Verify with LiveView tests for the "Assessed network", "Never assessed" and "Relation labels in the legend" scenarios.
- [ ] 7.3 Show signal values when there is no contribution, contributed signals first, and the answers panel on account detail. Verify with LiveView tests for "Signals without contributions" and "Account with links" (`Repost ring`).

## 8. Integration checks

- [ ] 8.1 Run `mix precommit`. Verify it exits 0 with no warnings.
- [ ] 8.2 With `DRIPSTONE_SIMULATE=1`, run the app and click through every screen in light and dark mode:
  - a live group or trend alert arrives, with a toast and a badge update;
  - an account finding updates an account;
  - an alert shows its answers;
  - a network shows its assessment and the new link colors.

  Verify by hand, and record the result in the PR description.

## Workflow follow-up

- Commit this OpenSpec change directly to `main`, create GitHub issues from the task groups, then do one branch and PR per issue in group order. Each step happens only on the user's go-ahead.
- Tell the detection owner about the new payload and the scorer question changes before group 5 merges. Also tell them which of their open issues this change touches: #49 and #53 (superseded), #54 and #55 (same scorer code as task 5.1), plus ordering with #48, #50 and #44. Their issue text describes code this change rewrites. The issues are left untouched here.
- Archive `add-jev-intake` after it is merged and stable.
