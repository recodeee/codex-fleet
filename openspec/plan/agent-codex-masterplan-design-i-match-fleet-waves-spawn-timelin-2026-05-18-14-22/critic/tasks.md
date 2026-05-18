# critic tasks

## 1. Spec

- [ ] 1.1 Validate principle-driver-option consistency across the plan
- [ ] 1.2 Validate risks, consequences, and mitigation clarity (including idempotency expectations)

## 2. Tests

- [ ] 2.1 Validate testability and measurability of all acceptance criteria
- [ ] 2.2 Validate verification steps are concrete and reproducible

## 3. Implementation

- [ ] 3.1 Produce verdict (APPROVE / ITERATE / REJECT) with actionable feedback
- [ ] 3.2 Confirm revised drafts resolve prior findings before approval
- [ ] 3.3 Publish final quality/risk sign-off notes

## 4. Checkpoints

- [ ] [C1] READY - Quality gate checkpoint

## 5. Collaboration

- [ ] 5.1 Owner recorded this lane before edits.
- [ ] 5.2 Record joined agents / handoffs, or mark `N/A` when solo.
- [ ] 5.3 Record unresolved plan questions in `../open-questions.md`, or mark `N/A` when none.

## 6. Cleanup

- [ ] 6.1 If this lane owns finalization, run `gx branch finish --branch <agent-branch> --base dev --via-pr --wait-for-merge --cleanup`.
- [ ] 6.2 Record PR URL + final `MERGED` state in the handoff.
- [ ] 6.3 Confirm sandbox cleanup (`git worktree list`, `git branch -a`) or append `BLOCKED:` and stop.
