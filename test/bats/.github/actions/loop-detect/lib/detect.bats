#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154

# Tests for .github/actions/loop-detect/lib/detect.sh

# Use cases:
# - detect_result_skip matches live changelog detect script output
# - build_verifier_context_from_result formats live docs detect script output
# - write_detect_outputs writes expected action output format
# - enrich_target_json_with_ci_context adds first failure metadata
# - build_loop_candidate_json rejects empty target_json with error annotation
# - build_loop_candidate_json rejects invalid detect_result with diagnostic error
# - build_loop_candidate_json assembles valid candidate JSON
# - resolve_detect_script_path converts relative path to absolute
# - resolve_detect_script_path keeps pinned script after cwd changes to stale tree
# - resolve_detect_script_path fails when script is missing
# - resolve_scoped_head_branch prefers LOOP_SCOPED_HEAD_BRANCH
# - resolve_scoped_head_branch uses EVENT_HEAD_BRANCH when workflow_run id is set
# - … and 10 more scenarios covered by @test names

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

@test "build_loop_candidate_json assembles large changelog detect payloads" {
    local target_json detect_result prompt verifier candidate i sha

    target_json='{"mode":"integration","key":"integration:main","from":{"branch":"main","ref":"abc"},"to":{"branch":"main"},"finalize":"open_pr"}'
    detect_result='{"status":"ok","skip":false,"commits":['
    for ((i = 0; i < 400; i++)); do
        sha="$(printf 'a%.039d' "${i}")"
        [[ ${i} -gt 0 ]] && detect_result+=','
        detect_result+="$(jq -nc --arg sha "${sha}" --arg subject "feat: item ${i}" '{sha:$sha,type:"feat",scope:"",breaking:false,subject:$subject}')"
    done
    detect_result+='],"releases":[]}'
    prompt="$(build_prompt_text "loop-changelog" "" "CHANGELOG.md" "instructions" "since" "head" "${detect_result}" "" "0")"
    verifier="$(build_verifier_context_from_result "${detect_result}")"

    candidate="$(build_loop_candidate_json "integration:main" "${target_json}" "${prompt}" "${verifier}" "${detect_result}" 2> /dev/null)"
    run jq -e '(.result.commits | length) == 400 and .target_json.key == "integration:main"' <<< "${candidate}"
    [ "$status" -eq 0 ]
}

# --- UC: pin detect script to branch_state checkout (not target worktree) ---

@test "resolve_detect_script_path converts relative path to absolute" {
    local tmp pinned

    tmp="$(mktemp -d)"
    mkdir -p "${tmp}/scripts"
    printf '%s\n' '#!/bin/bash' 'echo pinned' > "${tmp}/scripts/detect.sh"

    (
        cd "${tmp}"
        DETECT_SCRIPT="scripts/detect.sh"
        resolve_detect_script_path
        printf '%s' "${DETECT_SCRIPT}"
    ) > "${tmp}/out"
    pinned="$(cat "${tmp}/out")"

    [[ ${pinned} == /* ]]
    [[ ${pinned} == */scripts/detect.sh ]]
    [ -f "${pinned}" ]
    rm -rf "${tmp}"
}

@test "resolve_detect_script_path keeps pinned script after cwd changes to stale tree" {
    # Reproduces dogfood failure: PR head checkout has an older detect script;
    # loop-detect must keep invoking the absolute path from the initial checkout.
    local tmp pinned output

    tmp="$(mktemp -d)"
    mkdir -p "${tmp}/scripts" "${tmp}/stale/scripts"
    printf '%s\n' '#!/bin/bash' 'echo pinned' > "${tmp}/scripts/detect.sh"
    printf '%s\n' '#!/bin/bash' 'echo stale' > "${tmp}/stale/scripts/detect.sh"

    (
        cd "${tmp}"
        DETECT_SCRIPT="scripts/detect.sh"
        resolve_detect_script_path
        cd "${tmp}/stale"
        bash "${DETECT_SCRIPT}"
    ) > "${tmp}/out"
    output="$(cat "${tmp}/out")"

    [ "${output}" = "pinned" ]
    rm -rf "${tmp}"
}

@test "resolve_detect_script_path fails when script is missing" {
    local tmp old_pwd

    tmp="$(mktemp -d)"
    old_pwd="$(pwd)"
    cd "${tmp}"
    DETECT_SCRIPT="missing/detect.sh"
    run resolve_detect_script_path
    cd "${old_pwd}"
    rm -rf "${tmp}"

    [ "$status" -ne 0 ]
    [[ $output == *"DETECT_SCRIPT"* ]] || [[ $output == *"::error::"* ]]
}

# --- UC: workflow_run scopes watch list to failed head only ---

@test "resolve_scoped_head_branch prefers LOOP_SCOPED_HEAD_BRANCH" {
    LOOP_SCOPED_HEAD_BRANCH="feature/explicit"
    CI_SWEEPER_WORKFLOW_RUN_ID="29557410488"
    CI_SWEEPER_EVENT_HEAD_BRANCH="main"

    run resolve_scoped_head_branch
    [ "$status" -eq 0 ]
    [ "$output" = "feature/explicit" ]
}

