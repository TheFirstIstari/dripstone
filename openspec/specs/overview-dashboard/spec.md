# overview-dashboard Specification

## Purpose
Gives analysts a single landing screen that summarizes what needs attention (open
alerts) and what Dripstone is tracking, with links into the detailed screens.

## Requirements

### Requirement: Overview is the landing page
The root path `/` SHALL show the Overview screen inside the app shell.

#### Scenario: Opening the app
- **WHEN** a user opens `/`
- **THEN** the Overview screen is shown with Overview marked active in the navigation

### Requirement: Headline counts
The Overview SHALL show four headline counts: open alerts, open High severity alerts,
Suspected networks, and tracked accounts. Each count SHALL link to the matching filtered
screen, and the counts SHALL update live.

#### Scenario: High severity count links to filtered inbox
- **WHEN** a user selects the open High severity count
- **THEN** the Alerts screen opens filtered to Open and High

#### Scenario: Counts update live
- **WHEN** an alert is raised while the Overview is open
- **THEN** the open alerts count increases without a reload

### Requirement: Alert trend
The Overview SHALL show a chart of alerts raised per day over the last 30 days, with the
period total stated in text.

#### Scenario: Trend with data
- **WHEN** alerts were raised during the last 30 days
- **THEN** the chart shows one value per day for 30 days and the period total in text

#### Scenario: No alerts in the period
- **WHEN** no alerts were raised in the last 30 days
- **THEN** the chart area shows an empty state instead of a flat line

### Requirement: Newest open alerts
The Overview SHALL list up to five of the newest Open alerts with severity, title and
age, each linking to its detail page, plus a link to the inbox.

#### Scenario: Queue is clear
- **WHEN** no alerts are open
- **THEN** the list says there is nothing waiting for review

### Requirement: Recently active networks
The Overview SHALL list up to five networks ordered by most recent activity, each with
name, status, confidence and member count, linking to its detail page.

#### Scenario: Network list
- **WHEN** there are eight networks
- **THEN** the five most recently active are listed, with a link to see all networks

### Requirement: Feed health strip
The Overview SHALL show each registered feed's name and health status, and link to the
Feeds screen. Feeds that are not Healthy SHALL be listed first.

#### Scenario: A feed is down
- **WHEN** the Telegram feed is Down
- **THEN** Telegram appears first in the strip with the `Down` label
