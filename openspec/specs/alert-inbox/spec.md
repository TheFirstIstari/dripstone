# alert-inbox Specification

## Purpose
Lets analysts see the alerts the detection system raises, inspect the evidence behind
each one, and confirm or dismiss it, so that a human decides whether a bot farm exists.

## Requirements

### Requirement: Alert fields
Every alert SHALL have a title, the trigger that raised it, a severity (Low, Medium or
High), a status (Open, Confirmed or Dismissed), the network it concerns, the time it was
raised, and the evidence that caused it.

#### Scenario: Alert shown with its fields
- **WHEN** an alert raised by the promotion shift trigger is displayed
- **THEN** its title, `Promotion shift` trigger label, severity, status, network and
  raised time are shown

### Requirement: Alert inbox
The Alerts screen SHALL list alerts, newest first, showing each alert's severity, title,
trigger, network, platforms and age. It SHALL show only Open alerts by default, and each
entry SHALL link to the alert's detail page.

#### Scenario: Default inbox
- **WHEN** a user opens `/alerts`
- **THEN** only Open alerts are listed, newest first

### Requirement: Alert filters
The inbox SHALL filter by status, severity, trigger and platform, combining filters with
AND. The filters SHALL be kept in the URL, and the trigger and platform options SHALL be
the trigger catalog entries and registered feeds.

#### Scenario: Filtering by trigger
- **WHEN** a user filters to trigger `Network growth` and severity `High`
- **THEN** only High severity alerts raised by the network growth trigger are listed, and
  the URL records both filters

#### Scenario: Newly registered trigger appears as a filter
- **WHEN** a new trigger type is added to the trigger catalog
- **THEN** it appears as an option in the trigger filter without changes to the screen

### Requirement: Live arrival
New alerts that match the current filters SHALL appear at the top of the inbox without a
reload, and SHALL be visually highlighted until the user next interacts with the inbox.

#### Scenario: Alert arrives while viewing the inbox
- **WHEN** a new Open alert is raised while a user views the default inbox
- **THEN** it appears at the top of the list, highlighted as new

#### Scenario: Alert outside the filters
- **WHEN** a new Low severity alert is raised while the inbox is filtered to High severity
- **THEN** the list does not change

### Requirement: Alert detail evidence
The alert detail page SHALL show the alert's fields and a summary of its network, plus
the evidence behind the alert, strongest first. Each evidence item SHALL show a
plain-language explanation, its strength (Weak, Moderate or Strong), and the accounts
it involves.

#### Scenario: Evidence listed by strength
- **WHEN** an alert has one Strong and two Moderate evidence items
- **THEN** the Strong item is listed first, and each item shows its strength label,
  explanation and involved accounts

#### Scenario: AI rationale is labeled
- **WHEN** the alert includes an AI-written rationale
- **THEN** it appears under a visible `AI-generated` label with its generation time

### Requirement: Before and after evidence
For alerts that compare a network over time, such as growth or a promotion shift, the
detail page SHALL show the relevant values before and after the change.

#### Scenario: Promotion shift comparison
- **WHEN** an alert's finding reports that a network switched its main promoted domain
- **THEN** the detail page shows the previous domain and the new domain, each with its
  share of the network's links

### Requirement: Confirming an alert
The analyst SHALL be able to confirm an Open alert, with an optional note of up to 500
characters. Confirming SHALL set the alert to Confirmed, set its network to Confirmed,
and record who confirmed it, when, and the note.

#### Scenario: Confirming a new network
- **WHEN** an analyst confirms an Open alert for a Suspected network
- **THEN** the alert and the network both become Confirmed, and the confirmation appears
  in the network's alert history

#### Scenario: Note is too long
- **WHEN** an analyst enters a note longer than 500 characters
- **THEN** the alert is not changed and an error explains the limit

### Requirement: Dismissing an alert
The analyst SHALL be able to dismiss an Open alert as a false positive, with an optional
note of up to 500 characters. Dismissing SHALL set the alert to Dismissed and record who
dismissed it, when, and the note. If the network has no Confirmed alerts, it SHALL become
Dismissed. Dismissing SHALL NOT stop future alerts for the network.

#### Scenario: Dismissing a false positive
- **WHEN** an analyst dismisses the only alert of a Suspected network
- **THEN** the alert and the network both become Dismissed

#### Scenario: Dismissing does not mute
- **WHEN** a network has been dismissed
- **THEN** its alerts remain eligible to be raised by triggers, as defined in the alert
  intake capability

### Requirement: Undo last decision
After confirming or dismissing an alert, the analyst SHALL be able to undo that decision
until they make another one. Undoing SHALL restore the alert and its network to their
previous statuses.

#### Scenario: Undoing a dismissal
- **WHEN** an analyst dismisses an alert and then selects Undo
- **THEN** the alert is Open again and the network has its previous status

### Requirement: Keyboard workflow
On the alert detail page the keys `c` (confirm), `d` (dismiss), `j` (next alert in the
inbox) and `k` (previous alert in the inbox) SHALL work, and SHALL be shown next to their
controls. Keys SHALL be ignored while a text field has focus.

#### Scenario: Confirm by keyboard
- **WHEN** an analyst presses `c` on an Open alert while not typing in the note field
- **THEN** the alert is confirmed, as if the Confirm button had been used

#### Scenario: Typing a note
- **WHEN** an analyst types `d` inside the note field
- **THEN** the character is added to the note and the alert is not dismissed

### Requirement: Decision attribution
Each confirmation or dismissal SHALL record who made it. Until user sign-in exists, the
decision SHALL be recorded as `Unattributed`.

#### Scenario: No signed-in user
- **WHEN** an alert is confirmed with no signed-in user
- **THEN** the alert history shows the decision as made by `Unattributed`

### Requirement: Decided alerts are read-only
Confirmed and Dismissed alerts SHALL show their decision, who made it, when and the note,
and SHALL NOT offer confirm or dismiss actions.

#### Scenario: Viewing a confirmed alert
- **WHEN** an analyst opens a Confirmed alert
- **THEN** the decision details are shown and no confirm or dismiss controls are offered
