#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2154

# Tests for scripts/terraform/integration.sh
#
# Use cases:
# - run_additional_checks runs tflint --init then tflint with --call-module-type=all, not the removed --module option
# - run_additional_checks only warns when tflint reports issues
# - run_additional_checks skips tflint when it is not installed

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

INTEGRATION_SCRIPT="$(bats_workspace_root)/scripts/terraform/integration.sh"

setup() {
    MOCK_BIN="${BATS_TEST_TMPDIR}/bin"
    mkdir -p "${MOCK_BIN}"
    TFLINT_ARGS_FILE="${BATS_TEST_TMPDIR}/tflint.args"
    export TFLINT_ARGS_FILE
}

teardown() {
    rm -rf "${MOCK_BIN}" "${TFLINT_ARGS_FILE}"
}

@test "run_additional_checks only warns when tflint reports issues" {
    cat > "${MOCK_BIN}/tflint" << 'EOF'
#!/usr/bin/env bash
exit 2
EOF
    chmod +x "${MOCK_BIN}/tflint"

    run bash -c "export PATH='${MOCK_BIN}':\"\$PATH\" && source '${INTEGRATION_SCRIPT}' && run_additional_checks"
    [ "$status" -eq 0 ]
    [[ $output == *"tflint found issues that should be addressed"* ]]
}

@test "run_additional_checks runs tflint --init then tflint with --call-module-type=all, not the removed --module option" {
    cat > "${MOCK_BIN}/tflint" << 'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${TFLINT_ARGS_FILE}"
EOF
    chmod +x "${MOCK_BIN}/tflint"

    run bash -c "export PATH='${MOCK_BIN}':\"\$PATH\" && source '${INTEGRATION_SCRIPT}' && run_additional_checks"
    [ "$status" -eq 0 ]
    [ "$(cat "${TFLINT_ARGS_FILE}")" = $'--init\n--call-module-type=all' ]
}

@test "run_additional_checks skips tflint when it is not installed" {
    # PATH limited to a dir with only the basics the script needs; no tflint, no trivy
    for cmd in bash cat date dirname basename tr sed grep; do
        ln -sf "$(command -v "$cmd")" "${MOCK_BIN}/${cmd}"
    done

    run bash -c "export PATH='${MOCK_BIN}' && source '${INTEGRATION_SCRIPT}' && run_additional_checks"
    [ "$status" -eq 0 ]
    [[ $output == *"tflint not available, skipping linting"* ]]
}
