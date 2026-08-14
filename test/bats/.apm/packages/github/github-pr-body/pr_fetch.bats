#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154

# Tests for .apm/packages/github/.apm/skills/github-pr-body/scripts/pr_fetch.sh

# Use cases:
# - --help exits successfully
# - invalid PR number 0 is rejected
# - invalid --repo slug is rejected
# - fetch emits JSON metadata with mocked gh

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

FETCH_SCRIPT="$(apm_skill_script_path github-pr-body pr_fetch.sh)"

install_pr_fetch_gh_mock() {
    local mock_bin="${BATS_TEST_TMPDIR}/bin"
    mkdir -p "${mock_bin}"
    cat > "${mock_bin}/gh" << 'EOF'
#!/usr/bin/env bash
if [[ $1 == "pr" && $2 == "view" ]]; then
    jq -n \
        --arg title "Example PR title" \
        --arg body "## Overview\n\nTest body" \
        --argjson additions 3 \
        --argjson deletions 1 \
        --arg baseRefName "main" \
        --arg headRefName "feature/test" \
        --arg state "OPEN" \
        '{title: $title, body: $body, additions: $additions, deletions: $deletions, baseRefName: $baseRefName, headRefName: $headRefName, state: $state}'
    exit 0
fi
if [[ $1 == "api" ]]; then
    printf '%s\n' '[{"filename":"README.md","additions":2,"deletions":0}]'
    exit 0
fi
echo "unexpected gh invocation: $*" >&2
exit 1
EOF
    chmod +x "${mock_bin}/gh"
    export PATH="${mock_bin}:${PATH}"
}

setup() {
    install_pr_fetch_gh_mock
}

@test "fetch --help exits successfully" {
    run bash "${FETCH_SCRIPT}" --help
    [ "$status" -eq 0 ]
    [[ ${output} == *"PR_NUMBER"* ]]
}

@test "fetch rejects invalid PR number zero" {
    run bash "${FETCH_SCRIPT}" 0 --repo octocat/Hello-World
    [ "$status" -ne 0 ]
    [[ ${output} == *"Invalid argument: 0"* ]] || [[ ${stderr} == *"Invalid argument: 0"* ]]
}

@test "fetch rejects invalid repository slug" {
    run bash "${FETCH_SCRIPT}" 123 --repo 'not-a-valid-slug'
    [ "$status" -ne 0 ]
    [[ ${output} == *"Invalid repository slug"* ]] || [[ ${stderr} == *"Invalid repository slug"* ]]
}

@test "fetch emits JSON metadata with mocked gh" {
    run bash "${FETCH_SCRIPT}" 123 --repo octocat/Hello-World
    [ "$status" -eq 0 ]
    [[ ${output} == *'"metadata"'* ]]
    [[ ${output} == *'Example PR title'* ]]
}
