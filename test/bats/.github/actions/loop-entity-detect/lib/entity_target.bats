#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154

bats_require_minimum_version 1.5.0

# Tests for .github/actions/loop-entity-detect/lib/entity_target.sh
#
# Use cases:
# - build_entity_target_matrix returns an empty array when detect result skips, ignoring result.entity.kind
# - build_entity_target_matrix fails when skip is false and handoff_key or a valid result.entity.kind is missing
# - build_entity_target_matrix merges result.entity over {handoff_key} into target_json.entity
# - build_entity_target_matrix emits target_json without finalize and a matrix row without a duplicate handoff_key
# - build_entity_target_matrix emits target_json.from.branch and from.ref (worktree base)
# - build_entity_target_matrix threads level, agent_edit_target, and agent_edit_allowlist into the maker prompt
# - build_entity_target_matrix fails when the constraints block cannot be emitted (empty level)

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

setup() {
    ENTITY_TARGET_SH="$(bats_workspace_root)/.github/actions/loop-entity-detect/lib/entity_target.sh"
    # shellcheck disable=SC1090,SC1091
    source "${ENTITY_TARGET_SH}"
    DETECT_JSON="${BATS_TEST_TMPDIR}/d.json"
}

# prompt_constraints prints the ## Constraints block (to end) of the first matrix row prompt.
prompt_constraints() {
    jq -r '.[0].prompt' <<< "$1" | sed -n '/^## Constraints$/,$p'
}

@test "build_entity_target_matrix accepts issue and pr entity kinds" {
    local kind checked=0
    for kind in issue pr; do
        printf '{"status":"ok","skip":false,"result":{"handoff_key":"entity:%s:7","entity":{"kind":"%s"}}}' "${kind}" "${kind}" > "${DETECT_JSON}"
        run --separate-stderr build_entity_target_matrix "${DETECT_JSON}" "issue-triage" "issue-triage" "x" "L1" "none" "" ""
        [ "$status" -eq 0 ]
        [ -z "$stderr" ]
        run jq -r '.[0].target_json.entity.kind' <<< "${output}"
        [ "$output" = "${kind}" ]
        checked=$((checked + 1))
    done
    [ "${checked}" -eq 2 ]
}

@test "build_entity_target_matrix emits from.branch and from.ref for the worktree" {
    printf '%s' '{"status":"ok","skip":false,"result":{"handoff_key":"entity:pr:77","entity":{"kind":"pr"}}}' > "${DETECT_JSON}"
    GITHUB_REF_NAME=main GITHUB_SHA=abc123 run build_entity_target_matrix "${DETECT_JSON}" \
        "github-pr-review" "github-pr-review" "review" "L2" "none" "report" "**"
    [ "$status" -eq 0 ]
    run jq -c '[.[0].target_json.from, .[0].target_json.to]' <<< "${output}"
    [ "$output" = '[{"branch":"main","ref":"abc123"},{"branch":"main"}]' ]
}

@test "build_entity_target_matrix emits target_json without finalize and a row without handoff_key" {
    printf '%s' '{"status":"ok","skip":false,"result":{"handoff_key":"entity:issue:7","entity":{"kind":"issue","number":7},"event_name":"issues","event_action":"opened"},"verifier_context":"Issue #7"}' \
        > "${DETECT_JSON}"
    GITHUB_REF_NAME=main GITHUB_SHA=abc123 run build_entity_target_matrix "${DETECT_JSON}" \
        "issue-autofix" "issue-autofix" "x" "L3" "pr_create" "fix" "**"
    [ "$status" -eq 0 ]
    local matrix="${output}"
    run jq -c '.[0].target_json' <<< "${matrix}"
    [ "$output" = '{"key":"entity:issue:7","entity":{"handoff_key":"entity:issue:7","kind":"issue","number":7},"event":{"name":"issues","action":"opened"},"from":{"branch":"main","ref":"abc123"},"to":{"branch":"main"},"loop_name":"issue-autofix"}' ]
    run jq -c 'length, (.[0] | keys)' <<< "${matrix}"
    [ "$output" = $'1\n["prompt","result","target_json","verifier_context"]' ]
}

@test "build_entity_target_matrix fails when skip false and entity kind is invalid" {
    local -a cases=(
        '{}|empty'
        '{"kind":""}|empty'
        '{"kind":"PR"}|PR'
        '{"kind":"pull_request"}|pull_request'
        '{"kind":"repo"}|repo'
    )
    local entry entity got checked=0
    for entry in "${cases[@]}"; do
        entity="${entry%|*}"
        got="${entry##*|}"
        printf '{"status":"ok","skip":false,"result":{"handoff_key":"entity:issue:7","entity":%s}}' "${entity}" > "${DETECT_JSON}"
        run --separate-stderr build_entity_target_matrix "${DETECT_JSON}" "issue-triage" "issue-triage" "x" "L1" "none" "" ""
        [ "$status" -eq 1 ]
        [ -z "$output" ]
        [ "$stderr" = "build_entity_target_matrix: result.entity.kind must be issue or pr when skip=false (got: ${got})" ]
        checked=$((checked + 1))
    done
    [ "${checked}" -eq 5 ]
}

