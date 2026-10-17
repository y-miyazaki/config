#!/usr/bin/env bats
# shellcheck disable=SC2016,SC2030,SC2031,SC2034,SC2154

# Tests for .apm/packages/github/.apm/skills/github-pr-review/scripts/post_review.sh
#
# Use cases:
# - does nothing unless VERDICT is APPROVE
# - reads the report from the work branch (git fetch + git show) or REPORT_FILE
# - keeps rule/criteria findings only when the quote is an exact substring of the file at the
#   trusted base commit (a real temporary git repo; working-tree-only text is not evidence)
# - uses the PR's SHAs (gh pr view or PR_*_SHA seeds), never the report's; warns on mismatch
# - keeps bug findings that carry a location; drops malformed findings and escaping paths
# - checks diff membership per side and hunk (start_line in the same hunk)
# - moves in_diff findings outside the diff (or without a diff) into the body
# - posts a COMMENT review with marker, counts, premises, and numbered inline comments
# - links evidence to the base SHA and locations to the head SHA
# - reports the dropped findings count
# - fails closed (no post, exit 0) on unparseable input or unavailable trusted SHAs
# - posting failure and unexpected errors warn and exit 0
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
HEAD_SHA="$(printf 'a%.0s' {1..40})"
FORGED_SHA="$(printf 'c%.0s' {1..40})"
RULE_QUOTE='Never fabricate APIs, commands, paths, or behavior.'

setup() {
    # Base repository: the trusted base commit holds the evidence files
    git_test_repo_setup
    mkdir -p "${GIT_TEST_REPO}/docs"
    printf '# Rules\n\n- %s\n- Stay within requested scope.\n' "${RULE_QUOTE}" > "${GIT_TEST_REPO}/AGENTS.md"
    printf 'CRIT-01 (MUST): Quote exactly\n' > "${GIT_TEST_REPO}/docs/criteria.md"
    printf '%s\n' "${RULE_QUOTE}" > "${BATS_TEST_TMPDIR}/outside.md"
    ln -s "${BATS_TEST_TMPDIR}/outside.md" "${GIT_TEST_REPO}/link.md"
    bats_git_commit "${GIT_TEST_REPO}" base
    BASE_SHA="$(git_test_repo_git rev-parse HEAD)"

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
if [[ $1 == "pr" && $2 == "view" && -n ${GH_PR_VIEW_JSON:-} ]]; then
    printf '%s' "${GH_PR_VIEW_JSON}"
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
    REVIEW_BASE_SHA="${BASE_SHA}"
    PR_DIFF_FILE="${DIFF_FILE}"
    GITHUB_REPOSITORY=o/r
    # Library functions read git objects from cwd (production: the base checkout)
    cd "${GIT_TEST_REPO}" || return 1
}

