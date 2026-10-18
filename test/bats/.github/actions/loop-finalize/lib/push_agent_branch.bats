#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154

# Tests for .github/actions/loop-finalize/lib/push_agent_branch.sh
#
# Use cases:
# - a valid bundle is verified, imported (agent branch only), and pushed without force
# - from.ref must be an ancestor of the tip; a missing from.ref object fails closed
# - the diff range is <from.ref>..<branch>, or origin/<base>...<branch> when from.ref is empty
# - denylist (platform default when empty), allowlist, and .github/workflows/ are re-applied
#   to the --no-renames diff, including .loop/ paths and both sides of a rename
# - an existing remote branch or a rejected push fails without force
# - invalid agent branch names fail with branch= and invalid base branches fail
# - an empty branch, a failed agent, or no changes push nothing and record nothing
# - every failure records stage push, writes pushed=false failed=true, and exits 0
# - missing GITHUB_OUTPUT or LOOP_FAILURE_FILE exits 1

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

PUSH_SCRIPT="$(bats_workspace_root)/.github/actions/loop-finalize/lib/push_agent_branch.sh"
BRANCH='loop/changelog/20261018-123456'
EMPTY_TARGET='{}'

setup() {
    ORIGIN="${BATS_TEST_TMPDIR}/origin.git"
    AGENT="${BATS_TEST_TMPDIR}/agent"
    FINAL="${BATS_TEST_TMPDIR}/final"
    BUNDLE_DIR="${BATS_TEST_TMPDIR}/bundle"
    OUTPUT_FILE="${BATS_TEST_TMPDIR}/github_output"
    FAILURE_FILE="${BATS_TEST_TMPDIR}/failure.json"
    mkdir -p "${BUNDLE_DIR}"

    git init -q --bare -b main "${ORIGIN}"
    git clone -q "${ORIGIN}" "${AGENT}" 2> /dev/null
    git -C "${AGENT}" config user.email t@example.com
    git -C "${AGENT}" config user.name t
    git -C "${AGENT}" checkout -q -b main
    printf 'base\n' > "${AGENT}/README.md"
    printf 'secret\n' > "${AGENT}/secrets.txt"
    git -C "${AGENT}" add README.md secrets.txt
    git -C "${AGENT}" commit -q -m base
    git -C "${AGENT}" push -q origin main
    git -C "${AGENT}" checkout -q -b feature/pr-head
    mkdir -p "${AGENT}/src"
    printf 'pr\n' > "${AGENT}/src/pr.sh"
    git -C "${AGENT}" add src/pr.sh
    git -C "${AGENT}" commit -q -m pr-head
    git -C "${AGENT}" push -q origin feature/pr-head
    git -C "${AGENT}" fetch -q origin
    PR_HEAD_SHA="$(git -C "${AGENT}" rev-parse HEAD)"
    git -C "${AGENT}" checkout -q main
}

teardown() {
    rm -rf "${ORIGIN}" "${AGENT}" "${FINAL}" "${BUNDLE_DIR}" "${OUTPUT_FILE}" "${FAILURE_FILE}"
}

# agent_commit: write <content> to <path> on the agent branch and commit it.
function agent_commit {
    local path="$1"
    local content="${2:-change}"
    mkdir -p "$(dirname "${AGENT}/${path}")"
    printf '%s\n' "${content}" > "${AGENT}/${path}"
    git -C "${AGENT}" add -- "${path}"
    git -C "${AGENT}" commit -q -m "change ${path}"
}

# make_agent_branch: (re)create the agent branch from <start> (default origin/main).
function make_agent_branch {
    local start="${1:-origin/main}"
    git -C "${AGENT}" checkout -q -B "${BRANCH}" "${start}"
}

# make_bundle: bundle the agent branch (plus extra refs) the same way bundle.sh does.
function make_bundle {
    rm -f "${BUNDLE_DIR}/branch.bundle"
    git -C "${AGENT}" bundle create -q "${BUNDLE_DIR}/branch.bundle" "^origin/main" "refs/heads/${BRANCH}" "$@"
}

# origin_sha: print the SHA of refs/heads/<branch> on origin, or nothing.
function origin_sha {
    git -C "${ORIGIN}" rev-parse -q --verify "refs/heads/$1" || true
}

# reset_final: drop the finalize clone and the agent branch on origin.
function reset_final {
    rm -rf "${FINAL}"
    git -C "${ORIGIN}" update-ref -d "refs/heads/${BRANCH}" 2> /dev/null || true
}

