# Spec Delta

## MODIFIED Requirements

### Requirement: Data source indicator
The shell SHALL show which data source is in use. The sidebar SHALL display a `Live` or
`Demo` indicator matching the analyst's current mode, next to the control that switches
it. It SHALL never claim sample data while Live is shown.

#### Scenario: Sample data in use
- **WHEN** the app is showing the Demo dataset (the sample seed)
- **THEN** a `Demo` indicator is visible in the sidebar on every screen

#### Scenario: Live data in use
- **WHEN** the app is showing the Live dataset in production with sample data off
- **THEN** the sidebar shows `Live`, and no "Sample data" text appears
