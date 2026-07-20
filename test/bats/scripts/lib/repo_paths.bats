#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154

# Tests for scripts/lib/repo_paths.sh

# Use cases:
# - repo_path_should_skip excludes agent and generated directories
# - repo_path_should_skip allows .apm package sources, .github, and root dotfiles
# - repo_path_should_skip excludes unknown dot-prefixed directories such as .env
# - repo_path_should_skip_base honors extra prune roots
# - repo_path_should_skip respects .gitignore in a git repository
# - repo_filter_paths drops excluded stdin paths
# - repo_filter_paths preserves .github paths from git-diff-shaped input (regression)
# - repo_path_should_skip returns expected status for dot directory exclusion paths
# - repo_emit_tracked_paths filters tracked files
# - repo_append_find_prune_args builds a find prune predicate
# - repo_append_find_prune_args preserves github paths through repo_filter_paths
# - REPO_PATHS_EXTRA_PRUNES applies to skip and find prune consistently
# - REPO_PATHS_INCLUDE_AGENTS allows agent paths
# - REPO_PATHS_INCLUDE_GITIGNORED skips gitignore exclusion
# - repo_apply_git_rename records both-scannable renames and cross-zone fallbacks
# - repo_path_should_skip excludes cursor and kiro root agent directories

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

setup() {
    bats_source_rel "scripts/lib/repo_paths.sh"
    REPO_FIXTURE="${BATS_TEST_TMPDIR}/repo"
    mkdir -p "${REPO_FIXTURE}/.agents/skills" \
        "${REPO_FIXTURE}/docs" \
        "${REPO_FIXTURE}/tmp"
    printf 'tracked\n' > "${REPO_FIXTURE}/docs/readme.md"
    printf 'ignored\n' > "${REPO_FIXTURE}/tmp/ignored.txt"
    printf 'agent\n' > "${REPO_FIXTURE}/.agents/skills/SKILL.md"
    printf 'tmp/\n' > "${REPO_FIXTURE}/.gitignore"
    git -C "${REPO_FIXTURE}" init -q
    git -C "${REPO_FIXTURE}" add docs/readme.md .gitignore
    git -C "${REPO_FIXTURE}" commit -q -m "init"
}

@test "repo_path_should_skip allows github workflows and root config dotfiles" {
    run repo_path_should_skip ".github/workflows/ci.yaml"
    [ "$status" -eq 1 ]

    run repo_path_should_skip ".gitignore"
    [ "$status" -eq 1 ]

    run repo_path_should_skip ".pre-commit-config.yaml"
    [ "$status" -eq 1 ]
}

@test "repo_path_should_skip allows apm package source paths" {
    run repo_path_should_skip ".apm/packages/common/foo.md"
    [ "$status" -eq 1 ]

    run repo_path_should_skip ".apm/AGENTS.md"
    [ "$status" -eq 1 ]
}

@test "repo_path_should_skip excludes agent and generated directories" {
    run repo_path_should_skip ".agents/skills/SKILL.md"
    [ "$status" -eq 0 ]

    run repo_path_should_skip ".codex/skills/foo/SKILL.md"
    [ "$status" -eq 0 ]

    run repo_path_should_skip "cursor/skills/foo/SKILL.md"
    [ "$status" -eq 0 ]

    run repo_path_should_skip "kiro/skills/foo/SKILL.md"
    [ "$status" -eq 0 ]

    run repo_path_should_skip "apm_modules/pkg/index.js"
    [ "$status" -eq 0 ]

    run repo_path_should_skip "docs/readme.md"
    [ "$status" -eq 1 ]
}

@test "repo_path_should_skip_base honors extra prune roots" {
    run repo_path_should_skip_base "docs/report/2026-07-20.md" docs/report
    [ "$status" -eq 0 ]

    run repo_path_should_skip_base "docs/guide/overview.md" docs/report
    [ "$status" -eq 1 ]
}

@test "repo_path_should_skip respects gitignore in a git repository" {
    (
        cd "${REPO_FIXTURE}" || exit 1
        run repo_path_should_skip "tmp/ignored.txt"
        [ "$status" -eq 0 ]

        run repo_path_should_skip "docs/readme.md"
        [ "$status" -eq 1 ]
    )
}

