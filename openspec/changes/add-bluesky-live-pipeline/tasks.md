# Tasks

## 1. Groundwork

- [x] 1.1 Revise this draft against the merged code: persistence (#111, #216), the corpus and refresh task (#201), the politeness layer (#220), the test harness (#224) and the seeding fix (#230). Proposal, design and tasks were updated on 2026-11-08 against `main` at `4151328`. Verified with `openspec validate add-bluesky-live-pipeline --strict`.
- [ ] 1.2 Add the approved WebSocket dependency (`mint_web_socket` unless decided otherwise). Verify that `mix deps.get` succeeds and `mix precommit` passes, including the unused-deps check.
- [ ] 1.3 Fix the politeness layer (design §5):
  - a supervised `Polite.Gate` owns the ETS table;
  - rate slots are reserved atomically;
  - HTTP-date `Retry-After` is parsed;
  - robots rules are cached for 24 hours.

  Verify that the existing `polite_test.exs` still passes, and add tests that:
  - the gate's state survives the calling process exiting;
  - two concurrent callers to one host are spaced by the minimum interval;
  - a date-form `Retry-After` is honoured.

## 2. Demo and Live data modes

- [x] 2.1 Add `Dripstone.Tracker.DemoStore` (memory-only, started on demand under a `DynamicSupervisor`, seeded from `SampleLoader`, serialising its own writes). Add `Tracker.dataset/0` and `Tracker.with_dataset/2`. Make `Store.load/0`, `save/1` and `write/1` dispatch by dataset, and give PubSub one topic per dataset (design §1). Verify with tests:
  - Demo starts once and is reused;
  - a change in Demo leaves the database untouched ("Isolated changes", "Demo is never persisted");
  - code with no dataset set reads Live;
  - Demo broadcasts don't reach Live subscribers.
- [x] 2.2 Make the `:load_sample_data` default `false`, keeping `true` in `config/test.exs` (design §2). Verify with a store test that a dev/prod-configured empty database starts with no accounts ("Live starts without sample data"), and that the existing seeded-store tests still pass.
- [x] 2.3 Set the dataset per LiveView from the session in `DripstoneWeb.Nav`, subscribing to that dataset's topic. Add `POST /mode`, which stores the mode and redirects back (design §3). Verify with LiveView tests for "Switch to Demo" (another session stays on Live) and "Fresh session" (Live by default).
- [x] 2.4 Replace the hard-coded sidebar label with the Live/Demo indicator and switch, and add the Demo banner (design §11). Verify with tests for the ui-shell "Data source indicator" scenarios and "Demo on screen".
- [x] 2.5 Start the simulator with the Demo store and target Demo for its feed refreshes, canned findings and `AssessWorker` jobs (`"dataset"` arg, default `"live"`; design §4). Verify with "Simulator writes to Demo only", and that the database is unchanged after a simulator tick.

## 3. Bluesky fetcher

- [ ] 3.1 Add `Dripstone.Adapters.Bluesky.fetch_posts/2` (AppView `getAuthorFeed`, no auth, through `Polite.get/2`), mapping to canonical posts with link extraction. Register it in `Dripstone.Adapters` and in the refresh task's platforms. Verify with fixture-first tests under `HttpGuard` (`Req.Test` stubs) for "Recent posts fetched" and "Rate limited".
- [ ] 3.2 Check in a small Bluesky seed corpus (`priv/datasets/bluesky/<date>.jsonl`, recorded with `mix dripstone.refresh bluesky --handle <public handle>`). Verify that its lines carry the envelope fields (`fetched_at`, `source`), and that `Dripstone.Test.Corpus.latest("bluesky")` resolves it.

## 4. Live discovery

- [ ] 4.1 Add `Dripstone.Discovery.Bursts`: windows of distinct DIDs per link, threshold, cooldown, common-domain list, bounded tracking (design §7). Verify with unit tests for:
  - "Five accounts share a link within ten minutes";
  - "Common domain ignored";
  - "Cooldown";
  - a single account repeating a link counting once;
  - the tracked-link bound.
- [ ] 4.2 Add the Jetstream consumer: config-enabled, keeps linked posts, URL normalisation, reconnect with cursor, and feed-health counters flushed to Live once a minute in one write (design §6). Verify with tests driving it from recorded Jetstream frames (no network) for:
  - "Linked posts are kept";
  - "Disabled by configuration";
  - "Stream disconnected";
  - one write per flush, not per post.

## 5. Assessing candidates

- [ ] 5.1 Add `Tracker.report_findings/1`: one load, each finding through `Report` and `Rules` in order, one save, then broadcasts. A rejected finding rejects the batch (design §8). Verify with tests that a batch of an account and a group finding makes exactly one `Store.save`, and that a bad finding changes nothing.
- [ ] 5.2 Add `tracker_accounts.external_id` (migration plus `Account` field plus the `Store` row mapping; design §10). Verify with a store round-trip test.
- [ ] 5.3 Add `DiscoverWorker`: caps, DID-to-handle resolution, member fetch, account findings and a group finding with computed `domains`, reported in one batch (design §8). Verify with tests (stubbed HTTP and Jev) for:
  - "A candidate group raises a real alert";
  - "Unreachable account";
  - "Hourly cap reached";
  - "Large burst trimmed".
- [ ] 5.4 Add `Oban.Plugins.Cron` and `Pruner` to the Oban config (`config.exs` **and** `runtime.exs`) and `TrendWorker` every 6 hours, capped and batched (design §9). Verify with a test for "Active network re-checked" (inactive networks skipped), and that the prod Oban config includes the cron entry.

## 6. Docs and integration checks

- [ ] 6.1 Update `openspec/docs/FEEDS.md` (a feed with a real fetcher), `DETECTION_INTERFACE.md` ("Not covered yet") and the README (modes, enabling discovery, caps, and `mix ecto.reset` once in dev). Verify that the doc tests pass and that the README commands run as written.
- [ ] 6.2 Run `mix precommit` (warning-free). Then, with discovery enabled against the real Jetstream, run the app for at least 30 minutes:
  - Bluesky feed health is live;
  - any burst produces candidates within the caps;
  - switching to Demo shows the sample data with simulator alerts and the banner;
  - switching back shows Live unchanged.

  Record the results (candidates seen, skips, alerts, write counts) in the PR description.

## Workflow follow-up

- Commit this change to `main`, then create issues from task groups 1–6. Tell the detection owner first, because their AI picks up open issues quickly.
- Flag to the detection owner: the whole-state `Store.save/1` and per-read `Store.load/0` cost (design, Risks), and that this change takes Bluesky trend scheduling while #188 keeps generic refresh scheduling.
- Archive after merge and stability.
