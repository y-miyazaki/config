#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154

# Tests for .apm/packages/repo-maintenance/.apm/skills/test-gap/scripts/detect_test_gap.sh
#
# Use cases:
# - detect_test_gap accepts --scope range with --since and echoes since and commit_range
# - detect_test_gap defaults to scope all and returns skip false on an empty repo
# - detect_test_gap emits churn hotspots for frequently edited files
# - detect_test_gap emits error JSON outside a git repository
# - detect_test_gap emits verifier_context listing processed ledger paths when the ledger has recent entries
# - detect_test_gap excludes skipped paths from hotspots
# - detect_test_gap honors TEST_GAP_CHURN_MIN and TEST_GAP_CHURN_TOP
# - detect_test_gap never returns skip true
# - detect_test_gap omits ledger entries older than the retention window
# - detect_test_gap omits verifier_context when the ledger has no processed entries
# - detect_test_gap output is accepted by loop-detect helper functions
# - detect_test_gap range without --since returns error JSON exit 1
# - detect_test_gap rejects unknown --scope
# - detect_test_gap reports processed ledger entries within the retention window
# - detect_test_gap treats a missing ledger file as empty
# - detect_test_gap verifier_context is returned by build_verifier_context_from_result for a ledger with entries
# - detect_test_gap warns and continues on a corrupt ledger file
# - detect_test_gap warns and falls back to 30 days when TEST_GAP_RETENTION_DAYS is not a non-negative integer
# - detect_test_gap warns and returns empty hotspots when since is not a valid ref

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

DETECT_SCRIPT="$(apm_skill_script_path test-gap detect_test_gap.sh)"

# make_churn_repo <file> <commits>: repository where <file> is touched <commits> times
make_churn_repo() {
    local file="$1" commits="$2" i
    git_test_repo_setup
    mkdir -p "${GIT_TEST_REPO}/$(dirname "${file}")"
    for ((i = 1; i <= commits; i++)); do
        printf 'v%s\n' "${i}" > "${GIT_TEST_REPO}/${file}"
        git_test_repo_git add .
        git_test_repo_git commit -q -m "chore: edit ${i}"
    done
}

@test "detect_test_gap accepts --scope range with --since and echoes since and commit_range" {
    make_churn_repo "src/a.sh" 2
    git_test_repo_run "bash '${DETECT_SCRIPT}' --scope range --since HEAD~1"
    [ "$status" -eq 0 ]
    run jq -e '.scope == "range" and .since == "HEAD~1" and .commit_range == "HEAD~1..HEAD"' <<< "${output}"
    [ "$status" -eq 0 ]
}

@test "detect_test_gap defaults to scope all and returns skip false on an empty repo" {
    git_test_repo_setup
    printf 'x\n' > "${GIT_TEST_REPO}/a.txt"
    git_test_repo_git add .
    git_test_repo_git commit -q -m "chore: init"
    git_test_repo_run "bash '${DETECT_SCRIPT}'"
    [ "$status" -eq 0 ]
    run jq -e '.status == "ok" and .scope == "all" and .skip == false and (.hotspots | length) == 0 and (.warnings | type) == "array"' <<< "${output}"
    [ "$status" -eq 0 ]
}

@test "detect_test_gap emits churn hotspots for frequently edited files" {
    make_churn_repo "src/hot.sh" 4
    git_test_repo_run "env TEST_GAP_CHURN_MIN=3 bash '${DETECT_SCRIPT}'"
    [ "$status" -eq 0 ]
    run jq -e '.hotspots[0].path == "src/hot.sh" and .hotspots[0].kind == "churn" and .hotspots[0].count == 4' <<< "${output}"
    [ "$status" -eq 0 ]
}

@test "detect_test_gap emits error JSON outside a git repository" {
    local d
    d="$(mktemp -d)"
    run bash -c "cd '${d}' && bash '${DETECT_SCRIPT}'"
    rm -rf "${d}"
    [ "$status" -eq 1 ]
    run jq -e '.status == "error"' <<< "${output}"
    [ "$status" -eq 0 ]
}

