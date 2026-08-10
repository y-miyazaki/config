#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154

# Tests for .apm/packages/common/.apm/skills/github-pr-body/scripts/pr_body.sh

# Use cases:
# - section_has_visible_content ignores comment-only sections
# - generate_body_sections creates deterministic overview baseline
# - apply_complete_pr_body previews the full AI-completed body

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

install_github_pr_body_gh_mock() {
    local mock_bin="${BATS_TEST_TMPDIR}/bin"
    mkdir -p "${mock_bin}"
    cat > "${mock_bin}/gh" << 'EOF'
#!/usr/bin/env bash
if [[ $1 == "pr" && $2 == "view" ]]; then
    if [[ " $* " == *" --json body "* ]]; then
        jq -n --arg body "${GITHUB_PR_BODY_MOCK_VIEW_BODY:-}" '{body: $body}'
        exit 0
    fi
    jq -n \
        --arg title "Example PR title" \
        --arg body "${GITHUB_PR_BODY_MOCK_VIEW_BODY:-}" \
        --argjson additions 3 \
        --argjson deletions 1 \
        --arg baseRefName "main" \
        --arg headRefName "feature/test" \
        --arg state "OPEN" \
        '{title: $title, body: $body, additions: $additions, deletions: $deletions, baseRefName: $baseRefName, headRefName: $headRefName, state: $state}'
    exit 0
fi
if [[ $1 == "api" ]]; then
    printf '%s\n' '[{"filename":"README.md","additions":2,"deletions":0},{"filename":"scripts/demo.sh","additions":1,"deletions":1}]'
    exit 0
fi
echo "unexpected gh invocation: $*" >&2
exit 1
EOF
    chmod +x "${mock_bin}/gh"
    export PATH="${mock_bin}:${PATH}"
}

setup() {
    bats_source_apm_skill github-pr-body pr_body.sh
    install_github_pr_body_gh_mock

    export PR_NUMBER="123"
    export REPOSITORY="octocat/Hello-World"
    export DRY_RUN="true"
    export COMPLETE_BODY_FILE=""
    export BODY_FILE
    BODY_FILE="$(mktemp)"
    COMPLETE_BODY_PATH="$(mktemp)"

    GITHUB_PR_BODY_MOCK_VIEW_BODY=$(
        cat << 'EOF'
## Related Issues

<!--
Link related GitHub issues using #issue_number
-->
EOF
    )
    export GITHUB_PR_BODY_MOCK_VIEW_BODY

    cat > "$COMPLETE_BODY_PATH" << 'EOF'
## Overview

Completed AI overview.

## Testing

- Ran terraform validate for application modules.

## Type of Change

- [x] 🐛 Bug Fix: Issue resolution

## Checklist

- [x] Documentation updated if applicable

## Additional Notes

- No additional migration steps required.
EOF
}

teardown() {
    rm -f "$BODY_FILE"
    rm -f "$COMPLETE_BODY_PATH"
    unset GITHUB_PR_BODY_MOCK_VIEW_BODY
}

@test "section_has_visible_content ignores comment-only sections" {
    local section
    section=$(
        cat << 'EOF'
## Testing

<!-- single line comment -->

<!--
multi line comment
-->
EOF
    )

    run section_has_visible_content "$section"
    [ "$status" -ne 0 ]
}

@test "generate_body_sections creates deterministic overview baseline" {
    generate_body_sections

    run cat "$BODY_FILE"

    [ "$status" -eq 0 ]
    [[ $output == *"## Overview"* ]]
    [[ $output == *"**Title**: Example PR title"* ]]
    [[ $output == *"_This section was auto-generated._"* ]]
    [[ $output == *"README.md"* ]]
}

@test "apply_complete_pr_body previews the full AI-completed body" {
    COMPLETE_BODY_FILE="$COMPLETE_BODY_PATH"

    run apply_complete_pr_body

    [ "$status" -eq 0 ]
    [[ $output == *"Completed AI overview."* ]]
    [[ $output == *"Ran terraform validate for application modules."* ]]
    [[ $output == *"Documentation updated if applicable"* ]]
}
