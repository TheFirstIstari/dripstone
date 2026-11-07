# Proposal

## Why

Dripstone is the team's analysis platform for finding bot farms on social platforms.
Detection (a live AI model on the `desktop` node, combined with heuristics) finds linked
accounts and suspected networks and raises alerts. Analysts review the evidence, confirm
or dismiss, and curate the networks. The team decides what to do next.

The detection side is owned separately and its interface isn't settled yet. This change
builds the analyst-facing app as a working mockup on sample data, plus the **thin backend
seams** detection will plug into later, so that the UI and workflow can be agreed now and
adapted cheaply once the AI side is concrete.

## What Changes

- Replace the Phoenix landing page with a Dripstone **app shell**: a sidebar (Overview,
  Alerts, Networks, Accounts, Feeds) with a live open-alert badge, a top bar with account
  search and a theme toggle, live High-severity toasts, and responsive behavior.
- **BREAKING (internal):** remove daisyUI and restyle `core_components.ex` / `layouts.ex`
  with hand-written Tailwind and a Dripstone light/dark palette, as `AGENTS.md` requires.
- Add the screens:
  - **Overview** (`/`): live counts, a 30-day alert trend, newest open alerts, recent
    networks, and feed health.
  - **Alerts** (`/alerts`, `/alerts/:id`): a live inbox; the detail page shows evidence
    by strength, before/after values and an AI-written rationale, with
    **Confirm** / **Dismiss**, notes, undo and keyboard shortcuts.
  - **Networks** (`/networks`, `/networks/:id`): a Summary view and a linked-account
    **Graph** view, alert history, and **curation tools**: rename, tag, notes, add, remove
    and move members, merge, split, related networks, and change history.
  - **Accounts** (`/accounts`, `/accounts/:id`): a filterable list; the detail page shows
    signals, linked accounts, networks and posts.
  - **Feeds** (`/feeds`): read-only health of each platform feed.
- Backend seams, kept deliberately small:
  - **`Dripstone.Tracker`**: the one interface the UI uses, for reads, decisions and
    curation. Sample data sits behind it now and real storage later.
  - **Findings intake**: the single entry point detection will call to report "trigger X
    fired for network Y with this evidence". The app owns validation, de-duplication,
    re-alerting after dismissal, respecting analyst changes, and live updates. The contract
    is documented for the detection owner.
  - **Trigger catalog**: trigger types (id, name, description) used for labels and
    filters. It starts with New network, Network growth, Network reactivation and Promotion
    shift, and adding one is a single entry. *Detection logic is not part of this change.*
  - **Feed registry**: X, Reddit, Bluesky, Mastodon, Telegram and Facebook, each a small
    module (handle format, profile and post links). Adding a platform is one module plus
    one registry line.
- Detection blends AI and heuristics, so evidence is not split into "AI" versus
  "heuristic". Only AI-written text (summaries, rationales) is labeled AI-generated.
- Sample data reaches the app *through the findings intake*, both at boot and from an
  optional dev simulator, so the intake contract is exercised end to end before detection
  exists.

## Capabilities

### New Capabilities
- `ui-shell`: layout, navigation, live badge and toasts, search, theming, design tokens,
  and shared empty, not-found and accessibility behavior.
- `overview-dashboard`: the landing summary of alerts, networks, accounts and feeds.
- `alert-inbox`: listing, inspecting, confirming and dismissing alerts, live arrival, and
  undo.
- `alert-intake`: the trigger catalog and the findings intake contract with detection,
  including de-duplication, re-alerting after dismissal, and respecting analyst changes.
- `network-views`: browsing networks, their evidence, members, alert history and graph.
- `network-curation`: rename, tags, notes, membership edits, merge, split, related
  networks, and change history.
- `account-views`: browsing accounts and inspecting signals, links, networks and posts.
- `feeds`: the pluggable feed registry and the Feeds health screen.

### Modified Capabilities
- None. The `project`, `ai-client` and `ci` requirements are unchanged. The UI never
  calls `Dripstone.AIClient`; AI output arrives as data through the intake.

## Impact

- **Code:** `router.ex`, `layouts.ex`, `core_components.ex`, `root.html.heex`, `app.css`.
  New LiveViews in `lib/dripstone_web/live/`, a tracker components module and a nav hook.
  `PageController`, its template and its test are removed.
- **New domain code:** `lib/dripstone/tracker*` (context, structs, intake, sample store,
  sample data, dev simulator), `lib/dripstone/alerts/*` (trigger catalog), and
  `lib/dripstone/feeds/*` (feed registry and six platform modules).
- **Docs:** `docs/DETECTION_INTERFACE.md` (the intake contract), `docs/FEEDS.md`
  (adding a platform) and `docs/TRIGGERS.md` (adding a trigger type).
- **Dependencies:** remove `:daisyui`. No new dependencies.
- **Out of scope:** detection logic and thresholds, real ingestion, Ecto schemas and
  migrations, authentication and attribution, live LLM calls, actions beyond
  confirm/dismiss, bulk actions, notifications outside the app, translation, presence
  indicators, and merge/split alerts.
