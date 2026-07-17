#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154

# Tests for .github/actions/loop-install-cli/lib/install.sh

# Use cases:
# - install.sh rejects unsupported engine
# - install.sh resolves pinned npm package version
# - install.sh resolves latest npm package version via npm view
# - install.sh installs cursor CLI and appends bindir to GITHUB_PATH

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

INSTALL_SCRIPT="$(bats_workspace_root)/.github/actions/loop-install-cli/lib/install.sh"

setup() {
    MOCK_BIN="${BATS_TEST_TMPDIR}/bin"
    TEST_HOME="${BATS_TEST_TMPDIR}/home"
    mkdir -p "${MOCK_BIN}" "${TEST_HOME}"
    GITHUB_OUTPUT="${BATS_TEST_TMPDIR}/github_output"
    GITHUB_PATH="${BATS_TEST_TMPDIR}/github_path"
    : > "${GITHUB_OUTPUT}"
    : > "${GITHUB_PATH}"
    export HOME="${TEST_HOME}"
}

install_run() {
    run env \
        PATH="${MOCK_BIN}:${PATH}" \
        ENGINE="${ENGINE}" \
        CLI_VERSION="${CLI_VERSION}" \
        GITHUB_OUTPUT="${GITHUB_OUTPUT}" \
        GITHUB_PATH="${GITHUB_PATH}" \
        bash "${INSTALL_SCRIPT}"
}

@test "install.sh rejects unsupported engine" {
    ENGINE="unknown"
    CLI_VERSION="latest"
    install_run
    [ "$status" -eq 1 ]
}

@test "install.sh resolves pinned npm package version" {
    cat > "${MOCK_BIN}/npm" << 'EOF'
#!/usr/bin/env bash
if [[ $1 == "install" ]]; then
    exit 0
fi
echo "unexpected npm invocation: $*" >&2
exit 1
EOF
    chmod +x "${MOCK_BIN}/npm"

    ENGINE="claude"
    CLI_VERSION="1.2.3"
    install_run
    [ "$status" -eq 0 ]
    grep -Fx 'package=@anthropic-ai/claude-code' "${GITHUB_OUTPUT}"
    grep -Fx 'version=1.2.3' "${GITHUB_OUTPUT}"
}

@test "install.sh resolves latest npm package version via npm view" {
    cat > "${MOCK_BIN}/npm" << 'EOF'
#!/usr/bin/env bash
case "$1" in
    view)
        echo "9.9.9"
        ;;
    install)
        exit 0
        ;;
    *)
        echo "unexpected npm invocation: $*" >&2
        exit 1
        ;;
esac
EOF
    chmod +x "${MOCK_BIN}/npm"

    ENGINE="codex"
    CLI_VERSION="latest"
    install_run
    [ "$status" -eq 0 ]
    grep -Fx 'package=@openai/codex' "${GITHUB_OUTPUT}"
    grep -Fx 'version=9.9.9' "${GITHUB_OUTPUT}"
}

@test "install.sh installs cursor CLI and appends bindir to GITHUB_PATH" {
    cat > "${MOCK_BIN}/curl" << 'EOF'
#!/usr/bin/env bash
if [[ $1 == "https://cursor.com/install" ]]; then
    mkdir -p "${HOME}/.local/bin"
    printf '#!/bin/sh\nexit 0\n' > "${HOME}/.local/bin/agent"
    chmod +x "${HOME}/.local/bin/agent"
    exit 0
fi
echo "unexpected curl invocation: $*" >&2
exit 1
EOF
    chmod +x "${MOCK_BIN}/curl"

    ENGINE="cursor"
    CLI_VERSION="2.0.0"
    install_run
    [ "$status" -eq 0 ]
    grep -Fx 'package=cursor' "${GITHUB_OUTPUT}"
    grep -Fx 'version=2.0.0' "${GITHUB_OUTPUT}"
    grep -Fx "${TEST_HOME}/.local/bin" "${GITHUB_PATH}"
}
