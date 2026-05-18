# executor tasks

## 1. Spec

- [ ] 1.1 Map approved plan requirements to concrete implementation work items
- [ ] 1.2 Validate touched components/files are explicitly listed before coding starts

## 2. Tests

- [ ] 2.1 Define test additions/updates required to lock intended behavior
- [ ] 2.2 Validate regression and smoke verification commands for delivery

## 3. Implementation

- [ ] 3.1 Execute implementation tasks in approved order
- [ ] 3.2 Keep progress and evidence linked back to plan checkpoints
- [ ] 3.3 Complete final verification bundle for handoff

## 4. Checkpoints

- [ ] [E1] READY - Execution start checkpoint

## 5. Collaboration

- [ ] 5.1 Owner recorded this lane before edits.
- [ ] 5.2 Record joined agents / handoffs, or mark `N/A` when solo.
- [ ] 5.3 Record unresolved plan questions in `../open-questions.md`, or mark `N/A` when none.

## 6. Cleanup

- [ ] 6.1 If this lane owns finalization, run `gx branch finish --branch <agent-branch> --base dev --via-pr --wait-for-merge --cleanup`.
- [ ] 6.2 Record PR URL + final `MERGED` state in the handoff.
- [ ] 6.3 Confirm sandbox cleanup (`git worktree list`, `git branch -a`) or append `BLOCKED:` and stop.
