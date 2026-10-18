#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154

bats_require_minimum_version 1.5.0

# Tests for .github/actions/lib/loop/edit_paths.sh

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
# - list_diff_paths lists non-ASCII paths unquoted and both sides of a rename
# - list_diff_paths fails with 2 on a path with a control char, quote, or backslash
# - list_diff_paths fails with 1 when git diff fails

# - apply_platform_denylist_default preserves a caller denylist

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

setup() {
    bats_source_rel ".github/actions/lib/loop/edit_paths.sh"
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

# make_diff_repo: repo on main with secrets.txt, branch feature checked out.
function make_diff_repo {
    REPO="${BATS_TEST_TMPDIR}/repo"
    git init -q -b main "${REPO}"
    git -C "${REPO}" config user.email t@example.com
    git -C "${REPO}" config user.name t
    printf 'x\n' > "${REPO}/secrets.txt"
    git -C "${REPO}" add secrets.txt
    git -C "${REPO}" commit -q -m base
    git -C "${REPO}" checkout -q -b feature
}

@test "list_diff_paths fails with 1 when git diff fails" {
    make_diff_repo
    run bash -c 'cd "$1" && source "$2" && list_diff_paths missing-ref...HEAD --' _ "${REPO}" \
        "$(bats_workspace_root)/.github/actions/lib/loop/edit_paths.sh"
    [ "$status" -eq 1 ]
}

@test "list_diff_paths fails with 2 on unsafe path characters" {
    local name
    make_diff_repo
    for name in $'a\nb.txt' $'a\tb.txt' 'a"b.txt' 'a\b.txt'; do
        git -C "${REPO}" checkout -q -B feature main
        printf 'x\n' > "${REPO}/${name}"
        git -C "${REPO}" add -- "${name}"
        git -C "${REPO}" commit -q -m unsafe
        run --separate-stderr bash -c 'cd "$1" && source "$2" && list_diff_paths main...HEAD --' _ "${REPO}" \
            "$(bats_workspace_root)/.github/actions/lib/loop/edit_paths.sh"
        [ "$status" -eq 2 ]
        [ -z "$output" ]
        [[ $stderr == *"unsafe characters in changed path"* ]]
    done
}

@test "list_diff_paths lists non-ASCII paths unquoted and both sides of a rename" {
    make_diff_repo
    mkdir -p "${REPO}/.github/workflows" "${REPO}/dé"
    printf 'on: push\n' > "${REPO}/.github/workflows/é.yaml"
    git -C "${REPO}" mv secrets.txt dé/notes.txt
    git -C "${REPO}" add .github
    git -C "${REPO}" commit -q -m change
    run bash -c 'cd "$1" && source "$2" && list_diff_paths main...HEAD --' _ "${REPO}" \
        "$(bats_workspace_root)/.github/actions/lib/loop/edit_paths.sh"
    [ "$status" -eq 0 ]
    [ "$output" = $'.github/workflows/é.yaml\ndé/notes.txt\nsecrets.txt' ]
}
