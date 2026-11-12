#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

DETECT_SCRIPT="$(apm_skill_script_path github-issue-autofix detect_autofix.sh)"

@test "detect_autofix skips when ISSUE_NUMBER empty" {
    run env -u ISSUE_NUMBER -u GITHUB_EVENT_PATH bash "${DETECT_SCRIPT}"
    [ "$status" -eq 0 ]
    run jq -e '.skip == true and .status == "ok"' <<< "${output}"
    [ "$status" -eq 0 ]
}

@test "detect_autofix skips when open PR already Fixes same issue" {
    MOCK_BIN="${BATS_TEST_TMPDIR}/bin"
    mkdir -p "${MOCK_BIN}"
    cat > "${MOCK_BIN}/gh" << 'EOF'
#!/bin/bash
if [[ "$1" == "api" ]]; then
    printf '%s\n' '{"state":"open"}'
    exit 0
fi
if [[ "$1" == "pr" && "$2" == "list" ]]; then
    printf '%s\n' '[{"number":7,"title":"fix crash","body":"Fixes #12","isDraft":true}]'
    exit 0
fi
printf 'unexpected gh: %s\n' "$*" >&2
exit 1
EOF
    chmod +x "${MOCK_BIN}/gh"
    PATH="${MOCK_BIN}:${PATH}"
    export PATH ISSUE_NUMBER=12 GITHUB_REPOSITORY=owner/repo GITHUB_TOKEN=unit-test-token
    run bash "${DETECT_SCRIPT}"
    [ "$status" -eq 0 ]
    run jq -e '.skip == true and .status == "ok"' <<< "${output}"
    [ "$status" -eq 0 ]
}

@test "detect_autofix errors when PR scan prerequisites are missing" {
    run env -u GITHUB_REPOSITORY -u GH_TOKEN -u GITHUB_TOKEN ISSUE_NUMBER=12 bash "${DETECT_SCRIPT}"
    [ "$status" -eq 1 ]
    run jq -e '.status == "error" and .skip == true' <<< "${output}"
    [ "$status" -eq 0 ]
}

@test "detect_autofix errors when gh pr list fails" {
    MOCK_BIN="${BATS_TEST_TMPDIR}/bin"
    mkdir -p "${MOCK_BIN}"
    cat > "${MOCK_BIN}/gh" << 'EOF'
#!/bin/bash
if [[ "$1" == "api" ]]; then
    printf '%s\n' '{"state":"open"}'
    exit 0
fi
if [[ "$1" == "pr" && "$2" == "list" ]]; then
    exit 1
fi
printf 'unexpected gh: %s\n' "$*" >&2
exit 1
EOF
    chmod +x "${MOCK_BIN}/gh"
    PATH="${MOCK_BIN}:${PATH}"
    export PATH ISSUE_NUMBER=12 GITHUB_REPOSITORY=owner/repo GITHUB_TOKEN=unit-test-token
    run bash "${DETECT_SCRIPT}"
    [ "$status" -eq 1 ]
    run jq -e '.status == "error" and .skip == true' <<< "${output}"
    [ "$status" -eq 0 ]
}

@test "detect_autofix errors when ISSUE_NUMBER is not numeric" {
    run env ISSUE_NUMBER='12abc' GITHUB_REPOSITORY=owner/repo GITHUB_TOKEN=unit-test-token bash "${DETECT_SCRIPT}"
    [ "$status" -eq 1 ]
    run jq -e '.status == "error" and .skip == true' <<< "${output}"
    [ "$status" -eq 0 ]
}

