## ADDED Requirements

### Requirement: Reusable Design-C Action Sheet
The `fleet-ui` crate SHALL expose a reusable action sheet overlay module for grouped contextual actions.

#### Scenario: Rendering grouped actions
- **WHEN** an `ActionSheet` is rendered with one or more `ActionGroup` values
- **THEN** the sheet is bottom anchored inside the provided frame
- **AND** action rows are separated by hairline dividers
- **AND** the cancel action is rendered in a separate card below the action group.

#### Scenario: Rendering destructive and selected actions
- **WHEN** an action item is marked destructive
- **THEN** the item uses the iOS destructive red treatment.
- **WHEN** an action row or cancel row is selected
- **THEN** the selected surface uses the iOS tint treatment without changing row height.
