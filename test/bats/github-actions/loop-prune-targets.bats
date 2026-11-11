#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154

# Tests for .github/actions/loop-finalize/lib/prune_targets.sh

# Use cases:
# - integration old rejected: keep key, clear reject fields, reset consecutive_failures
# - integration with pending: unchanged
# - pull_request rejected aged: delete key
# - pull_request rejected recent: keep
# - pull_request with pending: keep even if terminal
# - pull_request pr_closed aged: delete
# - pull_request persisted old pr-closed aged: delete (same as pr_closed, via normalize_outcome)
# - integration persisted old pr-closed aged: cooldown same as pr_closed
# - non-terminal outcomes (pr_created, old pr-created, unchanged) aged: keep
# - missing last_run: keep
# - per-target hash key (integration:<branch>#<key>) aged without pending: delete regardless of outcome
# - per-target hash key with pending, within 30 days, or missing last_run: keep
# - plain integration key aged: kept (cooldown only), aged terminal pull_request key still deleted

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

setup() {
    bats_source_rel ".github/actions/loop-finalize/lib/prune_targets.sh"
}

@test "prune keeps hash key with missing last_run" {
    local state
    state="$(jq -nc '{
      targets: {
        "integration:main#issue:1": {outcome: "pr_created"}
      }
    }')"
    run prune_targets_json "${state}"
    [ "$status" -eq 0 ]
    run jq -e '.targets | has("integration:main#issue:1")' <<< "${output}"
    [ "$status" -eq 0 ]
}

@test "prune keeps hash key with pending" {
    local state old
    old="$(date -u -d '31 days ago' +%Y-%m-%dT00:00:00Z)"
    state="$(jq -nc --arg old "${old}" '{
      targets: {
        "integration:main#issue:1": {outcome: "pr_created", last_run: $old, pending: {sha: "def", pr: 1}}
      }
    }')"
    run prune_targets_json "${state}"
    [ "$status" -eq 0 ]
    run jq -e '.targets["integration:main#issue:1"].pending.pr == 1' <<< "${output}"
    [ "$status" -eq 0 ]
}

@test "prune keeps hash key within 30 days" {
    local state recent
    recent="$(date -u -d '1 day ago' +%Y-%m-%dT00:00:00Z)"
    state="$(jq -nc --arg recent "${recent}" '{
      targets: {
        "integration:main#issue:1": {outcome: "pr_created", last_run: $recent}
      }
    }')"
    run prune_targets_json "${state}"
    [ "$status" -eq 0 ]
    run jq -e '.targets | has("integration:main#issue:1")' <<< "${output}"
    [ "$status" -eq 0 ]
}

@test "prune keeps plain integration key even when aged" {
    local state old
    old="$(date -u -d '31 days ago' +%Y-%m-%dT00:00:00Z)"
    state="$(jq -nc --arg old "${old}" '{
      targets: {
        "integration:main": {outcome: "pr_created", last_run: $old, consecutive_failures: 1}
      }
    }')"
    run prune_targets_json "${state}"
    [ "$status" -eq 0 ]
    run jq -e '.targets["integration:main"].outcome == "pr_created" and .targets["integration:main"].consecutive_failures == 1' <<< "${output}"
    [ "$status" -eq 0 ]
}

@test "prune removes hash key when no pending and older than 30 days regardless of outcome" {
    local state old
    old="$(date -u -d '31 days ago' +%Y-%m-%dT00:00:00Z)"
    state="$(jq -nc --arg old "${old}" '{
      targets: {
        "integration:main#issue:1": {outcome: "pr_created", last_run: $old},
        "integration:main": {outcome: "pr_created", last_run: $old}
      }
    }')"
    run prune_targets_json "${state}"
    [ "$status" -eq 0 ]
    run jq -e '(.targets | has("integration:main#issue:1") | not) and (.targets | has("integration:main"))' <<< "${output}"
    [ "$status" -eq 0 ]
}

@test "prune still removes aged terminal pull_request key" {
    local state old
    old="$(date -u -d '31 days ago' +%Y-%m-%dT00:00:00Z)"
    state="$(jq -nc --arg old "${old}" '{
      targets: {
        "pull_request:5": {outcome: "pr_closed", last_run: $old}
      }
    }')"
    run prune_targets_json "${state}"
    [ "$status" -eq 0 ]
    run jq -e '.targets | has("pull_request:5") | not' <<< "${output}"
    [ "$status" -eq 0 ]
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

@test "prune_targets_json clears aged reject fields on integration key for old and new closed names" {
    local state outcome checked=0
    for outcome in pr_closed pr-closed; do
        state="$(jq -nc --arg outcome "${outcome}" '{
          targets: {
            "integration:main": {
              last_run: "2020-01-01T00:00:00Z",
              outcome: $outcome,
              consecutive_failures: 3,
              last_reject_reason: "closed"
            }
          }
        }')"
        run prune_targets_json "${state}"
        [ "$status" -eq 0 ]
        run jq -c '.targets["integration:main"]' <<< "${output}"
        [ "$output" = "{\"last_run\":\"2020-01-01T00:00:00Z\",\"outcome\":\"${outcome}\",\"consecutive_failures\":0}" ]
        checked=$((checked + 1))
    done
    [ "${checked}" -eq 2 ]
}

@test "prune_targets_json deletes aged pull_request key for old and new closed names" {
    local state outcome checked=0
    for outcome in pr_closed pr-closed; do
        state="$(jq -nc --arg outcome "${outcome}" '{
          targets: {
            "pull_request:265": {
              last_run: "2020-01-01T00:00:00Z",
              outcome: $outcome,
              consecutive_failures: 0
            }
          }
        }')"
        run prune_targets_json "${state}"
        [ "$status" -eq 0 ]
        [ "$output" = '{"targets":{}}' ]
        checked=$((checked + 1))
    done
    [ "${checked}" -eq 2 ]
}

@test "prune_targets_json keeps aged pull_request key for non-terminal outcomes" {
    local state outcome checked=0
    for outcome in pr_created pr-created pr_pushed unchanged no-changes; do
        state="$(jq -nc --arg outcome "${outcome}" '{
          targets: {
            "pull_request:7": {
              last_run: "2020-01-01T00:00:00Z",
              outcome: $outcome
            }
          }
        }')"
        run prune_targets_json "${state}"
        [ "$status" -eq 0 ]
        run jq -r '.targets["pull_request:7"].outcome' <<< "${output}"
        [ "$output" = "${outcome}" ]
        checked=$((checked + 1))
    done
    [ "${checked}" -eq 5 ]
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
