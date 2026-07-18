#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154

# Tests for .github/actions/loop-detect/lib/guards.sh

# Use cases:
# - target_circuit_breaker_open trips at three consecutive failures
# - read_budget_limits prefers budget file over defaults
# - budget_exceeded trips when daily run count reaches max
# - budget_exceeded allows runs under the daily cap
# - budget_exceeded trips when daily token count reaches max

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

setup() {
    bats_source_rel ".github/actions/loop-detect/lib/_init.sh"
    GUARDS_TMP="$(mktemp -d)"
    export GUARDS_TMP
}

teardown() {
    rm -rf "${GUARDS_TMP}"
}

@test "target_circuit_breaker_open trips at three consecutive failures" {
    run target_circuit_breaker_open 2
    [ "$status" -ne 0 ]

    run target_circuit_breaker_open 3
    [ "$status" -eq 0 ]

    run target_circuit_breaker_open 5
    [ "$status" -eq 0 ]
}

@test "read_budget_limits prefers budget file over defaults" {
    local budget_file

    budget_file="${GUARDS_TMP}/loop-budget.json"
    jq -nc '{loops:{"ci-sweeper":{max_runs_per_day:2,max_tokens_per_day:100}}}' > "${budget_file}"

    run read_budget_limits "ci-sweeper" "${budget_file}" "5" "1000000"
    [ "$status" -eq 0 ]
    [ "$output" = "2 100" ]
}

@test "budget_exceeded trips when daily run count reaches max" {
    local budget_file run_log today

    budget_file="${GUARDS_TMP}/loop-budget.json"
    run_log="${GUARDS_TMP}/loop-run-log.md"
    today="$(date -u +%Y-%m-%d)"
    jq -nc '{loops:{"ci-sweeper":{max_runs_per_day:1,max_tokens_per_day:1000000}}}' > "${budget_file}"
    printf '%s\n' "{\"run_id\":\"${today}T00:00:00Z\",\"pattern\":\"ci-sweeper\",\"tokens_estimate\":10}" \
        > "${run_log}"

    run budget_exceeded "ci-sweeper" "${budget_file}" "${run_log}" "5" "1000000"
    [ "$status" -eq 0 ]
    [[ $output == *"Daily run budget exceeded"* ]]
}

@test "budget_exceeded allows runs under the daily cap" {
    local budget_file run_log

    budget_file="${GUARDS_TMP}/loop-budget.json"
    run_log="${GUARDS_TMP}/loop-run-log.md"
    jq -nc '{loops:{"ci-sweeper":{max_runs_per_day:5,max_tokens_per_day:1000000}}}' > "${budget_file}"
    : > "${run_log}"

    run budget_exceeded "ci-sweeper" "${budget_file}" "${run_log}" "5" "1000000"
    [ "$status" -ne 0 ]
}

@test "budget_exceeded trips when daily token count reaches max" {
    local budget_file run_log today

    budget_file="${GUARDS_TMP}/loop-budget.json"
    run_log="${GUARDS_TMP}/loop-run-log.md"
    today="$(date -u +%Y-%m-%d)"
    jq -nc '{loops:{"ci-sweeper":{max_runs_per_day:100,max_tokens_per_day:100}}}' > "${budget_file}"
    printf '%s\n' "{\"run_id\":\"${today}T00:00:00Z\",\"pattern\":\"ci-sweeper\",\"tokens_estimate\":100}" \
        > "${run_log}"

    run budget_exceeded "ci-sweeper" "${budget_file}" "${run_log}" "5" "1000000"
    [ "$status" -eq 0 ]
    [[ $output == *"Daily token budget exceeded"* ]]
}
