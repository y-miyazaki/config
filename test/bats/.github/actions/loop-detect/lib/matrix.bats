#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154

# Tests for .github/actions/loop-detect/lib/matrix.sh

# Use cases:
# - build_verifier_context_from_result formats changelog commits
# - build_verifier_context_from_result returns empty for empty commits array
# - build_verifier_context_from_result prefers explicit verifier_context
# - build_verifier_context_from_result still formats affected_docs
# - candidate_priority_rank follows LOOP_PRIORITY order
# - shrink_matrix_candidate_for_output strips result and sets handoff_key
# - sort_candidates_by_priority puts integration before pull_request by default

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

setup() {
    # matrix.sh helpers depend on split_csv from branches.sh via _init.
    bats_source_rel ".github/actions/loop-detect/lib/_init.sh"
}

@test "build_verifier_context_from_result formats changelog commits" {
    local detect_result
    detect_result='{
      "changelog_file": "CHANGELOG.md",
      "commits": [
        {
          "sha": "123456789012",
          "type": "feat",
          "scope": "api",
          "breaking": false,
          "subject": "add endpoint"
        },
        {
          "sha": "123456789012",
          "type": "renovate",
          "scope": "mise",
          "breaking": false,
          "subject": "update pnpm"
        }
      ]
    }'
    run build_verifier_context_from_result "${detect_result}"
    [ "$status" -eq 0 ]
    [[ $output == *"## Changelog Commits"* ]]
    [[ $output == *"file: CHANGELOG.md"* ]]
    [[ $output == *"count: 2"* ]]
    [[ $output == *"**feat(api)**: add endpoint"* ]]
    [[ $output == *"**renovate(mise)**: update pnpm"* ]]
}

@test "build_verifier_context_from_result returns empty for empty commits array" {
    local detect_result='{"commits": []}'
    run build_verifier_context_from_result "${detect_result}"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "build_verifier_context_from_result prefers explicit verifier_context" {
    local detect_result='{
      "verifier_context": "custom context",
      "commits": [{"sha": "abc", "type": "feat", "scope": "", "breaking": false, "subject": "x"}]
    }'
    run build_verifier_context_from_result "${detect_result}"
    [ "$status" -eq 0 ]
    [ "$output" = "custom context" ]
}

@test "build_verifier_context_from_result still formats affected_docs" {
    local detect_result='{
      "changed_files": ["src/a.go"],
      "deleted_files": [],
      "renamed_files": [],
      "affected_docs": ["docs/a.md"]
    }'
    run build_verifier_context_from_result "${detect_result}"
    [ "$status" -eq 0 ]
    [[ $output == *"## Change Detection"* ]]
    [[ $output == *"affected_docs: docs/a.md"* ]]
}

@test "candidate_priority_rank follows LOOP_PRIORITY order" {
    LOOP_PRIORITY="pull_request,integration"

    run candidate_priority_rank "pull_request"
    [ "$status" -eq 0 ]
    [ "$output" = "1" ]

    run candidate_priority_rank "integration"
    [ "$status" -eq 0 ]
    [ "$output" = "2" ]

    run candidate_priority_rank "unknown"
    [ "$status" -eq 0 ]
    [ "$output" = "99" ]
}

@test "sort_candidates_by_priority puts integration before pull_request by default" {
    LOOP_PRIORITY="integration,pull_request"
    CANDIDATES_JSON=(
        '{"target_json":{"mode":"pull_request","key":"pull_request:265"},"prompt":"pr"}'
        '{"target_json":{"mode":"integration","key":"integration:main"},"prompt":"int"}'
    )

    sort_candidates_by_priority

    [ "${#CANDIDATES_JSON[@]}" -eq 2 ]
    run jq -r '.target_json.key' <<< "${CANDIDATES_JSON[0]}"
    [ "$output" = "integration:main" ]
    run jq -r '.target_json.key' <<< "${CANDIDATES_JSON[1]}"
    [ "$output" = "pull_request:265" ]
}

@test "build_prompt_text uses detect marker instead of embedding JSON" {
    local detect_result prompt

    detect_result='{"status":"ok","commits":[{"sha":"abc","type":"feat","scope":"","breaking":false,"subject":"big"}]}'
    prompt="$(build_prompt_text "loop-changelog" "L2" "CHANGELOG.md" "do work" "since" "head" "${detect_result}" "" "0")"

    [[ ${prompt} == *"__LOOP_DETECT_RESULT_JSON__"* ]]
    [[ ${prompt} != *'"commits"'* ]]
    [[ ${prompt} == *"## Instructions"* ]]
}

@test "shrink_matrix_candidate_for_output strips result and sets handoff_key" {
    local candidate shrunk

    candidate='{"target_json":{"key":"integration:main"},"prompt":"p","verifier_context":"big","result":{"skip":false}}'
    shrunk="$(shrink_matrix_candidate_for_output "${candidate}")"
    run jq -e '.handoff_key == "integration:main" and .verifier_context == "" and (.result? | not)' <<< "${shrunk}"
    [ "$status" -eq 0 ]
}
