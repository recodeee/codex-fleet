# docs/future/PROTOCOL.md
# codex-fleet Future Protocol

> A long-horizon, subsystem-by-subsystem improvement protocol for
> `recodeee/codex-fleet`. This document is **not** a roadmap — it is a
> living catalog of *proposals*, each tagged with a lifecycle state.
> Items graduate from PROPOSED to SHIPPED through the OpenSpec change
> pipeline.

## How to read this file

- Each top-level section covers one subsystem (a script, a crate, or a
  cross-cutting concern).
- Each section opens with **Mission**, **Current State**, **Pain Points**,
  then a numbered list of **Improvement Protocols**.
- Each improvement carries `state:`, `problem`, `hypothesis`, `proposal`,
  `implementation steps`, `lane`, `verification`, `acceptance criteria`,
  `rollback`, `risks`, `metrics`, and `refs`.
- Sections close with **Backlog (raw)**, **Open Questions**,
  **Cross-Cutting Dependencies**, **Risk Register**, **Migration Plan**,
  and **Out of Scope**.

## Lifecycle states

| State        | Meaning                                                    |
|--------------|------------------------------------------------------------|
| PROPOSED     | Authored here; not yet accepted by a captain.              |
| ACCEPTED     | Captain accepts the idea; awaiting an OpenSpec change.     |
| SCHEDULED    | OpenSpec change opened; awaiting implementation slot.      |
| IN-PROGRESS  | Actively being implemented by a lane.                      |
| SHIPPED      | Merged and verified in main; carries `PR #<n>` evidence.   |
| DEFERRED     | Parked with explicit reason; revisit at next review.       |
| REJECTED     | Captain says no; carries ADR link.                         |

## Caveman / verbose modes

This protocol is authored in normal English (not caveman mode). Comments
and chat may compress per AGENTS.md, but specs, plans, and this protocol
stay verbose so reviewers can pick them up cold.

## Authoring rules

- One captain per section. Default `unassigned`.
- One state per improvement. Update on merge.
- Every improvement must cite at least one real path in `refs`.
- Slugs are stable. Renames require deprecation.
- Sections cap at ~300 lines; overflow forks into `docs/future/deep/<slug>.md`.

## Table of Contents

1. [Meta-Protocol & Governance](#1-meta-protocol)
2. [Repository Layout & Workspace Hygiene](#2-repo-layout)
3. [Bash Layer: full-bringup.sh](#3-full-bringup)
4. [Bash Layer: force-claim.sh](#4-force-claim)
5. [Bash Layer: claim-release-supervisor.sh](#5-claim-release)
6. [Bash Layer: cap-swap-daemon.sh](#6-cap-swap)
7. [Bash Layer: stall-watcher.sh](#7-stall-watcher)
8. [Bash Layer: conductor.sh](#8-conductor)
9. [Bash Layer: plan-watcher.sh](#9-plan-watcher)
10. [Bash Layer: review-queue.sh](#10-review-queue)
11. [Bash Layer: review-pane-scanner.sh](#11-review-pane-scanner)
12. [Bash Layer: auto-reviewer.sh](#12-auto-reviewer)
13. [Bash Layer: score-checkpoint.sh](#13-score-checkpoint)
14. [Bash Layer: score-merged-pr.sh](#14-score-merged-pr)
15. [Bash Layer: watcher-board.sh](#15-watcher-board)
16. [Bash Layer: style-tabs.sh](#16-style-tabs)
17. [Bash Layer: show-fleet.sh](#17-show-fleet)
18. [Bash Layer: token-meter.sh](#18-token-meter)
19. [Bash Layer: warm-pool.sh](#19-warm-pool)
20. [Bash Layer: spawn-fleet.sh](#20-spawn-fleet)
21. [Bash Layer: dispatch-plan.sh](#21-dispatch-plan)
22. [Bash Layer: cap-probe.sh](#22-cap-probe)
23. [Bash Layer: proactive-probe.sh](#23-proactive-probe)
24. [Bash Layer: claim-trigger.sh](#24-claim-trigger)
25. [Bash Layer: claude-worker.sh](#25-claude-worker)
26. [Bash Layer: claude-spawn.sh](#26-claude-spawn)
27. [Bash Layer: claude-supervisor.sh](#27-claude-supervisor)
28. [Bash Layer: fleet-tick.sh](#28-fleet-tick)
29. [Bash Layer: fleet-tick-daemon.sh](#29-fleet-tick-daemon)
30. [Bash Layer: fleet-state-anim.sh](#30-fleet-state-anim)
31. [Bash Layer: plan-anim.sh](#31-plan-anim)
32. [Bash Layer: plan-tree-anim.sh](#32-plan-tree-anim)
33. [Bash Layer: plan-tree-pin.sh](#33-plan-tree-pin)
34. [Bash Layer: review-anim.sh](#34-review-anim)
35. [Bash Layer: waves-anim.sh](#35-waves-anim)
36. [Bash Layer: supervisor.sh](#36-supervisor)
37. [Bash Layer: patch-codex-prompts.sh](#37-patch-codex-prompts)
38. [Bash Layer: overview-header.sh](#38-overview-header)
39. [Bash Layer: down.sh](#39-down)
40. [Bash Layer: up.sh](#40-up)
41. [Bash Layer: add-workers.sh](#41-add-workers)
42. [Bash Layer: codex-fleet-2.sh](#42-codex-fleet-2)
43. [Rust Crate: fleet-components](#43-rust-fleet-components)
44. [Rust Crate: fleet-data](#44-rust-fleet-data)
45. [Rust Crate: fleet-input](#45-rust-fleet-input)
46. [Rust Crate: fleet-launcher](#46-rust-fleet-launcher)
47. [Rust Crate: fleet-layout](#47-rust-fleet-layout)
48. [Rust Crate: fleet-metrics-viewer](#48-rust-fleet-metrics-viewer)
49. [Rust Crate: fleet-pane-health](#49-rust-fleet-pane-health)
50. [Rust Crate: fleet-plan-tree](#50-rust-fleet-plan-tree)
51. [Rust Crate: fleet-state](#51-rust-fleet-state)
52. [Rust Crate: fleet-ui](#52-rust-fleet-ui)
53. [Rust Crate: fleet-watcher](#53-rust-fleet-watcher)
54. [Rust Crate: fleet-waves](#54-rust-fleet-waves)
55. [OpenSpec Workflow & Plan Registry](#55-openspec-workflow)
56. [Colony Integration & Task Graph](#56-colony-integration)
57. [Account / Auth Layer](#57-account-auth)
58. [Self-Healing Daemons (composite)](#58-self-healing)
59. [Observability & Metrics](#59-observability)
60. [Logging, Tracing & Replay](#60-logging-tracing)
61. [Testing Strategy (unit, integration, snapshot, e2e)](#61-testing-strategy)
62. [CI/CD & Release Pipeline](#62-ci-cd)
63. [Security, Sandboxing & Permissions](#63-security-sandbox)
64. [Secrets, Credentials & Token Hygiene](#64-secrets)
65. [Documentation & Onboarding](#65-docs-onboarding)
66. [Skills System (skills/codex-fleet)](#66-skills)
67. [Multi-Repo & Cross-Project Coordination](#67-multi-repo)
68. [Performance, Throughput & Backpressure](#68-performance)
69. [Resilience, Failure Modes & Chaos](#69-resilience)
70. [Cost, Quota & Rate-Limit Management](#70-cost-quota)
71. [UI/UX & Accessibility (tmux + future GUI)](#71-ui-ux)
72. [Design Tokens & Theming](#72-design-tokens)
73. [Internationalization & Localization](#73-i18n)
74. [Versioning, Backwards Compatibility & Deprecation](#74-versioning)
75. [Glossary & Conventions](#75-glossary)
76. [Risk Register (master)](#76-risk-register)
77. [Roadmap & Milestones](#77-roadmap)
78. [Appendix: Reference Configs & Templates](#78-appendix)

---

## 1. Meta-Protocol & Governance

- slug: `meta-protocol`
- captain: unassigned
- budget: ~300 lines (soft cap)

### 1.1 Mission

Define how this docs/future protocol itself is reviewed, accepted, and converted into OpenSpec changes. Without governance, a 12000-line wishlist degrades into noise; with it, each entry has a lifecycle from PROPOSED -> ACCEPTED -> SCHEDULED -> IN-PROGRESS -> SHIPPED.

### 1.2 Current state

- No formal governance document exists for forward-looking design work.
- Forward proposals are scattered across openspec/changes/, openspec/plans/, README, SPEC.md, and chat handoffs.
- There is no canonical 'future protocol' artifact; the Colony task graph carries near-term work but not long-horizon intent.
- AGENTS.md (-> CLAUDE.md) governs multi-agent execution but is silent on how new improvement protocols get accepted.

### 1.3 Pain points

1. Long-horizon ideas decay because they have no durable home.
2. Re-discovery cost: each new agent re-derives the same proposals from primary sources.
3. No explicit status field per improvement: readers cannot tell what is shipped vs. dreamed.
4. No SLA on how stale a proposal can get before it is archived or re-validated.

### 1.4 Improvement protocols

#### 1.4.1 Formal lifecycle states for every improvement entry

- state: SHIPPED
- lane: docs lane; no Rust changes

**Problem.** Improvements live or die without a tracked state, so readers cannot triage them.

**Hypothesis.** Tagging each improvement with one of PROPOSED, ACCEPTED, SCHEDULED, IN-PROGRESS, SHIPPED, REJECTED, DEFERRED will compress triage from minutes to seconds.

**Proposal.** Add a `state:` line to every improvement in this protocol. Add a CLI `scripts/codex-fleet/protocol-state.sh` that greps these lines and prints a status board.

**Implementation steps.**

1. Define enum and ordering in docs/future/PROTOCOL.md prelude.
1. Add a state line to every existing improvement block (default PROPOSED).
1. Implement `protocol-state.sh` using `rg '^- state:' docs/future/`.
1. Add CI check that every improvement block has exactly one state line.

**Verification.** Run `bash scripts/codex-fleet/protocol-state.sh --summary` and observe a non-empty per-state count.

**Acceptance criteria.**

- 100% of improvement blocks expose a state line.
- `protocol-state.sh --summary` exits 0 in CI.
- At least one improvement is moved out of PROPOSED within 14 days of acceptance.

**Rollback.** Remove the state lines and delete the CI check; protocol still readable as before.

**Risks.**

- State drift if reviewers forget to update lines after merge.
- Bike-shedding over which state a near-shipped item belongs to.

**Metrics.**

- % improvements with state != PROPOSED (target >25% after first quarter).
- Lead time PROPOSED -> SHIPPED p50.

**References.**

- `openspec/changes/`
- `CLAUDE.md`
- `Colony task_post`

#### 1.4.2 Per-section ownership ('captain' pattern)

- state: PROPOSED
- lane: docs lane + Colony notification template

**Problem.** Improvements with no owner stagnate; everyone assumes someone else is on it.

**Hypothesis.** Each top-level section gets a captain handle (Colony agent id or GitHub login). Captains are responsible for triage, not implementation.

**Proposal.** Add an `owner:` field to every section header. Surface it in protocol-state.sh.

**Implementation steps.**

1. Reserve a `Captain` line directly under each section title.
1. Default to `unassigned` and add a tracked task to fill in captains.
1. Add Colony `task_message` template `claim-captain` that posts a self-nomination note.

**Verification.** Verify every section has a Captain line populated within 30 days.

**Acceptance criteria.**

- All 50 sections show a non-unassigned captain.
- At least one captain rotation event is recorded.

**Rollback.** Drop the captain field; revert to flat triage.

**Risks.**

- Single point of failure if a captain disappears.

**Metrics.**

- % sections with named captain.
- Captain rotation frequency.

**References.**

- `AGENTS.md isolation section`
- `Colony task_messages`

### 1.5 Backlog (raw)

- Auto-cross-link improvements when one references another by slug.
- Per-section RSS-style changelog for stakeholders.
- Embed Mermaid diagrams illustrating lane responsibilities.
- Per-section maturity badge (alpha/beta/ga).
- Section-level licensing notes for any code snippets.
- Auto-generated digest summarising new entries weekly.
- Author attribution at sub-improvement level for accountability.
- Voting / lazy-consensus mechanic for prioritisation.
- Optional 'effort' (S/M/L/XL) tag per improvement.
- Optional 'value' tag (low/med/high/critical) per improvement.
- Search index for offline `rg`-based queries with helpers.
- Multilingual mirror under `docs/future/i18n/<locale>/`.
- Pinned 'currently shipping' shelf at top of doc.
- Quarterly archive snapshots saved under `docs/future/archive/YYYY-Qn/`.
- Pre-commit hook nudge if state field missing.
- Auto-import improvements from openspec changes that were never proposed.
- Two-week 'cold-storage' rule for unmodified PROPOSED entries.
- Optional risk-class rubric (cosmetic / functional / safety / security).
- Diff-friendly section anchors that don't shift on edits.
- Style guide for caveman mode applied to protocol comments only, not specs.

### 1.6 Open questions

- [ ] Should captains be expected to also drive implementation or only triage?
- [ ] Do we permit ADR consolidation (one ADR covering several improvements)?
- [ ] What is the right archival policy for SHIPPED entries older than one year?
- [ ] Should rejection require a documented alternative path forward?
- [ ] How do we keep this protocol from drifting from CLAUDE.md / AGENTS.md?

### 1.7 Cross-cutting dependencies

- OpenSpec change pipeline.
- Colony task graph (for ownership messages).
- CI infrastructure for new doc checks.

### 1.8 Risk register

- Process overhead grows faster than the underlying engineering work.
- Captains become bottlenecks if review cadence slips.
- Documentation diverges from code if state lines aren't updated on merge.

### 1.9 Migration plan

1. Bootstrap: add state lines and captains to all sections in a single PR.
2. Iterate: roll out CI checks one at a time, each with a one-week grace period.
3. Stabilise: lock the schema after 60 days; further changes require an ADR.

### 1.10 Out of scope

- Replacing OpenSpec.
- Building a GUI for navigating the protocol.
- Sentiment / scoring of authors.

---

## 2. Repository Layout & Workspace Hygiene

- slug: `repo-layout`
- captain: unassigned
- budget: ~300 lines (soft cap)

### 2.1 Mission

Keep the codex-fleet repository tidy as it absorbs more crates, scripts, plans, and docs. Bound the cognitive cost of opening a fresh checkout and finding the right entrypoint within 60 seconds.

### 2.2 Current state

- Top-level mixes bash (scripts/), rust workspace (rust/), docs/, openspec/, .specify/, skills/, AGENTS.md, SPEC.md, README.md.
- scripts/codex-fleet hosts ~50 shell scripts plus subdirs (bin, lib, demo, test, tmux).
- Rust workspace declares members as `fleet-input`, `fleet-layout`, `fleet-*` glob.
- No top-level Makefile/justfile or task runner; entrypoints live in README + AGENTS.md prose.

### 2.3 Pain points

1. Newcomers cannot quickly distinguish runtime (bash) vs library (rust) ownership.
2. scripts/ grows organically; multiple scripts may overlap responsibility.
3. OpenSpec plans live in a sibling repo via CODEX_FLEET_REPO_ROOT, leading to confusion about source of truth.
4. Symlink CLAUDE.md -> AGENTS.md confuses some tooling and editors.

### 2.4 Improvement protocols

#### 2.4.1 Top-level taskfile (justfile or Makefile)

- state: PROPOSED
- lane: tooling lane

**Problem.** No canonical command to bring up dev, run tests, lint, regenerate docs.

**Hypothesis.** A single `just` (or `make`) interface improves discoverability and reduces README rot.

**Proposal.** Adopt justfile with recipes: dev, fleet-up, fleet-down, test, lint, docs, fmt, ci.

**Implementation steps.**

1. Add `justfile` at repo root.
1. Mirror commands in README.md.
1. Wire CI to call `just ci`.

**Verification.** `just --list` shows recipes; `just ci` succeeds locally.

**Acceptance criteria.**

- `just ci` is the single CI entrypoint.
- README references just commands only.

**Rollback.** Remove justfile; revert to README prose.

**Risks.**

- Author overhead to keep recipes in sync.
- Just is an extra system dependency.

**Metrics.**

- # of CI scripts replaced by `just ci`.
- README LOC reduction.

**References.**

- `scripts/codex-fleet/`
- `rust/Cargo.toml`

#### 2.4.2 Split scripts/codex-fleet by responsibility

- state: PROPOSED
- lane: scripts lane

**Problem.** scripts/codex-fleet/ is a flat bag with bringup, daemons, animations, scorers.

**Hypothesis.** Sub-grouping into `bringup/`, `daemons/`, `ui/`, `scoring/`, `review/`, `tools/` clarifies ownership.

**Proposal.** Move scripts in waves; provide a shim layer that preserves old paths for 60 days.

**Implementation steps.**

1. Inventory all scripts and classify.
1. Create subdirectories.
1. git mv preserving history; add forwarding wrappers.
1. Update full-bringup.sh entrypoints accordingly.

**Verification.** All existing flows (full-bringup, down, force-claim) still work.

**Acceptance criteria.**

- All scripts moved to a category subdir.
- Shims expire after 60 days with deprecation log.

**Rollback.** Move scripts back; remove shims.

**Risks.**

- Path breakage for downstream consumers.

**Metrics.**

- # scripts per category.
- # of shims removed at expiry.

**References.**

- `scripts/codex-fleet/`

### 2.5 Backlog (raw)

- Top-level `Justfile` aliases for common Colony commands.
- Per-subdir README explaining the contract.
- Symlink-free policy across repo.
- Adopt cargo-nextest for faster Rust test runs.
- Drop unused crates from the workspace if any.
- Auto-generate a tree-view diagram of the repo.
- Repo-shape lint that warns on top-level file additions.
- Add a `support/` dir for non-binary fixture data.
- Add a `tools/` dir distinct from `scripts/`.
- Add LICENSE headers to all source files.
- Reformat all bash scripts with shfmt.
- Pre-commit hook to enforce naming conventions for scripts.
- Convert install.sh into a Rust binary for portability.
- Reduce duplicated bash boilerplate via lib/common.sh.
- Standardise script shebang and `set -euo pipefail` invariants.

### 2.6 Open questions

- [ ] Do we keep .specify alongside openspec/ or unify?
- [ ] Should rust/ become a top-level crates/ to match common rust monorepo patterns?
- [ ] Is there value in moving skills/ into .claude/ to keep all Claude assets together?

### 2.7 Cross-cutting dependencies

- openspec, Cargo workspace, CI.

### 2.8 Risk register

- Reorgs break downstream scripts that hard-code paths.

### 2.9 Migration plan

1. Phase 1: additive (justfile, .editorconfig, CODEOWNERS).
2. Phase 2: subdir splits with shims.
3. Phase 3: shim removal after 60 days.

### 2.10 Out of scope

- Forking into a polyrepo.
- Renaming the repo.

---

## 3. Bash Layer: full-bringup.sh

- slug: `full-bringup`
- captain: unassigned
- budget: ~300 lines (soft cap)

### 3.1 Mission

Make `full-bringup.sh` reliable, debuggable, and self-documenting. It is the operator-facing entrypoint; correctness here gates every fleet session.

### 3.2 Current state

- `scripts/codex-fleet/full-bringup.sh` exists and is invoked via the fleet bringup flow or daemon supervisor.
- Behaviour is documented inline via comments; no dedicated SPEC entry.
- Logging is ad-hoc; output goes to tmux pane stdout/stderr.
- Failure modes typically surface as silent exits or noisy retries.

### 3.3 Pain points

1. No structured log format; difficult to ingest into a metrics pipeline.
2. No --help output documenting flags and env vars.
3. Exit codes are not standardised across scripts.
4. Limited dry-run support; experimentation requires real fleet state.

### 3.4 Improvement protocols

#### 3.4.1 Add `--help` and `--version` to full-bringup.sh

- state: PROPOSED
- lane: scripts lane

**Problem.** Discoverability is poor; flags are guessed from source.

**Hypothesis.** A short help message + version banner accelerates onboarding and CI introspection.

**Proposal.** Wrap entry-point with a tiny `usage()` function; version pulled from a constants file.

**Implementation steps.**

1. Refactor script to recognise --help/--version.
1. Add scripts/codex-fleet/lib/version.sh providing FLEET_VERSION.
1. Add a smoke test asserting --help exits 0 with non-empty output.

**Verification.** `bash scripts/codex-fleet/full-bringup.sh --help` prints usage.

**Acceptance criteria.**

- --help and --version supported.
- Smoke test added.

**Rollback.** Revert to no usage banner.

**Risks.**

- Slight LOC overhead per script.

**Metrics.**

- # scripts with --help.
- Doc-coverage trend.

**References.**

- `scripts/codex-fleet/full-bringup.sh`

#### 3.4.2 Structured logging in full-bringup.sh

- state: PROPOSED
- lane: scripts lane

**Problem.** Plain echoes are hard to parse downstream.

**Hypothesis.** Emit `key=value`-style structured lines so the metrics-viewer crate can ingest them.

**Proposal.** Adopt a `log_kv` helper from `lib/log.sh` that emits ISO-8601 timestamp + level + key/value pairs.

**Implementation steps.**

1. Implement `lib/log.sh`.
1. Refactor critical echoes to log_kv calls.
1. Document the format in docs/future/PROTOCOL.md observability section.

**Verification.** Pipe a run of full-bringup.sh into `awk '/level=/' ` and observe parsable lines.

**Acceptance criteria.**

- All errors and lifecycle events emit structured lines.
- fleet-metrics-viewer parses the format.

**Rollback.** Revert to plain echo.

**Risks.**

- Verbose output; need log levels.

**Metrics.**

- % structured lines per run.

**References.**

- `scripts/codex-fleet/full-bringup.sh`
- `rust/fleet-metrics-viewer/`

### 3.5 Backlog (raw)

- Embed a structured banner in full-bringup.sh listing all subcommands.
- Promote full-bringup.sh to a Rust binary if footprint stabilises.
- Add fish/zsh completions for full-bringup.sh.
- Add `--json` output mode for full-bringup.sh where feasible.
- Provide a `--explain` mode that prints the decision tree.
- Document full-bringup.sh interactions with Colony in detail.
- Add per-run UUID for log correlation in full-bringup.sh.
- Add Prometheus-style metrics endpoint when running under a supervisor.
- Add chaos-test harness that injects failures into full-bringup.sh.
- Convert long-running portions of full-bringup.sh into a daemon-friendly service unit.

### 3.6 Open questions

- [ ] Should full-bringup.sh be allowed to mutate tmux on the host shell, or always go through a wrapper?
- [ ] What is the right escalation when full-bringup.sh cannot reach Colony?
- [ ] Do we keep full-bringup.sh bash-only or accept hybrid bash+rust?

### 3.7 Cross-cutting dependencies

- lib/common.sh (planned)
- Colony CLI
- tmux

### 3.8 Risk register

- Behavioural changes in full-bringup.sh may ripple through full-bringup and daemons.
- Logging or telemetry growth without rotation.

### 3.9 Migration plan

1. Phase 1: helpers in lib/.
2. Phase 2: refactor full-bringup.sh to use helpers.
3. Phase 3: enforce in CI via shellcheck + bats.

### 3.10 Out of scope

- Replacing bash with a different orchestrator wholesale.

---

## 4. Bash Layer: force-claim.sh

- slug: `force-claim`
- captain: unassigned
- budget: ~300 lines (soft cap)

### 4.1 Mission

Make `force-claim.sh` reliable, debuggable, and self-documenting. It dispatches Colony work; latency and dispatch correctness directly affect throughput.

### 4.2 Current state

- `scripts/codex-fleet/force-claim.sh` exists and is invoked via the fleet bringup flow or daemon supervisor.
- Behaviour is documented inline via comments; no dedicated SPEC entry.
- Logging is ad-hoc; output goes to tmux pane stdout/stderr.
- Failure modes typically surface as silent exits or noisy retries.

### 4.3 Pain points

1. No structured log format; difficult to ingest into a metrics pipeline.
2. No --help output documenting flags and env vars.
3. Exit codes are not standardised across scripts.
4. Limited dry-run support; experimentation requires real fleet state.

### 4.4 Improvement protocols

#### 4.4.1 Add `--help` and `--version` to force-claim.sh

- state: PROPOSED
- lane: scripts lane

**Problem.** Discoverability is poor; flags are guessed from source.

**Hypothesis.** A short help message + version banner accelerates onboarding and CI introspection.

**Proposal.** Wrap entry-point with a tiny `usage()` function; version pulled from a constants file.

**Implementation steps.**

1. Refactor script to recognise --help/--version.
1. Add scripts/codex-fleet/lib/version.sh providing FLEET_VERSION.
1. Add a smoke test asserting --help exits 0 with non-empty output.

**Verification.** `bash scripts/codex-fleet/force-claim.sh --help` prints usage.

**Acceptance criteria.**

- --help and --version supported.
- Smoke test added.

**Rollback.** Revert to no usage banner.

**Risks.**

- Slight LOC overhead per script.

**Metrics.**

- # scripts with --help.
- Doc-coverage trend.

**References.**

- `scripts/codex-fleet/force-claim.sh`

#### 4.4.2 Structured logging in force-claim.sh

- state: PROPOSED
- lane: scripts lane

**Problem.** Plain echoes are hard to parse downstream.

**Hypothesis.** Emit `key=value`-style structured lines so the metrics-viewer crate can ingest them.

**Proposal.** Adopt a `log_kv` helper from `lib/log.sh` that emits ISO-8601 timestamp + level + key/value pairs.

**Implementation steps.**

1. Implement `lib/log.sh`.
1. Refactor critical echoes to log_kv calls.
1. Document the format in docs/future/PROTOCOL.md observability section.

**Verification.** Pipe a run of force-claim.sh into `awk '/level=/' ` and observe parsable lines.

**Acceptance criteria.**

- All errors and lifecycle events emit structured lines.
- fleet-metrics-viewer parses the format.

**Rollback.** Revert to plain echo.

**Risks.**

- Verbose output; need log levels.

**Metrics.**

- % structured lines per run.

**References.**

- `scripts/codex-fleet/force-claim.sh`
- `rust/fleet-metrics-viewer/`

### 4.5 Backlog (raw)

- Embed a structured banner in force-claim.sh listing all subcommands.
- Promote force-claim.sh to a Rust binary if footprint stabilises.
- Add fish/zsh completions for force-claim.sh.
- Add `--json` output mode for force-claim.sh where feasible.
- Provide a `--explain` mode that prints the decision tree.
- Document force-claim.sh interactions with Colony in detail.
- Add per-run UUID for log correlation in force-claim.sh.
- Add Prometheus-style metrics endpoint when running under a supervisor.
- Add chaos-test harness that injects failures into force-claim.sh.
- Convert long-running portions of force-claim.sh into a daemon-friendly service unit.

### 4.6 Open questions

- [ ] Should force-claim.sh be allowed to mutate tmux on the host shell, or always go through a wrapper?
- [ ] What is the right escalation when force-claim.sh cannot reach Colony?
- [ ] Do we keep force-claim.sh bash-only or accept hybrid bash+rust?

### 4.7 Cross-cutting dependencies

- lib/common.sh (planned)
- Colony CLI
- tmux

### 4.8 Risk register

- Behavioural changes in force-claim.sh may ripple through full-bringup and daemons.
- Logging or telemetry growth without rotation.

### 4.9 Migration plan

1. Phase 1: helpers in lib/.
2. Phase 2: refactor force-claim.sh to use helpers.
3. Phase 3: enforce in CI via shellcheck + bats.

### 4.10 Out of scope

- Replacing bash with a different orchestrator wholesale.

---

## 5. Bash Layer: claim-release-supervisor.sh

- slug: `claim-release`
- captain: unassigned
- budget: ~300 lines (soft cap)

### 5.1 Mission

Make `claim-release-supervisor.sh` reliable, debuggable, and self-documenting. It rescues stranded claims; failure here causes idle panes to look busy.

### 5.2 Current state

- `scripts/codex-fleet/claim-release-supervisor.sh` exists and is invoked via the fleet bringup flow or daemon supervisor.
- Behaviour is documented inline via comments; no dedicated SPEC entry.
- Logging is ad-hoc; output goes to tmux pane stdout/stderr.
- Failure modes typically surface as silent exits or noisy retries.

### 5.3 Pain points

1. No structured log format; difficult to ingest into a metrics pipeline.
2. No --help output documenting flags and env vars.
3. Exit codes are not standardised across scripts.
4. Limited dry-run support; experimentation requires real fleet state.

### 5.4 Improvement protocols

#### 5.4.1 Add `--help` and `--version` to claim-release-supervisor.sh

- state: PROPOSED
- lane: scripts lane

**Problem.** Discoverability is poor; flags are guessed from source.

**Hypothesis.** A short help message + version banner accelerates onboarding and CI introspection.

**Proposal.** Wrap entry-point with a tiny `usage()` function; version pulled from a constants file.

**Implementation steps.**

1. Refactor script to recognise --help/--version.
1. Add scripts/codex-fleet/lib/version.sh providing FLEET_VERSION.
1. Add a smoke test asserting --help exits 0 with non-empty output.

**Verification.** `bash scripts/codex-fleet/claim-release-supervisor.sh --help` prints usage.

**Acceptance criteria.**

- --help and --version supported.
- Smoke test added.

**Rollback.** Revert to no usage banner.

**Risks.**

- Slight LOC overhead per script.

**Metrics.**

- # scripts with --help.
- Doc-coverage trend.

**References.**

- `scripts/codex-fleet/claim-release-supervisor.sh`

#### 5.4.2 Structured logging in claim-release-supervisor.sh

- state: PROPOSED
- lane: scripts lane

**Problem.** Plain echoes are hard to parse downstream.

**Hypothesis.** Emit `key=value`-style structured lines so the metrics-viewer crate can ingest them.

**Proposal.** Adopt a `log_kv` helper from `lib/log.sh` that emits ISO-8601 timestamp + level + key/value pairs.

**Implementation steps.**

1. Implement `lib/log.sh`.
1. Refactor critical echoes to log_kv calls.
1. Document the format in docs/future/PROTOCOL.md observability section.

**Verification.** Pipe a run of claim-release-supervisor.sh into `awk '/level=/' ` and observe parsable lines.

**Acceptance criteria.**

- All errors and lifecycle events emit structured lines.
- fleet-metrics-viewer parses the format.

**Rollback.** Revert to plain echo.

**Risks.**

- Verbose output; need log levels.

**Metrics.**

- % structured lines per run.

**References.**

- `scripts/codex-fleet/claim-release-supervisor.sh`
- `rust/fleet-metrics-viewer/`

### 5.5 Backlog (raw)

- Embed a structured banner in claim-release-supervisor.sh listing all subcommands.
- Promote claim-release-supervisor.sh to a Rust binary if footprint stabilises.
- Add fish/zsh completions for claim-release-supervisor.sh.
- Add `--json` output mode for claim-release-supervisor.sh where feasible.
- Provide a `--explain` mode that prints the decision tree.
- Document claim-release-supervisor.sh interactions with Colony in detail.
- Add per-run UUID for log correlation in claim-release-supervisor.sh.
- Add Prometheus-style metrics endpoint when running under a supervisor.
- Add chaos-test harness that injects failures into claim-release-supervisor.sh.
- Convert long-running portions of claim-release-supervisor.sh into a daemon-friendly service unit.

### 5.6 Open questions

- [ ] Should claim-release-supervisor.sh be allowed to mutate tmux on the host shell, or always go through a wrapper?
- [ ] What is the right escalation when claim-release-supervisor.sh cannot reach Colony?
- [ ] Do we keep claim-release-supervisor.sh bash-only or accept hybrid bash+rust?

### 5.7 Cross-cutting dependencies

- lib/common.sh (planned)
- Colony CLI
- tmux

### 5.8 Risk register

- Behavioural changes in claim-release-supervisor.sh may ripple through full-bringup and daemons.
- Logging or telemetry growth without rotation.

### 5.9 Migration plan

1. Phase 1: helpers in lib/.
2. Phase 2: refactor claim-release-supervisor.sh to use helpers.
3. Phase 3: enforce in CI via shellcheck + bats.

### 5.10 Out of scope

- Replacing bash with a different orchestrator wholesale.

---

## 6. Bash Layer: cap-swap-daemon.sh

- slug: `cap-swap`
- captain: unassigned
- budget: ~300 lines (soft cap)

### 6.1 Mission

Make `cap-swap-daemon.sh` reliable, debuggable, and self-documenting. It swaps capped accounts; reliability here keeps the pool warm.

### 6.2 Current state

- `scripts/codex-fleet/cap-swap-daemon.sh` exists and is invoked via the fleet bringup flow or daemon supervisor.
- Behaviour is documented inline via comments; no dedicated SPEC entry.
- Logging is ad-hoc; output goes to tmux pane stdout/stderr.
- Failure modes typically surface as silent exits or noisy retries.

### 6.3 Pain points

1. No structured log format; difficult to ingest into a metrics pipeline.
2. No --help output documenting flags and env vars.
3. Exit codes are not standardised across scripts.
4. Limited dry-run support; experimentation requires real fleet state.

### 6.4 Improvement protocols

#### 6.4.1 Add `--help` and `--version` to cap-swap-daemon.sh

- state: PROPOSED
- lane: scripts lane

**Problem.** Discoverability is poor; flags are guessed from source.

**Hypothesis.** A short help message + version banner accelerates onboarding and CI introspection.

**Proposal.** Wrap entry-point with a tiny `usage()` function; version pulled from a constants file.

**Implementation steps.**

1. Refactor script to recognise --help/--version.
1. Add scripts/codex-fleet/lib/version.sh providing FLEET_VERSION.
1. Add a smoke test asserting --help exits 0 with non-empty output.

**Verification.** `bash scripts/codex-fleet/cap-swap-daemon.sh --help` prints usage.

**Acceptance criteria.**

- --help and --version supported.
- Smoke test added.

**Rollback.** Revert to no usage banner.

**Risks.**

- Slight LOC overhead per script.

**Metrics.**

- # scripts with --help.
- Doc-coverage trend.

**References.**

- `scripts/codex-fleet/cap-swap-daemon.sh`

#### 6.4.2 Structured logging in cap-swap-daemon.sh

- state: PROPOSED
- lane: scripts lane

**Problem.** Plain echoes are hard to parse downstream.

**Hypothesis.** Emit `key=value`-style structured lines so the metrics-viewer crate can ingest them.

**Proposal.** Adopt a `log_kv` helper from `lib/log.sh` that emits ISO-8601 timestamp + level + key/value pairs.

**Implementation steps.**

1. Implement `lib/log.sh`.
1. Refactor critical echoes to log_kv calls.
1. Document the format in docs/future/PROTOCOL.md observability section.

**Verification.** Pipe a run of cap-swap-daemon.sh into `awk '/level=/' ` and observe parsable lines.

**Acceptance criteria.**

- All errors and lifecycle events emit structured lines.
- fleet-metrics-viewer parses the format.

**Rollback.** Revert to plain echo.

**Risks.**

- Verbose output; need log levels.

**Metrics.**

- % structured lines per run.

**References.**

- `scripts/codex-fleet/cap-swap-daemon.sh`
- `rust/fleet-metrics-viewer/`

### 6.5 Backlog (raw)

- Embed a structured banner in cap-swap-daemon.sh listing all subcommands.
- Promote cap-swap-daemon.sh to a Rust binary if footprint stabilises.
- Add fish/zsh completions for cap-swap-daemon.sh.
- Add `--json` output mode for cap-swap-daemon.sh where feasible.
- Provide a `--explain` mode that prints the decision tree.
- Document cap-swap-daemon.sh interactions with Colony in detail.
- Add per-run UUID for log correlation in cap-swap-daemon.sh.
- Add Prometheus-style metrics endpoint when running under a supervisor.
- Add chaos-test harness that injects failures into cap-swap-daemon.sh.
- Convert long-running portions of cap-swap-daemon.sh into a daemon-friendly service unit.

### 6.6 Open questions

- [ ] Should cap-swap-daemon.sh be allowed to mutate tmux on the host shell, or always go through a wrapper?
- [ ] What is the right escalation when cap-swap-daemon.sh cannot reach Colony?
- [ ] Do we keep cap-swap-daemon.sh bash-only or accept hybrid bash+rust?

### 6.7 Cross-cutting dependencies

- lib/common.sh (planned)
- Colony CLI
- tmux

### 6.8 Risk register

- Behavioural changes in cap-swap-daemon.sh may ripple through full-bringup and daemons.
- Logging or telemetry growth without rotation.

### 6.9 Migration plan

1. Phase 1: helpers in lib/.
2. Phase 2: refactor cap-swap-daemon.sh to use helpers.
3. Phase 3: enforce in CI via shellcheck + bats.

### 6.10 Out of scope

- Replacing bash with a different orchestrator wholesale.

---

## 7. Bash Layer: stall-watcher.sh

- slug: `stall-watcher`
- captain: unassigned
- budget: ~300 lines (soft cap)

### 7.1 Mission

Make `stall-watcher.sh` reliable, debuggable, and self-documenting. It triggers rescue for stranded claims older than 30 min.

### 7.2 Current state

- `scripts/codex-fleet/stall-watcher.sh` exists and is invoked via the fleet bringup flow or daemon supervisor.
- Behaviour is documented inline via comments; no dedicated SPEC entry.
- Logging is ad-hoc; output goes to tmux pane stdout/stderr.
- Failure modes typically surface as silent exits or noisy retries.

### 7.3 Pain points

1. No structured log format; difficult to ingest into a metrics pipeline.
2. No --help output documenting flags and env vars.
3. Exit codes are not standardised across scripts.
4. Limited dry-run support; experimentation requires real fleet state.

### 7.4 Improvement protocols

#### 7.4.1 Add `--help` and `--version` to stall-watcher.sh

- state: SHIPPED
- lane: scripts lane

**Problem.** Discoverability is poor; flags are guessed from source.

**Hypothesis.** A short help message + version banner accelerates onboarding and CI introspection.

**Proposal.** Wrap entry-point with a tiny `usage()` function; version pulled from a constants file.

**Implementation steps.**

1. Refactor script to recognise --help/--version.
1. Add scripts/codex-fleet/lib/version.sh providing FLEET_VERSION.
1. Add a smoke test asserting --help exits 0 with non-empty output.

**Verification.** `bash scripts/codex-fleet/stall-watcher.sh --help` prints usage.

**Acceptance criteria.**

- --help and --version supported.
- Smoke test added.

**Rollback.** Revert to no usage banner.

**Risks.**

- Slight LOC overhead per script.

**Metrics.**

- # scripts with --help.
- Doc-coverage trend.

**References.**

- `scripts/codex-fleet/stall-watcher.sh`

#### 7.4.2 Structured logging in stall-watcher.sh

- state: PROPOSED
- lane: scripts lane

**Problem.** Plain echoes are hard to parse downstream.

**Hypothesis.** Emit `key=value`-style structured lines so the metrics-viewer crate can ingest them.

**Proposal.** Adopt a `log_kv` helper from `lib/log.sh` that emits ISO-8601 timestamp + level + key/value pairs.

**Implementation steps.**

1. Implement `lib/log.sh`.
1. Refactor critical echoes to log_kv calls.
1. Document the format in docs/future/PROTOCOL.md observability section.

**Verification.** Pipe a run of stall-watcher.sh into `awk '/level=/' ` and observe parsable lines.

**Acceptance criteria.**

- All errors and lifecycle events emit structured lines.
- fleet-metrics-viewer parses the format.

**Rollback.** Revert to plain echo.

**Risks.**

- Verbose output; need log levels.

**Metrics.**

- % structured lines per run.

**References.**

- `scripts/codex-fleet/stall-watcher.sh`
- `rust/fleet-metrics-viewer/`

### 7.5 Backlog (raw)

- Embed a structured banner in stall-watcher.sh listing all subcommands.
- Promote stall-watcher.sh to a Rust binary if footprint stabilises.
- Add fish/zsh completions for stall-watcher.sh.
- Add `--json` output mode for stall-watcher.sh where feasible.
- Provide a `--explain` mode that prints the decision tree.
- Document stall-watcher.sh interactions with Colony in detail.
- Add per-run UUID for log correlation in stall-watcher.sh.
- Add Prometheus-style metrics endpoint when running under a supervisor.
- Add chaos-test harness that injects failures into stall-watcher.sh.
- Convert long-running portions of stall-watcher.sh into a daemon-friendly service unit.

### 7.6 Open questions

- [ ] Should stall-watcher.sh be allowed to mutate tmux on the host shell, or always go through a wrapper?
- [ ] What is the right escalation when stall-watcher.sh cannot reach Colony?
- [ ] Do we keep stall-watcher.sh bash-only or accept hybrid bash+rust?

### 7.7 Cross-cutting dependencies

- lib/common.sh (planned)
- Colony CLI
- tmux

### 7.8 Risk register

- Behavioural changes in stall-watcher.sh may ripple through full-bringup and daemons.
- Logging or telemetry growth without rotation.

### 7.9 Migration plan

1. Phase 1: helpers in lib/.
2. Phase 2: refactor stall-watcher.sh to use helpers.
3. Phase 3: enforce in CI via shellcheck + bats.

### 7.10 Out of scope

- Replacing bash with a different orchestrator wholesale.

---

## 8. Bash Layer: conductor.sh

- slug: `conductor`
- captain: unassigned
- budget: ~300 lines (soft cap)

### 8.1 Mission

Make `conductor.sh` reliable, debuggable, and self-documenting. It hosts the Claude conductor pane; UX here defines the operator's mental model.

### 8.2 Current state

- `scripts/codex-fleet/conductor.sh` exists and is invoked via the fleet bringup flow or daemon supervisor.
- Behaviour is documented inline via comments; no dedicated SPEC entry.
- Logging is ad-hoc; output goes to tmux pane stdout/stderr.
- Failure modes typically surface as silent exits or noisy retries.

### 8.3 Pain points

1. No structured log format; difficult to ingest into a metrics pipeline.
2. No --help output documenting flags and env vars.
3. Exit codes are not standardised across scripts.
4. Limited dry-run support; experimentation requires real fleet state.

### 8.4 Improvement protocols

#### 8.4.1 Add `--help` and `--version` to conductor.sh

- state: PROPOSED
- lane: scripts lane

**Problem.** Discoverability is poor; flags are guessed from source.

**Hypothesis.** A short help message + version banner accelerates onboarding and CI introspection.

**Proposal.** Wrap entry-point with a tiny `usage()` function; version pulled from a constants file.

**Implementation steps.**

1. Refactor script to recognise --help/--version.
1. Add scripts/codex-fleet/lib/version.sh providing FLEET_VERSION.
1. Add a smoke test asserting --help exits 0 with non-empty output.

**Verification.** `bash scripts/codex-fleet/conductor.sh --help` prints usage.

**Acceptance criteria.**

- --help and --version supported.
- Smoke test added.

**Rollback.** Revert to no usage banner.

**Risks.**

- Slight LOC overhead per script.

**Metrics.**

- # scripts with --help.
- Doc-coverage trend.

**References.**

- `scripts/codex-fleet/conductor.sh`

#### 8.4.2 Structured logging in conductor.sh

- state: PROPOSED
- lane: scripts lane

**Problem.** Plain echoes are hard to parse downstream.

**Hypothesis.** Emit `key=value`-style structured lines so the metrics-viewer crate can ingest them.

**Proposal.** Adopt a `log_kv` helper from `lib/log.sh` that emits ISO-8601 timestamp + level + key/value pairs.

**Implementation steps.**

1. Implement `lib/log.sh`.
1. Refactor critical echoes to log_kv calls.
1. Document the format in docs/future/PROTOCOL.md observability section.

**Verification.** Pipe a run of conductor.sh into `awk '/level=/' ` and observe parsable lines.

**Acceptance criteria.**

- All errors and lifecycle events emit structured lines.
- fleet-metrics-viewer parses the format.

**Rollback.** Revert to plain echo.

**Risks.**

- Verbose output; need log levels.

**Metrics.**

- % structured lines per run.

**References.**

- `scripts/codex-fleet/conductor.sh`
- `rust/fleet-metrics-viewer/`

### 8.5 Backlog (raw)

- Embed a structured banner in conductor.sh listing all subcommands.
- Promote conductor.sh to a Rust binary if footprint stabilises.
- Add fish/zsh completions for conductor.sh.
- Add `--json` output mode for conductor.sh where feasible.
- Provide a `--explain` mode that prints the decision tree.
- Document conductor.sh interactions with Colony in detail.
- Add per-run UUID for log correlation in conductor.sh.
- Add Prometheus-style metrics endpoint when running under a supervisor.
- Add chaos-test harness that injects failures into conductor.sh.
- Convert long-running portions of conductor.sh into a daemon-friendly service unit.

### 8.6 Open questions

- [ ] Should conductor.sh be allowed to mutate tmux on the host shell, or always go through a wrapper?
- [ ] What is the right escalation when conductor.sh cannot reach Colony?
- [ ] Do we keep conductor.sh bash-only or accept hybrid bash+rust?

### 8.7 Cross-cutting dependencies

- lib/common.sh (planned)
- Colony CLI
- tmux

### 8.8 Risk register

- Behavioural changes in conductor.sh may ripple through full-bringup and daemons.
- Logging or telemetry growth without rotation.

### 8.9 Migration plan

1. Phase 1: helpers in lib/.
2. Phase 2: refactor conductor.sh to use helpers.
3. Phase 3: enforce in CI via shellcheck + bats.

### 8.10 Out of scope

- Replacing bash with a different orchestrator wholesale.

---

## 9. Bash Layer: plan-watcher.sh

- slug: `plan-watcher`
- captain: unassigned
- budget: ~300 lines (soft cap)

### 9.1 Mission

Make `plan-watcher.sh` reliable, debuggable, and self-documenting. It surfaces plan changes; correctness here drives wave progression.

### 9.2 Current state

- `scripts/codex-fleet/plan-watcher.sh` exists and is invoked via the fleet bringup flow or daemon supervisor.
- Behaviour is documented inline via comments; no dedicated SPEC entry.
- Logging is ad-hoc; output goes to tmux pane stdout/stderr.
- Failure modes typically surface as silent exits or noisy retries.

### 9.3 Pain points

1. No structured log format; difficult to ingest into a metrics pipeline.
2. No --help output documenting flags and env vars.
3. Exit codes are not standardised across scripts.
4. Limited dry-run support; experimentation requires real fleet state.

### 9.4 Improvement protocols

#### 9.4.1 Add `--help` and `--version` to plan-watcher.sh

- state: SHIPPED
- lane: scripts lane

**Problem.** Discoverability is poor; flags are guessed from source.

**Hypothesis.** A short help message + version banner accelerates onboarding and CI introspection.

**Proposal.** Wrap entry-point with a tiny `usage()` function; version pulled from a constants file.

**Implementation steps.**

1. Refactor script to recognise --help/--version.
1. Add scripts/codex-fleet/lib/version.sh providing FLEET_VERSION.
1. Add a smoke test asserting --help exits 0 with non-empty output.

**Verification.** `bash scripts/codex-fleet/plan-watcher.sh --help` prints usage.

**Acceptance criteria.**

- --help and --version supported.
- Smoke test added.

**Rollback.** Revert to no usage banner.

**Risks.**

- Slight LOC overhead per script.

**Metrics.**

- # scripts with --help.
- Doc-coverage trend.

**References.**

- `scripts/codex-fleet/plan-watcher.sh`

#### 9.4.2 Structured logging in plan-watcher.sh

- state: PROPOSED
- lane: scripts lane

**Problem.** Plain echoes are hard to parse downstream.

**Hypothesis.** Emit `key=value`-style structured lines so the metrics-viewer crate can ingest them.

**Proposal.** Adopt a `log_kv` helper from `lib/log.sh` that emits ISO-8601 timestamp + level + key/value pairs.

**Implementation steps.**

1. Implement `lib/log.sh`.
1. Refactor critical echoes to log_kv calls.
1. Document the format in docs/future/PROTOCOL.md observability section.

**Verification.** Pipe a run of plan-watcher.sh into `awk '/level=/' ` and observe parsable lines.

**Acceptance criteria.**

- All errors and lifecycle events emit structured lines.
- fleet-metrics-viewer parses the format.

**Rollback.** Revert to plain echo.

**Risks.**

- Verbose output; need log levels.

**Metrics.**

- % structured lines per run.

**References.**

- `scripts/codex-fleet/plan-watcher.sh`
- `rust/fleet-metrics-viewer/`

### 9.5 Backlog (raw)

- Embed a structured banner in plan-watcher.sh listing all subcommands.
- Promote plan-watcher.sh to a Rust binary if footprint stabilises.
- Add fish/zsh completions for plan-watcher.sh.
- Add `--json` output mode for plan-watcher.sh where feasible.
- Provide a `--explain` mode that prints the decision tree.
- Document plan-watcher.sh interactions with Colony in detail.
- Add per-run UUID for log correlation in plan-watcher.sh.
- Add Prometheus-style metrics endpoint when running under a supervisor.
- Add chaos-test harness that injects failures into plan-watcher.sh.
- Convert long-running portions of plan-watcher.sh into a daemon-friendly service unit.

### 9.6 Open questions

- [ ] Should plan-watcher.sh be allowed to mutate tmux on the host shell, or always go through a wrapper?
- [ ] What is the right escalation when plan-watcher.sh cannot reach Colony?
- [ ] Do we keep plan-watcher.sh bash-only or accept hybrid bash+rust?

### 9.7 Cross-cutting dependencies

- lib/common.sh (planned)
- Colony CLI
- tmux

### 9.8 Risk register

- Behavioural changes in plan-watcher.sh may ripple through full-bringup and daemons.
- Logging or telemetry growth without rotation.

### 9.9 Migration plan

1. Phase 1: helpers in lib/.
2. Phase 2: refactor plan-watcher.sh to use helpers.
3. Phase 3: enforce in CI via shellcheck + bats.

### 9.10 Out of scope

- Replacing bash with a different orchestrator wholesale.

---

## 10. Bash Layer: review-queue.sh

- slug: `review-queue`
- captain: unassigned
- budget: ~300 lines (soft cap)

### 10.1 Mission

Make `review-queue.sh` reliable, debuggable, and self-documenting. It feeds the review lane; latency here gates PR throughput.

### 10.2 Current state

- `scripts/codex-fleet/review-queue.sh` exists and is invoked via the fleet bringup flow or daemon supervisor.
- Behaviour is documented inline via comments; no dedicated SPEC entry.
- Logging is ad-hoc; output goes to tmux pane stdout/stderr.
- Failure modes typically surface as silent exits or noisy retries.

### 10.3 Pain points

1. No structured log format; difficult to ingest into a metrics pipeline.
2. No --help output documenting flags and env vars.
3. Exit codes are not standardised across scripts.
4. Limited dry-run support; experimentation requires real fleet state.

### 10.4 Improvement protocols

#### 10.4.1 Add `--help` and `--version` to review-queue.sh

- state: SHIPPED
- lane: scripts lane

**Problem.** Discoverability is poor; flags are guessed from source.

**Hypothesis.** A short help message + version banner accelerates onboarding and CI introspection.

**Proposal.** Wrap entry-point with a tiny `usage()` function; version pulled from a constants file.

**Implementation steps.**

1. Refactor script to recognise --help/--version.
1. Add scripts/codex-fleet/lib/version.sh providing FLEET_VERSION.
1. Add a smoke test asserting --help exits 0 with non-empty output.

**Verification.** `bash scripts/codex-fleet/review-queue.sh --help` prints usage.

**Acceptance criteria.**

- --help and --version supported.
- Smoke test added.

**Rollback.** Revert to no usage banner.

**Risks.**

- Slight LOC overhead per script.

**Metrics.**

- # scripts with --help.
- Doc-coverage trend.

**References.**

- `scripts/codex-fleet/review-queue.sh`

#### 10.4.2 Structured logging in review-queue.sh

- state: PROPOSED
- lane: scripts lane

**Problem.** Plain echoes are hard to parse downstream.

**Hypothesis.** Emit `key=value`-style structured lines so the metrics-viewer crate can ingest them.

**Proposal.** Adopt a `log_kv` helper from `lib/log.sh` that emits ISO-8601 timestamp + level + key/value pairs.

**Implementation steps.**

1. Implement `lib/log.sh`.
1. Refactor critical echoes to log_kv calls.
1. Document the format in docs/future/PROTOCOL.md observability section.

**Verification.** Pipe a run of review-queue.sh into `awk '/level=/' ` and observe parsable lines.

**Acceptance criteria.**

- All errors and lifecycle events emit structured lines.
- fleet-metrics-viewer parses the format.

**Rollback.** Revert to plain echo.

**Risks.**

- Verbose output; need log levels.

**Metrics.**

- % structured lines per run.

**References.**

- `scripts/codex-fleet/review-queue.sh`
- `rust/fleet-metrics-viewer/`

### 10.5 Backlog (raw)

- Embed a structured banner in review-queue.sh listing all subcommands.
- Promote review-queue.sh to a Rust binary if footprint stabilises.
- Add fish/zsh completions for review-queue.sh.
- Add `--json` output mode for review-queue.sh where feasible.
- Provide a `--explain` mode that prints the decision tree.
- Document review-queue.sh interactions with Colony in detail.
- Add per-run UUID for log correlation in review-queue.sh.
- Add Prometheus-style metrics endpoint when running under a supervisor.
- Add chaos-test harness that injects failures into review-queue.sh.
- Convert long-running portions of review-queue.sh into a daemon-friendly service unit.

### 10.6 Open questions

- [ ] Should review-queue.sh be allowed to mutate tmux on the host shell, or always go through a wrapper?
- [ ] What is the right escalation when review-queue.sh cannot reach Colony?
- [ ] Do we keep review-queue.sh bash-only or accept hybrid bash+rust?

### 10.7 Cross-cutting dependencies

- lib/common.sh (planned)
- Colony CLI
- tmux

### 10.8 Risk register

- Behavioural changes in review-queue.sh may ripple through full-bringup and daemons.
- Logging or telemetry growth without rotation.

### 10.9 Migration plan

1. Phase 1: helpers in lib/.
2. Phase 2: refactor review-queue.sh to use helpers.
3. Phase 3: enforce in CI via shellcheck + bats.

### 10.10 Out of scope

- Replacing bash with a different orchestrator wholesale.

---

## 11. Bash Layer: review-pane-scanner.sh

- slug: `review-pane-scanner`
- captain: unassigned
- budget: ~300 lines (soft cap)

### 11.1 Mission

Make `review-pane-scanner.sh` reliable, debuggable, and self-documenting. It auto-attaches review panes.

### 11.2 Current state

- `scripts/codex-fleet/review-pane-scanner.sh` exists and is invoked via the fleet bringup flow or daemon supervisor.
- Behaviour is documented inline via comments; no dedicated SPEC entry.
- Logging is ad-hoc; output goes to tmux pane stdout/stderr.
- Failure modes typically surface as silent exits or noisy retries.

### 11.3 Pain points

1. No structured log format; difficult to ingest into a metrics pipeline.
2. No --help output documenting flags and env vars.
3. Exit codes are not standardised across scripts.
4. Limited dry-run support; experimentation requires real fleet state.

### 11.4 Improvement protocols

#### 11.4.1 Add `--help` and `--version` to review-pane-scanner.sh

- state: SHIPPED
- lane: scripts lane

**Problem.** Discoverability is poor; flags are guessed from source.

**Hypothesis.** A short help message + version banner accelerates onboarding and CI introspection.

**Proposal.** Wrap entry-point with a tiny `usage()` function; version pulled from a constants file.

**Implementation steps.**

1. Refactor script to recognise --help/--version.
1. Add scripts/codex-fleet/lib/version.sh providing FLEET_VERSION.
1. Add a smoke test asserting --help exits 0 with non-empty output.

**Verification.** `bash scripts/codex-fleet/review-pane-scanner.sh --help` prints usage.

**Acceptance criteria.**

- --help and --version supported.
- Smoke test added.

**Rollback.** Revert to no usage banner.

**Risks.**

- Slight LOC overhead per script.

**Metrics.**

- # scripts with --help.
- Doc-coverage trend.

**References.**

- `scripts/codex-fleet/review-pane-scanner.sh`

#### 11.4.2 Structured logging in review-pane-scanner.sh

- state: PROPOSED
- lane: scripts lane

**Problem.** Plain echoes are hard to parse downstream.

**Hypothesis.** Emit `key=value`-style structured lines so the metrics-viewer crate can ingest them.

**Proposal.** Adopt a `log_kv` helper from `lib/log.sh` that emits ISO-8601 timestamp + level + key/value pairs.

**Implementation steps.**

1. Implement `lib/log.sh`.
1. Refactor critical echoes to log_kv calls.
1. Document the format in docs/future/PROTOCOL.md observability section.

**Verification.** Pipe a run of review-pane-scanner.sh into `awk '/level=/' ` and observe parsable lines.

**Acceptance criteria.**

- All errors and lifecycle events emit structured lines.
- fleet-metrics-viewer parses the format.

**Rollback.** Revert to plain echo.

**Risks.**

- Verbose output; need log levels.

**Metrics.**

- % structured lines per run.

**References.**

- `scripts/codex-fleet/review-pane-scanner.sh`
- `rust/fleet-metrics-viewer/`

### 11.5 Backlog (raw)

- Embed a structured banner in review-pane-scanner.sh listing all subcommands.
- Promote review-pane-scanner.sh to a Rust binary if footprint stabilises.
- Add fish/zsh completions for review-pane-scanner.sh.
- Add `--json` output mode for review-pane-scanner.sh where feasible.
- Provide a `--explain` mode that prints the decision tree.
- Document review-pane-scanner.sh interactions with Colony in detail.
- Add per-run UUID for log correlation in review-pane-scanner.sh.
- Add Prometheus-style metrics endpoint when running under a supervisor.
- Add chaos-test harness that injects failures into review-pane-scanner.sh.
- Convert long-running portions of review-pane-scanner.sh into a daemon-friendly service unit.

### 11.6 Open questions

- [ ] Should review-pane-scanner.sh be allowed to mutate tmux on the host shell, or always go through a wrapper?
- [ ] What is the right escalation when review-pane-scanner.sh cannot reach Colony?
- [ ] Do we keep review-pane-scanner.sh bash-only or accept hybrid bash+rust?

### 11.7 Cross-cutting dependencies

- lib/common.sh (planned)
- Colony CLI
- tmux

### 11.8 Risk register

- Behavioural changes in review-pane-scanner.sh may ripple through full-bringup and daemons.
- Logging or telemetry growth without rotation.

### 11.9 Migration plan

1. Phase 1: helpers in lib/.
2. Phase 2: refactor review-pane-scanner.sh to use helpers.
3. Phase 3: enforce in CI via shellcheck + bats.

### 11.10 Out of scope

- Replacing bash with a different orchestrator wholesale.

---

## 12. Bash Layer: auto-reviewer.sh

- slug: `auto-reviewer`
- captain: unassigned
- budget: ~300 lines (soft cap)

### 12.1 Mission

Make `auto-reviewer.sh` reliable, debuggable, and self-documenting. It automates first-pass review.

### 12.2 Current state

- `scripts/codex-fleet/auto-reviewer.sh` exists and is invoked via the fleet bringup flow or daemon supervisor.
- Behaviour is documented inline via comments; no dedicated SPEC entry.
- Logging is ad-hoc; output goes to tmux pane stdout/stderr.
- Failure modes typically surface as silent exits or noisy retries.

### 12.3 Pain points

1. No structured log format; difficult to ingest into a metrics pipeline.
2. No --help output documenting flags and env vars.
3. Exit codes are not standardised across scripts.
4. Limited dry-run support; experimentation requires real fleet state.

### 12.4 Improvement protocols

#### 12.4.1 Add `--help` and `--version` to auto-reviewer.sh

- state: SHIPPED
- lane: scripts lane

**Problem.** Discoverability is poor; flags are guessed from source.

**Hypothesis.** A short help message + version banner accelerates onboarding and CI introspection.

**Proposal.** Wrap entry-point with a tiny `usage()` function; version pulled from a constants file.

**Implementation steps.**

1. Refactor script to recognise --help/--version.
1. Add scripts/codex-fleet/lib/version.sh providing FLEET_VERSION.
1. Add a smoke test asserting --help exits 0 with non-empty output.

**Verification.** `bash scripts/codex-fleet/auto-reviewer.sh --help` prints usage.

**Acceptance criteria.**

- --help and --version supported.
- Smoke test added.

**Rollback.** Revert to no usage banner.

**Risks.**

- Slight LOC overhead per script.

**Metrics.**

- # scripts with --help.
- Doc-coverage trend.

**References.**

- `scripts/codex-fleet/auto-reviewer.sh`

#### 12.4.2 Structured logging in auto-reviewer.sh

- state: PROPOSED
- lane: scripts lane

**Problem.** Plain echoes are hard to parse downstream.

**Hypothesis.** Emit `key=value`-style structured lines so the metrics-viewer crate can ingest them.

**Proposal.** Adopt a `log_kv` helper from `lib/log.sh` that emits ISO-8601 timestamp + level + key/value pairs.

**Implementation steps.**

1. Implement `lib/log.sh`.
1. Refactor critical echoes to log_kv calls.
1. Document the format in docs/future/PROTOCOL.md observability section.

**Verification.** Pipe a run of auto-reviewer.sh into `awk '/level=/' ` and observe parsable lines.

**Acceptance criteria.**

- All errors and lifecycle events emit structured lines.
- fleet-metrics-viewer parses the format.

**Rollback.** Revert to plain echo.

**Risks.**

- Verbose output; need log levels.

**Metrics.**

- % structured lines per run.

**References.**

- `scripts/codex-fleet/auto-reviewer.sh`
- `rust/fleet-metrics-viewer/`

### 12.5 Backlog (raw)

- Embed a structured banner in auto-reviewer.sh listing all subcommands.
- Promote auto-reviewer.sh to a Rust binary if footprint stabilises.
- Add fish/zsh completions for auto-reviewer.sh.
- Add `--json` output mode for auto-reviewer.sh where feasible.
- Provide a `--explain` mode that prints the decision tree.
- Document auto-reviewer.sh interactions with Colony in detail.
- Add per-run UUID for log correlation in auto-reviewer.sh.
- Add Prometheus-style metrics endpoint when running under a supervisor.
- Add chaos-test harness that injects failures into auto-reviewer.sh.
- Convert long-running portions of auto-reviewer.sh into a daemon-friendly service unit.

### 12.6 Open questions

- [ ] Should auto-reviewer.sh be allowed to mutate tmux on the host shell, or always go through a wrapper?
- [ ] What is the right escalation when auto-reviewer.sh cannot reach Colony?
- [ ] Do we keep auto-reviewer.sh bash-only or accept hybrid bash+rust?

### 12.7 Cross-cutting dependencies

- lib/common.sh (planned)
- Colony CLI
- tmux

### 12.8 Risk register

- Behavioural changes in auto-reviewer.sh may ripple through full-bringup and daemons.
- Logging or telemetry growth without rotation.

### 12.9 Migration plan

1. Phase 1: helpers in lib/.
2. Phase 2: refactor auto-reviewer.sh to use helpers.
3. Phase 3: enforce in CI via shellcheck + bats.

### 12.10 Out of scope

- Replacing bash with a different orchestrator wholesale.

---

## 13. Bash Layer: score-checkpoint.sh

- slug: `score-checkpoint`
- captain: unassigned
- budget: ~300 lines (soft cap)

### 13.1 Mission

Make `score-checkpoint.sh` reliable, debuggable, and self-documenting. It records scoring snapshots.

### 13.2 Current state

- `scripts/codex-fleet/score-checkpoint.sh` exists and is invoked via the fleet bringup flow or daemon supervisor.
- Behaviour is documented inline via comments; no dedicated SPEC entry.
- Logging is ad-hoc; output goes to tmux pane stdout/stderr.
- Failure modes typically surface as silent exits or noisy retries.

### 13.3 Pain points

1. No structured log format; difficult to ingest into a metrics pipeline.
2. No --help output documenting flags and env vars.
3. Exit codes are not standardised across scripts.
4. Limited dry-run support; experimentation requires real fleet state.

### 13.4 Improvement protocols

#### 13.4.1 Add `--help` and `--version` to score-checkpoint.sh

- state: PROPOSED
- lane: scripts lane

**Problem.** Discoverability is poor; flags are guessed from source.

**Hypothesis.** A short help message + version banner accelerates onboarding and CI introspection.

**Proposal.** Wrap entry-point with a tiny `usage()` function; version pulled from a constants file.

**Implementation steps.**

1. Refactor script to recognise --help/--version.
1. Add scripts/codex-fleet/lib/version.sh providing FLEET_VERSION.
1. Add a smoke test asserting --help exits 0 with non-empty output.

**Verification.** `bash scripts/codex-fleet/score-checkpoint.sh --help` prints usage.

**Acceptance criteria.**

- --help and --version supported.
- Smoke test added.

**Rollback.** Revert to no usage banner.

**Risks.**

- Slight LOC overhead per script.

**Metrics.**

- # scripts with --help.
- Doc-coverage trend.

**References.**

- `scripts/codex-fleet/score-checkpoint.sh`

#### 13.4.2 Structured logging in score-checkpoint.sh

- state: PROPOSED
- lane: scripts lane

**Problem.** Plain echoes are hard to parse downstream.

**Hypothesis.** Emit `key=value`-style structured lines so the metrics-viewer crate can ingest them.

**Proposal.** Adopt a `log_kv` helper from `lib/log.sh` that emits ISO-8601 timestamp + level + key/value pairs.

**Implementation steps.**

1. Implement `lib/log.sh`.
1. Refactor critical echoes to log_kv calls.
1. Document the format in docs/future/PROTOCOL.md observability section.

**Verification.** Pipe a run of score-checkpoint.sh into `awk '/level=/' ` and observe parsable lines.

**Acceptance criteria.**

- All errors and lifecycle events emit structured lines.
- fleet-metrics-viewer parses the format.

**Rollback.** Revert to plain echo.

**Risks.**

- Verbose output; need log levels.

**Metrics.**

- % structured lines per run.

**References.**

- `scripts/codex-fleet/score-checkpoint.sh`
- `rust/fleet-metrics-viewer/`

### 13.5 Backlog (raw)

- Embed a structured banner in score-checkpoint.sh listing all subcommands.
- Promote score-checkpoint.sh to a Rust binary if footprint stabilises.
- Add fish/zsh completions for score-checkpoint.sh.
- Add `--json` output mode for score-checkpoint.sh where feasible.
- Provide a `--explain` mode that prints the decision tree.
- Document score-checkpoint.sh interactions with Colony in detail.
- Add per-run UUID for log correlation in score-checkpoint.sh.
- Add Prometheus-style metrics endpoint when running under a supervisor.
- Add chaos-test harness that injects failures into score-checkpoint.sh.
- Convert long-running portions of score-checkpoint.sh into a daemon-friendly service unit.

### 13.6 Open questions

- [ ] Should score-checkpoint.sh be allowed to mutate tmux on the host shell, or always go through a wrapper?
- [ ] What is the right escalation when score-checkpoint.sh cannot reach Colony?
- [ ] Do we keep score-checkpoint.sh bash-only or accept hybrid bash+rust?

### 13.7 Cross-cutting dependencies

- lib/common.sh (planned)
- Colony CLI
- tmux

### 13.8 Risk register

- Behavioural changes in score-checkpoint.sh may ripple through full-bringup and daemons.
- Logging or telemetry growth without rotation.

### 13.9 Migration plan

1. Phase 1: helpers in lib/.
2. Phase 2: refactor score-checkpoint.sh to use helpers.
3. Phase 3: enforce in CI via shellcheck + bats.

### 13.10 Out of scope

- Replacing bash with a different orchestrator wholesale.

---

## 14. Bash Layer: score-merged-pr.sh

- slug: `score-merged-pr`
- captain: unassigned
- budget: ~300 lines (soft cap)

### 14.1 Mission

Make `score-merged-pr.sh` reliable, debuggable, and self-documenting. It records merged-PR scoring evidence.

### 14.2 Current state

- `scripts/codex-fleet/score-merged-pr.sh` exists and is invoked via the fleet bringup flow or daemon supervisor.
- Behaviour is documented inline via comments; no dedicated SPEC entry.
- Logging is ad-hoc; output goes to tmux pane stdout/stderr.
- Failure modes typically surface as silent exits or noisy retries.

### 14.3 Pain points

1. No structured log format; difficult to ingest into a metrics pipeline.
2. No --help output documenting flags and env vars.
3. Exit codes are not standardised across scripts.
4. Limited dry-run support; experimentation requires real fleet state.

### 14.4 Improvement protocols

#### 14.4.1 Add `--help` and `--version` to score-merged-pr.sh

- state: PROPOSED
- lane: scripts lane

**Problem.** Discoverability is poor; flags are guessed from source.

**Hypothesis.** A short help message + version banner accelerates onboarding and CI introspection.

**Proposal.** Wrap entry-point with a tiny `usage()` function; version pulled from a constants file.

**Implementation steps.**

1. Refactor script to recognise --help/--version.
1. Add scripts/codex-fleet/lib/version.sh providing FLEET_VERSION.
1. Add a smoke test asserting --help exits 0 with non-empty output.

**Verification.** `bash scripts/codex-fleet/score-merged-pr.sh --help` prints usage.

**Acceptance criteria.**

- --help and --version supported.
- Smoke test added.

**Rollback.** Revert to no usage banner.

**Risks.**

- Slight LOC overhead per script.

**Metrics.**

- # scripts with --help.
- Doc-coverage trend.

**References.**

- `scripts/codex-fleet/score-merged-pr.sh`

#### 14.4.2 Structured logging in score-merged-pr.sh

- state: PROPOSED
- lane: scripts lane

**Problem.** Plain echoes are hard to parse downstream.

**Hypothesis.** Emit `key=value`-style structured lines so the metrics-viewer crate can ingest them.

**Proposal.** Adopt a `log_kv` helper from `lib/log.sh` that emits ISO-8601 timestamp + level + key/value pairs.

**Implementation steps.**

1. Implement `lib/log.sh`.
1. Refactor critical echoes to log_kv calls.
1. Document the format in docs/future/PROTOCOL.md observability section.

**Verification.** Pipe a run of score-merged-pr.sh into `awk '/level=/' ` and observe parsable lines.

**Acceptance criteria.**

- All errors and lifecycle events emit structured lines.
- fleet-metrics-viewer parses the format.

**Rollback.** Revert to plain echo.

**Risks.**

- Verbose output; need log levels.

**Metrics.**

- % structured lines per run.

**References.**

- `scripts/codex-fleet/score-merged-pr.sh`
- `rust/fleet-metrics-viewer/`

### 14.5 Backlog (raw)

- Embed a structured banner in score-merged-pr.sh listing all subcommands.
- Promote score-merged-pr.sh to a Rust binary if footprint stabilises.
- Add fish/zsh completions for score-merged-pr.sh.
- Add `--json` output mode for score-merged-pr.sh where feasible.
- Provide a `--explain` mode that prints the decision tree.
- Document score-merged-pr.sh interactions with Colony in detail.
- Add per-run UUID for log correlation in score-merged-pr.sh.
- Add Prometheus-style metrics endpoint when running under a supervisor.
- Add chaos-test harness that injects failures into score-merged-pr.sh.
- Convert long-running portions of score-merged-pr.sh into a daemon-friendly service unit.

### 14.6 Open questions

- [ ] Should score-merged-pr.sh be allowed to mutate tmux on the host shell, or always go through a wrapper?
- [ ] What is the right escalation when score-merged-pr.sh cannot reach Colony?
- [ ] Do we keep score-merged-pr.sh bash-only or accept hybrid bash+rust?

### 14.7 Cross-cutting dependencies

- lib/common.sh (planned)
- Colony CLI
- tmux

### 14.8 Risk register

- Behavioural changes in score-merged-pr.sh may ripple through full-bringup and daemons.
- Logging or telemetry growth without rotation.

### 14.9 Migration plan

1. Phase 1: helpers in lib/.
2. Phase 2: refactor score-merged-pr.sh to use helpers.
3. Phase 3: enforce in CI via shellcheck + bats.

### 14.10 Out of scope

- Replacing bash with a different orchestrator wholesale.

---

## 15. Bash Layer: watcher-board.sh

- slug: `watcher-board`
- captain: unassigned
- budget: ~300 lines (soft cap)

### 15.1 Mission

Make `watcher-board.sh` reliable, debuggable, and self-documenting. It renders the iOS-style watcher dashboard.

### 15.2 Current state

- `scripts/codex-fleet/watcher-board.sh` exists and is invoked via the fleet bringup flow or daemon supervisor.
- Behaviour is documented inline via comments; no dedicated SPEC entry.
- Logging is ad-hoc; output goes to tmux pane stdout/stderr.
- Failure modes typically surface as silent exits or noisy retries.

### 15.3 Pain points

1. No structured log format; difficult to ingest into a metrics pipeline.
2. No --help output documenting flags and env vars.
3. Exit codes are not standardised across scripts.
4. Limited dry-run support; experimentation requires real fleet state.

### 15.4 Improvement protocols

#### 15.4.1 Add `--help` and `--version` to watcher-board.sh

- state: PROPOSED
- lane: scripts lane

**Problem.** Discoverability is poor; flags are guessed from source.

**Hypothesis.** A short help message + version banner accelerates onboarding and CI introspection.

**Proposal.** Wrap entry-point with a tiny `usage()` function; version pulled from a constants file.

**Implementation steps.**

1. Refactor script to recognise --help/--version.
1. Add scripts/codex-fleet/lib/version.sh providing FLEET_VERSION.
1. Add a smoke test asserting --help exits 0 with non-empty output.

**Verification.** `bash scripts/codex-fleet/watcher-board.sh --help` prints usage.

**Acceptance criteria.**

- --help and --version supported.
- Smoke test added.

**Rollback.** Revert to no usage banner.

**Risks.**

- Slight LOC overhead per script.

**Metrics.**

- # scripts with --help.
- Doc-coverage trend.

**References.**

- `scripts/codex-fleet/watcher-board.sh`

#### 15.4.2 Structured logging in watcher-board.sh

- state: PROPOSED
- lane: scripts lane

**Problem.** Plain echoes are hard to parse downstream.

**Hypothesis.** Emit `key=value`-style structured lines so the metrics-viewer crate can ingest them.

**Proposal.** Adopt a `log_kv` helper from `lib/log.sh` that emits ISO-8601 timestamp + level + key/value pairs.

**Implementation steps.**

1. Implement `lib/log.sh`.
1. Refactor critical echoes to log_kv calls.
1. Document the format in docs/future/PROTOCOL.md observability section.

**Verification.** Pipe a run of watcher-board.sh into `awk '/level=/' ` and observe parsable lines.

**Acceptance criteria.**

- All errors and lifecycle events emit structured lines.
- fleet-metrics-viewer parses the format.

**Rollback.** Revert to plain echo.

**Risks.**

- Verbose output; need log levels.

**Metrics.**

- % structured lines per run.

**References.**

- `scripts/codex-fleet/watcher-board.sh`
- `rust/fleet-metrics-viewer/`

### 15.5 Backlog (raw)

- Embed a structured banner in watcher-board.sh listing all subcommands.
- Promote watcher-board.sh to a Rust binary if footprint stabilises.
- Add fish/zsh completions for watcher-board.sh.
- Add `--json` output mode for watcher-board.sh where feasible.
- Provide a `--explain` mode that prints the decision tree.
- Document watcher-board.sh interactions with Colony in detail.
- Add per-run UUID for log correlation in watcher-board.sh.
- Add Prometheus-style metrics endpoint when running under a supervisor.
- Add chaos-test harness that injects failures into watcher-board.sh.
- Convert long-running portions of watcher-board.sh into a daemon-friendly service unit.

### 15.6 Open questions

- [ ] Should watcher-board.sh be allowed to mutate tmux on the host shell, or always go through a wrapper?
- [ ] What is the right escalation when watcher-board.sh cannot reach Colony?
- [ ] Do we keep watcher-board.sh bash-only or accept hybrid bash+rust?

### 15.7 Cross-cutting dependencies

- lib/common.sh (planned)
- Colony CLI
- tmux

### 15.8 Risk register

- Behavioural changes in watcher-board.sh may ripple through full-bringup and daemons.
- Logging or telemetry growth without rotation.

### 15.9 Migration plan

1. Phase 1: helpers in lib/.
2. Phase 2: refactor watcher-board.sh to use helpers.
3. Phase 3: enforce in CI via shellcheck + bats.

### 15.10 Out of scope

- Replacing bash with a different orchestrator wholesale.

---

## 16. Bash Layer: style-tabs.sh

- slug: `style-tabs`
- captain: unassigned
- budget: ~300 lines (soft cap)

### 16.1 Mission

Make `style-tabs.sh` reliable, debuggable, and self-documenting. It paints the rounded pill tabs.

### 16.2 Current state

- `scripts/codex-fleet/style-tabs.sh` exists and is invoked via the fleet bringup flow or daemon supervisor.
- Behaviour is documented inline via comments; no dedicated SPEC entry.
- Logging is ad-hoc; output goes to tmux pane stdout/stderr.
- Failure modes typically surface as silent exits or noisy retries.

### 16.3 Pain points

1. No structured log format; difficult to ingest into a metrics pipeline.
2. No --help output documenting flags and env vars.
3. Exit codes are not standardised across scripts.
4. Limited dry-run support; experimentation requires real fleet state.

### 16.4 Improvement protocols

#### 16.4.1 Add `--help` and `--version` to style-tabs.sh

- state: PROPOSED
- lane: scripts lane

**Problem.** Discoverability is poor; flags are guessed from source.

**Hypothesis.** A short help message + version banner accelerates onboarding and CI introspection.

**Proposal.** Wrap entry-point with a tiny `usage()` function; version pulled from a constants file.

**Implementation steps.**

1. Refactor script to recognise --help/--version.
1. Add scripts/codex-fleet/lib/version.sh providing FLEET_VERSION.
1. Add a smoke test asserting --help exits 0 with non-empty output.

**Verification.** `bash scripts/codex-fleet/style-tabs.sh --help` prints usage.

**Acceptance criteria.**

- --help and --version supported.
- Smoke test added.

**Rollback.** Revert to no usage banner.

**Risks.**

- Slight LOC overhead per script.

**Metrics.**

- # scripts with --help.
- Doc-coverage trend.

**References.**

- `scripts/codex-fleet/style-tabs.sh`

#### 16.4.2 Structured logging in style-tabs.sh

- state: PROPOSED
- lane: scripts lane

**Problem.** Plain echoes are hard to parse downstream.

**Hypothesis.** Emit `key=value`-style structured lines so the metrics-viewer crate can ingest them.

**Proposal.** Adopt a `log_kv` helper from `lib/log.sh` that emits ISO-8601 timestamp + level + key/value pairs.

**Implementation steps.**

1. Implement `lib/log.sh`.
1. Refactor critical echoes to log_kv calls.
1. Document the format in docs/future/PROTOCOL.md observability section.

**Verification.** Pipe a run of style-tabs.sh into `awk '/level=/' ` and observe parsable lines.

**Acceptance criteria.**

- All errors and lifecycle events emit structured lines.
- fleet-metrics-viewer parses the format.

**Rollback.** Revert to plain echo.

**Risks.**

- Verbose output; need log levels.

**Metrics.**

- % structured lines per run.

**References.**

- `scripts/codex-fleet/style-tabs.sh`
- `rust/fleet-metrics-viewer/`

### 16.5 Backlog (raw)

- Embed a structured banner in style-tabs.sh listing all subcommands.
- Promote style-tabs.sh to a Rust binary if footprint stabilises.
- Add fish/zsh completions for style-tabs.sh.
- Add `--json` output mode for style-tabs.sh where feasible.
- Provide a `--explain` mode that prints the decision tree.
- Document style-tabs.sh interactions with Colony in detail.
- Add per-run UUID for log correlation in style-tabs.sh.
- Add Prometheus-style metrics endpoint when running under a supervisor.
- Add chaos-test harness that injects failures into style-tabs.sh.
- Convert long-running portions of style-tabs.sh into a daemon-friendly service unit.

### 16.6 Open questions

- [ ] Should style-tabs.sh be allowed to mutate tmux on the host shell, or always go through a wrapper?
- [ ] What is the right escalation when style-tabs.sh cannot reach Colony?
- [ ] Do we keep style-tabs.sh bash-only or accept hybrid bash+rust?

### 16.7 Cross-cutting dependencies

- lib/common.sh (planned)
- Colony CLI
- tmux

### 16.8 Risk register

- Behavioural changes in style-tabs.sh may ripple through full-bringup and daemons.
- Logging or telemetry growth without rotation.

### 16.9 Migration plan

1. Phase 1: helpers in lib/.
2. Phase 2: refactor style-tabs.sh to use helpers.
3. Phase 3: enforce in CI via shellcheck + bats.

### 16.10 Out of scope

- Replacing bash with a different orchestrator wholesale.

---

## 17. Bash Layer: show-fleet.sh

- slug: `show-fleet`
- captain: unassigned
- budget: ~300 lines (soft cap)

### 17.1 Mission

Make `show-fleet.sh` reliable, debuggable, and self-documenting. It prints fleet overview details.

### 17.2 Current state

- `scripts/codex-fleet/show-fleet.sh` exists and is invoked via the fleet bringup flow or daemon supervisor.
- Behaviour is documented inline via comments; no dedicated SPEC entry.
- Logging is ad-hoc; output goes to tmux pane stdout/stderr.
- Failure modes typically surface as silent exits or noisy retries.

### 17.3 Pain points

1. No structured log format; difficult to ingest into a metrics pipeline.
2. No --help output documenting flags and env vars.
3. Exit codes are not standardised across scripts.
4. Limited dry-run support; experimentation requires real fleet state.

### 17.4 Improvement protocols

#### 17.4.1 Add `--help` and `--version` to show-fleet.sh

- state: SHIPPED
- lane: scripts lane

**Problem.** Discoverability is poor; flags are guessed from source.

**Hypothesis.** A short help message + version banner accelerates onboarding and CI introspection.

**Proposal.** Wrap entry-point with a tiny `usage()` function; version pulled from a constants file.

**Implementation steps.**

1. Refactor script to recognise --help/--version.
1. Add scripts/codex-fleet/lib/version.sh providing FLEET_VERSION.
1. Add a smoke test asserting --help exits 0 with non-empty output.

**Verification.** `bash scripts/codex-fleet/show-fleet.sh --help` prints usage.

**Acceptance criteria.**

- --help and --version supported.
- Smoke test added.

**Rollback.** Revert to no usage banner.

**Risks.**

- Slight LOC overhead per script.

**Metrics.**

- # scripts with --help.
- Doc-coverage trend.

**References.**

- `scripts/codex-fleet/show-fleet.sh`

#### 17.4.2 Structured logging in show-fleet.sh

- state: PROPOSED
- lane: scripts lane

**Problem.** Plain echoes are hard to parse downstream.

**Hypothesis.** Emit `key=value`-style structured lines so the metrics-viewer crate can ingest them.

**Proposal.** Adopt a `log_kv` helper from `lib/log.sh` that emits ISO-8601 timestamp + level + key/value pairs.

**Implementation steps.**

1. Implement `lib/log.sh`.
1. Refactor critical echoes to log_kv calls.
1. Document the format in docs/future/PROTOCOL.md observability section.

**Verification.** Pipe a run of show-fleet.sh into `awk '/level=/' ` and observe parsable lines.

**Acceptance criteria.**

- All errors and lifecycle events emit structured lines.
- fleet-metrics-viewer parses the format.

**Rollback.** Revert to plain echo.

**Risks.**

- Verbose output; need log levels.

**Metrics.**

- % structured lines per run.

**References.**

- `scripts/codex-fleet/show-fleet.sh`
- `rust/fleet-metrics-viewer/`

### 17.5 Backlog (raw)

- Embed a structured banner in show-fleet.sh listing all subcommands.
- Promote show-fleet.sh to a Rust binary if footprint stabilises.
- Add fish/zsh completions for show-fleet.sh.
- Add `--json` output mode for show-fleet.sh where feasible.
- Provide a `--explain` mode that prints the decision tree.
- Document show-fleet.sh interactions with Colony in detail.
- Add per-run UUID for log correlation in show-fleet.sh.
- Add Prometheus-style metrics endpoint when running under a supervisor.
- Add chaos-test harness that injects failures into show-fleet.sh.
- Convert long-running portions of show-fleet.sh into a daemon-friendly service unit.

### 17.6 Open questions

- [ ] Should show-fleet.sh be allowed to mutate tmux on the host shell, or always go through a wrapper?
- [ ] What is the right escalation when show-fleet.sh cannot reach Colony?
- [ ] Do we keep show-fleet.sh bash-only or accept hybrid bash+rust?

### 17.7 Cross-cutting dependencies

- lib/common.sh (planned)
- Colony CLI
- tmux

### 17.8 Risk register

- Behavioural changes in show-fleet.sh may ripple through full-bringup and daemons.
- Logging or telemetry growth without rotation.

### 17.9 Migration plan

1. Phase 1: helpers in lib/.
2. Phase 2: refactor show-fleet.sh to use helpers.
3. Phase 3: enforce in CI via shellcheck + bats.

### 17.10 Out of scope

- Replacing bash with a different orchestrator wholesale.

---

## 18. Bash Layer: token-meter.sh

- slug: `token-meter`
- captain: unassigned
- budget: ~300 lines (soft cap)

### 18.1 Mission

Make `token-meter.sh` reliable, debuggable, and self-documenting. It surfaces per-account token consumption.

### 18.2 Current state

- `scripts/codex-fleet/token-meter.sh` exists and is invoked via the fleet bringup flow or daemon supervisor.
- Behaviour is documented inline via comments; no dedicated SPEC entry.
- Logging is ad-hoc; output goes to tmux pane stdout/stderr.
- Failure modes typically surface as silent exits or noisy retries.

### 18.3 Pain points

1. No structured log format; difficult to ingest into a metrics pipeline.
2. No --help output documenting flags and env vars.
3. Exit codes are not standardised across scripts.
4. Limited dry-run support; experimentation requires real fleet state.

### 18.4 Improvement protocols

#### 18.4.1 Add `--help` and `--version` to token-meter.sh

- state: SHIPPED
- lane: scripts lane

**Problem.** Discoverability is poor; flags are guessed from source.

**Hypothesis.** A short help message + version banner accelerates onboarding and CI introspection.

**Proposal.** Wrap entry-point with a tiny `usage()` function; version pulled from a constants file.

**Implementation steps.**

1. Refactor script to recognise --help/--version.
1. Add scripts/codex-fleet/lib/version.sh providing FLEET_VERSION.
1. Add a smoke test asserting --help exits 0 with non-empty output.

**Verification.** `bash scripts/codex-fleet/token-meter.sh --help` prints usage.

**Acceptance criteria.**

- --help and --version supported.
- Smoke test added.

**Rollback.** Revert to no usage banner.

**Risks.**

- Slight LOC overhead per script.

**Metrics.**

- # scripts with --help.
- Doc-coverage trend.

**References.**

- `scripts/codex-fleet/token-meter.sh`

#### 18.4.2 Structured logging in token-meter.sh

- state: PROPOSED
- lane: scripts lane

**Problem.** Plain echoes are hard to parse downstream.

**Hypothesis.** Emit `key=value`-style structured lines so the metrics-viewer crate can ingest them.

**Proposal.** Adopt a `log_kv` helper from `lib/log.sh` that emits ISO-8601 timestamp + level + key/value pairs.

**Implementation steps.**

1. Implement `lib/log.sh`.
1. Refactor critical echoes to log_kv calls.
1. Document the format in docs/future/PROTOCOL.md observability section.

**Verification.** Pipe a run of token-meter.sh into `awk '/level=/' ` and observe parsable lines.

**Acceptance criteria.**

- All errors and lifecycle events emit structured lines.
- fleet-metrics-viewer parses the format.

**Rollback.** Revert to plain echo.

**Risks.**

- Verbose output; need log levels.

**Metrics.**

- % structured lines per run.

**References.**

- `scripts/codex-fleet/token-meter.sh`
- `rust/fleet-metrics-viewer/`

### 18.5 Backlog (raw)

- Embed a structured banner in token-meter.sh listing all subcommands.
- Promote token-meter.sh to a Rust binary if footprint stabilises.
- Add fish/zsh completions for token-meter.sh.
- Add `--json` output mode for token-meter.sh where feasible.
- Provide a `--explain` mode that prints the decision tree.
- Document token-meter.sh interactions with Colony in detail.
- Add per-run UUID for log correlation in token-meter.sh.
- Add Prometheus-style metrics endpoint when running under a supervisor.
- Add chaos-test harness that injects failures into token-meter.sh.
- Convert long-running portions of token-meter.sh into a daemon-friendly service unit.

### 18.6 Open questions

- [ ] Should token-meter.sh be allowed to mutate tmux on the host shell, or always go through a wrapper?
- [ ] What is the right escalation when token-meter.sh cannot reach Colony?
- [ ] Do we keep token-meter.sh bash-only or accept hybrid bash+rust?

### 18.7 Cross-cutting dependencies

- lib/common.sh (planned)
- Colony CLI
- tmux

### 18.8 Risk register

- Behavioural changes in token-meter.sh may ripple through full-bringup and daemons.
- Logging or telemetry growth without rotation.

### 18.9 Migration plan

1. Phase 1: helpers in lib/.
2. Phase 2: refactor token-meter.sh to use helpers.
3. Phase 3: enforce in CI via shellcheck + bats.

### 18.10 Out of scope

- Replacing bash with a different orchestrator wholesale.

---

## 19. Bash Layer: warm-pool.sh

- slug: `warm-pool`
- captain: unassigned
- budget: ~300 lines (soft cap)

### 19.1 Mission

Make `warm-pool.sh` reliable, debuggable, and self-documenting. It keeps a warm pool of probed accounts available.

### 19.2 Current state

- `scripts/codex-fleet/warm-pool.sh` exists and is invoked via the fleet bringup flow or daemon supervisor.
- Behaviour is documented inline via comments; no dedicated SPEC entry.
- Logging is ad-hoc; output goes to tmux pane stdout/stderr.
- Failure modes typically surface as silent exits or noisy retries.

### 19.3 Pain points

1. No structured log format; difficult to ingest into a metrics pipeline.
2. No --help output documenting flags and env vars.
3. Exit codes are not standardised across scripts.
4. Limited dry-run support; experimentation requires real fleet state.

### 19.4 Improvement protocols

#### 19.4.1 Add `--help` and `--version` to warm-pool.sh

- state: SHIPPED
- lane: scripts lane

**Problem.** Discoverability is poor; flags are guessed from source.

**Hypothesis.** A short help message + version banner accelerates onboarding and CI introspection.

**Proposal.** Wrap entry-point with a tiny `usage()` function; version pulled from a constants file.

**Implementation steps.**

1. Refactor script to recognise --help/--version.
1. Add scripts/codex-fleet/lib/version.sh providing FLEET_VERSION.
1. Add a smoke test asserting --help exits 0 with non-empty output.

**Verification.** `bash scripts/codex-fleet/warm-pool.sh --help` prints usage.

**Acceptance criteria.**

- --help and --version supported.
- Smoke test added.

**Rollback.** Revert to no usage banner.

**Risks.**

- Slight LOC overhead per script.

**Metrics.**

- # scripts with --help.
- Doc-coverage trend.

**References.**

- `scripts/codex-fleet/warm-pool.sh`

#### 19.4.2 Structured logging in warm-pool.sh

- state: PROPOSED
- lane: scripts lane

**Problem.** Plain echoes are hard to parse downstream.

**Hypothesis.** Emit `key=value`-style structured lines so the metrics-viewer crate can ingest them.

**Proposal.** Adopt a `log_kv` helper from `lib/log.sh` that emits ISO-8601 timestamp + level + key/value pairs.

**Implementation steps.**

1. Implement `lib/log.sh`.
1. Refactor critical echoes to log_kv calls.
1. Document the format in docs/future/PROTOCOL.md observability section.

**Verification.** Pipe a run of warm-pool.sh into `awk '/level=/' ` and observe parsable lines.

**Acceptance criteria.**

- All errors and lifecycle events emit structured lines.
- fleet-metrics-viewer parses the format.

**Rollback.** Revert to plain echo.

**Risks.**

- Verbose output; need log levels.

**Metrics.**

- % structured lines per run.

**References.**

- `scripts/codex-fleet/warm-pool.sh`
- `rust/fleet-metrics-viewer/`

### 19.5 Backlog (raw)

- Embed a structured banner in warm-pool.sh listing all subcommands.
- Promote warm-pool.sh to a Rust binary if footprint stabilises.
- Add fish/zsh completions for warm-pool.sh.
- Add `--json` output mode for warm-pool.sh where feasible.
- Provide a `--explain` mode that prints the decision tree.
- Document warm-pool.sh interactions with Colony in detail.
- Add per-run UUID for log correlation in warm-pool.sh.
- Add Prometheus-style metrics endpoint when running under a supervisor.
- Add chaos-test harness that injects failures into warm-pool.sh.
- Convert long-running portions of warm-pool.sh into a daemon-friendly service unit.

### 19.6 Open questions

- [ ] Should warm-pool.sh be allowed to mutate tmux on the host shell, or always go through a wrapper?
- [ ] What is the right escalation when warm-pool.sh cannot reach Colony?
- [ ] Do we keep warm-pool.sh bash-only or accept hybrid bash+rust?

### 19.7 Cross-cutting dependencies

- lib/common.sh (planned)
- Colony CLI
- tmux

### 19.8 Risk register

- Behavioural changes in warm-pool.sh may ripple through full-bringup and daemons.
- Logging or telemetry growth without rotation.

### 19.9 Migration plan

1. Phase 1: helpers in lib/.
2. Phase 2: refactor warm-pool.sh to use helpers.
3. Phase 3: enforce in CI via shellcheck + bats.

### 19.10 Out of scope

- Replacing bash with a different orchestrator wholesale.

---

## 20. Bash Layer: spawn-fleet.sh

- slug: `spawn-fleet`
- captain: unassigned
- budget: ~300 lines (soft cap)

### 20.1 Mission

Make `spawn-fleet.sh` reliable, debuggable, and self-documenting. It is the lower-level fleet spawner.

### 20.2 Current state

- `scripts/codex-fleet/spawn-fleet.sh` exists and is invoked via the fleet bringup flow or daemon supervisor.
- Behaviour is documented inline via comments; no dedicated SPEC entry.
- Logging is ad-hoc; output goes to tmux pane stdout/stderr.
- Failure modes typically surface as silent exits or noisy retries.

### 20.3 Pain points

1. No structured log format; difficult to ingest into a metrics pipeline.
2. No --help output documenting flags and env vars.
3. Exit codes are not standardised across scripts.
4. Limited dry-run support; experimentation requires real fleet state.

### 20.4 Improvement protocols

#### 20.4.1 Add `--help` and `--version` to spawn-fleet.sh

- state: SHIPPED
- lane: scripts lane

**Problem.** Discoverability is poor; flags are guessed from source.

**Hypothesis.** A short help message + version banner accelerates onboarding and CI introspection.

**Proposal.** Wrap entry-point with a tiny `usage()` function; version pulled from a constants file.

**Implementation steps.**

1. Refactor script to recognise --help/--version.
1. Add scripts/codex-fleet/lib/version.sh providing FLEET_VERSION.
1. Add a smoke test asserting --help exits 0 with non-empty output.

**Verification.** `bash scripts/codex-fleet/spawn-fleet.sh --help` prints usage.

**Acceptance criteria.**

- --help and --version supported.
- Smoke test added.

**Rollback.** Revert to no usage banner.

**Risks.**

- Slight LOC overhead per script.

**Metrics.**

- # scripts with --help.
- Doc-coverage trend.

**References.**

- `scripts/codex-fleet/spawn-fleet.sh`

#### 20.4.2 Structured logging in spawn-fleet.sh

- state: PROPOSED
- lane: scripts lane

**Problem.** Plain echoes are hard to parse downstream.

**Hypothesis.** Emit `key=value`-style structured lines so the metrics-viewer crate can ingest them.

**Proposal.** Adopt a `log_kv` helper from `lib/log.sh` that emits ISO-8601 timestamp + level + key/value pairs.

**Implementation steps.**

1. Implement `lib/log.sh`.
1. Refactor critical echoes to log_kv calls.
1. Document the format in docs/future/PROTOCOL.md observability section.

**Verification.** Pipe a run of spawn-fleet.sh into `awk '/level=/' ` and observe parsable lines.

**Acceptance criteria.**

- All errors and lifecycle events emit structured lines.
- fleet-metrics-viewer parses the format.

**Rollback.** Revert to plain echo.

**Risks.**

- Verbose output; need log levels.

**Metrics.**

- % structured lines per run.

**References.**

- `scripts/codex-fleet/spawn-fleet.sh`
- `rust/fleet-metrics-viewer/`

### 20.5 Backlog (raw)

- Embed a structured banner in spawn-fleet.sh listing all subcommands.
- Promote spawn-fleet.sh to a Rust binary if footprint stabilises.
- Add fish/zsh completions for spawn-fleet.sh.
- Add `--json` output mode for spawn-fleet.sh where feasible.
- Provide a `--explain` mode that prints the decision tree.
- Document spawn-fleet.sh interactions with Colony in detail.
- Add per-run UUID for log correlation in spawn-fleet.sh.
- Add Prometheus-style metrics endpoint when running under a supervisor.
- Add chaos-test harness that injects failures into spawn-fleet.sh.
- Convert long-running portions of spawn-fleet.sh into a daemon-friendly service unit.

### 20.6 Open questions

- [ ] Should spawn-fleet.sh be allowed to mutate tmux on the host shell, or always go through a wrapper?
- [ ] What is the right escalation when spawn-fleet.sh cannot reach Colony?
- [ ] Do we keep spawn-fleet.sh bash-only or accept hybrid bash+rust?

### 20.7 Cross-cutting dependencies

- lib/common.sh (planned)
- Colony CLI
- tmux

### 20.8 Risk register

- Behavioural changes in spawn-fleet.sh may ripple through full-bringup and daemons.
- Logging or telemetry growth without rotation.

### 20.9 Migration plan

1. Phase 1: helpers in lib/.
2. Phase 2: refactor spawn-fleet.sh to use helpers.
3. Phase 3: enforce in CI via shellcheck + bats.

### 20.10 Out of scope

- Replacing bash with a different orchestrator wholesale.

---

## 21. Bash Layer: dispatch-plan.sh

- slug: `dispatch-plan`
- captain: unassigned
- budget: ~300 lines (soft cap)

### 21.1 Mission

Make `dispatch-plan.sh` reliable, debuggable, and self-documenting. It publishes plan workspaces into Colony.

### 21.2 Current state

- `scripts/codex-fleet/dispatch-plan.sh` exists and is invoked via the fleet bringup flow or daemon supervisor.
- Behaviour is documented inline via comments; no dedicated SPEC entry.
- Logging is ad-hoc; output goes to tmux pane stdout/stderr.
- Failure modes typically surface as silent exits or noisy retries.

### 21.3 Pain points

1. No structured log format; difficult to ingest into a metrics pipeline.
2. No --help output documenting flags and env vars.
3. Exit codes are not standardised across scripts.
4. Limited dry-run support; experimentation requires real fleet state.

### 21.4 Improvement protocols

#### 21.4.1 Add `--help` and `--version` to dispatch-plan.sh

- state: SHIPPED
- lane: scripts lane

**Problem.** Discoverability is poor; flags are guessed from source.

**Hypothesis.** A short help message + version banner accelerates onboarding and CI introspection.

**Proposal.** Wrap entry-point with a tiny `usage()` function; version pulled from a constants file.

**Implementation steps.**

1. Refactor script to recognise --help/--version.
1. Add scripts/codex-fleet/lib/version.sh providing FLEET_VERSION.
1. Add a smoke test asserting --help exits 0 with non-empty output.

**Verification.** `bash scripts/codex-fleet/dispatch-plan.sh --help` prints usage.

**Acceptance criteria.**

- --help and --version supported.
- Smoke test added.

**Rollback.** Revert to no usage banner.

**Risks.**

- Slight LOC overhead per script.

**Metrics.**

- # scripts with --help.
- Doc-coverage trend.

**References.**

- `scripts/codex-fleet/dispatch-plan.sh`

#### 21.4.2 Structured logging in dispatch-plan.sh

- state: PROPOSED
- lane: scripts lane

**Problem.** Plain echoes are hard to parse downstream.

**Hypothesis.** Emit `key=value`-style structured lines so the metrics-viewer crate can ingest them.

**Proposal.** Adopt a `log_kv` helper from `lib/log.sh` that emits ISO-8601 timestamp + level + key/value pairs.

**Implementation steps.**

1. Implement `lib/log.sh`.
1. Refactor critical echoes to log_kv calls.
1. Document the format in docs/future/PROTOCOL.md observability section.

**Verification.** Pipe a run of dispatch-plan.sh into `awk '/level=/' ` and observe parsable lines.

**Acceptance criteria.**

- All errors and lifecycle events emit structured lines.
- fleet-metrics-viewer parses the format.

**Rollback.** Revert to plain echo.

**Risks.**

- Verbose output; need log levels.

**Metrics.**

- % structured lines per run.

**References.**

- `scripts/codex-fleet/dispatch-plan.sh`
- `rust/fleet-metrics-viewer/`

### 21.5 Backlog (raw)

- Embed a structured banner in dispatch-plan.sh listing all subcommands.
- Promote dispatch-plan.sh to a Rust binary if footprint stabilises.
- Add fish/zsh completions for dispatch-plan.sh.
- Add `--json` output mode for dispatch-plan.sh where feasible.
- Provide a `--explain` mode that prints the decision tree.
- Document dispatch-plan.sh interactions with Colony in detail.
- Add per-run UUID for log correlation in dispatch-plan.sh.
- Add Prometheus-style metrics endpoint when running under a supervisor.
- Add chaos-test harness that injects failures into dispatch-plan.sh.
- Convert long-running portions of dispatch-plan.sh into a daemon-friendly service unit.

### 21.6 Open questions

- [ ] Should dispatch-plan.sh be allowed to mutate tmux on the host shell, or always go through a wrapper?
- [ ] What is the right escalation when dispatch-plan.sh cannot reach Colony?
- [ ] Do we keep dispatch-plan.sh bash-only or accept hybrid bash+rust?

### 21.7 Cross-cutting dependencies

- lib/common.sh (planned)
- Colony CLI
- tmux

### 21.8 Risk register

- Behavioural changes in dispatch-plan.sh may ripple through full-bringup and daemons.
- Logging or telemetry growth without rotation.

### 21.9 Migration plan

1. Phase 1: helpers in lib/.
2. Phase 2: refactor dispatch-plan.sh to use helpers.
3. Phase 3: enforce in CI via shellcheck + bats.

### 21.10 Out of scope

- Replacing bash with a different orchestrator wholesale.

---

## 22. Bash Layer: cap-probe.sh

- slug: `cap-probe`
- captain: unassigned
- budget: ~300 lines (soft cap)

### 22.1 Mission

Make `cap-probe.sh` reliable, debuggable, and self-documenting. It probes accounts for cap status.

### 22.2 Current state

- `scripts/codex-fleet/cap-probe.sh` exists and is invoked via the fleet bringup flow or daemon supervisor.
- Behaviour is documented inline via comments; no dedicated SPEC entry.
- Logging is ad-hoc; output goes to tmux pane stdout/stderr.
- Failure modes typically surface as silent exits or noisy retries.

### 22.3 Pain points

1. No structured log format; difficult to ingest into a metrics pipeline.
2. No --help output documenting flags and env vars.
3. Exit codes are not standardised across scripts.
4. Limited dry-run support; experimentation requires real fleet state.

### 22.4 Improvement protocols

#### 22.4.1 Add `--help` and `--version` to cap-probe.sh

- state: PROPOSED
- lane: scripts lane

**Problem.** Discoverability is poor; flags are guessed from source.

**Hypothesis.** A short help message + version banner accelerates onboarding and CI introspection.

**Proposal.** Wrap entry-point with a tiny `usage()` function; version pulled from a constants file.

**Implementation steps.**

1. Refactor script to recognise --help/--version.
1. Add scripts/codex-fleet/lib/version.sh providing FLEET_VERSION.
1. Add a smoke test asserting --help exits 0 with non-empty output.

**Verification.** `bash scripts/codex-fleet/cap-probe.sh --help` prints usage.

**Acceptance criteria.**

- --help and --version supported.
- Smoke test added.

**Rollback.** Revert to no usage banner.

**Risks.**

- Slight LOC overhead per script.

**Metrics.**

- # scripts with --help.
- Doc-coverage trend.

**References.**

- `scripts/codex-fleet/cap-probe.sh`

#### 22.4.2 Structured logging in cap-probe.sh

- state: PROPOSED
- lane: scripts lane

**Problem.** Plain echoes are hard to parse downstream.

**Hypothesis.** Emit `key=value`-style structured lines so the metrics-viewer crate can ingest them.

**Proposal.** Adopt a `log_kv` helper from `lib/log.sh` that emits ISO-8601 timestamp + level + key/value pairs.

**Implementation steps.**

1. Implement `lib/log.sh`.
1. Refactor critical echoes to log_kv calls.
1. Document the format in docs/future/PROTOCOL.md observability section.

**Verification.** Pipe a run of cap-probe.sh into `awk '/level=/' ` and observe parsable lines.

**Acceptance criteria.**

- All errors and lifecycle events emit structured lines.
- fleet-metrics-viewer parses the format.

**Rollback.** Revert to plain echo.

**Risks.**

- Verbose output; need log levels.

**Metrics.**

- % structured lines per run.

**References.**

- `scripts/codex-fleet/cap-probe.sh`
- `rust/fleet-metrics-viewer/`

### 22.5 Backlog (raw)

- Embed a structured banner in cap-probe.sh listing all subcommands.
- Promote cap-probe.sh to a Rust binary if footprint stabilises.
- Add fish/zsh completions for cap-probe.sh.
- Add `--json` output mode for cap-probe.sh where feasible.
- Provide a `--explain` mode that prints the decision tree.
- Document cap-probe.sh interactions with Colony in detail.
- Add per-run UUID for log correlation in cap-probe.sh.
- Add Prometheus-style metrics endpoint when running under a supervisor.
- Add chaos-test harness that injects failures into cap-probe.sh.
- Convert long-running portions of cap-probe.sh into a daemon-friendly service unit.

### 22.6 Open questions

- [ ] Should cap-probe.sh be allowed to mutate tmux on the host shell, or always go through a wrapper?
- [ ] What is the right escalation when cap-probe.sh cannot reach Colony?
- [ ] Do we keep cap-probe.sh bash-only or accept hybrid bash+rust?

### 22.7 Cross-cutting dependencies

- lib/common.sh (planned)
- Colony CLI
- tmux

### 22.8 Risk register

- Behavioural changes in cap-probe.sh may ripple through full-bringup and daemons.
- Logging or telemetry growth without rotation.

### 22.9 Migration plan

1. Phase 1: helpers in lib/.
2. Phase 2: refactor cap-probe.sh to use helpers.
3. Phase 3: enforce in CI via shellcheck + bats.

### 22.10 Out of scope

- Replacing bash with a different orchestrator wholesale.

---

## 23. Bash Layer: proactive-probe.sh

- slug: `proactive-probe`
- captain: unassigned
- budget: ~300 lines (soft cap)

### 23.1 Mission

Make `proactive-probe.sh` reliable, debuggable, and self-documenting. It periodically probes accounts proactively.

### 23.2 Current state

- `scripts/codex-fleet/proactive-probe.sh` exists and is invoked via the fleet bringup flow or daemon supervisor.
- Behaviour is documented inline via comments; no dedicated SPEC entry.
- Logging is ad-hoc; output goes to tmux pane stdout/stderr.
- Failure modes typically surface as silent exits or noisy retries.

### 23.3 Pain points

1. No structured log format; difficult to ingest into a metrics pipeline.
2. No --help output documenting flags and env vars.
3. Exit codes are not standardised across scripts.
4. Limited dry-run support; experimentation requires real fleet state.

### 23.4 Improvement protocols

#### 23.4.1 Add `--help` and `--version` to proactive-probe.sh

- state: SHIPPED
- lane: scripts lane

**Problem.** Discoverability is poor; flags are guessed from source.

**Hypothesis.** A short help message + version banner accelerates onboarding and CI introspection.

**Proposal.** Wrap entry-point with a tiny `usage()` function; version pulled from a constants file.

**Implementation steps.**

1. Refactor script to recognise --help/--version.
1. Add scripts/codex-fleet/lib/version.sh providing FLEET_VERSION.
1. Add a smoke test asserting --help exits 0 with non-empty output.

**Verification.** `bash scripts/codex-fleet/proactive-probe.sh --help` prints usage.

**Acceptance criteria.**

- --help and --version supported.
- Smoke test added.

**Rollback.** Revert to no usage banner.

**Risks.**

- Slight LOC overhead per script.

**Metrics.**

- # scripts with --help.
- Doc-coverage trend.

**References.**

- `scripts/codex-fleet/proactive-probe.sh`

#### 23.4.2 Structured logging in proactive-probe.sh

- state: PROPOSED
- lane: scripts lane

**Problem.** Plain echoes are hard to parse downstream.

**Hypothesis.** Emit `key=value`-style structured lines so the metrics-viewer crate can ingest them.

**Proposal.** Adopt a `log_kv` helper from `lib/log.sh` that emits ISO-8601 timestamp + level + key/value pairs.

**Implementation steps.**

1. Implement `lib/log.sh`.
1. Refactor critical echoes to log_kv calls.
1. Document the format in docs/future/PROTOCOL.md observability section.

**Verification.** Pipe a run of proactive-probe.sh into `awk '/level=/' ` and observe parsable lines.

**Acceptance criteria.**

- All errors and lifecycle events emit structured lines.
- fleet-metrics-viewer parses the format.

**Rollback.** Revert to plain echo.

**Risks.**

- Verbose output; need log levels.

**Metrics.**

- % structured lines per run.

**References.**

- `scripts/codex-fleet/proactive-probe.sh`
- `rust/fleet-metrics-viewer/`

### 23.5 Backlog (raw)

- Embed a structured banner in proactive-probe.sh listing all subcommands.
- Promote proactive-probe.sh to a Rust binary if footprint stabilises.
- Add fish/zsh completions for proactive-probe.sh.
- Add `--json` output mode for proactive-probe.sh where feasible.
- Provide a `--explain` mode that prints the decision tree.
- Document proactive-probe.sh interactions with Colony in detail.
- Add per-run UUID for log correlation in proactive-probe.sh.
- Add Prometheus-style metrics endpoint when running under a supervisor.
- Add chaos-test harness that injects failures into proactive-probe.sh.
- Convert long-running portions of proactive-probe.sh into a daemon-friendly service unit.

### 23.6 Open questions

- [ ] Should proactive-probe.sh be allowed to mutate tmux on the host shell, or always go through a wrapper?
- [ ] What is the right escalation when proactive-probe.sh cannot reach Colony?
- [ ] Do we keep proactive-probe.sh bash-only or accept hybrid bash+rust?

### 23.7 Cross-cutting dependencies

- lib/common.sh (planned)
- Colony CLI
- tmux

### 23.8 Risk register

- Behavioural changes in proactive-probe.sh may ripple through full-bringup and daemons.
- Logging or telemetry growth without rotation.

### 23.9 Migration plan

1. Phase 1: helpers in lib/.
2. Phase 2: refactor proactive-probe.sh to use helpers.
3. Phase 3: enforce in CI via shellcheck + bats.

### 23.10 Out of scope

- Replacing bash with a different orchestrator wholesale.

---

## 24. Bash Layer: claim-trigger.sh

- slug: `claim-trigger`
- captain: unassigned
- budget: ~300 lines (soft cap)

### 24.1 Mission

Make `claim-trigger.sh` reliable, debuggable, and self-documenting. It triggers claim dispatch loops.

### 24.2 Current state

- `scripts/codex-fleet/claim-trigger.sh` exists and is invoked via the fleet bringup flow or daemon supervisor.
- Behaviour is documented inline via comments; no dedicated SPEC entry.
- Logging is ad-hoc; output goes to tmux pane stdout/stderr.
- Failure modes typically surface as silent exits or noisy retries.

### 24.3 Pain points

1. No structured log format; difficult to ingest into a metrics pipeline.
2. No --help output documenting flags and env vars.
3. Exit codes are not standardised across scripts.
4. Limited dry-run support; experimentation requires real fleet state.

### 24.4 Improvement protocols

#### 24.4.1 Add `--help` and `--version` to claim-trigger.sh

- state: SHIPPED
- lane: scripts lane

**Problem.** Discoverability is poor; flags are guessed from source.

**Hypothesis.** A short help message + version banner accelerates onboarding and CI introspection.

**Proposal.** Wrap entry-point with a tiny `usage()` function; version pulled from a constants file.

**Implementation steps.**

1. Refactor script to recognise --help/--version.
1. Add scripts/codex-fleet/lib/version.sh providing FLEET_VERSION.
1. Add a smoke test asserting --help exits 0 with non-empty output.

**Verification.** `bash scripts/codex-fleet/claim-trigger.sh --help` prints usage.

**Acceptance criteria.**

- --help and --version supported.
- Smoke test added.

**Rollback.** Revert to no usage banner.

**Risks.**

- Slight LOC overhead per script.

**Metrics.**

- # scripts with --help.
- Doc-coverage trend.

**References.**

- `scripts/codex-fleet/claim-trigger.sh`

#### 24.4.2 Structured logging in claim-trigger.sh

- state: PROPOSED
- lane: scripts lane

**Problem.** Plain echoes are hard to parse downstream.

**Hypothesis.** Emit `key=value`-style structured lines so the metrics-viewer crate can ingest them.

**Proposal.** Adopt a `log_kv` helper from `lib/log.sh` that emits ISO-8601 timestamp + level + key/value pairs.

**Implementation steps.**

1. Implement `lib/log.sh`.
1. Refactor critical echoes to log_kv calls.
1. Document the format in docs/future/PROTOCOL.md observability section.

**Verification.** Pipe a run of claim-trigger.sh into `awk '/level=/' ` and observe parsable lines.

**Acceptance criteria.**

- All errors and lifecycle events emit structured lines.
- fleet-metrics-viewer parses the format.

**Rollback.** Revert to plain echo.

**Risks.**

- Verbose output; need log levels.

**Metrics.**

- % structured lines per run.

**References.**

- `scripts/codex-fleet/claim-trigger.sh`
- `rust/fleet-metrics-viewer/`

### 24.5 Backlog (raw)

- Embed a structured banner in claim-trigger.sh listing all subcommands.
- Promote claim-trigger.sh to a Rust binary if footprint stabilises.
- Add fish/zsh completions for claim-trigger.sh.
- Add `--json` output mode for claim-trigger.sh where feasible.
- Provide a `--explain` mode that prints the decision tree.
- Document claim-trigger.sh interactions with Colony in detail.
- Add per-run UUID for log correlation in claim-trigger.sh.
- Add Prometheus-style metrics endpoint when running under a supervisor.
- Add chaos-test harness that injects failures into claim-trigger.sh.
- Convert long-running portions of claim-trigger.sh into a daemon-friendly service unit.

### 24.6 Open questions

- [ ] Should claim-trigger.sh be allowed to mutate tmux on the host shell, or always go through a wrapper?
- [ ] What is the right escalation when claim-trigger.sh cannot reach Colony?
- [ ] Do we keep claim-trigger.sh bash-only or accept hybrid bash+rust?

### 24.7 Cross-cutting dependencies

- lib/common.sh (planned)
- Colony CLI
- tmux

### 24.8 Risk register

- Behavioural changes in claim-trigger.sh may ripple through full-bringup and daemons.
- Logging or telemetry growth without rotation.

### 24.9 Migration plan

1. Phase 1: helpers in lib/.
2. Phase 2: refactor claim-trigger.sh to use helpers.
3. Phase 3: enforce in CI via shellcheck + bats.

### 24.10 Out of scope

- Replacing bash with a different orchestrator wholesale.

---

## 25. Bash Layer: claude-worker.sh

- slug: `claude-worker`
- captain: unassigned
- budget: ~300 lines (soft cap)

### 25.1 Mission

Make `claude-worker.sh` reliable, debuggable, and self-documenting. It hosts a Claude-driven worker pane.

### 25.2 Current state

- `scripts/codex-fleet/claude-worker.sh` exists and is invoked via the fleet bringup flow or daemon supervisor.
- Behaviour is documented inline via comments; no dedicated SPEC entry.
- Logging is ad-hoc; output goes to tmux pane stdout/stderr.
- Failure modes typically surface as silent exits or noisy retries.

### 25.3 Pain points

1. No structured log format; difficult to ingest into a metrics pipeline.
2. No --help output documenting flags and env vars.
3. Exit codes are not standardised across scripts.
4. Limited dry-run support; experimentation requires real fleet state.

### 25.4 Improvement protocols

#### 25.4.1 Add `--help` and `--version` to claude-worker.sh

- state: PROPOSED
- lane: scripts lane

**Problem.** Discoverability is poor; flags are guessed from source.

**Hypothesis.** A short help message + version banner accelerates onboarding and CI introspection.

**Proposal.** Wrap entry-point with a tiny `usage()` function; version pulled from a constants file.

**Implementation steps.**

1. Refactor script to recognise --help/--version.
1. Add scripts/codex-fleet/lib/version.sh providing FLEET_VERSION.
1. Add a smoke test asserting --help exits 0 with non-empty output.

**Verification.** `bash scripts/codex-fleet/claude-worker.sh --help` prints usage.

**Acceptance criteria.**

- --help and --version supported.
- Smoke test added.

**Rollback.** Revert to no usage banner.

**Risks.**

- Slight LOC overhead per script.

**Metrics.**

- # scripts with --help.
- Doc-coverage trend.

**References.**

- `scripts/codex-fleet/claude-worker.sh`

#### 25.4.2 Structured logging in claude-worker.sh

- state: PROPOSED
- lane: scripts lane

**Problem.** Plain echoes are hard to parse downstream.

**Hypothesis.** Emit `key=value`-style structured lines so the metrics-viewer crate can ingest them.

**Proposal.** Adopt a `log_kv` helper from `lib/log.sh` that emits ISO-8601 timestamp + level + key/value pairs.

**Implementation steps.**

1. Implement `lib/log.sh`.
1. Refactor critical echoes to log_kv calls.
1. Document the format in docs/future/PROTOCOL.md observability section.

**Verification.** Pipe a run of claude-worker.sh into `awk '/level=/' ` and observe parsable lines.

**Acceptance criteria.**

- All errors and lifecycle events emit structured lines.
- fleet-metrics-viewer parses the format.

**Rollback.** Revert to plain echo.

**Risks.**

- Verbose output; need log levels.

**Metrics.**

- % structured lines per run.

**References.**

- `scripts/codex-fleet/claude-worker.sh`
- `rust/fleet-metrics-viewer/`

### 25.5 Backlog (raw)

- Embed a structured banner in claude-worker.sh listing all subcommands.
- Promote claude-worker.sh to a Rust binary if footprint stabilises.
- Add fish/zsh completions for claude-worker.sh.
- Add `--json` output mode for claude-worker.sh where feasible.
- Provide a `--explain` mode that prints the decision tree.
- Document claude-worker.sh interactions with Colony in detail.
- Add per-run UUID for log correlation in claude-worker.sh.
- Add Prometheus-style metrics endpoint when running under a supervisor.
- Add chaos-test harness that injects failures into claude-worker.sh.
- Convert long-running portions of claude-worker.sh into a daemon-friendly service unit.

### 25.6 Open questions

- [ ] Should claude-worker.sh be allowed to mutate tmux on the host shell, or always go through a wrapper?
- [ ] What is the right escalation when claude-worker.sh cannot reach Colony?
- [ ] Do we keep claude-worker.sh bash-only or accept hybrid bash+rust?

### 25.7 Cross-cutting dependencies

- lib/common.sh (planned)
- Colony CLI
- tmux

### 25.8 Risk register

- Behavioural changes in claude-worker.sh may ripple through full-bringup and daemons.
- Logging or telemetry growth without rotation.

### 25.9 Migration plan

1. Phase 1: helpers in lib/.
2. Phase 2: refactor claude-worker.sh to use helpers.
3. Phase 3: enforce in CI via shellcheck + bats.

### 25.10 Out of scope

- Replacing bash with a different orchestrator wholesale.

---

## 26. Bash Layer: claude-spawn.sh

- slug: `claude-spawn`
- captain: unassigned
- budget: ~300 lines (soft cap)

### 26.1 Mission

Make `claude-spawn.sh` reliable, debuggable, and self-documenting. It spawns claude worker panes.

### 26.2 Current state

- `scripts/codex-fleet/claude-spawn.sh` exists and is invoked via the fleet bringup flow or daemon supervisor.
- Behaviour is documented inline via comments; no dedicated SPEC entry.
- Logging is ad-hoc; output goes to tmux pane stdout/stderr.
- Failure modes typically surface as silent exits or noisy retries.

### 26.3 Pain points

1. No structured log format; difficult to ingest into a metrics pipeline.
2. No --help output documenting flags and env vars.
3. Exit codes are not standardised across scripts.
4. Limited dry-run support; experimentation requires real fleet state.

### 26.4 Improvement protocols

#### 26.4.1 Add `--help` and `--version` to claude-spawn.sh

- state: PROPOSED
- lane: scripts lane

**Problem.** Discoverability is poor; flags are guessed from source.

**Hypothesis.** A short help message + version banner accelerates onboarding and CI introspection.

**Proposal.** Wrap entry-point with a tiny `usage()` function; version pulled from a constants file.

**Implementation steps.**

1. Refactor script to recognise --help/--version.
1. Add scripts/codex-fleet/lib/version.sh providing FLEET_VERSION.
1. Add a smoke test asserting --help exits 0 with non-empty output.

**Verification.** `bash scripts/codex-fleet/claude-spawn.sh --help` prints usage.

**Acceptance criteria.**

- --help and --version supported.
- Smoke test added.

**Rollback.** Revert to no usage banner.

**Risks.**

- Slight LOC overhead per script.

**Metrics.**

- # scripts with --help.
- Doc-coverage trend.

**References.**

- `scripts/codex-fleet/claude-spawn.sh`

#### 26.4.2 Structured logging in claude-spawn.sh

- state: PROPOSED
- lane: scripts lane

**Problem.** Plain echoes are hard to parse downstream.

**Hypothesis.** Emit `key=value`-style structured lines so the metrics-viewer crate can ingest them.

**Proposal.** Adopt a `log_kv` helper from `lib/log.sh` that emits ISO-8601 timestamp + level + key/value pairs.

**Implementation steps.**

1. Implement `lib/log.sh`.
1. Refactor critical echoes to log_kv calls.
1. Document the format in docs/future/PROTOCOL.md observability section.

**Verification.** Pipe a run of claude-spawn.sh into `awk '/level=/' ` and observe parsable lines.

**Acceptance criteria.**

- All errors and lifecycle events emit structured lines.
- fleet-metrics-viewer parses the format.

**Rollback.** Revert to plain echo.

**Risks.**

- Verbose output; need log levels.

**Metrics.**

- % structured lines per run.

**References.**

- `scripts/codex-fleet/claude-spawn.sh`
- `rust/fleet-metrics-viewer/`

### 26.5 Backlog (raw)

- Embed a structured banner in claude-spawn.sh listing all subcommands.
- Promote claude-spawn.sh to a Rust binary if footprint stabilises.
- Add fish/zsh completions for claude-spawn.sh.
- Add `--json` output mode for claude-spawn.sh where feasible.
- Provide a `--explain` mode that prints the decision tree.
- Document claude-spawn.sh interactions with Colony in detail.
- Add per-run UUID for log correlation in claude-spawn.sh.
- Add Prometheus-style metrics endpoint when running under a supervisor.
- Add chaos-test harness that injects failures into claude-spawn.sh.
- Convert long-running portions of claude-spawn.sh into a daemon-friendly service unit.

### 26.6 Open questions

- [ ] Should claude-spawn.sh be allowed to mutate tmux on the host shell, or always go through a wrapper?
- [ ] What is the right escalation when claude-spawn.sh cannot reach Colony?
- [ ] Do we keep claude-spawn.sh bash-only or accept hybrid bash+rust?

### 26.7 Cross-cutting dependencies

- lib/common.sh (planned)
- Colony CLI
- tmux

### 26.8 Risk register

- Behavioural changes in claude-spawn.sh may ripple through full-bringup and daemons.
- Logging or telemetry growth without rotation.

### 26.9 Migration plan

1. Phase 1: helpers in lib/.
2. Phase 2: refactor claude-spawn.sh to use helpers.
3. Phase 3: enforce in CI via shellcheck + bats.

### 26.10 Out of scope

- Replacing bash with a different orchestrator wholesale.

---

## 27. Bash Layer: claude-supervisor.sh

- slug: `claude-supervisor`
- captain: unassigned
- budget: ~300 lines (soft cap)

### 27.1 Mission

Make `claude-supervisor.sh` reliable, debuggable, and self-documenting. It supervises claude worker panes.

### 27.2 Current state

- `scripts/codex-fleet/claude-supervisor.sh` exists and is invoked via the fleet bringup flow or daemon supervisor.
- Behaviour is documented inline via comments; no dedicated SPEC entry.
- Logging is ad-hoc; output goes to tmux pane stdout/stderr.
- Failure modes typically surface as silent exits or noisy retries.

### 27.3 Pain points

1. No structured log format; difficult to ingest into a metrics pipeline.
2. No --help output documenting flags and env vars.
3. Exit codes are not standardised across scripts.
4. Limited dry-run support; experimentation requires real fleet state.

### 27.4 Improvement protocols

#### 27.4.1 Add `--help` and `--version` to claude-supervisor.sh

- state: SHIPPED
- lane: scripts lane

**Problem.** Discoverability is poor; flags are guessed from source.

**Hypothesis.** A short help message + version banner accelerates onboarding and CI introspection.

**Proposal.** Wrap entry-point with a tiny `usage()` function; version pulled from a constants file.

**Implementation steps.**

1. Refactor script to recognise --help/--version.
1. Add scripts/codex-fleet/lib/version.sh providing FLEET_VERSION.
1. Add a smoke test asserting --help exits 0 with non-empty output.

**Verification.** `bash scripts/codex-fleet/claude-supervisor.sh --help` prints usage.

**Acceptance criteria.**

- --help and --version supported.
- Smoke test added.

**Rollback.** Revert to no usage banner.

**Risks.**

- Slight LOC overhead per script.

**Metrics.**

- # scripts with --help.
- Doc-coverage trend.

**References.**

- `scripts/codex-fleet/claude-supervisor.sh`

#### 27.4.2 Structured logging in claude-supervisor.sh

- state: PROPOSED
- lane: scripts lane

**Problem.** Plain echoes are hard to parse downstream.

**Hypothesis.** Emit `key=value`-style structured lines so the metrics-viewer crate can ingest them.

**Proposal.** Adopt a `log_kv` helper from `lib/log.sh` that emits ISO-8601 timestamp + level + key/value pairs.

**Implementation steps.**

1. Implement `lib/log.sh`.
1. Refactor critical echoes to log_kv calls.
1. Document the format in docs/future/PROTOCOL.md observability section.

**Verification.** Pipe a run of claude-supervisor.sh into `awk '/level=/' ` and observe parsable lines.

**Acceptance criteria.**

- All errors and lifecycle events emit structured lines.
- fleet-metrics-viewer parses the format.

**Rollback.** Revert to plain echo.

**Risks.**

- Verbose output; need log levels.

**Metrics.**

- % structured lines per run.

**References.**

- `scripts/codex-fleet/claude-supervisor.sh`
- `rust/fleet-metrics-viewer/`

### 27.5 Backlog (raw)

- Embed a structured banner in claude-supervisor.sh listing all subcommands.
- Promote claude-supervisor.sh to a Rust binary if footprint stabilises.
- Add fish/zsh completions for claude-supervisor.sh.
- Add `--json` output mode for claude-supervisor.sh where feasible.
- Provide a `--explain` mode that prints the decision tree.
- Document claude-supervisor.sh interactions with Colony in detail.
- Add per-run UUID for log correlation in claude-supervisor.sh.
- Add Prometheus-style metrics endpoint when running under a supervisor.
- Add chaos-test harness that injects failures into claude-supervisor.sh.
- Convert long-running portions of claude-supervisor.sh into a daemon-friendly service unit.

### 27.6 Open questions

- [ ] Should claude-supervisor.sh be allowed to mutate tmux on the host shell, or always go through a wrapper?
- [ ] What is the right escalation when claude-supervisor.sh cannot reach Colony?
- [ ] Do we keep claude-supervisor.sh bash-only or accept hybrid bash+rust?

### 27.7 Cross-cutting dependencies

- lib/common.sh (planned)
- Colony CLI
- tmux

### 27.8 Risk register

- Behavioural changes in claude-supervisor.sh may ripple through full-bringup and daemons.
- Logging or telemetry growth without rotation.

### 27.9 Migration plan

1. Phase 1: helpers in lib/.
2. Phase 2: refactor claude-supervisor.sh to use helpers.
3. Phase 3: enforce in CI via shellcheck + bats.

### 27.10 Out of scope

- Replacing bash with a different orchestrator wholesale.

---

## 28. Bash Layer: fleet-tick.sh

- slug: `fleet-tick`
- captain: unassigned
- budget: ~300 lines (soft cap)

### 28.1 Mission

Make `fleet-tick.sh` reliable, debuggable, and self-documenting. It advances tick-driven state.

### 28.2 Current state

- `scripts/codex-fleet/fleet-tick.sh` exists and is invoked via the fleet bringup flow or daemon supervisor.
- Behaviour is documented inline via comments; no dedicated SPEC entry.
- Logging is ad-hoc; output goes to tmux pane stdout/stderr.
- Failure modes typically surface as silent exits or noisy retries.

### 28.3 Pain points

1. No structured log format; difficult to ingest into a metrics pipeline.
2. No --help output documenting flags and env vars.
3. Exit codes are not standardised across scripts.
4. Limited dry-run support; experimentation requires real fleet state.

### 28.4 Improvement protocols

#### 28.4.1 Add `--help` and `--version` to fleet-tick.sh

- state: PROPOSED
- lane: scripts lane

**Problem.** Discoverability is poor; flags are guessed from source.

**Hypothesis.** A short help message + version banner accelerates onboarding and CI introspection.

**Proposal.** Wrap entry-point with a tiny `usage()` function; version pulled from a constants file.

**Implementation steps.**

1. Refactor script to recognise --help/--version.
1. Add scripts/codex-fleet/lib/version.sh providing FLEET_VERSION.
1. Add a smoke test asserting --help exits 0 with non-empty output.

**Verification.** `bash scripts/codex-fleet/fleet-tick.sh --help` prints usage.

**Acceptance criteria.**

- --help and --version supported.
- Smoke test added.

**Rollback.** Revert to no usage banner.

**Risks.**

- Slight LOC overhead per script.

**Metrics.**

- # scripts with --help.
- Doc-coverage trend.

**References.**

- `scripts/codex-fleet/fleet-tick.sh`

#### 28.4.2 Structured logging in fleet-tick.sh

- state: PROPOSED
- lane: scripts lane

**Problem.** Plain echoes are hard to parse downstream.

**Hypothesis.** Emit `key=value`-style structured lines so the metrics-viewer crate can ingest them.

**Proposal.** Adopt a `log_kv` helper from `lib/log.sh` that emits ISO-8601 timestamp + level + key/value pairs.

**Implementation steps.**

1. Implement `lib/log.sh`.
1. Refactor critical echoes to log_kv calls.
1. Document the format in docs/future/PROTOCOL.md observability section.

**Verification.** Pipe a run of fleet-tick.sh into `awk '/level=/' ` and observe parsable lines.

**Acceptance criteria.**

- All errors and lifecycle events emit structured lines.
- fleet-metrics-viewer parses the format.

**Rollback.** Revert to plain echo.

**Risks.**

- Verbose output; need log levels.

**Metrics.**

- % structured lines per run.

**References.**

- `scripts/codex-fleet/fleet-tick.sh`
- `rust/fleet-metrics-viewer/`

### 28.5 Backlog (raw)

- Embed a structured banner in fleet-tick.sh listing all subcommands.
- Promote fleet-tick.sh to a Rust binary if footprint stabilises.
- Add fish/zsh completions for fleet-tick.sh.
- Add `--json` output mode for fleet-tick.sh where feasible.
- Provide a `--explain` mode that prints the decision tree.
- Document fleet-tick.sh interactions with Colony in detail.
- Add per-run UUID for log correlation in fleet-tick.sh.
- Add Prometheus-style metrics endpoint when running under a supervisor.
- Add chaos-test harness that injects failures into fleet-tick.sh.
- Convert long-running portions of fleet-tick.sh into a daemon-friendly service unit.

### 28.6 Open questions

- [ ] Should fleet-tick.sh be allowed to mutate tmux on the host shell, or always go through a wrapper?
- [ ] What is the right escalation when fleet-tick.sh cannot reach Colony?
- [ ] Do we keep fleet-tick.sh bash-only or accept hybrid bash+rust?

### 28.7 Cross-cutting dependencies

- lib/common.sh (planned)
- Colony CLI
- tmux

### 28.8 Risk register

- Behavioural changes in fleet-tick.sh may ripple through full-bringup and daemons.
- Logging or telemetry growth without rotation.

### 28.9 Migration plan

1. Phase 1: helpers in lib/.
2. Phase 2: refactor fleet-tick.sh to use helpers.
3. Phase 3: enforce in CI via shellcheck + bats.

### 28.10 Out of scope

- Replacing bash with a different orchestrator wholesale.

---

## 29. Bash Layer: fleet-tick-daemon.sh

- slug: `fleet-tick-daemon`
- captain: unassigned
- budget: ~300 lines (soft cap)

### 29.1 Mission

Make `fleet-tick-daemon.sh` reliable, debuggable, and self-documenting. It runs the tick loop continuously.

### 29.2 Current state

- `scripts/codex-fleet/fleet-tick-daemon.sh` exists and is invoked via the fleet bringup flow or daemon supervisor.
- Behaviour is documented inline via comments; no dedicated SPEC entry.
- Logging is ad-hoc; output goes to tmux pane stdout/stderr.
- Failure modes typically surface as silent exits or noisy retries.

### 29.3 Pain points

1. No structured log format; difficult to ingest into a metrics pipeline.
2. No --help output documenting flags and env vars.
3. Exit codes are not standardised across scripts.
4. Limited dry-run support; experimentation requires real fleet state.

### 29.4 Improvement protocols

#### 29.4.1 Add `--help` and `--version` to fleet-tick-daemon.sh

- state: PROPOSED
- lane: scripts lane

**Problem.** Discoverability is poor; flags are guessed from source.

**Hypothesis.** A short help message + version banner accelerates onboarding and CI introspection.

**Proposal.** Wrap entry-point with a tiny `usage()` function; version pulled from a constants file.

**Implementation steps.**

1. Refactor script to recognise --help/--version.
1. Add scripts/codex-fleet/lib/version.sh providing FLEET_VERSION.
1. Add a smoke test asserting --help exits 0 with non-empty output.

**Verification.** `bash scripts/codex-fleet/fleet-tick-daemon.sh --help` prints usage.

**Acceptance criteria.**

- --help and --version supported.
- Smoke test added.

**Rollback.** Revert to no usage banner.

**Risks.**

- Slight LOC overhead per script.

**Metrics.**

- # scripts with --help.
- Doc-coverage trend.

**References.**

- `scripts/codex-fleet/fleet-tick-daemon.sh`

#### 29.4.2 Structured logging in fleet-tick-daemon.sh

- state: PROPOSED
- lane: scripts lane

**Problem.** Plain echoes are hard to parse downstream.

**Hypothesis.** Emit `key=value`-style structured lines so the metrics-viewer crate can ingest them.

**Proposal.** Adopt a `log_kv` helper from `lib/log.sh` that emits ISO-8601 timestamp + level + key/value pairs.

**Implementation steps.**

1. Implement `lib/log.sh`.
1. Refactor critical echoes to log_kv calls.
1. Document the format in docs/future/PROTOCOL.md observability section.

**Verification.** Pipe a run of fleet-tick-daemon.sh into `awk '/level=/' ` and observe parsable lines.

**Acceptance criteria.**

- All errors and lifecycle events emit structured lines.
- fleet-metrics-viewer parses the format.

**Rollback.** Revert to plain echo.

**Risks.**

- Verbose output; need log levels.

**Metrics.**

- % structured lines per run.

**References.**

- `scripts/codex-fleet/fleet-tick-daemon.sh`
- `rust/fleet-metrics-viewer/`

### 29.5 Backlog (raw)

- Embed a structured banner in fleet-tick-daemon.sh listing all subcommands.
- Promote fleet-tick-daemon.sh to a Rust binary if footprint stabilises.
- Add fish/zsh completions for fleet-tick-daemon.sh.
- Add `--json` output mode for fleet-tick-daemon.sh where feasible.
- Provide a `--explain` mode that prints the decision tree.
- Document fleet-tick-daemon.sh interactions with Colony in detail.
- Add per-run UUID for log correlation in fleet-tick-daemon.sh.
- Add Prometheus-style metrics endpoint when running under a supervisor.
- Add chaos-test harness that injects failures into fleet-tick-daemon.sh.
- Convert long-running portions of fleet-tick-daemon.sh into a daemon-friendly service unit.

### 29.6 Open questions

- [ ] Should fleet-tick-daemon.sh be allowed to mutate tmux on the host shell, or always go through a wrapper?
- [ ] What is the right escalation when fleet-tick-daemon.sh cannot reach Colony?
- [ ] Do we keep fleet-tick-daemon.sh bash-only or accept hybrid bash+rust?

### 29.7 Cross-cutting dependencies

- lib/common.sh (planned)
- Colony CLI
- tmux

### 29.8 Risk register

- Behavioural changes in fleet-tick-daemon.sh may ripple through full-bringup and daemons.
- Logging or telemetry growth without rotation.

### 29.9 Migration plan

1. Phase 1: helpers in lib/.
2. Phase 2: refactor fleet-tick-daemon.sh to use helpers.
3. Phase 3: enforce in CI via shellcheck + bats.

### 29.10 Out of scope

- Replacing bash with a different orchestrator wholesale.

---

## 30. Bash Layer: fleet-state-anim.sh

- slug: `fleet-state-anim`
- captain: unassigned
- budget: ~300 lines (soft cap)

### 30.1 Mission

Make `fleet-state-anim.sh` reliable, debuggable, and self-documenting. It animates fleet state transitions.

### 30.2 Current state

- `scripts/codex-fleet/fleet-state-anim.sh` exists and is invoked via the fleet bringup flow or daemon supervisor.
- Behaviour is documented inline via comments; no dedicated SPEC entry.
- Logging is ad-hoc; output goes to tmux pane stdout/stderr.
- Failure modes typically surface as silent exits or noisy retries.

### 30.3 Pain points

1. No structured log format; difficult to ingest into a metrics pipeline.
2. No --help output documenting flags and env vars.
3. Exit codes are not standardised across scripts.
4. Limited dry-run support; experimentation requires real fleet state.

### 30.4 Improvement protocols

#### 30.4.1 Add `--help` and `--version` to fleet-state-anim.sh

- state: PROPOSED
- lane: scripts lane

**Problem.** Discoverability is poor; flags are guessed from source.

**Hypothesis.** A short help message + version banner accelerates onboarding and CI introspection.

**Proposal.** Wrap entry-point with a tiny `usage()` function; version pulled from a constants file.

**Implementation steps.**

1. Refactor script to recognise --help/--version.
1. Add scripts/codex-fleet/lib/version.sh providing FLEET_VERSION.
1. Add a smoke test asserting --help exits 0 with non-empty output.

**Verification.** `bash scripts/codex-fleet/fleet-state-anim.sh --help` prints usage.

**Acceptance criteria.**

- --help and --version supported.
- Smoke test added.

**Rollback.** Revert to no usage banner.

**Risks.**

- Slight LOC overhead per script.

**Metrics.**

- # scripts with --help.
- Doc-coverage trend.

**References.**

- `scripts/codex-fleet/fleet-state-anim.sh`

#### 30.4.2 Structured logging in fleet-state-anim.sh

- state: PROPOSED
- lane: scripts lane

**Problem.** Plain echoes are hard to parse downstream.

**Hypothesis.** Emit `key=value`-style structured lines so the metrics-viewer crate can ingest them.

**Proposal.** Adopt a `log_kv` helper from `lib/log.sh` that emits ISO-8601 timestamp + level + key/value pairs.

**Implementation steps.**

1. Implement `lib/log.sh`.
1. Refactor critical echoes to log_kv calls.
1. Document the format in docs/future/PROTOCOL.md observability section.

**Verification.** Pipe a run of fleet-state-anim.sh into `awk '/level=/' ` and observe parsable lines.

**Acceptance criteria.**

- All errors and lifecycle events emit structured lines.
- fleet-metrics-viewer parses the format.

**Rollback.** Revert to plain echo.

**Risks.**

- Verbose output; need log levels.

**Metrics.**

- % structured lines per run.

**References.**

- `scripts/codex-fleet/fleet-state-anim.sh`
- `rust/fleet-metrics-viewer/`

### 30.5 Backlog (raw)

- Embed a structured banner in fleet-state-anim.sh listing all subcommands.
- Promote fleet-state-anim.sh to a Rust binary if footprint stabilises.
- Add fish/zsh completions for fleet-state-anim.sh.
- Add `--json` output mode for fleet-state-anim.sh where feasible.
- Provide a `--explain` mode that prints the decision tree.
- Document fleet-state-anim.sh interactions with Colony in detail.
- Add per-run UUID for log correlation in fleet-state-anim.sh.
- Add Prometheus-style metrics endpoint when running under a supervisor.
- Add chaos-test harness that injects failures into fleet-state-anim.sh.
- Convert long-running portions of fleet-state-anim.sh into a daemon-friendly service unit.

### 30.6 Open questions

- [ ] Should fleet-state-anim.sh be allowed to mutate tmux on the host shell, or always go through a wrapper?
- [ ] What is the right escalation when fleet-state-anim.sh cannot reach Colony?
- [ ] Do we keep fleet-state-anim.sh bash-only or accept hybrid bash+rust?

### 30.7 Cross-cutting dependencies

- lib/common.sh (planned)
- Colony CLI
- tmux

### 30.8 Risk register

- Behavioural changes in fleet-state-anim.sh may ripple through full-bringup and daemons.
- Logging or telemetry growth without rotation.

### 30.9 Migration plan

1. Phase 1: helpers in lib/.
2. Phase 2: refactor fleet-state-anim.sh to use helpers.
3. Phase 3: enforce in CI via shellcheck + bats.

### 30.10 Out of scope

- Replacing bash with a different orchestrator wholesale.

---

## 31. Bash Layer: plan-anim.sh

- slug: `plan-anim`
- captain: unassigned
- budget: ~300 lines (soft cap)

### 31.1 Mission

Make `plan-anim.sh` reliable, debuggable, and self-documenting. It animates plan progression.

### 31.2 Current state

- `scripts/codex-fleet/plan-anim.sh` exists and is invoked via the fleet bringup flow or daemon supervisor.
- Behaviour is documented inline via comments; no dedicated SPEC entry.
- Logging is ad-hoc; output goes to tmux pane stdout/stderr.
- Failure modes typically surface as silent exits or noisy retries.

### 31.3 Pain points

1. No structured log format; difficult to ingest into a metrics pipeline.
2. No --help output documenting flags and env vars.
3. Exit codes are not standardised across scripts.
4. Limited dry-run support; experimentation requires real fleet state.

### 31.4 Improvement protocols

#### 31.4.1 Add `--help` and `--version` to plan-anim.sh

- state: PROPOSED
- lane: scripts lane

**Problem.** Discoverability is poor; flags are guessed from source.

**Hypothesis.** A short help message + version banner accelerates onboarding and CI introspection.

**Proposal.** Wrap entry-point with a tiny `usage()` function; version pulled from a constants file.

**Implementation steps.**

1. Refactor script to recognise --help/--version.
1. Add scripts/codex-fleet/lib/version.sh providing FLEET_VERSION.
1. Add a smoke test asserting --help exits 0 with non-empty output.

**Verification.** `bash scripts/codex-fleet/plan-anim.sh --help` prints usage.

**Acceptance criteria.**

- --help and --version supported.
- Smoke test added.

**Rollback.** Revert to no usage banner.

**Risks.**

- Slight LOC overhead per script.

**Metrics.**

- # scripts with --help.
- Doc-coverage trend.

**References.**

- `scripts/codex-fleet/plan-anim.sh`

#### 31.4.2 Structured logging in plan-anim.sh

- state: PROPOSED
- lane: scripts lane

**Problem.** Plain echoes are hard to parse downstream.

**Hypothesis.** Emit `key=value`-style structured lines so the metrics-viewer crate can ingest them.

**Proposal.** Adopt a `log_kv` helper from `lib/log.sh` that emits ISO-8601 timestamp + level + key/value pairs.

**Implementation steps.**

1. Implement `lib/log.sh`.
1. Refactor critical echoes to log_kv calls.
1. Document the format in docs/future/PROTOCOL.md observability section.

**Verification.** Pipe a run of plan-anim.sh into `awk '/level=/' ` and observe parsable lines.

**Acceptance criteria.**

- All errors and lifecycle events emit structured lines.
- fleet-metrics-viewer parses the format.

**Rollback.** Revert to plain echo.

**Risks.**

- Verbose output; need log levels.

**Metrics.**

- % structured lines per run.

**References.**

- `scripts/codex-fleet/plan-anim.sh`
- `rust/fleet-metrics-viewer/`

### 31.5 Backlog (raw)

- Embed a structured banner in plan-anim.sh listing all subcommands.
- Promote plan-anim.sh to a Rust binary if footprint stabilises.
- Add fish/zsh completions for plan-anim.sh.
- Add `--json` output mode for plan-anim.sh where feasible.
- Provide a `--explain` mode that prints the decision tree.
- Document plan-anim.sh interactions with Colony in detail.
- Add per-run UUID for log correlation in plan-anim.sh.
- Add Prometheus-style metrics endpoint when running under a supervisor.
- Add chaos-test harness that injects failures into plan-anim.sh.
- Convert long-running portions of plan-anim.sh into a daemon-friendly service unit.

### 31.6 Open questions

- [ ] Should plan-anim.sh be allowed to mutate tmux on the host shell, or always go through a wrapper?
- [ ] What is the right escalation when plan-anim.sh cannot reach Colony?
- [ ] Do we keep plan-anim.sh bash-only or accept hybrid bash+rust?

### 31.7 Cross-cutting dependencies

- lib/common.sh (planned)
- Colony CLI
- tmux

### 31.8 Risk register

- Behavioural changes in plan-anim.sh may ripple through full-bringup and daemons.
- Logging or telemetry growth without rotation.

### 31.9 Migration plan

1. Phase 1: helpers in lib/.
2. Phase 2: refactor plan-anim.sh to use helpers.
3. Phase 3: enforce in CI via shellcheck + bats.

### 31.10 Out of scope

- Replacing bash with a different orchestrator wholesale.

---

## 32. Bash Layer: plan-tree-anim.sh

- slug: `plan-tree-anim`
- captain: unassigned
- budget: ~300 lines (soft cap)

### 32.1 Mission

Make `plan-tree-anim.sh` reliable, debuggable, and self-documenting. It animates the plan tree view.

### 32.2 Current state

- `scripts/codex-fleet/plan-tree-anim.sh` exists and is invoked via the fleet bringup flow or daemon supervisor.
- Behaviour is documented inline via comments; no dedicated SPEC entry.
- Logging is ad-hoc; output goes to tmux pane stdout/stderr.
- Failure modes typically surface as silent exits or noisy retries.

### 32.3 Pain points

1. No structured log format; difficult to ingest into a metrics pipeline.
2. No --help output documenting flags and env vars.
3. Exit codes are not standardised across scripts.
4. Limited dry-run support; experimentation requires real fleet state.

### 32.4 Improvement protocols

#### 32.4.1 Add `--help` and `--version` to plan-tree-anim.sh

- state: PROPOSED
- lane: scripts lane

**Problem.** Discoverability is poor; flags are guessed from source.

**Hypothesis.** A short help message + version banner accelerates onboarding and CI introspection.

**Proposal.** Wrap entry-point with a tiny `usage()` function; version pulled from a constants file.

**Implementation steps.**

1. Refactor script to recognise --help/--version.
1. Add scripts/codex-fleet/lib/version.sh providing FLEET_VERSION.
1. Add a smoke test asserting --help exits 0 with non-empty output.

**Verification.** `bash scripts/codex-fleet/plan-tree-anim.sh --help` prints usage.

**Acceptance criteria.**

- --help and --version supported.
- Smoke test added.

**Rollback.** Revert to no usage banner.

**Risks.**

- Slight LOC overhead per script.

**Metrics.**

- # scripts with --help.
- Doc-coverage trend.

**References.**

- `scripts/codex-fleet/plan-tree-anim.sh`

#### 32.4.2 Structured logging in plan-tree-anim.sh

- state: PROPOSED
- lane: scripts lane

**Problem.** Plain echoes are hard to parse downstream.

**Hypothesis.** Emit `key=value`-style structured lines so the metrics-viewer crate can ingest them.

**Proposal.** Adopt a `log_kv` helper from `lib/log.sh` that emits ISO-8601 timestamp + level + key/value pairs.

**Implementation steps.**

1. Implement `lib/log.sh`.
1. Refactor critical echoes to log_kv calls.
1. Document the format in docs/future/PROTOCOL.md observability section.

**Verification.** Pipe a run of plan-tree-anim.sh into `awk '/level=/' ` and observe parsable lines.

**Acceptance criteria.**

- All errors and lifecycle events emit structured lines.
- fleet-metrics-viewer parses the format.

**Rollback.** Revert to plain echo.

**Risks.**

- Verbose output; need log levels.

**Metrics.**

- % structured lines per run.

**References.**

- `scripts/codex-fleet/plan-tree-anim.sh`
- `rust/fleet-metrics-viewer/`

### 32.5 Backlog (raw)

- Embed a structured banner in plan-tree-anim.sh listing all subcommands.
- Promote plan-tree-anim.sh to a Rust binary if footprint stabilises.
- Add fish/zsh completions for plan-tree-anim.sh.
- Add `--json` output mode for plan-tree-anim.sh where feasible.
- Provide a `--explain` mode that prints the decision tree.
- Document plan-tree-anim.sh interactions with Colony in detail.
- Add per-run UUID for log correlation in plan-tree-anim.sh.
- Add Prometheus-style metrics endpoint when running under a supervisor.
- Add chaos-test harness that injects failures into plan-tree-anim.sh.
- Convert long-running portions of plan-tree-anim.sh into a daemon-friendly service unit.

### 32.6 Open questions

- [ ] Should plan-tree-anim.sh be allowed to mutate tmux on the host shell, or always go through a wrapper?
- [ ] What is the right escalation when plan-tree-anim.sh cannot reach Colony?
- [ ] Do we keep plan-tree-anim.sh bash-only or accept hybrid bash+rust?

### 32.7 Cross-cutting dependencies

- lib/common.sh (planned)
- Colony CLI
- tmux

### 32.8 Risk register

- Behavioural changes in plan-tree-anim.sh may ripple through full-bringup and daemons.
- Logging or telemetry growth without rotation.

### 32.9 Migration plan

1. Phase 1: helpers in lib/.
2. Phase 2: refactor plan-tree-anim.sh to use helpers.
3. Phase 3: enforce in CI via shellcheck + bats.

### 32.10 Out of scope

- Replacing bash with a different orchestrator wholesale.

---

## 33. Bash Layer: plan-tree-pin.sh

- slug: `plan-tree-pin`
- captain: unassigned
- budget: ~300 lines (soft cap)

### 33.1 Mission

Make `plan-tree-pin.sh` reliable, debuggable, and self-documenting. It pins a plan tree view to a pane.

### 33.2 Current state

- `scripts/codex-fleet/plan-tree-pin.sh` exists and is invoked via the fleet bringup flow or daemon supervisor.
- Behaviour is documented inline via comments; no dedicated SPEC entry.
- Logging is ad-hoc; output goes to tmux pane stdout/stderr.
- Failure modes typically surface as silent exits or noisy retries.

### 33.3 Pain points

1. No structured log format; difficult to ingest into a metrics pipeline.
2. No --help output documenting flags and env vars.
3. Exit codes are not standardised across scripts.
4. Limited dry-run support; experimentation requires real fleet state.

### 33.4 Improvement protocols

#### 33.4.1 Add `--help` and `--version` to plan-tree-pin.sh

- state: SHIPPED
- lane: scripts lane

**Problem.** Discoverability is poor; flags are guessed from source.

**Hypothesis.** A short help message + version banner accelerates onboarding and CI introspection.

**Proposal.** Wrap entry-point with a tiny `usage()` function; version pulled from a constants file.

**Implementation steps.**

1. Refactor script to recognise --help/--version.
1. Add scripts/codex-fleet/lib/version.sh providing FLEET_VERSION.
1. Add a smoke test asserting --help exits 0 with non-empty output.

**Verification.** `bash scripts/codex-fleet/plan-tree-pin.sh --help` prints usage.

**Acceptance criteria.**

- --help and --version supported.
- Smoke test added.

**Rollback.** Revert to no usage banner.

**Risks.**

- Slight LOC overhead per script.

**Metrics.**

- # scripts with --help.
- Doc-coverage trend.

**References.**

- `scripts/codex-fleet/plan-tree-pin.sh`

#### 33.4.2 Structured logging in plan-tree-pin.sh

- state: PROPOSED
- lane: scripts lane

**Problem.** Plain echoes are hard to parse downstream.

**Hypothesis.** Emit `key=value`-style structured lines so the metrics-viewer crate can ingest them.

**Proposal.** Adopt a `log_kv` helper from `lib/log.sh` that emits ISO-8601 timestamp + level + key/value pairs.

**Implementation steps.**

1. Implement `lib/log.sh`.
1. Refactor critical echoes to log_kv calls.
1. Document the format in docs/future/PROTOCOL.md observability section.

**Verification.** Pipe a run of plan-tree-pin.sh into `awk '/level=/' ` and observe parsable lines.

**Acceptance criteria.**

- All errors and lifecycle events emit structured lines.
- fleet-metrics-viewer parses the format.

**Rollback.** Revert to plain echo.

**Risks.**

- Verbose output; need log levels.

**Metrics.**

- % structured lines per run.

**References.**

- `scripts/codex-fleet/plan-tree-pin.sh`
- `rust/fleet-metrics-viewer/`

### 33.5 Backlog (raw)

- Embed a structured banner in plan-tree-pin.sh listing all subcommands.
- Promote plan-tree-pin.sh to a Rust binary if footprint stabilises.
- Add fish/zsh completions for plan-tree-pin.sh.
- Add `--json` output mode for plan-tree-pin.sh where feasible.
- Provide a `--explain` mode that prints the decision tree.
- Document plan-tree-pin.sh interactions with Colony in detail.
- Add per-run UUID for log correlation in plan-tree-pin.sh.
- Add Prometheus-style metrics endpoint when running under a supervisor.
- Add chaos-test harness that injects failures into plan-tree-pin.sh.
- Convert long-running portions of plan-tree-pin.sh into a daemon-friendly service unit.

### 33.6 Open questions

- [ ] Should plan-tree-pin.sh be allowed to mutate tmux on the host shell, or always go through a wrapper?
- [ ] What is the right escalation when plan-tree-pin.sh cannot reach Colony?
- [ ] Do we keep plan-tree-pin.sh bash-only or accept hybrid bash+rust?

### 33.7 Cross-cutting dependencies

- lib/common.sh (planned)
- Colony CLI
- tmux

### 33.8 Risk register

- Behavioural changes in plan-tree-pin.sh may ripple through full-bringup and daemons.
- Logging or telemetry growth without rotation.

### 33.9 Migration plan

1. Phase 1: helpers in lib/.
2. Phase 2: refactor plan-tree-pin.sh to use helpers.
3. Phase 3: enforce in CI via shellcheck + bats.

### 33.10 Out of scope

- Replacing bash with a different orchestrator wholesale.

---

## 34. Bash Layer: review-anim.sh

- slug: `review-anim`
- captain: unassigned
- budget: ~300 lines (soft cap)

### 34.1 Mission

Make `review-anim.sh` reliable, debuggable, and self-documenting. It animates review pane status.

### 34.2 Current state

- `scripts/codex-fleet/review-anim.sh` exists and is invoked via the fleet bringup flow or daemon supervisor.
- Behaviour is documented inline via comments; no dedicated SPEC entry.
- Logging is ad-hoc; output goes to tmux pane stdout/stderr.
- Failure modes typically surface as silent exits or noisy retries.

### 34.3 Pain points

1. No structured log format; difficult to ingest into a metrics pipeline.
2. No --help output documenting flags and env vars.
3. Exit codes are not standardised across scripts.
4. Limited dry-run support; experimentation requires real fleet state.

### 34.4 Improvement protocols

#### 34.4.1 Add `--help` and `--version` to review-anim.sh

- state: PROPOSED
- lane: scripts lane

**Problem.** Discoverability is poor; flags are guessed from source.

**Hypothesis.** A short help message + version banner accelerates onboarding and CI introspection.

**Proposal.** Wrap entry-point with a tiny `usage()` function; version pulled from a constants file.

**Implementation steps.**

1. Refactor script to recognise --help/--version.
1. Add scripts/codex-fleet/lib/version.sh providing FLEET_VERSION.
1. Add a smoke test asserting --help exits 0 with non-empty output.

**Verification.** `bash scripts/codex-fleet/review-anim.sh --help` prints usage.

**Acceptance criteria.**

- --help and --version supported.
- Smoke test added.

**Rollback.** Revert to no usage banner.

**Risks.**

- Slight LOC overhead per script.

**Metrics.**

- # scripts with --help.
- Doc-coverage trend.

**References.**

- `scripts/codex-fleet/review-anim.sh`

#### 34.4.2 Structured logging in review-anim.sh

- state: PROPOSED
- lane: scripts lane

**Problem.** Plain echoes are hard to parse downstream.

**Hypothesis.** Emit `key=value`-style structured lines so the metrics-viewer crate can ingest them.

**Proposal.** Adopt a `log_kv` helper from `lib/log.sh` that emits ISO-8601 timestamp + level + key/value pairs.

**Implementation steps.**

1. Implement `lib/log.sh`.
1. Refactor critical echoes to log_kv calls.
1. Document the format in docs/future/PROTOCOL.md observability section.

**Verification.** Pipe a run of review-anim.sh into `awk '/level=/' ` and observe parsable lines.

**Acceptance criteria.**

- All errors and lifecycle events emit structured lines.
- fleet-metrics-viewer parses the format.

**Rollback.** Revert to plain echo.

**Risks.**

- Verbose output; need log levels.

**Metrics.**

- % structured lines per run.

**References.**

- `scripts/codex-fleet/review-anim.sh`
- `rust/fleet-metrics-viewer/`

### 34.5 Backlog (raw)

- Embed a structured banner in review-anim.sh listing all subcommands.
- Promote review-anim.sh to a Rust binary if footprint stabilises.
- Add fish/zsh completions for review-anim.sh.
- Add `--json` output mode for review-anim.sh where feasible.
- Provide a `--explain` mode that prints the decision tree.
- Document review-anim.sh interactions with Colony in detail.
- Add per-run UUID for log correlation in review-anim.sh.
- Add Prometheus-style metrics endpoint when running under a supervisor.
- Add chaos-test harness that injects failures into review-anim.sh.
- Convert long-running portions of review-anim.sh into a daemon-friendly service unit.

### 34.6 Open questions

- [ ] Should review-anim.sh be allowed to mutate tmux on the host shell, or always go through a wrapper?
- [ ] What is the right escalation when review-anim.sh cannot reach Colony?
- [ ] Do we keep review-anim.sh bash-only or accept hybrid bash+rust?

### 34.7 Cross-cutting dependencies

- lib/common.sh (planned)
- Colony CLI
- tmux

### 34.8 Risk register

- Behavioural changes in review-anim.sh may ripple through full-bringup and daemons.
- Logging or telemetry growth without rotation.

### 34.9 Migration plan

1. Phase 1: helpers in lib/.
2. Phase 2: refactor review-anim.sh to use helpers.
3. Phase 3: enforce in CI via shellcheck + bats.

### 34.10 Out of scope

- Replacing bash with a different orchestrator wholesale.

---

## 35. Bash Layer: waves-anim.sh

- slug: `waves-anim`
- captain: unassigned
- budget: ~300 lines (soft cap)

### 35.1 Mission

Make `waves-anim.sh` reliable, debuggable, and self-documenting. It animates wave progression.

### 35.2 Current state

- `scripts/codex-fleet/waves-anim.sh` exists and is invoked via the fleet bringup flow or daemon supervisor.
- Behaviour is documented inline via comments; no dedicated SPEC entry.
- Logging is ad-hoc; output goes to tmux pane stdout/stderr.
- Failure modes typically surface as silent exits or noisy retries.

### 35.3 Pain points

1. No structured log format; difficult to ingest into a metrics pipeline.
2. No --help output documenting flags and env vars.
3. Exit codes are not standardised across scripts.
4. Limited dry-run support; experimentation requires real fleet state.

### 35.4 Improvement protocols

#### 35.4.1 Add `--help` and `--version` to waves-anim.sh

- state: PROPOSED
- lane: scripts lane

**Problem.** Discoverability is poor; flags are guessed from source.

**Hypothesis.** A short help message + version banner accelerates onboarding and CI introspection.

**Proposal.** Wrap entry-point with a tiny `usage()` function; version pulled from a constants file.

**Implementation steps.**

1. Refactor script to recognise --help/--version.
1. Add scripts/codex-fleet/lib/version.sh providing FLEET_VERSION.
1. Add a smoke test asserting --help exits 0 with non-empty output.

**Verification.** `bash scripts/codex-fleet/waves-anim.sh --help` prints usage.

**Acceptance criteria.**

- --help and --version supported.
- Smoke test added.

**Rollback.** Revert to no usage banner.

**Risks.**

- Slight LOC overhead per script.

**Metrics.**

- # scripts with --help.
- Doc-coverage trend.

**References.**

- `scripts/codex-fleet/waves-anim.sh`

#### 35.4.2 Structured logging in waves-anim.sh

- state: PROPOSED
- lane: scripts lane

**Problem.** Plain echoes are hard to parse downstream.

**Hypothesis.** Emit `key=value`-style structured lines so the metrics-viewer crate can ingest them.

**Proposal.** Adopt a `log_kv` helper from `lib/log.sh` that emits ISO-8601 timestamp + level + key/value pairs.

**Implementation steps.**

1. Implement `lib/log.sh`.
1. Refactor critical echoes to log_kv calls.
1. Document the format in docs/future/PROTOCOL.md observability section.

**Verification.** Pipe a run of waves-anim.sh into `awk '/level=/' ` and observe parsable lines.

**Acceptance criteria.**

- All errors and lifecycle events emit structured lines.
- fleet-metrics-viewer parses the format.

**Rollback.** Revert to plain echo.

**Risks.**

- Verbose output; need log levels.

**Metrics.**

- % structured lines per run.

**References.**

- `scripts/codex-fleet/waves-anim.sh`
- `rust/fleet-metrics-viewer/`

### 35.5 Backlog (raw)

- Embed a structured banner in waves-anim.sh listing all subcommands.
- Promote waves-anim.sh to a Rust binary if footprint stabilises.
- Add fish/zsh completions for waves-anim.sh.
- Add `--json` output mode for waves-anim.sh where feasible.
- Provide a `--explain` mode that prints the decision tree.
- Document waves-anim.sh interactions with Colony in detail.
- Add per-run UUID for log correlation in waves-anim.sh.
- Add Prometheus-style metrics endpoint when running under a supervisor.
- Add chaos-test harness that injects failures into waves-anim.sh.
- Convert long-running portions of waves-anim.sh into a daemon-friendly service unit.

### 35.6 Open questions

- [ ] Should waves-anim.sh be allowed to mutate tmux on the host shell, or always go through a wrapper?
- [ ] What is the right escalation when waves-anim.sh cannot reach Colony?
- [ ] Do we keep waves-anim.sh bash-only or accept hybrid bash+rust?

### 35.7 Cross-cutting dependencies

- lib/common.sh (planned)
- Colony CLI
- tmux

### 35.8 Risk register

- Behavioural changes in waves-anim.sh may ripple through full-bringup and daemons.
- Logging or telemetry growth without rotation.

### 35.9 Migration plan

1. Phase 1: helpers in lib/.
2. Phase 2: refactor waves-anim.sh to use helpers.
3. Phase 3: enforce in CI via shellcheck + bats.

### 35.10 Out of scope

- Replacing bash with a different orchestrator wholesale.

---

## 36. Bash Layer: supervisor.sh

- slug: `supervisor`
- captain: unassigned
- budget: ~300 lines (soft cap)

### 36.1 Mission

Make `supervisor.sh` reliable, debuggable, and self-documenting. It is the legacy autonomous supervisor.

### 36.2 Current state

- `scripts/codex-fleet/supervisor.sh` exists and is invoked via the fleet bringup flow or daemon supervisor.
- Behaviour is documented inline via comments; no dedicated SPEC entry.
- Logging is ad-hoc; output goes to tmux pane stdout/stderr.
- Failure modes typically surface as silent exits or noisy retries.

### 36.3 Pain points

1. No structured log format; difficult to ingest into a metrics pipeline.
2. No --help output documenting flags and env vars.
3. Exit codes are not standardised across scripts.
4. Limited dry-run support; experimentation requires real fleet state.

### 36.4 Improvement protocols

#### 36.4.1 Add `--help` and `--version` to supervisor.sh

- state: SHIPPED
- lane: scripts lane

**Problem.** Discoverability is poor; flags are guessed from source.

**Hypothesis.** A short help message + version banner accelerates onboarding and CI introspection.

**Proposal.** Wrap entry-point with a tiny `usage()` function; version pulled from a constants file.

**Implementation steps.**

1. Refactor script to recognise --help/--version.
1. Add scripts/codex-fleet/lib/version.sh providing FLEET_VERSION.
1. Add a smoke test asserting --help exits 0 with non-empty output.

**Verification.** `bash scripts/codex-fleet/supervisor.sh --help` prints usage.

**Acceptance criteria.**

- --help and --version supported.
- Smoke test added.

**Rollback.** Revert to no usage banner.

**Risks.**

- Slight LOC overhead per script.

**Metrics.**

- # scripts with --help.
- Doc-coverage trend.

**References.**

- `scripts/codex-fleet/supervisor.sh`

#### 36.4.2 Structured logging in supervisor.sh

- state: PROPOSED
- lane: scripts lane

**Problem.** Plain echoes are hard to parse downstream.

**Hypothesis.** Emit `key=value`-style structured lines so the metrics-viewer crate can ingest them.

**Proposal.** Adopt a `log_kv` helper from `lib/log.sh` that emits ISO-8601 timestamp + level + key/value pairs.

**Implementation steps.**

1. Implement `lib/log.sh`.
1. Refactor critical echoes to log_kv calls.
1. Document the format in docs/future/PROTOCOL.md observability section.

**Verification.** Pipe a run of supervisor.sh into `awk '/level=/' ` and observe parsable lines.

**Acceptance criteria.**

- All errors and lifecycle events emit structured lines.
- fleet-metrics-viewer parses the format.

**Rollback.** Revert to plain echo.

**Risks.**

- Verbose output; need log levels.

**Metrics.**

- % structured lines per run.

**References.**

- `scripts/codex-fleet/supervisor.sh`
- `rust/fleet-metrics-viewer/`

### 36.5 Backlog (raw)

- Embed a structured banner in supervisor.sh listing all subcommands.
- Promote supervisor.sh to a Rust binary if footprint stabilises.
- Add fish/zsh completions for supervisor.sh.
- Add `--json` output mode for supervisor.sh where feasible.
- Provide a `--explain` mode that prints the decision tree.
- Document supervisor.sh interactions with Colony in detail.
- Add per-run UUID for log correlation in supervisor.sh.
- Add Prometheus-style metrics endpoint when running under a supervisor.
- Add chaos-test harness that injects failures into supervisor.sh.
- Convert long-running portions of supervisor.sh into a daemon-friendly service unit.

### 36.6 Open questions

- [ ] Should supervisor.sh be allowed to mutate tmux on the host shell, or always go through a wrapper?
- [ ] What is the right escalation when supervisor.sh cannot reach Colony?
- [ ] Do we keep supervisor.sh bash-only or accept hybrid bash+rust?

### 36.7 Cross-cutting dependencies

- lib/common.sh (planned)
- Colony CLI
- tmux

### 36.8 Risk register

- Behavioural changes in supervisor.sh may ripple through full-bringup and daemons.
- Logging or telemetry growth without rotation.

### 36.9 Migration plan

1. Phase 1: helpers in lib/.
2. Phase 2: refactor supervisor.sh to use helpers.
3. Phase 3: enforce in CI via shellcheck + bats.

### 36.10 Out of scope

- Replacing bash with a different orchestrator wholesale.

---

## 37. Bash Layer: patch-codex-prompts.sh

- slug: `patch-codex-prompts`
- captain: unassigned
- budget: ~300 lines (soft cap)

### 37.1 Mission

Make `patch-codex-prompts.sh` reliable, debuggable, and self-documenting. It patches the codex prompt artifacts.

### 37.2 Current state

- `scripts/codex-fleet/patch-codex-prompts.sh` exists and is invoked via the fleet bringup flow or daemon supervisor.
- Behaviour is documented inline via comments; no dedicated SPEC entry.
- Logging is ad-hoc; output goes to tmux pane stdout/stderr.
- Failure modes typically surface as silent exits or noisy retries.

### 37.3 Pain points

1. No structured log format; difficult to ingest into a metrics pipeline.
2. No --help output documenting flags and env vars.
3. Exit codes are not standardised across scripts.
4. Limited dry-run support; experimentation requires real fleet state.

### 37.4 Improvement protocols

#### 37.4.1 Add `--help` and `--version` to patch-codex-prompts.sh

- state: SHIPPED
- lane: scripts lane

**Problem.** Discoverability is poor; flags are guessed from source.

**Hypothesis.** A short help message + version banner accelerates onboarding and CI introspection.

**Proposal.** Wrap entry-point with a tiny `usage()` function; version pulled from a constants file.

**Implementation steps.**

1. Refactor script to recognise --help/--version.
1. Add scripts/codex-fleet/lib/version.sh providing FLEET_VERSION.
1. Add a smoke test asserting --help exits 0 with non-empty output.

**Verification.** `bash scripts/codex-fleet/patch-codex-prompts.sh --help` prints usage.

**Acceptance criteria.**

- --help and --version supported.
- Smoke test added.

**Rollback.** Revert to no usage banner.

**Risks.**

- Slight LOC overhead per script.

**Metrics.**

- # scripts with --help.
- Doc-coverage trend.

**References.**

- `scripts/codex-fleet/patch-codex-prompts.sh`

#### 37.4.2 Structured logging in patch-codex-prompts.sh

- state: PROPOSED
- lane: scripts lane

**Problem.** Plain echoes are hard to parse downstream.

**Hypothesis.** Emit `key=value`-style structured lines so the metrics-viewer crate can ingest them.

**Proposal.** Adopt a `log_kv` helper from `lib/log.sh` that emits ISO-8601 timestamp + level + key/value pairs.

**Implementation steps.**

1. Implement `lib/log.sh`.
1. Refactor critical echoes to log_kv calls.
1. Document the format in docs/future/PROTOCOL.md observability section.

**Verification.** Pipe a run of patch-codex-prompts.sh into `awk '/level=/' ` and observe parsable lines.

**Acceptance criteria.**

- All errors and lifecycle events emit structured lines.
- fleet-metrics-viewer parses the format.

**Rollback.** Revert to plain echo.

**Risks.**

- Verbose output; need log levels.

**Metrics.**

- % structured lines per run.

**References.**

- `scripts/codex-fleet/patch-codex-prompts.sh`
- `rust/fleet-metrics-viewer/`

### 37.5 Backlog (raw)

- Embed a structured banner in patch-codex-prompts.sh listing all subcommands.
- Promote patch-codex-prompts.sh to a Rust binary if footprint stabilises.
- Add fish/zsh completions for patch-codex-prompts.sh.
- Add `--json` output mode for patch-codex-prompts.sh where feasible.
- Provide a `--explain` mode that prints the decision tree.
- Document patch-codex-prompts.sh interactions with Colony in detail.
- Add per-run UUID for log correlation in patch-codex-prompts.sh.
- Add Prometheus-style metrics endpoint when running under a supervisor.
- Add chaos-test harness that injects failures into patch-codex-prompts.sh.
- Convert long-running portions of patch-codex-prompts.sh into a daemon-friendly service unit.

### 37.6 Open questions

- [ ] Should patch-codex-prompts.sh be allowed to mutate tmux on the host shell, or always go through a wrapper?
- [ ] What is the right escalation when patch-codex-prompts.sh cannot reach Colony?
- [ ] Do we keep patch-codex-prompts.sh bash-only or accept hybrid bash+rust?

### 37.7 Cross-cutting dependencies

- lib/common.sh (planned)
- Colony CLI
- tmux

### 37.8 Risk register

- Behavioural changes in patch-codex-prompts.sh may ripple through full-bringup and daemons.
- Logging or telemetry growth without rotation.

### 37.9 Migration plan

1. Phase 1: helpers in lib/.
2. Phase 2: refactor patch-codex-prompts.sh to use helpers.
3. Phase 3: enforce in CI via shellcheck + bats.

### 37.10 Out of scope

- Replacing bash with a different orchestrator wholesale.

---

## 38. Bash Layer: overview-header.sh

- slug: `overview-header`
- captain: unassigned
- budget: ~300 lines (soft cap)

### 38.1 Mission

Make `overview-header.sh` reliable, debuggable, and self-documenting. It paints the overview header bar.

### 38.2 Current state

- `scripts/codex-fleet/overview-header.sh` exists and is invoked via the fleet bringup flow or daemon supervisor.
- Behaviour is documented inline via comments; no dedicated SPEC entry.
- Logging is ad-hoc; output goes to tmux pane stdout/stderr.
- Failure modes typically surface as silent exits or noisy retries.

### 38.3 Pain points

1. No structured log format; difficult to ingest into a metrics pipeline.
2. No --help output documenting flags and env vars.
3. Exit codes are not standardised across scripts.
4. Limited dry-run support; experimentation requires real fleet state.

### 38.4 Improvement protocols

#### 38.4.1 Add `--help` and `--version` to overview-header.sh

- state: PROPOSED
- lane: scripts lane

**Problem.** Discoverability is poor; flags are guessed from source.

**Hypothesis.** A short help message + version banner accelerates onboarding and CI introspection.

**Proposal.** Wrap entry-point with a tiny `usage()` function; version pulled from a constants file.

**Implementation steps.**

1. Refactor script to recognise --help/--version.
1. Add scripts/codex-fleet/lib/version.sh providing FLEET_VERSION.
1. Add a smoke test asserting --help exits 0 with non-empty output.

**Verification.** `bash scripts/codex-fleet/overview-header.sh --help` prints usage.

**Acceptance criteria.**

- --help and --version supported.
- Smoke test added.

**Rollback.** Revert to no usage banner.

**Risks.**

- Slight LOC overhead per script.

**Metrics.**

- # scripts with --help.
- Doc-coverage trend.

**References.**

- `scripts/codex-fleet/overview-header.sh`

#### 38.4.2 Structured logging in overview-header.sh

- state: PROPOSED
- lane: scripts lane

**Problem.** Plain echoes are hard to parse downstream.

**Hypothesis.** Emit `key=value`-style structured lines so the metrics-viewer crate can ingest them.

**Proposal.** Adopt a `log_kv` helper from `lib/log.sh` that emits ISO-8601 timestamp + level + key/value pairs.

**Implementation steps.**

1. Implement `lib/log.sh`.
1. Refactor critical echoes to log_kv calls.
1. Document the format in docs/future/PROTOCOL.md observability section.

**Verification.** Pipe a run of overview-header.sh into `awk '/level=/' ` and observe parsable lines.

**Acceptance criteria.**

- All errors and lifecycle events emit structured lines.
- fleet-metrics-viewer parses the format.

**Rollback.** Revert to plain echo.

**Risks.**

- Verbose output; need log levels.

**Metrics.**

- % structured lines per run.

**References.**

- `scripts/codex-fleet/overview-header.sh`
- `rust/fleet-metrics-viewer/`

### 38.5 Backlog (raw)

- Embed a structured banner in overview-header.sh listing all subcommands.
- Promote overview-header.sh to a Rust binary if footprint stabilises.
- Add fish/zsh completions for overview-header.sh.
- Add `--json` output mode for overview-header.sh where feasible.
- Provide a `--explain` mode that prints the decision tree.
- Document overview-header.sh interactions with Colony in detail.
- Add per-run UUID for log correlation in overview-header.sh.
- Add Prometheus-style metrics endpoint when running under a supervisor.
- Add chaos-test harness that injects failures into overview-header.sh.
- Convert long-running portions of overview-header.sh into a daemon-friendly service unit.

### 38.6 Open questions

- [ ] Should overview-header.sh be allowed to mutate tmux on the host shell, or always go through a wrapper?
- [ ] What is the right escalation when overview-header.sh cannot reach Colony?
- [ ] Do we keep overview-header.sh bash-only or accept hybrid bash+rust?

### 38.7 Cross-cutting dependencies

- lib/common.sh (planned)
- Colony CLI
- tmux

### 38.8 Risk register

- Behavioural changes in overview-header.sh may ripple through full-bringup and daemons.
- Logging or telemetry growth without rotation.

### 38.9 Migration plan

1. Phase 1: helpers in lib/.
2. Phase 2: refactor overview-header.sh to use helpers.
3. Phase 3: enforce in CI via shellcheck + bats.

### 38.10 Out of scope

- Replacing bash with a different orchestrator wholesale.

---

## 39. Bash Layer: down.sh

- slug: `down`
- captain: unassigned
- budget: ~300 lines (soft cap)

### 39.1 Mission

Make `down.sh` reliable, debuggable, and self-documenting. It tears down the fleet cleanly.

### 39.2 Current state

- `scripts/codex-fleet/down.sh` exists and is invoked via the fleet bringup flow or daemon supervisor.
- Behaviour is documented inline via comments; no dedicated SPEC entry.
- Logging is ad-hoc; output goes to tmux pane stdout/stderr.
- Failure modes typically surface as silent exits or noisy retries.

### 39.3 Pain points

1. No structured log format; difficult to ingest into a metrics pipeline.
2. No --help output documenting flags and env vars.
3. Exit codes are not standardised across scripts.
4. Limited dry-run support; experimentation requires real fleet state.

### 39.4 Improvement protocols

#### 39.4.1 Add `--help` and `--version` to down.sh

- state: SHIPPED
- lane: scripts lane

**Problem.** Discoverability is poor; flags are guessed from source.

**Hypothesis.** A short help message + version banner accelerates onboarding and CI introspection.

**Proposal.** Wrap entry-point with a tiny `usage()` function; version pulled from a constants file.

**Implementation steps.**

1. Refactor script to recognise --help/--version.
1. Add scripts/codex-fleet/lib/version.sh providing FLEET_VERSION.
1. Add a smoke test asserting --help exits 0 with non-empty output.

**Verification.** `bash scripts/codex-fleet/down.sh --help` prints usage.

**Acceptance criteria.**

- --help and --version supported.
- Smoke test added.

**Rollback.** Revert to no usage banner.

**Risks.**

- Slight LOC overhead per script.

**Metrics.**

- # scripts with --help.
- Doc-coverage trend.

**References.**

- `scripts/codex-fleet/down.sh`

#### 39.4.2 Structured logging in down.sh

- state: PROPOSED
- lane: scripts lane

**Problem.** Plain echoes are hard to parse downstream.

**Hypothesis.** Emit `key=value`-style structured lines so the metrics-viewer crate can ingest them.

**Proposal.** Adopt a `log_kv` helper from `lib/log.sh` that emits ISO-8601 timestamp + level + key/value pairs.

**Implementation steps.**

1. Implement `lib/log.sh`.
1. Refactor critical echoes to log_kv calls.
1. Document the format in docs/future/PROTOCOL.md observability section.

**Verification.** Pipe a run of down.sh into `awk '/level=/' ` and observe parsable lines.

**Acceptance criteria.**

- All errors and lifecycle events emit structured lines.
- fleet-metrics-viewer parses the format.

**Rollback.** Revert to plain echo.

**Risks.**

- Verbose output; need log levels.

**Metrics.**

- % structured lines per run.

**References.**

- `scripts/codex-fleet/down.sh`
- `rust/fleet-metrics-viewer/`

### 39.5 Backlog (raw)

- Embed a structured banner in down.sh listing all subcommands.
- Promote down.sh to a Rust binary if footprint stabilises.
- Add fish/zsh completions for down.sh.
- Add `--json` output mode for down.sh where feasible.
- Provide a `--explain` mode that prints the decision tree.
- Document down.sh interactions with Colony in detail.
- Add per-run UUID for log correlation in down.sh.
- Add Prometheus-style metrics endpoint when running under a supervisor.
- Add chaos-test harness that injects failures into down.sh.
- Convert long-running portions of down.sh into a daemon-friendly service unit.

### 39.6 Open questions

- [ ] Should down.sh be allowed to mutate tmux on the host shell, or always go through a wrapper?
- [ ] What is the right escalation when down.sh cannot reach Colony?
- [ ] Do we keep down.sh bash-only or accept hybrid bash+rust?

### 39.7 Cross-cutting dependencies

- lib/common.sh (planned)
- Colony CLI
- tmux

### 39.8 Risk register

- Behavioural changes in down.sh may ripple through full-bringup and daemons.
- Logging or telemetry growth without rotation.

### 39.9 Migration plan

1. Phase 1: helpers in lib/.
2. Phase 2: refactor down.sh to use helpers.
3. Phase 3: enforce in CI via shellcheck + bats.

### 39.10 Out of scope

- Replacing bash with a different orchestrator wholesale.

---

## 40. Bash Layer: up.sh

- slug: `up`
- captain: unassigned
- budget: ~300 lines (soft cap)

### 40.1 Mission

Make `up.sh` reliable, debuggable, and self-documenting. It brings up the fleet.

### 40.2 Current state

- `scripts/codex-fleet/up.sh` exists and is invoked via the fleet bringup flow or daemon supervisor.
- Behaviour is documented inline via comments; no dedicated SPEC entry.
- Logging is ad-hoc; output goes to tmux pane stdout/stderr.
- Failure modes typically surface as silent exits or noisy retries.

### 40.3 Pain points

1. No structured log format; difficult to ingest into a metrics pipeline.
2. No --help output documenting flags and env vars.
3. Exit codes are not standardised across scripts.
4. Limited dry-run support; experimentation requires real fleet state.

### 40.4 Improvement protocols

#### 40.4.1 Add `--help` and `--version` to up.sh

- state: PROPOSED
- lane: scripts lane

**Problem.** Discoverability is poor; flags are guessed from source.

**Hypothesis.** A short help message + version banner accelerates onboarding and CI introspection.

**Proposal.** Wrap entry-point with a tiny `usage()` function; version pulled from a constants file.

**Implementation steps.**

1. Refactor script to recognise --help/--version.
1. Add scripts/codex-fleet/lib/version.sh providing FLEET_VERSION.
1. Add a smoke test asserting --help exits 0 with non-empty output.

**Verification.** `bash scripts/codex-fleet/up.sh --help` prints usage.

**Acceptance criteria.**

- --help and --version supported.
- Smoke test added.

**Rollback.** Revert to no usage banner.

**Risks.**

- Slight LOC overhead per script.

**Metrics.**

- # scripts with --help.
- Doc-coverage trend.

**References.**

- `scripts/codex-fleet/up.sh`

#### 40.4.2 Structured logging in up.sh

- state: PROPOSED
- lane: scripts lane

**Problem.** Plain echoes are hard to parse downstream.

**Hypothesis.** Emit `key=value`-style structured lines so the metrics-viewer crate can ingest them.

**Proposal.** Adopt a `log_kv` helper from `lib/log.sh` that emits ISO-8601 timestamp + level + key/value pairs.

**Implementation steps.**

1. Implement `lib/log.sh`.
1. Refactor critical echoes to log_kv calls.
1. Document the format in docs/future/PROTOCOL.md observability section.

**Verification.** Pipe a run of up.sh into `awk '/level=/' ` and observe parsable lines.

**Acceptance criteria.**

- All errors and lifecycle events emit structured lines.
- fleet-metrics-viewer parses the format.

**Rollback.** Revert to plain echo.

**Risks.**

- Verbose output; need log levels.

**Metrics.**

- % structured lines per run.

**References.**

- `scripts/codex-fleet/up.sh`
- `rust/fleet-metrics-viewer/`

### 40.5 Backlog (raw)

- Embed a structured banner in up.sh listing all subcommands.
- Promote up.sh to a Rust binary if footprint stabilises.
- Add fish/zsh completions for up.sh.
- Add `--json` output mode for up.sh where feasible.
- Provide a `--explain` mode that prints the decision tree.
- Document up.sh interactions with Colony in detail.
- Add per-run UUID for log correlation in up.sh.
- Add Prometheus-style metrics endpoint when running under a supervisor.
- Add chaos-test harness that injects failures into up.sh.
- Convert long-running portions of up.sh into a daemon-friendly service unit.

### 40.6 Open questions

- [ ] Should up.sh be allowed to mutate tmux on the host shell, or always go through a wrapper?
- [ ] What is the right escalation when up.sh cannot reach Colony?
- [ ] Do we keep up.sh bash-only or accept hybrid bash+rust?

### 40.7 Cross-cutting dependencies

- lib/common.sh (planned)
- Colony CLI
- tmux

### 40.8 Risk register

- Behavioural changes in up.sh may ripple through full-bringup and daemons.
- Logging or telemetry growth without rotation.

### 40.9 Migration plan

1. Phase 1: helpers in lib/.
2. Phase 2: refactor up.sh to use helpers.
3. Phase 3: enforce in CI via shellcheck + bats.

### 40.10 Out of scope

- Replacing bash with a different orchestrator wholesale.

---

## 41. Bash Layer: add-workers.sh

- slug: `add-workers`
- captain: unassigned
- budget: ~300 lines (soft cap)

### 41.1 Mission

Make `add-workers.sh` reliable, debuggable, and self-documenting. It adds workers to a running fleet.

### 41.2 Current state

- `scripts/codex-fleet/add-workers.sh` exists and is invoked via the fleet bringup flow or daemon supervisor.
- Behaviour is documented inline via comments; no dedicated SPEC entry.
- Logging is ad-hoc; output goes to tmux pane stdout/stderr.
- Failure modes typically surface as silent exits or noisy retries.

### 41.3 Pain points

1. No structured log format; difficult to ingest into a metrics pipeline.
2. No --help output documenting flags and env vars.
3. Exit codes are not standardised across scripts.
4. Limited dry-run support; experimentation requires real fleet state.

### 41.4 Improvement protocols

#### 41.4.1 Add `--help` and `--version` to add-workers.sh

- state: SHIPPED
- lane: scripts lane

**Problem.** Discoverability is poor; flags are guessed from source.

**Hypothesis.** A short help message + version banner accelerates onboarding and CI introspection.

**Proposal.** Wrap entry-point with a tiny `usage()` function; version pulled from a constants file.

**Implementation steps.**

1. Refactor script to recognise --help/--version.
1. Add scripts/codex-fleet/lib/version.sh providing FLEET_VERSION.
1. Add a smoke test asserting --help exits 0 with non-empty output.

**Verification.** `bash scripts/codex-fleet/add-workers.sh --help` prints usage.

**Acceptance criteria.**

- --help and --version supported.
- Smoke test added.

**Rollback.** Revert to no usage banner.

**Risks.**

- Slight LOC overhead per script.

**Metrics.**

- # scripts with --help.
- Doc-coverage trend.

**References.**

- `scripts/codex-fleet/add-workers.sh`

#### 41.4.2 Structured logging in add-workers.sh

- state: PROPOSED
- lane: scripts lane

**Problem.** Plain echoes are hard to parse downstream.

**Hypothesis.** Emit `key=value`-style structured lines so the metrics-viewer crate can ingest them.

**Proposal.** Adopt a `log_kv` helper from `lib/log.sh` that emits ISO-8601 timestamp + level + key/value pairs.

**Implementation steps.**

1. Implement `lib/log.sh`.
1. Refactor critical echoes to log_kv calls.
1. Document the format in docs/future/PROTOCOL.md observability section.

**Verification.** Pipe a run of add-workers.sh into `awk '/level=/' ` and observe parsable lines.

**Acceptance criteria.**

- All errors and lifecycle events emit structured lines.
- fleet-metrics-viewer parses the format.

**Rollback.** Revert to plain echo.

**Risks.**

- Verbose output; need log levels.

**Metrics.**

- % structured lines per run.

**References.**

- `scripts/codex-fleet/add-workers.sh`
- `rust/fleet-metrics-viewer/`

### 41.5 Backlog (raw)

- Embed a structured banner in add-workers.sh listing all subcommands.
- Promote add-workers.sh to a Rust binary if footprint stabilises.
- Add fish/zsh completions for add-workers.sh.
- Add `--json` output mode for add-workers.sh where feasible.
- Provide a `--explain` mode that prints the decision tree.
- Document add-workers.sh interactions with Colony in detail.
- Add per-run UUID for log correlation in add-workers.sh.
- Add Prometheus-style metrics endpoint when running under a supervisor.
- Add chaos-test harness that injects failures into add-workers.sh.
- Convert long-running portions of add-workers.sh into a daemon-friendly service unit.

### 41.6 Open questions

- [ ] Should add-workers.sh be allowed to mutate tmux on the host shell, or always go through a wrapper?
- [ ] What is the right escalation when add-workers.sh cannot reach Colony?
- [ ] Do we keep add-workers.sh bash-only or accept hybrid bash+rust?

### 41.7 Cross-cutting dependencies

- lib/common.sh (planned)
- Colony CLI
- tmux

### 41.8 Risk register

- Behavioural changes in add-workers.sh may ripple through full-bringup and daemons.
- Logging or telemetry growth without rotation.

### 41.9 Migration plan

1. Phase 1: helpers in lib/.
2. Phase 2: refactor add-workers.sh to use helpers.
3. Phase 3: enforce in CI via shellcheck + bats.

### 41.10 Out of scope

- Replacing bash with a different orchestrator wholesale.

---

## 42. Bash Layer: codex-fleet-2.sh

- slug: `codex-fleet-2`
- captain: unassigned
- budget: ~300 lines (soft cap)

### 42.1 Mission

Make `codex-fleet-2.sh` reliable, debuggable, and self-documenting. It is an alternative fleet entrypoint variant.

### 42.2 Current state

- `scripts/codex-fleet/codex-fleet-2.sh` exists and is invoked via the fleet bringup flow or daemon supervisor.
- Behaviour is documented inline via comments; no dedicated SPEC entry.
- Logging is ad-hoc; output goes to tmux pane stdout/stderr.
- Failure modes typically surface as silent exits or noisy retries.

### 42.3 Pain points

1. No structured log format; difficult to ingest into a metrics pipeline.
2. No --help output documenting flags and env vars.
3. Exit codes are not standardised across scripts.
4. Limited dry-run support; experimentation requires real fleet state.

### 42.4 Improvement protocols

#### 42.4.1 Add `--help` and `--version` to codex-fleet-2.sh

- state: SHIPPED
- lane: scripts lane

**Problem.** Discoverability is poor; flags are guessed from source.

**Hypothesis.** A short help message + version banner accelerates onboarding and CI introspection.

**Proposal.** Wrap entry-point with a tiny `usage()` function; version pulled from a constants file.

**Implementation steps.**

1. Refactor script to recognise --help/--version.
1. Add scripts/codex-fleet/lib/version.sh providing FLEET_VERSION.
1. Add a smoke test asserting --help exits 0 with non-empty output.

**Verification.** `bash scripts/codex-fleet/codex-fleet-2.sh --help` prints usage.

**Acceptance criteria.**

- --help and --version supported.
- Smoke test added.

**Rollback.** Revert to no usage banner.

**Risks.**

- Slight LOC overhead per script.

**Metrics.**

- # scripts with --help.
- Doc-coverage trend.

**References.**

- `scripts/codex-fleet/codex-fleet-2.sh`

#### 42.4.2 Structured logging in codex-fleet-2.sh

- state: PROPOSED
- lane: scripts lane

**Problem.** Plain echoes are hard to parse downstream.

**Hypothesis.** Emit `key=value`-style structured lines so the metrics-viewer crate can ingest them.

**Proposal.** Adopt a `log_kv` helper from `lib/log.sh` that emits ISO-8601 timestamp + level + key/value pairs.

**Implementation steps.**

1. Implement `lib/log.sh`.
1. Refactor critical echoes to log_kv calls.
1. Document the format in docs/future/PROTOCOL.md observability section.

**Verification.** Pipe a run of codex-fleet-2.sh into `awk '/level=/' ` and observe parsable lines.

**Acceptance criteria.**

- All errors and lifecycle events emit structured lines.
- fleet-metrics-viewer parses the format.

**Rollback.** Revert to plain echo.

**Risks.**

- Verbose output; need log levels.

**Metrics.**

- % structured lines per run.

**References.**

- `scripts/codex-fleet/codex-fleet-2.sh`
- `rust/fleet-metrics-viewer/`

### 42.5 Backlog (raw)

- Embed a structured banner in codex-fleet-2.sh listing all subcommands.
- Promote codex-fleet-2.sh to a Rust binary if footprint stabilises.
- Add fish/zsh completions for codex-fleet-2.sh.
- Add `--json` output mode for codex-fleet-2.sh where feasible.
- Provide a `--explain` mode that prints the decision tree.
- Document codex-fleet-2.sh interactions with Colony in detail.
- Add per-run UUID for log correlation in codex-fleet-2.sh.
- Add Prometheus-style metrics endpoint when running under a supervisor.
- Add chaos-test harness that injects failures into codex-fleet-2.sh.
- Convert long-running portions of codex-fleet-2.sh into a daemon-friendly service unit.

### 42.6 Open questions

- [ ] Should codex-fleet-2.sh be allowed to mutate tmux on the host shell, or always go through a wrapper?
- [ ] What is the right escalation when codex-fleet-2.sh cannot reach Colony?
- [ ] Do we keep codex-fleet-2.sh bash-only or accept hybrid bash+rust?

### 42.7 Cross-cutting dependencies

- lib/common.sh (planned)
- Colony CLI
- tmux

### 42.8 Risk register

- Behavioural changes in codex-fleet-2.sh may ripple through full-bringup and daemons.
- Logging or telemetry growth without rotation.

### 42.9 Migration plan

1. Phase 1: helpers in lib/.
2. Phase 2: refactor codex-fleet-2.sh to use helpers.
3. Phase 3: enforce in CI via shellcheck + bats.

### 42.10 Out of scope

- Replacing bash with a different orchestrator wholesale.

---

## 43. Rust Crate: fleet-components

- slug: `rust-fleet-components`
- captain: unassigned
- budget: ~300 lines (soft cap)

### 43.1 Mission

Make `fleet-components` a stable, testable, ergonomic crate. It hosts shared UI components.

### 43.2 Current state

- `rust/fleet-components` is part of the workspace.
- Public API surface for `fleet-components` is documented inline with rustdoc.
- Tests live under src/ unit tests and/or tests/ integration directory.
- Snapshots (where applicable) live under src/snapshots/.

### 43.3 Pain points

1. Limited rustdoc top-level crate docs.
2. Patchy property-based test coverage.
3. Public types may leak internal details.
4. No published changelog per crate.

### 43.4 Improvement protocols

#### 43.4.1 Crate-level rustdoc for fleet-components

- state: PROPOSED
- lane: fleet-components maintainers

**Problem.** Top-level crate docs are thin or missing.

**Hypothesis.** Strong crate docs reduce ramp-up time for contributors.

**Proposal.** Add `//!` crate docs with: purpose, stability promise, examples, feature flags, key types.

**Implementation steps.**

1. Author crate-level docs.
1. Add doctest examples covering the most common API.
1. Wire `cargo doc --no-deps` into CI.

**Verification.** `cargo doc -p fleet-components` succeeds; html includes overview.

**Acceptance criteria.**

- Crate has >= 50 lines of `//!` docs.
- Doctests pass.

**Rollback.** Revert docs.

**Risks.**

- Doctest brittleness.

**Metrics.**

- doc-coverage %
- broken-link count

**References.**

- `rust/fleet-components/src/lib.rs`

#### 43.4.2 Public API audit for fleet-components

- state: PROPOSED
- lane: rust lane

**Problem.** Public surface may leak internals or duplicate types.

**Hypothesis.** An API audit using `cargo public-api` highlights leakage.

**Proposal.** Run cargo public-api; reduce surface; mark internal items `pub(crate)`.

**Implementation steps.**

1. Run cargo public-api locally.
1. Triage each public item.
1. Commit reductions; add CI to track diff.

**Verification.** `cargo public-api -p fleet-components` baseline committed.

**Acceptance criteria.**

- Public surface reduced or stabilised.
- Baseline tracked in repo.

**Rollback.** Restore previous visibility.

**Risks.**

- Breaking changes for downstream crates.

**Metrics.**

- public-item count delta

**References.**

- `rust/fleet-components/`

### 43.5 Backlog (raw)

- Add fuzz target for fleet-components via cargo-fuzz.
- Add WASM build matrix entry for fleet-components if applicable.
- Add miri run on weekly schedule for fleet-components.
- Add semver-check via cargo-semver-checks for fleet-components.
- Add cargo-deny config covering fleet-components dependencies.
- Split fleet-components into core + helpers if API grows.
- Adopt typestate pattern where invariants warrant it.
- Reduce monomorphization cost in fleet-components hotspots.
- Audit allocations on hot paths in fleet-components.
- Add tracing instrumentation in fleet-components with feature flag.

### 43.6 Open questions

- [ ] Should fleet-components be published to crates.io eventually?
- [ ] What is the upstream story for fleet-components once codex-fleet stabilises?
- [ ] How do we version fleet-components relative to fleet release tags?

### 43.7 Cross-cutting dependencies

- Other fleet-* crates as declared in Cargo.toml.

### 43.8 Risk register

- Breaking changes in fleet-components ripple to all consumers.
- Performance regressions in fleet-components surface only under load.

### 43.9 Migration plan

1. Phase 1: docs + clippy baseline for fleet-components.
2. Phase 2: tests + benches + MSRV for fleet-components.
3. Phase 3: per-crate CHANGELOG and semver gating for fleet-components.

### 43.10 Out of scope

- Rewriting fleet-components in a different language.
- Splitting fleet-components into a separate repo.

---

## 44. Rust Crate: fleet-data

- slug: `rust-fleet-data`
- captain: unassigned
- budget: ~300 lines (soft cap)

### 44.1 Mission

Make `fleet-data` a stable, testable, ergonomic crate. It models fleet domain data.

### 44.2 Current state

- `rust/fleet-data` is part of the workspace.
- Public API surface for `fleet-data` is documented inline with rustdoc.
- Tests live under src/ unit tests and/or tests/ integration directory.
- Snapshots (where applicable) live under src/snapshots/.

### 44.3 Pain points

1. Limited rustdoc top-level crate docs.
2. Patchy property-based test coverage.
3. Public types may leak internal details.
4. No published changelog per crate.

### 44.4 Improvement protocols

#### 44.4.1 Crate-level rustdoc for fleet-data

- state: PROPOSED
- lane: fleet-data maintainers

**Problem.** Top-level crate docs are thin or missing.

**Hypothesis.** Strong crate docs reduce ramp-up time for contributors.

**Proposal.** Add `//!` crate docs with: purpose, stability promise, examples, feature flags, key types.

**Implementation steps.**

1. Author crate-level docs.
1. Add doctest examples covering the most common API.
1. Wire `cargo doc --no-deps` into CI.

**Verification.** `cargo doc -p fleet-data` succeeds; html includes overview.

**Acceptance criteria.**

- Crate has >= 50 lines of `//!` docs.
- Doctests pass.

**Rollback.** Revert docs.

**Risks.**

- Doctest brittleness.

**Metrics.**

- doc-coverage %
- broken-link count

**References.**

- `rust/fleet-data/src/lib.rs`

#### 44.4.2 Public API audit for fleet-data

- state: PROPOSED
- lane: rust lane

**Problem.** Public surface may leak internals or duplicate types.

**Hypothesis.** An API audit using `cargo public-api` highlights leakage.

**Proposal.** Run cargo public-api; reduce surface; mark internal items `pub(crate)`.

**Implementation steps.**

1. Run cargo public-api locally.
1. Triage each public item.
1. Commit reductions; add CI to track diff.

**Verification.** `cargo public-api -p fleet-data` baseline committed.

**Acceptance criteria.**

- Public surface reduced or stabilised.
- Baseline tracked in repo.

**Rollback.** Restore previous visibility.

**Risks.**

- Breaking changes for downstream crates.

**Metrics.**

- public-item count delta

**References.**

- `rust/fleet-data/`

### 44.5 Backlog (raw)

- Add fuzz target for fleet-data via cargo-fuzz.
- Add WASM build matrix entry for fleet-data if applicable.
- Add miri run on weekly schedule for fleet-data.
- Add semver-check via cargo-semver-checks for fleet-data.
- Add cargo-deny config covering fleet-data dependencies.
- Split fleet-data into core + helpers if API grows.
- Adopt typestate pattern where invariants warrant it.
- Reduce monomorphization cost in fleet-data hotspots.
- Audit allocations on hot paths in fleet-data.
- Add tracing instrumentation in fleet-data with feature flag.

### 44.6 Open questions

- [ ] Should fleet-data be published to crates.io eventually?
- [ ] What is the upstream story for fleet-data once codex-fleet stabilises?
- [ ] How do we version fleet-data relative to fleet release tags?

### 44.7 Cross-cutting dependencies

- Other fleet-* crates as declared in Cargo.toml.

### 44.8 Risk register

- Breaking changes in fleet-data ripple to all consumers.
- Performance regressions in fleet-data surface only under load.

### 44.9 Migration plan

1. Phase 1: docs + clippy baseline for fleet-data.
2. Phase 2: tests + benches + MSRV for fleet-data.
3. Phase 3: per-crate CHANGELOG and semver gating for fleet-data.

### 44.10 Out of scope

- Rewriting fleet-data in a different language.
- Splitting fleet-data into a separate repo.

---

## 45. Rust Crate: fleet-input

- slug: `rust-fleet-input`
- captain: unassigned
- budget: ~300 lines (soft cap)

### 45.1 Mission

Make `fleet-input` a stable, testable, ergonomic crate. It defines the cross-dashboard input contract.

### 45.2 Current state

- `rust/fleet-input` is part of the workspace.
- Public API surface for `fleet-input` is documented inline with rustdoc.
- Tests live under src/ unit tests and/or tests/ integration directory.
- Snapshots (where applicable) live under src/snapshots/.

### 45.3 Pain points

1. Limited rustdoc top-level crate docs.
2. Patchy property-based test coverage.
3. Public types may leak internal details.
4. No published changelog per crate.

### 45.4 Improvement protocols

#### 45.4.1 Crate-level rustdoc for fleet-input

- state: PROPOSED
- lane: fleet-input maintainers

**Problem.** Top-level crate docs are thin or missing.

**Hypothesis.** Strong crate docs reduce ramp-up time for contributors.

**Proposal.** Add `//!` crate docs with: purpose, stability promise, examples, feature flags, key types.

**Implementation steps.**

1. Author crate-level docs.
1. Add doctest examples covering the most common API.
1. Wire `cargo doc --no-deps` into CI.

**Verification.** `cargo doc -p fleet-input` succeeds; html includes overview.

**Acceptance criteria.**

- Crate has >= 50 lines of `//!` docs.
- Doctests pass.

**Rollback.** Revert docs.

**Risks.**

- Doctest brittleness.

**Metrics.**

- doc-coverage %
- broken-link count

**References.**

- `rust/fleet-input/src/lib.rs`

#### 45.4.2 Public API audit for fleet-input

- state: PROPOSED
- lane: rust lane

**Problem.** Public surface may leak internals or duplicate types.

**Hypothesis.** An API audit using `cargo public-api` highlights leakage.

**Proposal.** Run cargo public-api; reduce surface; mark internal items `pub(crate)`.

**Implementation steps.**

1. Run cargo public-api locally.
1. Triage each public item.
1. Commit reductions; add CI to track diff.

**Verification.** `cargo public-api -p fleet-input` baseline committed.

**Acceptance criteria.**

- Public surface reduced or stabilised.
- Baseline tracked in repo.

**Rollback.** Restore previous visibility.

**Risks.**

- Breaking changes for downstream crates.

**Metrics.**

- public-item count delta

**References.**

- `rust/fleet-input/`

### 45.5 Backlog (raw)

- Add fuzz target for fleet-input via cargo-fuzz.
- Add WASM build matrix entry for fleet-input if applicable.
- Add miri run on weekly schedule for fleet-input.
- Add semver-check via cargo-semver-checks for fleet-input.
- Add cargo-deny config covering fleet-input dependencies.
- Split fleet-input into core + helpers if API grows.
- Adopt typestate pattern where invariants warrant it.
- Reduce monomorphization cost in fleet-input hotspots.
- Audit allocations on hot paths in fleet-input.
- Add tracing instrumentation in fleet-input with feature flag.

### 45.6 Open questions

- [ ] Should fleet-input be published to crates.io eventually?
- [ ] What is the upstream story for fleet-input once codex-fleet stabilises?
- [ ] How do we version fleet-input relative to fleet release tags?

### 45.7 Cross-cutting dependencies

- Other fleet-* crates as declared in Cargo.toml.

### 45.8 Risk register

- Breaking changes in fleet-input ripple to all consumers.
- Performance regressions in fleet-input surface only under load.

### 45.9 Migration plan

1. Phase 1: docs + clippy baseline for fleet-input.
2. Phase 2: tests + benches + MSRV for fleet-input.
3. Phase 3: per-crate CHANGELOG and semver gating for fleet-input.

### 45.10 Out of scope

- Rewriting fleet-input in a different language.
- Splitting fleet-input into a separate repo.

---

## 46. Rust Crate: fleet-launcher

- slug: `rust-fleet-launcher`
- captain: unassigned
- budget: ~300 lines (soft cap)

### 46.1 Mission

Make `fleet-launcher` a stable, testable, ergonomic crate. It launches and supervises fleet runs.

### 46.2 Current state

- `rust/fleet-launcher` is part of the workspace.
- Public API surface for `fleet-launcher` is documented inline with rustdoc.
- Tests live under src/ unit tests and/or tests/ integration directory.
- Snapshots (where applicable) live under src/snapshots/.

### 46.3 Pain points

1. Limited rustdoc top-level crate docs.
2. Patchy property-based test coverage.
3. Public types may leak internal details.
4. No published changelog per crate.

### 46.4 Improvement protocols

#### 46.4.1 Crate-level rustdoc for fleet-launcher

- state: PROPOSED
- lane: fleet-launcher maintainers

**Problem.** Top-level crate docs are thin or missing.

**Hypothesis.** Strong crate docs reduce ramp-up time for contributors.

**Proposal.** Add `//!` crate docs with: purpose, stability promise, examples, feature flags, key types.

**Implementation steps.**

1. Author crate-level docs.
1. Add doctest examples covering the most common API.
1. Wire `cargo doc --no-deps` into CI.

**Verification.** `cargo doc -p fleet-launcher` succeeds; html includes overview.

**Acceptance criteria.**

- Crate has >= 50 lines of `//!` docs.
- Doctests pass.

**Rollback.** Revert docs.

**Risks.**

- Doctest brittleness.

**Metrics.**

- doc-coverage %
- broken-link count

**References.**

- `rust/fleet-launcher/src/lib.rs`

#### 46.4.2 Public API audit for fleet-launcher

- state: PROPOSED
- lane: rust lane

**Problem.** Public surface may leak internals or duplicate types.

**Hypothesis.** An API audit using `cargo public-api` highlights leakage.

**Proposal.** Run cargo public-api; reduce surface; mark internal items `pub(crate)`.

**Implementation steps.**

1. Run cargo public-api locally.
1. Triage each public item.
1. Commit reductions; add CI to track diff.

**Verification.** `cargo public-api -p fleet-launcher` baseline committed.

**Acceptance criteria.**

- Public surface reduced or stabilised.
- Baseline tracked in repo.

**Rollback.** Restore previous visibility.

**Risks.**

- Breaking changes for downstream crates.

**Metrics.**

- public-item count delta

**References.**

- `rust/fleet-launcher/`

### 46.5 Backlog (raw)

- Add fuzz target for fleet-launcher via cargo-fuzz.
- Add WASM build matrix entry for fleet-launcher if applicable.
- Add miri run on weekly schedule for fleet-launcher.
- Add semver-check via cargo-semver-checks for fleet-launcher.
- Add cargo-deny config covering fleet-launcher dependencies.
- Split fleet-launcher into core + helpers if API grows.
- Adopt typestate pattern where invariants warrant it.
- Reduce monomorphization cost in fleet-launcher hotspots.
- Audit allocations on hot paths in fleet-launcher.
- Add tracing instrumentation in fleet-launcher with feature flag.

### 46.6 Open questions

- [ ] Should fleet-launcher be published to crates.io eventually?
- [ ] What is the upstream story for fleet-launcher once codex-fleet stabilises?
- [ ] How do we version fleet-launcher relative to fleet release tags?

### 46.7 Cross-cutting dependencies

- Other fleet-* crates as declared in Cargo.toml.

### 46.8 Risk register

- Breaking changes in fleet-launcher ripple to all consumers.
- Performance regressions in fleet-launcher surface only under load.

### 46.9 Migration plan

1. Phase 1: docs + clippy baseline for fleet-launcher.
2. Phase 2: tests + benches + MSRV for fleet-launcher.
3. Phase 3: per-crate CHANGELOG and semver gating for fleet-launcher.

### 46.10 Out of scope

- Rewriting fleet-launcher in a different language.
- Splitting fleet-launcher into a separate repo.

---

## 47. Rust Crate: fleet-layout

- slug: `rust-fleet-layout`
- captain: unassigned
- budget: ~300 lines (soft cap)

### 47.1 Mission

Make `fleet-layout` a stable, testable, ergonomic crate. It exposes the layout DSL consumed by dashboards.

### 47.2 Current state

- `rust/fleet-layout` is part of the workspace.
- Public API surface for `fleet-layout` is documented inline with rustdoc.
- Tests live under src/ unit tests and/or tests/ integration directory.
- Snapshots (where applicable) live under src/snapshots/.

### 47.3 Pain points

1. Limited rustdoc top-level crate docs.
2. Patchy property-based test coverage.
3. Public types may leak internal details.
4. No published changelog per crate.

### 47.4 Improvement protocols

#### 47.4.1 Crate-level rustdoc for fleet-layout

- state: PROPOSED
- lane: fleet-layout maintainers

**Problem.** Top-level crate docs are thin or missing.

**Hypothesis.** Strong crate docs reduce ramp-up time for contributors.

**Proposal.** Add `//!` crate docs with: purpose, stability promise, examples, feature flags, key types.

**Implementation steps.**

1. Author crate-level docs.
1. Add doctest examples covering the most common API.
1. Wire `cargo doc --no-deps` into CI.

**Verification.** `cargo doc -p fleet-layout` succeeds; html includes overview.

**Acceptance criteria.**

- Crate has >= 50 lines of `//!` docs.
- Doctests pass.

**Rollback.** Revert docs.

**Risks.**

- Doctest brittleness.

**Metrics.**

- doc-coverage %
- broken-link count

**References.**

- `rust/fleet-layout/src/lib.rs`

#### 47.4.2 Public API audit for fleet-layout

- state: PROPOSED
- lane: rust lane

**Problem.** Public surface may leak internals or duplicate types.

**Hypothesis.** An API audit using `cargo public-api` highlights leakage.

**Proposal.** Run cargo public-api; reduce surface; mark internal items `pub(crate)`.

**Implementation steps.**

1. Run cargo public-api locally.
1. Triage each public item.
1. Commit reductions; add CI to track diff.

**Verification.** `cargo public-api -p fleet-layout` baseline committed.

**Acceptance criteria.**

- Public surface reduced or stabilised.
- Baseline tracked in repo.

**Rollback.** Restore previous visibility.

**Risks.**

- Breaking changes for downstream crates.

**Metrics.**

- public-item count delta

**References.**

- `rust/fleet-layout/`

### 47.5 Backlog (raw)

- Add fuzz target for fleet-layout via cargo-fuzz.
- Add WASM build matrix entry for fleet-layout if applicable.
- Add miri run on weekly schedule for fleet-layout.
- Add semver-check via cargo-semver-checks for fleet-layout.
- Add cargo-deny config covering fleet-layout dependencies.
- Split fleet-layout into core + helpers if API grows.
- Adopt typestate pattern where invariants warrant it.
- Reduce monomorphization cost in fleet-layout hotspots.
- Audit allocations on hot paths in fleet-layout.
- Add tracing instrumentation in fleet-layout with feature flag.

### 47.6 Open questions

- [ ] Should fleet-layout be published to crates.io eventually?
- [ ] What is the upstream story for fleet-layout once codex-fleet stabilises?
- [ ] How do we version fleet-layout relative to fleet release tags?

### 47.7 Cross-cutting dependencies

- Other fleet-* crates as declared in Cargo.toml.

### 47.8 Risk register

- Breaking changes in fleet-layout ripple to all consumers.
- Performance regressions in fleet-layout surface only under load.

### 47.9 Migration plan

1. Phase 1: docs + clippy baseline for fleet-layout.
2. Phase 2: tests + benches + MSRV for fleet-layout.
3. Phase 3: per-crate CHANGELOG and semver gating for fleet-layout.

### 47.10 Out of scope

- Rewriting fleet-layout in a different language.
- Splitting fleet-layout into a separate repo.

---

## 48. Rust Crate: fleet-metrics-viewer

- slug: `rust-fleet-metrics-viewer`
- captain: unassigned
- budget: ~300 lines (soft cap)

### 48.1 Mission

Make `fleet-metrics-viewer` a stable, testable, ergonomic crate. It renders fleet metrics.

### 48.2 Current state

- `rust/fleet-metrics-viewer` is part of the workspace.
- Public API surface for `fleet-metrics-viewer` is documented inline with rustdoc.
- Tests live under src/ unit tests and/or tests/ integration directory.
- Snapshots (where applicable) live under src/snapshots/.

### 48.3 Pain points

1. Limited rustdoc top-level crate docs.
2. Patchy property-based test coverage.
3. Public types may leak internal details.
4. No published changelog per crate.

### 48.4 Improvement protocols

#### 48.4.1 Crate-level rustdoc for fleet-metrics-viewer

- state: PROPOSED
- lane: fleet-metrics-viewer maintainers

**Problem.** Top-level crate docs are thin or missing.

**Hypothesis.** Strong crate docs reduce ramp-up time for contributors.

**Proposal.** Add `//!` crate docs with: purpose, stability promise, examples, feature flags, key types.

**Implementation steps.**

1. Author crate-level docs.
1. Add doctest examples covering the most common API.
1. Wire `cargo doc --no-deps` into CI.

**Verification.** `cargo doc -p fleet-metrics-viewer` succeeds; html includes overview.

**Acceptance criteria.**

- Crate has >= 50 lines of `//!` docs.
- Doctests pass.

**Rollback.** Revert docs.

**Risks.**

- Doctest brittleness.

**Metrics.**

- doc-coverage %
- broken-link count

**References.**

- `rust/fleet-metrics-viewer/src/lib.rs`

#### 48.4.2 Public API audit for fleet-metrics-viewer

- state: PROPOSED
- lane: rust lane

**Problem.** Public surface may leak internals or duplicate types.

**Hypothesis.** An API audit using `cargo public-api` highlights leakage.

**Proposal.** Run cargo public-api; reduce surface; mark internal items `pub(crate)`.

**Implementation steps.**

1. Run cargo public-api locally.
1. Triage each public item.
1. Commit reductions; add CI to track diff.

**Verification.** `cargo public-api -p fleet-metrics-viewer` baseline committed.

**Acceptance criteria.**

- Public surface reduced or stabilised.
- Baseline tracked in repo.

**Rollback.** Restore previous visibility.

**Risks.**

- Breaking changes for downstream crates.

**Metrics.**

- public-item count delta

**References.**

- `rust/fleet-metrics-viewer/`

### 48.5 Backlog (raw)

- Add fuzz target for fleet-metrics-viewer via cargo-fuzz.
- Add WASM build matrix entry for fleet-metrics-viewer if applicable.
- Add miri run on weekly schedule for fleet-metrics-viewer.
- Add semver-check via cargo-semver-checks for fleet-metrics-viewer.
- Add cargo-deny config covering fleet-metrics-viewer dependencies.
- Split fleet-metrics-viewer into core + helpers if API grows.
- Adopt typestate pattern where invariants warrant it.
- Reduce monomorphization cost in fleet-metrics-viewer hotspots.
- Audit allocations on hot paths in fleet-metrics-viewer.
- Add tracing instrumentation in fleet-metrics-viewer with feature flag.

### 48.6 Open questions

- [ ] Should fleet-metrics-viewer be published to crates.io eventually?
- [ ] What is the upstream story for fleet-metrics-viewer once codex-fleet stabilises?
- [ ] How do we version fleet-metrics-viewer relative to fleet release tags?

### 48.7 Cross-cutting dependencies

- Other fleet-* crates as declared in Cargo.toml.

### 48.8 Risk register

- Breaking changes in fleet-metrics-viewer ripple to all consumers.
- Performance regressions in fleet-metrics-viewer surface only under load.

### 48.9 Migration plan

1. Phase 1: docs + clippy baseline for fleet-metrics-viewer.
2. Phase 2: tests + benches + MSRV for fleet-metrics-viewer.
3. Phase 3: per-crate CHANGELOG and semver gating for fleet-metrics-viewer.

### 48.10 Out of scope

- Rewriting fleet-metrics-viewer in a different language.
- Splitting fleet-metrics-viewer into a separate repo.

---

## 49. Rust Crate: fleet-pane-health

- slug: `rust-fleet-pane-health`
- captain: unassigned
- budget: ~300 lines (soft cap)

### 49.1 Mission

Make `fleet-pane-health` a stable, testable, ergonomic crate. It tracks tmux pane health.

### 49.2 Current state

- `rust/fleet-pane-health` is part of the workspace.
- Public API surface for `fleet-pane-health` is documented inline with rustdoc.
- Tests live under src/ unit tests and/or tests/ integration directory.
- Snapshots (where applicable) live under src/snapshots/.

### 49.3 Pain points

1. Limited rustdoc top-level crate docs.
2. Patchy property-based test coverage.
3. Public types may leak internal details.
4. No published changelog per crate.

### 49.4 Improvement protocols

#### 49.4.1 Crate-level rustdoc for fleet-pane-health

- state: PROPOSED
- lane: fleet-pane-health maintainers

**Problem.** Top-level crate docs are thin or missing.

**Hypothesis.** Strong crate docs reduce ramp-up time for contributors.

**Proposal.** Add `//!` crate docs with: purpose, stability promise, examples, feature flags, key types.

**Implementation steps.**

1. Author crate-level docs.
1. Add doctest examples covering the most common API.
1. Wire `cargo doc --no-deps` into CI.

**Verification.** `cargo doc -p fleet-pane-health` succeeds; html includes overview.

**Acceptance criteria.**

- Crate has >= 50 lines of `//!` docs.
- Doctests pass.

**Rollback.** Revert docs.

**Risks.**

- Doctest brittleness.

**Metrics.**

- doc-coverage %
- broken-link count

**References.**

- `rust/fleet-pane-health/src/lib.rs`

#### 49.4.2 Public API audit for fleet-pane-health

- state: PROPOSED
- lane: rust lane

**Problem.** Public surface may leak internals or duplicate types.

**Hypothesis.** An API audit using `cargo public-api` highlights leakage.

**Proposal.** Run cargo public-api; reduce surface; mark internal items `pub(crate)`.

**Implementation steps.**

1. Run cargo public-api locally.
1. Triage each public item.
1. Commit reductions; add CI to track diff.

**Verification.** `cargo public-api -p fleet-pane-health` baseline committed.

**Acceptance criteria.**

- Public surface reduced or stabilised.
- Baseline tracked in repo.

**Rollback.** Restore previous visibility.

**Risks.**

- Breaking changes for downstream crates.

**Metrics.**

- public-item count delta

**References.**

- `rust/fleet-pane-health/`

### 49.5 Backlog (raw)

- Add fuzz target for fleet-pane-health via cargo-fuzz.
- Add WASM build matrix entry for fleet-pane-health if applicable.
- Add miri run on weekly schedule for fleet-pane-health.
- Add semver-check via cargo-semver-checks for fleet-pane-health.
- Add cargo-deny config covering fleet-pane-health dependencies.
- Split fleet-pane-health into core + helpers if API grows.
- Adopt typestate pattern where invariants warrant it.
- Reduce monomorphization cost in fleet-pane-health hotspots.
- Audit allocations on hot paths in fleet-pane-health.
- Add tracing instrumentation in fleet-pane-health with feature flag.

### 49.6 Open questions

- [ ] Should fleet-pane-health be published to crates.io eventually?
- [ ] What is the upstream story for fleet-pane-health once codex-fleet stabilises?
- [ ] How do we version fleet-pane-health relative to fleet release tags?

### 49.7 Cross-cutting dependencies

- Other fleet-* crates as declared in Cargo.toml.

### 49.8 Risk register

- Breaking changes in fleet-pane-health ripple to all consumers.
- Performance regressions in fleet-pane-health surface only under load.

### 49.9 Migration plan

1. Phase 1: docs + clippy baseline for fleet-pane-health.
2. Phase 2: tests + benches + MSRV for fleet-pane-health.
3. Phase 3: per-crate CHANGELOG and semver gating for fleet-pane-health.

### 49.10 Out of scope

- Rewriting fleet-pane-health in a different language.
- Splitting fleet-pane-health into a separate repo.

---

## 50. Rust Crate: fleet-plan-tree

- slug: `rust-fleet-plan-tree`
- captain: unassigned
- budget: ~300 lines (soft cap)

### 50.1 Mission

Make `fleet-plan-tree` a stable, testable, ergonomic crate. It models plan tree state.

### 50.2 Current state

- `rust/fleet-plan-tree` is part of the workspace.
- Public API surface for `fleet-plan-tree` is documented inline with rustdoc.
- Tests live under src/ unit tests and/or tests/ integration directory.
- Snapshots (where applicable) live under src/snapshots/.

### 50.3 Pain points

1. Limited rustdoc top-level crate docs.
2. Patchy property-based test coverage.
3. Public types may leak internal details.
4. No published changelog per crate.

### 50.4 Improvement protocols

#### 50.4.1 Crate-level rustdoc for fleet-plan-tree

- state: PROPOSED
- lane: fleet-plan-tree maintainers

**Problem.** Top-level crate docs are thin or missing.

**Hypothesis.** Strong crate docs reduce ramp-up time for contributors.

**Proposal.** Add `//!` crate docs with: purpose, stability promise, examples, feature flags, key types.

**Implementation steps.**

1. Author crate-level docs.
1. Add doctest examples covering the most common API.
1. Wire `cargo doc --no-deps` into CI.

**Verification.** `cargo doc -p fleet-plan-tree` succeeds; html includes overview.

**Acceptance criteria.**

- Crate has >= 50 lines of `//!` docs.
- Doctests pass.

**Rollback.** Revert docs.

**Risks.**

- Doctest brittleness.

**Metrics.**

- doc-coverage %
- broken-link count

**References.**

- `rust/fleet-plan-tree/src/lib.rs`

#### 50.4.2 Public API audit for fleet-plan-tree

- state: PROPOSED
- lane: rust lane

**Problem.** Public surface may leak internals or duplicate types.

**Hypothesis.** An API audit using `cargo public-api` highlights leakage.

**Proposal.** Run cargo public-api; reduce surface; mark internal items `pub(crate)`.

**Implementation steps.**

1. Run cargo public-api locally.
1. Triage each public item.
1. Commit reductions; add CI to track diff.

**Verification.** `cargo public-api -p fleet-plan-tree` baseline committed.

**Acceptance criteria.**

- Public surface reduced or stabilised.
- Baseline tracked in repo.

**Rollback.** Restore previous visibility.

**Risks.**

- Breaking changes for downstream crates.

**Metrics.**

- public-item count delta

**References.**

- `rust/fleet-plan-tree/`

### 50.5 Backlog (raw)

- Add fuzz target for fleet-plan-tree via cargo-fuzz.
- Add WASM build matrix entry for fleet-plan-tree if applicable.
- Add miri run on weekly schedule for fleet-plan-tree.
- Add semver-check via cargo-semver-checks for fleet-plan-tree.
- Add cargo-deny config covering fleet-plan-tree dependencies.
- Split fleet-plan-tree into core + helpers if API grows.
- Adopt typestate pattern where invariants warrant it.
- Reduce monomorphization cost in fleet-plan-tree hotspots.
- Audit allocations on hot paths in fleet-plan-tree.
- Add tracing instrumentation in fleet-plan-tree with feature flag.

### 50.6 Open questions

- [ ] Should fleet-plan-tree be published to crates.io eventually?
- [ ] What is the upstream story for fleet-plan-tree once codex-fleet stabilises?
- [ ] How do we version fleet-plan-tree relative to fleet release tags?

### 50.7 Cross-cutting dependencies

- Other fleet-* crates as declared in Cargo.toml.

### 50.8 Risk register

- Breaking changes in fleet-plan-tree ripple to all consumers.
- Performance regressions in fleet-plan-tree surface only under load.

### 50.9 Migration plan

1. Phase 1: docs + clippy baseline for fleet-plan-tree.
2. Phase 2: tests + benches + MSRV for fleet-plan-tree.
3. Phase 3: per-crate CHANGELOG and semver gating for fleet-plan-tree.

### 50.10 Out of scope

- Rewriting fleet-plan-tree in a different language.
- Splitting fleet-plan-tree into a separate repo.

---

## 51. Rust Crate: fleet-state

- slug: `rust-fleet-state`
- captain: unassigned
- budget: ~300 lines (soft cap)

### 51.1 Mission

Make `fleet-state` a stable, testable, ergonomic crate. It is the fleet-state dashboard binary.

### 51.2 Current state

- `rust/fleet-state` is part of the workspace.
- Public API surface for `fleet-state` is documented inline with rustdoc.
- Tests live under src/ unit tests and/or tests/ integration directory.
- Snapshots (where applicable) live under src/snapshots/.

### 51.3 Pain points

1. Limited rustdoc top-level crate docs.
2. Patchy property-based test coverage.
3. Public types may leak internal details.
4. No published changelog per crate.

### 51.4 Improvement protocols

#### 51.4.1 Crate-level rustdoc for fleet-state

- state: PROPOSED
- lane: fleet-state maintainers

**Problem.** Top-level crate docs are thin or missing.

**Hypothesis.** Strong crate docs reduce ramp-up time for contributors.

**Proposal.** Add `//!` crate docs with: purpose, stability promise, examples, feature flags, key types.

**Implementation steps.**

1. Author crate-level docs.
1. Add doctest examples covering the most common API.
1. Wire `cargo doc --no-deps` into CI.

**Verification.** `cargo doc -p fleet-state` succeeds; html includes overview.

**Acceptance criteria.**

- Crate has >= 50 lines of `//!` docs.
- Doctests pass.

**Rollback.** Revert docs.

**Risks.**

- Doctest brittleness.

**Metrics.**

- doc-coverage %
- broken-link count

**References.**

- `rust/fleet-state/src/lib.rs`

#### 51.4.2 Public API audit for fleet-state

- state: PROPOSED
- lane: rust lane

**Problem.** Public surface may leak internals or duplicate types.

**Hypothesis.** An API audit using `cargo public-api` highlights leakage.

**Proposal.** Run cargo public-api; reduce surface; mark internal items `pub(crate)`.

**Implementation steps.**

1. Run cargo public-api locally.
1. Triage each public item.
1. Commit reductions; add CI to track diff.

**Verification.** `cargo public-api -p fleet-state` baseline committed.

**Acceptance criteria.**

- Public surface reduced or stabilised.
- Baseline tracked in repo.

**Rollback.** Restore previous visibility.

**Risks.**

- Breaking changes for downstream crates.

**Metrics.**

- public-item count delta

**References.**

- `rust/fleet-state/`

### 51.5 Backlog (raw)

- Add fuzz target for fleet-state via cargo-fuzz.
- Add WASM build matrix entry for fleet-state if applicable.
- Add miri run on weekly schedule for fleet-state.
- Add semver-check via cargo-semver-checks for fleet-state.
- Add cargo-deny config covering fleet-state dependencies.
- Split fleet-state into core + helpers if API grows.
- Adopt typestate pattern where invariants warrant it.
- Reduce monomorphization cost in fleet-state hotspots.
- Audit allocations on hot paths in fleet-state.
- Add tracing instrumentation in fleet-state with feature flag.

### 51.6 Open questions

- [ ] Should fleet-state be published to crates.io eventually?
- [ ] What is the upstream story for fleet-state once codex-fleet stabilises?
- [ ] How do we version fleet-state relative to fleet release tags?

### 51.7 Cross-cutting dependencies

- Other fleet-* crates as declared in Cargo.toml.

### 51.8 Risk register

- Breaking changes in fleet-state ripple to all consumers.
- Performance regressions in fleet-state surface only under load.

### 51.9 Migration plan

1. Phase 1: docs + clippy baseline for fleet-state.
2. Phase 2: tests + benches + MSRV for fleet-state.
3. Phase 3: per-crate CHANGELOG and semver gating for fleet-state.

### 51.10 Out of scope

- Rewriting fleet-state in a different language.
- Splitting fleet-state into a separate repo.

---

## 52. Rust Crate: fleet-ui

- slug: `rust-fleet-ui`
- captain: unassigned
- budget: ~300 lines (soft cap)

### 52.1 Mission

Make `fleet-ui` a stable, testable, ergonomic crate. It is the shared UI primitives crate.

### 52.2 Current state

- `rust/fleet-ui` is part of the workspace.
- Public API surface for `fleet-ui` is documented inline with rustdoc.
- Tests live under src/ unit tests and/or tests/ integration directory.
- Snapshots (where applicable) live under src/snapshots/.

### 52.3 Pain points

1. Limited rustdoc top-level crate docs.
2. Patchy property-based test coverage.
3. Public types may leak internal details.
4. No published changelog per crate.

### 52.4 Improvement protocols

#### 52.4.1 Crate-level rustdoc for fleet-ui

- state: PROPOSED
- lane: fleet-ui maintainers

**Problem.** Top-level crate docs are thin or missing.

**Hypothesis.** Strong crate docs reduce ramp-up time for contributors.

**Proposal.** Add `//!` crate docs with: purpose, stability promise, examples, feature flags, key types.

**Implementation steps.**

1. Author crate-level docs.
1. Add doctest examples covering the most common API.
1. Wire `cargo doc --no-deps` into CI.

**Verification.** `cargo doc -p fleet-ui` succeeds; html includes overview.

**Acceptance criteria.**

- Crate has >= 50 lines of `//!` docs.
- Doctests pass.

**Rollback.** Revert docs.

**Risks.**

- Doctest brittleness.

**Metrics.**

- doc-coverage %
- broken-link count

**References.**

- `rust/fleet-ui/src/lib.rs`

#### 52.4.2 Public API audit for fleet-ui

- state: PROPOSED
- lane: rust lane

**Problem.** Public surface may leak internals or duplicate types.

**Hypothesis.** An API audit using `cargo public-api` highlights leakage.

**Proposal.** Run cargo public-api; reduce surface; mark internal items `pub(crate)`.

**Implementation steps.**

1. Run cargo public-api locally.
1. Triage each public item.
1. Commit reductions; add CI to track diff.

**Verification.** `cargo public-api -p fleet-ui` baseline committed.

**Acceptance criteria.**

- Public surface reduced or stabilised.
- Baseline tracked in repo.

**Rollback.** Restore previous visibility.

**Risks.**

- Breaking changes for downstream crates.

**Metrics.**

- public-item count delta

**References.**

- `rust/fleet-ui/`

### 52.5 Backlog (raw)

- Add fuzz target for fleet-ui via cargo-fuzz.
- Add WASM build matrix entry for fleet-ui if applicable.
- Add miri run on weekly schedule for fleet-ui.
- Add semver-check via cargo-semver-checks for fleet-ui.
- Add cargo-deny config covering fleet-ui dependencies.
- Split fleet-ui into core + helpers if API grows.
- Adopt typestate pattern where invariants warrant it.
- Reduce monomorphization cost in fleet-ui hotspots.
- Audit allocations on hot paths in fleet-ui.
- Add tracing instrumentation in fleet-ui with feature flag.

### 52.6 Open questions

- [ ] Should fleet-ui be published to crates.io eventually?
- [ ] What is the upstream story for fleet-ui once codex-fleet stabilises?
- [ ] How do we version fleet-ui relative to fleet release tags?

### 52.7 Cross-cutting dependencies

- Other fleet-* crates as declared in Cargo.toml.

### 52.8 Risk register

- Breaking changes in fleet-ui ripple to all consumers.
- Performance regressions in fleet-ui surface only under load.

### 52.9 Migration plan

1. Phase 1: docs + clippy baseline for fleet-ui.
2. Phase 2: tests + benches + MSRV for fleet-ui.
3. Phase 3: per-crate CHANGELOG and semver gating for fleet-ui.

### 52.10 Out of scope

- Rewriting fleet-ui in a different language.
- Splitting fleet-ui into a separate repo.

---

## 53. Rust Crate: fleet-watcher

- slug: `rust-fleet-watcher`
- captain: unassigned
- budget: ~300 lines (soft cap)

### 53.1 Mission

Make `fleet-watcher` a stable, testable, ergonomic crate. It is the fleet-watcher dashboard binary.

### 53.2 Current state

- `rust/fleet-watcher` is part of the workspace.
- Public API surface for `fleet-watcher` is documented inline with rustdoc.
- Tests live under src/ unit tests and/or tests/ integration directory.
- Snapshots (where applicable) live under src/snapshots/.

### 53.3 Pain points

1. Limited rustdoc top-level crate docs.
2. Patchy property-based test coverage.
3. Public types may leak internal details.
4. No published changelog per crate.

### 53.4 Improvement protocols

#### 53.4.1 Crate-level rustdoc for fleet-watcher

- state: PROPOSED
- lane: fleet-watcher maintainers

**Problem.** Top-level crate docs are thin or missing.

**Hypothesis.** Strong crate docs reduce ramp-up time for contributors.

**Proposal.** Add `//!` crate docs with: purpose, stability promise, examples, feature flags, key types.

**Implementation steps.**

1. Author crate-level docs.
1. Add doctest examples covering the most common API.
1. Wire `cargo doc --no-deps` into CI.

**Verification.** `cargo doc -p fleet-watcher` succeeds; html includes overview.

**Acceptance criteria.**

- Crate has >= 50 lines of `//!` docs.
- Doctests pass.

**Rollback.** Revert docs.

**Risks.**

- Doctest brittleness.

**Metrics.**

- doc-coverage %
- broken-link count

**References.**

- `rust/fleet-watcher/src/lib.rs`

#### 53.4.2 Public API audit for fleet-watcher

- state: PROPOSED
- lane: rust lane

**Problem.** Public surface may leak internals or duplicate types.

**Hypothesis.** An API audit using `cargo public-api` highlights leakage.

**Proposal.** Run cargo public-api; reduce surface; mark internal items `pub(crate)`.

**Implementation steps.**

1. Run cargo public-api locally.
1. Triage each public item.
1. Commit reductions; add CI to track diff.

**Verification.** `cargo public-api -p fleet-watcher` baseline committed.

**Acceptance criteria.**

- Public surface reduced or stabilised.
- Baseline tracked in repo.

**Rollback.** Restore previous visibility.

**Risks.**

- Breaking changes for downstream crates.

**Metrics.**

- public-item count delta

**References.**

- `rust/fleet-watcher/`

### 53.5 Backlog (raw)

- Add fuzz target for fleet-watcher via cargo-fuzz.
- Add WASM build matrix entry for fleet-watcher if applicable.
- Add miri run on weekly schedule for fleet-watcher.
- Add semver-check via cargo-semver-checks for fleet-watcher.
- Add cargo-deny config covering fleet-watcher dependencies.
- Split fleet-watcher into core + helpers if API grows.
- Adopt typestate pattern where invariants warrant it.
- Reduce monomorphization cost in fleet-watcher hotspots.
- Audit allocations on hot paths in fleet-watcher.
- Add tracing instrumentation in fleet-watcher with feature flag.

### 53.6 Open questions

- [ ] Should fleet-watcher be published to crates.io eventually?
- [ ] What is the upstream story for fleet-watcher once codex-fleet stabilises?
- [ ] How do we version fleet-watcher relative to fleet release tags?

### 53.7 Cross-cutting dependencies

- Other fleet-* crates as declared in Cargo.toml.

### 53.8 Risk register

- Breaking changes in fleet-watcher ripple to all consumers.
- Performance regressions in fleet-watcher surface only under load.

### 53.9 Migration plan

1. Phase 1: docs + clippy baseline for fleet-watcher.
2. Phase 2: tests + benches + MSRV for fleet-watcher.
3. Phase 3: per-crate CHANGELOG and semver gating for fleet-watcher.

### 53.10 Out of scope

- Rewriting fleet-watcher in a different language.
- Splitting fleet-watcher into a separate repo.

---

## 54. Rust Crate: fleet-waves

- slug: `rust-fleet-waves`
- captain: unassigned
- budget: ~300 lines (soft cap)

### 54.1 Mission

Make `fleet-waves` a stable, testable, ergonomic crate. It models wave progression.

### 54.2 Current state

- `rust/fleet-waves` is part of the workspace.
- Public API surface for `fleet-waves` is documented inline with rustdoc.
- Tests live under src/ unit tests and/or tests/ integration directory.
- Snapshots (where applicable) live under src/snapshots/.

### 54.3 Pain points

1. Limited rustdoc top-level crate docs.
2. Patchy property-based test coverage.
3. Public types may leak internal details.
4. No published changelog per crate.

### 54.4 Improvement protocols

#### 54.4.1 Crate-level rustdoc for fleet-waves

- state: PROPOSED
- lane: fleet-waves maintainers

**Problem.** Top-level crate docs are thin or missing.

**Hypothesis.** Strong crate docs reduce ramp-up time for contributors.

**Proposal.** Add `//!` crate docs with: purpose, stability promise, examples, feature flags, key types.

**Implementation steps.**

1. Author crate-level docs.
1. Add doctest examples covering the most common API.
1. Wire `cargo doc --no-deps` into CI.

**Verification.** `cargo doc -p fleet-waves` succeeds; html includes overview.

**Acceptance criteria.**

- Crate has >= 50 lines of `//!` docs.
- Doctests pass.

**Rollback.** Revert docs.

**Risks.**

- Doctest brittleness.

**Metrics.**

- doc-coverage %
- broken-link count

**References.**

- `rust/fleet-waves/src/lib.rs`

#### 54.4.2 Public API audit for fleet-waves

- state: PROPOSED
- lane: rust lane

**Problem.** Public surface may leak internals or duplicate types.

**Hypothesis.** An API audit using `cargo public-api` highlights leakage.

**Proposal.** Run cargo public-api; reduce surface; mark internal items `pub(crate)`.

**Implementation steps.**

1. Run cargo public-api locally.
1. Triage each public item.
1. Commit reductions; add CI to track diff.

**Verification.** `cargo public-api -p fleet-waves` baseline committed.

**Acceptance criteria.**

- Public surface reduced or stabilised.
- Baseline tracked in repo.

**Rollback.** Restore previous visibility.

**Risks.**

- Breaking changes for downstream crates.

**Metrics.**

- public-item count delta

**References.**

- `rust/fleet-waves/`

### 54.5 Backlog (raw)

- Add fuzz target for fleet-waves via cargo-fuzz.
- Add WASM build matrix entry for fleet-waves if applicable.
- Add miri run on weekly schedule for fleet-waves.
- Add semver-check via cargo-semver-checks for fleet-waves.
- Add cargo-deny config covering fleet-waves dependencies.
- Split fleet-waves into core + helpers if API grows.
- Adopt typestate pattern where invariants warrant it.
- Reduce monomorphization cost in fleet-waves hotspots.
- Audit allocations on hot paths in fleet-waves.
- Add tracing instrumentation in fleet-waves with feature flag.

### 54.6 Open questions

- [ ] Should fleet-waves be published to crates.io eventually?
- [ ] What is the upstream story for fleet-waves once codex-fleet stabilises?
- [ ] How do we version fleet-waves relative to fleet release tags?

### 54.7 Cross-cutting dependencies

- Other fleet-* crates as declared in Cargo.toml.

### 54.8 Risk register

- Breaking changes in fleet-waves ripple to all consumers.
- Performance regressions in fleet-waves surface only under load.

### 54.9 Migration plan

1. Phase 1: docs + clippy baseline for fleet-waves.
2. Phase 2: tests + benches + MSRV for fleet-waves.
3. Phase 3: per-crate CHANGELOG and semver gating for fleet-waves.

### 54.10 Out of scope

- Rewriting fleet-waves in a different language.
- Splitting fleet-waves into a separate repo.

---

## 55. OpenSpec Workflow & Plan Registry

- slug: `openspec-workflow`
- captain: unassigned
- budget: ~300 lines (soft cap)

### 55.1 Mission

OpenSpec is the source of truth for change-driven work. Improve plan publication, validation, archival, and registry semantics so that every fleet pane consumes a consistent view.

### 55.2 Current state

- openspec/plans/<slug>/plan.json drives full-bringup.
- openspec validate --specs is the validation entrypoint.
- Plans may live in a sibling repo via CODEX_FLEET_REPO_ROOT.
- openspec/changes/<slug>/ holds in-flight change artifacts.

### 55.3 Pain points

1. Plan schema drift between repos is undetected until runtime.
2. Archive workflow is manual; specs accumulate in changes/.
3. Task graph publication can race with bringup.

### 55.4 Improvement protocols

#### 55.4.1 OpenSpec: define explicit ownership boundaries

- state: PROPOSED
- lane: subsystem owner

**Problem.** Concrete gap exists for this concern within the fleet.

**Hypothesis.** Closing the gap improves reliability and reviewer signal.

**Proposal.** Adopt the named pattern with explicit owners and acceptance criteria.

**Implementation steps.**

1. Document the concern in this section.
1. Author the supporting artifact (runbook, schema, probe, etc.).
1. Wire into CI or observability where applicable.
1. Refresh dashboards and skill prompts.

**Verification.** Confirm artifact exists and is referenced from this section.

**Acceptance criteria.**

- Artifact exists.
- Referenced in protocol.
- Owner named.

**Rollback.** Remove artifact; revert to prior behaviour.

**Risks.**

- Process overhead.
- Lock-in to current patterns.

**Metrics.**

- Adoption %
- Time-to-detect failures

**References.**

- `openspec/`
- `openspec/changes/`
- `openspec/plans/`

#### 55.4.2 OpenSpec: instrument key paths with structured logs

- state: PROPOSED
- lane: subsystem owner

**Problem.** Concrete gap exists for this concern within the fleet.

**Hypothesis.** Closing the gap improves reliability and reviewer signal.

**Proposal.** Adopt the named pattern with explicit owners and acceptance criteria.

**Implementation steps.**

1. Document the concern in this section.
1. Author the supporting artifact (runbook, schema, probe, etc.).
1. Wire into CI or observability where applicable.
1. Refresh dashboards and skill prompts.

**Verification.** Confirm artifact exists and is referenced from this section.

**Acceptance criteria.**

- Artifact exists.
- Referenced in protocol.
- Owner named.

**Rollback.** Remove artifact; revert to prior behaviour.

**Risks.**

- Process overhead.
- Lock-in to current patterns.

**Metrics.**

- Adoption %
- Time-to-detect failures

**References.**

- `openspec/`
- `openspec/changes/`
- `openspec/plans/`

### 55.5 Backlog (raw)

- Adopt JSON Schema validation for plan.json with versioning.
- Add `openspec doctor` command surfacing common drift issues.
- Auto-archive specs after merge.
- Backfill historical plans into a queryable index.
- Add OpenSpec UI for non-CLI users.
- Sign plan.json with content hash; reject mismatched hashes.
- Add per-plan owner field used by Colony routing.
- Add `openspec lint` for style consistency.
- Annotate each plan with intended fleet size.
- Surface plan changes as Colony task_messages.

### 55.6 Open questions

- [ ] Should plans be versioned (v1, v2) within a slug?
- [ ] How do we handle plans that span multiple repos?
- [ ] What's the right archival cadence?

### 55.7 Cross-cutting dependencies

- Colony task graph
- full-bringup.sh

### 55.8 Risk register

- Schema drift breaks bringup.
- Validation gaps allow bad specs.

### 55.9 Migration plan

1. Phase 1: schema definition.
2. Phase 2: validator rollout (warning).
3. Phase 3: validator enforced.

### 55.10 Out of scope

- Replacing openspec wholesale.

---

## 56. Colony Integration & Task Graph

- slug: `colony-integration`
- captain: unassigned
- budget: ~300 lines (soft cap)

### 56.1 Mission

Colony is the coordination surface for tasks, messages, claims, and notes. Strengthen the contract so multi-agent execution stays deterministic across reboots and network blips.

### 56.2 Current state

- Colony CLI publishes plans and surfaces task_ready_for_agent.
- force-claim.sh polls Colony every 15s and dispatches.
- claim-release-supervisor releases stale claims.
- task_post / task_message used for handoffs.

### 56.3 Pain points

1. Colony API drift between server and CLI versions.
2. Limited observability into queue depth / starvation.
3. Network blips during a poll can cause double-dispatch.

### 56.4 Improvement protocols

#### 56.4.1 Colony: define explicit ownership boundaries

- state: PROPOSED
- lane: subsystem owner

**Problem.** Concrete gap exists for this concern within the fleet.

**Hypothesis.** Closing the gap improves reliability and reviewer signal.

**Proposal.** Adopt the named pattern with explicit owners and acceptance criteria.

**Implementation steps.**

1. Document the concern in this section.
1. Author the supporting artifact (runbook, schema, probe, etc.).
1. Wire into CI or observability where applicable.
1. Refresh dashboards and skill prompts.

**Verification.** Confirm artifact exists and is referenced from this section.

**Acceptance criteria.**

- Artifact exists.
- Referenced in protocol.
- Owner named.

**Rollback.** Remove artifact; revert to prior behaviour.

**Risks.**

- Process overhead.
- Lock-in to current patterns.

**Metrics.**

- Adoption %
- Time-to-detect failures

**References.**

- `scripts/codex-fleet/force-claim.sh`
- `scripts/codex-fleet/claim-release-supervisor.sh`

#### 56.4.2 Colony: instrument key paths with structured logs

- state: PROPOSED
- lane: subsystem owner

**Problem.** Concrete gap exists for this concern within the fleet.

**Hypothesis.** Closing the gap improves reliability and reviewer signal.

**Proposal.** Adopt the named pattern with explicit owners and acceptance criteria.

**Implementation steps.**

1. Document the concern in this section.
1. Author the supporting artifact (runbook, schema, probe, etc.).
1. Wire into CI or observability where applicable.
1. Refresh dashboards and skill prompts.

**Verification.** Confirm artifact exists and is referenced from this section.

**Acceptance criteria.**

- Artifact exists.
- Referenced in protocol.
- Owner named.

**Rollback.** Remove artifact; revert to prior behaviour.

**Risks.**

- Process overhead.
- Lock-in to current patterns.

**Metrics.**

- Adoption %
- Time-to-detect failures

**References.**

- `scripts/codex-fleet/force-claim.sh`
- `scripts/codex-fleet/claim-release-supervisor.sh`

### 56.5 Backlog (raw)

- Add Colony health-check command to bringup preflight.
- Expose queue-depth metric to fleet-metrics-viewer.
- Idempotency token on dispatch to prevent double-fire.
- Local Colony cache for offline mode.
- Track claim age distributions; alert on outliers.
- Add task priority surfacing in fleet-state.
- Add per-agent skill weighting; honour skills in ready selector.
- Add 'shadow agent' that mirrors traffic for replay testing.
- Add Colony message-rate limiter to avoid chat-spam.
- Add Colony rate cap configurable per env.

### 56.6 Open questions

- [ ] How do we version the Colony contract relative to CLI releases?
- [ ] Should we pin Colony CLI version in install.sh?
- [ ] What is the failover plan if Colony is unreachable for >10 min?

### 56.7 Cross-cutting dependencies

- Colony CLI
- Network connectivity

### 56.8 Risk register

- Colony outage stalls fleet.
- Schema drift breaks dispatch.

### 56.9 Migration plan

1. Phase 1: pin CLI.
2. Phase 2: cache.
3. Phase 3: offline mode.

### 56.10 Out of scope

- Replacing Colony with a custom queue.

---

## 57. Account / Auth Layer

- slug: `account-auth`
- captain: unassigned
- budget: ~300 lines (soft cap)

### 57.1 Mission

Account auth is the supply side: every worker pane needs a healthy `~/.codex/accounts/<email>.json`. Improve provisioning, rotation, and cap detection.

### 57.2 Current state

- agent-auth login produces JSON files per account.
- cap-probe.sh exercises accounts to determine cap status.
- cap-swap-daemon.sh swaps capped accounts with healthy ones.
- accounts.yml lists declared accounts and skills.

### 57.3 Pain points

1. Manual rotation when an account dies.
2. No central health view of all accounts.
3. Skills metadata not currently authoritative.

### 57.4 Improvement protocols

#### 57.4.1 Account/Auth: define explicit ownership boundaries

- state: PROPOSED
- lane: subsystem owner

**Problem.** Concrete gap exists for this concern within the fleet.

**Hypothesis.** Closing the gap improves reliability and reviewer signal.

**Proposal.** Adopt the named pattern with explicit owners and acceptance criteria.

**Implementation steps.**

1. Document the concern in this section.
1. Author the supporting artifact (runbook, schema, probe, etc.).
1. Wire into CI or observability where applicable.
1. Refresh dashboards and skill prompts.

**Verification.** Confirm artifact exists and is referenced from this section.

**Acceptance criteria.**

- Artifact exists.
- Referenced in protocol.
- Owner named.

**Rollback.** Remove artifact; revert to prior behaviour.

**Risks.**

- Process overhead.
- Lock-in to current patterns.

**Metrics.**

- Adoption %
- Time-to-detect failures

**References.**

- `scripts/codex-fleet/cap-probe.sh`
- `scripts/codex-fleet/cap-swap-daemon.sh`
- `scripts/codex-fleet/accounts.example.yml`

#### 57.4.2 Account/Auth: instrument key paths with structured logs

- state: PROPOSED
- lane: subsystem owner

**Problem.** Concrete gap exists for this concern within the fleet.

**Hypothesis.** Closing the gap improves reliability and reviewer signal.

**Proposal.** Adopt the named pattern with explicit owners and acceptance criteria.

**Implementation steps.**

1. Document the concern in this section.
1. Author the supporting artifact (runbook, schema, probe, etc.).
1. Wire into CI or observability where applicable.
1. Refresh dashboards and skill prompts.

**Verification.** Confirm artifact exists and is referenced from this section.

**Acceptance criteria.**

- Artifact exists.
- Referenced in protocol.
- Owner named.

**Rollback.** Remove artifact; revert to prior behaviour.

**Risks.**

- Process overhead.
- Lock-in to current patterns.

**Metrics.**

- Adoption %
- Time-to-detect failures

**References.**

- `scripts/codex-fleet/cap-probe.sh`
- `scripts/codex-fleet/cap-swap-daemon.sh`
- `scripts/codex-fleet/accounts.example.yml`

### 57.5 Backlog (raw)

- Add `fleet-accounts` CLI for listing, probing, rotating accounts.
- Encrypt accounts.yml at rest with sops or age.
- Auto-rotate auth tokens when nearing expiry.
- Visual fleet health board showing account state matrix.
- Per-account rate-limit telemetry.
- Account quota planner for upcoming wave.
- Anomaly detection on per-account latency.
- Bring-your-own-account API for community contributions.
- Backup account list with cold spares.
- Account labels (region, tier, project) for routing.

### 57.6 Open questions

- [ ] Do we standardise on agent-auth or accept multiple auth backends?
- [ ] How is account rotation gated when fleet is mid-bringup?

### 57.7 Cross-cutting dependencies

- agent-auth
- Codex CLI
- Colony

### 57.8 Risk register

- Account compromise.
- Cap detection false negatives.

### 57.9 Migration plan

1. Phase 1: CLI.
2. Phase 2: encryption.
3. Phase 3: anomaly detection.

### 57.10 Out of scope

- Authoring our own auth server.

---

## 58. Self-Healing Daemons (composite)

- slug: `self-healing`
- captain: unassigned
- budget: ~300 lines (soft cap)

### 58.1 Mission

Compose force-claim, claim-release-supervisor, cap-swap-daemon, and stall-watcher into a single self-healing fabric with measurable SLOs.

### 58.2 Current state

- Each daemon runs in its own tmux pane with hand-tuned cadences.
- Inter-daemon coordination is implicit (no shared state).
- Operator can disable or replace daemons via env flags.

### 58.3 Pain points

1. Cadence tuning is folklore.
2. No combined dashboard summarising healing outcomes.
3. Daemons can fight each other (e.g., release vs. claim).

### 58.4 Improvement protocols

#### 58.4.1 Self-Healing: define explicit ownership boundaries

- state: PROPOSED
- lane: subsystem owner

**Problem.** Concrete gap exists for this concern within the fleet.

**Hypothesis.** Closing the gap improves reliability and reviewer signal.

**Proposal.** Adopt the named pattern with explicit owners and acceptance criteria.

**Implementation steps.**

1. Document the concern in this section.
1. Author the supporting artifact (runbook, schema, probe, etc.).
1. Wire into CI or observability where applicable.
1. Refresh dashboards and skill prompts.

**Verification.** Confirm artifact exists and is referenced from this section.

**Acceptance criteria.**

- Artifact exists.
- Referenced in protocol.
- Owner named.

**Rollback.** Remove artifact; revert to prior behaviour.

**Risks.**

- Process overhead.
- Lock-in to current patterns.

**Metrics.**

- Adoption %
- Time-to-detect failures

**References.**

- `scripts/codex-fleet/force-claim.sh`
- `scripts/codex-fleet/claim-release-supervisor.sh`
- `scripts/codex-fleet/cap-swap-daemon.sh`
- `scripts/codex-fleet/stall-watcher.sh`

#### 58.4.2 Self-Healing: instrument key paths with structured logs

- state: PROPOSED
- lane: subsystem owner

**Problem.** Concrete gap exists for this concern within the fleet.

**Hypothesis.** Closing the gap improves reliability and reviewer signal.

**Proposal.** Adopt the named pattern with explicit owners and acceptance criteria.

**Implementation steps.**

1. Document the concern in this section.
1. Author the supporting artifact (runbook, schema, probe, etc.).
1. Wire into CI or observability where applicable.
1. Refresh dashboards and skill prompts.

**Verification.** Confirm artifact exists and is referenced from this section.

**Acceptance criteria.**

- Artifact exists.
- Referenced in protocol.
- Owner named.

**Rollback.** Remove artifact; revert to prior behaviour.

**Risks.**

- Process overhead.
- Lock-in to current patterns.

**Metrics.**

- Adoption %
- Time-to-detect failures

**References.**

- `scripts/codex-fleet/force-claim.sh`
- `scripts/codex-fleet/claim-release-supervisor.sh`
- `scripts/codex-fleet/cap-swap-daemon.sh`
- `scripts/codex-fleet/stall-watcher.sh`

### 58.5 Backlog (raw)

- Aggregate self-healing events into a single ledger.
- Add 'healing rate' SLO target (e.g., 95% within 60s).
- Synthesize daemon decisions into a Colony task_message stream.
- Allow daemon priority overrides per fleet config.
- Run daemons under systemd-style supervision for restart-on-crash.
- Add chaos toggle to simulate stranded panes.
- Daemon configuration via single TOML file.
- Replay log of healing events for postmortems.
- Visualise daemon decisions over time.
- Configurable cooldowns to avoid thrash.

### 58.6 Open questions

- [ ] Should daemons share a coordination lock?
- [ ] What's the tolerable fight-rate between daemons?

### 58.7 Cross-cutting dependencies

- Colony
- tmux

### 58.8 Risk register

- Daemon thrash.
- False healings.

### 58.9 Migration plan

1. Phase 1: shared ledger.
2. Phase 2: SLO.
3. Phase 3: supervisor.

### 58.10 Out of scope

- Rewriting daemons in another language right away.

---

## 59. Observability & Metrics

- slug: `observability`
- captain: unassigned
- budget: ~300 lines (soft cap)

### 59.1 Mission

Make fleet behaviour legible to operators and reviewers via metrics, dashboards, and traces.

### 59.2 Current state

- fleet-metrics-viewer crate exists.
- Most metrics are inferred from script output.
- No central time-series store.

### 59.3 Pain points

1. Cannot answer 'how did this fleet run perform vs. yesterday'.
2. Limited correlation between Colony events and pane behaviour.

### 59.4 Improvement protocols

#### 59.4.1 Observability: define explicit ownership boundaries

- state: PROPOSED
- lane: subsystem owner

**Problem.** Concrete gap exists for this concern within the fleet.

**Hypothesis.** Closing the gap improves reliability and reviewer signal.

**Proposal.** Adopt the named pattern with explicit owners and acceptance criteria.

**Implementation steps.**

1. Document the concern in this section.
1. Author the supporting artifact (runbook, schema, probe, etc.).
1. Wire into CI or observability where applicable.
1. Refresh dashboards and skill prompts.

**Verification.** Confirm artifact exists and is referenced from this section.

**Acceptance criteria.**

- Artifact exists.
- Referenced in protocol.
- Owner named.

**Rollback.** Remove artifact; revert to prior behaviour.

**Risks.**

- Process overhead.
- Lock-in to current patterns.

**Metrics.**

- Adoption %
- Time-to-detect failures

**References.**

- `rust/fleet-metrics-viewer/`
- `scripts/codex-fleet/`

#### 59.4.2 Observability: instrument key paths with structured logs

- state: PROPOSED
- lane: subsystem owner

**Problem.** Concrete gap exists for this concern within the fleet.

**Hypothesis.** Closing the gap improves reliability and reviewer signal.

**Proposal.** Adopt the named pattern with explicit owners and acceptance criteria.

**Implementation steps.**

1. Document the concern in this section.
1. Author the supporting artifact (runbook, schema, probe, etc.).
1. Wire into CI or observability where applicable.
1. Refresh dashboards and skill prompts.

**Verification.** Confirm artifact exists and is referenced from this section.

**Acceptance criteria.**

- Artifact exists.
- Referenced in protocol.
- Owner named.

**Rollback.** Remove artifact; revert to prior behaviour.

**Risks.**

- Process overhead.
- Lock-in to current patterns.

**Metrics.**

- Adoption %
- Time-to-detect failures

**References.**

- `rust/fleet-metrics-viewer/`
- `scripts/codex-fleet/`

### 59.5 Backlog (raw)

- Adopt OpenTelemetry traces across rust crates.
- Add per-pane heartbeat metrics.
- Add Colony queue-depth panel.
- Add latency histograms for force-claim dispatch.
- Add per-account token-burn timeline.
- Add per-plan progress timeline.
- Standardise metric naming (fleet_<subsystem>_<verb>_<unit>).
- Add SLO-burn calculation per subsystem.
- Add alerting thresholds documented in this section.
- Add long-term retention story (parquet under .codex-fleet/metrics/).

### 59.6 Open questions

- [ ] Do we ship a default Prometheus exporter?
- [ ] Do we depend on an external observability provider?

### 59.7 Cross-cutting dependencies

- fleet-metrics-viewer
- tracing crate

### 59.8 Risk register

- Metric explosion.
- Privacy of metric labels.

### 59.9 Migration plan

1. Phase 1: structured logs.
2. Phase 2: metrics crate.
3. Phase 3: traces.

### 59.10 Out of scope

- Becoming an observability platform.

---

## 60. Logging, Tracing & Replay

- slug: `logging-tracing`
- captain: unassigned
- budget: ~300 lines (soft cap)

### 60.1 Mission

Capture enough context to reconstruct any failed fleet run within minutes.

### 60.2 Current state

- Logs land in tmux scrollback and per-script files.
- No central trace ID across scripts and crates.
- Replay is manual.

### 60.3 Pain points

1. Scrollback is volatile.
2. No correlation IDs.
3. Hard to debug daemon decisions after the fact.

### 60.4 Improvement protocols

#### 60.4.1 Logging: define explicit ownership boundaries

- state: PROPOSED
- lane: subsystem owner

**Problem.** Concrete gap exists for this concern within the fleet.

**Hypothesis.** Closing the gap improves reliability and reviewer signal.

**Proposal.** Adopt the named pattern with explicit owners and acceptance criteria.

**Implementation steps.**

1. Document the concern in this section.
1. Author the supporting artifact (runbook, schema, probe, etc.).
1. Wire into CI or observability where applicable.
1. Refresh dashboards and skill prompts.

**Verification.** Confirm artifact exists and is referenced from this section.

**Acceptance criteria.**

- Artifact exists.
- Referenced in protocol.
- Owner named.

**Rollback.** Remove artifact; revert to prior behaviour.

**Risks.**

- Process overhead.
- Lock-in to current patterns.

**Metrics.**

- Adoption %
- Time-to-detect failures

**References.**

- `scripts/codex-fleet/`
- `rust/`

#### 60.4.2 Logging: instrument key paths with structured logs

- state: PROPOSED
- lane: subsystem owner

**Problem.** Concrete gap exists for this concern within the fleet.

**Hypothesis.** Closing the gap improves reliability and reviewer signal.

**Proposal.** Adopt the named pattern with explicit owners and acceptance criteria.

**Implementation steps.**

1. Document the concern in this section.
1. Author the supporting artifact (runbook, schema, probe, etc.).
1. Wire into CI or observability where applicable.
1. Refresh dashboards and skill prompts.

**Verification.** Confirm artifact exists and is referenced from this section.

**Acceptance criteria.**

- Artifact exists.
- Referenced in protocol.
- Owner named.

**Rollback.** Remove artifact; revert to prior behaviour.

**Risks.**

- Process overhead.
- Lock-in to current patterns.

**Metrics.**

- Adoption %
- Time-to-detect failures

**References.**

- `scripts/codex-fleet/`
- `rust/`

### 60.5 Backlog (raw)

- Adopt slog or tracing across rust binaries.
- Adopt a structured prefix in bash scripts.
- Persist all logs under .codex-fleet/logs/<run-id>/.
- Add log shipping to external store as opt-in.
- Add log rotation policy.
- Add log redaction for secrets.
- Add replay tool that reconstructs timeline from logs.
- Add log-level config knob per script.
- Add log-sampling for high-volume sources.
- Add 'last failure' quick command for operators.

### 60.6 Open questions

- [ ] Do we standardise on JSON logs or k=v logs?
- [ ] What is the retention window default?

### 60.7 Cross-cutting dependencies

- fleet-metrics-viewer
- fleet-state

### 60.8 Risk register

- Log volume.
- PII leakage.

### 60.9 Migration plan

1. Phase 1: structured format.
2. Phase 2: rotation.
3. Phase 3: replay.

### 60.10 Out of scope

- Building a logging service.

---

## 61. Testing Strategy (unit, integration, snapshot, e2e)

- slug: `testing-strategy`
- captain: unassigned
- budget: ~300 lines (soft cap)

### 61.1 Mission

Define a layered test strategy ensuring fast feedback and high confidence before merge.

### 61.2 Current state

- Per-crate unit tests via cargo test.
- Snapshot tests under src/snapshots/.
- Ad-hoc shell tests under scripts/codex-fleet/test/.
- No formal e2e harness for the full fleet bringup.

### 61.3 Pain points

1. E2E confidence is operator-dependent.
2. Snapshot drift can be missed.

### 61.4 Improvement protocols

#### 61.4.1 Testing: define explicit ownership boundaries

- state: PROPOSED
- lane: subsystem owner

**Problem.** Concrete gap exists for this concern within the fleet.

**Hypothesis.** Closing the gap improves reliability and reviewer signal.

**Proposal.** Adopt the named pattern with explicit owners and acceptance criteria.

**Implementation steps.**

1. Document the concern in this section.
1. Author the supporting artifact (runbook, schema, probe, etc.).
1. Wire into CI or observability where applicable.
1. Refresh dashboards and skill prompts.

**Verification.** Confirm artifact exists and is referenced from this section.

**Acceptance criteria.**

- Artifact exists.
- Referenced in protocol.
- Owner named.

**Rollback.** Remove artifact; revert to prior behaviour.

**Risks.**

- Process overhead.
- Lock-in to current patterns.

**Metrics.**

- Adoption %
- Time-to-detect failures

**References.**

- `rust/`
- `scripts/codex-fleet/test/`

#### 61.4.2 Testing: instrument key paths with structured logs

- state: PROPOSED
- lane: subsystem owner

**Problem.** Concrete gap exists for this concern within the fleet.

**Hypothesis.** Closing the gap improves reliability and reviewer signal.

**Proposal.** Adopt the named pattern with explicit owners and acceptance criteria.

**Implementation steps.**

1. Document the concern in this section.
1. Author the supporting artifact (runbook, schema, probe, etc.).
1. Wire into CI or observability where applicable.
1. Refresh dashboards and skill prompts.

**Verification.** Confirm artifact exists and is referenced from this section.

**Acceptance criteria.**

- Artifact exists.
- Referenced in protocol.
- Owner named.

**Rollback.** Remove artifact; revert to prior behaviour.

**Risks.**

- Process overhead.
- Lock-in to current patterns.

**Metrics.**

- Adoption %
- Time-to-detect failures

**References.**

- `rust/`
- `scripts/codex-fleet/test/`

### 61.5 Backlog (raw)

- Add bats-core test runner for shell.
- Add cargo-nextest profile.
- Add a virtual fleet test that runs in CI with synthetic Colony.
- Add a mutation testing pass (cargo-mutants) for critical crates.
- Add a cross-OS test matrix.
- Add a synthetic load generator.
- Add a regression test corpus.
- Add a flaky-test detector.
- Add a test-time budget gate.
- Add visual diff testing for tmux dashboards (where feasible).

### 61.6 Open questions

- [ ] How do we test interactions with real Codex CLI without burning quotas?
- [ ] Do we run nightly e2e against a sandbox Colony?

### 61.7 Cross-cutting dependencies

- CI
- Colony sandbox

### 61.8 Risk register

- Test flakiness erodes trust.
- Excessive runtime.

### 61.9 Migration plan

1. Phase 1: structure.
2. Phase 2: nextest.
3. Phase 3: e2e.

### 61.10 Out of scope

- Building a test orchestrator from scratch.

---

## 62. CI/CD & Release Pipeline

- slug: `ci-cd`
- captain: unassigned
- budget: ~300 lines (soft cap)

### 62.1 Mission

Reach push-to-green confidence with a single CI entrypoint and reproducible releases.

### 62.2 Current state

- .github/ holds workflow definitions.
- Release process is manual.

### 62.3 Pain points

1. No clear release artifact set.
2. CI runs may duplicate work across jobs.

### 62.4 Improvement protocols

#### 62.4.1 CI/CD: define explicit ownership boundaries

- state: PROPOSED
- lane: subsystem owner

**Problem.** Concrete gap exists for this concern within the fleet.

**Hypothesis.** Closing the gap improves reliability and reviewer signal.

**Proposal.** Adopt the named pattern with explicit owners and acceptance criteria.

**Implementation steps.**

1. Document the concern in this section.
1. Author the supporting artifact (runbook, schema, probe, etc.).
1. Wire into CI or observability where applicable.
1. Refresh dashboards and skill prompts.

**Verification.** Confirm artifact exists and is referenced from this section.

**Acceptance criteria.**

- Artifact exists.
- Referenced in protocol.
- Owner named.

**Rollback.** Remove artifact; revert to prior behaviour.

**Risks.**

- Process overhead.
- Lock-in to current patterns.

**Metrics.**

- Adoption %
- Time-to-detect failures

**References.**

- `.github/`
- `install.sh`

#### 62.4.2 CI/CD: instrument key paths with structured logs

- state: PROPOSED
- lane: subsystem owner

**Problem.** Concrete gap exists for this concern within the fleet.

**Hypothesis.** Closing the gap improves reliability and reviewer signal.

**Proposal.** Adopt the named pattern with explicit owners and acceptance criteria.

**Implementation steps.**

1. Document the concern in this section.
1. Author the supporting artifact (runbook, schema, probe, etc.).
1. Wire into CI or observability where applicable.
1. Refresh dashboards and skill prompts.

**Verification.** Confirm artifact exists and is referenced from this section.

**Acceptance criteria.**

- Artifact exists.
- Referenced in protocol.
- Owner named.

**Rollback.** Remove artifact; revert to prior behaviour.

**Risks.**

- Process overhead.
- Lock-in to current patterns.

**Metrics.**

- Adoption %
- Time-to-detect failures

**References.**

- `.github/`
- `install.sh`

### 62.5 Backlog (raw)

- Adopt cargo-dist for releases.
- Adopt cargo-deny.
- Adopt cargo-audit on schedule.
- Tagged releases auto-update install.sh checksum.
- Add SBOM generation.
- Cache cargo registry and target dir aggressively.
- Add concurrency groups to cancel stale PR runs.
- Add reusable workflows.
- Add 'release candidate' channel.
- Add 'hotfix' fast path.

### 62.6 Open questions

- [ ] Do we sign release artifacts?
- [ ] Do we publish binaries to a registry?

### 62.7 Cross-cutting dependencies

- GitHub Actions
- Cargo

### 62.8 Risk register

- Release regressions.
- CI flake.

### 62.9 Migration plan

1. Phase 1: just ci.
2. Phase 2: cargo-dist.
3. Phase 3: signing.

### 62.10 Out of scope

- Self-hosting CI.

---

## 63. Security, Sandboxing & Permissions

- slug: `security-sandbox`
- captain: unassigned
- budget: ~300 lines (soft cap)

### 63.1 Mission

Protect host environments from worker pane misbehaviour and reduce blast radius.

### 63.2 Current state

- microsandbox-integration.md documents prior thinking.
- Worker panes execute Codex CLI directly on host.

### 63.3 Pain points

1. Limited filesystem isolation.
2. No central permission policy.

### 63.4 Improvement protocols

#### 63.4.1 Security: define explicit ownership boundaries

- state: PROPOSED
- lane: subsystem owner

**Problem.** Concrete gap exists for this concern within the fleet.

**Hypothesis.** Closing the gap improves reliability and reviewer signal.

**Proposal.** Adopt the named pattern with explicit owners and acceptance criteria.

**Implementation steps.**

1. Document the concern in this section.
1. Author the supporting artifact (runbook, schema, probe, etc.).
1. Wire into CI or observability where applicable.
1. Refresh dashboards and skill prompts.

**Verification.** Confirm artifact exists and is referenced from this section.

**Acceptance criteria.**

- Artifact exists.
- Referenced in protocol.
- Owner named.

**Rollback.** Remove artifact; revert to prior behaviour.

**Risks.**

- Process overhead.
- Lock-in to current patterns.

**Metrics.**

- Adoption %
- Time-to-detect failures

**References.**

- `docs/microsandbox-integration.md`
- `scripts/codex-fleet/`

#### 63.4.2 Security: instrument key paths with structured logs

- state: PROPOSED
- lane: subsystem owner

**Problem.** Concrete gap exists for this concern within the fleet.

**Hypothesis.** Closing the gap improves reliability and reviewer signal.

**Proposal.** Adopt the named pattern with explicit owners and acceptance criteria.

**Implementation steps.**

1. Document the concern in this section.
1. Author the supporting artifact (runbook, schema, probe, etc.).
1. Wire into CI or observability where applicable.
1. Refresh dashboards and skill prompts.

**Verification.** Confirm artifact exists and is referenced from this section.

**Acceptance criteria.**

- Artifact exists.
- Referenced in protocol.
- Owner named.

**Rollback.** Remove artifact; revert to prior behaviour.

**Risks.**

- Process overhead.
- Lock-in to current patterns.

**Metrics.**

- Adoption %
- Time-to-detect failures

**References.**

- `docs/microsandbox-integration.md`
- `scripts/codex-fleet/`

### 63.5 Backlog (raw)

- Adopt firejail or bubblewrap for worker panes.
- Filesystem allow-list per pane.
- Add per-pane resource limits (cpu, ram).
- Add network allow-list per pane.
- Add audit log of permission events.
- Add credential redaction in shared logs.
- Add per-pane chroot or namespace isolation.
- Add seccomp policy.
- Add per-pane firewall rules.
- Document threat model.

### 63.6 Open questions

- [ ] Do we ship a sandbox by default or opt-in?
- [ ] What's the fallback if sandbox tools are missing?

### 63.7 Cross-cutting dependencies

- Linux namespaces
- Worker pane scripts

### 63.8 Risk register

- Sandbox breaks legitimate workflows.
- Performance overhead.

### 63.9 Migration plan

1. Phase 1: threat model.
2. Phase 2: opt-in sandbox.
3. Phase 3: default sandbox.

### 63.10 Out of scope

- Replacing host OS isolation.

---

## 64. Secrets, Credentials & Token Hygiene

- slug: `secrets`
- captain: unassigned
- budget: ~300 lines (soft cap)

### 64.1 Mission

Eliminate accidental leakage of account tokens, Colony tokens, and API keys.

### 64.2 Current state

- accounts.yml gitignored; example template tracked.
- Tokens live under ~/.codex/.
- Limited automated scanning.

### 64.3 Pain points

1. No central secret scanning.
2. Manual review burden for token paths in logs.

### 64.4 Improvement protocols

#### 64.4.1 Secrets: define explicit ownership boundaries

- state: PROPOSED
- lane: subsystem owner

**Problem.** Concrete gap exists for this concern within the fleet.

**Hypothesis.** Closing the gap improves reliability and reviewer signal.

**Proposal.** Adopt the named pattern with explicit owners and acceptance criteria.

**Implementation steps.**

1. Document the concern in this section.
1. Author the supporting artifact (runbook, schema, probe, etc.).
1. Wire into CI or observability where applicable.
1. Refresh dashboards and skill prompts.

**Verification.** Confirm artifact exists and is referenced from this section.

**Acceptance criteria.**

- Artifact exists.
- Referenced in protocol.
- Owner named.

**Rollback.** Remove artifact; revert to prior behaviour.

**Risks.**

- Process overhead.
- Lock-in to current patterns.

**Metrics.**

- Adoption %
- Time-to-detect failures

**References.**

- `scripts/codex-fleet/`
- `.gitignore`

#### 64.4.2 Secrets: instrument key paths with structured logs

- state: PROPOSED
- lane: subsystem owner

**Problem.** Concrete gap exists for this concern within the fleet.

**Hypothesis.** Closing the gap improves reliability and reviewer signal.

**Proposal.** Adopt the named pattern with explicit owners and acceptance criteria.

**Implementation steps.**

1. Document the concern in this section.
1. Author the supporting artifact (runbook, schema, probe, etc.).
1. Wire into CI or observability where applicable.
1. Refresh dashboards and skill prompts.

**Verification.** Confirm artifact exists and is referenced from this section.

**Acceptance criteria.**

- Artifact exists.
- Referenced in protocol.
- Owner named.

**Rollback.** Remove artifact; revert to prior behaviour.

**Risks.**

- Process overhead.
- Lock-in to current patterns.

**Metrics.**

- Adoption %
- Time-to-detect failures

**References.**

- `scripts/codex-fleet/`
- `.gitignore`

### 64.5 Backlog (raw)

- Add pre-commit secret-scanner (gitleaks).
- Add CI secret-scanner step.
- Add log redactor across scripts.
- Add encrypted accounts.yml via sops.
- Add token expiry reminders in fleet-state.
- Add automated token rotation policy.
- Add 'no plaintext in logs' lint.
- Document key handling lifecycle.
- Add per-account permission scoping where supported.
- Add tamper-evident logging for credential access.

### 64.6 Open questions

- [ ] Do we adopt sops or age for at-rest encryption?
- [ ] Who holds the master key for shared deployments?

### 64.7 Cross-cutting dependencies

- gitleaks
- sops

### 64.8 Risk register

- Key loss.
- Operator inconvenience.

### 64.9 Migration plan

1. Phase 1: scanners.
2. Phase 2: encryption.
3. Phase 3: rotation.

### 64.10 Out of scope

- Building a secrets manager.

---

## 65. Documentation & Onboarding

- slug: `docs-onboarding`
- captain: unassigned
- budget: ~300 lines (soft cap)

### 65.1 Mission

Help a new contributor reach 'first useful PR' within one day.

### 65.2 Current state

- README + AGENTS.md + SPEC.md cover the basics.
- docs/ holds a handful of design references.
- No structured onboarding doc.

### 65.3 Pain points

1. Fragmented entrypoints.
2. No 'first 24 hours' checklist.

### 65.4 Improvement protocols

#### 65.4.1 Docs/Onboarding: define explicit ownership boundaries

- state: PROPOSED
- lane: subsystem owner

**Problem.** Concrete gap exists for this concern within the fleet.

**Hypothesis.** Closing the gap improves reliability and reviewer signal.

**Proposal.** Adopt the named pattern with explicit owners and acceptance criteria.

**Implementation steps.**

1. Document the concern in this section.
1. Author the supporting artifact (runbook, schema, probe, etc.).
1. Wire into CI or observability where applicable.
1. Refresh dashboards and skill prompts.

**Verification.** Confirm artifact exists and is referenced from this section.

**Acceptance criteria.**

- Artifact exists.
- Referenced in protocol.
- Owner named.

**Rollback.** Remove artifact; revert to prior behaviour.

**Risks.**

- Process overhead.
- Lock-in to current patterns.

**Metrics.**

- Adoption %
- Time-to-detect failures

**References.**

- `README.md`
- `docs/`

#### 65.4.2 Docs/Onboarding: instrument key paths with structured logs

- state: PROPOSED
- lane: subsystem owner

**Problem.** Concrete gap exists for this concern within the fleet.

**Hypothesis.** Closing the gap improves reliability and reviewer signal.

**Proposal.** Adopt the named pattern with explicit owners and acceptance criteria.

**Implementation steps.**

1. Document the concern in this section.
1. Author the supporting artifact (runbook, schema, probe, etc.).
1. Wire into CI or observability where applicable.
1. Refresh dashboards and skill prompts.

**Verification.** Confirm artifact exists and is referenced from this section.

**Acceptance criteria.**

- Artifact exists.
- Referenced in protocol.
- Owner named.

**Rollback.** Remove artifact; revert to prior behaviour.

**Risks.**

- Process overhead.
- Lock-in to current patterns.

**Metrics.**

- Adoption %
- Time-to-detect failures

**References.**

- `README.md`
- `docs/`

### 65.5 Backlog (raw)

- Add docs/getting-started.md.
- Add docs/troubleshooting.md.
- Add docs/glossary.md.
- Add a mermaid architecture diagram.
- Add a 'demo fleet' that runs in a container.
- Add a video walkthrough placeholder doc.
- Add explicit 'what not to do' section.
- Add weekly digest blog template.
- Add ADR index page.
- Add maintainer responsibilities doc.

### 65.6 Open questions

- [ ] Do we maintain a public website?
- [ ] Do we publish API docs?

### 65.7 Cross-cutting dependencies

- docs/
- CI

### 65.8 Risk register

- Doc rot.
- Inconsistent voice.

### 65.9 Migration plan

1. Phase 1: structure.
2. Phase 2: onboarding.
3. Phase 3: site.

### 65.10 Out of scope

- Replacing GitHub README hosting.

---

## 66. Skills System (skills/codex-fleet)

- slug: `skills`
- captain: unassigned
- budget: ~300 lines (soft cap)

### 66.1 Mission

Make the Claude Code skill self-updating, well-tested, and aware of fleet conventions.

### 66.2 Current state

- skills/codex-fleet/SKILL.md drives Claude Code recognition.
- Install.sh symlinks the skill into ~/.claude/skills/.

### 66.3 Pain points

1. Skill text drifts from script behaviour.
2. Limited automated tests for skill correctness.

### 66.4 Improvement protocols

#### 66.4.1 Skills: define explicit ownership boundaries

- state: PROPOSED
- lane: subsystem owner

**Problem.** Concrete gap exists for this concern within the fleet.

**Hypothesis.** Closing the gap improves reliability and reviewer signal.

**Proposal.** Adopt the named pattern with explicit owners and acceptance criteria.

**Implementation steps.**

1. Document the concern in this section.
1. Author the supporting artifact (runbook, schema, probe, etc.).
1. Wire into CI or observability where applicable.
1. Refresh dashboards and skill prompts.

**Verification.** Confirm artifact exists and is referenced from this section.

**Acceptance criteria.**

- Artifact exists.
- Referenced in protocol.
- Owner named.

**Rollback.** Remove artifact; revert to prior behaviour.

**Risks.**

- Process overhead.
- Lock-in to current patterns.

**Metrics.**

- Adoption %
- Time-to-detect failures

**References.**

- `skills/codex-fleet/SKILL.md`
- `install.sh`

#### 66.4.2 Skills: instrument key paths with structured logs

- state: PROPOSED
- lane: subsystem owner

**Problem.** Concrete gap exists for this concern within the fleet.

**Hypothesis.** Closing the gap improves reliability and reviewer signal.

**Proposal.** Adopt the named pattern with explicit owners and acceptance criteria.

**Implementation steps.**

1. Document the concern in this section.
1. Author the supporting artifact (runbook, schema, probe, etc.).
1. Wire into CI or observability where applicable.
1. Refresh dashboards and skill prompts.

**Verification.** Confirm artifact exists and is referenced from this section.

**Acceptance criteria.**

- Artifact exists.
- Referenced in protocol.
- Owner named.

**Rollback.** Remove artifact; revert to prior behaviour.

**Risks.**

- Process overhead.
- Lock-in to current patterns.

**Metrics.**

- Adoption %
- Time-to-detect failures

**References.**

- `skills/codex-fleet/SKILL.md`
- `install.sh`

### 66.5 Backlog (raw)

- Add a test harness that exercises the skill via Claude Code SDK.
- Add version field to SKILL.md.
- Auto-regenerate SKILL.md snippets from canonical sources.
- Add trigger-phrase lint.
- Add a skill changelog.
- Add per-command examples.
- Add 'what this skill won't do' section.
- Add error-mode catalog.
- Add escalation pattern doc.
- Add usage analytics opt-in.

### 66.6 Open questions

- [ ] Do we host the skill in a registry or stick with the install.sh symlink?
- [ ] Do we version the skill alongside fleet releases?

### 66.7 Cross-cutting dependencies

- Claude Code
- install.sh

### 66.8 Risk register

- Skill misfires under new prompts.
- Symlink breakage.

### 66.9 Migration plan

1. Phase 1: tests.
2. Phase 2: version.
3. Phase 3: registry.

### 66.10 Out of scope

- Building a skill marketplace.

---

## 67. Multi-Repo & Cross-Project Coordination

- slug: `multi-repo`
- captain: unassigned
- budget: ~300 lines (soft cap)

### 67.1 Mission

Allow codex-fleet to drive plans from arbitrary repos without losing isolation.

### 67.2 Current state

- CODEX_FLEET_REPO_ROOT points the fleet at a sibling repo.
- Force-claim is pinned to a single repo at a time.

### 67.3 Pain points

1. Switching between repos requires manual env juggling.
2. Cross-repo plans cannot be coordinated in one fleet.

### 67.4 Improvement protocols

#### 67.4.1 Multi-Repo: define explicit ownership boundaries

- state: PROPOSED
- lane: subsystem owner

**Problem.** Concrete gap exists for this concern within the fleet.

**Hypothesis.** Closing the gap improves reliability and reviewer signal.

**Proposal.** Adopt the named pattern with explicit owners and acceptance criteria.

**Implementation steps.**

1. Document the concern in this section.
1. Author the supporting artifact (runbook, schema, probe, etc.).
1. Wire into CI or observability where applicable.
1. Refresh dashboards and skill prompts.

**Verification.** Confirm artifact exists and is referenced from this section.

**Acceptance criteria.**

- Artifact exists.
- Referenced in protocol.
- Owner named.

**Rollback.** Remove artifact; revert to prior behaviour.

**Risks.**

- Process overhead.
- Lock-in to current patterns.

**Metrics.**

- Adoption %
- Time-to-detect failures

**References.**

- `scripts/codex-fleet/full-bringup.sh`
- `scripts/codex-fleet/force-claim.sh`

#### 67.4.2 Multi-Repo: instrument key paths with structured logs

- state: PROPOSED
- lane: subsystem owner

**Problem.** Concrete gap exists for this concern within the fleet.

**Hypothesis.** Closing the gap improves reliability and reviewer signal.

**Proposal.** Adopt the named pattern with explicit owners and acceptance criteria.

**Implementation steps.**

1. Document the concern in this section.
1. Author the supporting artifact (runbook, schema, probe, etc.).
1. Wire into CI or observability where applicable.
1. Refresh dashboards and skill prompts.

**Verification.** Confirm artifact exists and is referenced from this section.

**Acceptance criteria.**

- Artifact exists.
- Referenced in protocol.
- Owner named.

**Rollback.** Remove artifact; revert to prior behaviour.

**Risks.**

- Process overhead.
- Lock-in to current patterns.

**Metrics.**

- Adoption %
- Time-to-detect failures

**References.**

- `scripts/codex-fleet/full-bringup.sh`
- `scripts/codex-fleet/force-claim.sh`

### 67.5 Backlog (raw)

- Add `fleet-repo` selector CLI.
- Add per-repo profile under ~/.config/codex-fleet/.
- Support multiple repos in one fleet bringup.
- Add per-repo Colony namespace.
- Add per-repo skill set.
- Add per-repo accounts allowlist.
- Add cross-repo plan dependency graph.
- Add 'fleet attach repo X' shortcut.
- Add per-repo overview window.
- Add per-repo throttles.

### 67.6 Open questions

- [ ] Should one fleet ever serve multiple repos simultaneously?
- [ ] What's the right Colony namespace strategy?

### 67.7 Cross-cutting dependencies

- Colony
- Bash bringup

### 67.8 Risk register

- Repo confusion under multi-repo.
- Namespace collisions.

### 67.9 Migration plan

1. Phase 1: profile.
2. Phase 2: selector.
3. Phase 3: multi-repo bringup.

### 67.10 Out of scope

- Becoming a repo manager.

---

## 68. Performance, Throughput & Backpressure

- slug: `performance`
- captain: unassigned
- budget: ~300 lines (soft cap)

### 68.1 Mission

Ensure the fleet scales gracefully under high task volume without overwhelming Colony, accounts, or hosts.

### 68.2 Current state

- Bringup defaults to 8 panes.
- No explicit backpressure between Colony and panes.

### 68.3 Pain points

1. Burst dispatch may saturate Colony API.
2. No throttle on per-account rates.

### 68.4 Improvement protocols

#### 68.4.1 Performance: define explicit ownership boundaries

- state: PROPOSED
- lane: subsystem owner

**Problem.** Concrete gap exists for this concern within the fleet.

**Hypothesis.** Closing the gap improves reliability and reviewer signal.

**Proposal.** Adopt the named pattern with explicit owners and acceptance criteria.

**Implementation steps.**

1. Document the concern in this section.
1. Author the supporting artifact (runbook, schema, probe, etc.).
1. Wire into CI or observability where applicable.
1. Refresh dashboards and skill prompts.

**Verification.** Confirm artifact exists and is referenced from this section.

**Acceptance criteria.**

- Artifact exists.
- Referenced in protocol.
- Owner named.

**Rollback.** Remove artifact; revert to prior behaviour.

**Risks.**

- Process overhead.
- Lock-in to current patterns.

**Metrics.**

- Adoption %
- Time-to-detect failures

**References.**

- `scripts/codex-fleet/force-claim.sh`

#### 68.4.2 Performance: instrument key paths with structured logs

- state: PROPOSED
- lane: subsystem owner

**Problem.** Concrete gap exists for this concern within the fleet.

**Hypothesis.** Closing the gap improves reliability and reviewer signal.

**Proposal.** Adopt the named pattern with explicit owners and acceptance criteria.

**Implementation steps.**

1. Document the concern in this section.
1. Author the supporting artifact (runbook, schema, probe, etc.).
1. Wire into CI or observability where applicable.
1. Refresh dashboards and skill prompts.

**Verification.** Confirm artifact exists and is referenced from this section.

**Acceptance criteria.**

- Artifact exists.
- Referenced in protocol.
- Owner named.

**Rollback.** Remove artifact; revert to prior behaviour.

**Risks.**

- Process overhead.
- Lock-in to current patterns.

**Metrics.**

- Adoption %
- Time-to-detect failures

**References.**

- `scripts/codex-fleet/force-claim.sh`

### 68.5 Backlog (raw)

- Add adaptive poll interval based on queue depth.
- Add per-account rate limiter.
- Add fleet-wide concurrency cap.
- Add Colony API circuit-breaker.
- Add CPU/RAM probes per pane.
- Add disk-io probe per pane.
- Add 'too many failures' panic mode.
- Add startup-time budget.
- Add bringup parallelism knob.
- Add per-script perf budget.

### 68.6 Open questions

- [ ] What is our target tasks/hour at 8 panes?
- [ ] What is the maximum supported pane count?

### 68.7 Cross-cutting dependencies

- Colony
- Bash bringup

### 68.8 Risk register

- Backpressure flips into starvation.
- Throttles hide upstream bugs.

### 68.9 Migration plan

1. Phase 1: measurement.
2. Phase 2: throttle.
3. Phase 3: adaptive.

### 68.10 Out of scope

- Distributed multi-host fleets right away.

---

## 69. Resilience, Failure Modes & Chaos

- slug: `resilience`
- captain: unassigned
- budget: ~300 lines (soft cap)

### 69.1 Mission

Catalogue failure modes and prove the fleet survives them.

### 69.2 Current state

- Self-healing daemons cover many cases.
- No formal chaos harness.

### 69.3 Pain points

1. Unknown unknowns surface only in production.

### 69.4 Improvement protocols

#### 69.4.1 Resilience: define explicit ownership boundaries

- state: PROPOSED
- lane: subsystem owner

**Problem.** Concrete gap exists for this concern within the fleet.

**Hypothesis.** Closing the gap improves reliability and reviewer signal.

**Proposal.** Adopt the named pattern with explicit owners and acceptance criteria.

**Implementation steps.**

1. Document the concern in this section.
1. Author the supporting artifact (runbook, schema, probe, etc.).
1. Wire into CI or observability where applicable.
1. Refresh dashboards and skill prompts.

**Verification.** Confirm artifact exists and is referenced from this section.

**Acceptance criteria.**

- Artifact exists.
- Referenced in protocol.
- Owner named.

**Rollback.** Remove artifact; revert to prior behaviour.

**Risks.**

- Process overhead.
- Lock-in to current patterns.

**Metrics.**

- Adoption %
- Time-to-detect failures

**References.**

- `scripts/codex-fleet/`

#### 69.4.2 Resilience: instrument key paths with structured logs

- state: PROPOSED
- lane: subsystem owner

**Problem.** Concrete gap exists for this concern within the fleet.

**Hypothesis.** Closing the gap improves reliability and reviewer signal.

**Proposal.** Adopt the named pattern with explicit owners and acceptance criteria.

**Implementation steps.**

1. Document the concern in this section.
1. Author the supporting artifact (runbook, schema, probe, etc.).
1. Wire into CI or observability where applicable.
1. Refresh dashboards and skill prompts.

**Verification.** Confirm artifact exists and is referenced from this section.

**Acceptance criteria.**

- Artifact exists.
- Referenced in protocol.
- Owner named.

**Rollback.** Remove artifact; revert to prior behaviour.

**Risks.**

- Process overhead.
- Lock-in to current patterns.

**Metrics.**

- Adoption %
- Time-to-detect failures

**References.**

- `scripts/codex-fleet/`

### 69.5 Backlog (raw)

- Add chaos toggles: random pane kill, network blip, disk full.
- Add weekly chaos run with summary report.
- Add documented runbook per failure mode.
- Add postmortem template under docs/.
- Add SLA targets per failure mode.
- Add 'panic button' that pauses dispatch.
- Add safe restart procedure.
- Add 'cold start' time budget.
- Add 'warm start' time budget.
- Add 'maintenance mode' for downtime windows.

### 69.6 Open questions

- [ ] Where do we host postmortems?
- [ ] Who runs chaos days?

### 69.7 Cross-cutting dependencies

- CI
- Operators

### 69.8 Risk register

- Chaos runs disrupt real work.
- Postmortems become blame games.

### 69.9 Migration plan

1. Phase 1: failure catalog.
2. Phase 2: chaos toggles.
3. Phase 3: chaos cadence.

### 69.10 Out of scope

- Becoming a chaos-engineering platform.

---

## 70. Cost, Quota & Rate-Limit Management

- slug: `cost-quota`
- captain: unassigned
- budget: ~300 lines (soft cap)

### 70.1 Mission

Maximise useful work per token while staying inside per-account quotas.

### 70.2 Current state

- token-meter.sh surfaces per-account burn.
- cap-swap-daemon rotates capped accounts.
- No cost dashboard.

### 70.3 Pain points

1. Cannot answer 'cost per merged PR' today.
2. Quotas are managed reactively, not predictively.

### 70.4 Improvement protocols

#### 70.4.1 Cost/Quota: define explicit ownership boundaries

- state: PROPOSED
- lane: subsystem owner

**Problem.** Concrete gap exists for this concern within the fleet.

**Hypothesis.** Closing the gap improves reliability and reviewer signal.

**Proposal.** Adopt the named pattern with explicit owners and acceptance criteria.

**Implementation steps.**

1. Document the concern in this section.
1. Author the supporting artifact (runbook, schema, probe, etc.).
1. Wire into CI or observability where applicable.
1. Refresh dashboards and skill prompts.

**Verification.** Confirm artifact exists and is referenced from this section.

**Acceptance criteria.**

- Artifact exists.
- Referenced in protocol.
- Owner named.

**Rollback.** Remove artifact; revert to prior behaviour.

**Risks.**

- Process overhead.
- Lock-in to current patterns.

**Metrics.**

- Adoption %
- Time-to-detect failures

**References.**

- `scripts/codex-fleet/token-meter.sh`
- `scripts/codex-fleet/cap-swap-daemon.sh`

#### 70.4.2 Cost/Quota: instrument key paths with structured logs

- state: PROPOSED
- lane: subsystem owner

**Problem.** Concrete gap exists for this concern within the fleet.

**Hypothesis.** Closing the gap improves reliability and reviewer signal.

**Proposal.** Adopt the named pattern with explicit owners and acceptance criteria.

**Implementation steps.**

1. Document the concern in this section.
1. Author the supporting artifact (runbook, schema, probe, etc.).
1. Wire into CI or observability where applicable.
1. Refresh dashboards and skill prompts.

**Verification.** Confirm artifact exists and is referenced from this section.

**Acceptance criteria.**

- Artifact exists.
- Referenced in protocol.
- Owner named.

**Rollback.** Remove artifact; revert to prior behaviour.

**Risks.**

- Process overhead.
- Lock-in to current patterns.

**Metrics.**

- Adoption %
- Time-to-detect failures

**References.**

- `scripts/codex-fleet/token-meter.sh`
- `scripts/codex-fleet/cap-swap-daemon.sh`

### 70.5 Backlog (raw)

- Add cost-per-task metric.
- Add cost-per-merged-PR metric.
- Add forecast model for cap exhaustion.
- Add per-plan cost ceiling.
- Add throttle when cost trend exceeds budget.
- Add cost report email opt-in.
- Add 'cheap mode' that prefers smaller model variants.
- Add 'expensive mode' override for critical lanes.
- Add cost log audit trail.
- Add per-skill cost weighting.

### 70.6 Open questions

- [ ] Do we expose cost data publicly?
- [ ] Do we adjust pricing assumptions periodically?

### 70.7 Cross-cutting dependencies

- token-meter.sh
- Colony

### 70.8 Risk register

- Cost data inaccuracy.
- Privacy of cost data.

### 70.9 Migration plan

1. Phase 1: metric.
2. Phase 2: forecast.
3. Phase 3: throttle.

### 70.10 Out of scope

- Becoming a billing system.

---

## 71. UI/UX & Accessibility (tmux + future GUI)

- slug: `ui-ux`
- captain: unassigned
- budget: ~300 lines (soft cap)

### 71.1 Mission

Make the iOS-style tmux chrome accessible and pleasant to live with; plan a future GUI dashboard.

### 71.2 Current state

- style-tabs, watcher-board, animations land an iOS-style chrome.
- fleet-ui crate ships shared primitives.
- No alternative GUI exists.

### 71.3 Pain points

1. Animations consume terminal CPU.
2. Limited keyboard accessibility patterns documented.
3. No screen-reader friendly mode.

### 71.4 Improvement protocols

#### 71.4.1 UI/UX: define explicit ownership boundaries

- state: PROPOSED
- lane: subsystem owner

**Problem.** Concrete gap exists for this concern within the fleet.

**Hypothesis.** Closing the gap improves reliability and reviewer signal.

**Proposal.** Adopt the named pattern with explicit owners and acceptance criteria.

**Implementation steps.**

1. Document the concern in this section.
1. Author the supporting artifact (runbook, schema, probe, etc.).
1. Wire into CI or observability where applicable.
1. Refresh dashboards and skill prompts.

**Verification.** Confirm artifact exists and is referenced from this section.

**Acceptance criteria.**

- Artifact exists.
- Referenced in protocol.
- Owner named.

**Rollback.** Remove artifact; revert to prior behaviour.

**Risks.**

- Process overhead.
- Lock-in to current patterns.

**Metrics.**

- Adoption %
- Time-to-detect failures

**References.**

- `rust/fleet-ui/`
- `scripts/codex-fleet/style-tabs.sh`

#### 71.4.2 UI/UX: instrument key paths with structured logs

- state: PROPOSED
- lane: subsystem owner

**Problem.** Concrete gap exists for this concern within the fleet.

**Hypothesis.** Closing the gap improves reliability and reviewer signal.

**Proposal.** Adopt the named pattern with explicit owners and acceptance criteria.

**Implementation steps.**

1. Document the concern in this section.
1. Author the supporting artifact (runbook, schema, probe, etc.).
1. Wire into CI or observability where applicable.
1. Refresh dashboards and skill prompts.

**Verification.** Confirm artifact exists and is referenced from this section.

**Acceptance criteria.**

- Artifact exists.
- Referenced in protocol.
- Owner named.

**Rollback.** Remove artifact; revert to prior behaviour.

**Risks.**

- Process overhead.
- Lock-in to current patterns.

**Metrics.**

- Adoption %
- Time-to-detect failures

**References.**

- `rust/fleet-ui/`
- `scripts/codex-fleet/style-tabs.sh`

### 71.5 Backlog (raw)

- Add a quiet mode (no animations).
- Add accessibility audit doc.
- Add keyboard shortcut cheat sheet.
- Add 'minimal' chrome variant.
- Add color-blind safe palette.
- Add per-pane title customisation.
- Add adaptive layout for narrow terminals.
- Plan a TUI ratatui-based dashboard.
- Plan a webview dashboard.
- Plan a mobile companion read-only view.

### 71.6 Open questions

- [ ] What is the floor terminal size we support?
- [ ] Do we expose a JSON API for external dashboards?

### 71.7 Cross-cutting dependencies

- tmux
- fleet-ui crate

### 71.8 Risk register

- Chrome breakage on new tmux versions.
- Accessibility regressions.

### 71.9 Migration plan

1. Phase 1: quiet mode.
2. Phase 2: accessibility.
3. Phase 3: TUI.

### 71.10 Out of scope

- Building a desktop app immediately.

---

## 72. Design Tokens & Theming

- slug: `design-tokens`
- captain: unassigned
- budget: ~300 lines (soft cap)

### 72.1 Mission

Promote the iOS-style design vocabulary to first-class tokens used across crates and scripts.

### 72.2 Current state

- docs/design-tokens.md sketches the vocabulary.
- Colors and spacings live inline across fleet-ui and shell.

### 72.3 Pain points

1. Tokens drift across modules.
2. Hard to reskin or theme.

### 72.4 Improvement protocols

#### 72.4.1 Design Tokens: define explicit ownership boundaries

- state: PROPOSED
- lane: subsystem owner

**Problem.** Concrete gap exists for this concern within the fleet.

**Hypothesis.** Closing the gap improves reliability and reviewer signal.

**Proposal.** Adopt the named pattern with explicit owners and acceptance criteria.

**Implementation steps.**

1. Document the concern in this section.
1. Author the supporting artifact (runbook, schema, probe, etc.).
1. Wire into CI or observability where applicable.
1. Refresh dashboards and skill prompts.

**Verification.** Confirm artifact exists and is referenced from this section.

**Acceptance criteria.**

- Artifact exists.
- Referenced in protocol.
- Owner named.

**Rollback.** Remove artifact; revert to prior behaviour.

**Risks.**

- Process overhead.
- Lock-in to current patterns.

**Metrics.**

- Adoption %
- Time-to-detect failures

**References.**

- `docs/design-tokens.md`
- `rust/fleet-ui/`

#### 72.4.2 Design Tokens: instrument key paths with structured logs

- state: PROPOSED
- lane: subsystem owner

**Problem.** Concrete gap exists for this concern within the fleet.

**Hypothesis.** Closing the gap improves reliability and reviewer signal.

**Proposal.** Adopt the named pattern with explicit owners and acceptance criteria.

**Implementation steps.**

1. Document the concern in this section.
1. Author the supporting artifact (runbook, schema, probe, etc.).
1. Wire into CI or observability where applicable.
1. Refresh dashboards and skill prompts.

**Verification.** Confirm artifact exists and is referenced from this section.

**Acceptance criteria.**

- Artifact exists.
- Referenced in protocol.
- Owner named.

**Rollback.** Remove artifact; revert to prior behaviour.

**Risks.**

- Process overhead.
- Lock-in to current patterns.

**Metrics.**

- Adoption %
- Time-to-detect failures

**References.**

- `docs/design-tokens.md`
- `rust/fleet-ui/`

### 72.5 Backlog (raw)

- Centralise tokens in fleet-ui::tokens.
- Generate bash color exports from rust tokens.
- Add light/dark theme.
- Add high-contrast theme.
- Add seasonal theme toggle.
- Add per-tenant brand colors.
- Add 'show tokens' debug command.
- Add token version stamp on chrome.
- Lint use of inline hex values.
- Document token semantics.

### 72.6 Open questions

- [ ] Do we ship one or many palettes?
- [ ] Do we adopt a known design system (e.g., Apple HIG) explicitly?

### 72.7 Cross-cutting dependencies

- fleet-ui
- Shell color helpers

### 72.8 Risk register

- Color regressions break readability.

### 72.9 Migration plan

1. Phase 1: centralise.
2. Phase 2: theme.
3. Phase 3: lint.

### 72.10 Out of scope

- Replacing tmux's color model.

---

## 73. Internationalization & Localization

- slug: `i18n`
- captain: unassigned
- budget: ~300 lines (soft cap)

### 73.1 Mission

Plan for non-English operators and accessibility users.

### 73.2 Current state

- All UI strings are English.
- No locale switching.

### 73.3 Pain points

1. Operators in non-English contexts must guess strings.

### 73.4 Improvement protocols

#### 73.4.1 i18n: define explicit ownership boundaries

- state: PROPOSED
- lane: subsystem owner

**Problem.** Concrete gap exists for this concern within the fleet.

**Hypothesis.** Closing the gap improves reliability and reviewer signal.

**Proposal.** Adopt the named pattern with explicit owners and acceptance criteria.

**Implementation steps.**

1. Document the concern in this section.
1. Author the supporting artifact (runbook, schema, probe, etc.).
1. Wire into CI or observability where applicable.
1. Refresh dashboards and skill prompts.

**Verification.** Confirm artifact exists and is referenced from this section.

**Acceptance criteria.**

- Artifact exists.
- Referenced in protocol.
- Owner named.

**Rollback.** Remove artifact; revert to prior behaviour.

**Risks.**

- Process overhead.
- Lock-in to current patterns.

**Metrics.**

- Adoption %
- Time-to-detect failures

**References.**

- `rust/fleet-ui/`
- `scripts/codex-fleet/`

#### 73.4.2 i18n: instrument key paths with structured logs

- state: PROPOSED
- lane: subsystem owner

**Problem.** Concrete gap exists for this concern within the fleet.

**Hypothesis.** Closing the gap improves reliability and reviewer signal.

**Proposal.** Adopt the named pattern with explicit owners and acceptance criteria.

**Implementation steps.**

1. Document the concern in this section.
1. Author the supporting artifact (runbook, schema, probe, etc.).
1. Wire into CI or observability where applicable.
1. Refresh dashboards and skill prompts.

**Verification.** Confirm artifact exists and is referenced from this section.

**Acceptance criteria.**

- Artifact exists.
- Referenced in protocol.
- Owner named.

**Rollback.** Remove artifact; revert to prior behaviour.

**Risks.**

- Process overhead.
- Lock-in to current patterns.

**Metrics.**

- Adoption %
- Time-to-detect failures

**References.**

- `rust/fleet-ui/`
- `scripts/codex-fleet/`

### 73.5 Backlog (raw)

- Extract user-facing strings to a catalog.
- Adopt fluent or gettext.
- Add right-to-left layout consideration.
- Add language picker.
- Document translator workflow.
- Add machine-translation fallback opt-in.
- Add per-locale date/time formatting.
- Add per-locale number formatting.
- Add multi-locale CI render check.
- Add accessibility-i18n cross-check.

### 73.6 Open questions

- [ ] Which languages do we prioritise after English?
- [ ] Do we accept community-contributed translations?

### 73.7 Cross-cutting dependencies

- fleet-ui
- Docs

### 73.8 Risk register

- Translation rot.

### 73.9 Migration plan

1. Phase 1: catalog.
2. Phase 2: backend.
3. Phase 3: translations.

### 73.10 Out of scope

- Becoming a translation platform.

---

## 74. Versioning, Backwards Compatibility & Deprecation

- slug: `versioning`
- captain: unassigned
- budget: ~300 lines (soft cap)

### 74.1 Mission

Adopt semver across crates and define a deprecation policy that the fleet honours.

### 74.2 Current state

- Crates have no formal semver discipline.
- Scripts are versioned via repo tag only.

### 74.3 Pain points

1. Hard to know whether a change breaks downstream.

### 74.4 Improvement protocols

#### 74.4.1 Versioning: define explicit ownership boundaries

- state: PROPOSED
- lane: subsystem owner

**Problem.** Concrete gap exists for this concern within the fleet.

**Hypothesis.** Closing the gap improves reliability and reviewer signal.

**Proposal.** Adopt the named pattern with explicit owners and acceptance criteria.

**Implementation steps.**

1. Document the concern in this section.
1. Author the supporting artifact (runbook, schema, probe, etc.).
1. Wire into CI or observability where applicable.
1. Refresh dashboards and skill prompts.

**Verification.** Confirm artifact exists and is referenced from this section.

**Acceptance criteria.**

- Artifact exists.
- Referenced in protocol.
- Owner named.

**Rollback.** Remove artifact; revert to prior behaviour.

**Risks.**

- Process overhead.
- Lock-in to current patterns.

**Metrics.**

- Adoption %
- Time-to-detect failures

**References.**

- `rust/`
- `scripts/codex-fleet/`

#### 74.4.2 Versioning: instrument key paths with structured logs

- state: PROPOSED
- lane: subsystem owner

**Problem.** Concrete gap exists for this concern within the fleet.

**Hypothesis.** Closing the gap improves reliability and reviewer signal.

**Proposal.** Adopt the named pattern with explicit owners and acceptance criteria.

**Implementation steps.**

1. Document the concern in this section.
1. Author the supporting artifact (runbook, schema, probe, etc.).
1. Wire into CI or observability where applicable.
1. Refresh dashboards and skill prompts.

**Verification.** Confirm artifact exists and is referenced from this section.

**Acceptance criteria.**

- Artifact exists.
- Referenced in protocol.
- Owner named.

**Rollback.** Remove artifact; revert to prior behaviour.

**Risks.**

- Process overhead.
- Lock-in to current patterns.

**Metrics.**

- Adoption %
- Time-to-detect failures

**References.**

- `rust/`
- `scripts/codex-fleet/`

### 74.5 Backlog (raw)

- Adopt cargo-semver-checks.
- Per-crate CHANGELOG.
- Document deprecation timeline (90 days).
- Add deprecation warnings to scripts.
- Add 'min-fleet-version' field in plan.json.
- Add upgrade guide per minor.
- Add release-notes generator.
- Add 'breaking change' label in PRs.
- Add 'compat shim' pattern docs.
- Add 'sunset' tag for retired features.

### 74.6 Open questions

- [ ] Do we adopt calver for the umbrella project?
- [ ] How do we synchronise crate versions in the workspace?

### 74.7 Cross-cutting dependencies

- Cargo
- GitHub

### 74.8 Risk register

- Premature breaking changes.

### 74.9 Migration plan

1. Phase 1: cargo-semver.
2. Phase 2: changelogs.
3. Phase 3: deprecation pipeline.

### 74.10 Out of scope

- Forking dependencies for compatibility.

---

## 75. Glossary & Conventions

- slug: `glossary`
- captain: unassigned
- budget: ~300 lines (soft cap)

### 75.1 Mission

A single place to define the fleet vocabulary so docs and scripts stay consistent.

### 75.2 Current state

- No central glossary.
- Terms scattered across README, AGENTS.md, docs/.

### 75.3 Pain points

1. New contributors guess at meanings.

### 75.4 Improvement protocols

#### 75.4.1 Glossary: define explicit ownership boundaries

- state: PROPOSED
- lane: subsystem owner

**Problem.** Concrete gap exists for this concern within the fleet.

**Hypothesis.** Closing the gap improves reliability and reviewer signal.

**Proposal.** Adopt the named pattern with explicit owners and acceptance criteria.

**Implementation steps.**

1. Document the concern in this section.
1. Author the supporting artifact (runbook, schema, probe, etc.).
1. Wire into CI or observability where applicable.
1. Refresh dashboards and skill prompts.

**Verification.** Confirm artifact exists and is referenced from this section.

**Acceptance criteria.**

- Artifact exists.
- Referenced in protocol.
- Owner named.

**Rollback.** Remove artifact; revert to prior behaviour.

**Risks.**

- Process overhead.
- Lock-in to current patterns.

**Metrics.**

- Adoption %
- Time-to-detect failures

**References.**

- `docs/`
- `README.md`
- `AGENTS.md`

#### 75.4.2 Glossary: instrument key paths with structured logs

- state: PROPOSED
- lane: subsystem owner

**Problem.** Concrete gap exists for this concern within the fleet.

**Hypothesis.** Closing the gap improves reliability and reviewer signal.

**Proposal.** Adopt the named pattern with explicit owners and acceptance criteria.

**Implementation steps.**

1. Document the concern in this section.
1. Author the supporting artifact (runbook, schema, probe, etc.).
1. Wire into CI or observability where applicable.
1. Refresh dashboards and skill prompts.

**Verification.** Confirm artifact exists and is referenced from this section.

**Acceptance criteria.**

- Artifact exists.
- Referenced in protocol.
- Owner named.

**Rollback.** Remove artifact; revert to prior behaviour.

**Risks.**

- Process overhead.
- Lock-in to current patterns.

**Metrics.**

- Adoption %
- Time-to-detect failures

**References.**

- `docs/`
- `README.md`
- `AGENTS.md`

### 75.5 Backlog (raw)

- Bootstrap glossary with: Colony, OpenSpec, Guardex, OMX, RTK, fff, lane, agent branch, plan, wave, claim, pane, conductor, supervisor, worker, dispatch, cap, probe, plan tree.
- Add canonical spellings and case conventions.
- Add anti-glossary (terms we don't use).
- Add language tone guide.
- Add per-term examples.
- Add per-term anti-examples.
- Add references to source files for each term.
- Add per-term 'origin' note.
- Add per-term deprecation flag.
- Add per-term translation hints.

### 75.6 Open questions

- [ ] Do we link the glossary from the README front page?

### 75.7 Cross-cutting dependencies

- docs/future/

### 75.8 Risk register

- Glossary churn confuses readers.

### 75.9 Migration plan

1. Phase 1: seed.
2. Phase 2: enforce.
3. Phase 3: translate.

### 75.10 Out of scope

- Building a dictionary product.

---

## 76. Risk Register (master)

- slug: `risk-register`
- captain: unassigned
- budget: ~300 lines (soft cap)

### 76.1 Mission

Top-down view of the largest risks across all subsystems.

### 76.2 Current state

- Risks live inline in each section.
- No master aggregation.

### 76.3 Pain points

1. Operators cannot see the full risk surface in one place.

### 76.4 Improvement protocols

#### 76.4.1 Risk Register: define explicit ownership boundaries

- state: PROPOSED
- lane: subsystem owner

**Problem.** Concrete gap exists for this concern within the fleet.

**Hypothesis.** Closing the gap improves reliability and reviewer signal.

**Proposal.** Adopt the named pattern with explicit owners and acceptance criteria.

**Implementation steps.**

1. Document the concern in this section.
1. Author the supporting artifact (runbook, schema, probe, etc.).
1. Wire into CI or observability where applicable.
1. Refresh dashboards and skill prompts.

**Verification.** Confirm artifact exists and is referenced from this section.

**Acceptance criteria.**

- Artifact exists.
- Referenced in protocol.
- Owner named.

**Rollback.** Remove artifact; revert to prior behaviour.

**Risks.**

- Process overhead.
- Lock-in to current patterns.

**Metrics.**

- Adoption %
- Time-to-detect failures

**References.**

- `docs/future/`

#### 76.4.2 Risk Register: instrument key paths with structured logs

- state: PROPOSED
- lane: subsystem owner

**Problem.** Concrete gap exists for this concern within the fleet.

**Hypothesis.** Closing the gap improves reliability and reviewer signal.

**Proposal.** Adopt the named pattern with explicit owners and acceptance criteria.

**Implementation steps.**

1. Document the concern in this section.
1. Author the supporting artifact (runbook, schema, probe, etc.).
1. Wire into CI or observability where applicable.
1. Refresh dashboards and skill prompts.

**Verification.** Confirm artifact exists and is referenced from this section.

**Acceptance criteria.**

- Artifact exists.
- Referenced in protocol.
- Owner named.

**Rollback.** Remove artifact; revert to prior behaviour.

**Risks.**

- Process overhead.
- Lock-in to current patterns.

**Metrics.**

- Adoption %
- Time-to-detect failures

**References.**

- `docs/future/`

### 76.5 Backlog (raw)

- Master register table (id, severity, likelihood, owner, mitigation).
- Quarterly risk review.
- Risk burn-down chart.
- Risk acceptance template.
- Risk closure template.
- Risk source rate audit.
- Risk-to-incident linkage.
- Risk training material.
- Risk-related drill playbook.
- Risk transfer policy (vendor risks).

### 76.6 Open questions

- [ ] Who is accountable for the master register?
- [ ] How do we anonymise sensitive risks?

### 76.7 Cross-cutting dependencies

- Risk owners across all sections.

### 76.8 Risk register

- Register itself becomes a chore.

### 76.9 Migration plan

1. Phase 1: aggregate.
2. Phase 2: review.
3. Phase 3: instrument.

### 76.10 Out of scope

- Replacing enterprise GRC tooling.

---

## 77. Roadmap & Milestones

- slug: `roadmap`
- captain: unassigned
- budget: ~300 lines (soft cap)

### 77.1 Mission

Sequence the improvements above into a credible plan of milestones.

### 77.2 Current state

- No explicit roadmap.

### 77.3 Pain points

1. Stakeholders cannot anticipate when an improvement will land.

### 77.4 Improvement protocols

#### 77.4.1 Roadmap: define explicit ownership boundaries

- state: PROPOSED
- lane: subsystem owner

**Problem.** Concrete gap exists for this concern within the fleet.

**Hypothesis.** Closing the gap improves reliability and reviewer signal.

**Proposal.** Adopt the named pattern with explicit owners and acceptance criteria.

**Implementation steps.**

1. Document the concern in this section.
1. Author the supporting artifact (runbook, schema, probe, etc.).
1. Wire into CI or observability where applicable.
1. Refresh dashboards and skill prompts.

**Verification.** Confirm artifact exists and is referenced from this section.

**Acceptance criteria.**

- Artifact exists.
- Referenced in protocol.
- Owner named.

**Rollback.** Remove artifact; revert to prior behaviour.

**Risks.**

- Process overhead.
- Lock-in to current patterns.

**Metrics.**

- Adoption %
- Time-to-detect failures

**References.**

- `docs/future/`

#### 77.4.2 Roadmap: instrument key paths with structured logs

- state: PROPOSED
- lane: subsystem owner

**Problem.** Concrete gap exists for this concern within the fleet.

**Hypothesis.** Closing the gap improves reliability and reviewer signal.

**Proposal.** Adopt the named pattern with explicit owners and acceptance criteria.

**Implementation steps.**

1. Document the concern in this section.
1. Author the supporting artifact (runbook, schema, probe, etc.).
1. Wire into CI or observability where applicable.
1. Refresh dashboards and skill prompts.

**Verification.** Confirm artifact exists and is referenced from this section.

**Acceptance criteria.**

- Artifact exists.
- Referenced in protocol.
- Owner named.

**Rollback.** Remove artifact; revert to prior behaviour.

**Risks.**

- Process overhead.
- Lock-in to current patterns.

**Metrics.**

- Adoption %
- Time-to-detect failures

**References.**

- `docs/future/`

### 77.5 Backlog (raw)

- Milestone M1: meta-protocol + governance live.
- Milestone M2: bash hygiene baseline.
- Milestone M3: rust crate hygiene baseline.
- Milestone M4: observability MVP.
- Milestone M5: self-healing SLO.
- Milestone M6: security hardening.
- Milestone M7: multi-repo support.
- Milestone M8: cost dashboard.
- Milestone M9: i18n MVP.
- Milestone M10: GA polish.

### 77.6 Open questions

- [ ] Do we commit to dates or to themes?
- [ ] Who owns roadmap updates?

### 77.7 Cross-cutting dependencies

- All sections.

### 77.8 Risk register

- Roadmap as wishlist.

### 77.9 Migration plan

1. Phase 1: themes.
2. Phase 2: dates.
3. Phase 3: review cadence.

### 77.10 Out of scope

- Becoming a project management product.

---

## 78. Appendix: Reference Configs & Templates

- slug: `appendix`
- captain: unassigned
- budget: ~300 lines (soft cap)

### 78.1 Mission

Park reusable templates referenced from above so each section stays compact.

### 78.2 Current state

- Templates live inline today.

### 78.3 Pain points

1. Duplicate templates drift.

### 78.4 Improvement protocols

#### 78.4.1 Appendix: define explicit ownership boundaries

- state: PROPOSED
- lane: subsystem owner

**Problem.** Concrete gap exists for this concern within the fleet.

**Hypothesis.** Closing the gap improves reliability and reviewer signal.

**Proposal.** Adopt the named pattern with explicit owners and acceptance criteria.

**Implementation steps.**

1. Document the concern in this section.
1. Author the supporting artifact (runbook, schema, probe, etc.).
1. Wire into CI or observability where applicable.
1. Refresh dashboards and skill prompts.

**Verification.** Confirm artifact exists and is referenced from this section.

**Acceptance criteria.**

- Artifact exists.
- Referenced in protocol.
- Owner named.

**Rollback.** Remove artifact; revert to prior behaviour.

**Risks.**

- Process overhead.
- Lock-in to current patterns.

**Metrics.**

- Adoption %
- Time-to-detect failures

**References.**

- `docs/future/`

#### 78.4.2 Appendix: instrument key paths with structured logs

- state: PROPOSED
- lane: subsystem owner

**Problem.** Concrete gap exists for this concern within the fleet.

**Hypothesis.** Closing the gap improves reliability and reviewer signal.

**Proposal.** Adopt the named pattern with explicit owners and acceptance criteria.

**Implementation steps.**

1. Document the concern in this section.
1. Author the supporting artifact (runbook, schema, probe, etc.).
1. Wire into CI or observability where applicable.
1. Refresh dashboards and skill prompts.

**Verification.** Confirm artifact exists and is referenced from this section.

**Acceptance criteria.**

- Artifact exists.
- Referenced in protocol.
- Owner named.

**Rollback.** Remove artifact; revert to prior behaviour.

**Risks.**

- Process overhead.
- Lock-in to current patterns.

**Metrics.**

- Adoption %
- Time-to-detect failures

**References.**

- `docs/future/`

### 78.5 Backlog (raw)

- Improvement entry template.
- ADR template.
- Review file template.
- Postmortem template.
- Runbook template.
- SLO template.
- Cost report template.
- Chaos report template.
- Skill changelog template.
- Glossary entry template.

### 78.6 Open questions

- [ ] Do we publish templates to a separate repo?

### 78.7 Cross-cutting dependencies

- docs/future/

### 78.8 Risk register

- Template proliferation.

### 78.9 Migration plan

1. Phase 1: extract.
2. Phase 2: link.
3. Phase 3: dedupe.

### 78.10 Out of scope

- Becoming a templating engine.

---

## Glossary (seed)

- **Colony** — External coordination service exposing task graph, claims, and messages used by the fleet.
- **OpenSpec** — Spec-driven workflow that lives under `openspec/` and gates change-driven repo work.
- **Guardex** — Multi-agent execution contract defined in AGENTS.md governing isolation, claims, and completion.
- **OMX** — Fallback coordination state under `.omx/state` and `.omx/notepad.md` when Colony is unavailable.
- **RTK** — Shell command compression and discovery helper; preferred for noisy shell discovery.
- **fff** — MCP file search server; preferred over default tools for file search.
- **Lane** — A unit of work owned by a particular agent or subsystem (scripts lane, rust lane, docs lane, etc.).
- **Agent branch** — A dedicated `agent/*` branch and worktree per task to enforce isolation.
- **Plan** — An OpenSpec plan workspace under `openspec/plans/<slug>/`.
- **Plan tree** — Hierarchical view of a plan's subtasks rendered by `fleet-plan-tree`.
- **Wave** — A grouping of related subtasks consumed by the fleet in dispatch order.
- **Claim** — An ownership lock recorded in Colony before editing files.
- **Pane** — A tmux pane hosting one Codex worker.
- **Conductor** — Operator-facing pane hosting an interactive Claude that supervises daemons.
- **Supervisor** — Daemon that keeps a subset of fleet behaviour healthy (claim-release, cap-swap, etc.).
- **Worker** — Codex CLI worker running inside a tmux pane on its own account auth.
- **Dispatch** — The act of handing a Colony-ready subtask to an idle pane.
- **Cap** — An account that has hit its usage limit and cannot accept new dispatch.
- **Probe** — A lightweight `codex exec` call used to determine account health.
- **Skill** — A Claude Code asset under `skills/codex-fleet/` providing trigger phrases and routing.
- **Spec** — An openspec/specs/ document defining behaviour invariants.
- **Change** — An openspec/changes/<slug>/ artifact set describing a proposed change.
- **ADR** — Architecture Decision Record under `docs/future/decisions/`.

---

## Environment Variable Registry

| Variable | Default | Owner | Purpose |
|----------|---------|-------|---------|
| `CODEX_FLEET_REPO_ROOT` | `repo root` | full-bringup.sh | Plan source root. |
| `CODEX_FLEET_AGENT_NAME` | `(unset)` | worker panes | Identifies the agent owning a worktree. |
| `CODEX_FLEET_SUPERVISOR` | `0` | full-bringup.sh | Enable legacy kitty supervisor. |
| `CODEX_FLEET_CONDUCTOR` | `1` | conductor.sh | Enable conductor pane. |
| `FORCE_CLAIM_REPO` | `repo root` | force-claim.sh | Repo whose Colony plans force-claim dispatches from. |
| `GUARDEX_ON` | `1` | AGENTS.md | Toggle Guardex multi-agent contract. |
| `FLEET_LOG_LEVEL` | `info` | scripts (planned) | Log verbosity. |
| `FLEET_DRY_RUN` | `0` | scripts (planned) | Dry-run mode. |
| `FLEET_CONFIG_FILE` | `fleet-config.toml` | scripts (planned) | Path to TOML config. |
| `FLEET_METRICS_DIR` | `.codex-fleet/metrics` | scripts (planned) | Where per-script tsv counters land. |
| `FLEET_LOG_DIR` | `.codex-fleet/logs` | scripts (planned) | Where structured logs land. |
| `FLEET_DAEMON_INTERVAL` | `varies` | daemons | Per-daemon poll cadence in seconds. |
| `FLEET_TMUX_SESSION` | `codex-fleet` | bringup | Session name for the main fleet tmux session. |
| `FLEET_TICKER_SESSION` | `fleet-ticker` | bringup | Session name for the ticker daemon session. |
| `FLEET_REVIEW_LANE_PANES` | `1` | review-queue | How many panes serve the review lane. |
| `FLEET_CHAOS_MODE` | `0` | chaos (planned) | Toggle chaos toggles for testing. |
| `FLEET_QUIET_CHROME` | `0` | ui (planned) | Disable animations for reduced CPU. |
| `FLEET_THEME` | `ios-default` | ui (planned) | Theme selector. |
| `FLEET_LOCALE` | `en-US` | ui (planned) | Locale for date/number formatting. |
| `FLEET_MIN_VERSION` | `(unset)` | plans (planned) | Required minimum fleet version for a plan. |

---

## Daemon Cadence Reference (current vs. targets)

| Daemon | Current cadence | Target SLO | Notes |
|--------|-----------------|------------|-------|
| `force-claim` | ~15s | p95 dispatch < 20s after Colony ready | Adaptive interval candidate. |
| `claim-release-supervisor` | ~60s | p95 release < 90s after pane idle | Could move to event-driven. |
| `cap-swap-daemon` | ~30s | Swap completes within 2 probe cycles | Probe via `codex exec`. |
| `stall-watcher` | ~30min | Rescue stranded claims within window | Wraps `colony rescue stranded --apply`. |
| `plan-watcher` | inotify-driven | Wave bump within 10s of change | Already low-latency. |
| `auto-reviewer` | on-demand | First-pass review under 5 min | Future cadence target. |
| `score-checkpoint` | per checkpoint | Score recorded synchronously | No retry storms. |
| `score-merged-pr` | on PR merge | Score within 5 min of merge | Hook off GitHub webhook eventually. |
| `fleet-tick-daemon` | 1s | Tick consistency >99% | CPU-cheap. |

---

## Quality Gates (composite checklist)

Before a section can move from PROPOSED to ACCEPTED, the captain must confirm:

1. The improvement cites at least one real path in `refs`.
2. The improvement does not duplicate an existing SHIPPED entry.
3. The improvement is scoped tightly enough to fit a single PR.
4. The improvement specifies a measurable acceptance criterion.
5. The improvement specifies a rollback path.
6. The improvement names at least one risk.
7. The improvement specifies at least one metric.
8. The improvement aligns with an existing or new milestone.
9. The improvement does not require a tool not yet in the dependency budget.
10. The improvement has a captain or volunteer.

Before ACCEPTED -> SCHEDULED:

1. An OpenSpec change is opened under `openspec/changes/<slug>/`.
2. The change includes proposal, spec, design, and tasks artifacts.
3. The change links back to this protocol entry via slug.
4. The change registers a Colony task with `task_plan_publish`.
5. The change captures verification gates per the section's `lane`.

Before SCHEDULED -> IN-PROGRESS:

1. A `gx branch start ...` worktree exists for the lane.
2. A Colony `task_claim_file` exists for each file to be touched.
3. A handoff `task_post` records `branch=...; task=...; blocker=none; next=...; evidence=...`.
4. Reviewers know the PR is incoming via Colony `task_message`.

Before IN-PROGRESS -> SHIPPED:

1. PR carries `PR #<n>` merged-state badge in `completed_summary`.
2. Sandbox worktree is pruned via `gx branch finish ... --cleanup`.
3. Per-crate CHANGELOG (if applicable) is updated.
4. Per-section captain refreshes the protocol entry state to SHIPPED.
5. `openspec validate --specs` passes for any touched specs.

---

## Mega Backlog

Future ideas not (yet) attached to a specific section. The captain of
this protocol periodically routes items to the right section.

- Adopt mise / asdf for tool version management.
- Replace install.sh with a Rust binary `fleetctl install`.
- Add `fleetctl doctor` to diagnose environment.
- Add `fleetctl probe` for ad-hoc account health.
- Add `fleetctl logs` for tailing structured logs.
- Add `fleetctl plans` for browsing OpenSpec plans.
- Add `fleetctl panes` for listing pane health.
- Add `fleetctl review` for triaging the review lane.
- Add `fleetctl claim` for manual claim operations.
- Add `fleetctl skill` for managing the Claude skill install.
- Add `fleetctl chaos` for orchestrated chaos drills.
- Add `fleetctl bench` for one-shot perf checks.
- Add `fleetctl cost` for cost reporting.
- Add `fleetctl theme` for switching chrome themes.
- Add `fleetctl locale` for switching language.
- Add a 'demo mode' that fakes Colony locally for tutorials.
- Add a 'replay mode' that runs a recorded session for postmortems.
- Add 'pause / resume' for full-fleet maintenance windows.
- Add 'soft drain' that lets in-flight tasks finish before shutdown.
- Add 'rebalance' for redistributing claims across panes.
- Add 'rolling restart' for fleet upgrade without downtime.
- Add 'canary lane' that runs new daemons for a subset of panes.
- Add 'tenant isolation' for serving multiple users on one fleet host.
- Add 'session save / restore' for persistent operator state.
- Add 'lite mode' for low-resource hosts.
- Add 'pro mode' with deeper telemetry and stricter checks.
- Add a public benchmark suite tracking fleet throughput over time.
- Add a public quality dashboard surfacing protocol state counts.
- Add an opt-in usage telemetry stream.
- Add per-pane history snapshots for audit.
- Add a 'compliance mode' enforcing extra security gates.
- Add a 'research mode' that disables auto-commit / auto-merge.
- Add a 'pair mode' that pins a Claude reviewer to every PR.
- Add a 'shadow mode' for running a new daemon alongside the old one.
- Add a 'forensics mode' for capturing every signal for one run.
- Add a 'minimal repro' generator from logs.
- Add a 'snapshot share' workflow for asking for help.
- Add a 'community contributions' guide.
- Add a 'plugin' API for third-party scripts.
- Add a 'webhook' surface for external integrations.
- Add a 'Slack' integration template.
- Add a 'Discord' integration template.
- Add an 'email' digest template.
- Add an 'RSS' feed of fleet events.
- Add a 'mobile push' adapter for critical alerts.
- Add a 'desktop notification' adapter.
- Add 'API tokens' for external dashboards.
- Add 'CLI completion' for bash/zsh/fish.
- Add a 'man page' generator for scripts.
- Add a 'help search' command that greps docs/future/.
- Add a 'feedback' command that opens a GitHub issue.
- Add 'auto-update' opt-in for install.sh symlinks.
- Add a 'self-test' command that runs the full preflight + sanity.
- Add a 'fleet snapshot' artifact for support escalations.
- Add 'release dry-run' that simulates publishing without side effects.
- Add 'feature flags' for risky new daemons.
- Add 'safe rollback' via signed snapshots.
- Add 'lint everything' make target combining shellcheck + clippy + markdownlint.
- Add 'docs everything' target that regenerates rustdoc, mermaid, and PROTOCOL HTML.
- Add 'lock file rotation' policy to keep deps fresh.
- Add 'monthly chore' tasks routed via Colony.
- Add 'quarterly retro' template under docs/future/retros/.
- Add 'release rehearsal' script.
- Add 'release rollback' script.
- Add 'release notes generator' tied to per-crate CHANGELOG.
- Add 'release postmortem' template.
- Add 'docs preview' workflow for PRs touching docs/future/.
- Add 'protocol diff' tool that summarises changes across two commits.
- Add 'protocol heatmap' showing state distribution by section.
- Add 'protocol cleanup' tool that flags stale PROPOSED entries.
- Add 'protocol export' to JSON for dashboards.
- Add 'protocol import' from JSON for batch updates.
- Add 'protocol metrics' exporter to prometheus.
- Add 'protocol explorer' TUI for browsing entries.
- Add 'protocol bot' that posts to PRs when relevant sections change.
- Add 'protocol owners.yaml' for richer captain metadata.
- Add 'protocol stale check' that flags entries unchanged in 90+ days.
- Add 'protocol consistency' check across sections (no contradictions).
- Add 'protocol cite' tool that auto-fills refs from `git grep`.
- Add 'protocol search index' precomputed under .codex-fleet/cache/.
- Add 'protocol minify' helper that strips PROPOSED entries for executive view.
- Add 'protocol expand' helper that hydrates each section from external sources.
- Add 'protocol audit' script that re-runs all CI checks locally.
- Add 'protocol bootstrap' script for setting up a new docs/future/ in another repo.
- Add 'protocol migration' to spec format if openspec evolves.

---

## Per-Section Deep Notes

Each section gets a deep-notes block here for content that doesn't fit
inline. These notes are advisory and may be moved into
`docs/future/deep/<slug>.md` once the section's budget is reached.

## Section-Status Snapshot

A one-line snapshot of every section in this protocol. Captains refresh
the status column at each review; the slug column is canonical and stable.

| # | Slug | Title | Captain | Status |
|---|------|-------|---------|--------|
| 1 | `meta-protocol` | Meta-Protocol & Governance | unassigned | PROPOSED |
| 2 | `repo-layout` | Repository Layout & Workspace Hygiene | unassigned | PROPOSED |
| 3 | `full-bringup` | Bash Layer: full-bringup.sh | unassigned | PROPOSED |
| 4 | `force-claim` | Bash Layer: force-claim.sh | unassigned | PROPOSED |
| 5 | `claim-release` | Bash Layer: claim-release-supervisor.sh | unassigned | PROPOSED |
| 6 | `cap-swap` | Bash Layer: cap-swap-daemon.sh | unassigned | PROPOSED |
| 7 | `stall-watcher` | Bash Layer: stall-watcher.sh | unassigned | PROPOSED |
| 8 | `conductor` | Bash Layer: conductor.sh | unassigned | PROPOSED |
| 9 | `plan-watcher` | Bash Layer: plan-watcher.sh | unassigned | PROPOSED |
| 10 | `review-queue` | Bash Layer: review-queue.sh | unassigned | PROPOSED |
| 11 | `review-pane-scanner` | Bash Layer: review-pane-scanner.sh | unassigned | PROPOSED |
| 12 | `auto-reviewer` | Bash Layer: auto-reviewer.sh | unassigned | PROPOSED |
| 13 | `score-checkpoint` | Bash Layer: score-checkpoint.sh | unassigned | PROPOSED |
| 14 | `score-merged-pr` | Bash Layer: score-merged-pr.sh | unassigned | PROPOSED |
| 15 | `watcher-board` | Bash Layer: watcher-board.sh | unassigned | PROPOSED |
| 16 | `style-tabs` | Bash Layer: style-tabs.sh | unassigned | PROPOSED |
| 17 | `show-fleet` | Bash Layer: show-fleet.sh | unassigned | PROPOSED |
| 18 | `token-meter` | Bash Layer: token-meter.sh | unassigned | PROPOSED |
| 19 | `warm-pool` | Bash Layer: warm-pool.sh | unassigned | PROPOSED |
| 20 | `spawn-fleet` | Bash Layer: spawn-fleet.sh | unassigned | PROPOSED |
| 21 | `dispatch-plan` | Bash Layer: dispatch-plan.sh | unassigned | PROPOSED |
| 22 | `cap-probe` | Bash Layer: cap-probe.sh | unassigned | PROPOSED |
| 23 | `proactive-probe` | Bash Layer: proactive-probe.sh | unassigned | PROPOSED |
| 24 | `claim-trigger` | Bash Layer: claim-trigger.sh | unassigned | PROPOSED |
| 25 | `claude-worker` | Bash Layer: claude-worker.sh | unassigned | PROPOSED |
| 26 | `claude-spawn` | Bash Layer: claude-spawn.sh | unassigned | PROPOSED |
| 27 | `claude-supervisor` | Bash Layer: claude-supervisor.sh | unassigned | PROPOSED |
| 28 | `fleet-tick` | Bash Layer: fleet-tick.sh | unassigned | PROPOSED |
| 29 | `fleet-tick-daemon` | Bash Layer: fleet-tick-daemon.sh | unassigned | PROPOSED |
| 30 | `fleet-state-anim` | Bash Layer: fleet-state-anim.sh | unassigned | PROPOSED |
| 31 | `plan-anim` | Bash Layer: plan-anim.sh | unassigned | PROPOSED |
| 32 | `plan-tree-anim` | Bash Layer: plan-tree-anim.sh | unassigned | PROPOSED |
| 33 | `plan-tree-pin` | Bash Layer: plan-tree-pin.sh | unassigned | PROPOSED |
| 34 | `review-anim` | Bash Layer: review-anim.sh | unassigned | PROPOSED |
| 35 | `waves-anim` | Bash Layer: waves-anim.sh | unassigned | PROPOSED |
| 36 | `supervisor` | Bash Layer: supervisor.sh | unassigned | PROPOSED |
| 37 | `patch-codex-prompts` | Bash Layer: patch-codex-prompts.sh | unassigned | PROPOSED |
| 38 | `overview-header` | Bash Layer: overview-header.sh | unassigned | PROPOSED |
| 39 | `down` | Bash Layer: down.sh | unassigned | PROPOSED |
| 40 | `up` | Bash Layer: up.sh | unassigned | PROPOSED |
| 41 | `add-workers` | Bash Layer: add-workers.sh | unassigned | PROPOSED |
| 42 | `codex-fleet-2` | Bash Layer: codex-fleet-2.sh | unassigned | PROPOSED |
| 43 | `rust-fleet-components` | Rust Crate: fleet-components | unassigned | PROPOSED |
| 44 | `rust-fleet-data` | Rust Crate: fleet-data | unassigned | PROPOSED |
| 45 | `rust-fleet-input` | Rust Crate: fleet-input | unassigned | PROPOSED |
| 46 | `rust-fleet-launcher` | Rust Crate: fleet-launcher | unassigned | PROPOSED |
| 47 | `rust-fleet-layout` | Rust Crate: fleet-layout | unassigned | PROPOSED |
| 48 | `rust-fleet-metrics-viewer` | Rust Crate: fleet-metrics-viewer | unassigned | PROPOSED |
| 49 | `rust-fleet-pane-health` | Rust Crate: fleet-pane-health | unassigned | PROPOSED |
| 50 | `rust-fleet-plan-tree` | Rust Crate: fleet-plan-tree | unassigned | PROPOSED |
| 51 | `rust-fleet-state` | Rust Crate: fleet-state | unassigned | PROPOSED |
| 52 | `rust-fleet-ui` | Rust Crate: fleet-ui | unassigned | PROPOSED |
| 53 | `rust-fleet-watcher` | Rust Crate: fleet-watcher | unassigned | PROPOSED |
| 54 | `rust-fleet-waves` | Rust Crate: fleet-waves | unassigned | PROPOSED |
| 55 | `openspec-workflow` | OpenSpec Workflow & Plan Registry | unassigned | PROPOSED |
| 56 | `colony-integration` | Colony Integration & Task Graph | unassigned | PROPOSED |
| 57 | `account-auth` | Account / Auth Layer | unassigned | PROPOSED |
| 58 | `self-healing` | Self-Healing Daemons (composite) | unassigned | PROPOSED |
| 59 | `observability` | Observability & Metrics | unassigned | PROPOSED |
| 60 | `logging-tracing` | Logging, Tracing & Replay | unassigned | PROPOSED |
| 61 | `testing-strategy` | Testing Strategy (unit, integration, snapshot, e2e) | unassigned | PROPOSED |
| 62 | `ci-cd` | CI/CD & Release Pipeline | unassigned | PROPOSED |
| 63 | `security-sandbox` | Security, Sandboxing & Permissions | unassigned | PROPOSED |
| 64 | `secrets` | Secrets, Credentials & Token Hygiene | unassigned | PROPOSED |
| 65 | `docs-onboarding` | Documentation & Onboarding | unassigned | PROPOSED |
| 66 | `skills` | Skills System (skills/codex-fleet) | unassigned | PROPOSED |
| 67 | `multi-repo` | Multi-Repo & Cross-Project Coordination | unassigned | PROPOSED |
| 68 | `performance` | Performance, Throughput & Backpressure | unassigned | PROPOSED |
| 69 | `resilience` | Resilience, Failure Modes & Chaos | unassigned | PROPOSED |
| 70 | `cost-quota` | Cost, Quota & Rate-Limit Management | unassigned | PROPOSED |
| 71 | `ui-ux` | UI/UX & Accessibility (tmux + future GUI) | unassigned | PROPOSED |
| 72 | `design-tokens` | Design Tokens & Theming | unassigned | PROPOSED |
| 73 | `i18n` | Internationalization & Localization | unassigned | PROPOSED |
| 74 | `versioning` | Versioning, Backwards Compatibility & Deprecation | unassigned | PROPOSED |
| 75 | `glossary` | Glossary & Conventions | unassigned | PROPOSED |
| 76 | `risk-register` | Risk Register (master) | unassigned | PROPOSED |
| 77 | `roadmap` | Roadmap & Milestones | unassigned | PROPOSED |
| 78 | `appendix` | Appendix: Reference Configs & Templates | unassigned | PROPOSED |

---

## Cross-Section Dependency Matrix (seed)

A first-pass dependency map. Rows depend on columns. Each line says:
the row section materially depends on the column section being
at least ACCEPTED before its own improvements can be SCHEDULED.

Captains audit this matrix during quarterly reviews; entries are added
or removed based on the actual blockers seen in flight. The seed
captures only obvious top-level couplings.

- `meta-protocol` -> `openspec-workflow` — Promotion gate from ACCEPTED to SCHEDULED requires the OpenSpec change pipeline.
- `repo-layout` -> `ci-cd` — Justfile / CODEOWNERS / .editorconfig changes ride on the CI lane.
- `observability` -> `logging-tracing` — Metrics depend on structured logging being in place first.
- `self-healing` -> `colony-integration` — Daemon SLOs cannot be measured without Colony queue-depth signals.
- `performance` -> `observability` — Adaptive cadence needs telemetry to react to queue depth.
- `resilience` -> `self-healing` — Chaos drills validate the self-healing fabric.
- `security-sandbox` -> `secrets` — Sandbox boundaries assume secret hygiene already enforced.
- `docs-onboarding` -> `glossary` — Onboarding docs should reference the central glossary.
- `skills` -> `docs-onboarding` — Skill prompts mirror onboarding-doc structure.
- `multi-repo` -> `openspec-workflow` — Multi-repo coordination needs schema-stable plan files.
- `cost-quota` -> `observability` — Cost dashboards depend on per-account metrics.
- `ui-ux` -> `design-tokens` — Theming work assumes tokens are centralised.
- `i18n` -> `ui-ux` — Locale switching depends on a quiet/minimal chrome variant.
- `versioning` -> `ci-cd` — Release pipeline carries semver enforcement.
- `roadmap` -> `meta-protocol` — Roadmap lanes are sequenced through the protocol governance.
- `appendix` -> `meta-protocol` — Templates are extracted under the governance umbrella.

---

## Maintainer Index

A flat alphabetical index of section slugs for fast `rg` lookup.

- `account-auth` — Account / Auth Layer
- `add-workers` — Bash Layer: add-workers.sh
- `appendix` — Appendix: Reference Configs & Templates
- `auto-reviewer` — Bash Layer: auto-reviewer.sh
- `cap-probe` — Bash Layer: cap-probe.sh
- `cap-swap` — Bash Layer: cap-swap-daemon.sh
- `ci-cd` — CI/CD & Release Pipeline
- `claim-release` — Bash Layer: claim-release-supervisor.sh
- `claim-trigger` — Bash Layer: claim-trigger.sh
- `claude-spawn` — Bash Layer: claude-spawn.sh
- `claude-supervisor` — Bash Layer: claude-supervisor.sh
- `claude-worker` — Bash Layer: claude-worker.sh
- `codex-fleet-2` — Bash Layer: codex-fleet-2.sh
- `colony-integration` — Colony Integration & Task Graph
- `conductor` — Bash Layer: conductor.sh
- `cost-quota` — Cost, Quota & Rate-Limit Management
- `design-tokens` — Design Tokens & Theming
- `dispatch-plan` — Bash Layer: dispatch-plan.sh
- `docs-onboarding` — Documentation & Onboarding
- `down` — Bash Layer: down.sh
- `fleet-state-anim` — Bash Layer: fleet-state-anim.sh
- `fleet-tick` — Bash Layer: fleet-tick.sh
- `fleet-tick-daemon` — Bash Layer: fleet-tick-daemon.sh
- `force-claim` — Bash Layer: force-claim.sh
- `full-bringup` — Bash Layer: full-bringup.sh
- `glossary` — Glossary & Conventions
- `i18n` — Internationalization & Localization
- `logging-tracing` — Logging, Tracing & Replay
- `meta-protocol` — Meta-Protocol & Governance
- `multi-repo` — Multi-Repo & Cross-Project Coordination
- `observability` — Observability & Metrics
- `openspec-workflow` — OpenSpec Workflow & Plan Registry
- `overview-header` — Bash Layer: overview-header.sh
- `patch-codex-prompts` — Bash Layer: patch-codex-prompts.sh
- `performance` — Performance, Throughput & Backpressure
- `plan-anim` — Bash Layer: plan-anim.sh
- `plan-tree-anim` — Bash Layer: plan-tree-anim.sh
- `plan-tree-pin` — Bash Layer: plan-tree-pin.sh
- `plan-watcher` — Bash Layer: plan-watcher.sh
- `proactive-probe` — Bash Layer: proactive-probe.sh
- `repo-layout` — Repository Layout & Workspace Hygiene
- `resilience` — Resilience, Failure Modes & Chaos
- `review-anim` — Bash Layer: review-anim.sh
- `review-pane-scanner` — Bash Layer: review-pane-scanner.sh
- `review-queue` — Bash Layer: review-queue.sh
- `risk-register` — Risk Register (master)
- `roadmap` — Roadmap & Milestones
- `rust-fleet-components` — Rust Crate: fleet-components
- `rust-fleet-data` — Rust Crate: fleet-data
- `rust-fleet-input` — Rust Crate: fleet-input
- `rust-fleet-launcher` — Rust Crate: fleet-launcher
- `rust-fleet-layout` — Rust Crate: fleet-layout
- `rust-fleet-metrics-viewer` — Rust Crate: fleet-metrics-viewer
- `rust-fleet-pane-health` — Rust Crate: fleet-pane-health
- `rust-fleet-plan-tree` — Rust Crate: fleet-plan-tree
- `rust-fleet-state` — Rust Crate: fleet-state
- `rust-fleet-ui` — Rust Crate: fleet-ui
- `rust-fleet-watcher` — Rust Crate: fleet-watcher
- `rust-fleet-waves` — Rust Crate: fleet-waves
- `score-checkpoint` — Bash Layer: score-checkpoint.sh
- `score-merged-pr` — Bash Layer: score-merged-pr.sh
- `secrets` — Secrets, Credentials & Token Hygiene
- `security-sandbox` — Security, Sandboxing & Permissions
- `self-healing` — Self-Healing Daemons (composite)
- `show-fleet` — Bash Layer: show-fleet.sh
- `skills` — Skills System (skills/codex-fleet)
- `spawn-fleet` — Bash Layer: spawn-fleet.sh
- `stall-watcher` — Bash Layer: stall-watcher.sh
- `style-tabs` — Bash Layer: style-tabs.sh
- `supervisor` — Bash Layer: supervisor.sh
- `testing-strategy` — Testing Strategy (unit, integration, snapshot, e2e)
- `token-meter` — Bash Layer: token-meter.sh
- `ui-ux` — UI/UX & Accessibility (tmux + future GUI)
- `up` — Bash Layer: up.sh
- `versioning` — Versioning, Backwards Compatibility & Deprecation
- `warm-pool` — Bash Layer: warm-pool.sh
- `watcher-board` — Bash Layer: watcher-board.sh
- `waves-anim` — Bash Layer: waves-anim.sh

---

## Closing notes

This protocol exists to compress repeated debates and to give every
subsystem a durable home for forward-looking thought. Use it as a
reference, not as a substitute for shipping. If a section feels stale,
update it; if a section feels wrong, propose an ADR; if a section
feels missing, add it.

Status, captains, and SHIPPED links can be refreshed at any time by
editing this file and opening a PR. The protocol-state CLI (see meta-
protocol section) will summarise the current distribution of states.

Updated by the docs/future captain after each two-week review.


---

## Implementation Log

This appendix records improvements that have moved beyond PROPOSED. Each
entry links to the protocol section it implements, the PR that landed
the work, and the resulting artifacts. Captains refresh this log at
each two-week review.

### 2026-05-17 — Governance bootstrap (PR #171)

The first wave of governance tooling that the rest of this protocol
depends on. None of the proposed *behaviour* changes ship in this PR;
only the scaffolding that makes the rest of the protocol enforceable.

| Section | Improvement | State | Artifact |
|---------|-------------|-------|----------|
| `meta-protocol` | Formal lifecycle states (state-line scheme + linter) | SHIPPED | `scripts/protocol/check-states.sh`, `scripts/protocol/protocol-state.sh` |
| `meta-protocol` | Anti-bikeshed: budget per section | SHIPPED | `scripts/protocol/check-budget.sh` |
| `meta-protocol` | Cite-real-files rule | SHIPPED | `scripts/protocol/check-refs.sh` |
| `meta-protocol` | Decision log (ADR-lite) | IN-PROGRESS | `docs/future/decisions/_template.md`, `docs/future/decisions/README.md` |
| `meta-protocol` | Two-week protocol review cadence | IN-PROGRESS | `docs/future/reviews/_template.md`, `docs/future/reviews/README.md` |
| `repo-layout` | Top-level taskfile (justfile) | SHIPPED | `justfile` |
| `repo-layout` | Top-level `.editorconfig` | SHIPPED | `.editorconfig` |

#### How to use the new tooling

- `just protocol-state` — print lifecycle-state counts.
- `just protocol-check` — run every governance gate (states, refs, budget).
- `just ci` — composite gate intended for CI.

Captains: see `docs/future/decisions/README.md` for ADR conventions and
`docs/future/reviews/README.md` for the bi-weekly review process.

#### Known gaps

- ADRs: only the template ships; no historical decisions backfilled yet.
- Reviews: the first review has not been held.
- CI wiring: `just ci` is documented but not yet invoked from any
  GitHub Actions workflow under `.github/`.
- Captains: every section still shows `unassigned`. The first review
  should fill the section-status snapshot.
