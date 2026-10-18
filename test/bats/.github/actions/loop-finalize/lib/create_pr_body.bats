#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154

# Tests for .github/actions/loop-finalize/lib/create_pr_body.sh
#
# Use cases:
# - create_pr_body renders prefix and footer from inline JSON
# - create_pr_body reads large detect JSON from file and ignores commits[] bulk
# - create_pr_body prefers AGENT_BRANCH over target integration branch for blob links
# - create_pr_body carries engine, model and tokens in the loop meta block
# - create_pr_body carries outcome into the loop meta table
# - create_pr_body keeps commit and release SHAs so the agent report can link them

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

setup() {
    bats_source_rel ".github/actions/loop-finalize/lib/create_pr_body.sh"
    PR_BODY_TMP="${BATS_TEST_TMPDIR}/create-pr-body"
    mkdir -p "${PR_BODY_TMP}"
}

@test "create_pr_body carries engine model and tokens in the loop meta block" {
    PR_BODY=""
    NOTIFY_CONTEXT_JSON='{"changed_files":[],"agent_report_overview":"","agent_report_summary":""}'
    DETECT_RESULT_JSON='{"failures":[]}'
    TARGET_JSON='{"key":"integration:main"}'
    LEVEL="L2"
    SKIP_REASON="none"
    AGENT_ENGINE="cursor"
    USAGE_JSON='{"total_input_tokens":100000,"total_output_tokens":100000,"model":"Composer-2.5"}'

    run create_pr_body
    [ "$status" -eq 0 ]
    [[ $output == *"| engine | cursor |"* ]]
    [[ $output == *"| model | Composer-2.5 |"* ]]
    [[ $output == *"| tokens | In/Out 100K/100K |"* ]]
}

@test "create_pr_body carries outcome into the loop meta table" {
    PR_BODY=""
    NOTIFY_CONTEXT_JSON='{"changed_files":[],"agent_report_overview":"","agent_report_summary":""}'
    DETECT_RESULT_JSON='{"failures":[]}'
    TARGET_JSON='{"key":"integration:main"}'
    LEVEL="L2"
    SKIP_REASON="none"
    OUTCOME="pr_created"

    run create_pr_body
    [ "$status" -eq 0 ]
    [[ $output == *"<summary>Meta</summary>"* ]]
    [[ $output == *"| outcome | pr_created |"* ]]
    [[ $output != *"<code>unknown</code>"* ]]
}

@test "create_pr_body renders prefix and footer from inline JSON" {
    PR_BODY="## Summary"
    NOTIFY_CONTEXT_JSON='{"changed_files":["CHANGELOG.md"],"agent_report_overview":"Updated changelog from 4 commits.","agent_report_summary":"done"}'
    DETECT_RESULT_JSON='{"failures":[{"workflow_name":"ci","job_name":"test","failure_type":"test","reason":"boom"}]}'
    TARGET_JSON='{"key":"integration:main"}'
    LEVEL="L2"
    SKIP_REASON="none"

    run create_pr_body
    [ "$status" -eq 0 ]
    [[ $output == *"## Overview"* ]]
    [[ $output == *"Updated changelog"* ]]
    [[ $output == *"CHANGELOG.md"* ]]
    [[ $output == *"<summary>Meta</summary>"* ]]
    [[ $output == *"integration:main"* ]]
    [[ $output == *"## Failure context"* ]]
}

@test "create_pr_body reads large detect JSON from file and ignores commits bulk" {
    local detect_file notify_file target_file padding i

    detect_file="$(mktemp "${PR_BODY_TMP}/tmp.XXXXXX")"
    notify_file="$(mktemp "${PR_BODY_TMP}/tmp.XXXXXX")"
    target_file="$(mktemp "${PR_BODY_TMP}/tmp.XXXXXX")"
    padding="$(printf 'x%.0s' {1..120})"
    {
        printf '{"commits":['
        for i in $(seq 1 2000); do
            [[ ${i} -gt 1 ]] && printf ','
            printf '{"sha":"sha%d","subject":"%s","type":"chore"}' "${i}" "${padding}"
        done
        printf '],"failures":[]}'
    } > "${detect_file}"
    jq -nc '{changed_files:[],agent_report_summary:""}' > "${notify_file}"
    jq -nc '{key:"integration:main"}' > "${target_file}"
    [ "$(wc -c < "${detect_file}")" -gt 131072 ]

    PR_BODY="Automated update"
    SKIP_REASON="none"
    export PR_BODY SKIP_REASON

    run bash "$(bats_workspace_root)/.github/actions/loop-finalize/lib/create_pr_body.sh" \
        --detect-json-file "${detect_file}" \
        --notify-json-file "${notify_file}" \
        --target-json-file "${target_file}"
    [ "$status" -eq 0 ]
    [[ $output == *"Automated update"* ]]
    [[ $output != *"## Failure context"* ]]
}

@test "create_pr_body prefers AGENT_BRANCH over target integration branch for blob links" {
    AGENT_BRANCH='loop/ci-sweeper-fix'
    GITHUB_REPOSITORY='org/repo'
    GITHUB_SERVER_URL='https://github.com'
    NOTIFY_CONTEXT_JSON='{"changed_files":["docs/a.md"],"agent_report_overview":"","agent_report_summary":""}'
    DETECT_RESULT_JSON='{"failures":[]}'
    TARGET_JSON='{"key":"integration:main","from":{"branch":"main"},"to":{"branch":"main"}}'
    LEVEL="L2"
    SKIP_REASON="none"
    PR_BODY=""

    run create_pr_body
    [ "$status" -eq 0 ]
    [[ $output == *"[docs/a.md](https://github.com/org/repo/blob/loop/ci-sweeper-fix/docs/a.md)"* ]]
    [[ $output != *"/blob/main/docs/a.md"* ]]
}

@test "create_pr_body keeps commit and release SHAs so the agent report can link them" {
    local sha_a="abcdef0123456789abcdef0123456789abcdef01"
    local sha_b="1234567890abcdef1234567890abcdef12345678"
    PR_BODY=""
    GITHUB_REPOSITORY="org/repo"
    GITHUB_SERVER_URL="https://github.com"
    AGENT_BRANCH="loop/changelog/x"
    SKIP_REASON="none"
    LEVEL="L2"
    DETECT_RESULT_JSON="$(jq -nc --arg a "${sha_a}" --arg b "${sha_b}" \
        '{commits:[{sha:$a,subject:"feat: x"}],releases:[{tag_sha:$b,commit_shas:[$a]}],failures:[]}')"
    NOTIFY_CONTEXT_JSON="$(jq -nc '{changed_files:["CHANGELOG.md"],agent_report_overview:"Recorded changes.",agent_report_summary:"### Changes\n| Commit | Type |\n| --- | --- |\n| abcdef0 | feat |\n| 1234567 | chore |"}')"
    TARGET_JSON='{"key":"integration:main"}'
    export PR_BODY GITHUB_REPOSITORY GITHUB_SERVER_URL AGENT_BRANCH SKIP_REASON LEVEL

    run create_pr_body
    [ "$status" -eq 0 ]
    [[ $output == *"| [abcdef0](https://github.com/org/repo/commit/${sha_a}) |"* ]]
    [[ $output == *"| [1234567](https://github.com/org/repo/commit/${sha_b}) |"* ]]
}
