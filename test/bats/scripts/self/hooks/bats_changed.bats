#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154

# Tests for scripts/self/hooks/bats_changed.sh
#
# Use cases:
# - resolve_bats_suites maps a script to suites by their "# Tests for" header, including trailing text
# - resolve_bats_suites returns a changed .bats file itself and ignores unmapped scripts
# - resolve_bats_suites matches the path literally, not as a regex
# - report_failure emits Claude Code Stop block JSON
# - main blocks when a mapped suite fails and stays silent when it passes
# - resolve_runner_bin keeps the runner name unless it is a mise shim
# - resolve_runner_bin returns the real binary path for a mise shim
# - main skips when stop_hook_active is true or nothing changed

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

HOOK_SCRIPT="$(bats_workspace_root)/scripts/self/hooks/bats_changed.sh"

setup() {
    REPO="${BATS_TEST_TMPDIR}/repo"
    mkdir -p "${REPO}/scripts" "${REPO}/test/bats/other"
    git -C "${REPO}" init -q
    git -C "${REPO}" config user.email t@example.com
    git -C "${REPO}" config user.name t
    printf '#!/bin/bash\n:\n' > "${REPO}/scripts/a.sh"
    printf '#!/bin/bash\n:\n' > "${REPO}/scripts/axsh"
    git -C "${REPO}" add -A
    git -C "${REPO}" commit -q -m init
}

_write_suite() {
    # $1 = path under test/bats, $2 = header target, $3 = test body
    mkdir -p "$(dirname "${REPO}/test/bats/$1")"
    printf '#!/usr/bin/env bats\n# Tests for %s\n@test "t" {\n    %s\n}\n' "$2" "$3" > "${REPO}/test/bats/$1"
}

@test "resolve_bats_suites maps a script to suites by their Tests for header including trailing text" {
    _write_suite "other/a.bats" "scripts/a.sh (extra note)" "true"
    run bash -c "cd '${REPO}' && source '${HOOK_SCRIPT}' </dev/null && resolve_bats_suites scripts/a.sh"
    [ "$status" -eq 0 ]
    [ "$output" = "test/bats/other/a.bats" ]
}

@test "resolve_bats_suites returns a changed bats file itself and ignores unmapped scripts" {
    run bash -c "cd '${REPO}' && source '${HOOK_SCRIPT}' </dev/null && resolve_bats_suites scripts/a.sh test/bats/x.bats"
    [ "$status" -eq 0 ]
    [ "$output" = "test/bats/x.bats" ]
}

@test "resolve_bats_suites matches the path literally, not as a regex" {
    _write_suite "other/ax.bats" "scripts/axsh" "true"
    run bash -c "cd '${REPO}' && source '${HOOK_SCRIPT}' </dev/null && resolve_bats_suites scripts/a.sh"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "report_failure emits Claude Code Stop block JSON" {
    run bash -c "source '${HOOK_SCRIPT}' </dev/null && report_failure 'boom'"
    [ "$status" -eq 0 ]
    [ "$(printf '%s' "$output" | jq -r .decision)" = "block" ]
    [ "$(printf '%s' "$output" | jq -r .reason)" = "boom" ]
}

@test "main blocks when a mapped suite fails and stays silent when it passes" {
    _write_suite "other/a.bats" "scripts/a.sh" "false"
    echo '# changed' >> "${REPO}/scripts/a.sh"
    run bash -c "cd '${REPO}' && BATS_JOBS=1 bash '${HOOK_SCRIPT}' </dev/null"
    [ "$status" -eq 0 ]
    [ "$(printf '%s' "$output" | jq -r .decision)" = "block" ]
    _write_suite "other/a.bats" "scripts/a.sh" "true"
    run bash -c "cd '${REPO}' && BATS_JOBS=1 bash '${HOOK_SCRIPT}' </dev/null"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "main skips when stop_hook_active is true or nothing changed" {
    _write_suite "other/a.bats" "scripts/a.sh" "false"
    git -C "${REPO}" add -A
    git -C "${REPO}" commit -q -m suite
    run bash -c "cd '${REPO}' && BATS_JOBS=1 bash '${HOOK_SCRIPT}' </dev/null"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    echo '# changed' >> "${REPO}/scripts/a.sh"
    run bash -c "cd '${REPO}' && echo '{\"stop_hook_active\":true}' | BATS_JOBS=1 bash '${HOOK_SCRIPT}'"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "resolve_runner_bin keeps the runner name unless it is a mise shim" {
    mkdir -p "${BATS_TEST_TMPDIR}/bin"
    printf '#!/bin/bash\n' > "${BATS_TEST_TMPDIR}/bin/rush"
    chmod +x "${BATS_TEST_TMPDIR}/bin/rush"
    run bash -c "PATH='${BATS_TEST_TMPDIR}/bin':\$PATH; source '${HOOK_SCRIPT}' </dev/null && resolve_runner_bin rush"
    [ "$status" -eq 0 ]
    [ "$output" = "rush" ]
}

@test "resolve_runner_bin returns the real binary path for a mise shim" {
    mkdir -p "${BATS_TEST_TMPDIR}/shims" "${BATS_TEST_TMPDIR}/real"
    printf '#!/bin/bash\n' > "${BATS_TEST_TMPDIR}/shims/rush"
    printf '#!/bin/bash\n' > "${BATS_TEST_TMPDIR}/real/rush"
    printf '#!/bin/bash\necho "%s/real/rush"\n' "${BATS_TEST_TMPDIR}" > "${BATS_TEST_TMPDIR}/shims/mise"
    chmod +x "${BATS_TEST_TMPDIR}/shims/rush" "${BATS_TEST_TMPDIR}/shims/mise" "${BATS_TEST_TMPDIR}/real/rush"
    run bash -c "PATH='${BATS_TEST_TMPDIR}/shims':\$PATH; source '${HOOK_SCRIPT}' </dev/null && resolve_runner_bin rush"
    [ "$status" -eq 0 ]
    [ "$output" = "${BATS_TEST_TMPDIR}/real/rush" ]
}
