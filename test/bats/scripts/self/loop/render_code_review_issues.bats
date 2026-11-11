#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154
bats_require_minimum_version 1.5.0

# Tests for scripts/self/loop/render_code_review_issues.sh
#
# Use cases:
# - a verdict other than APPROVE exits 0 and writes nothing (so rejected is recorded)
# - a missing agent branch on origin exits 0 and writes nothing
# - APPROVE fails closed on a missing or unreachable from.since / from.ref
# - APPROVE fails closed on a findings.json that is not an array or has a malformed finding
# - findings whose evidence lines overlap the changed lines of since..ref are kept; others are dropped
# - dropped findings are counted with their reason in the step summary
# - every finding dropped writes an empty array
# - a range with only deleted lines in the file drops the finding without failing
# - the kept finding body carries the evidence path and lines, and over-long titles or bodies are dropped

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

setup() {
    SCRIPT="$(bats_workspace_root)/scripts/self/loop/render_code_review_issues.sh"
    REMOTE="${BATS_TEST_TMPDIR}/remote.git"
    WORK="${BATS_TEST_TMPDIR}/work"
    MSG="${BATS_TEST_TMPDIR}/msg"
    SUMMARY="${BATS_TEST_TMPDIR}/summary.md"
    BRANCH="agent/code-review-1"
    : > "${SUMMARY}"
    mkdir -p "${MSG}"
    git init -q --bare "${REMOTE}"
    git init -q -b main "${WORK}"
    git -C "${WORK}" config user.email "test@example.com"
    git -C "${WORK}" config user.name "Test User"
    git -C "${WORK}" remote add origin "${REMOTE}"
    mkdir -p "${WORK}/src"
    seq 1 30 > "${WORK}/src/a.sh"
    seq 1 5 > "${WORK}/src/b.sh"
    git -C "${WORK}" add -A
    git -C "${WORK}" commit -q -m base
    SINCE="$(git -C "${WORK}" rev-parse HEAD)"
    # change src/a.sh lines 10-12 only
    sed -i '10,12s/$/ changed/' "${WORK}/src/a.sh"
    git -C "${WORK}" commit -q -am change
    REF="$(git -C "${WORK}" rev-parse HEAD)"
    git -C "${WORK}" push -q origin main
    TARGET_JSON="$(jq -nc --arg s "${SINCE}" --arg r "${REF}" \
        '{mode: "integration", key: "integration:main", from: {branch: "main", ref: $r, since: $s}, to: {branch: "main"}}')"
}

# push_report JSON: commit findings.json on the agent branch, push it, return to main
push_report() {
    git -C "${WORK}" checkout -q -b "${BRANCH}"
    mkdir -p "${WORK}/.loop-code-review"
    printf '%s' "$1" > "${WORK}/.loop-code-review/findings.json"
    git -C "${WORK}" add -A
    git -C "${WORK}" commit -q -m report
    git -C "${WORK}" push -q origin "${BRANCH}"
    git -C "${WORK}" checkout -q main
}

# finding TITLE PATH START END: one finding JSON object
finding() {
    jq -nc --arg t "$1" --arg p "$2" --argjson s "$3" --argjson e "$4" \
        '{title: $t, body: ("body of " + $t), fingerprint: ("fp-" + $t), evidence: {path: $p, start_line: $s, end_line: $e}}'
}

# run_render [VERDICT] [TARGET_JSON]: run the script in the work clone
run_render() {
    run --separate-stderr env -C "${WORK}" \
        VERDICT="${1-APPROVE}" EXECUTE_BRANCH="${BRANCH}" TARGET_JSON="${2-${TARGET_JSON}}" \
        LOOP_MESSAGE_DIR="${MSG}" GITHUB_STEP_SUMMARY="${SUMMARY}" \
        bash "${SCRIPT}"
}

@test "exits 0 and writes nothing when the agent branch does not exist on origin" {
    run_render
    [ "$status" -eq 0 ]
    [ ! -e "${MSG}/issues.json" ]
}

@test "exits 0 and writes nothing when VERDICT is REJECT" {
    push_report "[$(finding a src/a.sh 11 11)]"
    run_render REJECT
    [ "$status" -eq 0 ]
    [ ! -e "${MSG}/issues.json" ]
    run_render ""
    [ "$status" -eq 0 ]
    [ ! -e "${MSG}/issues.json" ]
}