# run_push: run the script in the finalize clone; T_* variables override the defaults.
function run_push {
    : > "${OUTPUT_FILE}"
    rm -f "${FAILURE_FILE}"
    if [[ ! -d ${FINAL} ]]; then
        git clone -q --no-local "${ORIGIN}" "${FINAL}" 2> /dev/null
    fi
    run env \
        AGENT_BRANCH="${T_BRANCH-${BRANCH}}" \
        AGENT_BRANCH_PREFIX="${T_PREFIX-loop}" \
        AGENT_BUNDLE_DIR="${BUNDLE_DIR}" \
        AGENT_EDIT_ALLOWLIST="${T_ALLOWLIST-}" \
        AGENT_EDIT_DENYLIST="${T_DENYLIST-}" \
        AGENT_MAKER_SKILL_NAME="${T_SKILL-changelog}" \
        AGENT_RESULT="${T_RESULT-success}" \
        BASE_BRANCH="${T_BASE-main}" \
        GITHUB_OUTPUT="${OUTPUT_FILE}" \
        GITHUB_TOKEN=dummy \
        HAS_CHANGES="${T_HAS_CHANGES-true}" \
        LOOP_FAILURE_FILE="${FAILURE_FILE}" \
        STATE_BRANCH="${T_STATE-main}" \
        TARGET_JSON="${T_TARGET-${EMPTY_TARGET}}" \
        TO_BRANCH="${T_TO-main}" \
        bash -c 'cd "$1" && bash "$2"' _ "${FINAL}" "${PUSH_SCRIPT}"
    OUT_BRANCH="$(sed -n 's/^branch=//p' "${OUTPUT_FILE}")"
    OUT_PUSHED="$(sed -n 's/^pushed=//p' "${OUTPUT_FILE}")"
    OUT_FAILED="$(sed -n 's/^failed=//p' "${OUTPUT_FILE}")"
    OUT_LINES="$(wc -l < "${OUTPUT_FILE}")"
    FAILURE_STAGE=""
    FAILURE_MESSAGE=""
    if [[ -f ${FAILURE_FILE} ]]; then
        FAILURE_STAGE="$(jq -r '.failure_stage' "${FAILURE_FILE}")"
        FAILURE_MESSAGE="$(jq -r '.failure_message' "${FAILURE_FILE}")"
    fi
}

# assert_failed: status 0, failed=true, pushed=false, stage push, branch=<$1>.
function assert_failed {
    [ "${status}" -eq 0 ]
    [ "${OUT_LINES}" -eq 3 ]
    [ "${OUT_FAILED}" = "true" ]
    [ "${OUT_PUSHED}" = "false" ]
    [ "${OUT_BRANCH}" = "$1" ]
    [ "${FAILURE_STAGE}" = "push" ]
}

# assert_pushed: status 0, pushed=true, failed=false, origin at the agent tip.
function assert_pushed {
    [ "${status}" -eq 0 ]
    [ "${OUT_LINES}" -eq 3 ]
    [ "${OUT_PUSHED}" = "true" ]
    [ "${OUT_FAILED}" = "false" ]
    [ "${OUT_BRANCH}" = "${BRANCH}" ]
    [ ! -e "${FAILURE_FILE}" ]
    [ "$(origin_sha "${BRANCH}")" = "$(git -C "${AGENT}" rev-parse "refs/heads/${BRANCH}")" ]
}

@test "a bundle with other refs imports only the agent branch" {
    git -C "${AGENT}" checkout -q -b other origin/main
    agent_commit other.txt
    make_agent_branch
    agent_commit docs/a.md
    make_bundle refs/heads/other
    run git bundle list-heads "${BUNDLE_DIR}/branch.bundle"
    [[ $output == *"refs/heads/other"* ]]

    run_push
    assert_pushed
    [ -z "$(origin_sha other)" ]
    run git -C "${FINAL}" rev-parse -q --verify refs/heads/other
    [ "${status}" -ne 0 ]
}

@test "a descendant tip of from.ref is pushed" {
    make_agent_branch "${PR_HEAD_SHA}"
    agent_commit docs/a.md
    make_bundle
    # src/pr.sh is between origin/main and from.ref, so only <from.ref>..<branch> passes
    T_ALLOWLIST='docs/**'
    T_TARGET="{\"from\":{\"ref\":\"${PR_HEAD_SHA}\"}}"
    run_push
    assert_pushed
}

