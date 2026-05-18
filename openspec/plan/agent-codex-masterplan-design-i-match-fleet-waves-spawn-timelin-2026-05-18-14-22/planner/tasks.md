# planner tasks

## 1. Spec

- [ ] 1.1 Define planning principles, decision drivers, and viable options for `agent-codex-masterplan-design-i-match-fleet-waves-spawn-timelin-2026-05-18-14-22`
- [ ] 1.2 Validate that scope, constraints, and acceptance criteria are captured in `summary.md`

## 2. Tests

- [ ] 2.1 Define verification approach for plan quality (traceability, testability, evidence expectations)
- [ ] 2.2 Validate OpenSpec consistency checkpoints (including `openspec validate --specs` when applicable)

## 3. Implementation

- [ ] 3.1 Produce the initial RALPLAN-DR plan draft
- [ ] 3.2 Integrate Architect/Critic feedback into revised plan iterations
- [ ] 3.3 Publish final planning handoff with explicit execution lanes

## 4. Checkpoints

- [ ] [P1] READY - Initial planning draft checkpoint

## 5. Collaboration

- [ ] 5.1 Owner recorded this lane before edits.
- [ ] 5.2 Record joined agents / handoffs, or mark `N/A` when solo.
- [ ] 5.3 Record unresolved plan questions in `../open-questions.md`, or mark `N/A` when none.

## 6. Cleanup

- [ ] 6.1 If this lane owns finalization, run `gx branch finish --branch <agent-branch> --base dev --via-pr --wait-for-merge --cleanup`.
- [ ] 6.2 Record PR URL + final `MERGED` state in the handoff.
- [ ] 6.3 Confirm sandbox cleanup (`git worktree list`, `git branch -a`) or append `BLOCKED:` and stop.
