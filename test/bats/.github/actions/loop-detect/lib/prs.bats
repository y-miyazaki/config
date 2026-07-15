#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154

# Tests for .github/actions/loop-detect/lib/prs.sh

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

setup() {
    bats_source_rel ".github/actions/loop-detect/lib/branches.sh"
    bats_source_rel ".github/actions/loop-detect/lib/prs.sh"
    LOOP_PULL_REQUESTS="false"
    OPEN_PRS_JSON=()
}

pr_json_with_labels() {
    local labels_json="$1"
    jq -nc --argjson labels "${labels_json}" \
        '{number:1,title:"fix",isDraft:false,author:{login:"alice"},labels:$labels,headRepository:{isFork:false}}'
}

@test "list_open_prs returns empty when pull_requests is false" {
    LOOP_PULL_REQUESTS="false"
    run list_open_prs "fork,draft" "" "token" "label:ci-sweeper-ok"
    [ "$status" -eq 0 ]
    [ "${#OPEN_PRS_JSON[@]}" -eq 0 ]
}

@test "list_open_prs returns empty when pr_require is not configured" {
    LOOP_PULL_REQUESTS="true"
    run list_open_prs "fork,draft" "" "token" ""
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

@test "pr_meets_requirements fails on empty require csv" {
    local pr
    pr="$(pr_json_with_labels '[{"name":"ci-sweeper-ok"}]')"
    run pr_meets_requirements "${pr}" ""
    [ "$status" -eq 1 ]
}

@test "pr_meets_requirements fails on unknown token" {
    local pr
    pr="$(pr_json_with_labels '[{"name":"ci-sweeper-ok"}]')"
    run pr_meets_requirements "${pr}" "author:collaborator"
    [ "$status" -eq 1 ]
}

@test "pr_meets_requirements fails when required label is missing" {
    local pr
    pr="$(pr_json_with_labels '[{"name":"other"}]')"
    run pr_meets_requirements "${pr}" "label:ci-sweeper-ok"
    [ "$status" -eq 1 ]
}

@test "pr_meets_requirements passes when required label is present" {
    local pr
    pr="$(pr_json_with_labels '[{"name":"ci-sweeper-ok"}]')"
    run pr_meets_requirements "${pr}" "label:ci-sweeper-ok"
    [ "$status" -eq 0 ]
}

@test "pr_meets_requirements requires all labels when multiple tokens" {
    local pr
    pr="$(pr_json_with_labels '[{"name":"ci-sweeper-ok"}]')"
    run pr_meets_requirements "${pr}" "label:ci-sweeper-ok,label:ready"
    [ "$status" -eq 1 ]

    pr="$(pr_json_with_labels '[{"name":"ci-sweeper-ok"},{"name":"ready"}]')"
    run pr_meets_requirements "${pr}" "label:ci-sweeper-ok,label:ready"
    [ "$status" -eq 0 ]
}

@test "pr_require_configured fails closed when pull_requests true and require empty" {
    LOOP_PULL_REQUESTS="true"
    run pr_require_configured ""
    [ "$status" -eq 1 ]
}

@test "pr_require_configured passes when pull_requests false even if require empty" {
    LOOP_PULL_REQUESTS="false"
    run pr_require_configured ""
    [ "$status" -eq 0 ]
}

@test "pr_require_configured passes when require has label token" {
    LOOP_PULL_REQUESTS="true"
    run pr_require_configured "label:ci-sweeper-ok"
    [ "$status" -eq 0 ]
}
