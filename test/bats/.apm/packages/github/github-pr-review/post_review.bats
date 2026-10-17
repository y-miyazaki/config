#!/usr/bin/env bats
# shellcheck disable=SC2016,SC2030,SC2031,SC2034,SC2154

# Tests for .apm/packages/github/.apm/skills/github-pr-review/scripts/post_review.sh
#
# Use cases:
# - does nothing unless VERDICT is APPROVE
# - reads the report from the work branch (git fetch + git show) or REPORT_FILE
# - keeps rule/criteria findings only when the quote is an exact substring of a base file
# - keeps bug findings that carry a location; drops malformed findings and escaping paths
# - checks diff membership per side and hunk (start_line in the same hunk)
# - moves in_diff findings outside the diff (or without a diff) into the body
# - posts a COMMENT review with marker, counts, premises, and numbered inline comments
# - links evidence to the base SHA and locations to the head SHA
# - reports the dropped findings count
# - fails closed (no post, exit 0) on unparseable input; posting failure warns and exits 0
# - retries once without inline comments when the first post is rejected
# - never sends an event other than COMMENT

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

POST_SCRIPT="$(apm_skill_script_path github-pr-review post_review.sh)"
MARKER='<!-- github-pr-review:v1 -->'
BASE_SHA="$(printf 'b%.0s' {1..40})"
HEAD_SHA="$(printf 'a%.0s' {1..40})"
RULE_QUOTE='Never fabricate APIs, commands, paths, or behavior.'

setup() {
    BASE_DIR="${BATS_TEST_TMPDIR}/base"
    mkdir -p "${BASE_DIR}/docs"
    printf '# Rules\n\n- %s\n- Stay within requested scope.\n' "${RULE_QUOTE}" > "${BASE_DIR}/AGENTS.md"
    printf 'CRIT-01 (MUST): Quote exactly\n' > "${BASE_DIR}/docs/criteria.md"

    DIFF_FILE="${BATS_TEST_TMPDIR}/pr.diff"
    cat > "${DIFF_FILE}" << 'DIFF'
diff --git a/a.sh b/a.sh
index 1111111..2222222 100644
--- a/a.sh
+++ b/a.sh
@@ -1,3 +1,4 @@
 line1
+added
 line2
 line3
@@ -20,2 +21,3 @@ function f {
 ctx
--- removed looks like a header
+new1
+new2
diff --git a/gone.sh b/gone.sh
deleted file mode 100644
index 3333333..0000000
--- a/gone.sh
+++ /dev/null
@@ -1,2 +0,0 @@
-old1
-old2
DIFF

    BIN_DIR="${BATS_TEST_TMPDIR}/bin"
    mkdir -p "${BIN_DIR}"
    cat > "${BIN_DIR}/gh" << 'STUB'
#!/bin/bash
echo "$*" >> "${GH_LOG}"
if [[ $1 == "api" && " $* " == *" --method POST "* ]]; then
    prev=""
    for arg in "$@"; do
        if [[ ${prev} == "--input" ]]; then
            n=$(find "${GH_CAPTURE_DIR}" -name 'post-*.json' | wc -l)
            cp "${arg}" "${GH_CAPTURE_DIR}/post-$((n + 1)).json"
        fi
        prev="${arg}"
    done
    if [[ -n ${GH_POST_FAIL_FIRST:-} && ! -f ${GH_CAPTURE_DIR}/.failed ]]; then
        touch "${GH_CAPTURE_DIR}/.failed"
        exit 1
    fi
    if [[ -n ${GH_POST_FAIL:-} ]]; then exit 1; fi
    echo '{}'
    exit 0
fi
exit 1
STUB
    chmod +x "${BIN_DIR}/gh"
    GH_LOG="${BATS_TEST_TMPDIR}/gh.log"
    GH_CAPTURE_DIR="${BATS_TEST_TMPDIR}/capture"
    mkdir -p "${GH_CAPTURE_DIR}"
    : > "${GH_LOG}"
    REPORT="${BATS_TEST_TMPDIR}/report.json"

    # shellcheck disable=SC1090
    source "${POST_SCRIPT}"
    BASE_TREE_DIR="${BASE_DIR}"
    PR_DIFF_FILE="${DIFF_FILE}"
    GITHUB_REPOSITORY=o/r
}

teardown() {
    rm -rf "${BASE_DIR}" "${BIN_DIR}" "${GH_CAPTURE_DIR}" "${DIFF_FILE}" "${GH_LOG}" "${REPORT}"
}

# rule_finding: Print a rule finding JSON; $1 severity, $2 quote, $3 location line, $4 in_diff
rule_finding() {
    jq -cn --arg s "$1" --arg q "$2" --argjson l "$3" --argjson d "$4" \
        '{id: 1, severity: $s, title: "Rule broken", evidence: {kind: "rule", path: "AGENTS.md", quote: $q},
          location: {path: "a.sh", line: $l, side: "RIGHT", in_diff: $d}, impact: "Bad things"}'
}

