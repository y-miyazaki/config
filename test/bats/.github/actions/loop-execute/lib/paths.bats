#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154

# Tests for .github/actions/loop-execute/lib/paths.sh

# Use cases:
# - infer_files_from_text uses fallback when no paths found
# - infer_files_from_text extracts repo-relative paths
# - infer_files_from_text honors AGENT_CHECKER_PATH_PATTERN

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

setup() {
    bats_source_rel ".github/actions/loop-execute/lib/paths.sh"
}

@test "infer_files_from_text uses fallback when no paths found" {
    unset AGENT_CHECKER_PATH_PATTERN
    result=$(infer_files_from_text "no paths here" "docs/fallback.md")
    [ "${result}" = "docs/fallback.md" ]
}

@test "infer_files_from_text extracts repo-relative paths" {
    unset AGENT_CHECKER_PATH_PATTERN
    result=$(infer_files_from_text "Fix docs/guide.md and src/app/main.go please" "")
    [[ ${result} == *"docs/guide.md"* ]]
    [[ ${result} == *"src/app/main.go"* ]]
}

@test "infer_files_from_text honors AGENT_CHECKER_PATH_PATTERN" {
    AGENT_CHECKER_PATH_PATTERN='[a-z]+\.md'
    result=$(infer_files_from_text "update readme.md and src/main.go" "fallback.md")
    [ "${result}" = "readme.md" ]
}
