#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154

# Tests for .apm/packages/common/.apm/skills/issue-triage/scripts/detect_issue.sh

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

DETECT_SCRIPT="$(apm_skill_script_path issue-triage detect_issue.sh)"

@test "skips when actor_type is Bot" {
    run env ISSUE_NUMBER=1 ISSUE_TITLE=t ISSUE_BODY=b ISSUE_LABELS_JSON='[]' \
        ISSUE_EVENT_NAME=issues ISSUE_EVENT_ACTION=opened \
        ISSUE_ACTOR=dependabot ISSUE_ACTOR_TYPE=Bot \
        bash "${DETECT_SCRIPT}"
    [ "$status" -eq 0 ]
    run jq -e '.skip == true and .status == "ok"' <<< "${output}"
    [ "$status" -eq 0 ]
}

@test "emits facts for human opened issue" {
    run env ISSUE_NUMBER=42 ISSUE_TITLE='Crash on save' ISSUE_BODY='steps' \
        ISSUE_LABELS_JSON='[]' ISSUE_EVENT_NAME=issues ISSUE_EVENT_ACTION=opened \
        ISSUE_ACTOR=alice ISSUE_ACTOR_TYPE=User \
        bash "${DETECT_SCRIPT}"
    [ "$status" -eq 0 ]
    run jq -e '.skip == false and .result.issue_number == 42' <<< "${output}"
    [ "$status" -eq 0 ]
}

@test "emits handoff_key entity:issue:N for human opened issue" {
    run env ISSUE_NUMBER=42 ISSUE_TITLE='Crash on save' ISSUE_BODY='steps' \
        ISSUE_LABELS_JSON='[]' ISSUE_EVENT_NAME=issues ISSUE_EVENT_ACTION=opened \
        ISSUE_ACTOR=alice ISSUE_ACTOR_TYPE=User \
        bash "${DETECT_SCRIPT}"
    [ "$status" -eq 0 ]
    run jq -e '.skip == false and .result.handoff_key == "entity:issue:42"' <<< "${output}"
    [ "$status" -eq 0 ]
}

@test "skips when triage:failed label present" {
    run env ISSUE_NUMBER=1 ISSUE_TITLE=t ISSUE_BODY=b \
        ISSUE_LABELS_JSON='["needs-triage","triage:failed"]' \
        ISSUE_EVENT_NAME=issues ISSUE_EVENT_ACTION=opened \
        ISSUE_ACTOR=alice ISSUE_ACTOR_TYPE=User \
        bash "${DETECT_SCRIPT}"
    [ "$status" -eq 0 ]
    run jq -e '.skip == true' <<< "${output}"
    [ "$status" -eq 0 ]
}

@test "skips issue_comment from Bot" {
    run env ISSUE_NUMBER=1 ISSUE_TITLE=t ISSUE_BODY=b ISSUE_LABELS_JSON='["triage:needs-info"]' \
        ISSUE_EVENT_NAME=issue_comment ISSUE_EVENT_ACTION=created \
        ISSUE_COMMENT_ID=9 ISSUE_ACTOR=bot ISSUE_ACTOR_TYPE=User \
        ISSUE_COMMENT_USER_TYPE=Bot \
        bash "${DETECT_SCRIPT}"
    [ "$status" -eq 0 ]
    run jq -e '.skip == true' <<< "${output}"
    [ "$status" -eq 0 ]
}

@test "hydrates ISSUE_* from GITHUB_EVENT_PATH when ISSUE_NUMBER unset" {
    cat > "${BATS_TEST_TMPDIR}/event.json" << 'EOF'
{
  "action": "opened",
  "issue": {"number": 9, "title": "T", "body": "B", "labels": [{"name": "bug"}]},
  "sender": {"login": "alice", "type": "User"}
}
EOF
    run env -u ISSUE_NUMBER GITHUB_EVENT_PATH="${BATS_TEST_TMPDIR}/event.json" \
        GITHUB_EVENT_NAME=issues \
        bash "${DETECT_SCRIPT}"
    [ "$status" -eq 0 ]
    run jq -e '.skip == false and .result.handoff_key == "entity:issue:9" and .result.issue_number == 9' <<< "${output}"
    [ "$status" -eq 0 ]
}

