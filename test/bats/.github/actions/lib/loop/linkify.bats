#!/usr/bin/env bats
# shellcheck disable=SC2016,SC2030,SC2031,SC2034,SC2154

# Tests for .github/actions/lib/loop/linkify.sh
#
# Use cases:
# - linkify_repo_text links tracked paths in code spans and plain text
# - linkify_repo_text turns #L and :N suffixes into line anchors
# - linkify_repo_text links a bare file name only when it is unique
# - linkify_repo_text leaves untracked paths, links, URLs, comments, and fences alone
# - linkify_repo_text is a no-op without a repository, a ref, or tracked files

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

setup() {
    bats_source_rel ".github/actions/lib/loop/linkify.sh"
    git_test_repo_setup
    mkdir -p "${GIT_TEST_REPO}/docs/specs" "${GIT_TEST_REPO}/lib" "${GIT_TEST_REPO}/other"
    : > "${GIT_TEST_REPO}/docs/specs/design.md"
    : > "${GIT_TEST_REPO}/lib/created_by.sh"
    : > "${GIT_TEST_REPO}/lib/dup.sh"
    : > "${GIT_TEST_REPO}/other/dup.sh"
    git_test_repo_commit "files"
    REF="$(git -C "${GIT_TEST_REPO}" rev-parse HEAD)"
    export GITHUB_REPOSITORY="o/r" GITHUB_SERVER_URL="https://github.com"
}

linkify() {
    (cd "${GIT_TEST_REPO}" && env -u GIT_DIR -u GIT_WORK_TREE bash -c "source '$(bats_workspace_root)/.github/actions/lib/loop/linkify.sh' && linkify_repo_text \"\$1\" \"\$2\"" _ "$1" "$2")
}

@test "linkify_repo_text links tracked paths in code spans and plain text" {
    run linkify 'See `docs/specs/design.md` and docs/specs/design.md.' "${REF}"
    [ "$status" -eq 0 ]
    [[ $output == *'[`docs/specs/design.md`](https://github.com/o/r/blob/'"${REF}"'/docs/specs/design.md)'* ]]
    [[ $output == *'[docs/specs/design.md](https://github.com/o/r/blob/'"${REF}"'/docs/specs/design.md).'* ]]
}

@test "linkify_repo_text turns line suffixes into anchors" {
    run linkify 'at lib/created_by.sh#L12-L20 and `lib/created_by.sh:7`' "${REF}"
    [[ $output == *'/blob/'"${REF}"'/lib/created_by.sh#L12-L20)'* ]]
    [[ $output == *'/blob/'"${REF}"'/lib/created_by.sh#L7)'* ]]
}

@test "linkify_repo_text links a bare file name only when it is unique" {
    run linkify 'created_by.sh and dup.sh' "${REF}"
    [[ $output == *'[created_by.sh](https://github.com/o/r/blob/'"${REF}"'/lib/created_by.sh)'* ]]
    [[ $output == *' and dup.sh' ]]
}

@test "linkify_repo_text leaves untracked paths, links, URLs, comments, and fences alone" {
    local input
    input=$'<!-- docs/specs/design.md -->\nmissing/file.md and [x](docs/specs/design.md)\nhttps://example.com/docs/specs/design.md\n```\ndocs/specs/design.md\n```\n`run docs/specs/design.md now`'
    run linkify "${input}" "${REF}"
    [ "$status" -eq 0 ]
    [ "$output" = "${input}" ]
}

@test "linkify_repo_text is a no-op without a repository, a ref, or tracked files" {
    GITHUB_REPOSITORY="" run linkify 'docs/specs/design.md' "${REF}"
    [ "$output" = 'docs/specs/design.md' ]
    run linkify 'docs/specs/design.md' ""
    [ "$output" = 'docs/specs/design.md' ]
    run linkify 'docs/specs/design.md' "0000000000000000000000000000000000000000"
    [ "$output" = 'docs/specs/design.md' ]
}
