#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154

# Tests for .apm/packages/github/.apm/skills/github-pr-review/scripts/detect_pr_review.sh
#
# Use cases:
# - emits handoff_key, report_path, SHAs, and changed_files for a human PR
# - skips bot-authored, draft, fork, and excluded-label PRs
# - skips when a marker review exists; PR_FORCE overrides the marker
# - hydrates PR facts from pull_request_target and workflow_dispatch events
# - errors on a missing or invalid PR number

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

DETECT_SCRIPT="$(apm_skill_script_path github-pr-review detect_pr_review.sh)"
MARKER='<!-- github-pr-review:v1 -->'

# run_detect: Run detect with a clean env plus caller-supplied assignments
run_detect() {
    run env -i PATH="${PATH}" HOME="${HOME}" PR_CHANGED_FILES_JSON='["a.sh"]' "$@" bash "${DETECT_SCRIPT}"
}

@test "does not skip when labels are not excluded" {
    run_detect PR_NUMBER=77 PR_REVIEWS_JSON='[]' PR_LABELS_JSON='["bug"]' PR_EXCLUDE_LABELS=no-loop,loop-automation
    [ "$status" -eq 0 ]
    run jq -e '.skip == false' <<< "${output}"
    [ "$status" -eq 0 ]
}

@test "does not skip when reviews lack the marker" {
    run_detect PR_NUMBER=77 PR_REVIEWS_JSON='[{"body":"lgtm"},{"body":null}]'
    [ "$status" -eq 0 ]
    run jq -e '.skip == false' <<< "${output}"
    [ "$status" -eq 0 ]
}

@test "emits handoff_key and report_path for a human PR" {
    run_detect PR_NUMBER=77 PR_REVIEWS_JSON='[]' PR_BASE_SHA=b1 PR_HEAD_SHA=h1 GITHUB_EVENT_NAME=pull_request_target
    [ "$status" -eq 0 ]
    run jq -e '.skip == false and .result.handoff_key == "entity:pr:77" and .result.report_path == ".loop/review/pr-77.json"
        and .result.base_sha == "b1" and .result.head_sha == "h1" and .result.changed_files == ["a.sh"]
        and .result.event_name == "pull_request_target" and .result.force == false
        and .verifier_context == "PR #77 base b1 head h1 files: 1"' <<< "${output}"
    [ "$status" -eq 0 ]
}

@test "errors on a non-numeric PR number" {
    run_detect PR_NUMBER=abc
    [ "$status" -ne 0 ]
    run jq -e '.status == "error"' <<< "${output}"
    [ "$status" -eq 0 ]
}

@test "errors without a PR number" {
    run_detect
    [ "$status" -ne 0 ]
    run jq -e '.status == "error"' <<< "${output}"
    [ "$status" -eq 0 ]
}

@test "force ignores the marker" {
    run_detect PR_NUMBER=77 PR_FORCE=true PR_REVIEWS_JSON="[{\"body\":\"${MARKER}\\nfindings\"}]"
    [ "$status" -eq 0 ]
    run jq -e '.skip == false and .result.force == true' <<< "${output}"
    [ "$status" -eq 0 ]
}

@test "hydrates from pull_request_target event" {
    local event="${BATS_TEST_TMPDIR}/event.json"
    cat > "${event}" << 'JSON'
{"action":"opened","repository":{"full_name":"o/r"},
 "pull_request":{"number":9,"user":{"type":"User"},"draft":false,
  "head":{"sha":"hh","repo":{"full_name":"o/r"}},"base":{"sha":"bb"},
  "labels":[{"name":"x"}]}}
JSON
    run_detect GITHUB_EVENT_PATH="${event}" GITHUB_EVENT_NAME=pull_request_target PR_REVIEWS_JSON='[]'
    [ "$status" -eq 0 ]
    run jq -e '.skip == false and .result.pr_number == 9 and .result.base_sha == "bb" and .result.head_sha == "hh"
        and .result.event_action == "opened" and .result.event_name == "pull_request_target"' <<< "${output}"
    [ "$status" -eq 0 ]
}

@test "hydrates from workflow_dispatch event" {
    local event="${BATS_TEST_TMPDIR}/event.json"
    printf '%s' '{"inputs":{"pr_number":"77","force":"true"}}' > "${event}"
    run_detect GITHUB_EVENT_PATH="${event}" PR_REVIEWS_JSON='[]'
    [ "$status" -eq 0 ]
    run jq -e '.result.pr_number == 77 and .result.force == true and .result.event_name == "workflow_dispatch"' <<< "${output}"
    [ "$status" -eq 0 ]
}

@test "skips bot-authored PR" {
    run_detect PR_NUMBER=77 PR_REVIEWS_JSON='[]' PR_AUTHOR_TYPE=Bot
    [ "$status" -eq 0 ]
    run jq -e '.skip == true' <<< "${output}"
    [ "$status" -eq 0 ]
}

@test "skips draft PR" {
    run_detect PR_NUMBER=77 PR_REVIEWS_JSON='[]' PR_DRAFT=true
    [ "$status" -eq 0 ]
    run jq -e '.skip == true' <<< "${output}"
    [ "$status" -eq 0 ]
}

@test "skips excluded label" {
    run_detect PR_NUMBER=77 PR_REVIEWS_JSON='[]' PR_LABELS_JSON='["loop-automation"]' PR_EXCLUDE_LABELS=no-loop,loop-automation
    [ "$status" -eq 0 ]
    run jq -e '.skip == true' <<< "${output}"
    [ "$status" -eq 0 ]
}

@test "skips fork PR" {
    run_detect PR_NUMBER=77 PR_REVIEWS_JSON='[]' PR_IS_FORK=true
    [ "$status" -eq 0 ]
    run jq -e '.skip == true' <<< "${output}"
    [ "$status" -eq 0 ]
}

@test "skips fork PR from pull_request_target event" {
    local event="${BATS_TEST_TMPDIR}/event.json"
    cat > "${event}" << 'JSON'
{"action":"opened","repository":{"full_name":"o/r"},
 "pull_request":{"number":9,"user":{"type":"User"},"draft":false,
  "head":{"sha":"hh","repo":{"full_name":"fork/r"}},"base":{"sha":"bb"},"labels":[]}}
JSON
    run_detect GITHUB_EVENT_PATH="${event}" GITHUB_EVENT_NAME=pull_request_target PR_REVIEWS_JSON='[]'
    [ "$status" -eq 0 ]
    run jq -e '.skip == true' <<< "${output}"
    [ "$status" -eq 0 ]
}

@test "skips when a marker review exists" {
    run_detect PR_NUMBER=77 PR_REVIEWS_JSON="[{\"body\":\"${MARKER}\\nfindings\"}]"
    [ "$status" -eq 0 ]
    run jq -e '.skip == true and (.message | test("already reviewed"))' <<< "${output}"
    [ "$status" -eq 0 ]
}
