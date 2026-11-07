# Spec Delta

## MODIFIED Requirements

### Requirement: Initial trigger types
The catalog SHALL initially contain `New network`, `Network growth`, `Network
reactivation`, `Promotion shift` (a network changing the domain or promotion it
spreads) and `Coordination rising` (an active network whose coordination is increasing).

#### Scenario: Initial catalog
- **WHEN** a user opens the trigger filter on the Alerts screen
- **THEN** the five initial trigger types are listed

### Requirement: Single findings intake
Detection SHALL report findings to the app through a single intake. A finding SHALL be
one of three kinds: an account finding, a group finding or a trend finding. Each SHALL
carry the time it was observed, the model that answered (if any), its heuristics, and
the decision model's answers map exactly as returned, or none when the AI was
unavailable.

#### Scenario: Reporting a group finding
- **WHEN** detection reports a valid group finding whose `coordinated` answer is 0.88 for
  accounts in no existing network
- **THEN** the app creates a network and an Open `New network` alert, and the intake
  reports the alert it created

#### Scenario: Reporting without AI answers
- **WHEN** detection reports an account finding with no answers because the AI was
  unavailable
- **THEN** the account is updated from the heuristics alone and the intake reports that
  no alert was raised

### Requirement: Finding validation
The intake SHALL reject a finding that has an unknown kind, no observation time, an
account on an unknown feed, a group of fewer than two accounts, a trend or group naming
an unknown network, or a malformed answer, and SHALL return the reasons. A rejected
finding SHALL NOT change any state.

#### Scenario: Unknown kind
- **WHEN** detection reports a finding with kind `does-not-exist`
- **THEN** the intake returns an error naming the unknown kind and no state changes

#### Scenario: Malformed answer
- **WHEN** a group finding's `coordinated` answer is a `noul` with a value of 1.4
- **THEN** the intake returns an error naming the `coordinated` answer and no state
  changes

### Requirement: Documented contract
The repository SHALL contain a document describing the trigger catalog, the three
finding kinds and their fields, the questions the app understands with their answer
types, the alert rules and their thresholds, validation errors and intake results, with
an example of each finding kind.

#### Scenario: Detection developer reads the contract
- **WHEN** the detection owner opens the contract document
- **THEN** it describes every finding field and every understood question, and shows an
  example account, group and trend finding that the intake accepts

### Requirement: No duplicate open alerts
If a network already has an Open alert for the same trigger, a new finding SHALL be added
to that alert, combining the evidence and raising its severity if the new finding is more
severe, instead of creating a second alert. Evidence written from the decision model's
answers SHALL be replaced by the newer finding's, and each alert SHALL keep at most its
100 newest evidence items.

#### Scenario: Repeated finding
- **WHEN** two `Network growth` findings arrive for a network before an analyst acts
- **THEN** there is one Open growth alert containing the evidence from both

#### Scenario: Re-assessed answers replace earlier ones
- **WHEN** an open `New network` alert was raised from `coordinated` 0.88, and a later
  group finding for the same network has `coordinated` 0.91
- **THEN** the alert shows the evidence from the 0.91 answer and no longer lists the
  0.88 one

#### Scenario: Evidence is capped
- **WHEN** an open alert already holds 100 evidence items and another finding adds new
  heuristic evidence
- **THEN** the newest 100 items are kept and the oldest are dropped

## ADDED Requirements

### Requirement: Account findings
An account finding SHALL name one account by feed and handle, and SHALL include the posts
that were assessed (each with its id, publish time and links) and the heuristic score
and labels. The app SHALL create the account if it is unknown, and update its risk score,
signals, topic and posts.

#### Scenario: New account assessed
- **WHEN** an account finding arrives for `@promo_daily` on X, which the app has not seen
- **THEN** the account is created with the heuristic score as its risk score, and its
  signals list the heuristic labels and the `is_bot`, `spam` and `topic` answers

#### Scenario: Re-assessment keeps earlier posts
- **WHEN** an account has stored posts `x1` and `x2`, and a new account finding includes
  posts `x2` and `x3`
- **THEN** the account's posts are `x1`, `x2` and `x3`, with `x2` updated from the
  newer finding

#### Scenario: Account findings raise no alert
- **WHEN** an account finding has an `is_bot` answer of 0.97
- **THEN** the account is updated and shows High risk, and no alert is raised

### Requirement: Group findings
A group finding SHALL name two or more accounts by feed and handle, optionally the known
network they were checked as, and the shares of the domains they link to. It SHALL carry
the `coordinated` and `relation` answers, and MAY carry one `member:<feed>:<handle>`
answer per account.

#### Scenario: Membership answers pick the members
- **WHEN** a coordinated group finding names five accounts and two of them have
  `member:` answers below the yes threshold
- **THEN** only the other three accounts become members of the network

#### Scenario: Without membership answers
- **WHEN** a coordinated group finding has no `member:` answers
- **THEN** every named account is treated as a member

### Requirement: Trend findings
A trend finding SHALL name a known network and the time window it covers, and SHALL
carry the `increasing` and `trajectory` answers. The app SHALL store the network's
latest trajectory so that later trend findings can be compared with it.

