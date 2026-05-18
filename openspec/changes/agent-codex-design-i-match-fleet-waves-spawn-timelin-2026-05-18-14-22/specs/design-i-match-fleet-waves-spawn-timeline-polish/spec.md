## ADDED Requirements

### Requirement: Fleet Waves Spawn Timeline Polish
The fleet-waves dashboard SHALL render wave progress as a Gantt-style spawn timeline that includes proportional bars, timeline tick markers, and task/agent summary columns.

#### Scenario: Wave rows expose timeline, task, and agent state
- **WHEN** a plan has topological waves with completed, claimed, and idle tasks
- **THEN** the Gantt card shows a top tick-marker row above the wave bars
- **AND** each wave row shows a proportional bar width based on its task count
- **AND** each wave row shows right-aligned `TASKS` and `AGENTS` values
- **AND** the active claimed wave receives a tint shimmer sweep without changing row geometry.
