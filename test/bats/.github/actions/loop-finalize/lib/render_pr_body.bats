#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154

# Tests for .github/actions/loop-finalize/lib/render_pr_body.sh

# Use cases:
# - redact_sensitive_text redacts github tokens
# - render_agent_summary_section omitted when empty
# - render_agent_summary_section wraps heading
# - render_changes_section lists files
# - render_changes_section omitted when empty
# - render_changes_section preserves notify overflow note
# - render_failure_context caps at five with overflow
# - render_failure_context empty when no failures
# - render_failure_context lists one failure
# - render_failure_context lists three failures fully
# - render_failure_context redacts secret-like reason
# - render_agent_overview_section omitted when empty
# - render_agent_overview_section wraps heading
# - render_pr_body empty prefix shows mechanical sections
# - render_pr_body orders prefix overview failure summary changes metadata

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

setup() {
    bats_source_rel ".github/actions/loop-finalize/lib/render_pr_body.sh"
}

@test "redact_sensitive_text redacts github tokens" {
    # Dummy token shape only — not a real credential (ghp_ + 36 alnum).
    run redact_sensitive_text 'token ghp_abcdefghijklmnopqrstuvwxyz0123456789' # pragma: allowlist secret
    [ "$status" -eq 0 ]
    [[ $output == *"[REDACTED]"* ]]
    [[ $output != *"ghp_abcdefghijklmnopqrstuvwxyz0123456789"* ]] # pragma: allowlist secret
}

