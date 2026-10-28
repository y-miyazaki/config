#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154

# Tests for .github/actions/loop-execute/lib/common.sh

# Use cases:
# - render_template replaces placeholders
# - validate_agent_unchanged_verdict accepts APPROVE and REJECT
# - validate_agent_unchanged_verdict fails on empty (no REJECT default) and ignores
#   the legacy NO_CHANGES_VERDICT name
# - validate_agent_unchanged_verdict fails on values other than APPROVE / REJECT
# - parse_output_field extracts legacy line fields
# - materialize_matrix_handoff_context resolves detect JSON from loop-handoff artifact
# - materialize_matrix_handoff_context writes detect file and keeps prompt compact
# - materialize_matrix_handoff_context rebuilds verifier_context from detect result when artifact omits it
# - materialize_matrix_handoff_context fails when required artifact payload is missing

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

setup() {
    bats_source_rel ".github/actions/lib/loop/handoff.sh"
    bats_source_rel ".github/actions/loop-execute/lib/common.sh"
}

@test "render_template replaces placeholders" {
    result=$(render_template "Hello {{name}}, attempt {{n}}" name "world" n "2")
    [ "${result}" = "Hello world, attempt 2" ]
}

@test "parse_output_field extracts legacy line fields" {
    tmpf=$(mktemp)
    cat > "${tmpf}" << 'EOF'
VERDICT: REJECT
REASON: Missing tests
FILES: docs/a.md,src/b.go
EOF
    run parse_output_field "${tmpf}" "REASON"
    [ "$status" -eq 0 ]
    [ "$output" = "Missing tests" ]
    rm -f "${tmpf}"
}

@test "load_default_prompts fills empty prompt env vars" {
    unset PROMPT_VERIFIER_TASK
    unset PROMPT_VERIFIER_OUTPUT_CONTRACT
    load_default_prompts
    [[ ${PROMPT_VERIFIER_TASK} == *"loop maker"* ]]
    [[ ${PROMPT_VERIFIER_OUTPUT_CONTRACT} == *'"verdict"'* ]]
}

@test "materialize_matrix_handoff_context resolves detect JSON from loop-handoff artifact" {
    local candidate

    candidate='{"target_json":{"key":"integration:main"},"prompt":"p","verifier_context":"stored","result":{"commits":[{"sha":"abc1234567890","type":"feat","scope":"","breaking":false,"subject":"from artifact"}]}}' # pragma: allowlist secret
    loop_handoff_write_bundle "${BATS_TEST_TMPDIR}/loop-handoff" "${candidate}"

    PROMPT_TEXT=$'Run skill\n\n## Change Detection Result\n__LOOP_DETECT_RESULT_JSON__\n'
    DETECT_RESULT_JSON="{}"
    LOOP_HANDOFF_DIR="${BATS_TEST_TMPDIR}/loop-handoff"
    HANDOFF_KEY="integration:main"
    VERIFIER_CONTEXT=""
    STATUS_DIR="${BATS_TEST_TMPDIR}/loop-status-artifact"
    mkdir -p "${STATUS_DIR}"

    materialize_matrix_handoff_context

    [ -f "${DETECT_JSON_FILE}" ]
    run jq -e '.commits[0].subject == "from artifact"' "${DETECT_JSON_FILE}"
    [ "$status" -eq 0 ]
    [ "${VERIFIER_CONTEXT}" = "stored" ]
}

@test "materialize_matrix_handoff_context writes detect file and keeps prompt compact" {
    local detect_json

    detect_json='{"commits":[{"sha":"abc1234567890","type":"feat","scope":"","breaking":false,"subject":"add thing"}]}' # pragma: allowlist secret
    PROMPT_TEXT=$'Run skill\n\n## Change Detection Result\n__LOOP_DETECT_RESULT_JSON__\n'
    DETECT_RESULT_JSON="${detect_json}"
    VERIFIER_CONTEXT=""
    STATUS_DIR="${BATS_TEST_TMPDIR}/loop-status"
    mkdir -p "${STATUS_DIR}"

    materialize_matrix_handoff_context

    [ -f "${DETECT_JSON_FILE}" ]
    run jq -e '.commits[0].subject == "add thing"' "${DETECT_JSON_FILE}"
    [ "$status" -eq 0 ]
    [[ ${PROMPT_TEXT} == *"Structured detect JSON path: ${DETECT_JSON_FILE}"* ]]
    [[ ${PROMPT_TEXT} != *'"commits"'* ]]
    [[ ${PROMPT_TEXT} != *"__LOOP_DETECT_RESULT_JSON__"* ]]
    [[ ${VERIFIER_CONTEXT} == *"## Changelog Commits"* ]]
}