@test "a force-pushed PR head still verifies against base" {
    local gone_sha
    make_agent_branch "${PR_HEAD_SHA}"
    agent_commit docs/a.md
    make_bundle
    # A head commit the agent branch does not contain, then force-pushed away
    git -C "${AGENT}" checkout -q -b scratch "${PR_HEAD_SHA}"
    agent_commit src/gone.sh
    gone_sha="$(git -C "${AGENT}" rev-parse HEAD)"
    git -C "${AGENT}" push -q origin "${gone_sha}:refs/heads/feature/pr-head"
    git -C "${AGENT}" checkout -q -b rewritten origin/main
    agent_commit src/new.sh
    git -C "${AGENT}" push -q -f origin HEAD:refs/heads/feature/pr-head

    run_push
    assert_pushed
    run git -C "${FINAL}" cat-file -e "${gone_sha}"
    [ "${status}" -ne 0 ]

    reset_final
    T_TARGET="{\"from\":{\"ref\":\"${gone_sha}\"}}"
    run_push
    assert_failed "${BRANCH}"
    [[ ${FAILURE_MESSAGE} == *"from.ref"* ]]
    [ -z "$(origin_sha "${BRANCH}")" ]
}

@test "a rejected push fails" {
    make_agent_branch
    agent_commit docs/a.md
    make_bundle
    printf '#!/bin/sh\necho denied by hook >&2\nexit 1\n' > "${ORIGIN}/hooks/pre-receive"
    chmod +x "${ORIGIN}/hooks/pre-receive"
    run_push
    assert_failed "${BRANCH}"
    [[ ${FAILURE_MESSAGE} == *"denied by hook"* ]]
    [ -z "$(origin_sha "${BRANCH}")" ]
}

@test "a tip that is not a descendant of from.ref fails" {
    make_agent_branch
    agent_commit docs/a.md
    make_bundle
    T_TARGET="{\"from\":{\"ref\":\"${PR_HEAD_SHA}\"}}"
    run_push
    assert_failed "${BRANCH}"
    [[ ${FAILURE_MESSAGE} == *"from.ref"* ]]
    [ -z "$(origin_sha "${BRANCH}")" ]
}

@test "allowlist and denylist are re-applied" {
    make_agent_branch
    agent_commit src/a.sh
    make_bundle
    T_ALLOWLIST='docs/**'
    run_push
    assert_failed "${BRANCH}"
    [[ ${FAILURE_MESSAGE} == *"src/a.sh"* ]]
    [ -z "$(origin_sha "${BRANCH}")" ]

    reset_final
    make_agent_branch
    agent_commit config/.env
    make_bundle
    T_ALLOWLIST=''
    T_DENYLIST=''
    run_push
    assert_failed "${BRANCH}"
    [[ ${FAILURE_MESSAGE} == *"config/.env"* ]]
    [ -z "$(origin_sha "${BRANCH}")" ]
}

@test "an empty from.ref diffs against origin/base" {
    make_agent_branch
    agent_commit docs/a.md
    make_bundle
    # origin/main moves on with a path outside the allowlist after the bundle
    git -C "${AGENT}" checkout -q main
    agent_commit src/later.sh
    git -C "${AGENT}" push -q origin main
    T_ALLOWLIST='docs/**'
    run_push
    assert_pushed
}

@test "an existing remote branch fails without force" {
    local main_sha
    make_agent_branch
    agent_commit docs/a.md
    make_bundle
    main_sha="$(git -C "${ORIGIN}" rev-parse refs/heads/main)"
    git -C "${ORIGIN}" update-ref "refs/heads/${BRANCH}" "${main_sha}"
    run_push
    assert_failed "${BRANCH}"
    [[ ${FAILURE_MESSAGE} == *"already exists"* ]]
    [ "$(origin_sha "${BRANCH}")" = "${main_sha}" ]
}

@test "changes under .loop/ are checked like any other path" {
    make_agent_branch
    agent_commit .loop/x.json '{}'
    make_bundle
    T_ALLOWLIST='docs/**'
    run_push
    assert_failed "${BRANCH}"
    [[ ${FAILURE_MESSAGE} == *".loop/x.json"* ]]
}

@test "has_changes true with no bundle fails" {
    run_push
    assert_failed "${BRANCH}"
    [[ ${FAILURE_MESSAGE} == *"bundle"* ]]
    [ -z "$(origin_sha "${BRANCH}")" ]
}

