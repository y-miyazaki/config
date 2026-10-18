#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154

# Tests for .github/actions/loop-execute/lib/verifier.sh

# Use cases:
# - extract_last_json_fence returns the last json block
# - parse_verifier_output parses fenced JSON APPROVE
# - parse_verifier_output parses fenced JSON REJECT with files array
# - parse_verifier_output falls back to legacy VERDICT lines
# - parse_verifier_output defaults to REJECT when unparsable
# - parse_verifier_output parses cursor stream-json checker capture
# - run_verify rejects instead of approving when the branch diff cannot be computed
# - run_verify honors AGENT_UNCHANGED_VERDICT when the branch diff is empty
# - run_verify fails (no REJECT default) when AGENT_UNCHANGED_VERDICT is empty
# - run_verify writes denylist_blocked when the diff matches the denylist
# - run_verify rejects a rename away from a denylisted path
# - run_verify rejects a rename away from a denylisted non-ASCII path
# - run_verify rejects and blocks a changed path with unsafe characters

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

setup() {
    bats_source_rel ".github/actions/loop-execute/lib/common.sh"
    bats_source_rel ".github/actions/loop-execute/lib/usage.sh"
    bats_source_rel ".github/actions/loop-execute/lib/paths.sh"
    bats_source_rel ".github/actions/loop-execute/lib/rejections.sh"
    bats_source_rel ".github/actions/loop-execute/lib/verifier.sh"
    OPEN_REJECTIONS_JSON='[]'
}

@test "extract_last_json_fence returns the last json block" {
    tmpf=$(mktemp)
    cat > "${tmpf}" << 'EOF'
Some prose
```json
{"verdict":"REJECT","reason":"first"}
```
More prose
```json
{"verdict":"APPROVE","reason":"final"}
```
EOF
    result=$(extract_last_json_fence "${tmpf}")
    [[ ${result} == *'"verdict":"APPROVE"'* ]]
    [[ ${result} != *'"reason":"first"'* ]]
    rm -f "${tmpf}"
}

@test "parse_verifier_output parses fenced JSON APPROVE" {
    tmpf=$(mktemp)
    cat > "${tmpf}" << 'EOF'
Looks good.
```json
{
  "verdict": "APPROVE",
  "reason": "docs only"
}
```
EOF
    parse_verifier_output "${tmpf}"
    [ "${parsed}" = "true" ]
    [ "${verdict}" = "APPROVE" ]
    [ "${reason}" = "docs only" ]
    rm -f "${tmpf}"
}

@test "parse_verifier_output parses fenced JSON REJECT with files array" {
    tmpf=$(mktemp)
    cat > "${tmpf}" << 'EOF'
```json
{
  "verdict": "REJECT",
  "files": ["docs/a.md", "docs/b.md"],
  "issue": "scope",
  "fix": "limit to allowlist",
  "reason": "out of scope"
}
```
EOF
    parse_verifier_output "${tmpf}"
    [ "${parsed}" = "true" ]
    [ "${verdict}" = "REJECT" ]
    [ "${files}" = "docs/a.md,docs/b.md" ]
    [ "${issue}" = "scope" ]
    [ "${fix}" = "limit to allowlist" ]
    rm -f "${tmpf}"
}

@test "parse_verifier_output falls back to legacy VERDICT lines" {
    tmpf=$(mktemp)
    cat > "${tmpf}" << 'EOF'
VERDICT: REJECT
REASON: Legacy format
FILES: docs/old.md
ISSUE: stale
FIX: refresh
EOF
    parse_verifier_output "${tmpf}"
    [ "${parsed}" = "true" ]
    [ "${verdict}" = "REJECT" ]
    [ "${reason}" = "Legacy format" ]
    [ "${files}" = "docs/old.md" ]
    rm -f "${tmpf}"
}

@test "parse_verifier_output defaults to REJECT when unparsable" {
    tmpf=$(mktemp)
    echo "no structured verdict here" > "${tmpf}"
    parse_verifier_output "${tmpf}"
    [ "${parsed}" = "false" ]
    [ "${verdict}" = "REJECT" ]
    rm -f "${tmpf}"
}

@test "parse_verifier_output parses cursor stream-json checker capture" {
    parse_verifier_output "test/fixtures/loop-execute/cursor-stream-json-verifier.ndjson"
    [ "${parsed}" = "true" ]
    [ "${verdict}" = "REJECT" ]
    [ "${files}" = "docs/explanation/architecture.md" ]
    [ "${issue}" = "factual mismatch in module list" ]
    [ "${fix}" = "align architecture.md with current packages" ]
    [ "${reason}" = "docs inconsistent with repo" ]
}

