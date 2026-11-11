#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154
bats_require_minimum_version 1.5.0

# Tests for scripts/self/loop/list_triage_issues.sh
#
# Use cases:
# - an open code-review Issue created by a Bot, with the fingerprint marker, is selected
# - Issues with a triage:* label, pull requests, User-authored Issues, Issues without the
#   fingerprint marker and Issues with a null body are left out
# - an Issue whose triage comment is not followed by a newer human comment stays out; a newer
#   human comment brings it back, while Bot comments and older human comments do not
# - three error or rejected run-log rows inside the window leave an Issue out; two rows, rows older
#   than the window and skipped rows do not
# - exclusions are applied before the limit, and Issues are ordered by oldest last attempt first
# - a missing run-log, non-JSON lines and rows without target_key do not stop the run
# - nothing selected writes issues=[] and a notice; a failing gh api exits 1
# - the scan is capped at TRIAGE_SCAN_LIMIT and the comments API is called at most once per Issue
# - every selected Issue passes detect_issue.sh on a schedule event; excluded triage:* Issues skip

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

setup() {
    ROOT="$(bats_workspace_root)"
    SCRIPT="${ROOT}/scripts/self/loop/list_triage_issues.sh"
    DETECT="${ROOT}/.agents/skills/github-issue-triage/scripts/detect_issue.sh"
    FIX="${BATS_TEST_TMPDIR}/fix"
    BIN="${BATS_TEST_TMPDIR}/bin"
    GH_LOG="${BATS_TEST_TMPDIR}/gh.log"
    OUT="${BATS_TEST_TMPDIR}/github_output"
    RUN_LOG="${BATS_TEST_TMPDIR}/run-log.md"
    mkdir -p "${FIX}/comments" "${BIN}"
    : > "${GH_LOG}"
    : > "${OUT}"
    printf '[]' > "${FIX}/issues.json"
    printf '# Loop Run Log\n\n## Recent Runs\n' > "${RUN_LOG}"
    # gh stub: serves fixtures for the issues list and per-issue comments, logs every call
    cat > "${BIN}/gh" << 'STUB'
#!/bin/bash
printf '%s\n' "$*" >> "${GH_LOG}"
for arg in "$@"; do
    case "${arg}" in
        repos/*/issues\?*)
            [[ -f ${FIX}/issues_fail ]] && exit 1
            cat "${FIX}/issues.json"
            exit 0
            ;;
        repos/*/issues/*/comments*)
            n="${arg#repos/*/issues/}"
            n="${n%%/comments*}"
            if [[ -f ${FIX}/comments/${n}.json ]]; then cat "${FIX}/comments/${n}.json"; else printf '[]'; fi
            exit 0
            ;;
    esac
done
exit 1
STUB
    chmod +x "${BIN}/gh"
    export GH_LOG FIX
    MARKER='<!-- github-issue-triage:v1 -->'
    NOW="2026-11-11T12:00:00Z"
}

# issue NUM [LABELS_CSV] [USER_TYPE] [BODY_JSON]: one Issue object as the REST API returns it
issue() {
    local labels="${2:-}" utype="${3:-Bot}" body="${4:-\"found <!-- code-review:fp:0123456789abcdef -->\"}"
    jq -nc --argjson n "$1" --arg l "${labels}" --arg u "${utype}" --argjson b "${body}" \
        '{number: $n, title: ("t" + ($n | tostring)), body: $b, user: {type: $u},
          labels: ([{name: "loop:code-review"}] + ($l | split(",") | map(select(length > 0) | {name: .})))}'
}

# set_issues OBJ...: write the issues fixture as one array
set_issues() {
    printf '%s\n' "$@" | jq -sc '.' > "${FIX}/issues.json"
}

# set_comments NUM OBJ...: write the comments fixture of one Issue
set_comments() {
    local n="$1"
    shift
    printf '%s\n' "$@" | jq -sc '.' > "${FIX}/comments/${n}.json"
}

# comment CREATED_AT USER_TYPE [BODY]: one comment object
comment() {
    jq -nc --arg t "$1" --arg u "$2" --arg b "${3:-hello}" '{created_at: $t, user: {type: $u}, body: $b}'
}

# log_row RUN_ID OUTCOME NUM: append one run-log row for the triage loop
log_row() {
    jq -nc --arg r "$1" --arg o "$2" --arg k "entity:issue:$3" \
        '{run_id: $r, loop_name: "github-issue-triage", outcome: $o, target_key: $k}' >> "${RUN_LOG}"
}

