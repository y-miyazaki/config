#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154

# Tests for .apm/packages/github/.apm/skills/github-issue-triage/scripts/issue_comment.sh

# Use cases:
# - create always posts a new Issue comment (does not PATCH)
# - correct PATCHes the latest marker comment only
# - correct fails when no marker comment exists

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

COMMENT_SCRIPT=""

install_issue_comment_gh_mock() {
    local mock_bin="${BATS_TEST_TMPDIR}/bin"
    mkdir -p "${mock_bin}"
    cat > "${mock_bin}/gh" << 'EOF'
#!/usr/bin/env bash
log="${GITHUB_MOCK_LOG:-/dev/null}"
printf '%s\n' "$*" >> "${log}"

if [[ $1 == "issue" && $2 == "comment" ]]; then
    exit 0
fi

if [[ $1 == "api" && $2 == "--method" && $3 == "PATCH" ]]; then
    exit 0
fi

if [[ $1 == "api" ]]; then
    if [[ -n ${GITHUB_MOCK_COMMENTS_JSON:-} && -f ${GITHUB_MOCK_COMMENTS_JSON} ]]; then
        cat "${GITHUB_MOCK_COMMENTS_JSON}"
        exit 0
    fi
    echo '[]'
    exit 0
fi

echo "unexpected gh invocation: $*" >&2
exit 1
EOF
    chmod +x "${mock_bin}/gh"
    export PATH="${mock_bin}:${PATH}"
}

setup() {
    BATS_WORKSPACE_ROOT="$(bats_workspace_root)"
    COMMENT_SCRIPT="$(apm_skill_script_path github-issue-triage issue_comment.sh)"
    install_issue_comment_gh_mock
    export GITHUB_MOCK_LOG="${BATS_TEST_TMPDIR}/gh.log"
    : > "${GITHUB_MOCK_LOG}"
    export GITHUB_MOCK_COMMENTS_JSON="${BATS_TEST_TMPDIR}/comments.json"
    echo '[]' > "${GITHUB_MOCK_COMMENTS_JSON}"
    BODY_FILE="${BATS_TEST_TMPDIR}/body.md"
    printf '%s\n' "Triage analysis" > "${BODY_FILE}"
}

@test "create posts a new issue comment even when a marker comment exists" {
    cat > "${GITHUB_MOCK_COMMENTS_JSON}" << 'EOF'
[
  {
    "id": 11,
    "created_at": "2026-08-01T00:00:00Z",
    "body": "<!-- github-issue-triage:v1 -->\nold"
  }
]
EOF
    run bash "${COMMENT_SCRIPT}" create 81 "${BODY_FILE}" --repo octocat/Hello-World
    [ "$status" -eq 0 ]
    run jq -e '.action == "create" and .issue_number == 81' <<< "${output}"
    [ "$status" -eq 0 ]
    run grep -E '^issue comment 81 ' "${GITHUB_MOCK_LOG}"
    [ "$status" -eq 0 ]
    run grep -F "PATCH" "${GITHUB_MOCK_LOG}"
    [ "$status" -ne 0 ]
}

@test "correct patches the latest marker comment and not an older one" {
    cat > "${GITHUB_MOCK_COMMENTS_JSON}" << 'EOF'
[
  {
    "id": 11,
    "created_at": "2026-08-01T00:00:00Z",
    "body": "<!-- github-issue-triage:v1 -->\nold"
  },
  {
    "id": 22,
    "created_at": "2026-08-02T00:00:00Z",
    "body": "human reply without marker"
  },
  {
    "id": 33,
    "created_at": "2026-08-03T00:00:00Z",
    "body": "<!-- github-issue-triage:v1 -->\nlatest"
  }
]
EOF
    run bash "${COMMENT_SCRIPT}" correct 81 "${BODY_FILE}" --repo octocat/Hello-World
    [ "$status" -eq 0 ]
    run jq -e '.action == "update" and .comment_id == 33' <<< "${output}"
    [ "$status" -eq 0 ]
    run grep -F "issues/comments/33" "${GITHUB_MOCK_LOG}"
    [ "$status" -eq 0 ]
    run grep -E '^issue comment ' "${GITHUB_MOCK_LOG}"
    [ "$status" -ne 0 ]
}

@test "correct fails when no marker comment exists" {
    echo '[]' > "${GITHUB_MOCK_COMMENTS_JSON}"
    run bash "${COMMENT_SCRIPT}" correct 81 "${BODY_FILE}" --repo octocat/Hello-World
    [ "$status" -ne 0 ]
    run grep -E '^issue comment ' "${GITHUB_MOCK_LOG}"
    [ "$status" -ne 0 ]
}
