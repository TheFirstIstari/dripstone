# Spec Delta

## MODIFIED Requirements

### Requirement: Alert detail evidence
The alert detail page SHALL show the alert's fields and a summary of its network, plus
the evidence behind the alert, strongest first. Each evidence item SHALL show a
plain-language explanation, its strength (Weak, Moderate or Strong), and the accounts
it involves. The page SHALL also list the decision model's answers behind the alert.

#### Scenario: Evidence listed by strength
- **WHEN** an alert has one Strong and two Moderate evidence items
- **THEN** the Strong item is listed first, and each item shows its strength label,
  explanation and involved accounts

#### Scenario: Answers behind the alert
- **WHEN** an alert was raised from a finding with `coordinated` 0.88 and `relation`
  `shared-link` (confidence 0.70), answered by `jev-1.13`
- **THEN** the page lists each question with its answer and confidence, the model, and
  when it was observed

#### Scenario: No AI answers
- **WHEN** an alert was raised from a finding with no AI answers
- **THEN** the answers area states that only heuristics were available

#### Scenario: No AI-written rationale
- **WHEN** an alert has no AI-written rationale
- **THEN** the rationale area states that none is available
