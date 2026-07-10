#!/usr/bin/env bats

# Tests for .github/actions/loop-execute/lib/paths.sh

setup() {
    source ".github/actions/loop-execute/lib/paths.sh"
}

@test "collect_allowlist_violations returns nothing when allowlist unset" {
    unset ALLOWLIST
    run collect_allowlist_violations $'docs/a.md\nsrc/b.go'
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "collect_allowlist_violations flags paths outside allowlist" {
    ALLOWLIST="docs/*,README.md"
    output=$(collect_allowlist_violations $'docs/a.md\nsrc/b.go')
    [[ ${output} == *"src/b.go"* ]]
    [[ ${output} != *"docs/a.md"* ]]
}

@test "collect_denylist_violations flags denylisted paths" {
    DENYLIST="**/.env,**/secrets*"
    output=$(collect_denylist_violations $'docs/a.md\nnested/.env\nconfig/secrets.json')
    [[ ${output} == *"nested/.env"* ]]
    [[ ${output} == *"config/secrets.json"* ]]
    [[ ${output} != *"docs/a.md"* ]]
}

@test "collect_denylist_violations returns nothing when denylist unset" {
    unset DENYLIST
    run collect_denylist_violations $'docs/a.md\n.env'
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "infer_files_from_text uses fallback when no paths found" {
    unset INFER_FILES_PATTERN
    result=$(infer_files_from_text "no paths here" "docs/fallback.md")
    [ "${result}" = "docs/fallback.md" ]
}

@test "infer_files_from_text extracts repo-relative paths" {
    unset INFER_FILES_PATTERN
    result=$(infer_files_from_text "Fix docs/guide.md and src/app/main.go please" "")
    [[ ${result} == *"docs/guide.md"* ]]
    [[ ${result} == *"src/app/main.go"* ]]
}

@test "infer_files_from_text honors INFER_FILES_PATTERN" {
    INFER_FILES_PATTERN='[a-z]+\.md'
    result=$(infer_files_from_text "update readme.md and src/main.go" "fallback.md")
    [ "${result}" = "readme.md" ]
}