@test "run_verify rejects when the branch diff cannot be computed" {
    local remote work attempt_dir

    remote="${BATS_TEST_TMPDIR}/remote"
    work="${BATS_TEST_TMPDIR}/work"
    attempt_dir="${BATS_TEST_TMPDIR}/attempt-nomergebase"

    bats_git_fresh_repo "${remote}"
    bats_git_cmd -C "${remote}" checkout -q -b main
    printf 'base\n' > "${remote}/base.txt"
    bats_git_commit "${remote}" "init"

    bats_git_cmd clone -q "${remote}" "${work}"
    bats_git_local_identity "${work}"
    # An orphan branch shares no ancestry with origin/main, which is exactly the
    # state a shallow base fetch used to produce: git diff then exits non-zero.
    bats_git_cmd -C "${work}" checkout -q --orphan loop/test
    printf 'new\n' > "${work}/new.txt"
    bats_git_commit "${work}" "orphan"

    WORKTREE_PATH="${work}"
    BASE_BRANCH="main"
    run run_verify "${attempt_dir}" 1 "true"
    [[ ${status} -eq 0 ]]
    [[ "$(cat "${attempt_dir}/verdict")" == "REJECT" ]]
    [[ "$(cat "${attempt_dir}/reason")" == *"Could not compute the branch diff"* ]]
}

@test "run_verify honors AGENT_UNCHANGED_VERDICT when the branch diff is empty" {
    local remote work attempt_dir

    remote="${BATS_TEST_TMPDIR}/remote-empty"
    work="${BATS_TEST_TMPDIR}/work-empty"
    attempt_dir="${BATS_TEST_TMPDIR}/attempt-empty"

    bats_git_fresh_repo "${remote}"
    bats_git_cmd -C "${remote}" checkout -q -b main
    printf 'base\n' > "${remote}/base.txt"
    bats_git_commit "${remote}" "init"

    bats_git_cmd clone -q "${remote}" "${work}"
    bats_git_local_identity "${work}"

    WORKTREE_PATH="${work}"
    BASE_BRANCH="main"

    AGENT_UNCHANGED_VERDICT="REJECT"
    run run_verify "${attempt_dir}" 1 "true"
    [[ ${status} -eq 0 ]]
    [[ "$(cat "${attempt_dir}/verdict")" == "REJECT" ]]

    AGENT_UNCHANGED_VERDICT="APPROVE"
    run run_verify "${attempt_dir}" 1 "true"
    [[ "$(cat "${attempt_dir}/verdict")" == "APPROVE" ]]
}

@test "run_verify fails without a verdict when AGENT_UNCHANGED_VERDICT is empty and the diff is empty" {
    local remote work attempt_dir

    remote="${BATS_TEST_TMPDIR}/remote-unset"
    work="${BATS_TEST_TMPDIR}/work-unset"
    attempt_dir="${BATS_TEST_TMPDIR}/attempt-unset"

    bats_git_fresh_repo "${remote}"
    bats_git_cmd -C "${remote}" checkout -q -b main
    printf 'base\n' > "${remote}/base.txt"
    bats_git_commit "${remote}" "init"

    bats_git_cmd clone -q "${remote}" "${work}"
    bats_git_local_identity "${work}"

    WORKTREE_PATH="${work}"
    BASE_BRANCH="main"
    AGENT_UNCHANGED_VERDICT=""
    NO_CHANGES_VERDICT="APPROVE"

    run run_verify "${attempt_dir}" 1 "true"
    [ "${status}" -eq 1 ]
    [ "${output}" = "::error::agent_unchanged_verdict is required (APPROVE or REJECT); got: ''" ]
    [ ! -f "${attempt_dir}/verdict" ]
}

@test "run_verify writes denylist_blocked when the diff matches the denylist" {
    local remote work attempt_dir

    remote="${BATS_TEST_TMPDIR}/remote-denylist"
    work="${BATS_TEST_TMPDIR}/work-denylist"
    attempt_dir="${BATS_TEST_TMPDIR}/attempt-denylist"

    bats_git_fresh_repo "${remote}"
    bats_git_cmd -C "${remote}" checkout -q -b main
    printf 'base\n' > "${remote}/base.txt"
    bats_git_commit "${remote}" "init"

    bats_git_cmd clone -q "${remote}" "${work}"
    bats_git_local_identity "${work}"
    printf 'hunter2\n' > "${work}/secrets.yaml" # pragma: allowlist secret
    bats_git_commit "${work}" "add secret"

    WORKTREE_PATH="${work}"
    BASE_BRANCH="main"
    AGENT_EDIT_DENYLIST="**/secrets*"

    run run_verify "${attempt_dir}" 1 "true"
    [[ ${status} -eq 0 ]]
    [[ "$(cat "${attempt_dir}/verdict")" == "REJECT" ]]
    [ -f "${attempt_dir}/denylist_blocked" ]
    [[ "$(cat "${attempt_dir}/denylist_blocked")" == "true" ]]
}

