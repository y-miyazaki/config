#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154

# Tests for .github/actions/loop-state-promote/lib/run.sh

# Use cases:
# - merged=true → pending.sha becomes last_sha; pending cleared; counters reset
# - merged=false → pending cleared only; last_sha unchanged; [skip ci] commit
# - empty STATE_PUSH_BRANCH → repository default only (never fix-PR heads; clear + promote)
# - multi-target / multi-file → only matching pending.pr rows updated
# - invalid branch / no match → fail or no-op safely

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

PROMOTE_SCRIPT="$(bats_workspace_root)/.github/actions/loop-state-promote/lib/run.sh"

state_promote_git_setup() {
    STATE_PROMOTE_BARE="${BATS_TEST_TMPDIR}/origin.git"
    STATE_PROMOTE_WORK="${BATS_TEST_TMPDIR}/work"
    rm -rf "${STATE_PROMOTE_BARE}" "${STATE_PROMOTE_WORK}"
    git init -q "${STATE_PROMOTE_WORK}"
    git -C "${STATE_PROMOTE_WORK}" config user.email "test@example.com"
    git -C "${STATE_PROMOTE_WORK}" config user.name "Test User"
    git -C "${STATE_PROMOTE_WORK}" checkout -q -b main
    mkdir -p "${STATE_PROMOTE_WORK}/.loop"
    printf '%s\n' \
        '{"targets":{"integration:main":{"last_sha":"oldsha000000","pending":{"sha":"newsha111111","pr":42},"consecutive_failures":2,"open_rejections":[{"attempt":1}]}}}' \
        > "${STATE_PROMOTE_WORK}/.loop/state-changelog.json"
    git -C "${STATE_PROMOTE_WORK}" add .loop/state-changelog.json
    git -C "${STATE_PROMOTE_WORK}" commit -q -m "chore: init state"
    git init -q --bare "${STATE_PROMOTE_BARE}"
    git -C "${STATE_PROMOTE_WORK}" remote add origin "${STATE_PROMOTE_BARE}"
    git -C "${STATE_PROMOTE_WORK}" push -q -u origin main
}

state_promote_install_gh_default_main() {
    local mock_bin="${BATS_TEST_TMPDIR}/bin"
    mkdir -p "${mock_bin}"
    cat > "${mock_bin}/gh" << 'EOF'
#!/usr/bin/env bash
if [[ $1 == "repo" && $2 == "view" ]]; then
    printf '%s\n' "main"
    exit 0
fi
exit 1
EOF
    chmod +x "${mock_bin}/gh"
    printf '%s' "${mock_bin}"
}

state_promote_run() {
    run bash -c "cd '${STATE_PROMOTE_WORK}' && $(printf '%q ' "${@}") bash '${PROMOTE_SCRIPT}'"
}

state_promote_origin_json() {
    local branch="$1"
    local file="$2"
    git -C "${STATE_PROMOTE_WORK}" fetch -q origin
    git -C "${STATE_PROMOTE_WORK}" show "origin/${branch}:${file}"
}

setup() {
    state_promote_git_setup
}

@test "run.sh clears pending and preserves last_sha when merged is false" {
    state_promote_run \
        GH_TOKEN='test-token' \
        GITHUB_REPOSITORY='test/repo' \
        MERGED='false' \
        PR_NUMBER='42' \
        STATE_PUSH_BRANCH='main'
    [ "$status" -eq 0 ]
    run jq -e \
        '.targets["integration:main"].outcome == "pr-closed"
         and (.targets["integration:main"] | has("pending") | not)
         and .targets["integration:main"].last_sha == "oldsha000000"' \
        "${STATE_PROMOTE_WORK}/.loop/state-changelog.json"
    [ "$status" -eq 0 ]
}

@test "run.sh commits state with skip ci trailer" {
    state_promote_run \
        GH_TOKEN='test-token' \
        GITHUB_REPOSITORY='test/repo' \
        MERGED='false' \
        PR_NUMBER='42' \
        STATE_PUSH_BRANCH='main'
    [ "$status" -eq 0 ]
    git -C "${STATE_PROMOTE_WORK}" fetch -q origin
    run git -C "${STATE_PROMOTE_WORK}" log -1 --pretty=%s origin/main
    [ "$status" -eq 0 ]
    [[ ${output} == *"[skip ci]"* ]]
    [[ ${output} == *"clear_pending"* ]]
}

@test "run.sh exits cleanly when no pending state matches PR" {
    state_promote_run \
        GH_TOKEN='test-token' \
        GITHUB_REPOSITORY='test/repo' \
        MERGED='true' \
        PR_NUMBER='99' \
        STATE_PUSH_BRANCH='main'
    [ "$status" -eq 0 ]
    [[ ${output} == *"No pending state matched PR #99 on main."* ]]
}

@test "run.sh exits when STATE_PUSH_BRANCH is invalid" {
    state_promote_run \
        GH_TOKEN='test-token' \
        GITHUB_REPOSITORY='test/repo' \
        MERGED='false' \
        PR_NUMBER='42' \
        STATE_PUSH_BRANCH='bad branch'
    [ "$status" -ne 0 ]
    [[ ${output} == *"Invalid state push branch"* ]]
}