@test "detect_autofix proceeds when no matching Fixes PR" {
    MOCK_BIN="${BATS_TEST_TMPDIR}/bin"
    mkdir -p "${MOCK_BIN}"
    cat > "${MOCK_BIN}/gh" << 'EOF'
#!/bin/bash
if [[ "$1" == "api" ]]; then
    printf '%s\n' '{"state":"open"}'
    exit 0
fi
if [[ "$1" == "pr" && "$2" == "list" ]]; then
    printf '%s\n' '[]'
    exit 0
fi
printf 'unexpected gh: %s\n' "$*" >&2
exit 1
EOF
    chmod +x "${MOCK_BIN}/gh"
    PATH="${MOCK_BIN}:${PATH}"
    export PATH ISSUE_NUMBER=12 GITHUB_REPOSITORY=owner/repo GITHUB_TOKEN=unit-test-token
    run bash "${DETECT_SCRIPT}"
    [ "$status" -eq 0 ]
    run jq -e '.skip == false and .status == "ok" and .result.issue_number == "12"' <<< "${output}"
    [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# Scan mode (AUTOFIX_SCAN=true)
# ---------------------------------------------------------------------------

# Install a fixture-driven gh stub. Fixtures live in ${FIX}:
#   issues.json, open_prs.json, closed_prs.json, comments_<N>.json
# Every call is appended to ${FIX}/calls.log. Failure switches: touch ${FIX}/fail_<issues|open|closed|comments>.
setup_scan_stub() {
    FIX="${BATS_TEST_TMPDIR}/fix"
    MOCK_BIN="${BATS_TEST_TMPDIR}/bin"
    mkdir -p "${FIX}" "${MOCK_BIN}"
    [[ -f "${FIX}/issues.json" ]] || printf '[]' > "${FIX}/issues.json"
    [[ -f "${FIX}/open_prs.json" ]] || printf '[]' > "${FIX}/open_prs.json"
    [[ -f "${FIX}/closed_prs.json" ]] || printf '[]' > "${FIX}/closed_prs.json"
    cat > "${MOCK_BIN}/gh" << 'EOF'
#!/bin/bash
fix="${FIX:?}"
printf '%s\n' "$*" >> "${fix}/calls.log"
if [[ "$1" == "pr" && "$2" == "list" ]]; then
    if [[ "$*" == *"--state open"* ]]; then
        [[ -f "${fix}/fail_open" ]] && exit 1
        cat "${fix}/open_prs.json"
        exit 0
    fi
    if [[ "$*" == *"--state closed"* ]]; then
        [[ -f "${fix}/fail_closed" ]] && exit 1
        cat "${fix}/closed_prs.json"
        exit 0
    fi
fi
if [[ "$1" == "api" ]]; then
    for a in "$@"; do
        if [[ "$a" =~ /issues/([0-9]+)$ ]]; then
            [[ -f "${fix}/fail_issue_state" ]] && exit 1
            f="${fix}/issue_state_${BASH_REMATCH[1]}.json"
            if [[ -f "${f}" ]]; then cat "${f}"; else printf '{"state":"open"}'; fi
            exit 0
        fi
        if [[ "$a" =~ /issues/([0-9]+)/comments ]]; then
            [[ -f "${fix}/fail_comments" ]] && exit 1
            f="${fix}/comments_${BASH_REMATCH[1]}.json"
            if [[ -f "${f}" ]]; then cat "${f}"; else printf '[]'; fi
            exit 0
        fi
        if [[ "$a" == *"/issues?"* ]]; then
            [[ -f "${fix}/fail_issues" ]] && exit 1
            cat "${fix}/issues.json"
            exit 0
        fi
    done
fi
printf 'unexpected gh: %s\n' "$*" >&2
exit 1
EOF
    chmod +x "${MOCK_BIN}/gh"
    PATH="${MOCK_BIN}:${PATH}"
    export PATH FIX
    export AUTOFIX_SCAN=true AUTOFIX_SOURCE_LABEL=src:label AUTOFIX_SOURCE_MARKER='<!-- src:marker:' \
        AUTOFIX_PR_LABEL=pr-label AUTOFIX_BRANCH_PREFIX=bot/autofix/ \
        GITHUB_REPOSITORY=owner/repo GITHUB_TOKEN=unit-test-token
    unset AUTOFIX_MAX_OPEN_PRS ISSUE_NUMBER GITHUB_EVENT_PATH
}

# Build one Issue JSON element: mk_issue <number> [overrides-as-jq-object]
mk_issue() {
    local n="$1" extra="${2:-{\}}"
    jq -n -c --argjson n "${n}" --argjson extra "${extra}" '
        {number:$n, state:"open", labels:[{name:"src:label"}],
         user:{type:"Bot"}, body:("<!-- src:marker:abc --> body " + ($n|tostring))} + $extra'
}

# assert_proceed: the output is a proceed result for the Issue and carries the open-state gate fact.
assert_proceed() {
    assert_jq ".status == \"ok\" and .skip == false and .message == \"github-issue-autofix: proceed\" and .result.issue_number == \"$1\" and .result.gate.entity == {kind:\"issue\",number:$1,state:\"open\"}"
}

# Assert helper: fails the test when output is not the expected jq truth.
assert_jq() {
    local expr="$1"
    [[ -n ${output} ]] || {
        echo "empty output" >&2
        return 1
    }
    jq -e "${expr}" <<< "${output}" > /dev/null || {
        echo "jq assertion failed: ${expr}" >&2
        echo "${output}" >&2
        return 1
    }
}

@test "scan: lists qualifying Issues oldest first as result.items" {
    setup_scan_stub
    jq -s -c '.' <(mk_issue 5) <(mk_issue 9) > "${FIX}/issues.json"
    run bash "${DETECT_SCRIPT}"
    [ "$status" -eq 0 ]
    assert_jq '.status == "ok" and .skip == false and (.result.items | length) == 2'
    assert_jq '.result.items[0] == {key:"issue:5",entity:{kind:"issue",number:5},context:{issue_number:5}}'
    assert_jq '.result.items[1].key == "issue:9"'
}

@test "scan: excludes PRs, autofix label, missing label, User author, no marker, null body" {
    setup_scan_stub
    jq -s -c '.' \
        <(mk_issue 1 '{"pull_request":{"url":"x"}}') \
        <(mk_issue 2 '{"labels":[{"name":"src:label"},{"name":"autofix"}]}') \
        <(mk_issue 3 '{"labels":[{"name":"other"}]}') \
        <(mk_issue 4 '{"user":{"type":"User"}}') \
        <(mk_issue 5 '{"body":"no marker here"}') \
        <(mk_issue 6 '{"body":null}') \
        <(mk_issue 7 '{"user":null}') \
        <(mk_issue 8) > "${FIX}/issues.json"
    run bash "${DETECT_SCRIPT}"
    [ "$status" -eq 0 ]
    assert_jq '[.result.items[].key] == ["issue:8"]'
}

@test "scan: autofix label exclusion is case-insensitive" {
    setup_scan_stub
    jq -s -c '.' \
        <(mk_issue 1 '{"labels":[{"name":"src:label"},{"name":"AutoFix"}]}') \
        <(mk_issue 2) > "${FIX}/issues.json"
    run bash "${DETECT_SCRIPT}"
    [ "$status" -eq 0 ]
    assert_jq '[.result.items[].key] == ["issue:2"]'
}

@test "scan: source label match is case-insensitive" {
    setup_scan_stub
    jq -s -c '.' <(mk_issue 3 '{"labels":[{"name":"SRC:Label"}]}') > "${FIX}/issues.json"
    run bash "${DETECT_SCRIPT}"
    [ "$status" -eq 0 ]
    assert_jq '[.result.items[].key] == ["issue:3"]'
}

@test "scan: excludes Issue referenced by open PR and does not confuse #1 with #12" {
    setup_scan_stub
    jq -s -c '.' <(mk_issue 12) <(mk_issue 13) <(mk_issue 14) > "${FIX}/issues.json"
    printf '%s' '[{"number":1,"title":"t","body":"Fixes #1","headRefName":"x","labels":[]},{"number":2,"title":"Closes #13","body":null,"headRefName":"y","labels":[]}]' > "${FIX}/open_prs.json"
    run bash "${DETECT_SCRIPT}"
    [ "$status" -eq 0 ]
    assert_jq '[.result.items[].key] == ["issue:12","issue:14"]'
    [ "$(grep -c -- '--state open' "${FIX}/calls.log")" -eq 1 ]
}

@test "scan: closed autofix PR without human comment excludes Issue" {
    setup_scan_stub
    jq -s -c '.' <(mk_issue 20) > "${FIX}/issues.json"
    printf '%s' '[{"number":3,"body":"Fixes #20","closedAt":"2026-01-02T00:00:00Z","headRefName":"bot/autofix/b"}]' > "${FIX}/closed_prs.json"
    printf '%s' '[{"user":{"type":"Bot"},"created_at":"2026-01-01T00:00:00Z"}]' > "${FIX}/comments_20.json"
    run bash "${DETECT_SCRIPT}"
    [ "$status" -eq 0 ]
    assert_jq '.skip == true and .result == {}'
}

@test "scan: human comment newer than closedAt re-includes Issue" {
    setup_scan_stub
    jq -s -c '.' <(mk_issue 20) > "${FIX}/issues.json"
    printf '%s' '[{"number":3,"body":"Fixes #20","closedAt":"2026-01-02T00:00:00Z","headRefName":"bot/autofix/b"}]' > "${FIX}/closed_prs.json"
    printf '%s' '[{"user":{"type":"User"},"author_association":"MEMBER","created_at":"2026-01-03T00:00:00Z"}]' > "${FIX}/comments_20.json"
    run bash "${DETECT_SCRIPT}"
    [ "$status" -eq 0 ]
    assert_jq '[.result.items[].key] == ["issue:20"]'
}

@test "scan: newer comment from OWNER, MEMBER or COLLABORATOR re-includes Issue" {
    local assoc
    for assoc in OWNER MEMBER COLLABORATOR; do
        setup_scan_stub
        jq -s -c '.' <(mk_issue 20) > "${FIX}/issues.json"
        printf '%s' '[{"number":3,"body":"Fixes #20","closedAt":"2026-01-02T00:00:00Z","headRefName":"bot/autofix/b"}]' > "${FIX}/closed_prs.json"
        jq -n -c --arg a "${assoc}" '[{"user":{"type":"User"},"author_association":$a,"created_at":"2026-01-03T00:00:00Z"}]' > "${FIX}/comments_20.json"
        run bash "${DETECT_SCRIPT}"
        [ "$status" -eq 0 ]
        assert_jq '[.result.items[].key] == ["issue:20"]'
    done
}

@test "scan: newer comment from CONTRIBUTOR, NONE or missing author_association does not re-include Issue" {
    local assoc
    for assoc in CONTRIBUTOR NONE FIRST_TIME_CONTRIBUTOR MISSING; do
        setup_scan_stub
        jq -s -c '.' <(mk_issue 20) > "${FIX}/issues.json"
        printf '%s' '[{"number":3,"body":"Fixes #20","closedAt":"2026-01-02T00:00:00Z","headRefName":"bot/autofix/b"}]' > "${FIX}/closed_prs.json"
        if [[ ${assoc} == MISSING ]]; then
            printf '%s' '[{"user":{"type":"User"},"created_at":"2026-01-03T00:00:00Z"}]' > "${FIX}/comments_20.json"
        else
            jq -n -c --arg a "${assoc}" '[{"user":{"type":"User"},"author_association":$a,"created_at":"2026-01-03T00:00:00Z"}]' > "${FIX}/comments_20.json"
        fi
        run bash "${DETECT_SCRIPT}"
        [ "$status" -eq 0 ]
        assert_jq '.skip == true and .result == {}'
    done
}

@test "scan: human comment older than closedAt keeps Issue excluded" {
    setup_scan_stub
    jq -s -c '.' <(mk_issue 20) > "${FIX}/issues.json"
    printf '%s' '[{"number":3,"body":"Fixes #20","closedAt":"2026-01-02T00:00:00Z","headRefName":"bot/autofix/b"}]' > "${FIX}/closed_prs.json"
    printf '%s' '[{"user":{"type":"User"},"author_association":"MEMBER","created_at":"2026-01-01T00:00:00Z"}]' > "${FIX}/comments_20.json"
    run bash "${DETECT_SCRIPT}"
    [ "$status" -eq 0 ]
    assert_jq '.skip == true'
}

@test "scan: newer Bot comment does not re-include Issue" {
    setup_scan_stub
    jq -s -c '.' <(mk_issue 20) > "${FIX}/issues.json"
    printf '%s' '[{"number":3,"body":"Fixes #20","closedAt":"2026-01-02T00:00:00Z","headRefName":"bot/autofix/b"}]' > "${FIX}/closed_prs.json"
    printf '%s' '[{"user":{"type":"Bot"},"created_at":"2026-01-05T00:00:00Z"}]' > "${FIX}/comments_20.json"
    run bash "${DETECT_SCRIPT}"
    [ "$status" -eq 0 ]
    assert_jq '.skip == true'
}

@test "scan: uses the latest closedAt among multiple closed PRs" {
    setup_scan_stub
    jq -s -c '.' <(mk_issue 20) > "${FIX}/issues.json"
    printf '%s' '[{"number":3,"body":"Fixes #20","closedAt":"2026-01-02T00:00:00Z","headRefName":"bot/autofix/b"},{"number":4,"body":"Resolves #20","closedAt":"2026-01-10T00:00:00Z","headRefName":"bot/autofix/c"},{"number":5,"body":"Fixes #200","closedAt":"2026-02-01T00:00:00Z","headRefName":"bot/autofix/d"}]' > "${FIX}/closed_prs.json"
    # human comment is after the first closedAt but before the latest one -> still handled
    printf '%s' '[{"user":{"type":"User"},"author_association":"MEMBER","created_at":"2026-01-05T00:00:00Z"}]' > "${FIX}/comments_20.json"
    run bash "${DETECT_SCRIPT}"
    [ "$status" -eq 0 ]
    assert_jq '.skip == true'
}

@test "scan: comments API is only called for Issues referenced by a closed autofix PR" {
    setup_scan_stub
    jq -s -c '.' <(mk_issue 20) <(mk_issue 21) <(mk_issue 22) > "${FIX}/issues.json"
    printf '%s' '[{"number":3,"body":"Fixes #21","closedAt":"2026-01-02T00:00:00Z","headRefName":"bot/autofix/b"}]' > "${FIX}/closed_prs.json"
    run bash "${DETECT_SCRIPT}"
    [ "$status" -eq 0 ]
    assert_jq '[.result.items[].key] == ["issue:20","issue:22"]'
    [ "$(grep -c '/comments' "${FIX}/calls.log")" -eq 1 ]
    grep -q 'issues/21/comments' "${FIX}/calls.log"
    run ! grep -q 'issues/20/comments' "${FIX}/calls.log"
    run ! grep -q 'issues/22/comments' "${FIX}/calls.log"
    [ "$(grep -c -- '--state closed' "${FIX}/calls.log")" -eq 1 ]
}

@test "scan: caps at 50 items without truncating to 3" {
    setup_scan_stub
    jq -n -c '[range(1;61) as $n | {number:$n,state:"open",labels:[{name:"src:label"}],user:{type:"Bot"},body:"<!-- src:marker:x -->"}]' > "${FIX}/issues.json"
    run bash "${DETECT_SCRIPT}"
    [ "$status" -eq 0 ]
    assert_jq '(.result.items | length) == 50 and .result.items[0].key == "issue:1" and .result.items[49].key == "issue:50"'
}

@test "scan: skips with empty result when no candidates" {
    setup_scan_stub
    run bash "${DETECT_SCRIPT}"
    [ "$status" -eq 0 ]
    assert_jq '.status == "ok" and .skip == true and .result == {}'
}

@test "scan: skips when open autofix PRs reach AUTOFIX_MAX_OPEN_PRS" {
    setup_scan_stub
    jq -s -c '.' <(mk_issue 5) > "${FIX}/issues.json"
    printf '%s' '[{"number":1,"title":"a","body":"","headRefName":"bot/autofix/1","labels":[{"name":"pr-label"}]},{"number":2,"title":"b","body":"","headRefName":"bot/autofix/2","labels":[{"name":"pr-label"}]},{"number":3,"title":"c","body":"","headRefName":"feature/x","labels":[{"name":"pr-label"}]}]' > "${FIX}/open_prs.json"
    AUTOFIX_MAX_OPEN_PRS=2 run bash "${DETECT_SCRIPT}"
    [ "$status" -eq 0 ]
    assert_jq '.skip == true and .result == {}'
    AUTOFIX_MAX_OPEN_PRS=3 run bash "${DETECT_SCRIPT}"
    [ "$status" -eq 0 ]
    assert_jq '.skip == false and ([.result.items[].key] == ["issue:5"])'
}

@test "scan: AUTOFIX_MAX_OPEN_PRS with leading zeros is decimal" {
    setup_scan_stub
    jq -s -c '.' <(mk_issue 5) > "${FIX}/issues.json"
    jq -n -c '[range(1;9) as $n | {number:$n,title:"t",body:"",headRefName:("bot/autofix/"+($n|tostring)),labels:[{name:"pr-label"}]}]' > "${FIX}/open_prs.json"
    AUTOFIX_MAX_OPEN_PRS=08 run bash "${DETECT_SCRIPT}"
    [ "$status" -eq 0 ]
    assert_jq '.skip == true'
    AUTOFIX_MAX_OPEN_PRS=010 run bash "${DETECT_SCRIPT}"
    [ "$status" -eq 0 ]
    assert_jq '.skip == false and ([.result.items[].key] == ["issue:5"])'
}

@test "single-issue mode ignores AUTOFIX_MAX_OPEN_PRS and output is unchanged" {
    MOCK_BIN="${BATS_TEST_TMPDIR}/bin"
    mkdir -p "${MOCK_BIN}"
    cat > "${MOCK_BIN}/gh" << 'EOF'
#!/bin/bash
if [[ "$1" == "api" ]]; then
    printf '%s\n' '{"state":"open"}'
    exit 0
fi
if [[ "$1" == "pr" && "$2" == "list" ]]; then
    printf '%s\n' '[{"number":1,"title":"a","body":"","headRefName":"bot/autofix/1","labels":[{"name":"pr-label"}]}]'
    exit 0
fi
exit 1
EOF
    chmod +x "${MOCK_BIN}/gh"
    PATH="${MOCK_BIN}:${PATH}"
    export PATH ISSUE_NUMBER=12 GITHUB_REPOSITORY=owner/repo GITHUB_TOKEN=unit-test-token
    export AUTOFIX_MAX_OPEN_PRS=1 AUTOFIX_BRANCH_PREFIX=bot/autofix/ AUTOFIX_PR_LABEL=pr-label
    unset AUTOFIX_SCAN
    run bash "${DETECT_SCRIPT}"
    [ "$status" -eq 0 ]
    assert_proceed 12
}

@test "scan: missing required env yields status error and exit 1" {
    setup_scan_stub
    local var
    for var in AUTOFIX_SOURCE_LABEL AUTOFIX_SOURCE_MARKER AUTOFIX_PR_LABEL; do
        run env "${var}=" bash "${DETECT_SCRIPT}"
        [ "$status" -eq 1 ]
        assert_jq '.status == "error" and .skip == true'
    done
}

@test "scan: gh failures yield status error and exit 1" {
    local f
    for f in issues open closed comments; do
        rm -rf "${BATS_TEST_TMPDIR}/fix"
        setup_scan_stub
        jq -s -c '.' <(mk_issue 20) > "${FIX}/issues.json"
        printf '%s' '[{"number":3,"body":"Fixes #20","closedAt":"2026-01-02T00:00:00Z","headRefName":"bot/autofix/b"}]' > "${FIX}/closed_prs.json"
        : > "${FIX}/fail_${f}"
        run bash "${DETECT_SCRIPT}"
        [ "$status" -eq 1 ]
        assert_jq '.status == "error" and .skip == true'
    done
}

@test "scan: Issue text with shell and jq special characters does not break" {
    setup_scan_stub
    jq -n -c '[{number:7,state:"open",labels:[{name:"src:label"}],user:{type:"Bot"},
        title:"$(touch /tmp/pwned) `x` \"q\" \\ ; |",
        body:"<!-- src:marker:1 --> $(id) `id` \" ) | .[] \\ ${HOME} @sh"}]' > "${FIX}/issues.json"
    run bash "${DETECT_SCRIPT}"
    [ "$status" -eq 0 ]
    assert_jq '[.result.items[].key] == ["issue:7"]'
}

