# Tasks

## 1. Registries: feeds and trigger types

- [x] 1.1 Add the `Dripstone.Feeds.Feed` behaviour and the `Dripstone.Feeds` registry (`all/0`, `get/1` by string id) configured in `config.exs` (design §4). Verify with a unit test that `all/0` keeps the configured order and that `get("nope")` returns `nil`.
- [x] 1.2 Implement the X, Reddit, Bluesky, Mastodon, Telegram and Facebook feeds, one module per file. Verify with tests covering `format_handle/1`, `profile_url/1` and `post_url/1` for each, including Mastodon `@user@instance`.
- [x] 1.3 Add the `Dripstone.Alerts.TriggerType` struct and the catalog (`trigger_types/0`, `get_trigger_type/1`) with the four initial types (design §3). Verify with a unit test of the catalog contents and lookup.
- [x] 1.4 Write `docs/FEEDS.md` and `docs/TRIGGERS.md` with copy-paste skeletons and the one-line registry step. Verify with tests that register a throwaway feed and a throwaway trigger type through `Application.put_env` (restored afterwards) and see them in `all/0` / `trigger_types/0`.

## 2. Tracker structs and sample base data

- [x] 2.1 Add the structs `Account`, `Network`, `Link`, `Signal`, `Post`, `Evidence` (explanation, strength, account_ids), `Alert`, `Decision`, `Note`, `HistoryEntry` and `FeedHealth`, one per file (design §1). `Network` includes `detected_name`, `tags`, `removed_account_ids`, `related_ids` and `retired_into`. Verify with `mix compile --warnings-as-errors`.
- [x] 2.2 Add `Dripstone.Tracker.SampleData`: seeded base data (accounts, links, signals, posts, feed health), a time-ordered list of findings, and seed decisions and curation covering every scenario in design §5. Verify with tests that generation is deterministic and that each listed scenario is present.

## 3. Findings intake

- [x] 3.1 Implement finding validation as a schemaless changeset (catalog trigger, at least one evidence item, severity, known or new network, `observed_at`). Verify with unit tests for each rejection in `specs/alert-intake/spec.md`, and that a rejected finding leaves state unchanged.
- [x] 3.2 Implement the intake pipeline (design §2): network creation and updates with analyst protections, de-duplication with severity escalation, the dismissal and stale rule, `System` history entries, the result map (`action`, `skipped`), and the PubSub broadcast. Verify with table-driven tests for every alert-intake scenario: repeated findings merging, a re-alert marked previously dismissed, a stale finding ignored, a removed member skipped, an analyst name kept, and a broadcast received.
- [x] 3.3 Write `docs/DETECTION_INTERFACE.md` with every finding field, the validation errors, the result shape, and one example finding per initial trigger type. Verify with a test that parses each example out of the doc and reports it successfully through `report_finding/1`.

## 4. Tracker context and store

- [x] 4.1 Add `Dripstone.Tracker.SampleStore` (a GenServer) to the supervision tree. It loads base data, replays sample findings through `report_finding/1` with seed decisions and curation, and supports `Tracker.reset_sample_data!/0`. Verify with a test that after boot every alert traces back to a replayed finding, and that the open count matches the seed expectations.
- [x] 4.2 Implement the read API (design §1), including the risk-level mapping, filters (with tag and retired-network exclusion), sorting, 50-row pages, neighbors and `list_tags/1`. Verify with unit tests covering filters, risk boundaries 39/40/69/70, pagination, neighbor order, and unknown ids returning `nil`.
- [x] 4.3 Implement `confirm_alert/2`, `dismiss_alert/2` and `undo_decision/1` (500-character note, `Unattributed`, network status rules, history, broadcasts). Verify with `async: false` tests covering confirm, dismiss-only-alert, undo restoring both statuses, the note limit, and broadcasts.
- [x] 4.4 Implement the curation functions (design §6): rename, tags, notes, add/remove/move members, merge, split, relate/unrelate, each with history and broadcasts. Verify with `async: false` tests for every scenario in `specs/network-curation/spec.md`, including tag normalization, the merge status order, a retired source, a refused full split, and symmetric relations.
- [x] 4.5 Implement `network_graph/1` (top 150, seeded layout, cache per membership version). Verify with tests that the 400-member network gives 150 nodes and an omitted count of 250, that the layout is deterministic, and that every edge references drawn nodes.
- [x] 4.6 Add `Dripstone.Tracker.Simulator` (only when `:simulate_alerts` is true, which `dev.exs` sets from `DRIPSTONE_SIMULATE=1`), reporting generated findings through the intake. Verify with a `start_supervised!` test using a short interval that an `{:alert_raised, _}` broadcast arrives, and that the simulator is not started by default.

## 5. Design system and app shell

- [x] 5.1 Remove daisyUI from `app.css` and `mix.exs`, then add the `@theme` tokens with dark overrides and reduced-motion rules (design §9). Verify that `mix assets.build` succeeds and that `grep -ri daisy lib assets mix.exs` finds nothing.
- [x] 5.2 Restyle `core_components.ex` with Tailwind only (names and attrs unchanged) and add a `modal` component. Verify with `mix compile --warnings-as-errors` and a check that no daisyUI class names remain.
- [x] 5.3 Add `DripstoneWeb.TrackerComponents` (design §10) and import it in `html_helpers`. Verify with `rendered_to_string/1` tests that severity, risk, status and strength badges include text labels, and that `sparkline` and `heatmap` render text summaries.
- [x] 5.4 Rebuild `Layouts.app(flash, nav)`: a sidebar with active state and badge, a drawer, a top bar with search and theme toggle, `toast_stack` (max 3), and the `Sample data` indicator. Set the title suffix to ` · Dripstone` and remove the Phoenix branding. Verify with the tests in 5.6.
- [x] 5.5 Add the `DripstoneWeb.Nav` hook (design §7) and `live_session :tracker` routes for `/`, `/alerts`, `/alerts/:id`, `/networks`, `/networks/:id`, `/accounts`, `/accounts/:id` and `/feeds`. Remove `PageController`, `PageHTML`, `home.html.heex` and its test. Verify that `mix phx.routes` lists exactly these routes plus the dev routes.
- [x] 5.6 Write shell LiveView tests (`test/dripstone_web/live/shell_test.exs`): active nav, the badge count (hidden at zero, updating on broadcast), a High toast versus no toast for Medium, search navigating to `/accounts?q=…`, the title format, the `Sample data` indicator, and not-found for unknown alert, network and account ids. Verify by running that file.

