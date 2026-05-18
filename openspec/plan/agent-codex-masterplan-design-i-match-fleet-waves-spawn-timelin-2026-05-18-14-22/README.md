# Plan Workspace: agent-codex-masterplan-design-i-match-fleet-waves-spawn-timelin-2026-05-18-14-22

This folder stores durable planning artifacts before implementation changes.

## Shared files
- `summary.md`
- `checkpoints.md`
- `phases.md`
- `open-questions.md`
- `coordinator-prompt.md`
- `kickoff-prompts.md`

## Role folders
- `planner/`
- `architect/`
- `critic/`
- `executor/`
- `writer/`
- `verifier/`

When Codex or Claude hits an unresolved question that should survive chat, add it to `open-questions.md` as an unchecked `- [ ]` item.

Each role folder contains OpenSpec-style artifacts:
- `.openspec.yaml`
- `prompt.md` (copy/paste role prompt)
- `proposal.md`
- `tasks.md` (Spec / Tests / Implementation / Checkpoints checklists)
- `specs/<role>/spec.md`
Planner also gets `plan.md`; executor also gets `checkpoints.md`.
Planner plans should follow `openspec/plan/PLANS.md`.
