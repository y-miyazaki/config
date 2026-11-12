#!/bin/bash
#######################################
# Description: Admission helpers shared by loop-detect and loop-entity-detect (budget, circuit breaker, actor and entity gate)
#
# Usage: source "${loop_action_lib}/admission.sh"
#
# Output:
# - None (library file)
#
# Design Rules:
# - Budget reads loop-budget.json and loop-run-log.md for daily aggregation
#######################################

_ADMISSION_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if ! declare -f redact_sensitive_text > /dev/null 2>&1; then
    # shellcheck source=./redact.sh disable=SC1091
    source "${_ADMISSION_LIB_DIR}/redact.sh"
fi

#######################################
# admission_budget_exceeded: Return 0 when daily budget is exceeded
#
# Globals:
#   None
#
# Arguments:
#   $1 - Loop name
#   $2 - Budget file path
#   $3 - Run log file path
#   $4 - Default max runs per day
#   $5 - Default max tokens per day
#
# Outputs:
#   None
#
# Returns:
#   0 when budget exceeded, 1 otherwise
#
#######################################
function admission_budget_exceeded {
    local loop_name="$1"
    local budget_file="$2"
    local run_log_file="$3"
    local default_runs="$4"
    local default_tokens="$5"
    local limits max_runs max_tokens max_cost today runs_today tokens_today cost_today line

    # Split on the single separator space rather than with `read`, which would
    # collapse a leading empty field and shift max_tokens into max_runs when
    # only a token limit is configured.
    limits="$(admission_read_budget_limits "${loop_name}" "${budget_file}" "${default_runs}" "${default_tokens}")"
    max_runs="${limits%% *}"
    max_tokens="${limits#* }"
    max_cost="$(admission_read_budget_cost_limit "${loop_name}" "${budget_file}")"
    if [[ -z ${max_runs} && -z ${max_tokens} && -z ${max_cost} ]]; then
        return 1
    fi

    today=$(date -u +%Y-%m-%d)
    runs_today=0
    tokens_today=0
    cost_today=0
    if [[ -f ${run_log_file} ]]; then
        while IFS= read -r line; do
            [[ -z ${line} ]] && continue
            [[ ${line} != \{* ]] && continue
            local log_date log_key log_outcome entry_tokens entry_cost
            log_date=$(jq -r '.run_id // ""' <<< "${line}" 2> /dev/null | cut -c1-10)
            log_key=$(jq -r '.loop_name // .pattern // ""' <<< "${line}" 2> /dev/null)
            log_outcome=$(jq -r '.outcome // ""' <<< "${line}" 2> /dev/null)
            [[ ${log_date} != "${today}" ]] && continue
            [[ ${log_key} != "${loop_name}" ]] && continue
            # Skipped entries record that detect declined to run (budget,
            # circuit breaker, no_changes). No agent ran and no tokens were
            # spent, so they must not consume the daily budget — otherwise a
            # loop that only ever skips would exhaust its own cap.
            [[ ${log_outcome} == "skipped" ]] && continue
            runs_today=$((runs_today + 1))
            entry_tokens=$(jq -r '
                if .usage then
                    ((.usage.total_input_tokens // .usage.input_tokens // .usage.inputTokens // 0)
                     + (.usage.total_output_tokens // .usage.output_tokens // .usage.outputTokens // 0))
                elif .tokens_total then
                    .tokens_total
                elif .tokens_estimate then
                    .tokens_estimate
                else
                    0
                end
            ' <<< "${line}" 2> /dev/null || echo "0")
            tokens_today=$((tokens_today + entry_tokens))
            entry_cost=$(jq -r '(.cost_usd // .usage.cost_usd // 0)' <<< "${line}" 2> /dev/null || echo "0")
            cost_today="$(awk -v a="${cost_today}" -v b="${entry_cost}" 'BEGIN { printf "%.6f", a + b }')"
        done < <(grep -E '^\{' "${run_log_file}" 2> /dev/null || true)
    fi

    if [[ -n ${max_runs} && ${runs_today} -ge ${max_runs} ]]; then
        echo "::warning::Daily run budget exceeded for ${loop_name} (${runs_today}/${max_runs})"
        return 0
    fi
    # Cost is the primary gate: it is what the spend actually is, and unlike a
    # token count it needs no assumption about how cache reads are priced. Only
    # engines that report their own cost populate it, so the token gate below
    # still covers the rest.
    if [[ -n ${max_cost} ]] && awk -v a="${cost_today}" -v b="${max_cost}" 'BEGIN { exit !(a >= b) }'; then
        echo "::warning::Daily cost budget exceeded for ${loop_name} (\$${cost_today}/\$${max_cost})"
        return 0
    fi
    if [[ -n ${max_tokens} && ${tokens_today} -ge ${max_tokens} ]]; then
        echo "::warning::Daily token budget exceeded for ${loop_name} (${tokens_today}/${max_tokens})"
        return 0
    fi
    return 1
}

#######################################
# admission_read_budget_limits: Echo max_runs and max_tokens for loop name
#
# Globals:
#   None
#
# Arguments:
#   $1 - Loop name
#   $2 - Budget file path
#   $3 - Default max runs
#   $4 - Default max tokens
#
# Outputs:
#   "max_runs max_tokens" on stdout
#
# Returns:
#   0 on success
#
#######################################
function admission_read_budget_limits {
    local loop_name="$1"
    local budget_file="$2"
    local default_runs="$3"
    local default_tokens="$4"
    local max_runs="" max_tokens=""

    if [[ -f ${budget_file} ]]; then
        max_runs=$(jq -r --arg loop "${loop_name}" '.loops[$loop].max_runs_per_day // empty' "${budget_file}" 2> /dev/null || true)
        max_tokens=$(jq -r --arg loop "${loop_name}" '.loops[$loop].max_tokens_per_day // empty' "${budget_file}" 2> /dev/null || true)
    fi
    max_runs="${max_runs:-${default_runs}}"
    max_tokens="${max_tokens:-${default_tokens}}"
    printf '%s %s' "${max_runs}" "${max_tokens}"
}

#######################################
# admission_read_budget_cost_limit: Echo the configured daily cost cap for a loop
#
# Globals:
#   None
#
# Arguments:
#   $1 - Loop name
#   $2 - Budget file path
#
# Outputs:
#   max_cost_usd_per_day on stdout, or an empty string when unset
#
# Returns:
#   0 on success
#
#######################################
function admission_read_budget_cost_limit {
    local loop_name="$1"
    local budget_file="$2"

    [[ -f ${budget_file} ]] || return 0
    jq -r --arg loop "${loop_name}" \
        '.loops[$loop].max_cost_usd_per_day // empty' "${budget_file}" 2> /dev/null || true
}

#######################################
# admission_circuit_breaker_open: Return 0 while the circuit breaker blocks the target
#
# Description:
#   Open when consecutive_failures >= 3, but only while last_run is inside the 30-day
#   cooldown window (same window and field as prune_targets.sh). Once last_run is older,
#   one run is allowed through (half-open): a rejected result reopens the breaker for
#   another 30 days, an approved result resets the counter. A missing or invalid last_run
#   keeps the breaker open (fail-safe, same as prune_targets.sh).
#
# Globals:
#   None
#
# Arguments:
#   $1 - Consecutive failure count
#   $2 - Target last_run timestamp (optional; empty keeps the breaker open)
#
# Outputs:
#   None
#
# Returns:
#   0 when circuit breaker is open, 1 otherwise
#
#######################################
function admission_circuit_breaker_open {
    local consecutive="$1"
    local last_run="${2:-}"
    local cutoff

    [[ ${consecutive} -ge 3 ]] || return 1
    [[ ${last_run} =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2} ]] || return 0
    cutoff="$(date -u -d '30 days ago' +%Y-%m-%d 2> /dev/null || date -u -v-30d +%Y-%m-%d)"
    [[ ${last_run:0:10} < ${cutoff} ]] && return 1
    return 0
}

#######################################
# admission_actor_is_bot: Return 0 when the actor is a bot
#
# Description:
#   The one bot definition. A detect script maps its source (event user.type, gh author.is_bot,
#   REST user.type, login) to the actor type and login and asks here.
#
# Globals:
#   None
#
# Arguments:
#   $1 - Actor type (User | Bot; empty when unknown)
#   $2 - Actor login (optional)
#
# Outputs:
#   None
#
# Returns:
#   0 when the type is Bot or the login is a bot login (suffix bot or [bot], prefix app/); 1 otherwise
#
#######################################
function admission_actor_is_bot {
    local type="${1:-}"
    local login="${2:-}"
    local lowered_type lowered_login

    lowered_type="$(tr '[:upper:]' '[:lower:]' <<< "${type}")"
    lowered_login="$(tr '[:upper:]' '[:lower:]' <<< "${login}")"
    [[ ${lowered_type} == "bot" ]] && return 0
    [[ ${lowered_login} == *"bot" || ${lowered_login} == *"[bot]" || ${lowered_login} == app/* ]] && return 0
    return 1
}

#######################################
# admission_actor_trusted: Return 0 when the author association is trusted
#
# Description:
#   Repository visibility is never a trust signal: the same association list applies to every repository.
#
# Globals:
#   None
#
# Arguments:
#   $1 - author_association (empty when unknown)
#
# Outputs:
#   None
#
# Returns:
#   0 for MEMBER, OWNER or COLLABORATOR; 1 otherwise, including empty
#
#######################################
function admission_actor_trusted {
    case "${1:-}" in
        MEMBER | OWNER | COLLABORATOR) return 0 ;;
        *) return 1 ;;
    esac
}

#######################################
# admission_evaluate: Decide whether a run may proceed from the facts of a detect result
#
# Description:
#   Evaluates result.gate in one fixed order, first failure wins: entity open, bot actor (every
#   source but schedule), author association (required on a webhook, checked on other sources
#   when reported), mention (webhook only), open PR
#   already handling the entity, circuit breaker, detect-script domain skip. A result without a
#   gate is not evaluated (admit), so detect scripts can adopt the gate one at a time. A fact
#   the script does not report is not evaluated; a reported entity.state that is not open,
#   closed or merged skips with fact_missing (fail closed).
#
# Globals:
#   None
#
# Arguments:
#   $1 - gate JSON (the detect result.gate object; empty or null means no gate)
#   $2 - target state JSON ({} when the target has no state; optional)
#
# Outputs:
#   STDOUT: {"admit":bool,"skip_reason":string,"detail":string}; skip_reason is empty when admitted
#
# Returns:
#   0 always
#
#######################################
function admission_evaluate {
    local gate="${1:-}"
    local target_state="${2:-}"
    local state source type login association mention_required mention_present open_pr
    local consecutive last_run domain_skip domain_reason

    [[ -n ${target_state} ]] || target_state='{}'
    if [[ -z ${gate} || ${gate} == "null" ]] || ! jq -e 'type == "object"' <<< "${gate}" > /dev/null 2>&1; then
        admission_result true "" ""
        return 0
    fi

    if jq -e '.entity | type == "object" and has("state")' <<< "${gate}" > /dev/null 2>&1; then
        state="$(jq -r '.entity.state // ""' <<< "${gate}")"
        case "${state}" in
            open) ;;
            closed | merged)
                admission_result false "entity_closed" "entity state is ${state}"
                return 0
                ;;
            *)
                admission_result false "fact_missing" "entity.state is unknown (${state:-empty})"
                return 0
                ;;
        esac
    fi

    source="$(jq -r '.trigger.source // ""' <<< "${gate}")"
    if [[ ${source} != "schedule" ]]; then
        type="$(jq -r '.actor.type // ""' <<< "${gate}")"
        login="$(jq -r '.actor.login // ""' <<< "${gate}")"
        if admission_actor_is_bot "${type}" "${login}"; then
            admission_result false "actor_untrusted" "actor is a bot"
            return 0
        fi
    fi
    association="$(jq -r '.actor.association // ""' <<< "${gate}")"
    if [[ ${source} == "webhook" || (${source} != "schedule" && -n ${association}) ]]; then
        if ! admission_actor_trusted "${association}"; then
            admission_result false "actor_untrusted" "author association is not trusted"
            return 0
        fi
    fi
    if [[ ${source} == "webhook" ]]; then
        mention_required="$(jq -r '.trigger.mention_required // false' <<< "${gate}")"
        mention_present="$(jq -r '.trigger.mention_present // false' <<< "${gate}")"
        if [[ ${mention_required} == "true" && ${mention_present} != "true" ]]; then
            admission_result false "mention_missing" "required mention is absent"
            return 0
        fi
    fi

    open_pr="$(jq -r '.dedupe.open_pr // empty' <<< "${gate}")"
    if [[ -n ${open_pr} ]]; then
        admission_result false "pending_pr" "open PR #${open_pr} already handles the entity"
        return 0
    fi

    consecutive="$(jq -r '.consecutive_failures // 0' <<< "${target_state}")"
    last_run="$(jq -r '.last_run // ""' <<< "${target_state}")"
    if [[ ${consecutive} =~ ^[0-9]+$ ]] && admission_circuit_breaker_open "${consecutive}" "${last_run}"; then
        admission_result false "circuit_breaker" "consecutive_failures ${consecutive}"
        return 0
    fi

    domain_skip="$(jq -r '.domain_skip.skip // false' <<< "${gate}")"
    if [[ ${domain_skip} == "true" ]]; then
        domain_reason="$(jq -r '.domain_skip.reason // ""' <<< "${gate}")"
        if [[ ! ${domain_reason} =~ ^[a-z0-9_]+$ ]]; then
            domain_reason="detect"
        fi
        admission_result false "domain:${domain_reason}" "detect script skipped the entity"
        return 0
    fi

    admission_result true "" ""
}

#######################################
# admission_result: Print one admission result object
#
# Globals:
#   None
#
# Arguments:
#   $1 - admit (true | false)
#   $2 - skip_reason (empty when admitted)
#   $3 - detail (one line)
#
# Outputs:
#   STDOUT: {"admit":bool,"skip_reason":string,"detail":string}
#
# Returns:
#   0 always
#
#######################################
function admission_result {
    jq -nc --argjson admit "${1}" --arg skip_reason "${2}" --arg detail "${3}" \
        '{admit: $admit, skip_reason: $skip_reason, detail: $detail}'
}

#######################################
# admission_skip_detail: Build the one-line, redacted detail recorded with a skip reason
#
# Globals:
#   None
#
# Arguments:
#   $1 - Message text (a detect script message or a gate detail)
#
# Outputs:
#   STDOUT: the message on one line, redacted and cut to 300 characters
#
# Returns:
#   0 always
#
#######################################
function admission_skip_detail {
    local message="${1:-}"

    message="$(printf '%s' "${message}" | tr '\r\n' '  ')"
    message="$(redact_sensitive_text "${message}")"
    printf '%s' "${message:0:300}"
}
