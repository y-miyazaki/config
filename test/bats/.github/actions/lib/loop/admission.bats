#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154

# Tests for .github/actions/lib/loop/admission.sh

# Use cases:
# - admission_circuit_breaker_open trips at three consecutive failures
# - admission_circuit_breaker_open closes after 30 days and stays open without a valid last_run
# - admission_read_budget_limits prefers budget file over defaults
# - admission_budget_exceeded trips when daily run count reaches max
# - admission_budget_exceeded allows runs under the daily cap
# - admission_budget_exceeded trips when daily token count reaches max
# - admission_budget_exceeded counts legacy pattern and tokens_estimate log entries
# - admission_budget_exceeded applies a token-only limit when no run limit is configured
# - admission_budget_exceeded excludes skipped entries from run and token aggregation
# - admission_budget_exceeded still counts entries that carry target_key
# - admission_actor_is_bot is the one bot definition (type Bot, login suffix bot or [bot], app/ prefix)
# - admission_actor_trusted accepts MEMBER, OWNER and COLLABORATOR on every repository and refuses the rest
# - admission_evaluate admits a result without a gate, fails closed on an unknown entity state and skips the check when no state is reported
# - admission_evaluate refuses a closed or merged entity, an untrusted or bot actor, a missing mention, an open PR, an open circuit breaker and a domain skip, in that order
# - admission_evaluate applies the bot check to every source but schedule, the association check to webhooks (required) and to other sources (when reported), and the mention check to webhooks only

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

setup() {
    bats_source_rel ".github/actions/lib/loop/admission.sh"
    GUARDS_TMP="$(mktemp -d)"
    export GUARDS_TMP
}

teardown() {
    rm -rf "${GUARDS_TMP}"
}

@test "admission_circuit_breaker_open trips at three consecutive failures" {
    run admission_circuit_breaker_open 2
    [ "$status" -ne 0 ]

    run admission_circuit_breaker_open 3
    [ "$status" -eq 0 ]

    run admission_circuit_breaker_open 5
    [ "$status" -eq 0 ]
}

@test "admission_circuit_breaker_open closes after 30 days and stays open without a valid last_run" {
    local today old recent
    today="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    recent="$(date -u -d '29 days ago' +%Y-%m-%dT%H:%M:%SZ 2> /dev/null || date -u -v-29d +%Y-%m-%dT%H:%M:%SZ)"
    old="$(date -u -d '31 days ago' +%Y-%m-%dT%H:%M:%SZ 2> /dev/null || date -u -v-31d +%Y-%m-%dT%H:%M:%SZ)"

    run admission_circuit_breaker_open 3 "${today}"
    [ "$status" -eq 0 ]
    run admission_circuit_breaker_open 3 "${recent}"
    [ "$status" -eq 0 ]
    run admission_circuit_breaker_open 3 "${old}"
    [ "$status" -eq 1 ]
    run admission_circuit_breaker_open 2 "${today}"
    [ "$status" -eq 1 ]
    run admission_circuit_breaker_open 3 ""
    [ "$status" -eq 0 ]
    run admission_circuit_breaker_open 3 "garbage"
    [ "$status" -eq 0 ]
    run admission_circuit_breaker_open 3
    [ "$status" -eq 0 ]
}

@test "admission_read_budget_limits prefers budget file over defaults" {
    local budget_file

    budget_file="${GUARDS_TMP}/loop-budget.json"
    jq -nc '{loops:{"ci-sweeper":{max_runs_per_day:2,max_tokens_per_day:100}}}' > "${budget_file}"

    run admission_read_budget_limits "ci-sweeper" "${budget_file}" "5" "1000000"
    [ "$status" -eq 0 ]
    [ "$output" = "2 100" ]
}

