# Design

## Context

- See `proposal.md` (Why) for the product and the alert-driven workflow.
- The app is a fresh Phoenix 1.8 / LiveView 1.2 scaffold. There are no schemas or
  migrations, no LiveViews, and Oban has no queues. The only route is
  `PageController :home`.
- `app.css` loads daisyUI plugins, and `core_components.ex` / `layouts.ex` use daisyUI
  classes. `AGENTS.md` requires hand-written Tailwind instead.
- Asset rules from `AGENTS.md`: only the `app.js` and `app.css` bundles; no external
  script or stylesheet links; no inline `<script>` in templates; JS goes in colocated
  hooks or `assets/js/`. This rules out CDN fonts and favors server-rendered charts.
- Users reach the app over the tailnet only, so there is no authentication in this change.
- Detection (AI plus heuristics) is owned by another teammate, and its shape (how it
  runs, what it emits, how it talks to the app) is not yet known. Anything this change
  assumes about it must be cheap to change.

## Goals / Non-Goals

**Goals:**
- A complete, live-updating mockup that a reviewer can click through with realistic data.
- Seams that isolate unknowns, so the AI side can be adapted without touching the UI:
  1. the UI talks only to `Dripstone.Tracker`;
  2. detection talks only to the findings intake;
  3. platforms and trigger types are registry entries.
- Exercise the intake end to end now, by feeding all sample alerts through it.

**Non-Goals:**
- Any detection logic: scoring, thresholds, clustering, snapshot formats or job
  scheduling. These belong to the detection owner.
- Pixel-perfect visuals. The wireframes fix layout and hierarchy; colors and spacing are
  tuned during implementation.
- Graph pan/zoom and physics animation. The graph is a static, server-laid-out SVG.
- Persistence. All state is in memory and resets on restart.

## Screen layouts

The wireframes show the desktop layout. On narrow screens the sidebar becomes a drawer,
grids stack into one column, and tables scroll horizontally inside their card.

### App shell (every screen)

```
┌─────────────┬──────────────────────────────────────────────────────────────┐
│ ◆ Dripstone │ [☰]  🔍 Search accounts by handle or name…        [◐ ☀ ☾]    │
│             ├──────────────────────────────────────────────────────────────┤
│ ▸ Overview  │  Page title                                 [page actions]   │
│   Alerts  7 │  One-line description                                        │
│   Networks  │  ──────────────────────────────────────────────────────────  │
│   Accounts  │                                                              │
│   Feeds     │                       page content                           │
│             │                                    ┌──────────────────────┐  │
│ ─────────── │                                    │ ▲ High · New network │  │ ← live toast
│ ● Sample    │                                    │ Sunrise Cluster  View│  │   (High only)
│   data      │                                    └──────────────────────┘  │
└─────────────┴──────────────────────────────────────────────────────────────┘
```

### Overview `/`

```
 ┌──────────────┐ ┌──────────────┐ ┌──────────────┐ ┌──────────────┐
 │ Open alerts  │ │ High severity│ │ Suspected    │ │ Tracked      │
 │ 7            │ │ 2            │ │ networks  9  │ │ accounts 1,284│
 └──────────────┘ └──────────────┘ └──────────────┘ └──────────────┘
 ┌─────────────────────────────────────────────┐ ┌───────────────────────┐
 │ Alerts raised · last 30 days            41  │ │ Newest open alerts    │
 │ ▁▂▂▃▂▅▇▆▄▃▃▂▄▅▆█▇▅▃▂▂▃▄▃▂▂▃▄▅▄             │ │ ▲ High  New network   │
 │ Oct 8                             Nov 7     │ │ ■ Med   Promotion …   │
 └─────────────────────────────────────────────┘ │ ● Low   Growth …      │
 ┌─────────────────────────────────────────────┐ │ Open inbox →          │
 │ Recently active networks          See all → │ └───────────────────────┘
 │ Sunrise Cluster  Suspected  86%  41 accts   │
 │ Bluewave Ring    Confirmed  97%  18 accts   │
 └─────────────────────────────────────────────┘
 Feeds:  ✕ Telegram Down  ·  ◐ Facebook Degraded  ·  ✓ X  ✓ Reddit  ✓ Bluesky  ✓ Mastodon
```

### Alerts inbox `/alerts`

