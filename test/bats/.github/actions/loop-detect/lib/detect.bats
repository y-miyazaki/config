#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154

# Tests for .github/actions/loop-detect/lib/detect.sh

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

CHANGELOG_DETECT_SCRIPT="$(apm_skill_script_path loop-changelog detect_changelog_commits.sh)"
DOCS_DETECT_SCRIPT="$(apm_skill_script_path loop-docs-triage detect_changes.sh)"

setup() {
    bats_source_rel ".github/actions/loop-detect/lib/detect.sh"
}

@test "detect_result_skip matches live changelog detect script output" {
    local workspace since_ref json

    workspace="$(bats_workspace_root)"
    if ! since_ref="$(bats_resolve_since_ref "${workspace}")"; then
        skip "not enough git history for relative since ref"
    fi

    run bash -c "cd '${workspace}' && bash '${CHANGELOG_DETECT_SCRIPT}' --scope range --since '${since_ref}'"
    [ "$status" -eq 0 ]
    json="${output}"
    assert_detect_changelog_ok_json "${json}" "range" "${since_ref}"

    if jq -e '.skip == true' <<< "${json}" > /dev/null; then
        run detect_result_skip "${json}"
        [ "$status" -eq 0 ]
    else
        run detect_result_skip "${json}"
        [ "$status" -eq 1 ]
    fi
}

@test "build_verifier_context_from_result formats live docs detect script output" {
    local workspace since_ref json

    workspace="$(bats_workspace_root)"
    if ! since_ref="$(bats_resolve_since_ref "${workspace}")"; then
        skip "not enough git history for relative since ref"
    fi

    run bash -c "cd '${workspace}' && env DOCS_TRIAGE_DOC_GLOBS='docs/**/*.md,README.md' bash '${DOCS_DETECT_SCRIPT}' --scope range --since '${since_ref}'"
    [ "$status" -eq 0 ]
    json="${output}"
    assert_detect_changes_ok_json "${json}" "range" "${since_ref}"

    if jq -e '.skip == false' <<< "${json}" > /dev/null; then
        run build_verifier_context_from_result "${json}"
        [ "$status" -eq 0 ]
        [[ $output == *"## Change Detection"* ]]
        [[ $output == *"affected_docs:"* ]]
    fi
}

@test "write_detect_outputs writes expected action output format" {
    local github_output

    github_output="$(mktemp)"
    GITHUB_OUTPUT="${github_output}"
    write_detect_outputs "false" "no_changes" "[]"

    run grep -Fx 'should_run=false' "${github_output}"
    [ "$status" -eq 0 ]
    run grep -Fx 'skip_reason=no_changes' "${github_output}"
    [ "$status" -eq 0 ]
    run grep -E '^target_matrix<<' "${github_output}"
    [ "$status" -eq 0 ]
    run awk '/^target_matrix<</{found=1;next} found{print; if ($0=="[]") exit}' "${github_output}"
    [ "$status" -eq 0 ]
    [ "$output" = "[]" ]
}

@test "enrich_target_json_with_ci_context adds first failure metadata" {
    local base detect_result enriched

    base='{"mode":"integration","key":"integration:main","from":{"branch":"main","ref":"abc"},"to":{"branch":"main"},"finalize":"open_pr"}'
    detect_result='{"status":"ok","skip":false,"failures":[{"workflow_run_id":"123","workflow_name":"ci-test","head_sha":"def","log_excerpt":"line1\r\nline2"}]}'

    enriched="$(enrich_target_json_with_ci_context "${base}" "${detect_result}" 2> /dev/null)"
    run jq -e '.workflow_run_id == "123" and .workflow_name == "ci-test" and .head_sha == "def"' <<< "${enriched}"
    [ "$status" -eq 0 ]
}

@test "build_loop_candidate_json rejects empty target_json with error annotation" {
    local detect_result

    detect_result='{"status":"ok","skip":false,"failures":[]}'

    run build_loop_candidate_json "integration:main" "" "prompt" "context" "${detect_result}"
    [ "$status" -eq 1 ]
    [[ $output == *"::error::loop-detect:"* ]]
    [[ $output == *"target_json is empty"* ]]
}

@test "build_loop_candidate_json rejects invalid detect_result with diagnostic error" {
    local target_json detect_result

    target_json='{"mode":"integration","key":"integration:main"}'
    detect_result='not-json'

    run build_loop_candidate_json "integration:main" "${target_json}" "prompt" "context" "${detect_result}"
    [ "$status" -eq 1 ]
    [[ $output == *"::error::loop-detect:"* ]]
    [[ $output == *"detect_result is not valid JSON"* ]]
    [[ $output == *"jq_error="* ]]
    [[ $output == *"preview="* ]]
}

@test "build_loop_candidate_json assembles valid candidate JSON" {
    local target_json detect_result candidate

    target_json='{"mode":"integration","key":"integration:main","workflow_run_id":"123"}'
    detect_result='{"status":"ok","skip":false,"failures":[{"workflow_run_id":"123"}]}'

    candidate="$(build_loop_candidate_json "integration:main" "${target_json}" "do work" "verify" "${detect_result}" 2> /dev/null)"
    run jq -e '.target_json.key == "integration:main" and .prompt == "do work" and .result.skip == false' <<< "${candidate}"
    [ "$status" -eq 0 ]
}