# ---------------------------------------------------------------------------
# AUTOFIX_ITEMS (single-Issue items output), PR list limits, jq error handling
# ---------------------------------------------------------------------------

@test "items: AUTOFIX_ITEMS with AUTOFIX_SCAN gives the scan output" {
    setup_scan_stub
    jq -s -c '.' <(mk_issue 5) > "${FIX}/issues.json"
    AUTOFIX_ITEMS=true run bash "${DETECT_SCRIPT}"
    [ "$status" -eq 0 ]
    assert_jq '.status == "ok" and .skip == false and ([.result.items[].key] == ["issue:5"])'
    assert_jq '.message | test("eligible")'
}

@test "items: AUTOFIX_ITEMS=true emits one item for a single Issue" {
    setup_scan_stub
    unset AUTOFIX_SCAN
    ISSUE_NUMBER=7 AUTOFIX_ITEMS=true run bash "${DETECT_SCRIPT}"
    [ "$status" -eq 0 ]
    assert_jq '.status == "ok" and .skip == false and (.message | length) > 0'
    assert_jq '.result == {items:[{key:"issue:7",entity:{kind:"issue",number:7},context:{issue_number:7},gate:{entity:{kind:"issue",number:7,state:"open"}}}]}'
}

@test "items: AUTOFIX_ITEMS=true skips with empty result when ISSUE_NUMBER is empty" {
    setup_scan_stub
    unset AUTOFIX_SCAN
    AUTOFIX_ITEMS=true run bash "${DETECT_SCRIPT}"
    [ "$status" -eq 0 ]
    assert_jq '.status == "ok" and .skip == true and .result == {}'
}

