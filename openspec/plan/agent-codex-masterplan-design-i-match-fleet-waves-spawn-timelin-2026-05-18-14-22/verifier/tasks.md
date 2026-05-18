# verifier tasks

## 1. Spec

- [ ] 1.1 Define end-to-end validation matrix for `agent-codex-masterplan-design-i-match-fleet-waves-spawn-timelin-2026-05-18-14-22`
- [ ] 1.2 Validate success/failure conditions and evidence requirements

## 2. Tests

- [ ] 2.1 Execute verification commands and collect outputs
- [ ] 2.2 Validate idempotency/re-run behavior and error-path handling

## 3. Implementation

- [ ] 3.1 Verify completed work against acceptance criteria
- [ ] 3.2 Produce pass/fail findings with concrete evidence links
- [ ] 3.3 Publish final verification sign-off (or blocker report)

## 4. Checkpoints

- [ ] [V1] READY - Verification checkpoint

## 5. Collaboration

- [ ] 5.1 Owner recorded this lane before edits.
- [ ] 5.2 Record joined agents / handoffs, or mark `N/A` when solo.
- [ ] 5.3 Record unresolved plan questions in `../open-questions.md`, or mark `N/A` when none.

## 6. Cleanup

- [ ] 6.1 If this lane owns finalization, run `gx branch finish --branch <agent-branch> --base dev --via-pr --wait-for-merge --cleanup`.
- [ ] 6.2 Record PR URL + final `MERGED` state in the handoff.
- [ ] 6.3 Confirm sandbox cleanup (`git worktree list`, `git branch -a`) or append `BLOCKED:` and stop.
