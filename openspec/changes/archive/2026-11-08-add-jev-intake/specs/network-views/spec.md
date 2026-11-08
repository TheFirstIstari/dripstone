# Spec Delta

## MODIFIED Requirements

### Requirement: AI-written summary
The Summary view SHALL show a narrative summary written by the AI model, labeled as
AI-generated with its generation time. If no summary exists, the page SHALL say so.
Because the decision model returns no text, live networks have no summary until a
text-writing model is added.

#### Scenario: Summary is labeled
- **WHEN** a network has an AI-written summary
- **THEN** it is shown under a visible `AI-generated` label with its generation time

#### Scenario: No summary yet
- **WHEN** a network has no AI-written summary
- **THEN** the summary area states that no summary has been generated

### Requirement: Shared evidence
The Summary view SHALL list the evidence linking members, such as shared links,
repost rings, timing sync or audience overlap. Each item SHALL show its strength and how
many members it involves.

#### Scenario: Shared link evidence
- **WHEN** 14 members of a network were found coordinated with relation `shared-link`
- **THEN** the evidence list shows a shared-link item with its strength, involving 14 members

### Requirement: Graph of linked accounts
The Graph view SHALL draw members as nodes and links between members as lines, colored
by link type with a legend. The link types SHALL be the relation labels (repost ring,
shared link, timing sync, audience overlap) plus near-duplicate content and created
together. Link types SHALL be toggleable to show or hide them.

#### Scenario: Hiding a link type
- **WHEN** a user hides the `Shared link` type
- **THEN** lines of that type disappear, and nodes left with no visible lines are dimmed

#### Scenario: New links appear without a membership change
- **WHEN** a group finding adds a `timing-sync` link between two existing members of a
  network whose Graph view was already opened
- **THEN** opening the Graph view again shows the new link

#### Scenario: Relation labels in the legend
- **WHEN** a network has links of type `repost-ring` and `timing-sync`
- **THEN** the legend lists `Repost ring` and `Timing sync` with their colors

## ADDED Requirements

### Requirement: Network assessment
The Summary view SHALL show the network's latest decision-model assessment: its
coordination probability, relation label with confidence, and trajectory, each with when
it was observed. A network never assessed SHALL say so.

#### Scenario: Assessed network
- **WHEN** a network's latest group finding had `coordinated` 0.88 and `relation`
  `shared-link`, and its latest trend finding had trajectory `forming`
- **THEN** the Summary view shows coordinated 88%, relation `Shared link` and trajectory
  `Forming`, each with its observation time

#### Scenario: Never assessed
- **WHEN** a network has no group or trend findings with answers
- **THEN** the assessment area states that the network has not been assessed
