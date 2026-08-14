#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154

# Tests for .apm/packages/github/.apm/skills/github-pr-body/scripts/pr_comment.sh

# Use cases:
# - --help exits successfully
# - invalid PR number 0 is rejected
# - invalid --repo slug is rejected
# - dry-run previews comment without calling gh write APIs

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

COMMENT_SCRIPT="$(apm_skill_script_path github-pr-body pr_comment.sh)"

install_pr_comment_gh_mock() {
    local mock_bin="${BATS_TEST_TMPDIR}/bin"
    mkdir -p "${mock_bin}"
    cat > "${mock_bin}/gh" << 'EOF'
#!/usr/bin/env bash
if [[ $1 == "pr" && $2 == "view" ]]; then
    if [[ " $* " == *" --json comments "* ]]; then
        jq -n '{comments: []}'
        exit 0
    fi
    exit 0
fi
if [[ $1 == "pr" && $2 == "comment" ]]; then
    echo "unexpected pr comment write: $*" >&2
    exit 1
fi
if [[ $1 == "api" ]]; then
    echo "unexpected gh api: $*" >&2
    exit 1
fi
echo "unexpected gh invocation: $*" >&2
exit 1
EOF
    chmod +x "${mock_bin}/gh"
    export PATH="${mock_bin}:${PATH}"
}

setup() {
    install_pr_comment_gh_mock
    COMMENT_FILE="${BATS_TEST_TMPDIR}/comment.md"
    cat > "${COMMENT_FILE}" << 'EOF'
<!-- github-pr-body:v1 -->
## Overview

Test overview comment.
EOF
}

@test "pr_comment --help exits successfully" {
    run bash "${COMMENT_SCRIPT}" --help
    [ "$status" -eq 0 ]
    [[ ${output} == *"COMMENT_FILE"* ]]
}

@test "pr_comment rejects invalid PR number zero" {
    run bash "${COMMENT_SCRIPT}" 0 "${COMMENT_FILE}" --repo octocat/Hello-World
    [ "$status" -ne 0 ]
    [[ ${output} == *"Invalid argument: 0"* ]] || [[ ${stderr} == *"Invalid argument: 0"* ]]
}

@test "pr_comment rejects invalid repository slug" {
    run env VERBOSE=true bash "${COMMENT_SCRIPT}" 123 "${COMMENT_FILE}" --repo 'not-a-valid-slug'
    [ "$status" -ne 0 ]
    [[ ${output} == *"Invalid repository slug"* ]] || [[ ${stderr} == *"Invalid repository slug"* ]]
}

@test "pr_comment dry-run previews comment without gh write APIs" {
    run env VERBOSE=true bash "${COMMENT_SCRIPT}" 123 "${COMMENT_FILE}" --repo octocat/Hello-World --dry-run
    [ "$status" -eq 0 ]
    [[ ${output} == *"DRY-RUN MODE"* ]] || [[ ${stderr} == *"DRY-RUN MODE"* ]]
    [[ ${output} == *"Test overview comment"* ]] || [[ ${stderr} == *"Test overview comment"* ]]
}