@test "run_verify rejects a rename away from a denylisted path" {
    local remote work attempt_dir

    remote="${BATS_TEST_TMPDIR}/remote-rename"
    work="${BATS_TEST_TMPDIR}/work-rename"
    attempt_dir="${BATS_TEST_TMPDIR}/attempt-rename"

    bats_git_fresh_repo "${remote}"
    bats_git_cmd -C "${remote}" checkout -q -b main
    printf 'hunter2\n' > "${remote}/secrets.txt" # pragma: allowlist secret
    bats_git_commit "${remote}" "init"

    bats_git_cmd clone -q "${remote}" "${work}"
    bats_git_local_identity "${work}"
    mkdir -p "${work}/docs"
    bats_git_cmd -C "${work}" mv secrets.txt docs/notes.txt
    bats_git_commit "${work}" "rename secrets"

    WORKTREE_PATH="${work}"
    BASE_BRANCH="main"
    AGENT_EDIT_DENYLIST="secrets*"

    run run_verify "${attempt_dir}" 1 "true"
    [[ ${status} -eq 0 ]]
    [[ "$(cat "${attempt_dir}/verdict")" == "REJECT" ]]
    [ -f "${attempt_dir}/denylist_blocked" ]
}

@test "run_verify rejects a rename away from a denylisted non-ASCII path" {
    local remote work attempt_dir

    remote="${BATS_TEST_TMPDIR}/remote-rename-utf8"
    work="${BATS_TEST_TMPDIR}/work-rename-utf8"
    attempt_dir="${BATS_TEST_TMPDIR}/attempt-rename-utf8"

    bats_git_fresh_repo "${remote}"
    bats_git_cmd -C "${remote}" checkout -q -b main
    printf 'hunter2\n' > "${remote}/secrets-é.txt" # pragma: allowlist secret
    bats_git_commit "${remote}" "init"

    bats_git_cmd clone -q "${remote}" "${work}"
    bats_git_local_identity "${work}"
    mkdir -p "${work}/docs"
    bats_git_cmd -C "${work}" mv secrets-é.txt docs/notes.txt
    bats_git_commit "${work}" "rename secrets"

    WORKTREE_PATH="${work}"
    BASE_BRANCH="main"
    AGENT_EDIT_DENYLIST="secrets*"

    run run_verify "${attempt_dir}" 1 "true"
    [[ ${status} -eq 0 ]]
    [[ "$(cat "${attempt_dir}/verdict")" == "REJECT" ]]
    [ -f "${attempt_dir}/denylist_blocked" ]
    grep -q 'secrets-é.txt' "${attempt_dir}/reason"
}

@test "run_verify rejects and blocks a changed path with unsafe characters" {
    local remote work attempt_dir

    remote="${BATS_TEST_TMPDIR}/remote-unsafe"
    work="${BATS_TEST_TMPDIR}/work-unsafe"
    attempt_dir="${BATS_TEST_TMPDIR}/attempt-unsafe"

    bats_git_fresh_repo "${remote}"
    bats_git_cmd -C "${remote}" checkout -q -b main
    printf 'base\n' > "${remote}/a.txt"
    bats_git_commit "${remote}" "init"

    bats_git_cmd clone -q "${remote}" "${work}"
    bats_git_local_identity "${work}"
    mkdir -p "${work}/docs"
    printf 'x\n' > "${work}/docs/a\"b.md"
    bats_git_commit "${work}" "quoted name"

    WORKTREE_PATH="${work}"
    BASE_BRANCH="main"
    AGENT_EDIT_DENYLIST="secrets*"

    run run_verify "${attempt_dir}" 1 "true"
    [[ ${status} -eq 0 ]]
    [[ "$(cat "${attempt_dir}/verdict")" == "REJECT" ]]
    [ -f "${attempt_dir}/denylist_blocked" ]
    grep -q 'unsafe characters' "${attempt_dir}/reason"
    [[ ${output} == *"::error::Branch diff lists an unsafe path"* ]]
}
