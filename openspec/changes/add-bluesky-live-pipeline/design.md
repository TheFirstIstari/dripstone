# Design

> Revised on 2026-11-08 against `main` at `4151328`, after the detection owner's
> persistence work (#111, #216), the corpus and refresh task (#201), the politeness
> layer (#220) and the test harness (#224) merged, and the production seeding fix
> (#230). Scheduling (#188) hasn't been started, so this change schedules its own
> Bluesky jobs.

## Context

- **Tracker state lives in Postgres.**
  - `Dripstone.Tracker` reads with `Store.load/0`, which rebuilds the whole `State` from
    the rows on every call.
  - Every change runs inside `Store.write/1`, a single-writer GenServer
    (`Tracker.Writer`): it loads, applies a pure function, then calls `Store.save/1`.
    That **deletes and re-inserts every tracker table** in one transaction.
  - `Store.override/1` already lets one process see an in-memory `State` instead of the
    rows (test-only today).
  - Changes broadcast on the `"tracker"` PubSub topic.
- **First-boot seeding** follows `config :dripstone, :load_sample_data` (#230): `true`
  seeds the sample rows, `:showcase` the showcase corpus, `false` (production) nothing.
- **The intake** (`Tracker.report_finding/1`) accepts account, group and trend findings.
  `Scorer.assess/2`, `assess_group/2` and `assess_trend/2` build the Jev question sets.
  Nothing calls the group and trend ones in production yet.
- **`Dripstone.Adapters.Polite.get/2`** (#220) is the shared polite GET: a per-host
  minimum gap, robots.txt rules, and 429 back-off honouring `Retry-After`. **Two bugs
  were found in review:**
  1. Its ETS table is created by, and owned by, whichever process calls it first. An
     ETS table dies with its owner, so in Oban (one process per job) the rate gate and
     the robots.txt cache reset after every job. This was verified.
  2. The gate's "check, then record" isn't atomic, so concurrent jobs can both skip the
     wait.
- **Datasets and harness.**
  - `mix dripstone.datasets.refresh` (alias `mix dripstone.refresh`) records adapter
    output to `priv/datasets/<platform>/<date>.jsonl`.
  - Its platform map and `Dripstone.Adapters` list only the X and Reddit stubs.
  - In tests, `Dripstone.Test.HttpGuard` makes any unstubbed `Req` call raise, and
    `Dripstone.Test.Corpus` resolves checked-in corpora.
- **Oban** runs one `default` queue (10) with no plugins. In production its config is
  re-asserted in `runtime.exs`.
- **Dev only.** `Tracker.Simulator` (`DRIPSTONE_SIMULATE=1`) refreshes feed health,
  queues `AssessWorker` jobs for the stub handles, and reports canned findings, all into
  the one dataset.
- **The sidebar** says "Sample data · Resets when the app restarts" everywhere
  (`layouts.ex`). That is now wrong twice over: production holds no sample data, and
  data no longer resets.
- **Bluesky (public, no auth):**
  - **Jetstream** (`wss://jetstream*.bsky.network/subscribe?wantedCollections=app.bsky.feed.post`)
    streams every public post as JSON: author DID, `time_us`, and the record with
    `text`, `createdAt`, link `facets` and `embed.external.uri`.
  - **The AppView** (`https://public.api.bsky.app/xrpc/`) serves
    `app.bsky.feed.getAuthorFeed` and `app.bsky.actor.getProfiles` (up to 25 actors per
    call).

## Goals / Non-Goals

**Goals:**
- The first real path from a live platform to alerts, with no hand-kept list.
- Demo and Live, switchable per session in every environment, with demo data never
  stored.
- Live pipeline writes stay cheap, despite every write rewriting the whole database.

**Non-Goals:**
- X and Reddit (#186, #187).
- Changing the store's whole-state save model (the detection owner's area; see Risks).
- A watch list editable in the UI, back-filling history, or following accounts beyond
  what bursts surface.

## Decisions

### 1. Datasets: Live is the database, Demo is a memory-only store
- **Live** is the existing database-backed `Store`, unchanged.
- **Demo** is a new `Dripstone.Tracker.DemoStore`. It's a GenServer holding one
  `State`, started on demand under a `DynamicSupervisor` the first time anyone switches
  to Demo. It's seeded from `SampleLoader.load/0` and never touches the database.
  - Its calls also serialise demo writes, the same way `Writer` does for Live.

**Routing happens inside `Store`, so `Tracker` and the pure modules don't change.**
- `Store.load/0`, `save/1` and `write/1` check `Dripstone.Tracker.dataset/0`. That reads
  `Process.get(:dripstone_dataset, :live)`, the same per-process mechanism
  `Store.override/1` already uses.
  - **For `:demo`,** they get, put and run against `DemoStore` instead of the database.
  - **For `:live`,** they behave exactly as today.
- **Each dataset has its own PubSub topic:** `"tracker"` (Live, unchanged) and
  `"tracker:demo"`. `Tracker.broadcast/1` and `subscribe/0` use the calling process's
  dataset.

**Who sets the dataset:**
- **`DripstoneWeb.Nav`'s `on_mount`** sets it from the session, so every LiveView reads
  and writes its session's dataset.
- **Background code** gets Live by default. The simulator sets `:demo` in its own
  process. `AssessWorker` takes an optional `"dataset"` arg, defaulting to `"live"`.
- **`Tracker.with_dataset/2`** wraps a block for callers that need to switch
  explicitly.

*Alternatives considered:*
- **A dataset argument on every `Tracker` function.** That's the Phoenix scope idiom,
  but it touches about 60 call sites and conflicts with ongoing tracker work.
- **A single global switch.** One analyst demoing would flip everyone's screens,
  including in production.

### 2. Live is never seeded with sample data outside tests
- **The `:load_sample_data` default becomes `false`** in `config/config.exs`, and
  **`true` only in `config/test.exs`**, where the existing tests rely on seeded rows.
- **Dev** then works like production: Live starts empty and fills from the pipeline,
  and the sample data is one switch away in Demo.
- **`DRIPSTONE_SAMPLE=showcase`** stays as an explicit dev option, seeding Live from the
  showcase corpus.
- **Existing dev databases keep their seeded rows.** The README tells developers to run
  `mix ecto.reset` once.

### 3. Switching
- **The sidebar control posts to `POST /mode`,** which sets `:data_mode` in the session
  and redirects back to the same path. The session cookie can only change through an
  HTTP request, so the switch is one page load, with no app restart.
- **Badge and banner:** the `Live` / `Demo` badge, and the banner while in Demo, render
  from the session's mode.
- **Starting the Demo store is idempotent:** if it already exists, the existing process
  is used.

### 4. What Demo contains
- **Data:** the sample seed.
- **Live alerts:** the simulator is started *with* the Demo store, in every environment,
  and targets Demo. Its canned findings, feed-health refreshes and `AssessWorker` jobs
  all carry `:demo`.
- **`DRIPSTONE_SIMULATE`:** no longer needed for Demo. It still starts the simulator at
  boot in dev, for people who want Demo pre-warmed.

### 5. Fix the politeness layer first
- **`Dripstone.Adapters.Polite.Gate`** is a small GenServer started in `application.ex`.
  It **owns** the ETS table (rate-gate timestamps and robots.txt cache), so the state
  survives individual jobs.
- **Rate slots are reserved atomically:** `Gate.reserve(host, interval_ms)` is one
  `GenServer.call`. It returns how long the caller must wait, and records the slot in
  the same step. Concurrent jobs to one host are therefore spaced correctly.
- **`Retry-After` given as an HTTP date** is parsed, rather than read as 0.
- **Robots rules** are cached for 24 hours rather than forever.
- **`Polite.get/2`'s signature and errors are unchanged,** so its existing tests keep
  passing.

### 6. Jetstream consumer
`Dripstone.Discovery.Jetstream` is a supervised process using `mint_web_socket`
(**dependency pending approval**).
- **Enabled by** `config :dripstone, Dripstone.Discovery, enabled:`: `false` in test,
  `true` in production, and set from `DRIPSTONE_DISCOVERY=1` in dev.
- **Subscription:** `wantedCollections=app.bsky.feed.post`.
- **Links** come from facets (`app.bsky.richtext.facet#link`) and `embed.external.uri`.
- **URL normalisation:** lowercase the host, and strip `utm_*`/`fbclid`/`ref` parameters
  and the fragment.
- **Reconnects** with back-off, resuming from the last `time_us` cursor.
- **Feed health without per-post writes.** The consumer keeps the Bluesky counters in
  memory (last item time, rolling 24-hour count, connection state, last error). It
  **flushes them to the Live dataset once every 60 seconds** in a single `Store.write`.
  A per-post write would rewrite the database hundreds of times a second.

*Alternative considered:* polling the AppView on a timer. Polling can't discover
accounts the app doesn't already know.

### 7. Burst detector
`Dripstone.Discovery.Bursts` is pure functions over bounded state, held by the consumer.

**Windows:** per normalised URL, the distinct DIDs seen within `window` (default 10
minutes), pruned as time passes.

**A candidate** `%{url, domain, dids, first_at, last_at}` is emitted when distinct DIDs ≥
`threshold` (default 5). The URL then enters `cooldown` (default 6 hours).

**Bounds:**
- at most `max_tracked_links` (default 50,000), with the oldest windows dropped first;
- a configured `common_domains` ignore list (bsky.app, youtube.com, youtu.be, x.com,
  twitter.com, instagram.com, tiktok.com, google.com, wikipedia.org, github.com, and
  news sites as needed).

**One-account bursts:** the same DID repeating a link counts once.

### 8. Assessing a candidate, in one write
`Dripstone.Workers.DiscoverWorker` (Oban, `max_attempts: 1`, unique per URL for the
cooldown) does the following:
1. **Checks caps first:** a token bucket for groups per hour (default 20), and a
   per-account re-assessment interval (default 24 hours). Both are held in an ETS table
   owned by a supervised process. Over the cap, it records a skip and stops.
2. **Resolves DIDs to handles** with `getProfiles` (batches of 25), and trims to
   `max_group_size` (default 10).
3. **Fetches each member's recent posts** with `Adapters.Bluesky.fetch_posts/2`: the
   AppView `getAuthorFeed` (limit 30, no replies), through `Polite.get/2`.
4. **Builds one account finding per fetched member** (`Scorer.assess/2`). **If at least
   two were fetched, it also builds a group finding** (`Scorer.assess_group/2`), with
   `heuristics.domains` computed from the members' posts. That makes Promotion shift
   reachable.
5. **Reports everything in one call:** `Tracker.report_findings/1`. That's a new batch
   variant that loads once, runs `Report.cast` and `Rules.run` for each finding in
   order, saves once, then broadcasts. A candidate group therefore costs **one**
   database rewrite, not eleven.

All of this goes to **Live**.

### 9. Trend re-checks on a schedule
- **`Oban.Plugins.Cron` and `Oban.Plugins.Pruner`** are added to the Oban config in
  `config.exs` **and** `runtime.exs`, because production re-asserts the Oban config
  there.
- **`Dripstone.Workers.TrendWorker`** runs every 6 hours. For each live network with
  member activity in the last day, it reports a trend finding (`Scorer.assess_trend/2`)
  over the members' recent posts. It's capped per hour, and it batches through
  `report_findings/1`.
- **This only covers Bluesky trend scheduling.** Generic per-platform refresh scheduling
  stays with #188.

### 10. Account identity
- **Bluesky handles can change; DIDs don't.** So an optional `external_id` is added to
  `Account`: a new column on `tracker_accounts` (migration), mapped in `Store`'s account
  row conversion.
- **`DiscoverWorker`** resolves an existing account by `external_id` first, then by
  feed and handle.

### 11. Data-source badge and banner
- **`Layouts.app/1`** reads the session's mode (via `@nav`). It replaces the hard-coded
  "Sample data" text with the Live/Demo indicator and switch.
- **A banner** shows on every screen in Demo: "Demo data — not real detections. Switch to
  Live".

## Risks / Trade-offs

- **Every Live write rewrites the whole database** (the current `Store.save/1`). The
  cost grows with the data.
  → The pipeline batches: one write per candidate group (§8), a feed-health flush once a
  minute (§6), and batched trend checks (§9). Caps bound how many writes there are.
  Incremental saves are the real fix, and are flagged to the detection owner. They
  belong to their persistence work, not this change.
- **Every read loads the whole database** as well. → It's out of scope here. Demo reads
  are in memory, so demos stay fast.
- **The stream's volume.** → Only linked posts are kept, the detector is bounded, and
  no per-post work is queued.
- **False positives from organic virality.** → The common-domain list, a threshold on
  distinct accounts, and Jev's `coordinated` answer as the gate for alerts. Thresholds
  stay in config.
- **Bluesky API limits aren't published.** → The fixed politeness layer, the caps and
  DID batching.
- **Implicit per-process dataset selection.** → It's confined to `Tracker.dataset/0` and
  the `Store` dispatch. Background code defaults to Live, and tests cover isolation.
- **Demo in production holds the sample seed in memory** once someone opens it. → It's
  built only on demand.
- **The new dependency** (`mint_web_socket`). → It's small, from the Mint family under
  Req. **It needs approval.**

## Migration Plan

- **One migration** adds `tracker_accounts.external_id`.
- **Production:** Live stays as it is (empty, per #230), and discovery fills it once
  enabled.
- **Development:** run `mix ecto.reset` once to drop the previously seeded sample rows
  from Live.
- **To roll back,** disable discovery in config. The mode switch keeps working.

## Open Questions

- **The starting values** for the discovery threshold, window and caps. They're
  configurable, and will be tuned from the first days of real data.
