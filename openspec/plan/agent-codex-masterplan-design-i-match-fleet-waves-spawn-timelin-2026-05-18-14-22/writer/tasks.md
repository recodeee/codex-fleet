# writer tasks

## 1. Spec

- [ ] 1.1 Validate documentation scope and audience for `agent-codex-masterplan-design-i-match-fleet-waves-spawn-timelin-2026-05-18-14-22`
- [ ] 1.2 Validate consistency between plan terminology and OpenSpec artifacts

## 2. Tests

- [ ] 2.1 Define documentation verification checklist (accuracy, completeness, command correctness)
- [ ] 2.2 Validate command/help text examples against current workflow behavior

## 3. Implementation

- [ ] 3.1 Update workflow docs and command guidance for approved plan behavior
- [ ] 3.2 Add or refine examples for operator usage and handoff clarity
- [ ] 3.3 Publish final docs change summary with references

## 4. Checkpoints

- [ ] [W1] READY - Docs update checkpoint

## 5. Collaboration

- [ ] 5.1 Owner recorded this lane before edits.
- [ ] 5.2 Record joined agents / handoffs, or mark `N/A` when solo.
- [ ] 5.3 Record unresolved plan questions in `../open-questions.md`, or mark `N/A` when none.

## 6. Cleanup

- [ ] 6.1 If this lane owns finalization, run `gx branch finish --branch <agent-branch> --base dev --via-pr --wait-for-merge --cleanup`.
- [ ] 6.2 Record PR URL + final `MERGED` state in the handoff.
- [ ] 6.3 Confirm sandbox cleanup (`git worktree list`, `git branch -a`) or append `BLOCKED:` and stop.