@test "fails when findings.json has a malformed finding" {
    local bad
    for bad in '[{"title":"t"}]' '[{"title":"t","body":"b","fingerprint":"f","evidence":{"path":"src/a.sh","start_line":0,"end_line":1}}]' \
        '[{"title":"t","body":"b","fingerprint":"f","evidence":{"path":"../x","start_line":1,"end_line":1}}]' \
        '[{"title":"t","body":"b","fingerprint":"f","evidence":{"path":"src/a.sh","start_line":5,"end_line":2}}]'; do
        git -C "${WORK}" push -q origin --delete "${BRANCH}" 2> /dev/null || true
        git -C "${WORK}" branch -q -D "${BRANCH}" 2> /dev/null || true
        push_report "${bad}"
        run_render
        [ "$status" -eq 1 ]
        [ ! -e "${MSG}/issues.json" ]
    done
}

@test "fails when findings.json is not an array" {
    push_report '{"title":"t"}'
    run_render
    [ "$status" -eq 1 ]
    [ ! -e "${MSG}/issues.json" ]
}

@test "fails when from.since or from.ref is missing or unreachable" {
    local target
    push_report "[$(finding a src/a.sh 11 11)]"
    for target in \
        '{"key":"integration:main","from":{"ref":"'"${REF}"'"}}' \
        '{"key":"integration:main","from":{"since":"'"${SINCE}"'"}}' \
        '{"key":"integration:main","from":{"since":"deadbeefdeadbeefdeadbeefdeadbeefdeadbeef","ref":"'"${REF}"'"}}' \
        '{"key":"integration:main","from":{"since":"'"${SINCE}"'","ref":"deadbeefdeadbeefdeadbeefdeadbeefdeadbeef"}}' \
        '' 'not json'; do
        run_render APPROVE "${target}"
        [ "$status" -eq 1 ]
        [ ! -e "${MSG}/issues.json" ]
    done
}

@test "keeps findings whose evidence overlaps changed lines and drops others" {
    push_report "[$(finding keep src/a.sh 11 11),$(finding partial src/a.sh 12 15),$(finding far src/a.sh 40 41),$(finding other src/b.sh 1 1)]"
    run_render
    [ "$status" -eq 0 ]
    [ "$(jq -r 'length' "${MSG}/issues.json")" -eq 2 ]
    [ "$(jq -r '[.[].title] | join(",")' "${MSG}/issues.json")" = "keep,partial" ]
    [ "$(jq -r '.[0].fingerprint' "${MSG}/issues.json")" = "fp-keep" ]
    [ "$(jq -r '.[0].body' "${MSG}/issues.json" | grep -c 'src/a.sh')" -ge 1 ]
    grep -q 'dropped 2' "${SUMMARY}"
    grep -q 'far' "${SUMMARY}"
    grep -q 'other' "${SUMMARY}"
}

@test "drops a finding whose title or body is over the limit" {
    local long_title long_body
    long_title="$(printf 'x%.0s' $(seq 1 257))"
    long_body="$(printf 'y%.0s' $(seq 1 60001))"
    push_report "$(jq -nc --arg t "${long_title}" --arg b "${long_body}" '[
        {title: $t, body: "b", fingerprint: "f1", evidence: {path: "src/a.sh", start_line: 11, end_line: 11}},
        {title: "ok", body: $b, fingerprint: "f2", evidence: {path: "src/a.sh", start_line: 11, end_line: 11}},
        {title: "fine", body: "b", fingerprint: "f3", evidence: {path: "src/a.sh", start_line: 11, end_line: 11}}]')"
    run_render
    [ "$status" -eq 0 ]
    [ "$(jq -r '[.[].title] | join(",")' "${MSG}/issues.json")" = "fine" ]
}

@test "writes an empty array when every finding is dropped" {
    push_report "[$(finding far src/a.sh 40 41)]"
    run_render
    [ "$status" -eq 0 ]
    [ "$(cat "${MSG}/issues.json")" = "[]" ]
}

@test "drops a finding on a file whose range only deletes lines without failing" {
    local ref2
    sed -i '20,22d' "${WORK}/src/a.sh"
    git -C "${WORK}" commit -q -am delete
    ref2="$(git -C "${WORK}" rev-parse HEAD)"
    git -C "${WORK}" push -q origin main
    push_report "[$(finding gone src/a.sh 20 20)]"
    run_render APPROVE "$(jq -nc --arg s "$(git -C "${WORK}" rev-parse HEAD~1)" --arg r "${ref2}" '{from: {since: $s, ref: $r}}')"
    [ "$status" -eq 0 ]
    [ "$(cat "${MSG}/issues.json")" = "[]" ]
}