```
 Alerts                                                      7 open
 Status [Open ▾]  Severity [All ▾]  Trigger [All ▾]  Platform [All ▾]
 ┌──────────────────────────────────────────────────────────────────────────┐
 │ NEW ▲ High  Sunrise Cluster switched to deals-b.example   Promotion shift│
 │             Sunrise Cluster · X, Bluesky                          2m ago │
 │     ■ Med   Bluewave Ring gained 9 accounts               Network growth │
 │             Bluewave Ring · Reddit · ↺ Previously dismissed       1h ago │
 │     ● Low   New network detected (64%)                    New network    │
 │             Cluster #0412 · Telegram                              5h ago │
 └──────────────────────────────────────────────────────────────────────────┘
```

### Alert detail `/alerts/:id`

```
 ← Alerts                                              ‹ k   2 of 7   j ›
 ▲ High · Promotion shift · Open · raised 2m ago
 Sunrise Cluster switched its main promoted domain
 ┌──────────────────────────────────────────┐ ┌───────────────────────────┐
 │ What changed                             │ │ Network                   │
 │ Before  deals-a.example   62% of links   │ │ Sunrise Cluster →         │
 │ After   deals-b.example   55% of links   │ │ Suspected · 86% · 41 accts│
 ├──────────────────────────────────────────┤ │ X, Bluesky                │
 │ Evidence                                 │ └───────────────────────────┘
 │ Strong    Domain share shift · 23 accts  │
 │ Moderate  New domain registered 3d ago   │
 │ Moderate  Same promo copy, new link …    │
 ├──────────────────────────────────────────┤
 │ ✦ AI-generated · 2m ago                  │
 │ The network moved its promotion to a     │
 │ newly registered domain using the same … │
 └──────────────────────────────────────────┘
 Note (optional) [______________________________________________]  0/500
 [ ✓ Confirm  C ]   [ ✕ Dismiss  D ]
   ✓ Confirmed · Undo                                  ← after a decision
```

### Network detail `/networks/:id` — Summary | Graph

```
 ← Networks
 Discount Spam Ring ✎     Suspected · 86% · 41 accounts · 2 open alerts →
 Detected as Sunrise Cluster · X, Bluesky · active Oct 3 – 2h ago · main domain deals-b.example
 #crypto-scam  #discount-spam  [+ tag]          [Merge into…] [Relate…] [⋯]
 [ Summary ]  Graph  Notes (3)  History
 ┌──────────────────────────────────────────┐ ┌───────────────────────────┐
 │ ✦ AI-generated · Nov 6, 14:02            │ │ Shared evidence           │
 │ A cluster of 41 recently created …       │ │ Strong   Same link     14 │
 └──────────────────────────────────────────┘ │ Strong   Persona tmpl  29 │
 ┌──────────────────────────────────────────┐ │ Moderate Created wk    33 │
 │ When members post (UTC)  Busiest: weekdays│ └───────────────────────────┘
 │ 09:00–10:00   [7×24 heatmap]             │ ┌───────────────────────────┐
 └──────────────────────────────────────────┘ │ Alert history             │
 ┌──────────────────────────────────────────┐ │ ▲ Promotion shift  Open   │
 │ Members (41)            [+ Add account]  │ │ ● New network  Confirmed  │
 │ ☐ @sunny_deals   X    ● High 91          │ ├───────────────────────────┤
 │ ☐ @deal_hunter22 X    ● High 84          │ │ Related networks          │
 │ 2 selected: [Move to…] [Split…] [Remove] │ │ Bluewave Ring →           │
 └──────────────────────────────────────────┘ └───────────────────────────┘

 Merge confirmation (modal):
 ┌───────────────────────────────────────────────────────┐
 │ Merge "Cluster #0417" into "Discount Spam Ring"?      │
 │ Moves 12 members, 2 alerts, 1 note and 2 tags.        │
 │ "Cluster #0417" will be retired and redirect here.    │
 │                              [Cancel]  [Merge]        │
 └───────────────────────────────────────────────────────┘

 Graph view:
 ┌──────────────────────────────────────────────────┐ ┌─────────────────────┐
 │        ●───●                                     │ │ @sunny_deals        │
 │       / \ / \        ●                           │ │ X · ● High 91       │
 │      ●───◉───●──────●                            │ │ Shared link     6   │
 │       \ /   \       /                            │ │ Near-dup text   11  │
 │        ●     ●─────●                             │ │ Open account →      │
 └──────────────────────────────────────────────────┘ └─────────────────────┘
 Legend: ━ Shared link [✓]  ━ Near-duplicate [✓]  ━ Synced posting [✓]  ━ Created together [ ]
```