@test "resolve_scoped_head_branch uses EVENT_HEAD_BRANCH when workflow_run id is set" {
    # UC: main markdown failure must not scan open Renovate PRs.
    unset LOOP_SCOPED_HEAD_BRANCH
    CI_SWEEPER_WORKFLOW_RUN_ID="29557410488"
    CI_SWEEPER_EVENT_HEAD_BRANCH="main"

    run resolve_scoped_head_branch
    [ "$status" -eq 0 ]
    [ "$output" = "main" ]
}

@test "resolve_scoped_head_branch is empty for schedule-like runs" {
    unset LOOP_SCOPED_HEAD_BRANCH
    unset CI_SWEEPER_WORKFLOW_RUN_ID
    unset CI_SWEEPER_EVENT_HEAD_BRANCH

    run resolve_scoped_head_branch
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "apply_scoped_head_filter keeps matching integration branch only" {
    INTEGRATION_BRANCHES=("main" "develop")
    OPEN_PRS_JSON=(
        '{"number":265,"headRefName":"renovate/go"}'
        '{"number":409,"headRefName":"renovate/pipx"}'
    )

    apply_scoped_head_filter "main"

    [ "${#INTEGRATION_BRANCHES[@]}" -eq 1 ]
    [ "${INTEGRATION_BRANCHES[0]}" = "main" ]
    [ "${#OPEN_PRS_JSON[@]}" -eq 0 ]
}

@test "apply_scoped_head_filter keeps matching PR head only" {
    INTEGRATION_BRANCHES=("main")
    OPEN_PRS_JSON=(
        '{"number":265,"headRefName":"renovate/mcr.microsoft.com-devcontainers-go-1.26"}'
        '{"number":409,"headRefName":"renovate/pipx-headroom-ai-0.x"}'
    )

    apply_scoped_head_filter "renovate/mcr.microsoft.com-devcontainers-go-1.26"

    [ "${#INTEGRATION_BRANCHES[@]}" -eq 0 ]
    [ "${#OPEN_PRS_JSON[@]}" -eq 1 ]
    run jq -e '.number == 265' <<< "${OPEN_PRS_JSON[0]}"
    [ "$status" -eq 0 ]
}

@test "apply_scoped_head_filter is a no-op when scoped head is empty" {
    INTEGRATION_BRANCHES=("main" "develop")
    OPEN_PRS_JSON=('{"number":1,"headRefName":"feature/a"}')

    apply_scoped_head_filter ""

    [ "${#INTEGRATION_BRANCHES[@]}" -eq 2 ]
    [ "${#OPEN_PRS_JSON[@]}" -eq 1 ]
}

@test "resolve_detect_script_path preserves already-absolute paths" {
    local tmp abs

    tmp="$(mktemp -d)"
    printf '%s\n' '#!/bin/bash' 'echo ok' > "${tmp}/detect.sh"
    abs="${tmp}/detect.sh"
    DETECT_SCRIPT="${abs}"

    resolve_detect_script_path

    [ "${DETECT_SCRIPT}" = "$(realpath "${abs}")" ]
    rm -rf "${tmp}"
}

@test "apply_scoped_head_filter clears all targets when none match" {
    INTEGRATION_BRANCHES=("main")
    OPEN_PRS_JSON=('{"number":265,"headRefName":"renovate/go"}')

    apply_scoped_head_filter "feature/does-not-exist"

    [ "${#INTEGRATION_BRANCHES[@]}" -eq 0 ]
    [ "${#OPEN_PRS_JSON[@]}" -eq 0 ]
}

@test "require_scoped_head_for_workflow_run fails closed when run id set without head" {
    CI_SWEEPER_WORKFLOW_RUN_ID="29557410488"

    run require_scoped_head_for_workflow_run ""
    [ "$status" -ne 0 ]
    [[ $output == *"::error::"* ]]
}

@test "require_scoped_head_for_workflow_run allows schedule when run id unset" {
    unset CI_SWEEPER_WORKFLOW_RUN_ID

    run require_scoped_head_for_workflow_run ""
    [ "$status" -eq 0 ]
}

@test "require_scoped_head_for_workflow_run accepts non-empty scoped head" {
    CI_SWEEPER_WORKFLOW_RUN_ID="29557410488"

    run require_scoped_head_for_workflow_run "main"
    [ "$status" -eq 0 ]
}

@test "resolve_scoped_head_branch empty when workflow_run id set without EVENT_HEAD" {
    unset LOOP_SCOPED_HEAD_BRANCH
    unset CI_SWEEPER_EVENT_HEAD_BRANCH
    CI_SWEEPER_WORKFLOW_RUN_ID="29557410488"

    run resolve_scoped_head_branch
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}
