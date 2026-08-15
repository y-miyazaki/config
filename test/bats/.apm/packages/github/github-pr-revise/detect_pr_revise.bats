#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

DETECT_SCRIPT="$(apm_skill_script_path github-pr-revise detect_pr_revise.sh)"

@test "detect_pr_revise skips bot actor" {
    run env PR_NUMBER=5 PR_MENTION='@loop' PR_COMMENT_BODY='@loop please fix' \
        PR_ACTOR_TYPE=Bot bash "${DETECT_SCRIPT}"
    [ "$status" -eq 0 ]
    run jq -e '.skip == true and .status == "ok"' <<< "${output}"
    [ "$status" -eq 0 ]
}

@test "detect_pr_revise skips human without mention" {
    run env PR_NUMBER=5 PR_MENTION='@loop' PR_COMMENT_BODY='looks good' \
        PR_ACTOR_TYPE=User bash "${DETECT_SCRIPT}"
    [ "$status" -eq 0 ]
    run jq -e '.skip == true and .status == "ok"' <<< "${output}"
    [ "$status" -eq 0 ]
}

@test "detect_pr_revise skips human with empty comment body" {
    run env PR_NUMBER=5 PR_MENTION='@loop' PR_COMMENT_BODY='' \
        PR_ACTOR_TYPE=User bash "${DETECT_SCRIPT}"
    [ "$status" -eq 0 ]
    run jq -e '.skip == true and .status == "ok"' <<< "${output}"
    [ "$status" -eq 0 ]
}

@test "detect_pr_revise proceeds for human with @loop" {
    run env PR_NUMBER=5 PR_MENTION='@loop' PR_COMMENT_BODY='@loop please fix tests' \
        PR_ACTOR_TYPE=User bash "${DETECT_SCRIPT}"
    [ "$status" -eq 0 ]
    run jq -e '.skip == false and .result.pr_number == "5"' <<< "${output}"
    [ "$status" -eq 0 ]
}

@test "detect_pr_revise respects custom PR_MENTION" {
    run env PR_NUMBER=5 PR_MENTION='@waza' PR_COMMENT_BODY='@loop ignore' \
        PR_ACTOR_TYPE=User bash "${DETECT_SCRIPT}"
    [ "$status" -eq 0 ]
    run jq -e '.skip == true' <<< "${output}"
    [ "$status" -eq 0 ]

    run env PR_NUMBER=5 PR_MENTION='@waza' PR_COMMENT_BODY='@waza please revise' \
        PR_ACTOR_TYPE=User bash "${DETECT_SCRIPT}"
    [ "$status" -eq 0 ]
    run jq -e '.skip == false' <<< "${output}"
    [ "$status" -eq 0 ]
}

@test "detect_pr_revise rejects invalid PR_NUMBER with structured error" {
    run env PR_NUMBER=0 PR_MENTION='@loop' PR_COMMENT_BODY='@loop please fix' \
        PR_ACTOR_TYPE=User bash "${DETECT_SCRIPT}"
    [ "$status" -eq 1 ]
    run jq -e '.status == "error" and .skip == true' <<< "${output}"
    [ "$status" -eq 0 ]
}

@test "detect_pr_revise skips @loopback substring false positive" {
    run env PR_NUMBER=5 PR_MENTION='@loop' PR_COMMENT_BODY='@loopback please fix' PR_ACTOR_TYPE=User bash "${DETECT_SCRIPT}"
    [ "$status" -eq 0 ]
    run jq -e '.skip == true' <<< "${output}"
    [ "$status" -eq 0 ]
}

@test "detect_pr_revise proceeds for workflow_dispatch without mention" {
    cat > "${BATS_TEST_TMPDIR}/event.json" << 'EOF'
{
  "inputs": {
    "pr_number": "9",
    "feedback": "Please fix the failing test"
  }
}
EOF
    run env PR_NUMBER=9 GITHUB_EVENT_NAME=workflow_dispatch \
        GITHUB_EVENT_PATH="${BATS_TEST_TMPDIR}/event.json" \
        PR_ACTOR_TYPE=User bash "${DETECT_SCRIPT}"
    [ "$status" -eq 0 ]
    run jq -e '.skip == false and .result.comment_body == "Please fix the failing test"' <<< "${output}"
    [ "$status" -eq 0 ]
}