### Account detail `/accounts/:id`

```
 ← Accounts
 @sunny_deals · Sunny Deals                                    ● High 91
 X · created Mar 2, 2026 · seen Oct 1 – 2h ago · View on X ↗
 ┌──────────────────────────────────────────┐ ┌───────────────────────────┐
 │ Why it scores high                       │ │ Networks                  │
 │ Posting cadence               +34 ██████ │ │ Sunrise Cluster →         │
 │ Persona consistency           +28 █████  │ │ Suspected · 86%           │
 │ Account age                   +17 ███    │ └───────────────────────────┘
 └──────────────────────────────────────────┘
 ┌──────────────────────────────────────────┐ ┌───────────────────────────┐
 │ Linked accounts (11)                     │ │ Recent activity           │
 │ @deal_hunter22  Near-dup · Shared link   │ │ 2h  "Huge discount…"      │
 │ @bargain.bot    Synced posting           │ │     deals-b.example ↗     │
 └──────────────────────────────────────────┘ └───────────────────────────┘
```

### Networks list, Accounts list, Feeds

The Networks and Accounts lists follow the inbox pattern: a filter bar over a streamed
table with URL-kept filters (see specs). Feeds is a single table:

```
 Feeds              Feeds are added in code: see docs/FEEDS.md
 Platform   Status         Last item   24h items   Accounts   Last error
 X          ✓ Healthy      12s ago     18,204      402        —
 Telegram   ✕ Down         3h ago      1,102       97         401 Unauthorized · 3h ago
 Facebook   ◐ Degraded     41m ago     2,881       133        —
```

## Decisions

### 1. `Dripstone.Tracker` is the only thing the UI calls
The LiveViews depend on one context module:
- **Reads:** `overview/0`, `list_alerts/1`, `get_alert/1`, `alert_neighbors/2`,
  `list_networks/1`, `get_network/1`, `network_graph/1`, `list_accounts/1`,
  `get_account/1`, `feed_health/0`, `list_tags/1`.
- **Decisions:** `confirm_alert/2`, `dismiss_alert/2`, `undo_decision/1`.
- **Curation:** `rename_network/2`, `add_tag/2`, `remove_tag/2`, `add_note/2`,
  `add_members/2`, `remove_members/2`, `move_members/3`, `merge_networks/2`,
  `split_network/3`, `relate_networks/3`, `unrelate_networks/2`.

Everything returns plain structs, or `{:ok, _}` / `{:error, changeset_or_reason}`. Today
the context delegates to `Dripstone.Tracker.SampleStore`, a GenServer holding all state.
Later the same functions move to Ecto with the same signatures, so the LiveViews don't
change.

Structs (`Account`, `Network`, `Link`, `Signal`, `Post`, `Evidence`, `Alert`,
`Decision`, `Note`, `HistoryEntry`, `FeedHealth`) each live in their own file under
`lib/dripstone/tracker/`.

- *Alternative: Ecto schemas now.* Rejected because the detection side may reshape the
  data, and migrations would churn.

### 2. The findings intake is the one seam for detection
- `Dripstone.Tracker.report_finding(attrs)` is the only function detection calls. `attrs`
  is a plain map, so detection can live in-process, in an Oban worker, or behind an HTTP
  endpoint added later.
- Validation uses a schemaless changeset. The trigger id must be in the catalog, there
  must be at least one evidence item, severity must be one of `low`, `medium`, `high`,
  and the network must be known (or the finding must describe a new one).
- The store then applies, in order:
  1. network updates, skipping analyst-protected fields and removed members;
  2. de-duplication against the open alert for the same trigger and network;
  3. the dismissal rule (`observed_at` must be after the dismissal; set
     `previously_dismissed_alert_id`; set the network back to Suspected);
  4. history entries marked `System`;
  5. a PubSub broadcast.
- It returns `{:ok, %{alert: alert, action: :created | :merged, skipped: [...]}}` or
  `{:error, reasons}`.
- `docs/DETECTION_INTERFACE.md` documents every field and result, with one example per
  trigger type. This is the document to agree with the detection owner. Changing it is
  expected; the UI shouldn't need to change when it does.

