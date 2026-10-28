#!/usr/bin/env bash
# Mock shellcheck/shfmt helpers for bats tests.
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
    cat > "$SHELL_TOOL_MOCK_DIR/shellcheck"
    chmod +x "$SHELL_TOOL_MOCK_DIR/shellcheck"
}

# Convenience: write a shfmt mock script from stdin
function mock_shfmt_write() {
    cat > "$SHELL_TOOL_MOCK_DIR/shfmt"
    chmod +x "$SHELL_TOOL_MOCK_DIR/shfmt"
}

export -f mock_shell_tool_setup mock_shell_tool_teardown mock_shellcheck_write mock_shfmt_write
