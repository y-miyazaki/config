#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154

# Tests for .github/actions/loop-run-log/lib/append.sh

# Use cases:
# - loop_run_log_build_entry includes tokens_total zero by default
# - loop_run_log_build_entry sets tokens_total from measured usage_json
# - loop_run_log_append_entry writes JSONL entry with expected format
# - loop_run_log_compute_duration returns zero for empty start
# - loop_run_log_compute_duration returns elapsed seconds
# - loop_run_log_prune_cutoff_date returns YYYY-MM-DD
# - loop_run_log_append_entry prunes entries older than 30 days
# - budget token selection prefers measured usage over tokens_total
# - loop_run_log_build_entry carries the per-model usage breakdown through unchanged
# - loop_run_log_commit_and_push skips committing when the run log is unchanged
# - loop_run_log_commit_and_push pushes the entry to the base branch
# - loop_run_log_commit_and_push keeps both entries when a concurrent run wins the push race

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

setup() {
    bats_source_rel ".github/actions/loop-run-log/lib/append.sh"
    TEST_DIR="$(mktemp -d)"
}

teardown() {
    rm -rf "${TEST_DIR}"
}

# Build a run log entry dated now, so the 30-day prune always keeps it.
_run_log_entry() {
    printf '{"run_id":"%s","loop_name":"%s","duration_s":1,"outcome":"skipped","skip_reason":"none","tokens_total":0,"workflow_run":"%s"}' \
        "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1" "$2"
}

# Create a bare origin plus a working clone, both holding an empty run log on main.
# Echoes the clone path; the origin is always "${TEST_DIR}/origin.git".
_make_git_sandbox() {
    local origin="${TEST_DIR}/origin.git"
    local work="${TEST_DIR}/work"

    git init --bare -q -b main "${origin}"
    git clone -q "${origin}" "${work}" 2> /dev/null
    git -C "${work}" config user.email "test@example.com"
    git -C "${work}" config user.name "test"
    mkdir -p "${work}/.loop"
    printf '%s' "${RUN_LOG_HEADER}" > "${work}/.loop/loop-run-log.md"
    git -C "${work}" add .loop/loop-run-log.md
    git -C "${work}" commit -q -m "init"
    git -C "${work}" push -q origin HEAD:main
    printf '%s' "${work}"
}

# Append one entry to the run log from a second clone and push it, so the clone
# under test is left behind the base branch.
_push_concurrent_entry() {
    local entry="$1"
    local other="${TEST_DIR}/other"

    git clone -q "${TEST_DIR}/origin.git" "${other}"
    git -C "${other}" config user.email "other@example.com"
    git -C "${other}" config user.name "other"
    (
        cd "${other}" && loop_run_log_append_entry ".loop/loop-run-log.md" "${entry}"
    )
    git -C "${other}" add .loop/loop-run-log.md
    git -C "${other}" commit -q -m "concurrent append"
    git -C "${other}" push -q origin HEAD:main
}

@test "loop_run_log_build_entry includes tokens_total zero by default" {
    result="$(loop_run_log_build_entry "" 12 "" "docs-updater" "skipped" "budget" "" "12345" "")"
    [ "$(jq -r '.loop_name' <<< "${result}")" = "docs-updater" ]
    [ "$(jq -r '.tokens_total' <<< "${result}")" = "0" ]
    [ "$(jq -r '.usage // empty' <<< "${result}")" = "" ]
}

@test "loop_run_log_build_entry sets tokens_total from usage_json" {
    local usage='{"total_input_tokens":1842,"total_output_tokens":17,"model":"composer-2.5"}'
    result="$(loop_run_log_build_entry "2" 45 "true" "docs-updater" "pr-created" "none" "APPROVE" "999" "${usage}")"
    [ "$(jq -r '.tokens_total' <<< "${result}")" = "1859" ]
    [ "$(jq -r '.usage.total_input_tokens' <<< "${result}")" = "1842" ]
    [ "$(jq -r '.usage.total_output_tokens' <<< "${result}")" = "17" ]
    [ "$(jq -r '.usage.model' <<< "${result}")" = "composer-2.5" ]
    [ "$(jq -r '.attempts' <<< "${result}")" = "2" ]
    [ "$(jq -r '.has_changes' <<< "${result}")" = "true" ]
    [ "$(jq -r '.verdict' <<< "${result}")" = "APPROVE" ]
}

