#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154

# Tests for shared hook JSON helper functions across apm hook packages.
#
# Use cases:
# - emit_json_with_reason avoids ARG_MAX by piping reason text to jq
# - report_failure uses emit_json_with_reason in go/shell/terraform hook families
# - truncate_reason_text caps oversized reason payloads

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

COMMON_HOOK="$(bats_workspace_root)/.apm/packages/common-hooks-cursor/.apm/hooks/scripts/markdownlint_cli2.sh"
GO_HOOK="$(bats_workspace_root)/.apm/packages/go-hooks-cursor/.apm/hooks/scripts/golangci_lint.sh"
SHELL_HOOK="$(bats_workspace_root)/.apm/packages/shell-script-hooks-cursor/.apm/hooks/scripts/shellcheck.sh"
TERRAFORM_HOOK="$(bats_workspace_root)/.apm/packages/terraform-hooks-cursor/.apm/hooks/scripts/tflint.sh"

setup_common_hook() {
    # shellcheck disable=SC1090
    source "${COMMON_HOOK}"
    HOOK_STDIN_DATA='{"hook_event_name":"stop","cursor_version":"3.13.25","workspace_roots":["/workspace"]}'
}

setup_go_hook() {
    # shellcheck disable=SC1090
    source "${GO_HOOK}"
    HOOK_STDIN_DATA='{"hook_event_name":"stop","cursor_version":"3.13.25","workspace_roots":["/workspace"]}'
}

@test "emit_json_with_reason builds followup_message JSON" {
    setup_common_hook
    run emit_json_with_reason "lint failed" '{followup_message: .}'
    [ "$status" -eq 0 ]
    [[ ${output} == *'"followup_message"'* ]]
    [[ ${output} == *'lint failed'* ]]
}

@test "golangci_lint report_failure emits followup_message for cursor stop" {
    setup_go_hook
    run report_failure "golangci-lint found issues in Go code:
main.go:1:1: undefined: foo"
    [ "$status" -eq 0 ]
    [[ ${output} == *'"followup_message"'* ]]
    [[ ${output} == *'undefined: foo'* ]]
}

@test "shellcheck hook defines JSON helper functions" {
    # shellcheck disable=SC1090
    source "${SHELL_HOOK}"
    declare -F truncate_reason_text > /dev/null
    declare -F emit_json_with_reason > /dev/null
}

@test "tflint hook defines JSON helper functions" {
    # shellcheck disable=SC1090
    source "${TERRAFORM_HOOK}"
    declare -F truncate_reason_text > /dev/null
    declare -F emit_json_with_reason > /dev/null
}

@test "truncate_reason_text appends marker when text exceeds limit" {
    setup_common_hook
    REASON_TRUNCATE_CHARS=10
    run truncate_reason_text "0123456789abcdef"
    [ "$status" -eq 0 ]
    [ "$output" = $'0123456789\n...[truncated]' ]
}
