# Proposal

> Revised on 2026-11-08 against `main` at `4151328`. That's after the detection owner's
> persistence work (#111, #216), corpus and refresh task (#201), politeness layer (#220),
> test harness (#224), and the production seeding fix (#230). Refresh scheduling (#188)
> hasn't been started, so this change schedules its own Bluesky jobs.

## Why

Nothing real reaches the app:
- The only fetchers are stubs that read test files.
- Nothing is scheduled.
- Nothing produces group or trend findings.

So every account, network and alert comes from sample, showcase or simulated data. In
production, every screen is empty.

The detection owner's research rules out the obvious live sources. X has no viable free
collection. New Reddit API access closed on 31 Oct 2026, and Reddit RSS ends on 13 Nov
2026. Bluesky is the one platform with a free, public, unauthenticated live stream
(Jetstream) and public read APIs.

There is no curated list of known bot accounts to watch, so the pipeline has to find
candidates itself.

The app must also stay easy to demo. Real coordinated activity rarely happens on cue, so
analysts need to show real data and then switch to a demo dataset where alerts arrive
reliably.

## What Changes

**Live discovery on Bluesky.**
- **Listen** to Jetstream for public posts that carry links.
- **Detect bursts:** the same link posted by several different accounts within a short
  window. A burst is a candidate group. This is the "prescreening" the intake contract
  has been waiting for.
- **Cap the work:** candidates per hour, accounts per group and a cooldown per link, so
  the Jev budget and Bluesky's public API are respected.

**A Bluesky fetcher** behind the shared `fetch_posts(handle, opts)` behaviour. It reads
recent posts from the public AppView API through the shared politeness layer
(`Adapters.Polite`), and its captures can be recorded with the existing refresh task.

**Fixes to the politeness layer** before anything relies on it. Its rate-limit and
robots.txt memory currently disappears after every background job, and concurrent jobs
can both skip the wait. Both were found in review and verified.

**Cheap Live writes.** Every tracker write currently rewrites the whole database, so the
pipeline batches its writes:
- one write per candidate group (a new `Tracker.report_findings/1`);
- feed health flushed once a minute.

**Assessment of candidates.** For each candidate group, a background job:
1. fetches each member's recent posts;
2. reports an **account finding** per member (`Scorer.assess`);
3. reports a **group finding** (`Scorer.assess_group`), with link-domain shares computed
   from the posts.

Real **New network** and **Network growth** alerts can then arise. Promotion shift can
fire too, because the heuristics now produce `domains`. Live networks get periodic
**trend findings** (`Scorer.assess_trend`).

**Real Bluesky feed health.** The last item received, items in the last 24 hours, and the
connection state (Healthy, Degraded or Down) come from the actual stream.

**Demo and Live data modes.**
- The app keeps **two datasets**:
  - **Live**, filled only by the pipeline;
  - **Demo**, the sample seed plus the dev simulator's canned findings.
- Each analyst switches between them in the app, per session, with no restart.
- Changes made in Demo (decisions, curation) never touch Live.
- The live pipeline keeps running in the background whichever mode is shown.

**Production stays honest.**
- Live is the default everywhere.
- Demo can be switched on in production, but the demo dataset is only built on first use.
- A clear banner shows whenever demo data is on screen.

**An accurate data-source badge.** The sidebar's hard-coded "Sample data · Resets when
the app restarts" label becomes a correct **Live** / **Demo** badge with the switch.

**Not in scope:**
- X and Reddit fetchers (the detection owner's #186 and #187);
- changing the store's whole-state save and load model (the detection owner's
  persistence work; flagged to them, see design Risks);
- generic per-platform refresh scheduling (#188);
- a hand-kept watch list (discovery finds candidates instead);
- AI-written text;
- the temporal, attention, circadian, adversarial and watcher features.

## Capabilities

### New Capabilities
- `live-discovery`: finds and assesses candidate coordinated accounts from a live
  platform stream. It covers stream ingestion, burst-based prescreening, caps, the
  assessment of candidates into findings, and feed health derived from ingestion.
- `data-modes`: the Live and Demo datasets, switching between them per session, keeping
  them isolated, and the defaults and banner rules (including production).

### Modified Capabilities
- `ui-shell`: "Data source indicator" now shows Live or Demo accurately, with the switch
  next to it. The hard-coded "Sample data" label goes.

## Impact

- **New code:**
  - `Dripstone.Discovery.Jetstream`, the consumer, and `Dripstone.Discovery.Bursts`;
  - `Dripstone.Adapters.Bluesky`;
  - `Dripstone.Workers.DiscoverWorker` and `TrendWorker`;
  - `Dripstone.Tracker.DemoStore`;
  - `Polite.Gate`;
  - `Tracker.report_findings/1`;
  - a `POST /mode` controller.
- **Changed code:**
  - `Dripstone.Tracker.Store`: dispatches load, save and write by dataset;
  - `Dripstone.Tracker`: `dataset/0`, `with_dataset/2`, and a topic per dataset;
  - `DripstoneWeb.Nav` and `layouts.ex`: the mode and its badge, plus the banner;
  - `Simulator` and `AssessWorker`: dataset targeting;
  - `Adapters.Polite`: the fixes above;
  - `Dripstone.Adapters` and the refresh task: Bluesky registered;
  - `application.ex`: the gate, the consumer, and the Demo supervisor.
- **Config:**
  - the `:load_sample_data` default becomes `false`, except in tests;
  - discovery enable flag and caps;
  - Oban `Cron` and `Pruner` plugins in `config.exs` and `runtime.exs`.
- **Database:** one migration adds `tracker_accounts.external_id` (the Bluesky DID).
- **Dependencies:** a WebSocket client for Jetstream. The proposal is `mint_web_socket`,
  from the Mint family already under Req. **It needs approval.**
- **Docs:**
  - `openspec/docs/FEEDS.md` (a feed with a real fetcher);
  - `DETECTION_INTERFACE.md` ("Not covered yet" shrinks);
  - README: modes, enabling discovery, and `mix ecto.reset` once in dev to drop
    previously seeded sample rows.