@test "hydrates issue facts from gh api on workflow_dispatch with ISSUE_NUMBER only" {
    MOCK_BIN="${BATS_TEST_TMPDIR}/bin"
    mkdir -p "${MOCK_BIN}"
    cat > "${MOCK_BIN}/gh" << 'EOF'
#!/bin/bash
if [[ "$1" == "api" ]]; then
    printf '%s\n' '{"title":"From API","body":"body text","labels":[{"name":"bug"}]}'
    exit 0
fi
printf 'unexpected gh: %s\n' "$*" >&2
exit 1
EOF
    chmod +x "${MOCK_BIN}/gh"
    PATH="${MOCK_BIN}:${PATH}"
    export PATH ISSUE_NUMBER=55 GITHUB_EVENT_NAME=workflow_dispatch GITHUB_REPOSITORY=owner/repo GITHUB_TOKEN=unit-test-token
    run bash "${DETECT_SCRIPT}"
    [ "$status" -eq 0 ]
    run jq -e '.skip == false and .result.issue_number == 55 and .result.title == "From API" and .result.body == "body text" and .result.labels == ["bug"]' <<< "${output}"
    [ "$status" -eq 0 ]
}

@test "omits dispatch flags on labeled(autofix) because autofix workflow handles intake" {
    run env ISSUE_NUMBER=12 ISSUE_TITLE=t ISSUE_BODY=b \
        ISSUE_LABELS_JSON='["triage:ready","autofix"]' \
        ISSUE_EVENT_NAME=issues ISSUE_EVENT_ACTION=labeled ISSUE_LABEL_NAME=autofix \
        ISSUE_ACTOR=alice ISSUE_ACTOR_TYPE=User \
        bash "${DETECT_SCRIPT}"
    [ "$status" -eq 0 ]
    run jq -e '(.result.dispatch_requested // false) != true' <<< "${output}"
    [ "$status" -eq 0 ]
}

@test "emits dispatch flags when triage:ready labeled with autofix already present" {
    run env ISSUE_NUMBER=12 ISSUE_TITLE=t ISSUE_BODY=b \
        ISSUE_LABELS_JSON='["triage:ready","autofix"]' \
        ISSUE_EVENT_NAME=issues ISSUE_EVENT_ACTION=labeled ISSUE_LABEL_NAME=triage:ready \
        ISSUE_ACTOR=alice ISSUE_ACTOR_TYPE=User \
        bash "${DETECT_SCRIPT}"
    [ "$status" -eq 0 ]
    run jq -e '
        .result.dispatch_requested == true
        and .result.dispatch_event_type == "loop-issue-autofix"
        and .result.dispatch_client_payload.issue_number == "12"
    ' <<< "${output}"
    [ "$status" -eq 0 ]
}

@test "rejects ISSUE_NUMBER zero with structured error" {
    run env ISSUE_NUMBER=0 ISSUE_TITLE=t ISSUE_BODY=b ISSUE_LABELS_JSON='[]' \
        ISSUE_EVENT_NAME=issues ISSUE_EVENT_ACTION=opened \
        ISSUE_ACTOR=alice ISSUE_ACTOR_TYPE=User \
        bash "${DETECT_SCRIPT}"
    [ "$status" -eq 1 ]
    run jq -e '.status == "error" and .skip == true' <<< "${output}"
    [ "$status" -eq 0 ]
}

