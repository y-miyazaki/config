#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154

# Tests for .github/actions/loop-finalize/lib/determine_outcome.sh
#
# Use cases:
# - an explicit override wins over every other input
# - a failed or cancelled agent job is error
# - no product diff is rejected on REJECT and unchanged otherwise, for every delivery
# - APPROVE with changes follows the delivery table: pr_create is pr_created,
#   pr_push is pr_pushed, none is reported
# - APPROVE with changes and an unknown or empty delivery is error (fail closed)
# - REJECT with changes is rejected; a missing verdict with changes is error
# - issue_comment is issue_commented and pr_review is pr_reviewed regardless of
#   has_changes and APPROVE/empty verdict
# - REJECT is rejected for issue_comment and pr_review
# - an override wins and a failed agent is error for issue_comment and pr_review

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

setup() {
    bats_source_rel ".github/actions/loop-finalize/lib/determine_outcome.sh"
}

@test "APPROVE with changes follows the delivery table" {
    local row delivery expected checked=0
    for row in "pr_create:pr_created" "pr_push:pr_pushed" "none:reported"; do
        delivery="${row%%:*}"
        expected="${row#*:}"
        run determine_outcome "" success true APPROVE "${delivery}"
        [ "$status" -eq 0 ]
        [ "$output" = "${expected}" ]
        checked=$((checked + 1))
    done
    [ "${checked}" -eq 3 ]
}

@test "APPROVE with changes is error for an unknown or empty delivery" {
    local delivery checked=0
    for delivery in "" open_pr push_head push; do
        run determine_outcome "" success true APPROVE "${delivery}"
        [ "$status" -eq 0 ]
        [ "$output" = "error" ]
        checked=$((checked + 1))
    done
    [ "${checked}" -eq 4 ]
}

@test "failed or cancelled agent job is error" {
    local r checked=0
    for r in failure cancelled; do
        run determine_outcome "" "$r" true APPROVE pr_create
        [ "$output" = "error" ]
        checked=$((checked + 1))
    done
    [ "${checked}" -eq 2 ]
}

@test "no product diff is rejected or unchanged for every delivery" {
    local delivery checked=0
    for delivery in pr_create pr_push none; do
        run determine_outcome "" success false REJECT "${delivery}"
        [ "$output" = "rejected" ]
        run determine_outcome "" success false APPROVE "${delivery}"
        [ "$output" = "unchanged" ]
        run determine_outcome "" skipped false "" "${delivery}"
        [ "$output" = "unchanged" ]
        checked=$((checked + 1))
    done
    [ "${checked}" -eq 3 ]
}

@test "override wins" {
    run determine_outcome watch failure true REJECT pr_create
    [ "$status" -eq 0 ]
    [ "$output" = "watch" ]
}

@test "REJECT with changes is rejected and a missing verdict is error" {
    run determine_outcome "" success true REJECT pr_push
    [ "$output" = "rejected" ]
    run determine_outcome "" success true "" pr_create
    [ "$output" = "error" ]
}

@test "REJECT is rejected for pr_review and issue_comment" {
    local delivery c checked=0
    for delivery in pr_review issue_comment; do
        for c in true false; do
            run determine_outcome "" success "$c" REJECT "${delivery}"
            [ "$status" -eq 0 ]
            [ "$output" = "rejected" ]
            checked=$((checked + 1))
        done
    done
    [ "${checked}" -eq 4 ]
}

@test "failed agent is error for issue_comment and pr_review" {
    local delivery r checked=0
    for delivery in issue_comment pr_review; do
        for r in failure cancelled; do
            run determine_outcome "" "$r" false APPROVE "${delivery}"
            [ "$output" = "error" ]
            checked=$((checked + 1))
        done
    done
    [ "${checked}" -eq 4 ]
}

@test "issue_comment and pr_review are issue_commented and pr_reviewed with or without changes" {
    local row delivery expected c v checked=0
    for row in "issue_comment:issue_commented" "pr_review:pr_reviewed"; do
        delivery="${row%%:*}"
        expected="${row#*:}"
        for c in true false; do
            for v in APPROVE ""; do
                run determine_outcome "" success "$c" "$v" "${delivery}"
                [ "$status" -eq 0 ]
                [ "$output" = "${expected}" ]
                checked=$((checked + 1))
            done
        done
    done
    [ "${checked}" -eq 8 ]
}

@test "override wins over issue_comment and pr_review" {
    run determine_outcome watch success true APPROVE issue_comment
    [ "$output" = "watch" ]
    run determine_outcome watch failure true REJECT pr_review
    [ "$output" = "watch" ]
}
