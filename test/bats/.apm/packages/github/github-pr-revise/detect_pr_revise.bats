#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154

# Tests for .apm/packages/github/.apm/skills/github-pr-revise/scripts/detect_pr_revise.sh
#
# Use cases:
# - Skip bots, missing mention, empty body, and untrusted association
# - Proceed for mention-gated comment and trusted dispatch feedback
# - Hydrate inline review path/line/side/diff_hunk/comment_id into result
# - Keep path/line empty for issue_comment (compat)
# - Emit result.comments array (trigger fallback and PR_COMMENTS_JSON gather)
# - Skip when gathered comments array is empty
# - Gather via mocked gh filters eyes/bot/mention and batches review+issue comments

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

DETECT_SCRIPT="$(apm_skill_script_path github-pr-revise detect_pr_revise.sh)"

@test "detect_pr_revise keeps path and line empty for issue_comment events" {
    cat > "${BATS_TEST_TMPDIR}/event.json" << 'EOF'
{
  "action": "created",
  "issue": {
    "number": 42,
    "pull_request": {
      "url": "https://api.github.com/repos/o/r/pulls/42"
    }
  },
  "comment": {
    "id": 9001,
    "body": "@loop please rename the helper",
    "user": {
      "login": "maintainer",
      "type": "User"
    },
    "author_association": "MEMBER"
  }
}
EOF
    run env GITHUB_EVENT_NAME=issue_comment \
        GITHUB_EVENT_PATH="${BATS_TEST_TMPDIR}/event.json" \
        bash "${DETECT_SCRIPT}"
    [ "$status" -eq 0 ]
    run jq -e '
        .skip == false
        and .result.pr_number == "42"
        and .result.comment_id == 9001
        and .result.path == ""
        and .result.line == ""
        and .result.side == ""
        and .result.diff_hunk == ""
        and (.result.comment_body | test("@loop"))
    ' <<< "${output}"
    [ "$status" -eq 0 ]
}

@test "detect_pr_revise proceeds with inline fields from pull_request_review_comment" {
    cat > "${BATS_TEST_TMPDIR}/event.json" << 'EOF'
{
  "action": "created",
  "pull_request": {
    "number": 77
  },
  "comment": {
    "id": 555001,
    "body": "@loop fix the null check here",
    "path": "pkg/foo/bar.go",
    "line": 42,
    "original_line": 40,
    "side": "RIGHT",
    "diff_hunk": "@@ -40,3 +40,5 @@\n func Example() {\n-        return nil\n+        if x == nil {\n+                return err\n+        }",
    "user": {
      "login": "maintainer",
      "type": "User"
    },
    "author_association": "MEMBER"
  }
}
EOF
    run env GITHUB_EVENT_NAME=pull_request_review_comment \
        GITHUB_EVENT_PATH="${BATS_TEST_TMPDIR}/event.json" \
        bash "${DETECT_SCRIPT}"
    [ "$status" -eq 0 ]
    run jq -e '
        .skip == false
        and .result.pr_number == "77"
        and .result.comment_id == 555001
        and .result.path == "pkg/foo/bar.go"
        and .result.line == 42
        and .result.side == "RIGHT"
        and (.result.diff_hunk | test("func Example"))
        and (.result.comment_body | test("@loop"))
    ' <<< "${output}"
    [ "$status" -eq 0 ]
}

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
    run jq -e '
        .skip == false
        and .result.pr_number == "5"
        and (.result.comments | length) == 1
        and (.result.comments[0].body | test("@loop"))
    ' <<< "${output}"
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
    run env GITHUB_EVENT_NAME=issue_comment GITHUB_EVENT_PATH="${BATS_TEST_TMPDIR}/event.json" PR_ACTOR_TYPE=User bash "${DETECT_SCRIPT}"
    [ "$status" -eq 0 ]
    run jq -e '.skip == false and .result.comment_id == 4242 and .result.event_name == "issue_comment"' <<< "${output}"
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
    run env GITHUB_EVENT_NAME=pull_request_review_comment GITHUB_EVENT_PATH="${BATS_TEST_TMPDIR}/event.json" PR_ACTOR_TYPE=User bash "${DETECT_SCRIPT}"
    [ "$status" -eq 0 ]
    run jq -e '.skip == false and .result.comment_id == 9090 and .result.event_name == "pull_request_review_comment" and .result.pr_number == "8"' <<< "${output}"
    [ "$status" -eq 0 ]
}