- *Alternative: the trigger framework with built-in detectors (the earlier draft).*
  Rejected because it would fix the detection architecture before the detection owner has
  designed it.

### 3. Trigger catalog = metadata only
- `Dripstone.Alerts.TriggerType` is a struct (`id`, `name`, `description`).
- The catalog is `config :dripstone, Dripstone.Alerts, trigger_types: [...]`, read by
  `Dripstone.Alerts.trigger_types/0` and `get_trigger_type/1`.
- Ids are strings, and filter params are matched against them, so no atoms are created
  from input.
- `docs/TRIGGERS.md` explains how to add a type. Its detector lives on the detection side
  and reports findings with that id.

### 4. Feed registry
- `Dripstone.Feeds.Feed` is a behaviour with `id/0` (string), `name/0`,
  `format_handle/1`, `profile_url/1`, `post_url/1` and `expected_interval/0`.
- The registry is `config :dripstone, Dripstone.Feeds, feeds: [...]`, with the six
  modules under `lib/dripstone/feeds/`.
- Unknown feed ids render as a plain label instead of crashing.
- `docs/FEEDS.md` explains how to add a platform. Ingestion callbacks are left out until
  the detection and ingestion design exists.

### 5. Sample data flows through the intake
- `Dripstone.Tracker.SampleData` generates the base data from a fixed seed: about 1,300
  accounts across six feeds, links, signals, posts and feed health.
- It also generates a time-ordered **list of findings** covering every spec scenario:
  - a promotion shift;
  - growth on a Confirmed network;
  - a reactivation;
  - a dismissed network that returns, plus a stale finding that is ignored;
  - a network with no AI rationale;
  - a 400-member network;
  - a Down feed and a Degraded feed.
- At boot, the store replays those findings through `report_finding/1`, applying seed
  decisions and curation (a renamed, tagged network; a removed member that a later finding
  tries to re-add) at the right points.
- The dev simulator (`Dripstone.Tracker.Simulator`, enabled by `DRIPSTONE_SIMULATE=1`)
  reports a new generated finding every 45 seconds.
- The intake is therefore exercised for real, and replacing sample data with detection
  only changes *who* calls `report_finding/1`.

### 6. Curation semantics
- **Protection:** `rename_network/2` sets `name` and keeps `detected_name`, which marks
  the name as analyst-protected. `remove_members/2` records the removals in the network's
  `removed_account_ids`, which the intake honors.
- **Merge:** `merge_networks(source, target)` moves members, alerts, notes and tags to the
  target. The target's status is the highest of the two by Confirmed > Suspected >
  Dismissed. The source becomes `retired_into: target_id`; it is excluded from lists, and
  its detail page shows a "merged into" notice.
- **Split:** `split_network(network, account_ids, name)` refuses an empty or full
  selection, and creates a Suspected network with `detected_name: nil`.
- **Tags:** normalized with `String.downcase/1`, with spaces turned into hyphens, then
  validated against `^[a-z0-9-]{1,32}$` and the 20-tag cap. Suggestions come from
  `list_tags(prefix)`.
- **History:** every mutation appends a `HistoryEntry` (`actor: :analyst | :system`, `by`,
  `at`, `summary`). Analyst actions are `Unattributed` until sign-in exists.
- **Confirmation:** destructive actions use a `<.modal>` that is rendered from a
  `pending_action` assign holding a server-computed impact summary. Nothing changes until
  the analyst confirms.

### 7. Live updates through PubSub and the nav hook
- The store broadcasts `{:alert_raised | :alert_updated, alert}` and
  `{:network_updated, network_id}` on the `"tracker"` topic.
- `DripstoneWeb.Nav` (`on_mount` for `live_session :tracker`) assigns `@nav` (active
  section, open count, toasts). It subscribes, and attaches `handle_info` hooks that update
  `@nav` (toasts only for High) and a `handle_event` hook for `global_search`.
- Every LiveView renders `<Layouts.app flash={@flash} nav={@nav}>`.
- The inbox `stream_insert`s matching alerts `at: 0`, with a `new_ids` set for highlighting.
- The network detail page reloads its data on `{:network_updated, id}` for its own id.

