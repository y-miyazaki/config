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
# - fails closed when required facts cannot be fetched (no gh, gh failure)
# - hydrates workflow_dispatch facts, reviews, and paginated changed files via a stub gh
# - does not fetch changed files for a skipped PR
# - treats an event with a missing repository name as a fork

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

# stub_gh: Create a stub gh on PATH_STUB; behavior driven by env
#   GH_PR_VIEW_JSON  stdout for `gh pr view`
#   GH_FILES_OUT     stdout for `gh api .../files` (one filename per line, pages concatenated)
#   GH_REVIEWS_OUT   stdout for `gh api .../reviews`
#   GH_FAIL          when set, every call logs and exits 1
stub_gh() {
    mkdir -p "${BATS_TEST_TMPDIR}/bin"
    cat > "${BATS_TEST_TMPDIR}/bin/gh" << 'STUB'
#!/bin/bash
echo "$*" >> "${GH_LOG:-/dev/null}"
if [[ -n ${GH_FAIL:-} ]]; then exit 1; fi
if [[ $1 == "pr" && $2 == "view" ]]; then printf '%s' "${GH_PR_VIEW_JSON:-}"; exit 0; fi
if [[ $1 == "api" ]]; then
    case "$*" in
        */files*) printf '%s' "${GH_FILES_OUT:-}" ;;
        */reviews*) printf '%s' "${GH_REVIEWS_OUT:-[]}" ;;
    esac
    exit 0
fi
exit 1
STUB
    chmod +x "${BATS_TEST_TMPDIR}/bin/gh"
}

# run_dispatch: workflow_dispatch run with stub gh and token env; extra args are env assignments
run_dispatch() {
    local event="${BATS_TEST_TMPDIR}/dispatch.json"
    printf '%s' '{"inputs":{"pr_number":"5"}}' > "${event}"
    stub_gh
    run env -i PATH="${BATS_TEST_TMPDIR}/bin:${PATH}" HOME="${HOME}" GH_TOKEN=x GITHUB_REPOSITORY=o/r \
        GITHUB_EVENT_PATH="${event}" GH_LOG="${BATS_TEST_TMPDIR}/gh.log" "$@" bash "${DETECT_SCRIPT}"
}

PR_VIEW_OK='{"author":{"is_bot":false},"isDraft":false,"isCrossRepository":false,"labels":[],"baseRefOid":"bb","headRefOid":"hh"}'

@test "dispatch hydration emits facts, marker-free reviews, and paginated files" {
    run_dispatch GH_PR_VIEW_JSON="${PR_VIEW_OK}" GH_REVIEWS_OUT='[{"body":"x"}]' GH_FILES_OUT=$'a.sh\nb.sh\nc.sh\n'
    [ "$status" -eq 0 ]
    run jq -e '.skip == false and .result.base_sha == "bb" and .result.head_sha == "hh"
        and .result.changed_files == ["a.sh","b.sh","c.sh"] and .result.event_name == "workflow_dispatch"' <<< "${output}"
    [ "$status" -eq 0 ]
    run grep -c -- '--paginate' "${BATS_TEST_TMPDIR}/gh.log"
    [ "$output" -ge 2 ]
}

@test "dispatch hydration skips a bot author" {
    run_dispatch GH_PR_VIEW_JSON='{"author":{"is_bot":true},"isDraft":false,"isCrossRepository":false,"labels":[],"baseRefOid":"bb","headRefOid":"hh"}' \
        GH_REVIEWS_OUT='[]' GH_FILES_OUT=$'a.sh\n'
    [ "$status" -eq 0 ]
    run jq -e '.skip == true' <<< "${output}"
    [ "$status" -eq 0 ]
}

@test "dispatch hydration skips a draft PR" {
    run_dispatch GH_PR_VIEW_JSON='{"author":{"is_bot":false},"isDraft":true,"isCrossRepository":false,"labels":[],"baseRefOid":"bb","headRefOid":"hh"}'
    [ "$status" -eq 0 ]
    run jq -e '.skip == true' <<< "${output}"
    [ "$status" -eq 0 ]
}