@test "admission_budget_exceeded trips when daily run count reaches max" {
    local budget_file run_log today

    budget_file="${GUARDS_TMP}/loop-budget.json"
    run_log="${GUARDS_TMP}/loop-run-log.md"
    today="$(date -u +%Y-%m-%d)"
    jq -nc '{loops:{"ci-sweeper":{max_runs_per_day:1,max_tokens_per_day:1000000}}}' > "${budget_file}"
    printf '%s\n' "{\"run_id\":\"${today}T00:00:00Z\",\"loop_name\":\"ci-sweeper\",\"tokens_total\":10}" \
        > "${run_log}"

    run admission_budget_exceeded "ci-sweeper" "${budget_file}" "${run_log}" "5" "1000000"
    [ "$status" -eq 0 ]
    [[ $output == *"Daily run budget exceeded"* ]]
}

@test "admission_budget_exceeded allows runs under the daily cap" {
    local budget_file run_log

    budget_file="${GUARDS_TMP}/loop-budget.json"
    run_log="${GUARDS_TMP}/loop-run-log.md"
    jq -nc '{loops:{"ci-sweeper":{max_runs_per_day:5,max_tokens_per_day:1000000}}}' > "${budget_file}"
    : > "${run_log}"

    run admission_budget_exceeded "ci-sweeper" "${budget_file}" "${run_log}" "5" "1000000"
    [ "$status" -ne 0 ]
}

@test "admission_budget_exceeded trips when daily token count reaches max" {
    local budget_file run_log today

    budget_file="${GUARDS_TMP}/loop-budget.json"
    run_log="${GUARDS_TMP}/loop-run-log.md"
    today="$(date -u +%Y-%m-%d)"
    jq -nc '{loops:{"ci-sweeper":{max_runs_per_day:100,max_tokens_per_day:100}}}' > "${budget_file}"
    printf '%s\n' "{\"run_id\":\"${today}T00:00:00Z\",\"loop_name\":\"ci-sweeper\",\"tokens_total\":100}" \
        > "${run_log}"

    run admission_budget_exceeded "ci-sweeper" "${budget_file}" "${run_log}" "5" "1000000"
    [ "$status" -eq 0 ]
    [[ $output == *"Daily token budget exceeded"* ]]
}

@test "admission_budget_exceeded counts legacy pattern and tokens_estimate log entries" {
    local budget_file run_log today

    budget_file="${GUARDS_TMP}/loop-budget.json"
    run_log="${GUARDS_TMP}/loop-run-log.md"
    today="$(date -u +%Y-%m-%d)"
    jq -nc '{loops:{"ci-sweeper":{max_runs_per_day:100,max_tokens_per_day:100}}}' > "${budget_file}"
    printf '%s\n' "{\"run_id\":\"${today}T00:00:00Z\",\"pattern\":\"ci-sweeper\",\"tokens_estimate\":100}" \
        > "${run_log}"

    run admission_budget_exceeded "ci-sweeper" "${budget_file}" "${run_log}" "5" "1000000"
    [ "$status" -eq 0 ]
    [[ $output == *"Daily token budget exceeded"* ]]
}

@test "admission_budget_exceeded applies a token-only limit when no run limit is configured" {
    local budget_file run_log today

    budget_file="${GUARDS_TMP}/missing-budget.json"
    run_log="${GUARDS_TMP}/loop-run-log.md"
    today="$(date -u +%Y-%m-%d)"
    printf '%s\n' "{\"run_id\":\"${today}T00:00:00Z\",\"loop_name\":\"ci-sweeper\",\"tokens_total\":100}" \
        > "${run_log}"

    # Empty default_runs must not shift default_tokens into the run limit.
    run admission_budget_exceeded "ci-sweeper" "${budget_file}" "${run_log}" "" "100"
    [ "$status" -eq 0 ]
    [[ $output == *"Daily token budget exceeded"* ]]
}

@test "admission_budget_exceeded excludes skipped entries from run aggregation" {
    local budget_file run_log today

    budget_file="${GUARDS_TMP}/missing-budget.json"
    run_log="${GUARDS_TMP}/loop-run-log.md"
    today="$(date -u +%Y-%m-%d)"
    {
        printf '%s\n' "{\"run_id\":\"${today}T00:00:00Z\",\"loop_name\":\"ci-sweeper\",\"outcome\":\"skipped\"}"
        printf '%s\n' "{\"run_id\":\"${today}T00:00:00Z\",\"loop_name\":\"ci-sweeper\",\"outcome\":\"skipped\"}"
        printf '%s\n' "{\"run_id\":\"${today}T00:00:00Z\",\"loop_name\":\"ci-sweeper\",\"outcome\":\"pr-created\"}"
    } > "${run_log}"

    run admission_budget_exceeded "ci-sweeper" "${budget_file}" "${run_log}" "2" "1000000"
    [ "$status" -ne 0 ]
}