@test "repo_filter_paths drops excluded stdin paths" {
    local filtered

    filtered="$(printf '%s\n' \
        'docs/readme.md' \
        '.agents/skills/SKILL.md' \
        'tmp/ignored.txt' \
        | (
            cd "${REPO_FIXTURE}" || exit 1
            repo_filter_paths
        ))"

    [[ ${filtered} == *"docs/readme.md"* ]]
    [[ ${filtered} != *".agents/skills/SKILL.md"* ]]
}

@test "repo_filter_paths preserves github paths from git diff shaped input" {
    local filtered expected

    expected=$'.github/actions/loop-detect/action.yml\n.github/workflows/ci.yaml\ndocs/readme.md'
    filtered="$(printf '%s\n' \
        '.github/workflows/ci.yaml' \
        '.github/actions/loop-detect/action.yml' \
        '.agents/skills/docs-updater/SKILL.md' \
        'docs/readme.md' \
        '.env/common/local.env' \
        | (
            cd "${REPO_FIXTURE}" || exit 1
            repo_filter_paths
        ) | sort)"

    [ "${filtered}" = "$(printf '%s' "${expected}" | sort)" ]
}

@test "repo_path_should_skip returns expected status for dot directory exclusion paths" {
    local path expect_scan status_code case_entry

    # path:expect_scan — 1 = scannable (repo_path_should_skip returns 1), 0 = excluded (returns 0)
    local -a cases=(
        '.github/workflows/ci.yaml:1'
        '.github/actions/foo/action.yml:1'
        '.gitignore:1'
        '.pre-commit-config.yaml:1'
        '.golangci.yaml:1'
        '.markdownlint-cli2.yaml:1'
        '.apm/packages/common/foo.md:1'
        '.agents/skills/SKILL.md:0'
        '.cursor/rules/foo.mdc:0'
        '.env/common/local.env:0'
    )

    for case_entry in "${cases[@]}"; do
        path="${case_entry%%:*}"
        expect_scan="${case_entry##*:}"
        run repo_path_should_skip "${path}"
        status_code="${status}"
        if [[ ${expect_scan} -eq 1 ]]; then
            [ "${status_code}" -eq 1 ]
        else
            [ "${status_code}" -eq 0 ]
        fi
    done
}

@test "repo_emit_tracked_paths filters tracked files" {
    local emitted

    emitted="$(
        cd "${REPO_FIXTURE}" || exit 1
        repo_emit_tracked_paths '\.md$'
    )"

    [[ ${emitted} == "docs/readme.md" ]]
    [[ ${emitted} != *".agents"* ]]
}

@test "repo_append_find_prune_args preserves github paths through repo_filter_paths" {
    local -a find_args=(.)
    local output

    mkdir -p "${REPO_FIXTURE}/.github/workflows"
    printf 'workflow\n' > "${REPO_FIXTURE}/.github/workflows/ci.yaml"
    repo_append_find_prune_args find_args
    find_args+=(-name '*.yaml' -type f -print)
    output="$(
        cd "${REPO_FIXTURE}" || exit 1
        find "${find_args[@]}" 2> /dev/null | sed 's|^\./||' | repo_filter_paths | sort
    )"

    [[ ${output} == ".github/workflows/ci.yaml" ]]
}

@test "repo_append_find_prune_args builds a find prune predicate" {
    local -a find_args=(.)
    local output

    repo_append_find_prune_args find_args
    find_args+=(-name '*.md' -type f -print)
    output="$(
        cd "${REPO_FIXTURE}" || exit 1
        find "${find_args[@]}" 2> /dev/null | sed 's|^\./||' | sort
    )"

    [[ ${output} == "docs/readme.md" ]]
    [[ ${output} != *".agents"* ]]
}

