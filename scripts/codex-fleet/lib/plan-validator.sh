#!/usr/bin/env bash
# shellcheck shell=bash
#
# plan-validator.sh — validate a codex-fleet plan.json against the flat-parallelism contract.
#
# Usage:
#   plan-validator.sh <path-to-plan.json> [--allow-waves] [--strict]
#
# Rules enforced:
#   (a) every sub-task's `depends_on` is empty UNLESS --allow-waves is passed.
#       With --allow-waves, `depends_on` is allowed but must form a DAG (no
#       cycles).
#   (b) no two sub-tasks share any file path in `file_scope`. A directory
#       entry (one that ends with '/') overlaps with any sibling entry that
#       falls under that directory prefix.
#   (c) `acceptance_criteria` is a non-empty array of strings each ≥ 40 chars.
#   (d) every `metadata.writable_roots` path exists and is writable.
#   (e) every `file_scope` path is under at least one writable_root. Warning
#       by default; promoted to a fatal error with --strict.
#   (f) every sub-task `description` is ≥ 200 chars.
#
# Output contract:
#   - Human-readable findings go to STDERR (one finding per line, prefixed
#     "WARN: " or "ERROR: ").
#   - A single JSON summary goes to STDOUT with shape:
#       {"ok": bool, "warnings": [string,...], "errors": [string,...]}
#
# Exit codes:
#   0  ok           (no warnings, no errors)
#   2  warnings     (warnings but no errors)
#   3  hard errors  (one or more errors; "ok": false in JSON)
#   1  usage / IO   (missing arg, file unreadable, malformed JSON)
#
# Dependencies: bash, jq (already a project dependency).
#
# ---------------------------------------------------------------------------
# Self-tests (commented; run manually with `bash -c "$(sed -n '/^# >>> SELFTEST/,/^# <<< SELFTEST/p' plan-validator.sh)"`):
#
# >>> SELFTEST BEGIN
# tmpdir=$(mktemp -d)
# trap 'rm -rf "$tmpdir"' EXIT
#
# # Fixture 1: well-formed, flat-parallel plan — expect exit 0.
# cat > "$tmpdir/ok.json" <<'OKJSON'
# {
#   "schema_version": 1,
#   "plan_slug": "selftest-ok",
#   "title": "selftest",
#   "problem": "x",
#   "acceptance_criteria": [
#     "Every sub-task lands as an independent PR with verifiable evidence in the PR body.",
#     "Workspace cargo check passes after all sub-tasks land; no regressions in existing crates."
#   ],
#   "tasks": [
#     {"subtask_index": 0, "title": "a", "file_scope": ["scripts/a.sh"], "depends_on": []},
#     {"subtask_index": 1, "title": "b", "file_scope": ["scripts/b.sh"], "depends_on": []}
#   ]
# }
# OKJSON
# bash plan-validator.sh "$tmpdir/ok.json" >/dev/null; echo "ok-fixture exit=$?"  # expect 0
#
# # Fixture 2: overlapping file_scope — expect exit 3.
# cat > "$tmpdir/bad.json" <<'BADJSON'
# {
#   "schema_version": 1,
#   "plan_slug": "selftest-bad",
#   "title": "selftest",
#   "problem": "x",
#   "acceptance_criteria": [
#     "Every sub-task lands as an independent PR with verifiable evidence in the PR body."
#   ],
#   "tasks": [
#     {"subtask_index": 0, "title": "a", "file_scope": ["scripts/shared/"], "depends_on": []},
#     {"subtask_index": 1, "title": "b", "file_scope": ["scripts/shared/util.sh"], "depends_on": []}
#   ]
# }
# BADJSON
# bash plan-validator.sh "$tmpdir/bad.json" >/dev/null; echo "bad-fixture exit=$?"  # expect 3
# <<< SELFTEST END
# ---------------------------------------------------------------------------

set -u
set -o pipefail

PROG="plan-validator.sh"

usage() {
    printf 'usage: %s <path-to-plan.json> [--allow-waves]\n' "$PROG" >&2
    return 1
}

if [ "$#" -lt 1 ]; then
    usage
    exit 1
fi

PLAN_PATH=""
ALLOW_WAVES=0
STRICT=0

while [ "$#" -gt 0 ]; do
    case "$1" in
        --allow-waves)
            ALLOW_WAVES=1
            shift
            ;;
        --strict)
            STRICT=1
            shift
            ;;
        -h|--help)
            usage || true
            exit 0
            ;;
        --*)
            printf '%s: unknown flag: %s\n' "$PROG" "$1" >&2
            exit 1
            ;;
        *)
            if [ -z "$PLAN_PATH" ]; then
                PLAN_PATH="$1"
            else
                printf '%s: unexpected extra arg: %s\n' "$PROG" "$1" >&2
                exit 1
            fi
            shift
            ;;
    esac