@test "admission_budget_exceeded excludes skipped entries from token aggregation" {
    local budget_file run_log today

    budget_file="${GUARDS_TMP}/missing-budget.json"
    run_log="${GUARDS_TMP}/loop-run-log.md"
    today="$(date -u +%Y-%m-%d)"
    printf '%s\n' "{\"run_id\":\"${today}T00:00:00Z\",\"loop_name\":\"ci-sweeper\",\"outcome\":\"skipped\",\"tokens_total\":100}" \
        > "${run_log}"

    run admission_budget_exceeded "ci-sweeper" "${budget_file}" "${run_log}" "100" "100"
    [ "$status" -ne 0 ]
}

@test "admission_budget_exceeded trips when daily cost reaches max" {
    local budget_file run_log today

    budget_file="${GUARDS_TMP}/loop-budget.json"
    run_log="${GUARDS_TMP}/loop-run-log.md"
    today="$(date -u +%Y-%m-%d)"
    jq -nc '{loops:{"docs-updater":{max_runs_per_day:100,max_tokens_per_day:999999999,max_cost_usd_per_day:5}}}' > "${budget_file}"
    printf '%s\n' \
        "{\"run_id\":\"${today}T00:00:00Z\",\"loop_name\":\"docs-updater\",\"tokens_total\":10,\"cost_usd\":3.2}" \
        "{\"run_id\":\"${today}T01:00:00Z\",\"loop_name\":\"docs-updater\",\"tokens_total\":10,\"cost_usd\":2.1}" \
        > "${run_log}"

    run admission_budget_exceeded "docs-updater" "${budget_file}" "${run_log}" "100" "999999999"
    [ "$status" -eq 0 ]
    [[ $output == *"Daily cost budget exceeded"* ]]
}

@test "admission_budget_exceeded allows runs under the daily cost cap" {
    local budget_file run_log today

    budget_file="${GUARDS_TMP}/loop-budget.json"
    run_log="${GUARDS_TMP}/loop-run-log.md"
    today="$(date -u +%Y-%m-%d)"
    jq -nc '{loops:{"docs-updater":{max_runs_per_day:100,max_tokens_per_day:999999999,max_cost_usd_per_day:5}}}' > "${budget_file}"
    printf '%s\n' \
        "{\"run_id\":\"${today}T00:00:00Z\",\"loop_name\":\"docs-updater\",\"tokens_total\":10,\"cost_usd\":1.5}" \
        > "${run_log}"

    run admission_budget_exceeded "docs-updater" "${budget_file}" "${run_log}" "100" "999999999"
    [ "$status" -ne 0 ]
}

@test "admission_budget_exceeded falls back to tokens when the engine reports no cost" {
    local budget_file run_log today

    budget_file="${GUARDS_TMP}/loop-budget.json"
    run_log="${GUARDS_TMP}/loop-run-log.md"
    today="$(date -u +%Y-%m-%d)"
    jq -nc '{loops:{"docs-updater":{max_runs_per_day:100,max_tokens_per_day:100,max_cost_usd_per_day:5}}}' > "${budget_file}"
    printf '%s\n' \
        "{\"run_id\":\"${today}T00:00:00Z\",\"loop_name\":\"docs-updater\",\"tokens_total\":150}" \
        > "${run_log}"

    run admission_budget_exceeded "docs-updater" "${budget_file}" "${run_log}" "100" "100"
    [ "$status" -eq 0 ]
    [[ $output == *"Daily token budget exceeded"* ]]
}

