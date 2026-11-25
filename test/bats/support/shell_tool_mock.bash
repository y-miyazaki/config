#!/usr/bin/env bash
# Mock shellcheck/shfmt (and any other external CLI) helpers for bats tests.
# Load via: source "$(bats_support_dir)/shell_tool_mock.bash" (after common.bash).

function mock_shell_tool_setup() {
    SHELL_TOOL_MOCK_DIR=$(mktemp -d)
    export SHELL_TOOL_MOCK_DIR
    export PATH="$SHELL_TOOL_MOCK_DIR:$PATH"

    cat > "$SHELL_TOOL_MOCK_DIR/shellcheck" << 'EOF'
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "$SHELL_TOOL_MOCK_DIR/shellcheck"

    cat > "$SHELL_TOOL_MOCK_DIR/shfmt" << 'EOF'
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "$SHELL_TOOL_MOCK_DIR/shfmt"
}

function mock_shell_tool_teardown() {
    if [[ -n ${SHELL_TOOL_MOCK_DIR:-} && -d $SHELL_TOOL_MOCK_DIR ]]; then
        rm -rf "$SHELL_TOOL_MOCK_DIR"
        unset SHELL_TOOL_MOCK_DIR
    fi
}

# Convenience: write a shellcheck mock script from stdin
function mock_shellcheck_write() {
    mock_tool_write shellcheck
}

# Convenience: write a shfmt mock script from stdin
function mock_shfmt_write() {
    mock_tool_write shfmt
}

# Convenience: write a mock for any external CLI (name in $1) from stdin; call after
# mock_shell_tool_setup so the tool is found through PATH
function mock_tool_write() {
    cat > "$SHELL_TOOL_MOCK_DIR/$1"
    chmod +x "$SHELL_TOOL_MOCK_DIR/$1"
}

export -f mock_shell_tool_setup mock_shell_tool_teardown mock_shellcheck_write mock_shfmt_write mock_tool_write