teardown() {
    cd "${BATS_TEST_TMPDIR}" || return 1
    rm -rf "${GIT_TEST_REPO}" "${BIN_DIR}" "${GH_CAPTURE_DIR}" "${DIFF_FILE}" "${GH_LOG}" "${REPORT}" \
        "${BATS_TEST_TMPDIR}/outside.md" "${BATS_TEST_TMPDIR}/work"
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

# run_in_repo: Run post_review.sh with a clean env from repo dir $1; remaining args are env assignments
run_in_repo() {
    local dir="$1"
    shift
    run env -i PATH="${BIN_DIR}:${PATH}" HOME="${HOME}" GH_TOKEN=x GITHUB_REPOSITORY=o/r \
        GH_LOG="${GH_LOG}" GH_CAPTURE_DIR="${GH_CAPTURE_DIR}" \
        VERDICT=APPROVE EXECUTE_BRANCH=loop/x TARGET_JSON='{"entity":{"handoff_key":"entity:pr:7"}}' \
        "$@" bash -c 'cd "$1" && exec bash "$2"' _ "${dir}" "${POST_SCRIPT}"
}

# run_post: Run post_review.sh in the base repo with seeded SHAs, report, and diff
run_post() {
    run_in_repo "${GIT_TEST_REPO}" PR_BASE_SHA="${BASE_SHA}" PR_HEAD_SHA="${HEAD_SHA}" \
        REPORT_FILE="${REPORT}" PR_DIFF_FILE="${DIFF_FILE}" "$@"
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

@test "drops a quote that exists only in the working tree, not at the base commit" {
    printf 'Uncommitted rule text\n' >> "${GIT_TEST_REPO}/AGENTS.md"
    printf 'NEW-01 (MUST): only on disk\n' > "${GIT_TEST_REPO}/docs/new.md"
    run validate_finding "$(rule_finding Warning "Uncommitted rule text" 2 true)"
    [ "$status" -eq 1 ]
    run validate_finding "$(rule_finding Warning "NEW-01 (MUST)" 2 true | jq -c '.evidence.path = "docs/new.md"')"
    [ "$status" -eq 1 ]

    write_report "[$(rule_finding Warning "Uncommitted rule text" 2 true)]"
    run_post
    [ "$status" -eq 0 ]
    run jq -e '(.comments | length) == 0' <<< "$(posted)"
    [ "$status" -eq 0 ]
    [[ "$(posted | jq -r '.body')" == *"Dropped: 1"* ]]
}

@test "drops a rule finding whose quote differs only by whitespace" {
    run validate_finding "$(rule_finding Warning "${RULE_QUOTE} " 2 true)"
    [ "$status" -eq 1 ]
    run validate_finding "$(rule_finding Warning "${RULE_QUOTE}"$'\n  - Stay within' 2 true)"
    [ "$status" -eq 1 ]
}

@test "drops evidence paths that escape the base tree" {
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

@test "exits 0 without posting on an unexpected failure" {
    write_report "[$(bug_finding Critical 2 true)]"
    run_post TMPDIR="${BATS_TEST_TMPDIR}/no-such-dir"
    [ "$status" -eq 0 ]
    [[ ${output} == *"::warning::post_review: unexpected failure"* ]]
    [ "$(find "${GH_CAPTURE_DIR}" -name 'post-*.json' | wc -l)" -eq 0 ]
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

@test "fails closed without posting when trusted SHAs are unavailable" {
    write_report "[$(bug_finding Critical 2 true)]"
    # gh pr view fails (stub has no GH_PR_VIEW_JSON) and no PR_*_SHA seeds
    run_in_repo "${GIT_TEST_REPO}" REPORT_FILE="${REPORT}" PR_DIFF_FILE="${DIFF_FILE}"
    [ "$status" -eq 0 ]
    [[ ${output} == *"::warning::"*"trusted base/head SHAs"* ]]
    run grep -c -- '--method POST' "${GH_LOG}"
    [ "$output" -eq 0 ]

    # gh answers, but the base commit is unknown locally and cannot be fetched
    : > "${GH_LOG}"
    run_in_repo "${GIT_TEST_REPO}" REPORT_FILE="${REPORT}" PR_DIFF_FILE="${DIFF_FILE}" \
        GH_PR_VIEW_JSON="{\"baseRefOid\":\"${FORGED_SHA}\",\"headRefOid\":\"${HEAD_SHA}\"}"
    [ "$status" -eq 0 ]
    [[ ${output} == *"::warning::"* ]]
    run grep -c -- '--method POST' "${GH_LOG}"
    [ "$output" -eq 0 ]

    # gh returns malformed SHAs
    run_in_repo "${GIT_TEST_REPO}" REPORT_FILE="${REPORT}" PR_DIFF_FILE="${DIFF_FILE}" \
        GH_PR_VIEW_JSON='{"baseRefOid":"abc","headRefOid":"def"}'
    [ "$status" -eq 0 ]
    run grep -c -- '--method POST' "${GH_LOG}"
    [ "$output" -eq 0 ]
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

@test "reads the PR number from TARGET_JSON key" {
    write_report '[]'
    run_post TARGET_JSON='{"key":"entity:pr:7"}'
    [ "$status" -eq 0 ]
    grep -q 'pulls/7/reviews' "${GH_LOG}"
}

@test "reads the report from the work branch via git fetch" {
    # GIT_TEST_REPO acts as origin: base commit on its default branch, report on loop/x
    local work="${BATS_TEST_TMPDIR}/work" default_branch
    default_branch="$(git_test_repo_git rev-parse --abbrev-ref HEAD)"
    git_test_repo_git checkout -q -b loop/x
    mkdir -p "${GIT_TEST_REPO}/.loop-review"
    write_report "[$(rule_finding Critical "${RULE_QUOTE}" 2 true)]"
    cp "${REPORT}" "${GIT_TEST_REPO}/.loop-review/pr-7.json"
    bats_git_commit "${GIT_TEST_REPO}" report .loop-review
    git_test_repo_git checkout -q "${default_branch}"
    bats_git_cmd clone -q "${GIT_TEST_REPO}" "${work}"
    run_in_repo "${work}" PR_BASE_SHA="${BASE_SHA}" PR_HEAD_SHA="${HEAD_SHA}" PR_DIFF_FILE="${DIFF_FILE}"
    [ "$status" -eq 0 ]
    run jq -e '.event == "COMMENT" and (.comments | length) == 1' <<< "$(posted)"
    [ "$status" -eq 0 ]

    : > "${GH_LOG}"
    run_in_repo "${work}" PR_BASE_SHA="${BASE_SHA}" PR_HEAD_SHA="${HEAD_SHA}" EXECUTE_BRANCH='loop/../x'
    [ "$status" -eq 0 ]
    [[ ${output} == *"::warning::"* ]]
    [ ! -s "${GH_LOG}" ]
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

@test "skips posting when the PR head moved after the review" {
    # Report written against an older head; the author pushed since (well-formed, different SHA)
    write_report "[$(bug_finding Critical 2 true)]"
    jq --arg old "$(printf 'd%.0s' {1..40})" '.head_sha = $old' "${REPORT}" > "${REPORT}.tmp"
    mv "${REPORT}.tmp" "${REPORT}"
    run_post
    [ "$status" -eq 0 ]
    [[ ${output} == *"::warning::"*"report head_sha does not match the PR head"*"review not posted"* ]]
    run grep -c -- '--method POST' "${GH_LOG}"
    [ "$output" -eq 0 ]
}

@test "skips posting when the report head_sha is forged, malformed, or missing" {
    local mutation
    for mutation in ".head_sha = \"${FORGED_SHA}\" | .base_sha = \"${FORGED_SHA}\"" \
        '.head_sha = "abc"' '.head_sha = 42' 'del(.head_sha)'; do
        write_report "[$(bug_finding Critical 2 true)]"
        jq "${mutation}" "${REPORT}" > "${REPORT}.tmp" && mv "${REPORT}.tmp" "${REPORT}"
        : > "${GH_LOG}"
        run_post
        [ "$status" -eq 0 ]
        [[ ${output} == *"::warning::"*"report head_sha does not match the PR head"* ]]
        run grep -c -- '--method POST' "${GH_LOG}"
        [ "$output" -eq 0 ]
    done
}

@test "uses the PR's SHAs from gh pr view" {
    write_report "[$(rule_finding Warning "${RULE_QUOTE}" 10 false)]"
    run_in_repo "${GIT_TEST_REPO}" REPORT_FILE="${REPORT}" PR_DIFF_FILE="${DIFF_FILE}" \
        GH_PR_VIEW_JSON="{\"baseRefOid\":\"${BASE_SHA}\",\"headRefOid\":\"${HEAD_SHA}\"}"
    [ "$status" -eq 0 ]
    grep -q -- 'pr view 7 --repo o/r --json baseRefOid,headRefOid' "${GH_LOG}"
    run jq -e --arg h "${HEAD_SHA}" '.commit_id == $h' <<< "$(posted)"
    [ "$status" -eq 0 ]
    [[ "$(posted | jq -r '.body')" == *"blob/${BASE_SHA}/AGENTS.md#L3"* ]]
}

@test "uses trusted SHAs when only the report base_sha is forged" {
    write_report "[$(rule_finding Warning "${RULE_QUOTE}" 10 false), $(bug_finding Critical 2 true)]"
    jq --arg f "${FORGED_SHA}" '.base_sha = $f' "${REPORT}" > "${REPORT}.tmp"
    mv "${REPORT}.tmp" "${REPORT}"
    run_post
    [ "$status" -eq 0 ]
    [[ ${output} == *"::warning::"*"base_sha differs from PR #7"* ]]
    run jq -e --arg h "${HEAD_SHA}" '.event == "COMMENT" and .commit_id == $h and (.comments | length) == 1' <<< "$(posted)"
    [ "$status" -eq 0 ]
    body="$(posted | jq -r '.body')"
    [[ ${body} == *"blob/${BASE_SHA}/AGENTS.md#L3"* ]]
    [[ ${body} == *"blob/${HEAD_SHA}/a.sh#L10"* ]]
    [[ ${body} != *"${FORGED_SHA}"* ]]
    [[ "$(posted | jq -r '.comments[0].body')" != *"${FORGED_SHA}"* ]]

    # A missing base_sha is warned about the same way
    write_report '[]'
    jq 'del(.base_sha)' "${REPORT}" > "${REPORT}.tmp" && mv "${REPORT}.tmp" "${REPORT}"
    run_post
    [ "$status" -eq 0 ]
    [[ ${output} == *"::warning::"*"base_sha differs"* ]]
    run jq -e --arg h "${HEAD_SHA}" '.event == "COMMENT" and .commit_id == $h' <<< "$(posted)"
    [ "$status" -eq 0 ]
}

@test "warns and exits 0 when posting fails" {
    write_report '[]'
    run_post GH_POST_FAIL=1
    [ "$status" -eq 0 ]
    [[ ${output} == *"::warning::"* ]]
}