@test "detect_pr_revise skips workflow_dispatch without feedback" {
    cat > "${BATS_TEST_TMPDIR}/event.json" << 'EOF'
{
  "inputs": {
    "pr_number": "9",
    "feedback": ""
  }
}
EOF
    run env PR_NUMBER=9 GITHUB_EVENT_NAME=workflow_dispatch \
        GITHUB_EVENT_PATH="${BATS_TEST_TMPDIR}/event.json" \
        PR_ACTOR_TYPE=User bash "${DETECT_SCRIPT}"
    [ "$status" -eq 0 ]
    run jq -e '.skip == true and (.message | test("feedback"))' <<< "${output}"
    [ "$status" -eq 0 ]
}

@test "detect_pr_revise proceeds for repository_dispatch with client_payload feedback" {
    cat > "${BATS_TEST_TMPDIR}/event.json" << 'EOF'
{
  "client_payload": {
    "pr_number": "12",
    "feedback": "Revise error handling"
  },
  "sender": {
    "login": "maintainer",
    "type": "User",
    "author_association": "MEMBER"
  }
}
EOF
    run env PR_NUMBER=12 GITHUB_EVENT_NAME=repository_dispatch \
        GITHUB_EVENT_PATH="${BATS_TEST_TMPDIR}/event.json" \
        PR_ACTOR_TYPE=User bash "${DETECT_SCRIPT}"
    [ "$status" -eq 0 ]
    run jq -e '.skip == false and .result.comment_body == "Revise error handling"' <<< "${output}"
    [ "$status" -eq 0 ]
}

@test "detect_pr_revise skips repository_dispatch from external contributor" {
    cat > "${BATS_TEST_TMPDIR}/event.json" << 'EOF'
{
  "client_payload": {
    "pr_number": "12",
    "feedback": "Revise error handling"
  },
  "sender": {
    "login": "contributor",
    "type": "User",
    "author_association": "CONTRIBUTOR"
  }
}
EOF
    run env PR_NUMBER=12 GITHUB_EVENT_NAME=repository_dispatch \
        GITHUB_EVENT_PATH="${BATS_TEST_TMPDIR}/event.json" \
        PR_ACTOR_TYPE=User bash "${DETECT_SCRIPT}"
    [ "$status" -eq 0 ]
    run jq -e '.skip == true and (.message | test("maintainer association"))' <<< "${output}"
    [ "$status" -eq 0 ]
}

@test "detect_pr_revise emits comment_id and event_name from event" {
    cat > "${BATS_TEST_TMPDIR}/event.json" << 'EOF'
{
  "comment": {
    "id": 4242,
    "body": "@loop please fix",
    "user": {"login": "maintainer", "type": "User"},
    "author_association": "MEMBER"
  },
  "issue": {
    "number": 5,
    "pull_request": {}
  }
}
EOF
    run env GITHUB_EVENT_NAME=issue_comment \
        GITHUB_EVENT_PATH="${BATS_TEST_TMPDIR}/event.json" \
        PR_ACTOR_TYPE=User bash "${DETECT_SCRIPT}"
    [ "$status" -eq 0 ]
    run jq -e '.skip == false and .result.comment_id == "4242" and .result.event_name == "issue_comment"' <<< "${output}"
    [ "$status" -eq 0 ]
}

@test "detect_pr_revise emits comment_id for review comment event" {
    cat > "${BATS_TEST_TMPDIR}/event.json" << 'EOF'
{
  "comment": {
    "id": 9090,
    "body": "@loop apply this",
    "user": {"login": "maintainer", "type": "User"},
    "author_association": "OWNER"
  },
  "pull_request": {
    "number": 8
  }
}
EOF
    run env GITHUB_EVENT_NAME=pull_request_review_comment \
        GITHUB_EVENT_PATH="${BATS_TEST_TMPDIR}/event.json" \
        PR_ACTOR_TYPE=User bash "${DETECT_SCRIPT}"
    [ "$status" -eq 0 ]
    run jq -e '.skip == false and .result.comment_id == "9090" and .result.event_name == "pull_request_review_comment" and .result.pr_number == "8"' <<< "${output}"
    [ "$status" -eq 0 ]
}
