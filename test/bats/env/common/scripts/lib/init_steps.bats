#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154

# Tests for env/common/scripts/lib/init_steps.sh
#
# Use cases:
# - resolve_repo_root prints the git root of the workspace and falls back to the workspace folder outside git
# - index_codebase_memory indexes the whole root in one call when the tool accepts it
# - a "too broad" refusal falls back to one project per git-tracked top-level directory
# - the fallback names projects <repo-basename>-<directory> without a leading dot and skips untracked directories
# - any other indexing failure warns on stderr and does not fall back
# - index_codebase_memory is skipped silently when codebase-memory-mcp is missing
# - auto-index settings are applied after indexing
# - install_mise_global_node sets the node pinned by mise.toml as the mise global without the lock
# - install_mise_global_node warns and skips when mise.toml pins no node, and is silent without mise or mise.toml

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

setup() {
    REPO_ROOT="$(bats_workspace_root)"
    SCRIPT="${REPO_ROOT}/env/common/scripts/lib/init_steps.sh"
    MOCK_BIN="${BATS_TEST_TMPDIR}/bin"
    CALL_LOG="${BATS_TEST_TMPDIR}/calls.log"
    WORK="${BATS_TEST_TMPDIR}/work/myrepo"
    mkdir -p "${MOCK_BIN}" "${WORK}/scripts" "${WORK}/.apm" "${WORK}/untracked"
    : > "${CALL_LOG}"
    : > "${WORK}/top.txt"
    : > "${WORK}/scripts/a.sh"
    : > "${WORK}/.apm/b.yml"
    : > "${WORK}/untracked/c.txt"
    git -C "${WORK}" init -q
    git -C "${WORK}" add top.txt scripts .apm
    export CALL_LOG WORK
    write_mock ok
}

# write_mock: Install a codebase-memory-mcp mock; $1 = behavior for the whole root (ok|broad|fail)
write_mock() {
    local mode="$1"
    cat > "${MOCK_BIN}/codebase-memory-mcp" << EOF
#!/usr/bin/env bash
if [[ "\$1" == "cli" ]]; then
    input="\$(cat)"
    echo "index \${input}" >> "${CALL_LOG}"
    path="\$(printf '%s' "\${input}" | jq -r .repo_path)"
    if [[ "\${path}" == "${WORK}" ]]; then
        case "${mode}" in
            broad) echo "\${path}: path is too broad to index as one root; name a project directory below it" >&2; exit 1 ;;
            fail) echo "boom" >&2; exit 1 ;;
        esac
    fi
    exit 0
fi
echo "\$*" >> "${CALL_LOG}"
EOF
    chmod +x "${MOCK_BIN}/codebase-memory-mcp"
}

# run_index: Source init_steps.sh and run index_codebase_memory against the work repository
run_index() {
    run env PATH="${MOCK_BIN}:${PATH}" bash -c "source '${SCRIPT}' && REPO_ROOT='${WORK}' && index_codebase_memory"
}

teardown() {
    rm -rf "${BATS_TEST_TMPDIR}/work" "${MOCK_BIN}"
}

@test "resolve_repo_root prints the git root of the workspace" {
    run bash -c "source '${SCRIPT}' && WORKSPACE='${WORK}' && resolve_repo_root"
    [ "$status" -eq 0 ]
    [ "$output" = "${WORK}" ]
}

@test "resolve_repo_root falls back to the workspace folder outside git" {
    local outside="${BATS_TEST_TMPDIR}/not_git"
    mkdir -p "${outside}"
    run bash -c "cd '${outside}' && source '${SCRIPT}' && WORKSPACE='${outside}' && resolve_repo_root"
    [ "$status" -eq 0 ]
    [ "$output" = "${outside}" ]
}

@test "index_codebase_memory is skipped silently when codebase-memory-mcp is missing" {
    rm -f "${MOCK_BIN}/codebase-memory-mcp"
    run env PATH="${MOCK_BIN}:/usr/bin:/bin" bash -c "source '${SCRIPT}' && REPO_ROOT='${WORK}' && index_codebase_memory"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "a too broad refusal falls back to one project per git-tracked top-level directory" {
    write_mock broad
    run_index
    [ "$status" -eq 0 ]
    [[ $output == *"as myrepo-apm"* ]]
    [[ $output == *"as myrepo-scripts"* ]]
    [ "$(grep -c '^index' "${CALL_LOG}")" -eq 3 ]
}

@test "any other indexing failure warns and does not fall back" {
    write_mock fail
    run_index
    [ "$status" -eq 0 ]
    [[ $output == *"[warn] codebase-memory-mcp indexing failed: boom"* ]]
    [ "$(grep -c '^index' "${CALL_LOG}")" -eq 1 ]
}

@test "auto-index settings are applied after indexing" {
    run_index
    [ "$status" -eq 0 ]
    grep -q "config set auto_index true" "${CALL_LOG}"
    grep -q "config set auto_index_limit 50000" "${CALL_LOG}"
}

@test "the fallback skips directories that git does not track" {
    write_mock broad
    run_index
    [ "$status" -eq 0 ]
    [[ $output != *"untracked"* ]]
}

@test "the whole root is indexed in one call when the tool accepts it" {
    run_index
    [ "$status" -eq 0 ]
    [ "$(grep -c '^index' "${CALL_LOG}")" -eq 1 ]
    [[ $output == *"indexed ${WORK}"* ]]
}

# write_mise_mock: Install a mise mock; $1 = node version printed by "mise current node" (empty prints nothing)
write_mise_mock() {
    local version="$1"
    cat > "${MOCK_BIN}/mise" << EOF
#!/usr/bin/env bash
if [[ "\$1" == "current" ]]; then
    [[ -n "${version}" ]] && echo "${version}"
    exit 0
fi
echo "MISE_LOCKED=\${MISE_LOCKED:-unset} \$*" >> "${CALL_LOG}"
EOF
    chmod +x "${MOCK_BIN}/mise"
}

@test "install_mise_global_node is silent without mise" {
    : > "${WORK}/mise.toml"
    run env PATH="${MOCK_BIN}:/usr/bin:/bin" bash -c "source '${SCRIPT}' && REPO_ROOT='${WORK}' && install_mise_global_node"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "install_mise_global_node is silent without mise.toml" {
    write_mise_mock "24.22.3"
    run env PATH="${MOCK_BIN}:${PATH}" bash -c "source '${SCRIPT}' && REPO_ROOT='${WORK}' && install_mise_global_node"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    [ ! -s "${CALL_LOG}" ]
}

@test "install_mise_global_node sets the pinned node as global without the lock" {
    : > "${WORK}/mise.toml"
    write_mise_mock "24.22.3"
    run env PATH="${MOCK_BIN}:${PATH}" bash -c "source '${SCRIPT}' && REPO_ROOT='${WORK}' && install_mise_global_node"
    [ "$status" -eq 0 ]
    grep -qx "MISE_LOCKED=0 use -g node@24.22.3" "${CALL_LOG}"
}

@test "install_mise_global_node warns and skips when mise.toml pins no node" {
    : > "${WORK}/mise.toml"
    write_mise_mock ""
    run env PATH="${MOCK_BIN}:${PATH}" bash -c "source '${SCRIPT}' && REPO_ROOT='${WORK}' && install_mise_global_node"
    [ "$status" -eq 0 ]
    [[ $output == *"[warn] mise global node skipped"* ]]
    [ ! -s "${CALL_LOG}" ]
}