@test "detect_pr_revise emits comments from PR_COMMENTS_JSON override" {
    comments='[{"comment_id":1,"body":"@loop one","path":"a.go","line":10,"side":"RIGHT","diff_hunk":"@@","in_reply_to_id":null,"source":"pull_request_review_comment","actor":"maintainer"},{"comment_id":2,"body":"@loop two","path":"","line":null,"side":"","diff_hunk":"","in_reply_to_id":null,"source":"issue_comment","actor":"maintainer"}]'
    run env PR_NUMBER=5 PR_MENTION='@loop' PR_COMMENT_BODY='@loop one' \
        PR_ACTOR_TYPE=User PR_COMMENTS_JSON="${comments}" bash "${DETECT_SCRIPT}"
    [ "$status" -eq 0 ]
    run jq -e '
        .skip == false
        and (.result.comments | length) == 2
        and .result.comments[0].comment_id == 1
        and .result.comments[1].comment_id == 2
        and (.verifier_context | test("PR Revise Comments"))
    ' <<< "${output}"
    [ "$status" -eq 0 ]
}

@test "detect_pr_revise skips when gathered comments array is empty" {
    run env PR_NUMBER=5 PR_MENTION='@loop' PR_COMMENT_BODY='@loop please fix' \
        PR_ACTOR_TYPE=User PR_COMMENTS_JSON='[]' bash "${DETECT_SCRIPT}"
    [ "$status" -eq 0 ]
    run jq -e '
        .skip == true
        and .status == "ok"
        and (.message | test("no open"))
    ' <<< "${output}"
    [ "$status" -eq 0 ]
}

@test "detect_pr_revise gathers open comments via mocked gh api" {
    MOCK_BIN="${BATS_TEST_TMPDIR}/bin"
    mkdir -p "${MOCK_BIN}"
    cat > "${MOCK_BIN}/gh" << 'EOF'
#!/bin/bash
if [[ "$1" == "api" && "$*" == *"issues/77/comments"* ]]; then
    printf '%s\n' '[{"id":101,"body":"@loop convo","user":{"login":"maintainer","type":"User"},"author_association":"MEMBER","reactions":{"eyes":0}}]'
    exit 0
fi
if [[ "$1" == "api" && "$*" == *"pulls/77/comments"* ]]; then
    printf '%s\n' '[{"id":202,"body":"@loop inline","path":"pkg/foo.go","line":9,"start_line":7,"subject_type":"line","side":"RIGHT","diff_hunk":"@@ -1 +1 @@","in_reply_to_id":null,"user":{"login":"maintainer","type":"User"},"author_association":"OWNER","reactions":{"eyes":0}},{"id":203,"body":"@loop claimed","path":"pkg/bar.go","line":3,"side":"RIGHT","user":{"login":"maintainer","type":"User"},"author_association":"OWNER","reactions":{"eyes":1}},{"id":204,"body":"no mention","path":"pkg/baz.go","line":1,"side":"RIGHT","user":{"login":"maintainer","type":"User"},"author_association":"OWNER","reactions":{"eyes":0}}]'
    exit 0
fi
printf 'unexpected gh: %s\n' "$*" >&2
exit 1
EOF
    chmod +x "${MOCK_BIN}/gh"
    PATH="${MOCK_BIN}:${PATH}"
    export PATH
    run env PR_NUMBER=77 PR_MENTION='@loop' PR_COMMENT_BODY='@loop inline' \
        PR_ACTOR_TYPE=User GITHUB_EVENT_NAME=pull_request_review_comment \
        GITHUB_REPOSITORY=owner/repo GITHUB_TOKEN=token \
        bash "${DETECT_SCRIPT}"
    [ "$status" -eq 0 ]
    run jq -e '
        .skip == false
        and ([.result.comments[].comment_id] | sort) == [101,202]
        and (.result.comments | map(select(.comment_id == 202)) | .[0].path) == "pkg/foo.go"
        and (.result.comments | map(select(.comment_id == 202)) | .[0].start_line) == 7
        and (.result.comments | map(select(.comment_id == 202)) | .[0].subject_type) == "line"
        and (.result.comments | map(select(.comment_id == 101)) | .[0].source) == "issue_comment"
    ' <<< "${output}"
    [ "$status" -eq 0 ]
}