@test "admission_budget_exceeded reads cost from the nested usage object" {
    local budget_file run_log today

    budget_file="${GUARDS_TMP}/loop-budget.json"
    run_log="${GUARDS_TMP}/loop-run-log.md"
    today="$(date -u +%Y-%m-%d)"
    jq -nc '{loops:{"docs-updater":{max_runs_per_day:100,max_tokens_per_day:999999999,max_cost_usd_per_day:2}}}' > "${budget_file}"
    printf '%s\n' \
        "{\"run_id\":\"${today}T00:00:00Z\",\"loop_name\":\"docs-updater\",\"usage\":{\"cost_usd\":2.5}}" \
        > "${run_log}"

    run admission_budget_exceeded "docs-updater" "${budget_file}" "${run_log}" "100" "999999999"
    [ "$status" -eq 0 ]
    [[ $output == *"Daily cost budget exceeded"* ]]
}

@test "admission_budget_exceeded still counts entries that carry target_key" {
    local budget_file run_log today

    budget_file="${GUARDS_TMP}/loop-budget.json"
    run_log="${GUARDS_TMP}/loop-run-log.md"
    today="$(date -u +%Y-%m-%d)"
    jq -nc '{loops:{"ci-sweeper":{max_runs_per_day:1,max_tokens_per_day:1000000}}}' > "${budget_file}"
    printf '%s\n' "{\"run_id\":\"${today}T00:00:00Z\",\"loop_name\":\"ci-sweeper\",\"tokens_total\":10,\"target_key\":\"entity:issue:7\"}" \
        > "${run_log}"

    run admission_budget_exceeded "ci-sweeper" "${budget_file}" "${run_log}" "5" "1000000"
    [ "$status" -eq 0 ]
    [[ $output == *"Daily run budget exceeded"* ]]
}

gate_json() {
    jq -nc --arg state "${1:-open}" --arg source "${2:-webhook}" --arg type "${3:-User}" --arg login "${4:-alice}" \
        --arg association "${5:-MEMBER}" --argjson mention_required "${6:-false}" --argjson mention_present "${7:-false}" \
        '{entity: {kind: "pr", number: 1, state: $state},
          actor: {login: $login, type: $type, association: $association},
          trigger: {source: $source, mention_required: $mention_required, mention_present: $mention_present},
          dedupe: {open_pr: null},
          domain_skip: {skip: false}}'
}

@test "admission_actor_is_bot is the one bot definition" {
    run admission_actor_is_bot "Bot" "x"
    [ "$status" -eq 0 ]
    run admission_actor_is_bot "User" "renovate[bot]"
    [ "$status" -eq 0 ]
    run admission_actor_is_bot "" "repo-maintenance-bot"
    [ "$status" -eq 0 ]
    run admission_actor_is_bot "" "app/renovate"
    [ "$status" -eq 0 ]
    run admission_actor_is_bot "User" "alice"
    [ "$status" -eq 1 ]
    run admission_actor_is_bot "" ""
    [ "$status" -eq 1 ]
}

@test "admission_actor_trusted accepts MEMBER OWNER COLLABORATOR only" {
    local value
    for value in MEMBER OWNER COLLABORATOR; do
        run admission_actor_trusted "${value}"
        [ "$status" -eq 0 ]
    done
    for value in CONTRIBUTOR NONE FIRST_TIME_CONTRIBUTOR ""; do
        run admission_actor_trusted "${value}"
        [ "$status" -eq 1 ]
    done
}

@test "admission_evaluate admits a result without a gate" {
    run admission_evaluate "" '{}'
    [ "$status" -eq 0 ]
    [ "$(jq -r '.admit' <<< "${output}")" = "true" ]
    run admission_evaluate "null" '{}'
    [ "$(jq -r '.admit' <<< "${output}")" = "true" ]
}

@test "admission_evaluate fails closed on an unknown entity state and skips the check when none is reported" {
    run admission_evaluate "$(gate_json weird)" '{}'
    [ "$(jq -r '.skip_reason' <<< "${output}")" = "fact_missing" ]
    run admission_evaluate '{"entity":{"kind":"pr","number":1,"state":""}}' '{}'
    [ "$(jq -r '.skip_reason' <<< "${output}")" = "fact_missing" ]
    run admission_evaluate '{"entity":{"kind":"pr","number":1}}' '{}'
    [ "$(jq -r '.admit' <<< "${output}")" = "true" ]
}

