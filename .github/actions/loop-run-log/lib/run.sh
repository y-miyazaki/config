#!/usr/bin/env bash
# Append loop run log entry and commit. Env mirrors loop-run-log action inputs.
set -euo pipefail

# shellcheck disable=SC1091
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/append.sh"

ATTEMPTS="${ATTEMPTS:-}"
HAS_CHANGES="${HAS_CHANGES:-}"
VERDICT="${VERDICT:-}"
USAGE_JSON="${USAGE_JSON:-}"
WORKFLOW_RUN="${WORKFLOW_RUN:-}"
DURATION_S_INPUT="${DURATION_S_INPUT:-}"
RUN_STARTED_AT="${RUN_STARTED_AT:-}"

: "${LOOP_NAME:?}"
: "${OUTCOME:?}"
: "${RUN_LOG_FILE:=.loop/loop-run-log.md}"
: "${SKIP_REASON:=none}"
: "${TOKENS_ESTIMATE:=52000}"
: "${TOKEN:?}"

duration_s="${DURATION_S_INPUT}"
if [[ -z ${duration_s} ]]; then
    duration_s="$(loop_run_log_compute_duration "${RUN_STARTED_AT}")"
fi

entry_json="$(loop_run_log_build_entry \
    "${ATTEMPTS}" \
    "${duration_s}" \
    "${HAS_CHANGES}" \
    "${LOOP_NAME}" \
    "${OUTCOME}" \
    "${SKIP_REASON}" \
    "${TOKENS_ESTIMATE}" \
    "${VERDICT}" \
    "${WORKFLOW_RUN}" \
    "${USAGE_JSON}")"

loop_run_log_append_entry "${RUN_LOG_FILE}" "${entry_json}"
loop_run_log_commit_and_push "${BASE_BRANCH}" "${RUN_LOG_FILE}" "${TOKEN}"

if [[ -n ${GITHUB_OUTPUT:-} ]]; then
    DELIM="ENTRY_JSON_$(openssl rand -hex 8)"
    {
        echo "entry_json<<${DELIM}"
        echo "${entry_json}"
        echo "${DELIM}"
    } >> "${GITHUB_OUTPUT}"
fi
