# alert-intake Specification

## Purpose
Defines the small, documented contract between the separately owned detection side
(AI plus heuristics) and the app: a catalog of trigger types, and a single intake through
which detection reports findings that the app turns into alerts.

## Requirements

### Requirement: Trigger catalog
The app SHALL keep a catalog of trigger types, each with a stable identifier, a display
name and a one-sentence description. Adding a trigger type SHALL require only a catalog
entry; it SHALL then appear in alert labels and filters with no other change.

#### Scenario: Adding a trigger type
- **WHEN** a developer adds a `Link rotation` entry to the trigger catalog
- **THEN** `Link rotation` appears as an option in the alert trigger filter, and findings
  reported with its identifier are accepted

### Requirement: Initial trigger types
The catalog SHALL initially contain `New network`, `Network growth`, `Network
reactivation` and `Promotion shift` (a network changing the domain or promotion it
spreads).

#### Scenario: Initial catalog
- **WHEN** a user opens the trigger filter on the Alerts screen
- **THEN** the four initial trigger types are listed

### Requirement: Single findings intake
Detection SHALL report findings to the app through a single intake. A finding SHALL name
a catalog trigger, a network (an existing one, or a new one with its member accounts and
confidence), a severity, a title, the time it was observed, and at least one evidence item.

#### Scenario: Reporting a finding
- **WHEN** detection reports a valid `Promotion shift` finding for an existing network
- **THEN** the app creates an Open alert for that network and the intake reports the
  alert it created

### Requirement: Finding validation
The intake SHALL reject a finding that names an unknown trigger, has no evidence, has an
invalid severity, or refers to an unknown network, and SHALL return the reasons. A
rejected finding SHALL NOT change any state.

#### Scenario: Unknown trigger
- **WHEN** detection reports a finding with trigger `does-not-exist`
- **THEN** the intake returns an error naming the unknown trigger and no alert is created

### Requirement: Optional finding details
A finding SHALL be able to include an AI-written rationale, before-and-after values for
what changed (for example the previous and new promoted domain with their shares), and
updates to the network: new members, confidence and main promoted domain.

#### Scenario: Before-and-after values
- **WHEN** a finding includes before `deals-a.example (62%)` and after
  `deals-b.example (55%)`
- **THEN** the resulting alert shows both values on its detail page

### Requirement: Contract is open to all detection methods
The finding contract SHALL NOT require detection to state whether AI analysis or
heuristics produced a finding, because findings combine both.

#### Scenario: Blended finding
- **WHEN** a finding produced by a mix of AI analysis and heuristics is reported
- **THEN** it is accepted without any AI-or-heuristic source field

### Requirement: Analyst changes are respected
Network updates in a finding SHALL NOT re-add an account an analyst removed from that
network, and SHALL NOT override an analyst-set network name. The intake result SHALL list
any updates it skipped for this reason.

#### Scenario: Removed account reported again
- **WHEN** an analyst removed `@sunny_deals` from a network and a later finding lists it
  as a new member
- **THEN** the account is not re-added, and the intake result reports it as skipped

### Requirement: No duplicate open alerts
If a network already has an Open alert for the same trigger, a new finding SHALL be added
to that alert, combining the evidence and raising its severity if the new finding is more
severe, instead of creating a second alert.

#### Scenario: Repeated finding
- **WHEN** two `Network growth` findings arrive for a network before an analyst acts
- **THEN** there is one Open growth alert containing the evidence from both

### Requirement: Re-alerting after dismissal
For a dismissed network, the intake SHALL create an alert only if the finding was
observed after the dismissal. Such an alert SHALL be marked previously dismissed, link to
the dismissed alert, and return the network to Suspected.

#### Scenario: Network returns with new evidence
- **WHEN** a finding observed after a network's dismissal is reported for it
- **THEN** an alert is created marked previously dismissed and linked to the earlier
  alert, and the network becomes Suspected

#### Scenario: Stale finding
- **WHEN** a finding observed before the network's dismissal is reported
- **THEN** no alert is created, and the intake result says the finding predates the dismissal

### Requirement: Live notification
Every alert created or updated through the intake SHALL be pushed to open screens
immediately, as described by the shell, inbox and overview capabilities.

#### Scenario: Intake to screen
- **WHEN** the intake creates an alert
- **THEN** open screens receive it without a reload

### Requirement: Documented contract
The repository SHALL contain a document describing the trigger catalog, the finding
fields, validation errors and intake results, with an example finding for each initial
trigger type.

#### Scenario: Detection developer reads the contract
- **WHEN** the detection owner opens the contract document
- **THEN** it describes every finding field and shows an example finding for each of the
  four initial trigger types