@test "detect_pr_revise hydrates in_reply_to_id from review comment event" {
    cat > "${BATS_TEST_TMPDIR}/event.json" << 'EOF'
{
  "action": "created",
  "pull_request": { "number": 11 },
  "comment": {
    "id": 700,
    "body": "@loop follow up",
    "path": "x.go",
    "line": 5,
    "side": "RIGHT",
    "diff_hunk": "@@",
    "in_reply_to_id": 699,
    "user": { "login": "maintainer", "type": "User" },
    "author_association": "MEMBER"
  }
}
EOF
    run env GITHUB_EVENT_NAME=pull_request_review_comment \
        GITHUB_EVENT_PATH="${BATS_TEST_TMPDIR}/event.json" \
        bash "${DETECT_SCRIPT}"
    [ "$status" -eq 0 ]
    run jq -e '
        .skip == false
        and .result.in_reply_to_id == 699
        and .result.comments[0].in_reply_to_id == 699
    ' <<< "${output}"
    [ "$status" -eq 0 ]
}

@test "detect_pr_revise hydrates start_line and subject_type from review comment event" {
    cat > "${BATS_TEST_TMPDIR}/event.json" << 'EOF'
{
  "action": "created",
  "pull_request": { "number": 11 },
  "comment": {
    "id": 800,
    "body": "@loop fix this range",
    "path": "x.go",
    "line": 12,
    "start_line": 8,
    "side": "RIGHT",
    "subject_type": "line",
    "diff_hunk": "@@",
    "user": { "login": "maintainer", "type": "User" },
    "author_association": "MEMBER"
  }
}
EOF
    run env GITHUB_EVENT_NAME=pull_request_review_comment \
        GITHUB_EVENT_PATH="${BATS_TEST_TMPDIR}/event.json" \
        bash "${DETECT_SCRIPT}"
    [ "$status" -eq 0 ]
    run jq -e '
        .skip == false
        and .result.start_line == 8
        and .result.subject_type == "line"
        and .result.comments[0].start_line == 8
        and .result.comments[0].subject_type == "line"
    ' <<< "${output}"
    [ "$status" -eq 0 ]
}

@test "detect_pr_revise hydrates file-level subject_type without line" {
    cat > "${BATS_TEST_TMPDIR}/event.json" << 'EOF'
{
  "action": "created",
  "pull_request": { "number": 11 },
  "comment": {
    "id": 801,
    "body": "@loop rename this file",
    "path": "x.go",
    "subject_type": "file",
    "user": { "login": "maintainer", "type": "User" },
    "author_association": "MEMBER"
  }
}
EOF
    run env GITHUB_EVENT_NAME=pull_request_review_comment \
        GITHUB_EVENT_PATH="${BATS_TEST_TMPDIR}/event.json" \
        bash "${DETECT_SCRIPT}"
    [ "$status" -eq 0 ]
    run jq -e '
        .skip == false
        and .result.subject_type == "file"
        and .result.path == "x.go"
        and .result.comments[0].subject_type == "file"
    ' <<< "${output}"
    [ "$status" -eq 0 ]
}