@test "invalid base branches fail" {
    local base
    make_agent_branch
    agent_commit docs/a.md
    make_bundle
    T_BASE=''
    run_push
    assert_failed "${BRANCH}"
    [[ ${FAILURE_MESSAGE} == *"base branch is empty"* ]]
    for base in '-main' '--upload-pack=x' 'ma in' 'main;x' $'main\nx'; do
        T_BASE="${base}"
        run_push
        assert_failed "${BRANCH}"
        [[ ${FAILURE_MESSAGE} == *"invalid base branch"* ]]
        [ -z "$(origin_sha "${BRANCH}")" ]
    done
}

@test "invalid branch names fail" {
    local name
    for name in 'main' 'loop/changelog/../x' 'loop/other/20261018-123456' 'loop/changelog/2026-10-18' \
        'loop/changelog/20261018-123456/x' "-${BRANCH}" $'loop/changelog/20261018-123456\nfailed=false'; do
        T_BRANCH="${name}"
        run_push
        assert_failed ""
    done
    unset T_BRANCH

    T_STATE="${BRANCH}"
    run_push
    assert_failed ""
    unset T_STATE

    T_TO="${BRANCH}"
    run_push
    assert_failed ""
    unset T_TO

    T_PREFIX=''
    run_push
    assert_failed ""
    unset T_PREFIX

    T_SKILL=''
    run_push
    assert_failed ""
}

@test "missing GITHUB_OUTPUT or LOOP_FAILURE_FILE exits 1" {
    run env -u GITHUB_OUTPUT LOOP_FAILURE_FILE="${FAILURE_FILE}" AGENT_BRANCH='' bash "${PUSH_SCRIPT}"
    [ "${status}" -eq 1 ]
    run env -u LOOP_FAILURE_FILE GITHUB_OUTPUT="${OUTPUT_FILE}" AGENT_BRANCH='' bash "${PUSH_SCRIPT}"
    [ "${status}" -eq 1 ]
}

@test "nothing happens for an empty branch" {
    T_BRANCH=''
    run_push
    [ "${status}" -eq 0 ]
    [ "${OUT_LINES}" -eq 3 ]
    [ "${OUT_BRANCH}" = "" ]
    [ "${OUT_PUSHED}" = "false" ]
    [ "${OUT_FAILED}" = "false" ]
    [ ! -e "${FAILURE_FILE}" ]
}

@test "nothing is pushed when the agent failed or has no changes" {
    make_agent_branch
    agent_commit docs/a.md
    make_bundle

    T_RESULT='failure'
    run_push
    [ "${status}" -eq 0 ]
    [ "${OUT_LINES}" -eq 3 ]
    [ "${OUT_BRANCH}" = "${BRANCH}" ]
    [ "${OUT_PUSHED}" = "false" ]
    [ "${OUT_FAILED}" = "false" ]
    [ ! -e "${FAILURE_FILE}" ]
    [ -z "$(origin_sha "${BRANCH}")" ]

    T_RESULT='success'
    T_HAS_CHANGES='false'
    run_push
    [ "${status}" -eq 0 ]
    [ "${OUT_BRANCH}" = "${BRANCH}" ]
    [ "${OUT_PUSHED}" = "false" ]
    [ "${OUT_FAILED}" = "false" ]
    [ ! -e "${FAILURE_FILE}" ]
    [ -z "$(origin_sha "${BRANCH}")" ]
}

@test "pushes a valid bundle and updates origin/<branch>" {
    make_agent_branch
    agent_commit docs/a.md
    make_bundle
    run_push
    assert_pushed
    [ "$(git -C "${FINAL}" rev-parse "refs/remotes/origin/${BRANCH}")" = "$(origin_sha "${BRANCH}")" ]
}

@test "renaming a denylisted file is rejected" {
    make_agent_branch
    mkdir -p "${AGENT}/docs"
    git -C "${AGENT}" mv secrets.txt docs/notes.txt
    git -C "${AGENT}" commit -q -m rename
    make_bundle
    T_ALLOWLIST='docs/**'
    run_push
    assert_failed "${BRANCH}"
    [[ ${FAILURE_MESSAGE} == *"secrets.txt"* ]]
    [ -z "$(origin_sha "${BRANCH}")" ]
}

@test "workflow changes need a .github/ allowlist pattern" {
    make_agent_branch
    agent_commit .github/workflows/x.yaml 'on: push'
    make_bundle

    T_ALLOWLIST='**'
    run_push
    assert_failed "${BRANCH}"
    [[ ${FAILURE_MESSAGE} == *".github/workflows/x.yaml"* ]]

    reset_final
    T_ALLOWLIST=''
    run_push
    assert_failed "${BRANCH}"

    reset_final
    T_ALLOWLIST='.github/**'
    run_push
    assert_pushed
}
