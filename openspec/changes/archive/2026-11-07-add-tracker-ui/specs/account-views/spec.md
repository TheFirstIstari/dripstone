# Spec Delta

## Purpose

Lets analysts browse and filter tracked social accounts, and inspect a single account's
risk score, the signals behind it, the accounts it is linked to, its networks, and its
activity.

## ADDED Requirements

### Requirement: Risk levels
Each account's risk score (0–100) SHALL be shown as a level: Low for 0–39, Medium for
40–69, High for 70–100. The level and the numeric score SHALL be shown together.

#### Scenario: Score mapped to level
- **WHEN** an account has a risk score of 72
- **THEN** it is displayed as `High` with the score `72`

#### Scenario: Boundary score
- **WHEN** an account has a risk score of 40
- **THEN** it is displayed as `Medium`

### Requirement: Account list
The Accounts screen SHALL show a table of accounts with handle, display name, platform,
risk level and score, network and its status (if any), and last-seen time. Each row SHALL
link to that account's detail page.

#### Scenario: Opening an account
- **WHEN** a user selects a row in the accounts table
- **THEN** that account's detail page opens

### Requirement: Account filters
The Accounts screen SHALL filter by text search on handle or display name, platform, risk
level, and network membership (any network, a specific network, or none). Filters SHALL
combine with AND, and the platform options SHALL be the registered feeds.

#### Scenario: Combined filters
- **WHEN** a user filters by platform `Reddit` and risk level `High`
- **THEN** only Reddit accounts with a High risk level are listed

### Requirement: Shareable list state
Filters, sort order and page SHALL be kept in the URL, so reloading or sharing the link
restores the same view, and browser back and forward move between views.

#### Scenario: Reloading a filtered view
- **WHEN** a user filters to risk level `High`, sorts by last seen, and reloads the page
- **THEN** the same filters and sort order are applied after the reload

#### Scenario: Unknown filter values
- **WHEN** the URL contains a filter value that is not recognized
- **THEN** that filter is ignored and the page still loads

### Requirement: Sorting and pagination
The account table SHALL be sortable by risk score and last-seen time, defaulting to
highest risk first. It SHALL be paginated at 50 rows per page and show the total count.

#### Scenario: Default order
- **WHEN** a user opens `/accounts` without parameters
- **THEN** accounts are ordered by risk score, highest first, and the total number of
  matching accounts is shown

#### Scenario: Next page
- **WHEN** more than 50 accounts match and the user moves to the next page
- **THEN** accounts 51–100 are shown and the page is reflected in the URL

### Requirement: Account detail header
The account detail page SHALL show handle, display name, platform, a link to the profile
on its platform, creation date, first and last seen times, and risk level and score.

#### Scenario: External link
- **WHEN** a user selects the platform link on an account detail page
- **THEN** the account's profile on its platform opens in a new tab

### Requirement: Risk signal breakdown
The account detail page SHALL list the signals behind the risk score, largest
contribution first. Each signal SHALL show its name, a plain-language explanation, and
its contribution.

#### Scenario: Explaining a score
- **WHEN** an account's score includes `Posting cadence` (+34) and `Persona
  consistency` (+28)
- **THEN** both are listed with their explanations and contributions, largest first

### Requirement: Linked accounts
The account detail page SHALL list the accounts it is linked to, strongest link first,
each with the link types (for example shared links, near-duplicate content, synchronized
posting), the strength of the link, and a link to that account.

#### Scenario: Account with links
- **WHEN** an account shares near-duplicate content with 11 other accounts
- **THEN** those accounts are listed with the `Near-duplicate content` link type

#### Scenario: No links
- **WHEN** an account has no links to other accounts
- **THEN** the linked accounts section shows an empty state

### Requirement: Network membership on account
The account detail page SHALL list each network the account belongs to, with status and
confidence, linking to the network detail page.

#### Scenario: Account in a network
- **WHEN** an account belongs to network `Sunrise Cluster`
- **THEN** its detail page links to the `Sunrise Cluster` network page

### Requirement: Account activity
The account detail page SHALL show recent posts, newest first, each with time, text
excerpt, promoted domain (if any), and a link to the original post.

#### Scenario: No recorded activity
- **WHEN** an account has no recorded posts
- **THEN** the activity section shows an empty state