# bug_finding: Print a bug finding JSON; $1 severity, $2 location line, $3 in_diff
bug_finding() {
    jq -cn --arg s "$1" --argjson l "$2" --argjson d "$3" \
        '{id: 2, severity: $s, title: "Bug here", evidence: {kind: "bug", quote: "empty input crashes"},
          location: {path: "a.sh", line: $l, side: "RIGHT", in_diff: $d}, impact: "Crash on empty input"}'
}

# write_report: Write REPORT with the given findings JSON array
write_report() {
    jq -n --arg h "${HEAD_SHA}" --arg b "${BASE_SHA}" --argjson f "$1" \
        '{pr_number: 7, head_sha: $h, base_sha: $b, response_language: "en",
          premises: {pr_body: "checked", linked: ["#120"]}, summary: "Adds a thing.", findings: $f}' > "${REPORT}"
}

# run_post: Run post_review.sh in a clean env; extra args are env assignments
run_post() {
    run env -i PATH="${BIN_DIR}:${PATH}" HOME="${HOME}" GH_TOKEN=x GITHUB_REPOSITORY=o/r \
        GH_LOG="${GH_LOG}" GH_CAPTURE_DIR="${GH_CAPTURE_DIR}" \
        VERDICT=APPROVE EXECUTE_BRANCH=loop/x TARGET_JSON='{"entity":{"handoff_key":"entity:pr:7"}}' \
        REPORT_FILE="${REPORT}" PR_DIFF_FILE="${DIFF_FILE}" BASE_TREE_DIR="${BASE_DIR}" \
        "$@" bash "${POST_SCRIPT}"
}

# posted: Print the last posted JSON payload
posted() {
    cat "$(find "${GH_CAPTURE_DIR}" -name 'post-*.json' | sort | tail -n 1)"
}

@test "diff_contains_line checks side and hunk ranges" {
    run diff_contains_line a.sh 2 RIGHT
    [ "$status" -eq 0 ]
    run diff_contains_line a.sh 23 RIGHT
    [ "$status" -eq 0 ]
    run diff_contains_line a.sh 10 RIGHT
    [ "$status" -eq 1 ]
    run diff_contains_line a.sh 21 LEFT
    [ "$status" -eq 0 ]
    run diff_contains_line a.sh 22 LEFT
    [ "$status" -eq 1 ]
    run diff_contains_line gone.sh 2 LEFT
    [ "$status" -eq 0 ]
    run diff_contains_line gone.sh 1 RIGHT
    [ "$status" -eq 1 ]
    run diff_contains_line other.sh 1 RIGHT
    [ "$status" -eq 1 ]
}

@test "diff_contains_line requires start_line in the same hunk" {
    run diff_contains_line a.sh 4 RIGHT 2
    [ "$status" -eq 0 ]
    run diff_contains_line a.sh 22 RIGHT 3
    [ "$status" -eq 1 ]
}

@test "does nothing unless VERDICT is APPROVE" {
    write_report '[]'
    run_post VERDICT=REJECT
    [ "$status" -eq 0 ]
    [ ! -s "${GH_LOG}" ]
}

@test "drops a criteria finding whose file does not exist on base" {
    run validate_finding '{"severity":"Warning","title":"t","impact":"i","evidence":{"kind":"criteria","path":"docs/missing.md","quote":"CRIT-01"},"location":{"path":"a.sh","line":2,"side":"RIGHT","in_diff":true}}'
    [ "$status" -eq 1 ]
    run validate_finding '{"severity":"Warning","title":"t","impact":"i","evidence":{"kind":"criteria","path":"docs/criteria.md","quote":"CRIT-01 (MUST)"},"location":{"path":"a.sh","line":2,"side":"RIGHT","in_diff":true}}'
    [ "$status" -eq 0 ]
}

@test "drops a rule finding whose quote differs only by whitespace" {
    run validate_finding "$(rule_finding Warning "${RULE_QUOTE} " 2 true)"
    [ "$status" -eq 1 ]
    run validate_finding "$(rule_finding Warning "${RULE_QUOTE}"$'\n  - Stay within' 2 true)"
    [ "$status" -eq 1 ]
}

