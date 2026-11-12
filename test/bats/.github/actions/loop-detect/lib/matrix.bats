#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154

# Tests for .github/actions/loop-detect/lib/matrix.sh
#
# Use cases:
# - verifier_context_build_from_result formats changelog commits
# - verifier_context_build_from_result returns empty for empty commits array
# - verifier_context_build_from_result prefers explicit verifier_context
# - verifier_context_build_from_result still formats affected_docs
# - verifier_context_build_from_result renders refactor hints markdown
# - verifier_context_build_from_result returns empty string for empty hints array
# - verifier_context_build_from_result renders tech-debt signals and hotspots markdown with agent_report_file
# - candidate_priority_rank follows DETECT_PRIORITY order
# - shrink_matrix_candidate_for_output strips result and sets handoff_key
# - sort_candidates_by_priority puts integration before pull_request by default
# - sort_candidates_by_priority keeps modes missing from DETECT_PRIORITY, last and in input order

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

@test "verifier_context_build_from_result formats changelog commits" {
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
    run verifier_context_build_from_result "${detect_result}"
    [ "$status" -eq 0 ]
    [[ $output == *"## Changelog Commits"* ]]
    [[ $output == *"file: CHANGELOG.md"* ]]
    [[ $output == *"count: 2"* ]]
    [[ $output == *"**feat(api)**: add endpoint"* ]]
    [[ $output == *"**renovate(mise)**: update pnpm"* ]]
}

@test "verifier_context_build_from_result returns empty for empty commits array" {
    local detect_result='{"commits": []}'
    run verifier_context_build_from_result "${detect_result}"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "verifier_context_build_from_result prefers explicit verifier_context" {
    local detect_result='{
      "verifier_context": "custom context",
      "commits": [{"sha": "abc", "type": "feat", "scope": "", "breaking": false, "subject": "x"}]
    }'
    run verifier_context_build_from_result "${detect_result}"
    [ "$status" -eq 0 ]
    [ "$output" = "custom context" ]
}

@test "verifier_context_build_from_result still formats affected_docs" {
    local detect_result='{
      "changed_files": ["src/a.go"],
      "deleted_files": [],
      "renamed_files": [],
      "affected_docs": ["docs/a.md"]
    }'
    run verifier_context_build_from_result "${detect_result}"
    [ "$status" -eq 0 ]
    [[ $output == *"## Change Detection"* ]]
    [[ $output == *"affected_docs: docs/a.md"* ]]
}

@test "verifier_context_build_from_result renders refactor hints markdown" {
    local detect_result
    detect_result="$(jq -nc '
        {
            scope: "all",
            commit_range: "abc..def",
            hints: [
                {kind: "oversized_unit", path: "scripts/foo.sh", detail: "file lines=450"}
            ]
        }
    ')"
    run verifier_context_build_from_result "${detect_result}"
    [ "$status" -eq 0 ]
    [[ $output == *"## Refactor Hints"* ]]
    [[ $output == *"oversized_unit"* ]]
    [[ $output == *"scripts/foo.sh"* ]]
    [[ $output == *"file lines=450"* ]]
}

@test "verifier_context_build_from_result returns empty string for empty hints array" {
    local detect_result
    detect_result="$(jq -nc '{scope: "all", commit_range: "", hints: []}')"
    run verifier_context_build_from_result "${detect_result}"
    [ "$status" -eq 0 ]
    [ -z "${output}" ]
}

@test "verifier_context_build_from_result renders tech-debt signals and hotspots markdown" {
    local detect_result
    detect_result="$(jq -nc '
        {
            agent_report_file: "docs/report/tech-debt/2026-07-21.md",
            previous_report: "docs/report/tech-debt/2026-07-14.md",
            signals: [
                {
                    kind: "todo_comment",
                    path: "src/app.go",
                    line: 10,
                    snippet: "// TODO: fix"
                }
            ],
            hotspots: [
                {path: "src/app.go", metric: "churn", value: 12, window: "90.days"}
            ],
            warnings: ["sensor skipped"]
        }
    ')"
    run verifier_context_build_from_result "${detect_result}"
    [ "$status" -eq 0 ]
    [[ $output == *$'## Tech Debt Signals\n- agent_report_file: docs/report/tech-debt/2026-07-21.md\n'* ]]
    [[ $output == *"todo_comment"* ]]
    [[ $output == *"src/app.go"* ]]
    [[ $output == *"## Hotspots"* ]]
    [[ $output == *"churn=12"* ]]
    [[ $output == *"sensor skipped"* ]]
}

@test "candidate_priority_rank follows DETECT_PRIORITY order" {
    DETECT_PRIORITY="pull_request,integration"

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

@test "build_prompt_text uses detect marker instead of embedding JSON" {
    local detect_result prompt

    detect_result='{"status":"ok","commits":[{"sha":"abc","type":"feat","scope":"","breaking":false,"subject":"big"}]}'
    prompt="$(build_prompt_text "loop-changelog" "L2" "CHANGELOG.md" "do work" "since" "head" "${detect_result}" "" "0" "fix" "")"

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

@test "sort_candidates_by_priority keeps modes missing from DETECT_PRIORITY, last and in input order" {
    DETECT_PRIORITY="integration"
    CANDIDATES_JSON=(
        '{"target_json":{"mode":"pull_request","key":"pull_request:1"},"prompt":"a"}'
        '{"target_json":{"mode":"integration","key":"integration:main"},"prompt":"b"}'
        '{"target_json":{"mode":"pull_request","key":"pull_request:2"},"prompt":"c"}'
    )

    sort_candidates_by_priority

    [ "${#CANDIDATES_JSON[@]}" -eq 3 ]
    [ "$(jq -r '.target_json.key' <<< "${CANDIDATES_JSON[0]}")" = "integration:main" ]
    [ "$(jq -r '.target_json.key' <<< "${CANDIDATES_JSON[1]}")" = "pull_request:1" ]
    [ "$(jq -r '.target_json.key' <<< "${CANDIDATES_JSON[2]}")" = "pull_request:2" ]
}

@test "sort_candidates_by_priority puts integration before pull_request by default" {
    DETECT_PRIORITY="integration,pull_request"
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