@test "items: AUTOFIX_ITEMS=true skips with empty result when an open PR fixes the Issue" {
    setup_scan_stub
    unset AUTOFIX_SCAN
    printf '%s' '[{"number":1,"title":"t","body":"Fixes #7","isDraft":false}]' > "${FIX}/open_prs.json"
    ISSUE_NUMBER=7 AUTOFIX_ITEMS=true run bash "${DETECT_SCRIPT}"
    [ "$status" -eq 0 ]
    assert_jq '.status == "ok" and .skip == true and .result == {}'
}

@test "items: output without AUTOFIX_ITEMS or with another value is unchanged" {
    setup_scan_stub
    unset AUTOFIX_SCAN
    ISSUE_NUMBER=7 run bash "${DETECT_SCRIPT}"
    [ "$status" -eq 0 ]
    assert_proceed 7
    ISSUE_NUMBER=7 AUTOFIX_ITEMS=false run bash "${DETECT_SCRIPT}"
    [ "$status" -eq 0 ]
    assert_proceed 7
}

@test "items: single-issue open PR list with broken JSON yields status error" {
    setup_scan_stub
    unset AUTOFIX_SCAN
    printf '%s' 'not json' > "${FIX}/open_prs.json"
    ISSUE_NUMBER=7 run bash "${DETECT_SCRIPT}"
    [ "$status" -eq 1 ]
    assert_jq '.status == "error" and .skip == true'
}