@test "drops evidence paths that escape the base tree" {
    printf '%s\n' "${RULE_QUOTE}" > "${BATS_TEST_TMPDIR}/outside.md"
    ln -s "${BATS_TEST_TMPDIR}/outside.md" "${BASE_DIR}/link.md"
    run validate_finding "$(rule_finding Warning "${RULE_QUOTE}" 2 true | jq -c '.evidence.path = "../outside.md"')"
    [ "$status" -eq 1 ]
    run validate_finding "$(rule_finding Warning "${RULE_QUOTE}" 2 true | jq -c '.evidence.path = "link.md"')"
    [ "$status" -eq 1 ]
    run validate_finding "$(bug_finding Critical 2 true | jq -c '.location.path = "/etc/passwd"')"
    [ "$status" -eq 1 ]
}

@test "drops findings with an unknown severity, kind, or missing location" {
    run validate_finding "$(bug_finding Major 2 true)"
    [ "$status" -eq 1 ]
    run validate_finding "$(bug_finding Critical 2 true | jq -c '.evidence.kind = "style"')"
    [ "$status" -eq 1 ]
    run validate_finding "$(bug_finding Critical 2 true | jq -c 'del(.location)')"
    [ "$status" -eq 1 ]
    run validate_finding "$(bug_finding Critical 4 true | jq -c '.location.start_line = 4')"
    [ "$status" -eq 1 ]
    run validate_finding 'not json'
    [ "$status" -eq 1 ]
}

@test "fails closed without posting on unparseable input" {
    printf 'not json' > "${REPORT}"
    run_post
    [ "$status" -eq 0 ]
    [[ ${output} == *"::warning::"* ]]
    [ ! -s "${GH_LOG}" ]

    write_report '[]'
    jq '.pr_number = 8' "${REPORT}" > "${REPORT}.tmp" && mv "${REPORT}.tmp" "${REPORT}"
    run_post
    [ "$status" -eq 0 ]
    [ ! -s "${GH_LOG}" ]

    write_report '[]'
    jq '.head_sha = "abc"' "${REPORT}" > "${REPORT}.tmp" && mv "${REPORT}.tmp" "${REPORT}"
    run_post
    [ "$status" -eq 0 ]
    [ ! -s "${GH_LOG}" ]

    write_report '[]'
    jq '.findings = {}' "${REPORT}" > "${REPORT}.tmp" && mv "${REPORT}.tmp" "${REPORT}"
    run_post
    [ "$status" -eq 0 ]
    [ ! -s "${GH_LOG}" ]

    write_report '[]'
    run_post TARGET_JSON='{"key":"entity:issue:7"}'
    [ "$status" -eq 0 ]
    [[ ${output} == *"::warning::"* ]]
    [ ! -s "${GH_LOG}" ]

    run_post TARGET_JSON='not json'
    [ "$status" -eq 0 ]
    [ ! -s "${GH_LOG}" ]

    run_post REPORT_FILE="${BATS_TEST_TMPDIR}/missing.json"
    [ "$status" -eq 0 ]
    [[ ${output} == *"::warning::"* ]]
    [ ! -s "${GH_LOG}" ]
}

@test "keeps a bug finding without evidence path" {
    run validate_finding "$(bug_finding Critical 2 true)"
    [ "$status" -eq 0 ]
}

@test "keeps a multi-line quote that matches exactly" {
    run validate_finding "$(rule_finding Warning "${RULE_QUOTE}"$'\n- Stay within' 2 true)"
    [ "$status" -eq 0 ]
}

@test "keeps a rule finding whose quote exists in the base file" {
    run validate_finding "$(rule_finding Warning "${RULE_QUOTE}" 2 true)"
    [ "$status" -eq 0 ]
}

@test "links a multi-line quote to its line range" {
    write_report "[$(rule_finding Warning "${RULE_QUOTE}"$'\n- Stay within' 2 true)]"
    run_post
    [ "$status" -eq 0 ]
    inline="$(posted | jq -r '.comments[0].body')"
    [[ ${inline} == *"blob/${BASE_SHA}/AGENTS.md#L3-L4) —"$'\n'"  \`\`\`\`text"$'\n'"  ${RULE_QUOTE}"$'\n'"  - Stay within"$'\n'"  \`\`\`\`"* ]]
}

@test "links evidence to base sha and location to head sha" {
    write_report "[$(rule_finding Warning "${RULE_QUOTE}" 10 false)]"
    run_post
    [ "$status" -eq 0 ]
    body="$(posted | jq -r '.body')"
    [[ ${body} == *"[\`AGENTS.md#L3\`](https://github.com/o/r/blob/${BASE_SHA}/AGENTS.md#L3) — \"${RULE_QUOTE}\""* ]]
    [[ ${body} == *"blob/${HEAD_SHA}/a.sh#L10"* ]]
}