## 6. Overview screen

- [x] 6.1 Implement `OverviewLive` per the wireframe: live counts linking to filtered screens, the 30-day trend with total, five newest open alerts, five recent networks, and a feed strip with non-healthy feeds first, plus empty states. Verify with `mix test test/dripstone_web/live/overview_live_test.exs`, covering the count links, a live update on a reported finding, feed ordering, and the clear state.

## 7. Alerts screens

- [ ] 7.1 Implement `AlertLive.Index`: URL filters (status defaulting to Open; severity; trigger and platform options from the catalog and registry), a streamed newest-first list, live insertion of matching alerts with a NEW highlight, a previously-dismissed marker, and an empty state. Verify with `mix test test/dripstone_web/live/alert_live/index_test.exs`, covering the default filter, combined filters with URL restore, live arrival matching versus not matching, and a throwaway trigger type in the filter.
- [ ] 7.2 Implement `AlertLive.Show`: fields, network card, evidence sorted by strength, before/after values, the AI rationale under `ai_label`, a note form, Confirm/Dismiss, Undo, the read-only decided state, and `j`/`k` neighbors with the inbox query. Verify with `mix test test/dripstone_web/live/alert_live/show_test.exs` (`async: false`, store reset), covering each decision path, the note limit, before/after domains, and neighbor navigation.
- [ ] 7.3 Add the colocated `.AlertShortcuts` hook (c/d/j/k, ignored in text fields) with a unique element id. Verify with a LiveView test that sends the hook's events, and by hand in the browser that typing `c` in the note field doesn't confirm.

## 8. Network screens

- [ ] 8.1 Implement `NetworkLive.Index` with status, platform and tag filters in the URL, ordered by most recent activity, excluding retired networks, and showing tags and open alert counts. Verify with `mix test test/dripstone_web/live/network_live/index_test.exs`, covering the default order and the `Suspected` and tag filters.
- [ ] 8.2 Implement `NetworkLive.Show` Summary: the header (name, `Detected as`, tags, main domain, open alerts), the AI summary or no-summary state, evidence by strength, the heatmap, the member list, alert history with the previously-dismissed marker, related networks, and the retired "merged into" state. Verify with `mix test test/dripstone_web/live/network_live/show_test.exs`.
- [ ] 8.3 Implement the Graph view (`?view=graph`): SVG by link type with a legend and toggles, node selection with a panel, and the omitted-members notice. Verify with LiveView tests covering the URL view, toggling, selection, and the 400-member notice.
- [ ] 8.4 Implement the curation UI on `NetworkLive.Show`: inline rename, a tag input with suggestions, a Notes tab, a History tab (`Analyst`/`System`), member selection with Move, Split and Remove, Add account (search), Merge into… and Relate…, with confirmation modals showing impact summaries. Verify with `mix test test/dripstone_web/live/network_live/curation_test.exs` (`async: false`), covering each network-curation scenario through the UI, including cancelling a merge leaving everything unchanged.

## 9. Account screens

- [ ] 9.1 Implement `AccountLive.Index` with search, platform, risk and network filters, sorting, 50-row pages, a total, and an empty state with clear-filters. Verify with `mix test test/dripstone_web/live/account_live/index_test.exs`, covering combined filters, URL restore, ignored unknown params, the default sort, and page 2.
- [ ] 9.2 Implement `AccountLive.Show`: the header with the feed-built external link (`target="_blank" rel="noopener noreferrer"`), signals by contribution, linked accounts with types and strength, networks, recent posts with domains, an "Add to network…" picker, and empty states. Verify with `mix test test/dripstone_web/live/account_live/show_test.exs`, including a Mastodon handle and profile URL, and adding to a network.

## 10. Feeds screen

- [ ] 10.1 Implement `FeedLive.Index`: a read-only table with status, last item, 24h items, account count and last error, plus the `docs/FEEDS.md` note. Verify with `mix test test/dripstone_web/live/feed_live_test.exs`, covering all six feeds, the Down feed's error, no edit controls, and a throwaway feed appearing.

## 11. Integration checks

- [ ] 11.1 Run `mix precommit` and verify that it passes with no warnings, formatting changes or test failures.
- [ ] 11.2 Run `DRIPSTONE_SIMULATE=1 mix phx.server` and click through every screen in light, dark and system themes at phone and desktop widths. Verify live arrivals and toasts, curation flows end to end (rename, tag, merge, split), the drawer, focus rings, reduced motion, and the absence of daisyUI or Phoenix branding, and that the layouts match the `design.md` wireframes.

## Workflow follow-up

- Review `docs/DETECTION_INTERFACE.md` with the detection owner before or right after apply; adjust the intake if the AI side needs a different shape.
- After review, archive the change so the eight new capability specs move into `openspec/specs/`.
- Next change: persistence (Ecto schemas behind `Dripstone.Tracker`) and the real detection integration through the intake.
