#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154

# Tests for .github/actions/loop-detect/lib/prs.sh

# Use cases:
# - list_open_prs returns empty when pr_enabled is false
# - pr_excluded allows bot author listed in include_bots
# - pr_excluded excludes bot authors when include_bots is empty
# - pr_excluded excludes draft when draft token is set
# - pr_excluded excludes fork when fork token is set
# - pr_excluded excludes label match
# - pr_excluded excludes wip_title when token is set
# - list_open_prs fails when gh missing and pr_enabled is true

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

setup() {
    bats_source_rel ".github/actions/loop-detect/lib/branches.sh"
    bats_source_rel ".github/actions/loop-detect/lib/prs.sh"
    LOOP_PR_ENABLED="false"
    OPEN_PRS_JSON=()
}

pr_json_with_labels() {
    local labels_json="$1"
    jq -nc --argjson labels "${labels_json}" \
        '{number:1,title:"fix",isDraft:false,author:{login:"alice"},labels:$labels,headRepository:{isFork:false}}'
}

@test "list_open_prs returns empty when pr_enabled is false" {
    LOOP_PR_ENABLED="false"
    run list_open_prs "fork,draft" "" "token"
    [ "$status" -eq 0 ]
    [ "${#OPEN_PRS_JSON[@]}" -eq 0 ]
}

@test "pr_excluded allows bot author listed in include_bots" {
    local pr
    pr='{"number":1,"title":"deps","isDraft":false,"author":{"login":"dependabot"},"labels":[],"headRepository":{"isFork":false}}'
    run pr_excluded "${pr}" "fork" "dependabot"
    [ "$status" -eq 1 ]
}

@test "pr_excluded excludes bot authors when include_bots is empty" {
    local pr
    pr='{"number":1,"title":"deps","isDraft":false,"author":{"login":"dependabot"},"labels":[],"headRepository":{"isFork":false}}'
    run pr_excluded "${pr}" "fork" ""
    [ "$status" -eq 0 ]
}

@test "pr_excluded excludes draft when draft token is set" {
    local pr
    pr='{"number":1,"title":"wip","isDraft":true,"author":{"login":"alice"},"labels":[],"headRepository":{"isFork":false}}'
    run pr_excluded "${pr}" "draft" ""
    [ "$status" -eq 0 ]
}

@test "pr_excluded excludes fork when fork token is set" {
    local pr
    pr='{"number":1,"title":"fix","isDraft":false,"author":{"login":"alice"},"labels":[],"headRepository":{"isFork":true}}'
    run pr_excluded "${pr}" "fork" ""
    [ "$status" -eq 0 ]
}

@test "pr_excluded excludes label match" {
    local pr
    pr="$(pr_json_with_labels '[{"name":"no-loop"}]')"
    run pr_excluded "${pr}" "label:no-loop" ""
    [ "$status" -eq 0 ]
}

@test "pr_excluded excludes wip_title when token is set" {
    local pr
    pr='{"number":1,"title":"WIP: auth refactor","isDraft":false,"author":{"login":"alice"},"labels":[],"headRepository":{"isFork":false}}'
    run pr_excluded "${pr}" "wip_title" ""
    [ "$status" -eq 0 ]
}

@test "list_open_prs fails when gh missing and pr_enabled is true" {
    local repo_root empty_bin

    repo_root="$(bats_workspace_root)"
    empty_bin="${BATS_TEST_TMPDIR}/empty-bin"
    mkdir -p "${empty_bin}"
    run bash -c '
        set -euo pipefail
        # shellcheck disable=SC1091
        source "'"${repo_root}"'/.github/actions/loop-detect/lib/branches.sh"
        # shellcheck disable=SC1091
        source "'"${repo_root}"'/.github/actions/loop-detect/lib/prs.sh"
        LOOP_PR_ENABLED="true"
        PATH="'"${empty_bin}"'"
        command -v gh > /dev/null 2>&1 && exit 99
        list_open_prs "fork" "" "token"
    '
    [ "$status" -eq 1 ]
    [[ $output == *"gh CLI is required"* ]]
}
