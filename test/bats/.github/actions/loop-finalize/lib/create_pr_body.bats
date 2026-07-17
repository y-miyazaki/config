#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154

# Tests for .github/actions/loop-finalize/lib/create_pr_body.sh

# Use cases:
# - create_pr_body keeps detect failures and agent summary (no :-{} corruption)
# - create_pr_body falls back when JSON invalid
# - normalize_json_object rejects empty and invalid
# - bash ${VAR:-{}} gotcha still appends extra brace (documentation lock)

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

CREATE_PR_BODY_SCRIPT="$(bats_workspace_root)/.github/actions/loop-finalize/lib/create_pr_body.sh"

setup() {
    bats_source_rel ".github/actions/loop-finalize/lib/create_pr_body.sh"
}

@test 'bash ${VAR:-{}} gotcha appends extra closing brace' {
    # Lock the language gotcha that wiped hybrid PR bodies in production.
    local var
    var='{"a":1}'
    # shellcheck disable=SC2086,SC2295
    [[ "${var:-{}}" == '{"a":1}}' ]]
}

@test "normalize_json_object rejects empty and invalid" {
    run normalize_json_object ''
    [ "$status" -eq 0 ]
    [ "$output" = '{}' ]

    run normalize_json_object 'not-json'
    [ "$status" -eq 0 ]
    [ "$output" = '{}' ]

    run normalize_json_object '{"ok":true}'
    [ "$status" -eq 0 ]
    [ "$output" = '{"ok":true}' ]
}

@test "create_pr_body keeps detect failures and agent summary" {
    local detect notify body
    detect='{"failures":[{"workflow_name":"on-ci-push-markdown","run_url":"https://example/runs/1","job_name":"lint","failure_type":"regression","reason":"MD001"}]}'
    notify="$(jq -nc --arg s $'\n- **Outcome:** MD001 fixed' \
        '{changed_files:["docs/ci-sweeper-test.md"],agent_report_summary:$s}')"

    run env \
        PR_BODY=$'## Summary\n\nAutomated minimal CI fix by `loop-ci-sweeper`.\n\n---\n*This PR was created by a loop automation. Review before merging.*' \
        DETECT_RESULT_JSON="${detect}" \
        NOTIFY_CONTEXT_JSON="${notify}" \
        LEVEL=L2 \
        TARGET_JSON='{"key":"integration:main"}' \
        SKIP_REASON=none \
        bash "${CREATE_PR_BODY_SCRIPT}"
    [ "$status" -eq 0 ]
    body="${output}"
    [[ ${body} == *"## Failure context"* ]]
    [[ ${body} == *"on-ci-push-markdown"* ]]
    [[ ${body} == *"## Changes"* ]]
    [[ ${body} == *"docs/ci-sweeper-test.md"* ]]
    [[ ${body} == *"MD001 fixed"* ]]
    [[ ${body} == *"- Target: \`integration:main\`"* ]]
}

@test "create_pr_body falls back when JSON invalid" {
    run env \
        PR_BODY='## Summary\n\nprefix' \
        DETECT_RESULT_JSON='not-json' \
        NOTIFY_CONTEXT_JSON='also-bad' \
        LEVEL=L2 \
        TARGET_JSON='{' \
        SKIP_REASON=none \
        bash "${CREATE_PR_BODY_SCRIPT}"
    [ "$status" -eq 0 ]
    [[ ${output} == *"## Summary"* ]]
    [[ ${output} != *"## Failure context"* ]]
    [[ ${output} == *"- Level: L2"* ]]
}
