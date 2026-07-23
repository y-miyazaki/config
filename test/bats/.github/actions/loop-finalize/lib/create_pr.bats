#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154

# Tests for .github/actions/loop-finalize/lib/create_pr.sh
#
# Use cases:
# - create_pr exits cleanly after PR creation (EXIT trap must not reference local scope)

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

setup() {
    local candidate

    MOCK_BIN="${BATS_TEST_TMPDIR}/bin"
    HANDOFF_DIR="${BATS_TEST_TMPDIR}/loop-handoff"
    mkdir -p "${MOCK_BIN}"

    cat > "${MOCK_BIN}/gh" << 'EOF'
#!/bin/bash
if [[ "$1" == "pr" && "$2" == "create" ]]; then
    echo "https://github.com/example/repo/pull/42"
    exit 0
fi
if [[ "$1" == "pr" && "$2" == "view" ]]; then
    echo '{"number":42}'
    exit 0
fi
printf 'unexpected gh: %s\n' "$*" >&2
exit 1
EOF
    chmod +x "${MOCK_BIN}/gh"
    export PATH="${MOCK_BIN}:${PATH}"

    bats_source_rel ".github/actions/lib/loop/handoff.sh"
    candidate='{"target_json":{"key":"integration:main"},"prompt":"p","verifier_context":"","result":{"failures":[]}}'
    loop_handoff_write_bundle "${HANDOFF_DIR}" "${candidate}"
}

@test "create_pr exits cleanly after successful PR creation" {
    local script

    script="$(bats_workspace_root)/.github/actions/loop-finalize/lib/create_pr.sh"
    export BRANCH="loop/test-branch"
    export DETECT_RESULT_JSON="{}"
    export GH_TOKEN="test-token"
    export GITHUB_REPOSITORY="example/repo"
    export HANDOFF_KEY="integration:main"
    export LOOP_HANDOFF_DIR="${HANDOFF_DIR}"
    export NOTIFY_CONTEXT_JSON='{"changed_files":[],"agent_report_summary":"done"}'
    export PR_BASE_BRANCH="main"
    export PR_BODY="Automated update"
    export PR_TITLE="chore: test"
    export SKIP_REASON="none"
    export TARGET_JSON='{"key":"integration:main"}'

    run bash "${script}"
    [ "$status" -eq 0 ]
    [[ $output == *"https://github.com/example/repo/pull/42"* ]]
}