@test "dispatch hydration skips a fork PR" {
    run_dispatch GH_PR_VIEW_JSON='{"author":{"is_bot":false},"isDraft":false,"isCrossRepository":true,"labels":[],"baseRefOid":"bb","headRefOid":"hh"}'
    [ "$status" -eq 0 ]
    run jq -e '.skip == true' <<< "${output}"
    [ "$status" -eq 0 ]
}

@test "dispatch hydration skips an excluded label" {
    run_dispatch PR_EXCLUDE_LABELS=no-loop \
        GH_PR_VIEW_JSON='{"author":{"is_bot":false},"isDraft":false,"isCrossRepository":false,"labels":[{"name":"no-loop"}],"baseRefOid":"bb","headRefOid":"hh"}'
    [ "$status" -eq 0 ]
    run jq -e '.skip == true' <<< "${output}"
    [ "$status" -eq 0 ]
}

@test "dispatch hydration skips when gh reports a marker review" {
    run_dispatch GH_PR_VIEW_JSON="${PR_VIEW_OK}" GH_REVIEWS_OUT="[{\"body\":\"${MARKER}\"}]"
    [ "$status" -eq 0 ]
    run jq -e '.skip == true and (.message | test("already reviewed"))' <<< "${output}"
    [ "$status" -eq 0 ]
}

@test "does not call gh for changed files when the PR is skipped" {
    stub_gh
    run env -i PATH="${BATS_TEST_TMPDIR}/bin:${PATH}" HOME="${HOME}" GH_TOKEN=x GITHUB_REPOSITORY=o/r GH_FAIL=1 \
        GH_LOG="${BATS_TEST_TMPDIR}/gh.log" PR_NUMBER=77 PR_DRAFT=true PR_REVIEWS_JSON='[]' bash "${DETECT_SCRIPT}"
    [ "$status" -eq 0 ]
    run jq -e '.skip == true and .result.changed_files == []' <<< "${output}"
    [ "$status" -eq 0 ]
    [ ! -s "${BATS_TEST_TMPDIR}/gh.log" ]
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

@test "errors when changed files cannot be fetched and are not seeded" {
    run env -i PATH="${PATH}" HOME="${HOME}" PR_NUMBER=77 PR_REVIEWS_JSON='[]' bash "${DETECT_SCRIPT}"
    [ "$status" -ne 0 ]
    run jq -e '.status == "error"' <<< "${output}"
    [ "$status" -eq 0 ]
}

@test "errors when gh fails during dispatch hydration" {
    run_dispatch GH_FAIL=1
    [ "$status" -ne 0 ]
    run jq -e '.status == "error"' <<< "${output}"
    [ "$status" -eq 0 ]
}

@test "errors when gh is unavailable and PR facts are not seeded" {
    local event="${BATS_TEST_TMPDIR}/dispatch.json"
    printf '%s' '{"inputs":{"pr_number":"5"}}' > "${event}"
    run_detect GITHUB_EVENT_PATH="${event}" PR_REVIEWS_JSON='[]'
    [ "$status" -ne 0 ]
    run jq -e '.status == "error"' <<< "${output}"
    [ "$status" -eq 0 ]
}

@test "errors when reviews cannot be fetched and are not seeded" {
    run_detect PR_NUMBER=77
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
    run_detect GITHUB_EVENT_PATH="${event}" PR_REVIEWS_JSON='[]' PR_AUTHOR_TYPE=User PR_DRAFT=false PR_IS_FORK=false \
        PR_LABELS_JSON='[]' PR_BASE_SHA=bb PR_HEAD_SHA=hh
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

@test "treats an event with a missing repository name as a fork" {
    local event="${BATS_TEST_TMPDIR}/event.json"
    cat > "${event}" << 'JSON'
{"action":"opened",
 "pull_request":{"number":9,"user":{"type":"User"},"draft":false,
  "head":{"sha":"hh"},"base":{"sha":"bb"},"labels":[]}}
JSON
    run_detect GITHUB_EVENT_PATH="${event}" GITHUB_EVENT_NAME=pull_request_target PR_REVIEWS_JSON='[]'
    [ "$status" -eq 0 ]
    run jq -e '.skip == true' <<< "${output}"
    [ "$status" -eq 0 ]
}