@test "run.sh leaves other target pending untouched when clearing one PR" {
    printf '%s\n' \
        '{"targets":{"integration:main":{"pending":{"sha":"sha-a","pr":42}},"pull_request:7":{"pending":{"sha":"sha-b","pr":99}}}}' \
        > "${STATE_PROMOTE_WORK}/.loop/state-changelog.json"
    git -C "${STATE_PROMOTE_WORK}" add .loop/state-changelog.json
    git -C "${STATE_PROMOTE_WORK}" commit -q -m "chore: multi target pending"
    git -C "${STATE_PROMOTE_WORK}" push -q origin main

    state_promote_run \
        GH_TOKEN='test-token' \
        GITHUB_REPOSITORY='test/repo' \
        MERGED='false' \
        PR_NUMBER='42' \
        STATE_PUSH_BRANCH='main'
    [ "$status" -eq 0 ]

    run jq -e \
        '(.targets["integration:main"] | has("pending") | not)
         and .targets["pull_request:7"].pending.pr == 99' \
        "${STATE_PROMOTE_WORK}/.loop/state-changelog.json"
    [ "$status" -eq 0 ]
}

@test "run.sh promotes pending to last_sha when merged is true" {
    state_promote_run \
        GH_TOKEN='test-token' \
        GITHUB_REPOSITORY='test/repo' \
        MERGED='true' \
        PR_NUMBER='42' \
        STATE_PUSH_BRANCH='main'
    [ "$status" -eq 0 ]
    run jq -e \
        '.targets["integration:main"].last_sha == "newsha111111"
         and .targets["integration:main"].outcome == "merged"
         and (.targets["integration:main"] | has("pending") | not)
         and .targets["integration:main"].consecutive_failures == 0
         and (.targets["integration:main"].open_rejections | length) == 0' \
        "${STATE_PROMOTE_WORK}/.loop/state-changelog.json"
    [ "$status" -eq 0 ]
}

@test "run.sh updates only matching state file among multiple loop state files" {
    printf '%s\n' \
        '{"targets":{"integration:main":{"pending":{"sha":"docs-sha","pr":42}}}}' \
        > "${STATE_PROMOTE_WORK}/.loop/state-docs-triage.json"
    git -C "${STATE_PROMOTE_WORK}" add .loop/state-docs-triage.json
    git -C "${STATE_PROMOTE_WORK}" commit -q -m "chore: add docs state"
    git -C "${STATE_PROMOTE_WORK}" push -q origin main

    state_promote_run \
        GH_TOKEN='test-token' \
        GITHUB_REPOSITORY='test/repo' \
        MERGED='true' \
        PR_NUMBER='42' \
        STATE_PUSH_BRANCH='main'
    [ "$status" -eq 0 ]

    run jq -e \
        '.targets["integration:main"].last_sha == "newsha111111"
         and (.targets["integration:main"] | has("pending") | not)' \
        "${STATE_PROMOTE_WORK}/.loop/state-changelog.json"
    [ "$status" -eq 0 ]
    run jq -e \
        '.targets["integration:main"].last_sha == "docs-sha"
         and (.targets["integration:main"] | has("pending") | not)' \
        "${STATE_PROMOTE_WORK}/.loop/state-docs-triage.json"
    [ "$status" -eq 0 ]
}

@test "run.sh with empty STATE_PUSH_BRANCH never pushes clear_pending onto fix-PR head" {
    local mock_bin main_json fix_json

    # Regression for PR #417: promote must not pollute open fix-PR heads with [skip ci].
    git -C "${STATE_PROMOTE_WORK}" checkout -q -b 'loop/fix-pr'
    git -C "${STATE_PROMOTE_WORK}" push -q -u origin 'loop/fix-pr'
    git -C "${STATE_PROMOTE_WORK}" checkout -q main

    mock_bin="$(state_promote_install_gh_default_main)"
    state_promote_run \
        PATH="${mock_bin}:${PATH}" \
        GH_TOKEN='test-token' \
        GITHUB_REPOSITORY='test/repo' \
        MERGED='false' \
        PR_NUMBER='42' \
        STATE_PUSH_BRANCH=''
    [ "$status" -eq 0 ]

    main_json="$(state_promote_origin_json main .loop/state-changelog.json)"
    fix_json="$(state_promote_origin_json 'loop/fix-pr' .loop/state-changelog.json)"

    run jq -e \
        '(.targets["integration:main"] | has("pending") | not)
         and .targets["integration:main"].outcome == "pr-closed"
         and .targets["integration:main"].last_sha == "oldsha000000"' \
        <<< "${main_json}"
    [ "$status" -eq 0 ]

    run jq -e \
        '.targets["integration:main"].pending.pr == 42' \
        <<< "${fix_json}"
    [ "$status" -eq 0 ]
}

@test "run.sh with empty STATE_PUSH_BRANCH promotes onto default only not fix-PR head" {
    local mock_bin main_json fix_json

    git -C "${STATE_PROMOTE_WORK}" checkout -q -b 'loop/fix-pr'
    git -C "${STATE_PROMOTE_WORK}" push -q -u origin 'loop/fix-pr'
    git -C "${STATE_PROMOTE_WORK}" checkout -q main

    mock_bin="$(state_promote_install_gh_default_main)"
    state_promote_run \
        PATH="${mock_bin}:${PATH}" \
        GH_TOKEN='test-token' \
        GITHUB_REPOSITORY='test/repo' \
        MERGED='true' \
        PR_NUMBER='42' \
        STATE_PUSH_BRANCH=''
    [ "$status" -eq 0 ]

    main_json="$(state_promote_origin_json main .loop/state-changelog.json)"
    fix_json="$(state_promote_origin_json 'loop/fix-pr' .loop/state-changelog.json)"

    run jq -e \
        '.targets["integration:main"].last_sha == "newsha111111"
         and (.targets["integration:main"] | has("pending") | not)
         and .targets["integration:main"].outcome == "merged"' \
        <<< "${main_json}"
    [ "$status" -eq 0 ]

    run jq -e \
        '.targets["integration:main"].pending.pr == 42
         and .targets["integration:main"].last_sha == "oldsha000000"' \
        <<< "${fix_json}"
    [ "$status" -eq 0 ]
}
