# Spec Delta

## Purpose

Lets analysts show real data and switch to a demo dataset where alerts arrive reliably,
without restarting the app and without demo data ever mixing with real data.

## ADDED Requirements

### Requirement: Two datasets
The app SHALL keep a Live dataset and a Demo dataset. Live SHALL be filled only by real
detection. Demo SHALL hold the sample seed and the dev simulator's findings. Neither
SHALL ever receive the other's data.

#### Scenario: Live starts without sample data
- **WHEN** the app starts in development or production on an empty database
- **THEN** the Live dataset has no accounts, networks or alerts until real detection
  reports some

#### Scenario: Simulator writes to Demo only
- **WHEN** the simulator reports a finding while live discovery is also running
- **THEN** the finding appears in the Demo dataset and not in Live

### Requirement: Switching modes
Each analyst SHALL be able to switch between Live and Demo from every screen. The switch
SHALL apply to that analyst's session only, take effect immediately without restarting
the app, keep the analyst on the same screen, and be remembered for the session.

#### Scenario: Switch to Demo
- **WHEN** an analyst viewing Live switches to Demo
- **THEN** every screen shows the Demo dataset, and another analyst viewing Live is not
  affected

### Requirement: Isolated changes
Decisions, notes and curation made in one mode SHALL apply only to that mode's dataset.

#### Scenario: Confirming a demo alert
- **WHEN** an analyst confirms an alert while in Demo
- **THEN** the alert is confirmed in Demo, and nothing in Live changes

### Requirement: Live data keeps flowing
Live detection SHALL keep running and updating the Live dataset while any analyst views
Demo.

#### Scenario: Back to Live after a demo
- **WHEN** live discovery raises an alert while an analyst is in Demo, and the analyst
  then switches back to Live
- **THEN** the new live alert is there

### Requirement: Defaults
Sessions SHALL start in Live. The Demo dataset SHALL be built when it is first needed,
so an app that is never switched to Demo holds no demo data in memory.

#### Scenario: Fresh session
- **WHEN** an analyst logs in
- **THEN** the session shows Live

### Requirement: Demo is never persisted
The Demo dataset SHALL be kept in memory only. When Live data is stored durably, Demo
data SHALL never be written to that storage.

#### Scenario: Restart
- **WHEN** the app restarts after an analyst used Demo
- **THEN** no demo data has been stored, and Demo is rebuilt fresh on next use

### Requirement: Demo banner
While an analyst is viewing Demo, every screen SHALL show a clear banner saying the data
is demo data, with a way to switch back to Live.

#### Scenario: Demo on screen
- **WHEN** an analyst switches to Demo
- **THEN** a "Demo data" banner is visible on every screen until they switch back