@test "admission_evaluate refuses closed and merged entities" {
    run admission_evaluate "$(gate_json closed)" '{}'
    [ "$(jq -r '.admit' <<< "${output}")" = "false" ]
    [ "$(jq -r '.skip_reason' <<< "${output}")" = "entity_closed" ]
    run admission_evaluate "$(gate_json merged)" '{}'
    [ "$(jq -r '.skip_reason' <<< "${output}")" = "entity_closed" ]
}

@test "admission_evaluate refuses bot actors on webhook and dispatch, an untrusted association on webhook and dispatch, nothing on schedule" {
    run admission_evaluate "$(gate_json open webhook Bot bot-x MEMBER)" '{}'
    [ "$(jq -r '.skip_reason' <<< "${output}")" = "actor_untrusted" ]
    run admission_evaluate "$(gate_json open webhook User alice NONE)" '{}'
    [ "$(jq -r '.skip_reason' <<< "${output}")" = "actor_untrusted" ]
    run admission_evaluate "$(gate_json open dispatch Bot bot-x NONE)" '{}'
    [ "$(jq -r '.skip_reason' <<< "${output}")" = "actor_untrusted" ]
    run admission_evaluate "$(gate_json open dispatch User alice CONTRIBUTOR)" '{}'
    [ "$(jq -r '.skip_reason' <<< "${output}")" = "actor_untrusted" ]
    run admission_evaluate "$(gate_json open dispatch User alice MEMBER)" '{}'
    [ "$(jq -r '.admit' <<< "${output}")" = "true" ]
    run admission_evaluate "$(gate_json open dispatch User alice "")" '{}'
    [ "$(jq -r '.admit' <<< "${output}")" = "true" ]
    run admission_evaluate "$(gate_json open schedule Bot bot-x NONE)" '{}'
    [ "$(jq -r '.admit' <<< "${output}")" = "true" ]
}

@test "admission_evaluate refuses a webhook without the required mention" {
    run admission_evaluate "$(gate_json open webhook User alice MEMBER true false)" '{}'
    [ "$(jq -r '.skip_reason' <<< "${output}")" = "mention_missing" ]
    run admission_evaluate "$(gate_json open webhook User alice MEMBER true true)" '{}'
    [ "$(jq -r '.admit' <<< "${output}")" = "true" ]
    run admission_evaluate "$(gate_json open dispatch User alice MEMBER true false)" '{}'
    [ "$(jq -r '.admit' <<< "${output}")" = "true" ]
}

@test "admission_evaluate refuses an entity an open PR already handles" {
    local gate
    gate="$(gate_json | jq -c '.dedupe.open_pr = 7')"
    run admission_evaluate "${gate}" '{}'
    [ "$(jq -r '.skip_reason' <<< "${output}")" = "pending_pr" ]
}

@test "admission_evaluate refuses while the circuit breaker is open" {
    local today
    today="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    run admission_evaluate "$(gate_json)" "{\"consecutive_failures\":3,\"last_run\":\"${today}\"}"
    [ "$(jq -r '.skip_reason' <<< "${output}")" = "circuit_breaker" ]
    run admission_evaluate "$(gate_json)" "{\"consecutive_failures\":2,\"last_run\":\"${today}\"}"
    [ "$(jq -r '.admit' <<< "${output}")" = "true" ]
}

@test "admission_evaluate reports a domain skip with a slug and checks in the fixed order" {
    local gate
    gate="$(gate_json | jq -c '.domain_skip = {skip: true, reason: "already_reviewed"}')"
    run admission_evaluate "${gate}" '{}'
    [ "$(jq -r '.skip_reason' <<< "${output}")" = "domain:already_reviewed" ]
    gate="$(gate_json closed | jq -c '.domain_skip = {skip: true, reason: "x"}')"
    run admission_evaluate "${gate}" '{}'
    [ "$(jq -r '.skip_reason' <<< "${output}")" = "entity_closed" ]
    gate="$(gate_json | jq -c '.domain_skip = {skip: true, reason: "Bad Reason"}')"
    run admission_evaluate "${gate}" '{}'
    [ "$(jq -r '.skip_reason' <<< "${output}")" = "domain:detect" ]
}
