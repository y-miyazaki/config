#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154

# Tests for .apm/packages/common-hooks-cursor/.apm/hooks/scripts/markdownlint_cli2.sh
#
# Use cases:
# - build_markdownlint_literal_targets emits :path args for --no-globs
# - failure detail truncation survives pipefail (no SIGPIPE exit 141)
# - markdownlint_has_issues detects Summary and error lines in captured output
# - markdownlint_requires_failure_report fail-closes on unknown non-zero exits
# - report_failure emits followup_message JSON for Cursor stop hooks

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

HOOK_SCRIPT="$(bats_workspace_root)/.apm/packages/common-hooks-cursor/.apm/hooks/scripts/markdownlint_cli2.sh"

setup() {
    # shellcheck disable=SC1090
    source "${HOOK_SCRIPT}"
    HOOK_STDIN_DATA='{"hook_event_name":"stop","cursor_version":"3.13.25","workspace_roots":["/workspace"]}'
}

@test "build_markdownlint_literal_targets prefixes changed paths" {
    mapfile -t targets < <(build_markdownlint_literal_targets docs/README.md .apm/foo.md)
    [ "${#targets[@]}" -eq 2 ]
    [ "${targets[0]}" = ":docs/README.md" ]
    [ "${targets[1]}" = ":.apm/foo.md" ]
}

@test "failure detail truncation survives pipefail" {
    run bash -c 'set -euo pipefail; source "'"${HOOK_SCRIPT}"'"; result=$(printf "%s\n" {1..120}); failure_detail=$(printf "%s\n" "$result" | grep -m 50 -E "^[0-9]+$" || true); [[ ${#failure_detail} -gt 0 ]]'
    [ "$status" -eq 0 ]
}

@test "markdownlint_has_issues detects summary and error output" {
    run markdownlint_has_issues $'markdownlint-cli2 v0.23.1\nSummary: 2 issues in 1 file\nfoo.md:1 error MD025/single-title'
    [ "$status" -eq 0 ]

    run markdownlint_has_issues $'markdownlint-cli2 v0.23.1\nSummary: 586 issues in 135 files\nfoo.md:1 error MD025'
    [ "$status" -eq 0 ]

    run markdownlint_has_issues $'markdownlint-cli2 v0.23.1\nSummary: 0 issues in 1 file'
    [ "$status" -eq 1 ]
}

@test "markdownlint_requires_failure_report fail-closes on unknown non-zero exit" {
    run markdownlint_requires_failure_report $'markdownlint-cli2 v0.23.1\nSummary: 2 issues in 1 file' 1
    [ "$status" -eq 0 ]

    run markdownlint_requires_failure_report $'Unable to parse config\nENOENT: no such file' 2
    [ "$status" -eq 0 ]

    run markdownlint_requires_failure_report $'markdownlint-cli2 v0.23.1\nSummary: 0 issues in 1 file' 0
    [ "$status" -eq 1 ]
}

@test "report_failure emits followup_message for cursor stop" {
    run report_failure "markdownlint-cli2 found issues:
sample.md:10 error MD025/single-title"
    [ "$status" -eq 0 ]
    [[ ${output} == *'"followup_message"'* ]]
    [[ ${output} == *'MD025/single-title'* ]]
}
