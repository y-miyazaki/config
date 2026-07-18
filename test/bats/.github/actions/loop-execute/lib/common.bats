#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154

# Tests for .github/actions/loop-execute/lib/common.sh

# Use cases:
# - render_template replaces placeholders
# - normalize_no_changes_verdict defaults to APPROVE
# - normalize_no_changes_verdict coerces reject variants to REJECT
# - normalize_no_changes_verdict coerces unknown values to APPROVE
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
    bats_source_rel ".github/actions/loop-detect/lib/handoff.sh"
    bats_source_rel ".github/actions/loop-execute/lib/common.sh"
}

@test "render_template replaces placeholders" {
    result=$(render_template "Hello {{name}}, attempt {{n}}" name "world" n "2")
    [ "${result}" = "Hello world, attempt 2" ]
}

@test "normalize_no_changes_verdict defaults to APPROVE" {
    unset NO_CHANGES_VERDICT
    normalize_no_changes_verdict
    [ "${NO_CHANGES_VERDICT}" = "APPROVE" ]
}

@test "normalize_no_changes_verdict coerces reject variants to REJECT" {
    NO_CHANGES_VERDICT="reject"
    normalize_no_changes_verdict
    [ "${NO_CHANGES_VERDICT}" = "REJECT" ]
}

@test "normalize_no_changes_verdict coerces unknown values to APPROVE" {
    NO_CHANGES_VERDICT="maybe"
    normalize_no_changes_verdict
    [ "${NO_CHANGES_VERDICT}" = "APPROVE" ]
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
    [[ ${PROMPT_VERIFIER_TASK} == *"loop implementer"* ]]
    [[ ${PROMPT_VERIFIER_OUTPUT_CONTRACT} == *'"verdict"'* ]]
}

@test "materialize_matrix_handoff_context resolves detect JSON from loop-handoff artifact" {
    local candidate detect_file

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

    detect_file="${STATUS_DIR}/detect-result.json"
    [ -f "${detect_file}" ]
    run jq -e '.commits[0].subject == "from artifact"' "${detect_file}"
    [ "$status" -eq 0 ]
    [ "${VERIFIER_CONTEXT}" = "stored" ]
}

@test "materialize_matrix_handoff_context writes detect file and keeps prompt compact" {
    local detect_json detect_file

    detect_json='{"commits":[{"sha":"abc1234567890","type":"feat","scope":"","breaking":false,"subject":"add thing"}]}' # pragma: allowlist secret
    PROMPT_TEXT=$'Run skill\n\n## Change Detection Result\n__LOOP_DETECT_RESULT_JSON__\n'
    DETECT_RESULT_JSON="${detect_json}"
    VERIFIER_CONTEXT=""
    STATUS_DIR="${BATS_TEST_TMPDIR}/loop-status"
    mkdir -p "${STATUS_DIR}"

    materialize_matrix_handoff_context

    detect_file="${STATUS_DIR}/detect-result.json"
    [ -f "${detect_file}" ]
    run jq -e '.commits[0].subject == "add thing"' "${detect_file}"
    [ "$status" -eq 0 ]
    [[ ${PROMPT_TEXT} == *"Structured detect JSON path: ${detect_file}"* ]]
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
