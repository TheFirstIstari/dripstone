# ui-shell Specification

## Purpose
Provides the shared frame around every Dripstone screen: navigation, open-alert badge,
live alert toasts, global account search, theming, and common empty, not-found and
accessibility behavior.

## Requirements

### Requirement: Persistent navigation
Every screen SHALL show the same primary navigation, with links to Overview, Alerts,
Networks, Accounts and Feeds, and the current section visibly marked as active.

#### Scenario: Active section is marked
- **WHEN** a user opens any page under `/networks`
- **THEN** the navigation shows Networks as active and the other links as inactive

#### Scenario: Navigation reaches every section
- **WHEN** a user selects Overview, Alerts, Networks, Accounts or Feeds
- **THEN** the corresponding screen (`/`, `/alerts`, `/networks`, `/accounts`, `/feeds`)
  loads without a full page reload

### Requirement: Open-alert badge
The Alerts link SHALL show the number of open alerts and SHALL hide the badge when none
are open. The count SHALL update live, without a reload, when alerts are raised,
confirmed or dismissed in any session.

#### Scenario: Badge counts open alerts
- **WHEN** 7 alerts are open
- **THEN** the Alerts link shows a badge reading `7`

#### Scenario: Badge updates live
- **WHEN** a new alert is raised while a user is viewing the Accounts screen
- **THEN** the badge count increases by one without a page reload

#### Scenario: No open alerts
- **WHEN** no alerts are open
- **THEN** the Alerts link shows no badge

### Requirement: Live high-severity toast
When a High severity alert is raised, every open screen SHALL show a dismissible toast
naming the alert and linking to it. Lower severities SHALL update the badge only.

#### Scenario: High severity alert arrives
- **WHEN** a High severity alert is raised while a user is on the Overview
- **THEN** a toast appears with the alert's title and a link to its detail page

#### Scenario: Medium severity alert arrives
- **WHEN** a Medium severity alert is raised
- **THEN** no toast appears, and the badge count increases

### Requirement: Responsive layout
On wide viewports the navigation SHALL be a persistent sidebar. On narrow viewports it
SHALL collapse behind a menu button that opens it as a dismissible overlay drawer.

#### Scenario: Narrow viewport
- **WHEN** the viewport is narrower than the large breakpoint
- **THEN** the sidebar is hidden and a menu button opens the navigation as a drawer

#### Scenario: Wide viewport
- **WHEN** the viewport is at or above the large breakpoint
- **THEN** the sidebar is always visible and no menu button is shown

### Requirement: Global account search
The top bar SHALL contain a search field that finds accounts by handle or display name
and opens the Accounts screen filtered to that query.

#### Scenario: Searching from any screen
- **WHEN** a user submits `crypto_` in the top bar search while on the Networks screen
- **THEN** the Accounts screen opens with its search filter set to `crypto_`

### Requirement: Theme selection
Users SHALL be able to choose a light, dark or system theme. The choice SHALL persist in
the browser and be applied before the page first paints.

#### Scenario: Choosing dark
- **WHEN** a user selects the dark theme and reloads the page
- **THEN** the page renders in the dark theme without first flashing the light theme

#### Scenario: Following the system
- **WHEN** a user selects the system theme and the operating system is in dark mode
- **THEN** the page renders in the dark theme

### Requirement: Dripstone branding
The browser title SHALL read `<Page> · Dripstone`. No Phoenix framework branding, version
number or external Phoenix links SHALL appear in the UI.

#### Scenario: Page title
- **WHEN** a user opens the Feeds screen
- **THEN** the browser title is `Feeds · Dripstone`

### Requirement: Data source indicator
The shell SHALL show which data source is in use. While the app runs on sample data,
the sidebar SHALL display a `Sample data` indicator.

#### Scenario: Sample data in use
- **WHEN** the app is running on sample data
- **THEN** a `Sample data` indicator is visible in the sidebar on every screen

### Requirement: Empty states
Every list or table SHALL show an explanatory empty state, not a blank area, when it
has no rows.

#### Scenario: Filter with no results
- **WHEN** a user applies filters on the Accounts screen that match no accounts
- **THEN** the table area says no accounts match, with a control to clear the filters

### Requirement: Not-found handling
Opening a detail page for an alert, network or account that does not exist SHALL show a
not-found page within the app shell, with a link back to the matching list.

#### Scenario: Unknown network
- **WHEN** a user opens `/networks/does-not-exist`
- **THEN** a not-found page is shown with a link back to `/networks`

### Requirement: Accessible status indicators
Severity, risk level, status and evidence strength SHALL be conveyed by text as well
as color. All interactive controls SHALL be keyboard-reachable with a visible focus
indicator.

#### Scenario: Color is not the only signal
- **WHEN** a High severity alert is displayed anywhere in the UI
- **THEN** its severity indicator includes the text `High` alongside its color

### Requirement: Reduced motion
Transitions and animations SHALL be disabled or minimized when the user's system requests
reduced motion.

#### Scenario: Reduced motion preference
- **WHEN** the operating system's reduced-motion setting is on
- **THEN** drawer, toast, hover and loading transitions do not animate