done

if [ -z "$PLAN_PATH" ]; then
    usage
    exit 1
fi

if [ ! -f "$PLAN_PATH" ]; then
    printf '%s: plan file not found: %s\n' "$PROG" "$PLAN_PATH" >&2
    exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
    printf '%s: jq is required but not on PATH\n' "$PROG" >&2
    exit 1
fi

# Validate the file is parseable JSON up front.
if ! jq -e . "$PLAN_PATH" >/dev/null 2>&1; then
    printf '%s: plan file is not valid JSON: %s\n' "$PROG" "$PLAN_PATH" >&2
    # Still emit a JSON summary on stdout for callers that parse it.
    printf '{"ok":false,"warnings":[],"errors":["plan file is not valid JSON"]}\n'
    exit 3
fi

# Accumulators. We deliberately use newline-delimited strings (one finding
# per line) so we can pass them to jq -R . | jq -s . at the end.
warnings=""
errors=""

# add_warning is intentionally retained for future soft-checks (e.g. style
# warnings) even though no current rule emits warnings. The JSON summary
# always includes a `warnings` array so downstream callers can rely on the
# shape regardless of which rules are enabled.
# shellcheck disable=SC2329
add_warning() {
    warnings="${warnings}${1}"$'\n'
    printf 'WARN: %s\n' "$1" >&2
}

add_error() {
    errors="${errors}${1}"$'\n'
    printf 'ERROR: %s\n' "$1" >&2
}

# ---------------------------------------------------------------------------
# Rule (c): acceptance_criteria — non-empty array of strings each ≥ 40 chars.
# ---------------------------------------------------------------------------

ac_type=$(jq -r '.acceptance_criteria | type' "$PLAN_PATH")
if [ "$ac_type" != "array" ]; then
    add_error "acceptance_criteria is missing or not an array (got: $ac_type)"