# run_list: run the script with the stubbed gh
run_list() {
    run --separate-stderr env PATH="${BIN}:${PATH}" GITHUB_REPOSITORY="o/r" GH_TOKEN="x" \
        RUN_LOG_FILE="${RUN_LOG}" GITHUB_OUTPUT="${OUT}" TRIAGE_NOW="${NOW}" "$@" bash "${SCRIPT}"
}

# selected: print the selected issue numbers on one line
selected() {
    if ! grep -q '^issues=' "${OUT}"; then
        printf 'NO_ISSUES_LINE'
        return 1
    fi
    grep '^issues=' "${OUT}" | cut -d= -f2- | jq -r 'map(tostring) | join(",")'
}

# ok_count N: assert a successful run that wrote count=N
ok_count() {
    [ "$status" -eq 0 ]
    grep -qx "count=$1" "${OUT}"
}

@test "calls the comments api at most once per issue" {
    set_issues "$(issue 1)" "$(issue 2)"
    set_comments 1 "$(comment 2026-11-01T00:00:00Z Bot "${MARKER}")"
    run_list
    [ "$status" -eq 0 ]
    [ "$(grep -c 'issues/1/comments' "${GH_LOG}")" -eq 1 ]
    [ "$(grep -c 'issues/2/comments' "${GH_LOG}")" -eq 1 ]
}

@test "caps the issues read at TRIAGE_SCAN_LIMIT" {
    local i objs=()
    for i in $(seq 1 250); do objs+=("$(issue "${i}")"); done
    set_issues "${objs[@]}"
    run_list TRIAGE_LIST_LIMIT=1000
    [ "$status" -eq 0 ]
    grep -qx 'count=200' "${OUT}"
    [ "$(selected | tr ',' '\n' | tail -1)" = "200" ]
}

@test "continues when the run-log has non-JSON lines and rows without target_key" {
    set_issues "$(issue 1)"
    printf 'not json\n{broken\n{"run_id":"2026-11-10T00:00:00Z","loop_name":"github-issue-triage","outcome":"error"}\n' >> "${RUN_LOG}"
    run_list
    [ "$status" -eq 0 ]
    ok_count 1
    [ "$(selected)" = "1" ]
}

@test "continues when the run-log is missing" {
    set_issues "$(issue 1)"
    rm -f "${RUN_LOG}"
    run_list
    [ "$status" -eq 0 ]
    ok_count 1
    [ "$(selected)" = "1" ]
}

@test "detect does not skip any issue the lister selects on a schedule event" {
    set_issues "$(issue 5)" "$(issue 6)"
    run_list
    [ "$status" -eq 0 ]
    local n
    for n in $(selected | tr ',' ' '); do
        run env ISSUE_NUMBER="${n}" ISSUE_TITLE="t" ISSUE_BODY="b" ISSUE_LABELS_JSON='["loop:code-review"]' \
            ISSUE_EVENT_NAME=schedule ISSUE_ACTOR_TYPE=User bash "${DETECT}"
        [ "$status" -eq 0 ]
        [ "$(jq -r '.skip' <<< "${output}")" = "false" ]
    done
}

@test "detect skips the triage-labelled issues the lister excludes" {
    local l
    set_issues "$(issue 1 triage:ready)" "$(issue 2 triage:needs-info)" "$(issue 3 triage:failed)"
    run_list
    [ "$status" -eq 0 ]
    ok_count 0
    [ "$(selected)" = "" ]
    for l in triage:ready triage:needs-info triage:failed; do
        run env ISSUE_NUMBER=9 ISSUE_TITLE="t" ISSUE_BODY="b" ISSUE_LABELS_JSON="[\"loop:code-review\",\"${l}\"]" \
            ISSUE_EVENT_NAME=schedule ISSUE_ACTOR_TYPE=User bash "${DETECT}"
        [ "$status" -eq 0 ]
        [ "$(jq -r '.skip' <<< "${output}")" = "true" ]
    done
}

@test "does not count skipped rows as failures" {
    set_issues "$(issue 1)"
    local d
    for d in 08 09 10; do log_row "2026-11-${d}T00:00:00Z" skipped 1; done
    run_list
    ok_count 1
    [ "$(selected)" = "1" ]
}

@test "does not count failures older than the window" {
    set_issues "$(issue 1)"
    local d
    for d in 01 02 03; do log_row "2026-11-${d}T00:00:00Z" error 1; done
    run_list
    ok_count 1
    [ "$(selected)" = "1" ]
}