@test "materialize_matrix_handoff_context rebuilds verifier_context from detect result when artifact omits it" {
    local candidate detect_file

    candidate='{"target_json":{"key":"integration:main"},"prompt":"p","verifier_context":"","result":{"commits":[{"sha":"abc1234567890","type":"feat","scope":"","breaking":false,"subject":"from artifact"}]}}' # pragma: allowlist secret
    loop_handoff_write_bundle "${BATS_TEST_TMPDIR}/loop-handoff" "${candidate}"

    PROMPT_TEXT="Run skill"
    DETECT_RESULT_JSON="{}"
    LOOP_HANDOFF_DIR="${BATS_TEST_TMPDIR}/loop-handoff"
    HANDOFF_KEY="integration:main"
    VERIFIER_CONTEXT=""
    STATUS_DIR="${BATS_TEST_TMPDIR}/loop-status-rebuild"
    mkdir -p "${STATUS_DIR}"

    materialize_matrix_handoff_context

    [[ ${VERIFIER_CONTEXT} == *"## Changelog Commits"* ]]
    [[ ${VERIFIER_CONTEXT} == *"from artifact"* ]]
}

@test "materialize_matrix_handoff_context fails when required artifact payload is missing" {
    PROMPT_TEXT="Run skill"
    DETECT_RESULT_JSON="{}"
    LOOP_HANDOFF_DIR="${BATS_TEST_TMPDIR}/missing-handoff"
    HANDOFF_KEY="integration:main"
    mkdir -p "${LOOP_HANDOFF_DIR}/payloads"
    VERIFIER_CONTEXT=""
    STATUS_DIR="${BATS_TEST_TMPDIR}/loop-status-fail"
    mkdir -p "${STATUS_DIR}"

    run materialize_matrix_handoff_context
    [ "$status" -eq 1 ]
    [[ $output == *"handoff payload missing"* ]]
}

@test "materialize_matrix_handoff_context fails on invalid inline detect json" {
    PROMPT_TEXT="Run skill"
    DETECT_RESULT_JSON="not-json"
    unset LOOP_HANDOFF_DIR HANDOFF_KEY
    VERIFIER_CONTEXT=""
    STATUS_DIR="${BATS_TEST_TMPDIR}/loop-status-invalid-inline"
    mkdir -p "${STATUS_DIR}"

    run materialize_matrix_handoff_context
    [ "$status" -eq 1 ]
    [[ $output == *"inline DETECT_RESULT_JSON is invalid"* ]]
}

@test "validate_agent_unchanged_verdict accepts APPROVE and REJECT" {
    local value checked=0
    for value in APPROVE REJECT; do
        AGENT_UNCHANGED_VERDICT="${value}"
        run validate_agent_unchanged_verdict
        [ "${status}" -eq 0 ]
        [ -z "${output}" ]
        checked=$((checked + 1))
    done
    [ "${checked}" -eq 2 ]
}

@test "validate_agent_unchanged_verdict fails on empty and ignores NO_CHANGES_VERDICT" {
    unset AGENT_UNCHANGED_VERDICT
    NO_CHANGES_VERDICT="APPROVE"
    run validate_agent_unchanged_verdict
    [ "${status}" -eq 1 ]
    [ "${output}" = "::error::agent_unchanged_verdict is required (APPROVE or REJECT); got: ''" ]
}

@test "validate_agent_unchanged_verdict fails on values other than APPROVE or REJECT" {
    local value checked=0
    for value in approve reject maybe; do
        AGENT_UNCHANGED_VERDICT="${value}"
        run validate_agent_unchanged_verdict
        [ "${status}" -eq 1 ]
        [ "${output}" = "::error::agent_unchanged_verdict is required (APPROVE or REJECT); got: '${value}'" ]
        checked=$((checked + 1))
    done
    [ "${checked}" -eq 3 ]
}