@test "single-issue: reports a closed Issue as a gate fact and leaves the decision to the gate" {
    setup_scan_stub
    unset AUTOFIX_SCAN
    printf '%s' '{"state":"closed"}' > "${FIX}/issue_state_7.json"
    ISSUE_NUMBER=7 run bash "${DETECT_SCRIPT}"
    [ "$status" -eq 0 ]
    assert_jq '.status == "ok" and .skip == false and .result.gate.entity == {kind:"issue",number:7,state:"closed"}'
}

@test "single-issue: closed Issue with AUTOFIX_ITEMS=true carries the closed state on the item" {
    setup_scan_stub
    unset AUTOFIX_SCAN
    printf '%s' '{"state":"closed"}' > "${FIX}/issue_state_7.json"
    ISSUE_NUMBER=7 AUTOFIX_ITEMS=true run bash "${DETECT_SCRIPT}"
    [ "$status" -eq 0 ]
    assert_jq '.skip == false and .result.items[0].gate.entity.state == "closed"'
}

@test "single-issue: fails closed when the Issue state cannot be read" {
    setup_scan_stub
    unset AUTOFIX_SCAN
    touch "${FIX}/fail_issue_state"
    ISSUE_NUMBER=7 run bash "${DETECT_SCRIPT}"
    [ "$status" -eq 1 ]
    assert_jq '.status == "error" and .skip == true'
}

