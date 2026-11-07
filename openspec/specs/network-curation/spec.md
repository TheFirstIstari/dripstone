# network-curation Specification

## Purpose
Gives analysts the tools to correct and organize what detection found: naming, tagging
and annotating networks, adjusting membership, merging, splitting and relating networks,
with every manual change recorded.

## Requirements

### Requirement: Rename a network
Analysts SHALL be able to rename a network (1–80 characters). The name detection gave it
SHALL be kept and shown as `Detected as <original name>`.

#### Scenario: Renaming
- **WHEN** an analyst renames `Cluster #0412` to `Discount Spam Ring`
- **THEN** the network shows `Discount Spam Ring` everywhere, with `Detected as Cluster
  #0412` on its detail page

#### Scenario: Empty name
- **WHEN** an analyst submits an empty name
- **THEN** the name is unchanged and an error explains the length rule

### Requirement: Tag networks
Analysts SHALL be able to add and remove tags on a network. Tags SHALL be lowercase
letters, digits and hyphens, 1–32 characters, at most 20 per network. Existing tags
SHALL be suggested while typing.

#### Scenario: Adding a tag
- **WHEN** an analyst types `Crypto Scam` as a tag
- **THEN** the tag is saved as `crypto-scam` and shown on the network

#### Scenario: Suggestions
- **WHEN** an analyst types `cry` and the tag `crypto-scam` exists on another network
- **THEN** `crypto-scam` is suggested

### Requirement: Filter networks by tag
The Networks screen SHALL filter by tag, combined with its other filters, and the tag
filter SHALL be kept in the URL.

#### Scenario: Tag filter
- **WHEN** a user filters the Networks screen to tag `crypto-scam`
- **THEN** only networks with that tag are listed

### Requirement: Network notes
Analysts SHALL be able to add notes (1–2,000 characters) to a network. Notes SHALL be
shown newest first with author and time.

#### Scenario: Adding a note
- **WHEN** an analyst adds a note to a network
- **THEN** the note appears at the top of the network's notes with the author
  `Unattributed` and the current time

### Requirement: Add and remove members
Analysts SHALL be able to add an account to a network by searching for it, and remove
members from a network. An account SHALL be able to belong to more than one network.

#### Scenario: Removing a member
- **WHEN** an analyst removes `@k_morgan` from a network
- **THEN** the account is no longer listed as a member, and the removal is recorded as an
  analyst change that later detection updates will not undo

#### Scenario: Adding from the account page
- **WHEN** an analyst chooses to add an account to a network from the account detail page
- **THEN** the analyst can pick a network, and the account becomes a member of it

### Requirement: Move members between networks
Analysts SHALL be able to select one or more members and move them to another network
in one action.

#### Scenario: Moving members
- **WHEN** an analyst moves 3 selected members from network A to network B
- **THEN** the 3 accounts are members of B and no longer members of A

### Requirement: Merge networks
Analysts SHALL be able to merge one network into another. The target SHALL gain the
source's members, alerts, notes and tags. Its status SHALL be the source's or target's,
whichever comes first in Confirmed, Suspected, Dismissed. The source SHALL be retired.

#### Scenario: Merging
- **WHEN** an analyst merges Suspected network B into Dismissed network A
- **THEN** A contains B's members, alerts, notes and tags, A's status becomes Suspected,
  and B no longer appears in network lists

#### Scenario: Visiting a merged network
- **WHEN** a user opens the detail page of a retired network
- **THEN** the page says it was merged and links to the network it was merged into

### Requirement: Split a network
Analysts SHALL be able to select some (but not all) members and split them into a new
Suspected network, which they name when splitting.

#### Scenario: Splitting
- **WHEN** an analyst splits 8 of a network's 41 members into a new network named
  `Sunrise Offshoot`
- **THEN** `Sunrise Offshoot` exists with those 8 members and status Suspected, and the
  original network keeps the other 33

#### Scenario: Selecting every member
- **WHEN** an analyst selects all members of a network to split
- **THEN** the split is refused with an explanation

### Requirement: Related networks
Analysts SHALL be able to mark two networks as related, with an optional note, without
merging them, and to remove that relation. Each network's detail page SHALL list its
related networks.

#### Scenario: Relating networks
- **WHEN** an analyst marks network A as related to network B
- **THEN** A lists B as related and B lists A as related

### Requirement: Confirmation for destructive changes
Merging, splitting, moving and removing members SHALL require a confirmation step that
states what will change (for example how many members move) before it happens.

#### Scenario: Merge confirmation
- **WHEN** an analyst starts a merge of B into A
- **THEN** a confirmation shows the number of members, alerts and notes that will move,
  and nothing changes unless the analyst confirms

### Requirement: Change history
Every change to a network SHALL be recorded in its history: who made it, when, and what
changed. Analyst changes SHALL be marked `Analyst` and detection changes marked `System`.

#### Scenario: Viewing history
- **WHEN** an analyst renames a network and detection later adds members to it
- **THEN** the history lists the rename marked `Analyst` and the member additions marked
  `System`, newest first
