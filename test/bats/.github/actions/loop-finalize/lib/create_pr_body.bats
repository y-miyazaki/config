#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154

# Tests for .github/actions/loop-finalize/lib/create_pr_body.sh
#
# Use cases:
# - create_pr_body renders prefix and footer from inline JSON
# - create_pr_body reads large detect JSON from file and ignores commits[] bulk

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

@test "create_pr_body renders prefix and footer from inline JSON" {
    PR_BODY="## Summary"
    NOTIFY_CONTEXT_JSON='{"changed_files":["CHANGELOG.md"],"agent_report_summary":"done"}'
    DETECT_RESULT_JSON='{"failures":[{"workflow_name":"ci","job_name":"test","failure_type":"test","reason":"boom"}]}'
    TARGET_JSON='{"key":"integration:main"}'
    LEVEL="L2"
    SKIP_REASON="none"

    run create_pr_body
    [ "$status" -eq 0 ]
    [[ $output == *"## Summary"* ]]
    [[ $output == *"CHANGELOG.md"* ]]
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