@test "repo_apply_git_rename appends changed_files for agent to scannable cross-zone rename" {
    local -a renamed=() deleted=() changed=()

    repo_apply_git_rename ".agents/skills/foo/SKILL.md" "docs/new.md" renamed deleted changed
    [ "${#renamed[@]}" -eq 1 ]
    [ "${renamed[0]}" == ".agents/skills/foo/SKILL.md->docs/new.md" ]
    [ "${#deleted[@]}" -eq 0 ]
    [ "${#changed[@]}" -eq 1 ]
    [ "${changed[0]}" == "docs/new.md" ]
}

@test "repo_apply_git_rename appends deleted_files for scannable to agent cross-zone rename" {
    local -a renamed=() deleted=() changed=()

    repo_apply_git_rename "docs/old.md" ".agents/skills/foo/SKILL.md" renamed deleted changed
    [ "${#renamed[@]}" -eq 1 ]
    [ "${renamed[0]}" == "docs/old.md->.agents/skills/foo/SKILL.md" ]
    [ "${#deleted[@]}" -eq 1 ]
    [ "${deleted[0]}" == "docs/old.md" ]
    [ "${#changed[@]}" -eq 0 ]
}

@test "repo_apply_git_rename records both-scannable paths in renamed only" {
    local -a renamed=() deleted=() changed=()

    repo_apply_git_rename "src/app.go" "src/main.go" renamed deleted changed
    [ "${#renamed[@]}" -eq 1 ]
    [ "${renamed[0]}" == "src/app.go->src/main.go" ]
    [ "${#deleted[@]}" -eq 0 ]
    [ "${#changed[@]}" -eq 0 ]
}

@test "REPO_PATHS_INCLUDE_AGENTS allows agent paths" {
    REPO_PATHS_INCLUDE_AGENTS=true
    run repo_path_should_skip ".agents/skills/SKILL.md"
    [ "$status" -eq 1 ]
}

@test "REPO_PATHS_INCLUDE_GITIGNORED allows gitignored paths" {
    (
        cd "${REPO_FIXTURE}" || exit 1
        REPO_PATHS_INCLUDE_GITIGNORED=true
        run repo_path_should_skip "tmp/ignored.txt"
        [ "$status" -eq 1 ]
    )
}

@test "REPO_PATHS_EXTRA_PRUNES excludes paths from skip and find prune" {
    local -a find_args=(.)
    local find_line

    REPO_PATHS_EXTRA_PRUNES="docs/report"
    run repo_path_should_skip "docs/report/2026-07-20.md"
    [ "$status" -eq 0 ]

    run repo_path_should_skip "docs/guide/overview.md"
    [ "$status" -eq 1 ]

    repo_append_find_prune_args find_args
    find_line="$(printf '%s\n' "${find_args[@]}")"
    [[ ${find_line} == *"./docs/report"* ]]
}

@test "repo_filter_paths excludes env paths after find enumeration" {
    local -a find_args=(.)
    local filtered raw

    mkdir -p "${REPO_FIXTURE}/.env/common"
    printf 'secret\n' > "${REPO_FIXTURE}/.env/common/secret.md"
    repo_append_find_prune_args find_args
    find_args+=(-name '*.md' -type f -print)
    raw="$(
        cd "${REPO_FIXTURE}" || exit 1
        find "${find_args[@]}" 2> /dev/null | sed 's|^\./||' | sort
    )"
    filtered="$(
        cd "${REPO_FIXTURE}" || exit 1
        find "${find_args[@]}" 2> /dev/null | sed 's|^\./||' | repo_filter_paths | sort
    )"

    [[ ${raw} == *".env/common/secret.md"* ]]
    [[ ${filtered} != *".env/common/secret.md"* ]]
    [[ ${filtered} == *"docs/readme.md"* ]]
}

@test "repo_path_is_gitignored caches repeated lookups" {
    (
        cd "${REPO_FIXTURE}" || exit 1
        repo_path_should_skip "tmp/ignored.txt" || exit 1
        [[ ${REPO_PATHS_GITIGNORE_CACHE[__rp_tmp_ignored_D_txt]+set} == set ]]

        repo_path_should_skip "tmp/ignored.txt" || exit 1
        [[ ${REPO_PATHS_GITIGNORE_CACHE[__rp_tmp_ignored_D_txt]} -eq 1 ]]
    )
}
