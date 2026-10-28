#!/usr/bin/env bats

# Tests for .github/actions/aws-service-control-validate/lib/validate.sh
#
# Use cases:
# - rejects invalid action values
# - auto_discover decodes base64 targets
# - empty targets emit targets=[] without failure

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

VALIDATE_LIB="$(bats_workspace_root)/.github/actions/aws-service-control-validate/lib/validate.sh"

setup() {
    export GITHUB_OUTPUT="${BATS_TEST_TMPDIR}/github_output"
    : > "${GITHUB_OUTPUT}"
    export ACTION="start"
    export AUTO_DISCOVER="false"
    export DISCOVERED_B64=""
    export INPUT_FIELD_NAME="instances"
    export MANUAL_TARGETS_JSON='["i-123"]'
    export RESOURCE_LABEL="EC2 instances"
}

@test "validate_service_control_inputs rejects invalid action" {
    # shellcheck disable=SC1090
    source "${VALIDATE_LIB}"
    run bash -c 'source "'"${VALIDATE_LIB}"'"; ACTION=pause AUTO_DISCOVER=false MANUAL_TARGETS_JSON="[]" INPUT_FIELD_NAME=instances RESOURCE_LABEL="EC2 instances" GITHUB_OUTPUT="'"${GITHUB_OUTPUT}"'" validate_service_control_inputs'
    [ "$status" -eq 1 ]
    [[ $output == *"action must be 'start' or 'stop'"* ]]
}

@test "validate_service_control_inputs accepts manual targets json" {
    # shellcheck disable=SC1090
    source "${VALIDATE_LIB}"
    run bash -c 'source "'"${VALIDATE_LIB}"'"; ACTION=start AUTO_DISCOVER=false MANUAL_TARGETS_JSON="[\"i-123\"]" INPUT_FIELD_NAME=instances RESOURCE_LABEL="EC2 instances" GITHUB_OUTPUT="'"${GITHUB_OUTPUT}"'" validate_service_control_inputs'
    [ "$status" -eq 0 ]
    grep -q '^targets<<TARGETS_EOF$' "${GITHUB_OUTPUT}"
    grep -q '^\["i-123"\]$' "${GITHUB_OUTPUT}"
}

@test "validate_service_control_inputs rejects invalid manual targets json" {
    # shellcheck disable=SC1090
    source "${VALIDATE_LIB}"
    run bash -c 'source "'"${VALIDATE_LIB}"'"; ACTION=start AUTO_DISCOVER=false MANUAL_TARGETS_JSON="not-json" INPUT_FIELD_NAME=instances RESOURCE_LABEL="EC2 instances" GITHUB_OUTPUT="'"${GITHUB_OUTPUT}"'" validate_service_control_inputs'
    [ "$status" -eq 1 ]
    [[ $output == *"is not valid JSON"* ]]
}

@test "validate_service_control_inputs emits empty targets array" {
    # shellcheck disable=SC1090
    source "${VALIDATE_LIB}"
    run bash -c 'source "'"${VALIDATE_LIB}"'"; ACTION=start AUTO_DISCOVER=false MANUAL_TARGETS_JSON="[]" INPUT_FIELD_NAME=instances RESOURCE_LABEL="EC2 instances" GITHUB_OUTPUT="'"${GITHUB_OUTPUT}"'" validate_service_control_inputs'
    [ "$status" -eq 0 ]
    grep -q '^targets<<TARGETS_EOF$' "${GITHUB_OUTPUT}"
    grep -q '^\[\]$' "${GITHUB_OUTPUT}"
}

@test "validate_service_control_inputs decodes discovered targets" {
    # shellcheck disable=SC1090
    source "${VALIDATE_LIB}"
    local discovered_b64
    discovered_b64=$(printf '%s' '["queue-a"]' | base64 -w0)
    run bash -c 'source "'"${VALIDATE_LIB}"'"; ACTION=start AUTO_DISCOVER=true DISCOVERED_B64="'"${discovered_b64}"'" MANUAL_TARGETS_JSON="[]" INPUT_FIELD_NAME=job_queues RESOURCE_LABEL="Batch job queues" GITHUB_OUTPUT="'"${GITHUB_OUTPUT}"'" validate_service_control_inputs'
    [ "$status" -eq 0 ]
    grep -q '^targets<<TARGETS_EOF$' "${GITHUB_OUTPUT}"
    grep -q '^\["queue-a"\]$' "${GITHUB_OUTPUT}"
}
