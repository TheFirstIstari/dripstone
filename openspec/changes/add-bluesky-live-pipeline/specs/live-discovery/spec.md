# Spec Delta

## Purpose

Finds candidate coordinated accounts in a live public platform stream, assesses them
with heuristics and the decision model, and reports the results through the findings
intake, so real alerts can arise without a hand-kept watch list.

## ADDED Requirements

### Requirement: Live stream ingestion
When live discovery is enabled, the app SHALL consume Bluesky's public Jetstream post
stream without authentication, and keep only posts that carry at least one link. When
discovery is disabled (the default in tests), no connection SHALL be made.

#### Scenario: Linked posts are kept
- **WHEN** the stream delivers one post with an external link and one without
- **THEN** only the post with the link is considered for burst detection

#### Scenario: Disabled by configuration
- **WHEN** the app starts with live discovery disabled
- **THEN** no connection to the stream is opened

### Requirement: Burst prescreening
The app SHALL treat a link posted by at least a configured number of distinct accounts
within a configured window as a candidate group. Links on a configured list of very
common domains SHALL be ignored, and the same link SHALL not produce a new candidate
again within a configured cooldown.

#### Scenario: Five accounts share a link within ten minutes
- **WHEN** five different accounts post `https://deals.example/x` within ten minutes,
  with a threshold of five and a ten-minute window
- **THEN** one candidate group of those five accounts is produced for that link

#### Scenario: Common domain ignored
- **WHEN** twenty accounts post links to `youtube.com` within a minute, and `youtube.com`
  is on the common-domain list
- **THEN** no candidate group is produced

#### Scenario: Cooldown
- **WHEN** a link has produced a candidate group and two more accounts post it within the
  cooldown
- **THEN** no second candidate group is produced for that link

### Requirement: Assessment caps
The app SHALL cap live assessment work: candidate groups assessed per hour, accounts per
group, and how often the same account is re-assessed. Work over a cap SHALL be skipped
and counted, not queued without bound.

#### Scenario: Hourly cap reached
- **WHEN** the hourly cap is 20 and a twenty-first candidate group arrives within the
  hour
- **THEN** it is not assessed, and the skipped count increases

#### Scenario: Large burst trimmed
- **WHEN** a candidate group has 40 accounts and the per-group limit is 10
- **THEN** only 10 of its accounts are fetched and assessed

### Requirement: Bluesky fetcher
The app SHALL have a Bluesky fetcher behind the shared `fetch_posts(handle, opts)`
behaviour. It SHALL read an account's recent posts from the public read API without
authentication, return them as canonical posts (id, handle, text, links, publish time),
and use the shared politeness rules (rate limits, back-off on 429).

#### Scenario: Recent posts fetched
- **WHEN** the fetcher is asked for `alice.bsky.social`
- **THEN** it returns her recent posts with ids, text, links and publish times, with no
  credentials used

#### Scenario: Rate limited
- **WHEN** the public API answers 429
- **THEN** the fetcher backs off and retries per the shared politeness rules, and returns
  an error if retries are exhausted

### Requirement: Candidates become findings
For each assessed candidate group, the app SHALL report an account finding for every
member it could fetch, then one group finding for the group. The group finding SHALL
carry the members' link-domain shares as heuristics, so the Promotion shift rule can
apply.

#### Scenario: A candidate group raises a real alert
- **WHEN** a candidate group of five accounts is assessed and the decision model answers
  `coordinated` 0.9
- **THEN** five account findings and one group finding are reported, and a `New network`
  alert is raised in the Live dataset

#### Scenario: Unreachable account
- **WHEN** one member of a candidate group can't be fetched
- **THEN** the others are still assessed, and the group finding names only the fetched
  accounts (if at least two remain)

### Requirement: Trend re-checks
The app SHALL periodically report a trend finding for each live network that has been
active within a configured period, using its members' recent posts, so trajectory
changes can raise alerts.

#### Scenario: Active network re-checked
- **WHEN** a live network had member activity in the last day and its re-check is due
- **THEN** a trend finding is reported for it

### Requirement: Feed health from ingestion
While live discovery runs, the Bluesky feed's health SHALL come from the stream itself:
the time of the last item received, the number of items in the last 24 hours, and the
last error. Its status SHALL be Down while the stream is disconnected.

#### Scenario: Stream disconnected
- **WHEN** the stream connection drops and hasn't reconnected
- **THEN** the Feeds screen in Live mode shows Bluesky as Down, with the error and the
  time it happened