@test "build_entity_target_matrix fails when skip false and handoff_key missing" {
    printf '%s' '{"status":"ok","skip":false,"result":{"issue_number":7,"entity":{"kind":"issue"}}}' > "${DETECT_JSON}"
    run --separate-stderr build_entity_target_matrix "${DETECT_JSON}" "issue-triage" "issue-triage" "x" "L1" "none" "" ""
    [ "$status" -eq 1 ]
    [ "$stderr" = "build_entity_target_matrix: result.handoff_key required when skip=false" ]
}

@test "build_entity_target_matrix fails when skip false and result.entity is absent" {
    printf '%s' '{"status":"ok","skip":false,"result":{"handoff_key":"entity:issue:7"}}' > "${DETECT_JSON}"
    run --separate-stderr build_entity_target_matrix "${DETECT_JSON}" "issue-triage" "issue-triage" "x" "L1" "none" "" ""
    [ "$status" -eq 1 ]
    [ "$stderr" = "build_entity_target_matrix: result.entity.kind must be issue or pr when skip=false (got: empty)" ]
}

@test "build_entity_target_matrix fails when the level is empty" {
    printf '%s' '{"status":"ok","skip":false,"result":{"handoff_key":"entity:issue:7","entity":{"kind":"issue"}}}' > "${DETECT_JSON}"
    run --separate-stderr build_entity_target_matrix "${DETECT_JSON}" "issue-triage" "issue-triage" "x" "" "none" "" ""
    [ "$status" -eq 1 ]
    [ -z "$output" ]
    [ "$stderr" = "::error::Invalid level:  (expected L1, L2, or L3)" ]
}

@test "build_entity_target_matrix keeps handoff_key when result.entity carries kind" {
    printf '%s' '{"status":"ok","skip":false,"result":{"handoff_key":"entity:pr:12","entity":{"kind":"pr","number":12}}}' > "${DETECT_JSON}"
    run build_entity_target_matrix "${DETECT_JSON}" "github-pr-review" "github-pr-review" "x" "L2" "none" "report" "**"
    [ "$status" -eq 0 ]
    run jq -c '.[0].target_json.entity' <<< "${output}"
    [ "$output" = '{"handoff_key":"entity:pr:12","kind":"pr","number":12}' ]
}

@test "build_entity_target_matrix prompt carries the given agent_edit_allowlist" {
    printf '%s' '{"status":"ok","skip":false,"result":{"handoff_key":"entity:issue:7","entity":{"kind":"issue"}}}' > "${DETECT_JSON}"
    run build_entity_target_matrix "${DETECT_JSON}" "issue-autofix" "issue-autofix" "x" "L2" "pr_create" "fix" "docs/**,README.md"
    [ "$status" -eq 0 ]
    run prompt_constraints "${output}"
    [ "$output" = "## Constraints
agent_edit_allowed: true
agent_edit_target: fix
You MUST persist fixes within allowlist; survey-only output is insufficient when agent_edit_allowed is true.
Do not claim files were modified unless git would show real changes.
Allowed paths: docs/**,README.md.
Do NOT modify any other files." ]
}

@test "build_entity_target_matrix prompt reflects the L1 read-only contract" {
    printf '%s' '{"status":"ok","skip":false,"result":{"handoff_key":"entity:issue:7","entity":{"kind":"issue"}}}' > "${DETECT_JSON}"
    run build_entity_target_matrix "${DETECT_JSON}" "issue-triage" "issue-triage" "x" "L1" "none" "" ""
    [ "$status" -eq 0 ]
    run prompt_constraints "${output}"
    [ "$output" = "## Constraints
agent_edit_allowed: false
Do not claim files were modified unless git would show real changes." ]
}

@test "build_entity_target_matrix returns empty array when skip true" {
    local entity checked=0
    for entity in 'null' '{}' '{"kind":"repo"}'; do
        printf '{"status":"ok","skip":true,"result":{"entity":%s}}' "${entity}" > "${DETECT_JSON}"
        run --separate-stderr build_entity_target_matrix "${DETECT_JSON}" "issue-triage" "issue-triage" "x" "L1" "none" "" ""
        [ "$status" -eq 0 ]
        [ "$output" = "[]" ]
        [ -z "$stderr" ]
        checked=$((checked + 1))
    done
    [ "${checked}" -eq 3 ]
}