@test "render_agent_overview_section omitted when empty" {
    run render_agent_overview_section ''
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "render_agent_overview_section wraps heading" {
    run render_agent_overview_section 'CI failed on MD001; fixed heading in docs/foo.md.'
    [ "$status" -eq 0 ]
    [[ $output == *"## Overview"* ]]
    [[ $output == *"MD001"* ]]
}

@test "render_agent_summary_section omitted when empty" {
    run render_agent_summary_section ''
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "render_agent_summary_section wraps heading" {
    run render_agent_summary_section $'- **Outcome:** fixed\n'
    [ "$status" -eq 0 ]
    [[ $output == *"## Summary"* ]]
    [[ $output == *"Outcome"* ]]
}

@test "render_changes_section lists files" {
    run render_changes_section '["docs/a.md","scripts/b.sh"]'
    [ "$status" -eq 0 ]
    [[ $output == *"## Changes"* ]]
    [[ $output == *"$(docs/a.md)"* ]]
    [[ $output == *"$(scripts/b.sh)"* ]]
}

@test "render_changes_section omitted when empty" {
    run render_changes_section '[]'
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "render_changes_section preserves notify overflow note" {
    local files_json
    files_json="$(jq -nc --arg note "… (+5 more)" '
      [range(1;21) | "file-\(.).txt"] + [$note]
    ')"
    run render_changes_section "${files_json}"
    [ "$status" -eq 0 ]
    [[ $output == *"## Changes"* ]]
    [[ $output == *"$(file-1.txt)"* ]]
    [[ $output == *"$(file-20.txt)"* ]]
    [[ $output == *"(+5 more)"* ]]
    [[ $output != *"(+1 more)"* ]]
}

@test "render_failure_context caps at five with overflow" {
    local json
    json="$(jq -nc '{failures:[range(1;8)|{workflow_name:("wf-\(.)"),run_url:("u\(.)"),job_name:("j\(.)"),failure_type:"regression",reason:("r\(.)")}]}')"
    FAILURES_MAX=5 run render_failure_context "${json}"
    [ "$status" -eq 0 ]
    [[ $output == *"wf-1"* ]]
    [[ $output == *"wf-5"* ]]
    [[ $output != *"wf-6"* ]]
    [[ $output == *"… and 2 more"* ]]
}

@test "render_failure_context empty when no failures" {
    run render_failure_context '{"failures":[]}'
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "render_failure_context lists one failure" {
    local json='{"failures":[{"workflow_name":"on-ci-push-markdown","run_url":"https://example/runs/1","job_name":"lint","failure_type":"regression","reason":"MD001"}]}'
    run render_failure_context "${json}"
    [ "$status" -eq 0 ]
    [[ $output == *"## Failure context"* ]]
    [[ $output == *"on-ci-push-markdown"* ]]
    [[ $output == *"https://example/runs/1"* ]]
    [[ $output == *"MD001"* ]]
}

@test "render_failure_context lists three failures fully" {
    local json
    json="$(jq -nc '{failures:[
      {workflow_name:"wf-a",run_url:"u1",job_name:"j1",failure_type:"regression",reason:"r1"},
      {workflow_name:"wf-b",run_url:"u2",job_name:"j2",failure_type:"regression",reason:"r2"},
      {workflow_name:"wf-c",run_url:"u3",job_name:"j3",failure_type:"flake",reason:"r3"}
    ]}')"
    run render_failure_context "${json}"
    [ "$status" -eq 0 ]
    [[ $output == *"wf-a"* ]]
    [[ $output == *"wf-b"* ]]
    [[ $output == *"wf-c"* ]]
    [[ $output != *"… and"* ]]
}

@test "render_failure_context redacts secret-like reason" {
    local json='{"failures":[{"workflow_name":"wf","run_url":"https://example/r","job_name":"job","failure_type":"regression","reason":"token ghp_abcdefghijklmnopqrstuvwxyz0123456789"}]}' # pragma: allowlist secret
    run render_failure_context "${json}"
    [ "$status" -eq 0 ]
    [[ $output == *"[REDACTED]"* ]]
    [[ $output != *"ghp_abcdefghijklmnopqrstuvwxyz0123456789"* ]] # pragma: allowlist secret
}

@test "render_run_metadata escapes pipe in skip reason" {
    run render_run_metadata L2 'integration:main' 'foo|bar'
    [ "$status" -eq 0 ]
    [[ $output == *"## Run Metadata"* ]]
    [[ $output == *"foo\\|bar"* ]]
    [[ $output != *"| foo | bar |"* ]]
}

@test "render_pr_body empty prefix shows mechanical sections" {
    export PR_BODY_PREFIX=''
    export AGENT_REPORT_OVERVIEW=''
    export DETECT_RESULT_JSON='{"failures":[{"workflow_name":"wf","run_url":"https://example/r","job_name":"job","failure_type":"regression","reason":"boom"}]}'
    export CHANGED_FILES_JSON='[]'
    export AGENT_REPORT_SUMMARY=''
    export LEVEL=L2
    export TARGET_KEY=integration:main
    export SKIP_REASON=none
    run render_pr_body
    [ "$status" -eq 0 ]
    [[ $output == *"## Failure context"* ]]
    [[ $output == *"## Run Metadata"* ]]
    [[ $output == *"| Level | L2 |"* ]]
    [[ $output != *"## Summary"* ]]
    [[ $output != *"- Level:"* ]]
}

@test "render_pr_body orders prefix overview failure summary changes metadata" {
    export PR_BODY_PREFIX=$'Prefix only.\n'
    export AGENT_REPORT_OVERVIEW='Docs drift scan found stale nav entries.'
    export DETECT_RESULT_JSON='{"failures":[{"workflow_name":"wf","run_url":"https://example/r","job_name":"job","failure_type":"regression","reason":"boom"}]}'
    export CHANGED_FILES_JSON='["docs/x.md"]'
    export AGENT_REPORT_SUMMARY=$'- **Fix applied:** tweak\n'
    export LEVEL=L2
    export TARGET_KEY=integration:main
    export SKIP_REASON=none
    run render_pr_body
    [ "$status" -eq 0 ]
    local prefix_i overview_i fail_i sum_i changes_i meta_i
    prefix_i="$(printf '%s\n' "${output}" | grep -n 'Prefix only' | head -1 | cut -d: -f1)"
    overview_i="$(printf '%s\n' "${output}" | grep -n '## Overview' | head -1 | cut -d: -f1)"
    fail_i="$(printf '%s\n' "${output}" | grep -n '## Failure context' | head -1 | cut -d: -f1)"
    sum_i="$(printf '%s\n' "${output}" | grep -n 'Fix applied' | head -1 | cut -d: -f1)"
    changes_i="$(printf '%s\n' "${output}" | grep -n '## Changes' | head -1 | cut -d: -f1)"
    meta_i="$(printf '%s\n' "${output}" | grep -n '## Run Metadata' | head -1 | cut -d: -f1)"
    [ "${prefix_i}" -lt "${overview_i}" ]
    [ "${overview_i}" -lt "${fail_i}" ]
    [ "${fail_i}" -lt "${sum_i}" ]
    [ "${sum_i}" -lt "${changes_i}" ]
    [ "${changes_i}" -lt "${meta_i}" ]
}
