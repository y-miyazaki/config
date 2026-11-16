#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154

# Tests for .github/actions/lib/loop/target_slug.sh
#
# Use cases:
# - target_slug_from_key normalizes colon to dash
# - target_slug_from_key differs for issue:1-2 and issue-1:2
# - target_slug_from_key truncates long keys to 32 chars plus hash
# - target_slug_from_key output passes git check-ref-format as branch suffix
# - target_slug_from_key strips leading and trailing dots
# - target_slug_from_key collapses double dots and rewrites a .lock ending
# - target_slug_from_key empty key prints nothing
# - target_slug_from_key uses the whole key when it has no '#'
# - target_slug_from_key output is ASCII-only and ref-safe under a UTF-8 locale

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

setup() {
    bats_source_rel ".github/actions/lib/loop/target_slug.sh"
}

@test "target_slug_from_key normalizes colon to dash" {
    run target_slug_from_key "repo#issue:12"
    [ "$status" -eq 0 ]
    [[ ${output} =~ ^issue-12-[0-9a-f]{8}$ ]]
}

@test "target_slug_from_key differs for issue:1-2 and issue-1:2" {
    local a b
    a="$(target_slug_from_key "issue:1-2")"
    b="$(target_slug_from_key "issue-1:2")"
    [ -n "${a}" ]
    [ "${a}" != "${b}" ]
}

@test "target_slug_from_key truncates long keys to 32 chars plus hash" {
    run target_slug_from_key "x#$(printf 'a%.0s' {1..80})"
    [ "$status" -eq 0 ]
    [[ ${output} =~ ^a{32}-[0-9a-f]{8}$ ]]
}

@test "target_slug_from_key output passes git check-ref-format as branch suffix" {
    local key
    for key in 'a#..x..' 'a#x.lock' 'a#.lock' 'a#a b/c~d^e' 'a#...' 'a#' "a#$(printf 'b%.0s' {1..40}).lock"; do
        run target_slug_from_key "${key}"
        [ "$status" -eq 0 ]
        [[ ${output} =~ ^[A-Za-z0-9._-]{1,48}$ ]]
        git check-ref-format "refs/heads/loop/skill/20261018-123456-${output}"
    done
}

@test "target_slug_from_key strips leading and trailing dots" {
    run target_slug_from_key "a#..x.."
    [[ ${output} =~ ^x-[0-9a-f]{8}$ ]]
}

@test "target_slug_from_key collapses double dots and rewrites a .lock ending" {
    run target_slug_from_key "a#x..y"
    [[ ${output} =~ ^x\.y-[0-9a-f]{8}$ ]]
    run target_slug_from_key "a#foo.lock"
    [[ ${output} =~ ^foo-lock-[0-9a-f]{8}$ ]]
}

@test "target_slug_from_key empty key prints nothing" {
    run target_slug_from_key ""
    [ "$status" -eq 0 ]
    [ -z "${output}" ]
}

@test "target_slug_from_key uses the whole key when it has no hash" {
    run target_slug_from_key "integration:main"
    [ "$status" -eq 0 ]
    [[ ${output} =~ ^integration-main-[0-9a-f]{8}$ ]]
}

@test "target_slug_from_key output is ASCII-only and ref-safe under a UTF-8 locale" {
    local key
    for key in 'a#あいう' 'a#é-ü_ñ' 'a#ÀÉ'; do
        run env LC_ALL=en_US.UTF-8 bash -c "source '$(bats_workspace_root)/.github/actions/lib/loop/target_slug.sh'; target_slug_from_key '${key}'"
        [ "$status" -eq 0 ]
        [[ ${output} =~ ^[A-Za-z0-9._-]+$ ]]
        LC_ALL=C grep -qv '[^ -~]' <<< "${output}"
        git check-ref-format "refs/heads/loop/skill/20261018-123456-${output}"
    done
}