@test "single-issue: fails closed when the Issue state is unreadable JSON" {
    setup_scan_stub
    unset AUTOFIX_SCAN
    printf '%s' 'not json' > "${FIX}/issue_state_7.json"
    ISSUE_NUMBER=7 run bash "${DETECT_SCRIPT}"
    [ "$status" -eq 1 ]
    assert_jq '.status == "error" and .skip == true'
}

@test "limit: AUTOFIX_PR_SCAN_LIMIT defaults to 1000 for open and closed fetches" {
    setup_scan_stub
    jq -s -c '.' <(mk_issue 20) > "${FIX}/issues.json"
    run bash "${DETECT_SCRIPT}"
    [ "$status" -eq 0 ]
    assert_jq '.skip == false'
    [ "$(grep -c -- '--state open.*--limit 1000' "${FIX}/calls.log")" -eq 1 ]
    [ "$(grep -c -- '--state closed.*--limit 1000' "${FIX}/calls.log")" -eq 1 ]
}

@test "limit: single-issue mode passes --limit 1000 by default and honors AUTOFIX_PR_SCAN_LIMIT" {
    setup_scan_stub
    unset AUTOFIX_SCAN
    ISSUE_NUMBER=7 run bash "${DETECT_SCRIPT}"
    [ "$status" -eq 0 ]
    assert_proceed 7
    grep -q -- '--state open.*--limit 1000' "${FIX}/calls.log"
    rm -f "${FIX}/calls.log"
    ISSUE_NUMBER=7 AUTOFIX_PR_SCAN_LIMIT=5 run bash "${DETECT_SCRIPT}"
    [ "$status" -eq 0 ]
    grep -q -- '--state open.*--limit 5' "${FIX}/calls.log"
}

