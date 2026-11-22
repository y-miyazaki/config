#!/usr/bin/env bats

# Tests for .apm/packages/shell-script-hooks-*/.apm/hooks/scripts/shellcheck.sh
#
# Use cases:
# - a changed .sh file is checked
# - a changed executable extensionless file with a shell shebang is checked
# - a changed non-executable extensionless file or a non-shell shebang is not checked
# - every agent package ships the same shellcheck.sh and shfmt.sh

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

setup() {
    ROOT="$(bats_workspace_root)"
    HOOK="${ROOT}/.apm/packages/shell-script-hooks-claude/.apm/hooks/scripts/shellcheck.sh"
    REPO="${BATS_TEST_TMPDIR}/repo"
    STOP_JSON='{"hook_event_name":"Stop","stop_hook_active":false,"session_id":"s1"}'
    export TMPDIR="${BATS_TEST_TMPDIR}/state-tmp"
    mkdir -p "${TMPDIR}" "${BATS_TEST_TMPDIR}/bin" "${REPO}/tools"
    unset HOOK_BLOCK_LIMIT

    # Stub that records the checked files and fails so the hook reports them
    cat > "${BATS_TEST_TMPDIR}/bin/shellcheck" << 'STUB'
#!/bin/bash
echo "SHELLCHECK: $*"
exit 1
STUB
    chmod +x "${BATS_TEST_TMPDIR}/bin/shellcheck"

    git -C "${REPO}" init -q
    git -C "${REPO}" config user.email "test@example.com"
    git -C "${REPO}" config user.name "test"
    printf 'x\n' > "${REPO}/readme.md"
    git -C "${REPO}" add .
    git -C "${REPO}" commit -q -m init
}

run_hook() {
    run bash -c "cd '${REPO}' && PATH='${BATS_TEST_TMPDIR}/bin':\$PATH bash '${HOOK}' <<< '${STOP_JSON}'"
}

@test "a changed executable extensionless file with a shell shebang is checked" {
    printf '#!/bin/bash\necho hi\n' > "${REPO}/tools/deploy"
    chmod +x "${REPO}/tools/deploy"
    run_hook
    [[ ${output} == *'SHELLCHECK: -x tools/deploy'* ]]
}

@test "a changed non-executable extensionless file or a non-shell shebang is not checked" {
    printf '#!/bin/bash\n' > "${REPO}/tools/not_exec"
    printf '#!/usr/bin/env python3\n' > "${REPO}/tools/tool"
    chmod +x "${REPO}/tools/tool"
    run_hook
    [ "$status" -eq 0 ]
    [[ ${output} != *'SHELLCHECK'* ]]
}

@test "a changed sh file is checked" {
    printf '#!/bin/bash\necho hi\n' > "${REPO}/lib.sh"
    run_hook
    [[ ${output} == *'SHELLCHECK: -x lib.sh'* ]]
}

@test "every agent package ships the same shellcheck.sh and shfmt.sh" {
    local agent script
    for agent in copilot cursor; do
        for script in shellcheck.sh shfmt.sh; do
            cmp "${ROOT}/.apm/packages/shell-script-hooks-claude/.apm/hooks/scripts/${script}" "${ROOT}/.apm/packages/shell-script-hooks-${agent}/.apm/hooks/scripts/${script}"
        done
    done
}