else
    ac_count=$(jq -r '.acceptance_criteria | length' "$PLAN_PATH")
    if [ "$ac_count" -eq 0 ]; then
        add_error "acceptance_criteria is an empty array"
    else
        # Collect items that are not strings or are shorter than 40 chars.
        # Output format from jq: "<index>\t<reason>\t<truncated-content>" per line.
        bad_ac=$(jq -r '
            .acceptance_criteria
            | to_entries
            | map(
                if (.value | type) != "string" then
                    "\(.key)\tnot-a-string\t\(.value | tostring | .[0:60])"
                elif ((.value | length) < 40) then
                    "\(.key)\ttoo-short(\(.value | length))\t\(.value)"
                else
                    empty
                end
              )
            | .[]
        ' "$PLAN_PATH")
        if [ -n "$bad_ac" ]; then
            while IFS=$'\t' read -r idx reason content; do
                [ -z "$idx" ] && continue
                add_error "acceptance_criteria[$idx] $reason: $content"
            done <<EOF
$bad_ac
EOF
        fi
    fi
fi

# ---------------------------------------------------------------------------
# Rule (a): depends_on must be empty unless --allow-waves.
# ---------------------------------------------------------------------------

tasks_type=$(jq -r '.tasks | type' "$PLAN_PATH")
if [ "$tasks_type" != "array" ]; then
    add_error "tasks is missing or not an array (got: $tasks_type)"
else
    if [ "$ALLOW_WAVES" -eq 0 ]; then
        # Emit "<idx>\t<title>\t<depends_csv>" for any task with non-empty depends_on.
        offenders=$(jq -r '
            .tasks
            | to_entries
            | map(
                select(
                    (.value.depends_on // []) | type == "array" and length > 0
                )
                | "\(.key)\t\(.value.title // "")\t\((.value.depends_on // []) | join(","))"
              )
            | .[]
        ' "$PLAN_PATH")
        if [ -n "$offenders" ]; then
            while IFS=$'\t' read -r idx title deps; do
                [ -z "$idx" ] && continue
                add_error "tasks[$idx] '$title' has depends_on=[$deps] but --allow-waves was not passed"
            done <<EOF
$offenders
EOF
        fi
    fi
fi

# ---------------------------------------------------------------------------
# Rule (b): no two sub-tasks share any path in file_scope.
#
# A directory entry (ending with '/') overlaps with any other entry that
# starts with that directory prefix. A file entry overlaps with another
# file entry if the strings are equal, or if either entry is a directory
# that prefixes the other.
# ---------------------------------------------------------------------------

if [ "$tasks_type" = "array" ]; then
    # Build a TSV stream of "<task_index>\t<scope_path>" for every (task, scope) pair.
    # We normalize paths: strip a single leading "./" but otherwise keep them verbatim.
    scope_pairs=$(jq -r '
        .tasks
        | to_entries
        | map(
            . as $t
            | (($t.value.file_scope // []) | map(
                {idx: $t.key, path: (. | sub("^\\./"; ""))}
              ))
          )
        | add // []
        | .[]
        | "\(.idx)\t\(.path)"
    ' "$PLAN_PATH")

    # Pairwise overlap detection. The number of sub-tasks is small (typically
    # under 30), so O(n^2) is fine and keeps logic obvious.
    if [ -n "$scope_pairs" ]; then
        # Read into parallel arrays.
        idx_arr=()
        path_arr=()
        while IFS=$'\t' read -r p_idx p_path; do
            [ -z "$p_idx" ] && continue
            idx_arr+=("$p_idx")
            path_arr+=("$p_path")
        done <<EOF
$scope_pairs
EOF

        n=${#idx_arr[@]}
        i=0
        while [ "$i" -lt "$n" ]; do
            j=$((i + 1))
            while [ "$j" -lt "$n" ]; do
                a_idx="${idx_arr[$i]}"
                b_idx="${idx_arr[$j]}"
                a_path="${path_arr[$i]}"
                b_path="${path_arr[$j]}"

                # Skip within-task pairs — overlapping scopes inside a single
                # task are not a parallelism violation (and the plan author
                # may have legitimate reasons to list both a dir and a file).
                if [ "$a_idx" = "$b_idx" ]; then
                    j=$((j + 1))
                    continue
                fi

                overlap=0
                # Case 1: exact match.
                if [ "$a_path" = "$b_path" ]; then
                    overlap=1
                fi
                # Case 2: a is a directory prefix of b.
                if [ "$overlap" -eq 0 ]; then
                    case "$a_path" in
                        */)
                            case "$b_path" in
                                "$a_path"*) overlap=1 ;;
                            esac
                            ;;
                    esac
                fi
                # Case 3: b is a directory prefix of a.
                if [ "$overlap" -eq 0 ]; then
                    case "$b_path" in
                        */)
                            case "$a_path" in
                                "$b_path"*) overlap=1 ;;
                            esac
                            ;;
                    esac
                fi

                if [ "$overlap" -eq 1 ]; then
                    add_error "file_scope overlap: tasks[$a_idx]='$a_path' overlaps tasks[$b_idx]='$b_path'"
                fi

                j=$((j + 1))
            done
            i=$((i + 1))
        done
    fi
fi

# ---------------------------------------------------------------------------
# Rule (a-extra): depends_on must form a DAG (no cycles) when --allow-waves.
# We always run this check — a cycle is an error regardless of waves mode.
# ---------------------------------------------------------------------------

if [ "$tasks_type" = "array" ]; then
    cycle_msg=$(PLAN_FILE="$PLAN_PATH" python3 - <<'PY'
import json, os, sys

try:
    with open(os.environ["PLAN_FILE"]) as f:
        data = json.load(f)
except Exception:
    sys.exit(0)

tasks = data.get("tasks") or []
if not isinstance(tasks, list) or not tasks:
    sys.exit(0)

# Build adjacency map keyed on subtask_index (preferred) or array position.
graph = {}
title_by = {}
for pos, t in enumerate(tasks):
    if not isinstance(t, dict):
        continue
    idx = t.get("subtask_index")
    if not isinstance(idx, int):
        idx = pos
    deps = t.get("depends_on") or []
    if not isinstance(deps, list):
        deps = []
    clean = []
    for d in deps:
        if isinstance(d, int):
            clean.append(d)
    graph[idx] = clean
    title_by[idx] = t.get("title", "")

# Kahn's algorithm: count incoming edges per node; repeatedly remove nodes
# with zero in-degree. If any nodes remain afterwards, those form a cycle.
indeg = {n: 0 for n in graph}
for n, deps in graph.items():
    for d in deps:
        if d in indeg:
            indeg[d] = indeg.get(d, 0)
            # An edge n -> d means n depends on d; d must come first.
            # In-degree of n increments for each dependency.
    # Recompute n's in-degree as len of its (in-graph) deps.
    indeg[n] = sum(1 for d in deps if d in graph)

# Topological sort.
ready = [n for n, c in indeg.items() if c == 0]
removed = set()
while ready:
    n = ready.pop()
    removed.add(n)
    for m, deps in graph.items():
        if m in removed:
            continue
        if n in deps:
            indeg[m] -= 1
            if indeg[m] == 0:
                ready.append(m)

remaining = [n for n in graph if n not in removed]
if remaining:
    parts = ["{}({})".format(n, title_by.get(n, "")) for n in remaining]
    print("depends_on cycle detected; involved subtasks: " + ", ".join(parts))
PY
)
    if [ -n "$cycle_msg" ]; then
        add_error "$cycle_msg"
    fi
fi

# ---------------------------------------------------------------------------
# Rule (d): every metadata.writable_roots path must exist and be writable.
# ---------------------------------------------------------------------------

writable_roots=$(jq -r '(.metadata.writable_roots // []) | .[]?' "$PLAN_PATH" 2>/dev/null || true)
if [ -n "$writable_roots" ]; then
    while IFS= read -r root; do
        [ -z "$root" ] && continue
        if [ ! -d "$root" ]; then
            add_error "writable_root path does not exist or is not a directory: $root"
            continue
        fi
        if [ ! -w "$root" ]; then
            add_error "writable_root path is not writable by current user: $root"
        fi
    done <<EOF
$writable_roots
EOF
fi

# ---------------------------------------------------------------------------
# Rule (e): every file_scope path must be under at least one writable_root.
# Warning by default, fatal under --strict.
# ---------------------------------------------------------------------------

if [ "$tasks_type" = "array" ] && [ -n "$writable_roots" ]; then
    # Normalize roots: strip trailing slash for comparison.
    roots_for_check=$(printf '%s\n' "$writable_roots" | sed 's:/*$::')
    # Stream "<idx>\t<path>" pairs.
    scope_pairs2=$(jq -r '
        .tasks
        | to_entries
        | map(
            . as $t
            | (($t.value.file_scope // []) | map({idx: $t.key, path: .}))
          )
        | add // []
        | .[]
        | "\(.idx)\t\(.path)"
    ' "$PLAN_PATH")
    if [ -n "$scope_pairs2" ]; then
        while IFS=$'\t' read -r s_idx s_path; do
            [ -z "$s_idx" ] && continue
            # Repo-relative file_scope entries (the norm) are considered
            # covered because they resolve against whichever writable_root
            # the worker cd's to. We only police absolute paths — those
            # must literally fall under one of the declared roots.
            case "$s_path" in
                /*) : ;;
                *)
                    continue
                    ;;
            esac
            covered=0
            while IFS= read -r root; do
                [ -z "$root" ] && continue
                case "$s_path" in
                    "$root"|"$root"/*)
                        covered=1
                        break
                        ;;
                esac
            done <<EOF
$roots_for_check
EOF
            if [ "$covered" -eq 0 ]; then
                if [ "$STRICT" -eq 1 ]; then
                    add_error "file_scope path not under any writable_root: tasks[$s_idx]='$s_path'"
                else
                    add_warning "file_scope path not under any writable_root: tasks[$s_idx]='$s_path'"
                fi
            fi
        done <<EOF
$scope_pairs2
EOF
    fi
fi

# ---------------------------------------------------------------------------
# Rule (f): every subtask description must be ≥ 200 chars.
# ---------------------------------------------------------------------------

if [ "$tasks_type" = "array" ]; then
    short_descs=$(jq -r '
        .tasks
        | to_entries
        | map(
            select(((.value.description // "") | length) < 200)
            | "\(.key)\t\(.value.title // "")\t\((.value.description // "") | length)"
          )
        | .[]
    ' "$PLAN_PATH")
    if [ -n "$short_descs" ]; then
        while IFS=$'\t' read -r d_idx d_title d_len; do
            [ -z "$d_idx" ] && continue
            add_error "tasks[$d_idx] '$d_title' description too short (length=$d_len, need ≥ 200)"
        done <<EOF
$short_descs
EOF
    fi
fi

# ---------------------------------------------------------------------------
# Emit JSON summary on stdout and exit with the appropriate code.
# ---------------------------------------------------------------------------

# Strip trailing newline; produce JSON arrays via jq.
warnings_trim=${warnings%$'\n'}
errors_trim=${errors%$'\n'}

warnings_json="[]"
if [ -n "$warnings_trim" ]; then
    warnings_json=$(printf '%s' "$warnings_trim" | jq -R . | jq -s .)
fi

errors_json="[]"
if [ -n "$errors_trim" ]; then
    errors_json=$(printf '%s' "$errors_trim" | jq -R . | jq -s .)
fi

ok="true"
if [ -n "$errors_trim" ]; then
    ok="false"
fi

jq -n \
    --argjson ok "$ok" \
    --argjson warnings "$warnings_json" \
    --argjson errors "$errors_json" \
    '{ok: $ok, warnings: $warnings, errors: $errors}'

if [ -n "$errors_trim" ]; then
    exit 3
fi
if [ -n "$warnings_trim" ]; then
    exit 2
fi
exit 0
