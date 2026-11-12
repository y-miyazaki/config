#!/usr/bin/env bats

# Tests for .github/actions/lib/loop/state_snapshot.sh
#
# Use cases:
# - state_snapshot_from_branch copies files from origin/<state_branch>, not from the checked-out tree
# - state_snapshot_from_branch copies several files with one fetch
# - state_snapshot_from_branch leaves a destination absent when the branch has no such file
# - state_snapshot_from_branch rejects an invalid branch name and odd file/destination pairs
# - state_snapshot_from_branch falls back to the local copies with a warning when the fetch fails

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

setup() {
    bats_source_rel ".github/actions/lib/loop/check_names.sh"
    bats_source_rel ".github/actions/lib/loop/state_snapshot.sh"
    SNAP_BARE="${BATS_TEST_TMPDIR}/origin.git"
    SNAP_WORK="${BATS_TEST_TMPDIR}/work"
    git init -q --bare -b main "${SNAP_BARE}"
    git clone -q "${SNAP_BARE}" "${SNAP_WORK}" 2> /dev/null
    git -C "${SNAP_WORK}" config user.email "t@example.com"
    git -C "${SNAP_WORK}" config user.name "t"
    git -C "${SNAP_WORK}" checkout -q -b main
    mkdir -p "${SNAP_WORK}/.loop"
    printf '{"targets":{"pull_request:7":{"consecutive_failures":0}}}\n' > "${SNAP_WORK}/.loop/state-x.json"
    printf 'old log\n' > "${SNAP_WORK}/.loop/loop-run-log.md"
    git -C "${SNAP_WORK}" add -A
    git -C "${SNAP_WORK}" commit -q -m "init"
    git -C "${SNAP_WORK}" push -q origin main
    git -C "${SNAP_WORK}" checkout -q -b feature/pr-head
    # The authoritative state advances on main after the PR head forked.
    git -C "${SNAP_WORK}" checkout -q main
    printf '{"targets":{"pull_request:7":{"consecutive_failures":3}}}\n' > "${SNAP_WORK}/.loop/state-x.json"
    printf 'new log\n' > "${SNAP_WORK}/.loop/loop-run-log.md"
    git -C "${SNAP_WORK}" commit -q -am "state"
    git -C "${SNAP_WORK}" push -q origin main
    git -C "${SNAP_WORK}" checkout -q feature/pr-head
    cd "${SNAP_WORK}"
}

@test "state_snapshot_from_branch copies files from origin state branch, not from the checked-out tree" {
    run state_snapshot_from_branch main ".loop/state-x.json" "${BATS_TEST_TMPDIR}/snap.json"
    [ "$status" -eq 0 ]
    [ "$(jq -r '.targets["pull_request:7"].consecutive_failures' "${BATS_TEST_TMPDIR}/snap.json")" = "3" ]
    # The stale tracked copy on the PR head is untouched and not what was read.
    [ "$(jq -r '.targets["pull_request:7"].consecutive_failures' .loop/state-x.json)" = "0" ]
}

@test "state_snapshot_from_branch copies several files with one fetch" {
    local bin="${BATS_TEST_TMPDIR}/bin" count_file="${BATS_TEST_TMPDIR}/fetches"
    mkdir -p "${bin}"
    printf '#!/bin/bash\nif [[ $1 == fetch ]]; then echo x >> "%s"; fi\nexec %s "$@"\n' "${count_file}" "$(command -v git)" > "${bin}/git"
    chmod +x "${bin}/git"
    PATH="${bin}:${PATH}" run state_snapshot_from_branch main \
        ".loop/state-x.json" "${BATS_TEST_TMPDIR}/s.json" \
        ".loop/loop-run-log.md" "${BATS_TEST_TMPDIR}/l.md"
    [ "$status" -eq 0 ]
    [ "$(cat "${BATS_TEST_TMPDIR}/l.md")" = "new log" ]
    [ "$(wc -l < "${count_file}")" -eq 1 ]
}

@test "state_snapshot_from_branch leaves a destination absent when the branch has no such file" {
    : > "${BATS_TEST_TMPDIR}/snap.json"
    run state_snapshot_from_branch main ".loop/state-missing.json" "${BATS_TEST_TMPDIR}/snap.json"
    [ "$status" -eq 0 ]
    [ ! -e "${BATS_TEST_TMPDIR}/snap.json" ]
}

@test "state_snapshot_from_branch rejects an invalid branch name and odd file/destination pairs" {
    run state_snapshot_from_branch "--upload-pack=x" ".loop/state-x.json" "${BATS_TEST_TMPDIR}/snap.json"
    [ "$status" -eq 1 ]
    [[ $output == *"Invalid state branch"* ]]
    run state_snapshot_from_branch main ".loop/state-x.json"
    [ "$status" -eq 1 ]
    [[ $output == *"pairs"* ]]
}

@test "state_snapshot_from_branch falls back to the local copies with a warning when the fetch fails" {
    run state_snapshot_from_branch no-such-branch ".loop/state-x.json" "${BATS_TEST_TMPDIR}/snap.json"
    [ "$status" -eq 0 ]
    [[ $output == *"could not fetch"* ]]
    [ "$(jq -r '.targets["pull_request:7"].consecutive_failures' "${BATS_TEST_TMPDIR}/snap.json")" = "0" ]
}
