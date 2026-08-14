#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154

# Tests for .apm/packages/github/.apm/skills/github-issue-triage/scripts/label_fsm.sh
# (outside scripts/lib/ so sync_skill_lib.sh does not overwrite domain helpers)

# Use cases:
# - label_fsm_is_allowlisted accepts catalog labels and rejects unknown names
# - label_fsm_next_state opened event recommends needs-triage when unlabeled
# - label_fsm_next_state mark_ready removes triage labels and adds triage:ready

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

LABEL_FSM_LIB="${BATS_WORKSPACE_ROOT:-}/.apm/packages/github/.apm/skills/github-issue-triage/scripts/label_fsm.sh"
LABELS_JSON="${BATS_WORKSPACE_ROOT:-}/.apm/packages/github/.apm/skills/github-issue-triage/scripts/labels.json"

setup() {
    BATS_WORKSPACE_ROOT="$(bats_workspace_root)"
    LABEL_FSM_LIB="${BATS_WORKSPACE_ROOT}/.apm/packages/github/.apm/skills/github-issue-triage/scripts/label_fsm.sh"
    LABELS_JSON="${BATS_WORKSPACE_ROOT}/.apm/packages/github/.apm/skills/github-issue-triage/scripts/labels.json"
    # shellcheck disable=SC1090,SC1091
    source "${LABEL_FSM_LIB}"
    label_fsm_load_catalog "${LABELS_JSON}"
}

@test "allowlist includes needs-triage bug feature triage:needs-info triage:ready" {
    run label_fsm_is_allowlisted "triage:needs-info"
    [ "$status" -eq 0 ]
    run label_fsm_is_allowlisted "random-label"
    [ "$status" -eq 1 ]
}

@test "opened event recommends needs-triage when unlabeled" {
    run label_fsm_next_state '[]' opened
    [ "$status" -eq 0 ]
    run jq -e '.add | index("needs-triage") != null' <<< "${output}"
    [ "$status" -eq 0 ]
}

@test "ready transition removes needs-info and needs-triage" {
    run label_fsm_next_state '["needs-triage","triage:needs-info","bug"]' mark_ready
    [ "$status" -eq 0 ]
    run jq -e '
        (.add | index("triage:ready") != null)
        and (.remove | index("triage:needs-info") != null)
        and (.remove | index("needs-triage") != null)
    ' <<< "${output}"
    [ "$status" -eq 0 ]
}
