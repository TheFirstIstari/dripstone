# Spec Delta

## MODIFIED Requirements

### Requirement: Risk signal breakdown
The account detail page SHALL list the signals behind the risk score, largest
contribution first. Each signal SHALL show its name, a plain-language explanation, and
either its contribution or, when detection gives no contribution, its value. Signals
with a contribution SHALL come before those without.

#### Scenario: Explaining a score
- **WHEN** an account's score includes `Posting cadence` (+34) and `Persona
  consistency` (+28)
- **THEN** both are listed with their explanations and contributions, largest first

#### Scenario: Signals without contributions
- **WHEN** an account's signals are the heuristic label `regular_timing` and the answer
  `Bot-like 81%`, with no contributions
- **THEN** both are listed with their explanations, and `Bot-like` shows `81%` instead
  of a contribution

### Requirement: Linked accounts
The account detail page SHALL list the accounts it is linked to, strongest link first,
each with the link types (for example shared link, repost ring, timing sync, audience
overlap), the strength of the link, and a link to that account.

#### Scenario: Account with links
- **WHEN** an account was found in a repost ring with 11 other accounts
- **THEN** those accounts are listed with the `Repost ring` link type

#### Scenario: No links
- **WHEN** an account has no links to other accounts
- **THEN** the linked accounts section shows an empty state