@test "omits dispatch flags when triage:ready and autofix on issue_comment" {
    run env ISSUE_NUMBER=12 ISSUE_TITLE=t ISSUE_BODY=b \
        ISSUE_LABELS_JSON='["triage:ready","autofix"]' \
        ISSUE_EVENT_NAME=issue_comment ISSUE_EVENT_ACTION=created \
        ISSUE_COMMENT_ID=1 ISSUE_ACTOR=alice ISSUE_ACTOR_TYPE=User \
        bash "${DETECT_SCRIPT}"
    [ "$status" -eq 0 ]
    run jq -e '
        .skip == true
        and (.result.dispatch_requested // false) != true
    ' <<< "${output}"
    [ "$status" -eq 0 ]
}

@test "omits dispatch flags for Bot actor with triage:ready and autofix" {
    run env ISSUE_NUMBER=12 ISSUE_TITLE=t ISSUE_BODY=b \
        ISSUE_LABELS_JSON='["triage:ready","autofix"]' \
        ISSUE_EVENT_NAME=issues ISSUE_EVENT_ACTION=labeled ISSUE_LABEL_NAME=autofix \
        ISSUE_ACTOR=dependabot ISSUE_ACTOR_TYPE=Bot \
        bash "${DETECT_SCRIPT}"
    [ "$status" -eq 0 ]
    run jq -e '
        .skip == true
        and (.result.dispatch_requested // false) != true
    ' <<< "${output}"
    [ "$status" -eq 0 ]
}

@test "skips human issue_comment when triage:ready without needs-info" {
    run env ISSUE_NUMBER=1 ISSUE_TITLE=t ISSUE_BODY=b \
        ISSUE_LABELS_JSON='["triage:ready","bug"]' \
        ISSUE_EVENT_NAME=issue_comment ISSUE_EVENT_ACTION=created \
        ISSUE_COMMENT_ID=9 ISSUE_ACTOR=alice ISSUE_ACTOR_TYPE=User \
        bash "${DETECT_SCRIPT}"
    [ "$status" -eq 0 ]
    run jq -e '.skip == true' <<< "${output}"
    [ "$status" -eq 0 ]
}

@test "does not skip human issue_comment while triage:needs-info" {
    run env ISSUE_NUMBER=1 ISSUE_TITLE=t ISSUE_BODY=b \
        ISSUE_LABELS_JSON='["triage:needs-info"]' \
        ISSUE_EVENT_NAME=issue_comment ISSUE_EVENT_ACTION=created \
        ISSUE_COMMENT_ID=9 ISSUE_ACTOR=alice ISSUE_ACTOR_TYPE=User \
        bash "${DETECT_SCRIPT}"
    [ "$status" -eq 0 ]
    run jq -e '.skip == false' <<< "${output}"
    [ "$status" -eq 0 ]
}

@test "omits dispatch flags when triage:ready without autofix" {
    run env ISSUE_NUMBER=12 ISSUE_TITLE=t ISSUE_BODY=b \
        ISSUE_LABELS_JSON='["triage:ready"]' \
        ISSUE_EVENT_NAME=issues ISSUE_EVENT_ACTION=labeled \
        ISSUE_ACTOR=alice ISSUE_ACTOR_TYPE=User \
        bash "${DETECT_SCRIPT}"
    [ "$status" -eq 0 ]
    run jq -e '(.result.dispatch_requested // false) != true' <<< "${output}"
    [ "$status" -eq 0 ]
}

@test "omits dispatch flags when triage:failed present with triage:ready and autofix" {
    run env ISSUE_NUMBER=12 ISSUE_TITLE=t ISSUE_BODY=b \
        ISSUE_LABELS_JSON='["triage:ready","autofix","triage:failed"]' \
        ISSUE_EVENT_NAME=issues ISSUE_EVENT_ACTION=labeled \
        ISSUE_ACTOR=alice ISSUE_ACTOR_TYPE=User \
        bash "${DETECT_SCRIPT}"
    [ "$status" -eq 0 ]
    run jq -e '
        .skip == true
        and (.result.dispatch_requested // false) != true
    ' <<< "${output}"
    [ "$status" -eq 0 ]
}

@test "rejects invalid GITHUB_EVENT_PATH JSON with structured error" {
    printf 'not-json' > "${BATS_TEST_TMPDIR}/bad-event.json"
    run env -u ISSUE_NUMBER GITHUB_EVENT_PATH="${BATS_TEST_TMPDIR}/bad-event.json" GITHUB_EVENT_NAME=issues bash "${DETECT_SCRIPT}"
    [ "$status" -eq 1 ]
    run jq -e '.status == "error" and .skip == true' <<< "${output}"
    [ "$status" -eq 0 ]
}