@test "detect_test_gap emits verifier_context listing processed ledger paths when the ledger has recent entries" {
    make_churn_repo "src/a.sh" 1
    mkdir -p "${GIT_TEST_REPO}/.loop"
    printf '%s' '{"entries":{"test/bats/foo.bats":{"attempts":2,"last_loop_run_id":"7","outcome":"pr-created","processed_at":"2999-01-01T00:00:00Z"},"test/bats/bar baz.bats":{"attempts":1,"last_loop_run_id":"8","outcome":"no-change","processed_at":"2999-01-01T00:00:00Z"}}}' > "${GIT_TEST_REPO}/.loop/state-test-gap-ledger.json"
    git_test_repo_run "bash '${DETECT_SCRIPT}'"
    [ "$status" -eq 0 ]
    local ctx
    ctx="$(jq -r '.verifier_context' <<< "${output}")"
    [[ ${ctx} == *"## test-gap ledger (recently processed test paths)"* ]]
    [[ ${ctx} == *"- test/bats/foo.bats (attempts: 2, outcome: pr-created)"* ]]
    [[ ${ctx} == *"- test/bats/bar baz.bats (attempts: 1, outcome: no-change)"* ]]
    [[ ${ctx} == *".loop/state-test-gap-ledger.json"* ]]
    [[ ${ctx} == *"must not be selected again unless the PR body states a new reason"* ]]
}

@test "detect_test_gap excludes skipped paths from hotspots" {
    make_churn_repo "node_modules/pkg/index.js" 5
    git_test_repo_run "env TEST_GAP_CHURN_MIN=3 bash '${DETECT_SCRIPT}'"
    [ "$status" -eq 0 ]
    run jq -e '(.hotspots | length) == 0' <<< "${output}"
    [ "$status" -eq 0 ]
}

@test "detect_test_gap honors TEST_GAP_CHURN_MIN and TEST_GAP_CHURN_TOP" {
    make_churn_repo "src/a.sh" 4
    printf 'b\n' > "${GIT_TEST_REPO}/src/b.sh"
    git_test_repo_git add .
    git_test_repo_git commit -q -m "chore: b1"
    git_test_repo_run "env TEST_GAP_CHURN_MIN=99 bash '${DETECT_SCRIPT}'"
    [ "$status" -eq 0 ]
    run jq -e '(.hotspots | length) == 0' <<< "${output}"
    [ "$status" -eq 0 ]
    git_test_repo_run "env TEST_GAP_CHURN_MIN=1 TEST_GAP_CHURN_TOP=1 bash '${DETECT_SCRIPT}'"
    [ "$status" -eq 0 ]
    run jq -e '(.hotspots | length) == 1' <<< "${output}"
    [ "$status" -eq 0 ]
}

@test "detect_test_gap never returns skip true" {
    make_churn_repo "src/a.sh" 1
    git_test_repo_run "bash '${DETECT_SCRIPT}' --scope staged"
    [ "$status" -eq 0 ]
    run jq -e '.skip == false' <<< "${output}"
    [ "$status" -eq 0 ]
}

@test "detect_test_gap omits ledger entries older than the retention window" {
    make_churn_repo "src/a.sh" 1
    mkdir -p "${GIT_TEST_REPO}/.loop"
    printf '%s' '{"entries":{"test/bats/old.bats":{"attempts":1,"last_loop_run_id":"1","outcome":"pr-created","processed_at":"2000-01-01T00:00:00Z"}}}' > "${GIT_TEST_REPO}/.loop/state-test-gap-ledger.json"
    git_test_repo_run "env TEST_GAP_RETENTION_DAYS=30 bash '${DETECT_SCRIPT}'"
    [ "$status" -eq 0 ]
    run jq -e '(.ledger.processed | length) == 0' <<< "${output}"
    [ "$status" -eq 0 ]
}

@test "detect_test_gap omits verifier_context when the ledger has no processed entries" {
    make_churn_repo "src/a.sh" 1
    git_test_repo_run "bash '${DETECT_SCRIPT}'"
    [ "$status" -eq 0 ]
    local det="${output}"
    run jq -e '(.verifier_context // "") == ""' <<< "${det}"
    [ "$status" -eq 0 ]
    bats_source_rel ".github/actions/loop-detect/lib/detect.sh"
    run build_verifier_context_from_result "${det}"
    [ "$status" -eq 0 ]
    [ -z "${output}" ]
}

@test "detect_test_gap output is accepted by loop-detect helper functions" {
    make_churn_repo "src/a.sh" 1
    git_test_repo_run "bash '${DETECT_SCRIPT}' --scope range --since HEAD"
    [ "$status" -eq 0 ]
    local det="${output}"
    bats_source_rel ".github/actions/loop-detect/lib/detect.sh"
    run detect_result_skip "${det}"
    [ "$status" -eq 1 ]
    run build_verifier_context_from_result "${det}"
    [ "$status" -eq 0 ]
    [ -z "${output}" ]
}

@test "detect_test_gap range without --since returns error JSON exit 1" {
    git_test_repo_setup
    git_test_repo_run "bash '${DETECT_SCRIPT}' --scope range"
    [ "$status" -eq 1 ]
    run jq -e '.status == "error"' <<< "${output}"
    [ "$status" -eq 0 ]
}