@test "moves an in_diff finding outside the diff into the body" {
    write_report "[$(rule_finding Warning "${RULE_QUOTE}" 10 true)]"
    run_post
    [ "$status" -eq 0 ]
    run jq -e '(.comments | length) == 0' <<< "$(posted)"
    [ "$status" -eq 0 ]
    body="$(posted | jq -r '.body')"
    [[ ${body} == *"1. **[Warning]** Rule broken"* ]]
    [[ ${body} == *"- Evidence: "* ]]
    [[ ${body} == *"- Location: https://github.com/o/r/blob/${HEAD_SHA}/a.sh#L10"* ]]
    [[ ${body} == *"- Impact: Bad things"* ]]
    [[ ${body} != *"inline:"* ]]
}

@test "moves in_diff findings into the body when the diff is unavailable" {
    write_report "[$(bug_finding Critical 2 true)]"
    run_post PR_DIFF_FILE="${BATS_TEST_TMPDIR}/missing.diff"
    [ "$status" -eq 0 ]
    run jq -e '.event == "COMMENT" and (.comments | length) == 0' <<< "$(posted)"
    [ "$status" -eq 0 ]
}

@test "never sends REQUEST_CHANGES or APPROVE" {
    write_report "[$(bug_finding Critical 2 true)]"
    jq '.event = "REQUEST_CHANGES" | .verdict = "APPROVE"' "${REPORT}" > "${REPORT}.tmp"
    mv "${REPORT}.tmp" "${REPORT}"
    run_post
    [ "$status" -eq 0 ]
    run jq -e '.event == "COMMENT"' <<< "$(posted)"
    [ "$status" -eq 0 ]
    write_report '[]'
    run_post
    run jq -e '.event == "COMMENT"' <<< "$(posted)"
    [ "$status" -eq 0 ]
}

@test "numbers inline comments to match the body" {
    write_report "[$(rule_finding Warning "${RULE_QUOTE}" 10 false), $(bug_finding Critical 2 true)]"
    run_post
    [ "$status" -eq 0 ]
    run jq -e '(.comments | length) == 1 and .comments[0].path == "a.sh" and .comments[0].line == 2
        and .comments[0].side == "RIGHT" and (.comments[0] | has("start_line") | not)' <<< "$(posted)"
    [ "$status" -eq 0 ]
    inline="$(posted | jq -r '.comments[0].body')"
    [[ ${inline} == "**#2 [Critical]** Bug here"* ]]
    [[ ${inline} == *'To request a fix, reply to this comment with `@loop`.'* ]]
    body="$(posted | jq -r '.body')"
    [[ ${body} == *'2. **[Critical]** Bug here — inline: [`a.sh#L2`](https://github.com/o/r/pull/7/files)'* ]]
    [[ ${body} == *"1. **[Warning]** Rule broken"$'\n'"   - Evidence:"* ]]
}

@test "numbers the first inline finding #1 and keeps start_line" {
    write_report "[$(bug_finding Critical 4 true | jq -c '.location.start_line = 2')]"
    run_post
    [ "$status" -eq 0 ]
    run jq -e '.comments[0].start_line == 2 and .comments[0].start_side == "RIGHT" and .comments[0].line == 4' <<< "$(posted)"
    [ "$status" -eq 0 ]
    [[ "$(posted | jq -r '.comments[0].body')" == "**#1 [Critical]** Bug here"* ]]
    [[ "$(posted | jq -r '.body')" == *'1. **[Critical]** Bug here — inline: [`a.sh#L2-L4`]'* ]]
}

@test "posts COMMENT with marker, counts, and premises" {
    write_report "[$(bug_finding Critical 2 true), $(rule_finding Warning "${RULE_QUOTE}" 10 false)]"
    run_post
    [ "$status" -eq 0 ]
    grep -q -- '--method POST repos/o/r/pulls/7/reviews' "${GH_LOG}"
    run jq -e --arg h "${HEAD_SHA}" '.event == "COMMENT" and .commit_id == $h' <<< "$(posted)"
    [ "$status" -eq 0 ]
    body="$(posted | jq -r '.body')"
    [[ ${body} == "${MARKER}"* ]]
    [[ ${body} == *"## Code review"* ]]
    [[ ${body} == *"Findings: 2 (Critical: 1 / Warning: 1 / Suggestion: 0)"* ]]
    [[ ${body} == *"Adds a thing."* ]]
    [[ ${body} == *"### Premises checked"* ]]
    [[ ${body} == *"- PR body: checked"* ]]
    [[ ${body} == *"- Linked Issue / spec: #120"* ]]
    [[ ${body} != *"Dropped:"* ]]
}

