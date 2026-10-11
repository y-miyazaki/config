#!/usr/bin/env bash
# Mock gh CLI helpers for bats tests.
# Load via: source "$(bats_support_dir)/gh_mock.bash" (after common.bash).

function mock_gh_setup() {
    GH_MOCK_DIR=$(mktemp -d)
    export GH_MOCK_DIR
    export PATH="$GH_MOCK_DIR:$PATH"
}

function mock_gh_teardown() {
    if [[ -n ${GH_MOCK_DIR:-} && -d $GH_MOCK_DIR ]]; then
        rm -rf "$GH_MOCK_DIR"
        unset GH_MOCK_DIR
    fi
}

# Convenience: write a gh mock script from stdin
function mock_gh_write() {
    cat > "$GH_MOCK_DIR/gh"
    chmod +x "$GH_MOCK_DIR/gh"
}

# Provide a helper to assert a mock exists for debugging
function mock_gh_path() {
    echo "$GH_MOCK_DIR/gh"
}

export -f mock_gh_setup mock_gh_teardown mock_gh_write mock_gh_path