@test "loop_run_log_build_entry includes failure diagnostics when provided" {
    result="$(loop_run_log_build_entry "" 12 "" "ci-sweeper" "error" "none" "APPROVE" "12345" "" "failure" "push" "remote rejected")"
    [ "$(jq -r '.agent_result' <<< "${result}")" = "failure" ]
    [ "$(jq -r '.failure_stage' <<< "${result}")" = "push" ]
    [ "$(jq -r '.failure_message' <<< "${result}")" = "remote rejected" ]
}

@test "loop_run_log_append_entry writes JSONL entry with expected format" {
    local log_file="${TEST_DIR}/loop-run-log.md"
    local entry

    entry="$(loop_run_log_build_entry "" 3 "" "docs-updater" "skipped" "budget" "" "42" "")"
    assert_loop_run_log_entry_json "${entry}"
    loop_run_log_append_entry "${log_file}" "${entry}"

    run tail -n 1 "${log_file}"
    [ "$status" -eq 0 ]
    assert_loop_run_log_entry_json "${output}"
    [ "$(jq -r '.workflow_run' <<< "${output}")" = "42" ]
}

@test "loop_run_log_compute_duration returns zero for empty start" {
    result="$(loop_run_log_compute_duration "")"
    [ "${result}" = "0" ]
}

@test "loop_run_log_compute_duration returns elapsed seconds" {
    local started
    started="$(date -u -d '10 seconds ago' +%Y-%m-%dT%H:%M:%SZ)"
    result="$(loop_run_log_compute_duration "${started}")"
    [ "${result}" -ge 8 ]
    [ "${result}" -le 15 ]
}