#### Scenario: Trajectory recorded
- **WHEN** a trend finding for a network has a `trajectory` answer of `stable`
- **THEN** the network's current trajectory is shown as `stable`

### Requirement: Answer values
The app SHALL read a `noul` answer as a probability from 0 to 1, a `choice` answer as
its label with its confidence, and a `score` answer as its expected level divided by the
highest level, giving 0 to 1. Answers to questions the app does not know SHALL be kept
and shown but SHALL NOT affect alerts.

#### Scenario: Score normalized
- **WHEN** a `spam` answer has a score of 1.5 on a three-level scale (levels 0 to 2)
- **THEN** the app treats the spam value as 0.75

#### Scenario: Unknown question kept
- **WHEN** a finding includes an answer named `language`, which the app does not use
- **THEN** the answer is stored and listed with the finding's answers, and no rule uses it

### Requirement: Configurable thresholds
The yes threshold, the severity bands and the evidence strength bands SHALL be set in
configuration. They SHALL start at 0.7 for yes; High at 0.9 or above, Medium at 0.8 or
above, Low otherwise; and Strong at 0.85 or above, Moderate at 0.7 or above, Weak
otherwise.

#### Scenario: Severity from probability
- **WHEN** a finding raises an alert from a `coordinated` answer of 0.83
- **THEN** the alert's severity is Medium

### Requirement: New network rule
A group finding with a `coordinated` answer at or above the yes threshold SHALL raise a
`New network` alert for a new network of its members, unless most of its members already
belong to one existing network. In that case it SHALL be treated as a finding for that
network.

#### Scenario: Coordinated strangers
- **WHEN** a group finding of four accounts in no network has `coordinated` 0.91
- **THEN** a new Suspected network of those four accounts is created with confidence 91,
  and a High `New network` alert is raised

#### Scenario: Not coordinated
- **WHEN** a group finding has `coordinated` 0.4
- **THEN** no network or alert is created, and the intake reports that the finding was
  below the threshold

### Requirement: Network growth rule
A coordinated group finding for a known network that includes members not yet in it
SHALL add them, except accounts an analyst removed, and SHALL raise a `Network growth`
alert comparing the member count before and after.

#### Scenario: Two new members
- **WHEN** a coordinated group finding for a 12-member network includes two accounts
  that are not members
- **THEN** both are added and a `Network growth` alert shows members `12` before and `14`
  after

### Requirement: Promotion shift rule
When a group finding for a known network reports a top domain with at least half of the
links, and that domain differs from the network's current main domain, the app SHALL
update the main domain and raise a `Promotion shift` alert. No AI answer is needed.

#### Scenario: Domain changes
- **WHEN** a network's main domain is `deals-a.example` and a group finding reports
  `deals-b.example` with a 55% share
- **THEN** a `Promotion shift` alert shows `deals-a.example` before and
  `deals-b.example (55%)` after

### Requirement: Trend rules
A trend finding whose `increasing` answer is at or above the yes threshold, or whose
trajectory is `forming`, SHALL raise an alert. It SHALL be `Network reactivation` if the
network's previous trajectory was `fading` or `none`, and `Coordination rising`
otherwise. Either way, the alert compares the previous and new trajectory.

#### Scenario: Dormant network wakes up
- **WHEN** a network's stored trajectory is `fading` and a trend finding returns
  `trajectory` `forming`
- **THEN** a `Network reactivation` alert shows `fading` before and `forming` after

#### Scenario: Active network intensifies
- **WHEN** a network's stored trajectory is `stable` and a trend finding returns
  `increasing` 0.82
- **THEN** a `Coordination rising` alert is raised

### Requirement: Evidence from answers
Each alert raised by a rule SHALL carry evidence written by the app from the answers and
heuristics that triggered it, each item with a strength from the evidence bands and the
accounts it involves. Detection SHALL NOT need to supply evidence text.

#### Scenario: Relation evidence
- **WHEN** a `New network` alert is raised from `coordinated` 0.88 and `relation`
  `shared-link` with confidence 0.7
- **THEN** its evidence includes a Strong item stating the accounts are coordinated and
  an item naming the `shared-link` relation, both involving the members

### Requirement: Links with provenance
A coordinated group finding SHALL create or update a link between each pair of members.
The link type SHALL be the `relation` label (unless it is `none`), and its strength SHALL
come from `coordinated`. Each link SHALL record the finding, question, model and time
that produced it.

#### Scenario: Link records its origin
- **WHEN** a group finding observed at 19:40 by model `jev-1.13` links two accounts with
  relation `timing-sync`
- **THEN** the link between them has type `timing-sync` and records that finding, the
  `relation` question, `jev-1.13` and 19:40

## REMOVED Requirements

### Requirement: Optional finding details
**Reason**: Detection reports measurements, not finished alerts. The decision model
returns no text, so findings carry no AI-written rationale. Before-and-after values and
network updates are now worked out by the app's rules (Network growth, Promotion shift,
Trend rules).
**Migration**: Send the answers and heuristics in an account, group or trend finding.
The app derives comparisons and network updates. AI-written rationales are shown as not
available.