@test "limit: single-issue mode fails closed when the open PR list reaches the limit" {
    setup_scan_stub
    unset AUTOFIX_SCAN
    jq -n -c '[range(0;3) as $n | {number:$n,title:"t",body:"",isDraft:false}]' > "${FIX}/open_prs.json"
    ISSUE_NUMBER=7 AUTOFIX_PR_SCAN_LIMIT=3 run bash "${DETECT_SCRIPT}"
    [ "$status" -eq 1 ]
    assert_jq '.status == "error" and .skip == true and (.message | test("AUTOFIX_PR_SCAN_LIMIT"))'
}

@test "limit: single-issue mode below the limit is unchanged" {
    setup_scan_stub
    unset AUTOFIX_SCAN
    jq -n -c '[range(0;2) as $n | {number:$n,title:"t",body:"",isDraft:false}]' > "${FIX}/open_prs.json"
    ISSUE_NUMBER=7 AUTOFIX_PR_SCAN_LIMIT=3 run bash "${DETECT_SCRIPT}"
    [ "$status" -eq 0 ]
    assert_proceed 7
}

@test "limit: single-issue mode rejects an invalid AUTOFIX_PR_SCAN_LIMIT" {
    setup_scan_stub
    unset AUTOFIX_SCAN
    local v
    for v in 0 abc -1; do
        ISSUE_NUMBER=7 AUTOFIX_PR_SCAN_LIMIT="${v}" run bash "${DETECT_SCRIPT}"
        [ "$status" -eq 1 ]
        assert_jq '.status == "error" and .skip == true and (.message | test("AUTOFIX_PR_SCAN_LIMIT"))'
    done
}

@test "limit: closed PR list reaching the limit fails closed" {
    setup_scan_stub
    jq -s -c '.' <(mk_issue 20) > "${FIX}/issues.json"
    jq -n -c '[range(0;3) as $n | {number:$n,title:"t",body:"",closedAt:"2026-01-01T00:00:00Z",headRefName:"bot/autofix/x"}]' > "${FIX}/closed_prs.json"
    AUTOFIX_PR_SCAN_LIMIT=3 run bash "${DETECT_SCRIPT}"
    [ "$status" -eq 1 ]
    assert_jq '.status == "error" and .skip == true'
    grep -q -- '--state closed.*--limit 3' "${FIX}/calls.log"
}

@test "limit: invalid AUTOFIX_PR_SCAN_LIMIT yields status error" {
    setup_scan_stub
    local v
    for v in 0 abc -1 1.5 "1 2"; do
        AUTOFIX_PR_SCAN_LIMIT="${v}" run bash "${DETECT_SCRIPT}"
        [ "$status" -eq 1 ]
        assert_jq '.status == "error" and .skip == true and (.message | test("AUTOFIX_PR_SCAN_LIMIT"))'
    done
}

