# network-views Specification

## Purpose
Lets analysts browse suspected bot farms (networks of linked accounts) and inspect the
members, evidence and alert history that define each one, through a simple summary and
an optional graph for deeper investigation.

## Requirements

### Requirement: Network statuses
Every network SHALL have exactly one status: Suspected, Confirmed or Dismissed. The
status SHALL be shown as a text label wherever the network appears, and SHALL change
only through alert decisions, re-alerting or merges.

#### Scenario: Status label
- **WHEN** a network has been confirmed through an alert
- **THEN** it is shown with the label `Confirmed`

### Requirement: Network list
The Networks screen SHALL list networks with name, status, confidence (0–100%), member
count, platforms, open alert count, and first and last activity. It SHALL default to the
most recently active first, SHALL exclude networks retired by a merge, and each entry
SHALL link to its detail page.

#### Scenario: Default order
- **WHEN** a user opens `/networks`
- **THEN** networks are listed with the most recently active first

### Requirement: Network filters
The Networks screen SHALL filter by status and platform. Filters SHALL be kept in the
URL, and the platform options SHALL be the registered feeds.

#### Scenario: Hiding dismissed networks
- **WHEN** a user filters to status `Suspected`
- **THEN** only Suspected networks are listed and the URL records the filter

### Requirement: Network summary
The network detail page SHALL show the network's name, tags, status, confidence, member
count, platforms, first and last activity, current main promoted domain, and number of
open alerts linking to them, plus the curation controls from the network curation
capability.

#### Scenario: Opening a network
- **WHEN** a user opens a network's detail page
- **THEN** its summary fields are shown at the top of the page

### Requirement: Summary and graph views
The network detail page SHALL offer a Summary view (the default) and a Graph view, and
the selected view SHALL be kept in the URL.

#### Scenario: Linking to the graph
- **WHEN** a user switches to the Graph view and copies the URL
- **THEN** opening that URL shows the same network in the Graph view

### Requirement: AI-written summary
The Summary view SHALL show a narrative summary written by the AI model, labeled as
AI-generated with its generation time. If no summary exists, the page SHALL say so.

#### Scenario: Summary is labeled
- **WHEN** a network has an AI-written summary
- **THEN** it is shown under a visible `AI-generated` label with its generation time

#### Scenario: No summary yet
- **WHEN** a network has no AI-written summary
- **THEN** the summary area states that no summary has been generated

### Requirement: Shared evidence
The Summary view SHALL list the evidence linking members, such as shared links,
near-duplicate content, synchronized posting or similar creation dates. Each item SHALL
show its strength and how many members it involves.

#### Scenario: Shared link evidence
- **WHEN** 14 members of a network posted the same link
- **THEN** the evidence list shows a shared-link item with its strength, involving 14 members

### Requirement: Posting synchronization heatmap
The Summary view SHALL show members' posting activity by hour of day and day of week as
a heatmap, with the busiest period stated in text.

#### Scenario: Coordinated posting is visible
- **WHEN** a network's members mostly post between 09:00 and 10:00 UTC on weekdays
- **THEN** the heatmap is darkest in those cells and the text names that window

### Requirement: Member accounts
The Summary view SHALL list the network's members with handle, platform, risk level and
score, and the date each joined the network, each linking to the account detail page.

#### Scenario: Navigating to a member
- **WHEN** a user selects a member on a network page
- **THEN** that account's detail page opens

### Requirement: Alert history
The network detail page SHALL list every alert for the network, newest first, with
trigger, severity, status, decision details, and a marker on alerts raised after an
earlier dismissal. Each entry SHALL link to the alert.

#### Scenario: Previously dismissed network
- **WHEN** a network was dismissed and later re-alerted
- **THEN** its alert history shows the dismissed alert and the newer alert marked
  `Previously dismissed`

### Requirement: Graph of linked accounts
The Graph view SHALL draw members as nodes and links between members as lines, colored
by link type with a legend. Link types SHALL be toggleable to show or hide them.

#### Scenario: Hiding a link type
- **WHEN** a user hides the `Shared link` type
- **THEN** lines of that type disappear, and nodes left with no visible lines are dimmed

### Requirement: Inspecting a graph node
Selecting a node in the Graph view SHALL highlight its direct links and show a panel
with the account's handle, platform, risk level, link count by type, and a link to the
account's detail page.

#### Scenario: Selecting a node
- **WHEN** a user selects a node
- **THEN** its direct links are highlighted and its account panel is shown

### Requirement: Large network graphs
For networks with more than 150 members, the Graph view SHALL draw the 150 most-linked
members and state how many were left out, with a pointer to the full member list.

#### Scenario: Very large network
- **WHEN** a user opens the Graph view for a network with 400 members
- **THEN** 150 members are drawn and the view states that 250 members are not shown
