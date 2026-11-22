#!/usr/bin/env bats

# Tests for .apm/packages/terraform-hooks-*/.apm/hooks/scripts/tflint.sh
#
# Use cases:
# - a changed .tf file lints its own directory
# - a changed .tfvars file in a directory without .tf files lints the nearest module above it
# - a removed .tf file lints the surviving directory, or the nearest surviving ancestor when the directory is gone
# - a changed file with no module above it is not linted
# - every agent package ships the same script

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

setup() {
    ROOT="$(bats_workspace_root)"
    HOOK="${ROOT}/.apm/packages/terraform-hooks-claude/.apm/hooks/scripts/tflint.sh"
    REPO="${BATS_TEST_TMPDIR}/repo"
    STOP_JSON='{"hook_event_name":"Stop","stop_hook_active":false,"session_id":"s1"}'
    export TMPDIR="${BATS_TEST_TMPDIR}/state-tmp"
    mkdir -p "${TMPDIR}" "${BATS_TEST_TMPDIR}/bin"
    unset HOOK_BLOCK_LIMIT

    # Stub that records the linted directory and fails so the hook reports it
    cat > "${BATS_TEST_TMPDIR}/bin/tflint" << 'STUB'
#!/bin/bash
for a in "$@"; do case "$a" in --init) exit 0;; esac; done
echo "TFLINT: $*"
exit 1
STUB
    chmod +x "${BATS_TEST_TMPDIR}/bin/tflint"

    mkdir -p "${REPO}/m1/sub" "${REPO}/m2" "${REPO}/loose"
    git -C "${REPO}" init -q
    git -C "${REPO}" config user.email "test@example.com"
    git -C "${REPO}" config user.name "test"
    printf '# m1\n' > "${REPO}/m1/main.tf"
    printf '# m1 vars\n' > "${REPO}/m1/vars.tf"
    printf '# m2\n' > "${REPO}/m2/main.tf"
    printf 'x = 1\n' > "${REPO}/m1/sub/a.tfvars"
    git -C "${REPO}" add .
    git -C "${REPO}" commit -q -m init
}

run_hook() {
    run bash -c "cd '${REPO}' && PATH='${BATS_TEST_TMPDIR}/bin':\$PATH bash '${HOOK}' <<< '${STOP_JSON}'"
}

@test "a changed file with no module above it is not linted" {
    printf 'x = 1\n' > "${REPO}/loose/l.hcl"
    run_hook
    [ "$status" -eq 0 ]
    [[ ${output} != *'TFLINT'* ]]
}

@test "a changed tf file lints its own directory" {
    printf '# touch\n' >> "${REPO}/m2/main.tf"
    run_hook
    [[ ${output} == *'--chdir m2'* ]]
    [[ ${output} != *'--chdir m1'* ]]
}

@test "a changed tfvars file in a directory without tf files lints the nearest module above it" {
    printf 'x = 2\n' >> "${REPO}/m1/sub/a.tfvars"
    run_hook
    [[ ${output} == *'--chdir m1'* ]]
}

@test "a removed tf file lints the surviving directory or the nearest surviving ancestor" {
    rm "${REPO}/m1/vars.tf"
    run_hook
    [[ ${output} == *'--chdir m1'* ]]

    git -C "${REPO}" checkout -q -- m1/vars.tf
    mkdir -p "${REPO}/m1/gone"
    printf '# g\n' > "${REPO}/m1/gone/main.tf"
    git -C "${REPO}" add -A
    git -C "${REPO}" commit -q -m gone
    rm -r "${REPO}/m1/gone"
    rm -f "${TMPDIR}"/hook-state-*/* 2> /dev/null || true
    run_hook
    [[ ${output} == *'--chdir m1'* ]]
}

@test "every agent package ships the same tflint.sh" {
    local agent
    for agent in copilot cursor; do
        cmp "${HOOK}" "${ROOT}/.apm/packages/terraform-hooks-${agent}/.apm/hooks/scripts/tflint.sh"
    done
}