@test "limit: leading zeros are decimal" {
    setup_scan_stub
    jq -s -c '.' <(mk_issue 20) > "${FIX}/issues.json"
    jq -n -c '[range(0;10) as $n | {number:$n,title:"t",body:"",closedAt:"2026-01-01T00:00:00Z",headRefName:"bot/autofix/x"}]' > "${FIX}/closed_prs.json"
    AUTOFIX_PR_SCAN_LIMIT=010 run bash "${DETECT_SCRIPT}"
    [ "$status" -eq 1 ]
    assert_jq '.status == "error"'
    jq -n -c '[range(0;9) as $n | {number:$n,title:"t",body:"",closedAt:"2026-01-01T00:00:00Z",headRefName:"bot/autofix/x"}]' > "${FIX}/closed_prs.json"
    AUTOFIX_PR_SCAN_LIMIT=010 run bash "${DETECT_SCRIPT}"
    [ "$status" -eq 0 ]
    assert_jq '.status == "ok" and ([.result.items[].key] == ["issue:20"])'
}

@test "limit: open PR list reaching the limit fails closed" {
    setup_scan_stub
    jq -s -c '.' <(mk_issue 20) > "${FIX}/issues.json"
    jq -n -c '[range(0;3) as $n | {number:$n,title:"t",body:"",headRefName:"x",labels:[]}]' > "${FIX}/open_prs.json"
    AUTOFIX_PR_SCAN_LIMIT=3 run bash "${DETECT_SCRIPT}"
    [ "$status" -eq 1 ]
    assert_jq '.status == "error" and .skip == true'
    grep -q -- '--state open.*--limit 3' "${FIX}/calls.log"
}

@test "limit: lists below the limit work normally" {
    setup_scan_stub
    jq -s -c '.' <(mk_issue 20) > "${FIX}/issues.json"
    jq -n -c '[range(0;2) as $n | {number:$n,title:"t",body:"",headRefName:"x",labels:[]}]' > "${FIX}/open_prs.json"
    jq -n -c '[range(0;2) as $n | {number:$n,title:"t",body:"",closedAt:"2026-01-01T00:00:00Z",headRefName:"bot/autofix/x"}]' > "${FIX}/closed_prs.json"
    AUTOFIX_PR_SCAN_LIMIT=3 run bash "${DETECT_SCRIPT}"
    [ "$status" -eq 0 ]
    assert_jq '.status == "ok" and .skip == false and ([.result.items[].key] == ["issue:20"])'
}

@test "prefix: closed PRs outside AUTOFIX_BRANCH_PREFIX are ignored for matching" {
    setup_scan_stub
    jq -s -c '.' <(mk_issue 20) <(mk_issue 21) > "${FIX}/issues.json"
    printf '%s' '[{"number":3,"body":"Fixes #20","closedAt":"2026-01-02T00:00:00Z","headRefName":"other/loop/3"},{"number":4,"body":"Fixes #21","closedAt":"2026-01-02T00:00:00Z","headRefName":"bot/autofix/4"}]' > "${FIX}/closed_prs.json"
    run bash "${DETECT_SCRIPT}"
    [ "$status" -eq 0 ]
    assert_jq '[.result.items[].key] == ["issue:20"]'
}

@test "prefix: empty AUTOFIX_BRANCH_PREFIX skips the closed PR prefix filter" {
    setup_scan_stub
    jq -s -c '.' <(mk_issue 20) > "${FIX}/issues.json"
    printf '%s' '[{"number":3,"body":"Fixes #20","closedAt":"2026-01-02T00:00:00Z","headRefName":"other/loop/3"}]' > "${FIX}/closed_prs.json"
    AUTOFIX_BRANCH_PREFIX='' run bash "${DETECT_SCRIPT}"
    [ "$status" -eq 0 ]
    assert_jq '.skip == true and .result == {}'
}

@test "jq errors: broken comments JSON yields status error" {
    setup_scan_stub
    jq -s -c '.' <(mk_issue 20) > "${FIX}/issues.json"
    printf '%s' '[{"number":3,"body":"Fixes #20","closedAt":"2026-01-02T00:00:00Z","headRefName":"bot/autofix/3"}]' > "${FIX}/closed_prs.json"
    printf '%s' '{{ not json' > "${FIX}/comments_20.json"
    run bash "${DETECT_SCRIPT}"
    [ "$status" -eq 1 ]
    assert_jq '.status == "error" and .skip == true'
}

@test "jq errors: broken open PR JSON yields status error in scan mode" {
    setup_scan_stub
    jq -s -c '.' <(mk_issue 20) > "${FIX}/issues.json"
    printf '%s' '{{ not json' > "${FIX}/open_prs.json"
    run bash "${DETECT_SCRIPT}"
    [ "$status" -eq 1 ]
    assert_jq '.status == "error" and .skip == true'
}

@test "jq errors: open PR with non-string title yields status error in scan mode" {
    setup_scan_stub
    jq -s -c '.' <(mk_issue 20) > "${FIX}/issues.json"
    printf '%s' '[{"number":1,"title":5,"body":"x","headRefName":"x","labels":[]}]' > "${FIX}/open_prs.json"
    run bash "${DETECT_SCRIPT}"
    [ "$status" -eq 1 ]
    assert_jq '.status == "error" and .skip == true'
}
