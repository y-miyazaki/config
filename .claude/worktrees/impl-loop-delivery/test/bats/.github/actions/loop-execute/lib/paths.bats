#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154

# Tests for .github/actions/loop-execute/lib/paths.sh

# Use cases:
# - collect_allowlist_violations returns nothing when allowlist unset
# - collect_allowlist_violations / collect_denylist_violations ignore the legacy
#   ALLOWLIST / DENYLIST names (only AGENT_EDIT_ALLOWLIST / AGENT_EDIT_DENYLIST count)
# - collect_allowlist_violations flags paths outside allowlist
# - collect_allowlist_violations matches docs root markdown via ** glob
# - collect_allowlist_violations matches nested docs markdown via ** glob
# - path_matches_glob supports trailing ** directory patterns
# - path_matches_glob matches a root-level file against a leading ** pattern
# - path_matches_glob treats a bare ** as matching every path
# - collect_denylist_violations flags denylisted paths
# - collect_denylist_violations matches ** at start of pattern
# - collect_denylist_violations returns nothing when denylist unset
# - apply_platform_denylist_default fills empty AGENT_EDIT_DENYLIST with secret globs only
# - apply_platform_denylist_default preserves a caller denylist
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

@test "collect_allowlist_violations returns nothing when allowlist unset" {
    unset AGENT_EDIT_ALLOWLIST
    run collect_allowlist_violations $'docs/a.md\nsrc/b.go'
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "collect_allowlist_violations ignores the legacy ALLOWLIST name" {
    unset AGENT_EDIT_ALLOWLIST
    ALLOWLIST="docs/*"
    run collect_allowlist_violations $'docs/a.md\nsrc/b.go'
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "collect_allowlist_violations flags paths outside allowlist" {
    AGENT_EDIT_ALLOWLIST="docs/*,README.md"
    output=$(collect_allowlist_violations $'docs/a.md\nsrc/b.go')
    [[ ${output} == *"src/b.go"* ]]
    [[ ${output} != *"docs/a.md"* ]]
}

@test "collect_allowlist_violations matches docs root markdown via ** glob" {
    AGENT_EDIT_ALLOWLIST="docs/**/*.md,README.md,mkdocs.yml"
    output=$(collect_allowlist_violations $'docs/index.md\nsrc/b.go')
    [[ ${output} != *"docs/index.md"* ]]
    [[ ${output} == *"src/b.go"* ]]
}

@test "collect_allowlist_violations matches nested docs markdown via ** glob" {
    AGENT_EDIT_ALLOWLIST="docs/**/*.md"
    output=$(collect_allowlist_violations $'docs/explanation/architecture.md\nREADME.md')
    [[ ${output} != *"docs/explanation/architecture.md"* ]]
    [[ ${output} == *"README.md"* ]]
}

@test "path_matches_glob supports trailing ** directory patterns" {
    run path_matches_glob ".github/workflows/ci.yaml" ".github/**"
    [ "$status" -eq 0 ]
    run path_matches_glob "README.md" ".github/**"
    [ "$status" -eq 1 ]
}

@test "path_matches_glob matches a root-level file against a leading ** pattern" {
    run path_matches_glob ".env" "**/.env"
    [ "$status" -eq 0 ]
    run path_matches_glob "credentials.json" "**/credentials*"
    [ "$status" -eq 0 ]
    run path_matches_glob "notes.txt" "**/.env"
    [ "$status" -eq 1 ]
}

@test "path_matches_glob treats a bare ** as matching every path" {
    run path_matches_glob "a/b/c.txt" "**"
    [ "$status" -eq 0 ]
    run path_matches_glob ".env" "**"
    [ "$status" -eq 0 ]
}

@test "collect_denylist_violations flags denylisted paths" {
    AGENT_EDIT_DENYLIST="**/.env,**/secrets*"
    output=$(collect_denylist_violations $'docs/a.md\nnested/.env\nconfig/secrets.json')
    [[ ${output} == *"nested/.env"* ]]
    [[ ${output} == *"config/secrets.json"* ]]
    [[ ${output} != *"docs/a.md"* ]]
}

@test "collect_denylist_violations matches ** at start of pattern" {
    AGENT_EDIT_DENYLIST="**/.env"
    output=$(collect_denylist_violations $'nested/.env\n.env')
    [[ ${output} == *"nested/.env"* ]]
    # Root-level ".env" must appear as its own violation line, not merely as a
    # substring of "nested/.env" (regression guard for the leading ** glob).
    while IFS= read -r line; do
        [[ ${line} == ".env" ]] && found_root_env="true"
    done <<< "${output}"
    [[ ${found_root_env:-} == "true" ]]
}

@test "apply_platform_denylist_default fills empty AGENT_EDIT_DENYLIST" {
    unset AGENT_EDIT_DENYLIST
    apply_platform_denylist_default
    [[ ${AGENT_EDIT_DENYLIST} == *".env"* ]]
    [[ ${AGENT_EDIT_DENYLIST} == *"credentials*"* ]]
    [[ ${AGENT_EDIT_DENYLIST} == *"secrets*"* ]]
    # A reusable workflow must not assume a caller's directory layout: domain
    # paths belong in that repository's own caller denylist.
    [[ ${AGENT_EDIT_DENYLIST} != *"migration"* ]]
    [[ ${AGENT_EDIT_DENYLIST} != *"infrastructure"* ]]
}

@test "apply_platform_denylist_default preserves caller denylist" {
    AGENT_EDIT_DENYLIST="custom/**"
    apply_platform_denylist_default
    [[ ${AGENT_EDIT_DENYLIST} == "custom/**" ]]
}

@test "collect_denylist_violations ignores the legacy DENYLIST name" {
    unset AGENT_EDIT_DENYLIST
    DENYLIST="**/.env"
    run collect_denylist_violations $'docs/a.md\n.env'
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "collect_denylist_violations returns nothing when denylist unset" {
    unset AGENT_EDIT_DENYLIST
    run collect_denylist_violations $'docs/a.md\n.env'
    [ "$status" -eq 0 ]
    [ -z "$output" ]
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
