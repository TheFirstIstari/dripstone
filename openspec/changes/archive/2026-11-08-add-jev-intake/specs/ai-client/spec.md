# Spec Delta

## MODIFIED Requirements

### Requirement: Relationship analysis
`decide/2` SHALL support link-analysis questions over pairs/groups of accounts:
a `noul` question asking whether the accounts are coordinated plus a `choice`
question classifying the relation (e.g. repost-ring, shared-link, timing-sync,
audience-overlap, none), and optionally one `noul` question per account
(`member:<feed>:<handle>`) asking whether that account takes part. State for these
calls SHALL be the accounts' activity summaries (posts, timestamps, shared domains),
still under the 8000-char cap and public-data-only.

#### Scenario: Two synced accounts return coordinated with relation label
- **WHEN** `decide/2` is called with activity summaries of two timing-synced accounts
- **THEN** it returns `coordinated=true` with a relation label and probability

#### Scenario: Per-account membership in one call
- **WHEN** `decide/2` is called for a group of four accounts with a `member:` question
  for each
- **THEN** one response returns the `coordinated` and `relation` answers and a
  membership probability for each of the four accounts

## ADDED Requirements

### Requirement: Question definitions follow the model's schema
Questions sent to the decision model SHALL follow its published schema. Every `choice`
question SHALL carry `criteria` mapping each option to a description. Every `score`
question SHALL carry `criteria` listing between two and ten levels, lowest first. Option
and level names SHALL be the values the app's intake expects.

#### Scenario: Choice question carries its options
- **WHEN** the scorer asks the `relation` question
- **THEN** the request's `relation` question has type `choice` and `criteria` with
  `repost-ring`, `shared-link`, `timing-sync`, `audience-overlap` and `none`, each
  described

#### Scenario: Score question carries its levels
- **WHEN** the scorer asks the `spam` question
- **THEN** the request's `spam` question has type `score` and `criteria` listing its
  levels, lowest first