### 8. Server-laid-out SVG graph
`Tracker.network_graph/1` keeps the 150 most-linked members, then runs a seeded
Fruchterman–Reingold layout (200 iterations) in Elixir, cached per network and membership
version. It renders as SVG with `phx-click` node selection and link-type toggles, and
`?view=graph` is kept in the URL.

- *Alternative: a JS graph library in a hook.* Rejected for now because of the extra
  dependency and hook-owned DOM. It can be revisited if pan/zoom is needed.

### 9. Design tokens with Tailwind v4 `@theme`, daisyUI removed
- `app.css` drops daisyUI and defines semantic tokens in `@theme`, with
  `[data-theme=dark]` overrides: `canvas`, `surface`, `surface-raised`, `line`, `ink`,
  `ink-muted`, `accent`, `sev-*`, `risk-*`, `strength-*`, and one color per link type.
- The look is dark-first: stone-gray neutrals with a mineral-teal accent.
- Typography is the system UI stack, `tabular-nums` for figures and the mono stack for
  handles.
- The generator's theme script in `root.html.heex` stays, because it prevents a
  wrong-theme flash.
- `core_components.ex` is restyled in place, with names and attrs unchanged. A `modal`
  component is added.

### 10. Components
`DripstoneWeb.TrackerComponents` is imported in `html_helpers`. It contains `stat_tile`,
`severity_badge`, `risk_badge`, `status_pill`, `strength_badge`, `platform_badge`,
`tag_chip`, `ai_label`, `empty_state`, `page_header`, `filter_bar`, `pager`, `sparkline`,
`heatmap`, `toast_stack`, `network_graph` and `history_list`. Charts have text summaries
and `aria-label`s.

### 11. URL-driven lists with streams
- Filters, sort, page, view and tab live in query params. Forms use `to_form(params)` with
  `phx-change`, which does `push_patch`.
- `handle_params` parses the params against allow-lists or registry/catalog ids, and drops
  unknown values.
- Lists render through streams with `reset: true`, and totals live in separate assigns.
- Member selection for move, split and remove is kept in a `MapSet` assign. The member
  rows are re-streamed when the selection changes.
- The alert detail page carries the inbox query, so `j`/`k` follow the filtered order.

### 12. Keyboard shortcuts, decisions and undo
- `.AlertShortcuts` is a colocated hook: c/d/j/k, ignored inside `input`/`textarea`. It
  pushes the same events as the buttons.
- The decision note is validated by a schemaless changeset (500 characters or fewer).
- A `Decision` stores the alert's and network's previous statuses, so undo restores both.
  Only the last decision id is kept, so undo lasts until the next decision.
- Times: the heatmap is in UTC; elsewhere times are relative ("2h ago"), with the exact UTC
  time in a `<time title=…>`.

### 13. Not-found inside the shell
`get_*` returns `nil` for unknown ids, and the detail LiveViews render a not-found state
inside the shell. The trade-off is that the dead render returns 200 instead of 404, which
is acceptable for an internal tool.

## Risks / Trade-offs

- [The intake contract doesn't match what detection ends up producing] → It is one
  function over a plain map with a documented shape. Adapting means changing the map
  mapping and the doc, not the UI. Review `docs/DETECTION_INTERFACE.md` with the detection
  owner early.
- [Intake rules (dedupe, dismissal, protections) are subtle] → Table-driven unit tests per
  spec scenario, with the boot replay as an integration check.
- [Curation and detection disagree, e.g. detection wants to re-add a removed member] →
  Protections are explicit and reported back in `skipped`, so detection can see and log
  the conflict.
- [The shared store makes write tests order-dependent] → Write-path tests run with
  `async: false` and call `Tracker.reset_sample_data!/0` in `setup`. Read-only tests stay
  async.
- [Merge is hard to reverse] → A confirmation modal with a precise impact summary, plus
  the history entries. Unmerge is out of scope.
- [The graph layout is slow for large networks] → Capped at 150 nodes and cached per
  membership version.
- [Toast noise] → At most three toasts stacked. Later ones replace the oldest.
- [State vanishes on restart] → Expected for sample data. The `Sample data` indicator
  makes this visible.

## Migration Plan

Nothing is deployed and there is no persisted data. Removing `PageController`,
`PageHTML`, `home.html.heex` and their test is part of the change. To roll back, revert
the change's commits.

## Open Questions

- Final palette values and spacing: tuned during implementation against the wireframes.
- Simulator cadence and the mix of findings it generates: adjust during the demo.