@test "drops a handled issue when only a Bot commented after the marker" {
    set_issues "$(issue 1)"
    set_comments 1 "$(comment 2026-11-01T00:00:00Z Bot "${MARKER}")" "$(comment 2026-11-02T00:00:00Z Bot)"
    run_list
    ok_count 0
    [ "$(selected)" = "" ]
}

@test "drops a handled issue when only older human comments exist" {
    set_issues "$(issue 1)"
    set_comments 1 "$(comment 2026-10-30T00:00:00Z User)" "$(comment 2026-11-01T00:00:00Z Bot "${MARKER}")"
    run_list
    ok_count 0
    [ "$(selected)" = "" ]
}

@test "drops a handled issue when there is no newer human comment" {
    set_issues "$(issue 1)"
    set_comments 1 "$(comment 2026-11-01T00:00:00Z Bot "${MARKER}")"
    run_list
    ok_count 0
    [ "$(selected)" = "" ]
}

@test "drops issues authored by a User, without the marker, or with a null body" {
    set_issues "$(issue 1 '' User)" "$(issue 2 '' Bot '"no marker here"')" "$(issue 3 '' Bot null)"
    run_list
    [ "$status" -eq 0 ]
    ok_count 0
    [ "$(selected)" = "" ]
}

@test "drops issues carrying a triage label" {
    set_issues "$(issue 1 triage:ready)" "$(issue 2 triage:needs-info)" "$(issue 3 triage:failed)" "$(issue 4)"
    run_list
    ok_count 1
    [ "$(selected)" = "4" ]
}

@test "drops issues with three recent error or rejected rows" {
    set_issues "$(issue 1)"
    log_row 2026-11-08T00:00:00Z error 1
    log_row 2026-11-09T00:00:00Z rejected 1
    log_row 2026-11-10T00:00:00Z error 1
    run_list
    ok_count 0
    [ "$(selected)" = "" ]
}

@test "keeps running when a label name has a double quote and a backslash" {
    set_issues "$(issue 1 'we"ird\\label')" "$(issue 2)"
    run_list
    ok_count 2
    [ "$(selected)" = "1,2" ]
}

@test "drops pull requests" {
    set_issues "$(issue 1 | jq -c '. + {pull_request: {url: "x"}}')" "$(issue 2)"
    run_list
    ok_count 1
    [ "$(selected)" = "2" ]
}

@test "exits 0 with a notice and empty output when nothing matches" {
    run_list
    [ "$status" -eq 0 ]
    [[ "$output" == *"::notice"* ]]
    grep -qx 'issues=\[\]' "${OUT}"
    grep -qx 'count=0' "${OUT}"
}

@test "exits 1 when gh api fails" {
    touch "${FIX}/issues_fail"
    run_list
    [ "$status" -eq 1 ]
    ! grep -q '^issues=' "${OUT}"
}

@test "keeps an issue with two recent failures" {
    set_issues "$(issue 1)"
    log_row 2026-11-08T00:00:00Z error 1
    log_row 2026-11-09T00:00:00Z rejected 1
    run_list
    ok_count 1
    [ "$(selected)" = "1" ]
}

@test "keeps an issue with a human comment newer than the marker" {
    set_issues "$(issue 1)"
    set_comments 1 "$(comment 2026-11-01T00:00:00Z Bot "${MARKER}")" "$(comment 2026-11-02T00:00:00Z User)"
    run_list
    ok_count 1
    [ "$(selected)" = "1" ]
}

@test "orders by oldest last attempt with unrecorded issues first" {
    set_issues "$(issue 1)" "$(issue 2)" "$(issue 3)" "$(issue 4)"
    log_row 2026-11-10T00:00:00Z error 1
    log_row 2026-11-05T00:00:00Z error 2
    log_row 2026-11-06T00:00:00Z skipped 4
    log_row 2026-11-07T00:00:00Z approved 4
    run_list TRIAGE_LIST_LIMIT=10
    ok_count 4
    [ "$(selected)" = "3,2,4,1" ]
}

@test "selects a matching issue and writes issues and count" {
    set_issues "$(issue 7)"
    run_list
    [ "$status" -eq 0 ]
    [ "$(selected)" = "7" ]
    grep -qx 'count=1' "${OUT}"
}

@test "selects up to the limit after exclusions" {
    set_issues "$(issue 1 triage:ready)" "$(issue 2 '' User)" "$(issue 3)" "$(issue 4)" "$(issue 5)" "$(issue 6)"
    run_list
    [ "$(selected)" = "3,4,5" ]
    grep -qx 'count=3' "${OUT}"
}