@test "loop_run_log_prune_cutoff_date returns YYYY-MM-DD" {
    result="$(loop_run_log_prune_cutoff_date)"
    [[ ${result} =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]
}

@test "loop_run_log_append_entry prunes entries older than 30 days" {
    local log_file="${TEST_DIR}/loop-run-log.md"
    local cutoff old_date recent_date new_entry

    cutoff="$(loop_run_log_prune_cutoff_date)"
    old_date="$(date -u -d "${cutoff} - 1 day" +%Y-%m-%dT%H:%M:%SZ)"
    recent_date="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    new_entry='{"run_id":"'"${recent_date}"'","loop_name":"docs-updater","duration_s":1,"outcome":"skipped","skip_reason":"budget","tokens_total":0,"workflow_run":"1"}'

    mkdir -p "$(dirname "${log_file}")"
    {
        printf '%s' "${RUN_LOG_HEADER}"
        printf '{"run_id":"%s","loop_name":"docs-updater","duration_s":1,"outcome":"skipped","skip_reason":"budget","tokens_total":0,"workflow_run":"0"}\n' "${old_date}"
        printf '{"run_id":"%s","loop_name":"docs-updater","duration_s":1,"outcome":"skipped","skip_reason":"none","tokens_total":0,"workflow_run":"2"}\n' "${recent_date}"
    } > "${log_file}"

    loop_run_log_append_entry "${log_file}" "${new_entry}"

    run grep -F "${old_date}" "${log_file}"
    [ "$status" -eq 1 ]
    run grep -F "${recent_date}" "${log_file}"
    [ "$status" -eq 0 ]
    run grep -F "${RUN_LOG_HEADER%%$'\n'*}" "${log_file}"
    [ "$status" -eq 0 ]
}

@test "budget token selection prefers measured usage over tokens_total" {
    local line measured_only tokens_only
    line='{"tokens_total":0,"usage":{"total_input_tokens":100,"total_output_tokens":50}}'
    measured_only="$(jq -r '
      if .usage then
        ((.usage.total_input_tokens // .usage.input_tokens // .usage.inputTokens // 0)
         + (.usage.total_output_tokens // .usage.output_tokens // .usage.outputTokens // 0))
      elif .tokens_total then
        .tokens_total
      else
        0
      end
    ' <<< "${line}")"
    [ "${measured_only}" = "150" ]

    line='{"tokens_total":42}'
    tokens_only="$(jq -r '
      if .usage then
        ((.usage.total_input_tokens // .usage.input_tokens // .usage.inputTokens // 0)
         + (.usage.total_output_tokens // .usage.output_tokens // .usage.outputTokens // 0))
      elif .tokens_total then
        .tokens_total
      else
        0
      end
    ' <<< "${line}")"
    [ "${tokens_only}" = "42" ]

    line='{}'
    tokens_only="$(jq -r '
      if .usage then
        ((.usage.total_input_tokens // .usage.input_tokens // .usage.inputTokens // 0)
         + (.usage.total_output_tokens // .usage.output_tokens // .usage.outputTokens // 0))
      elif .tokens_total then
        .tokens_total
      else
        0
      end
    ' <<< "${line}")"
    [ "${tokens_only}" = "0" ]
}

@test "loop_run_log_resolve_cost_usd echoes engine cost" {
    run loop_run_log_resolve_cost_usd '{"total_input_tokens":10,"cost_usd":0.865485}'
    [ "$status" -eq 0 ]
    [ "$output" = "0.865485" ]
}

@test "loop_run_log_resolve_cost_usd is empty when the engine reports none" {
    run loop_run_log_resolve_cost_usd '{"total_input_tokens":10}'
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
}

@test "loop_run_log_resolve_tokens_total excludes cache tokens" {
    run loop_run_log_resolve_tokens_total '{"total_input_tokens":4815,"total_output_tokens":14276,"cache_read_tokens":2107374,"cache_write_tokens":72780}'
    [ "$status" -eq 0 ]
    [ "$output" = "19091" ]
}

@test "loop_run_log_commit_and_push keeps both entries when a concurrent run wins the push race" {
    local work ours theirs result remote_log

    work="$(_make_git_sandbox)"
    ours="$(_run_log_entry "ours" "1")"
    theirs="$(_run_log_entry "theirs" "2")"

    (cd "${work}" && loop_run_log_append_entry ".loop/loop-run-log.md" "${ours}")
    _push_concurrent_entry "${theirs}"

    result="$(cd "${work}" && loop_run_log_commit_and_push "main" ".loop/loop-run-log.md" "token" "${ours}")"
    [[ ${result} == *"push attempt 1 failed"* ]]
    [[ ${result} == *"pushed to main on attempt 2"* ]]

    remote_log="$(git -C "${TEST_DIR}/origin.git" show "main:.loop/loop-run-log.md")"
    [ "$(grep -c '"loop_name":"theirs"' <<< "${remote_log}")" -eq 1 ]
    [ "$(grep -c '"loop_name":"ours"' <<< "${remote_log}")" -eq 1 ]
}

@test "loop_run_log_commit_and_push pushes the entry to the base branch" {
    local work ours result remote_log

    work="$(_make_git_sandbox)"
    ours="$(_run_log_entry "ours" "1")"

    (cd "${work}" && loop_run_log_append_entry ".loop/loop-run-log.md" "${ours}")

    result="$(cd "${work}" && loop_run_log_commit_and_push "main" ".loop/loop-run-log.md" "token" "${ours}")"
    [[ ${result} == *"pushed to main on attempt 1"* ]]

    remote_log="$(git -C "${TEST_DIR}/origin.git" show "main:.loop/loop-run-log.md")"
    [ "$(grep -c '"loop_name":"ours"' <<< "${remote_log}")" -eq 1 ]
}

@test "loop_run_log_commit_and_push skips committing when the run log is unchanged" {
    local work result

    work="$(_make_git_sandbox)"

    result="$(cd "${work}" && loop_run_log_commit_and_push "main" ".loop/loop-run-log.md" "token" "$(_run_log_entry "ours" "1")")"
    [[ ${result} == *"No run log changes to commit."* ]]
    [ "$(git -C "${work}" rev-list --count HEAD)" -eq 1 ]
}

@test "loop_run_log_build_entry carries the per-model usage breakdown through unchanged" {
    local usage result
    # Shape emitted by build_usage_json for a mixed maker/checker run: no single
    # top-level model, totals still flat so the budget guard needs no change.
    usage='{"total_input_tokens":48,"total_output_tokens":17052,"cost_usd":1.182053,
            "models":["claude-opus-5","claude-sonnet-5"],
            "by_model":{"claude-sonnet-5":{"tokens":10668,"cost_usd":0.435638},
                        "claude-opus-5":{"tokens":6432,"cost_usd":0.746415}},
            "sessions":[{"role":"maker","attempt":1,"model":"claude-sonnet-5","input":26,"output":10642},
                        {"role":"checker","attempt":1,"model":"claude-opus-5","input":22,"output":6410}]}'
    result="$(loop_run_log_build_entry "1" 816 "true" "tech-debt" "pr-created" "none" "APPROVE" "37927886699" "${usage}")"

    [ "$(jq -r '.tokens_total' <<< "${result}")" = "17100" ]
    [ "$(jq -r '.cost_usd' <<< "${result}")" = "1.182053" ]
    [ "$(jq -r '.usage.by_model["claude-opus-5"].cost_usd' <<< "${result}")" = "0.746415" ]
    [ "$(jq -r '.usage.sessions | length' <<< "${result}")" = "2" ]
    [ "$(jq -r '.usage.sessions[1].role' <<< "${result}")" = "checker" ]
}