@test "posts an explicit no-findings review" {
    write_report '[]'
    run_post
    [ "$status" -eq 0 ]
    run jq -e '.event == "COMMENT" and (.comments | length) == 0' <<< "$(posted)"
    [ "$status" -eq 0 ]
    body="$(posted | jq -r '.body')"
    [[ ${body} == "${MARKER}"* ]]
    [[ ${body} == *"Findings: 0 (Critical: 0 / Warning: 0 / Suggestion: 0)"* ]]
}

@test "reads the report from the work branch via git fetch" {
    local origin="${BATS_TEST_TMPDIR}/origin" work="${BATS_TEST_TMPDIR}/work"
    bats_git_fresh_repo "${origin}"
    mkdir -p "${origin}/.loop/review"
    write_report "[$(bug_finding Critical 2 true)]"
    cp "${REPORT}" "${origin}/.loop/review/pr-7.json"
    bats_git_cmd -C "${origin}" checkout -q -b loop/x
    bats_git_cmd -C "${origin}" add .loop
    bats_git_cmd -C "${origin}" commit -q -m report
    bats_git_cmd clone -q "${origin}" "${work}"
    run env -i PATH="${BIN_DIR}:${PATH}" HOME="${HOME}" GH_TOKEN=x GITHUB_REPOSITORY=o/r \
        GH_LOG="${GH_LOG}" GH_CAPTURE_DIR="${GH_CAPTURE_DIR}" \
        VERDICT=APPROVE EXECUTE_BRANCH=loop/x TARGET_JSON='{"entity":{"handoff_key":"entity:pr:7"}}' \
        PR_DIFF_FILE="${DIFF_FILE}" BASE_TREE_DIR="${BASE_DIR}" \
        bash -c 'cd "$1" && bash "$2"' _ "${work}" "${POST_SCRIPT}"
    [ "$status" -eq 0 ]
    run jq -e '.event == "COMMENT" and (.comments | length) == 1' <<< "$(posted)"
    [ "$status" -eq 0 ]

    : > "${GH_LOG}"
    run env -i PATH="${BIN_DIR}:${PATH}" HOME="${HOME}" GH_TOKEN=x GITHUB_REPOSITORY=o/r \
        GH_LOG="${GH_LOG}" GH_CAPTURE_DIR="${GH_CAPTURE_DIR}" \
        VERDICT=APPROVE EXECUTE_BRANCH='loop/../x' TARGET_JSON='{"entity":{"handoff_key":"entity:pr:7"}}' \
        bash -c 'cd "$1" && bash "$2"' _ "${work}" "${POST_SCRIPT}"
    [ "$status" -eq 0 ]
    [[ ${output} == *"::warning::"* ]]
    [ ! -s "${GH_LOG}" ]
}

@test "reads the PR number from TARGET_JSON key" {
    write_report '[]'
    run_post TARGET_JSON='{"key":"entity:pr:7"}'
    [ "$status" -eq 0 ]
    grep -q 'pulls/7/reviews' "${GH_LOG}"
}

@test "reports dropped findings count in the body" {
    write_report "[$(rule_finding Warning "not in the file" 2 true), $(bug_finding Critical 2 true)]"
    run_post
    [ "$status" -eq 0 ]
    body="$(posted | jq -r '.body')"
    [[ ${body} == *"Findings: 1 (Critical: 1 / Warning: 0 / Suggestion: 0)"* ]]
    [[ ${body} == *"Dropped: 1"* ]]
    [[ "$(posted | jq -r '.comments[0].body')" == "**#1 [Critical]**"* ]]
}

@test "retries without inline comments when the first post is rejected" {
    write_report "[$(bug_finding Critical 2 true)]"
    run_post GH_POST_FAIL_FIRST=1
    [ "$status" -eq 0 ]
    [ "$(grep -c -- '--method POST' "${GH_LOG}")" -eq 2 ]
    run jq -e '.event == "COMMENT" and (.comments | length) == 0' <<< "$(posted)"
    [ "$status" -eq 0 ]
    [[ "$(posted | jq -r '.body')" == *"- Location: https://github.com/o/r/blob/${HEAD_SHA}/a.sh#L2"* ]]
}

@test "warns and exits 0 when posting fails" {
    write_report '[]'
    run_post GH_POST_FAIL=1
    [ "$status" -eq 0 ]
    [[ ${output} == *"::warning::"* ]]
}
