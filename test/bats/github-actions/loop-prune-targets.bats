#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154

# Tests for .github/actions/loop-finalize/lib/prune_targets.sh

# Use cases:
# - integration old rejected: keep key, clear reject fields, reset consecutive_failures
# - integration with pending: unchanged
# - pull_request rejected aged: delete key
# - pull_request rejected recent: keep
# - pull_request with pending: keep even if terminal
# - pull_request pr-closed aged: delete
# - missing last_run: keep

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

setup() {
    bats_source_rel ".github/actions/loop-finalize/lib/prune_targets.sh"
}

@test "prune_targets_json clears aged reject fields on integration key" {
    local state out cutoff old
    cutoff="$(prune_targets_cutoff_date)"
    old="2020-01-01T00:00:00Z"
    state="$(jq -nc --arg old "${old}" '{
      targets: {
        "integration:main": {
          last_sha: "abc",
          last_run: $old,
          outcome: "rejected",
          consecutive_failures: 2,
          last_reject_reason: "no changes",
          open_rejections: [{"issue":"x"}]
        }
      }
    }')"
    run prune_targets_json "${state}"
    [ "$status" -eq 0 ]
    out="${output}"
    run jq -e '
      .targets["integration:main"].last_sha == "abc"
      and .targets["integration:main"].consecutive_failures == 0
      and (.targets["integration:main"]|has("last_reject_reason")|not)
      and (.targets["integration:main"]|has("open_rejections")|not)
      and .targets["integration:main"].outcome == "rejected"
    ' <<< "${out}"
    [ "$status" -eq 0 ]
    [[ -n ${cutoff} ]]
}

@test "prune_targets_json keeps integration pending unchanged" {
    local state out
    state="$(jq -nc '{
      targets: {
        "integration:main": {
          last_sha: "abc",
          last_run: "2020-01-01T00:00:00Z",
          outcome: "pr-created",
          consecutive_failures: 0,
          pending: {sha: "def", pr: 1}
        }
      }
    }')"
    run prune_targets_json "${state}"
    [ "$status" -eq 0 ]
    out="${output}"
    run jq -e '.targets["integration:main"].pending.pr == 1 and .targets["integration:main"].last_sha == "abc"' <<< "${out}"
    [ "$status" -eq 0 ]
}

@test "prune_targets_json deletes aged rejected pull_request key" {
    local state
    state="$(jq -nc '{
      targets: {
        "pull_request:355": {
          last_run: "2020-01-01T00:00:00Z",
          outcome: "rejected",
          consecutive_failures: 1,
          last_reject_reason: "No file changes produced"
        }
      }
    }')"
    run prune_targets_json "${state}"
    [ "$status" -eq 0 ]
    run jq -e '(.targets|has("pull_request:355")|not)' <<< "${output}"
    [ "$status" -eq 0 ]
}

@test "prune_targets_json keeps recent rejected pull_request key" {
    local state recent
    recent="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    state="$(jq -nc --arg recent "${recent}" '{
      targets: {
        "pull_request:401": {
          last_run: $recent,
          outcome: "rejected",
          consecutive_failures: 1
        }
      }
    }')"
    run prune_targets_json "${state}"
    [ "$status" -eq 0 ]
    run jq -e '.targets["pull_request:401"].outcome == "rejected"' <<< "${output}"
    [ "$status" -eq 0 ]
}

@test "prune_targets_json keeps pull_request with pending even if terminal aged" {
    local state
    state="$(jq -nc '{
      targets: {
        "pull_request:99": {
          last_run: "2020-01-01T00:00:00Z",
          outcome: "rejected",
          pending: {sha: "x", pr: 99}
        }
      }
    }')"
    run prune_targets_json "${state}"
    [ "$status" -eq 0 ]
    run jq -e '.targets["pull_request:99"].pending.pr == 99' <<< "${output}"
    [ "$status" -eq 0 ]
}

@test "prune_targets_json deletes aged pr-closed pull_request key" {
    local state
    state="$(jq -nc '{
      targets: {
        "pull_request:265": {
          last_run: "2020-01-01T00:00:00Z",
          outcome: "pr-closed",
          consecutive_failures: 0
        }
      }
    }')"
    run prune_targets_json "${state}"
    [ "$status" -eq 0 ]
    run jq -e '(.targets|has("pull_request:265")|not)' <<< "${output}"
    [ "$status" -eq 0 ]
}

@test "prune_targets_json keeps entry when last_run missing" {
    local state
    state="$(jq -nc '{
      targets: {
        "pull_request:1": {
          outcome: "rejected",
          consecutive_failures: 1
        }
      }
    }')"
    run prune_targets_json "${state}"
    [ "$status" -eq 0 ]
    run jq -e '.targets["pull_request:1"].outcome == "rejected"' <<< "${output}"
    [ "$status" -eq 0 ]
}