@test "detect_test_gap rejects unknown --scope" {
    git_test_repo_setup
    git_test_repo_run "bash '${DETECT_SCRIPT}' --scope bogus"
    [ "$status" -eq 1 ]
    run jq -e '.status == "error"' <<< "${output}"
    [ "$status" -eq 0 ]
}

@test "detect_test_gap reports processed ledger entries within the retention window" {
    make_churn_repo "src/a.sh" 1
    mkdir -p "${GIT_TEST_REPO}/.loop"
    printf '%s' '{"entries":{"test/bats/foo.bats":{"attempts":2,"last_loop_run_id":"7","outcome":"pr-created","processed_at":"2999-01-01T00:00:00Z"}}}' > "${GIT_TEST_REPO}/.loop/state-test-gap-ledger.json"
    git_test_repo_run "bash '${DETECT_SCRIPT}'"
    [ "$status" -eq 0 ]
    run jq -e '.ledger.file == ".loop/state-test-gap-ledger.json" and .ledger.processed[0].path == "test/bats/foo.bats" and .ledger.processed[0].attempts == 2' <<< "${output}"
    [ "$status" -eq 0 ]
}

@test "detect_test_gap treats a missing ledger file as empty" {
    make_churn_repo "src/a.sh" 1
    git_test_repo_run "bash '${DETECT_SCRIPT}'"
    [ "$status" -eq 0 ]
    run jq -e '(.ledger.processed | length) == 0' <<< "${output}"
    [ "$status" -eq 0 ]
}

@test "detect_test_gap verifier_context is returned by build_verifier_context_from_result for a ledger with entries" {
    make_churn_repo "src/a.sh" 1
    mkdir -p "${GIT_TEST_REPO}/.loop"
    printf '%s' '{"entries":{"test/bats/foo.bats":{"attempts":2,"last_loop_run_id":"7","outcome":"pr-created","processed_at":"2999-01-01T00:00:00Z"}}}' > "${GIT_TEST_REPO}/.loop/state-test-gap-ledger.json"
    git_test_repo_run "bash '${DETECT_SCRIPT}'"
    [ "$status" -eq 0 ]
    local det="${output}"
    bats_source_rel ".github/actions/loop-detect/lib/detect.sh"
    run build_verifier_context_from_result "${det}"
    [ "$status" -eq 0 ]
    [[ ${output} == *"test/bats/foo.bats"* ]]
    [[ ${output} == *"## test-gap ledger"* ]]
}

@test "detect_test_gap warns and continues on a corrupt ledger file" {
    make_churn_repo "src/a.sh" 1
    mkdir -p "${GIT_TEST_REPO}/.loop"
    printf '%s' 'not json' > "${GIT_TEST_REPO}/.loop/state-test-gap-ledger.json"
    git_test_repo_run "bash '${DETECT_SCRIPT}'"
    [ "$status" -eq 0 ]
    run jq -e '(.ledger.processed | length) == 0 and ([.warnings[] | test("ledger")] | any)' <<< "${output}"
    [ "$status" -eq 0 ]
}

@test "detect_test_gap warns and falls back to 30 days when TEST_GAP_RETENTION_DAYS is not a non-negative integer" {
    make_churn_repo "src/a.sh" 1
    mkdir -p "${GIT_TEST_REPO}/.loop"
    printf '%s' '{"entries":{"test/bats/foo.bats":{"attempts":1,"last_loop_run_id":"7","outcome":"pr-created","processed_at":"2999-01-01T00:00:00Z"},"test/bats/old.bats":{"attempts":1,"last_loop_run_id":"1","outcome":"pr-created","processed_at":"2000-01-01T00:00:00Z"}}}' > "${GIT_TEST_REPO}/.loop/state-test-gap-ledger.json"
    local bad
    for bad in abc -5 "1 day"; do
        git_test_repo_run "env TEST_GAP_RETENTION_DAYS='${bad}' bash '${DETECT_SCRIPT}'"
        [ "$status" -eq 0 ]
        run jq -e '.status == "ok" and ([.warnings[] | test("TEST_GAP_RETENTION_DAYS")] | any) and ([.ledger.processed[].path] == ["test/bats/foo.bats"])' <<< "${output}"
        [ "$status" -eq 0 ]
    done
}

@test "detect_test_gap warns and returns empty hotspots when since is not a valid ref" {
    make_churn_repo "src/a.sh" 4
    git_test_repo_run "env TEST_GAP_CHURN_MIN=1 bash '${DETECT_SCRIPT}' --scope range --since no-such-ref"
    [ "$status" -eq 0 ]
    run jq -e '.skip == false and ([.warnings[] | test("since")] | any)' <<< "${output}"
    [ "$status" -eq 0 ]
}
