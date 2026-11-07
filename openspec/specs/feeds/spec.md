# feeds Specification

## Purpose
Defines how social platforms plug into Dripstone, as a registry of self-contained feeds,
and gives analysts a read-only view of each feed's health.

## Requirements

### Requirement: Pluggable feeds
Platforms SHALL be self-contained feeds listed in a single registry. Adding a platform
SHALL require only the new feed and a registry entry. Once registered, the platform SHALL
appear in every platform filter, badge and the Feeds screen with no other change.

#### Scenario: Adding a platform
- **WHEN** a developer adds and registers a new feed
- **THEN** the platform appears as an option in the Accounts, Networks and Alerts
  platform filters, and as a row on the Feeds screen

### Requirement: Built-in feeds
The registry SHALL include feeds for X, Reddit, Bluesky, Mastodon, Telegram and Facebook.

#### Scenario: Initial platforms
- **WHEN** a user opens the platform filter on the Accounts screen
- **THEN** X, Reddit, Bluesky, Mastodon, Telegram and Facebook are listed

### Requirement: Feed contract
Each feed SHALL declare a stable identifier and a display name, and SHALL provide how to
display an account handle and how to build links to an account's profile and to a post
on that platform.

#### Scenario: Platform-specific handle
- **WHEN** a Mastodon account `alice` on instance `example.social` is displayed
- **THEN** its handle is shown as `@alice@example.social` and its profile link points to
  that instance

### Requirement: Feed health
Each feed SHALL report a health status (Healthy, Degraded, Down or Not connected), the
time the last item was received, items received in the last 24 hours, and its most recent
error if any.

#### Scenario: Degraded feed
- **WHEN** a feed has received no items for longer than its expected interval
- **THEN** its status is Degraded and the last-received time is shown

### Requirement: Feeds screen
The Feeds screen SHALL list every registered feed with its name, health status, last
item time, 24-hour item count, and the number of accounts tracked on that platform.
It SHALL be read-only.

#### Scenario: Viewing feeds
- **WHEN** a user opens `/feeds`
- **THEN** each registered feed is listed with its health details, and no controls for
  adding, editing or removing feeds are shown

#### Scenario: Feed with an error
- **WHEN** a feed's status is Down
- **THEN** its row shows the most recent error message and when it occurred

### Requirement: Adding a feed is documented
The Feeds screen SHALL state that feeds are added in code and SHALL point to the
repository document that explains how to add one.

#### Scenario: Looking for how to add a feed
- **WHEN** a user reads the Feeds screen
- **THEN** it names the repository document that describes how to add a feed
