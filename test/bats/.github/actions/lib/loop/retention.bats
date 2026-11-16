#!/usr/bin/env bats

# Tests for .github/actions/lib/loop/retention.sh
#
# Use cases:
# - retention_cutoff_date returns a YYYY-MM-DD date 30 days in the past
# - the run log prune, the budget aggregation and the state prune all take their cutoff from retention_cutoff_date

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

setup() {
    bats_source_rel ".github/actions/lib/loop/retention.sh"
}

@test "retention_cutoff_date returns a YYYY-MM-DD date 30 days in the past" {
    local result expected
    result="$(retention_cutoff_date)"
    [[ ${result} =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]
    expected="$(date -u -d '30 days ago' +%Y-%m-%d)"
    [ "${result}" = "${expected}" ]
}

@test "the run log prune, the budget aggregation and the state prune all take their cutoff from retention_cutoff_date" {
    local root hits
    root="$(bats_workspace_root)/.github/actions"
    hits="$(grep -rnE "30 days ago|-v-30d" "${root}" | grep -v 'lib/loop/retention.sh' || true)"
    [ -z "${hits}" ]
}
