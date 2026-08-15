#!/usr/bin/env bats

# Tests for github-actions-validation/scripts/lib/yaml_map_order.py (ORD-01)

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

setup() {
    ROOT="$(bats_workspace_root)"
    CHECKER="${ROOT}/scripts/lib/yaml_map_order.py"
    FIXTURE_DIR="${BATS_TEST_TMPDIR}/yaml_map_order"
    mkdir -p "${FIXTURE_DIR}"
}

@test "check passes when inputs block is alphabetically ordered" {
    cat > "${FIXTURE_DIR}/sorted.yml" << 'EOF'
on:
  workflow_call:
    inputs:
      alpha:
        type: string
      beta:
        type: string
EOF

    run python3 "${CHECKER}" check "${FIXTURE_DIR}/sorted.yml"
    [ "$status" -eq 0 ]
}

@test "check fails when inputs block is not alphabetically ordered" {
    cat > "${FIXTURE_DIR}/unsorted-inputs.yml" << 'EOF'
on:
  workflow_call:
    inputs:
      zebra:
        type: string
      alpha:
        type: string
EOF

    run python3 "${CHECKER}" check "${FIXTURE_DIR}/unsorted-inputs.yml"
    [ "$status" -eq 1 ]
    [[ $output == *"inputs block keys not alphabetically ordered"* ]]
}

@test "check fails when env block is not alphabetically ordered" {
    cat > "${FIXTURE_DIR}/unsorted-env.yml" << 'EOF'
jobs:
  test:
    runs-on: ubuntu-latest
    env:
      ZEBRA: "1"
      ALPHA: "2"
    steps:
      - run: echo ok
EOF

    run python3 "${CHECKER}" check "${FIXTURE_DIR}/unsorted-env.yml"
    [ "$status" -eq 1 ]
    [[ $output == *"env block keys not alphabetically ordered"* ]]
}

@test "check fails when with block is not alphabetically ordered" {
    cat > "${FIXTURE_DIR}/unsorted-with.yml" << 'EOF'
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: ./.github/actions/example
        with:
          zebra: "1"
          alpha: "2"
EOF

    run python3 "${CHECKER}" check "${FIXTURE_DIR}/unsorted-with.yml"
    [ "$status" -eq 1 ]
    [[ $output == *"with block keys not alphabetically ordered"* ]]
}

@test "check fails when permissions block has hyphenated keys out of order" {
    cat > "${FIXTURE_DIR}/unsorted-permissions.yml" << 'EOF'
permissions:
  pull-requests: write
  contents: read
  id-token: write
EOF

    run python3 "${CHECKER}" check "${FIXTURE_DIR}/unsorted-permissions.yml"
    [ "$status" -eq 1 ]
    [[ $output == *"permissions block keys not alphabetically ordered"* ]]
}

@test "check passes when permissions block hyphenated keys are ordered" {
    cat > "${FIXTURE_DIR}/sorted-permissions.yml" << 'EOF'
permissions:
  contents: read
  id-token: write
  pull-requests: write
EOF

    run python3 "${CHECKER}" check "${FIXTURE_DIR}/sorted-permissions.yml"
    [ "$status" -eq 0 ]
}

@test "fix reorders map keys and check passes afterward" {
    cat > "${FIXTURE_DIR}/to-fix.yml" << 'EOF'
on:
  workflow_call:
    inputs:
      zebra:
        type: string
      alpha:
        type: string
EOF

    run python3 "${CHECKER}" fix "${FIXTURE_DIR}/to-fix.yml"
    [ "$status" -eq 0 ]

    run python3 "${CHECKER}" check "${FIXTURE_DIR}/to-fix.yml"
    [ "$status" -eq 0 ]

    run awk '/^    inputs:/{flag=1; next} flag && /^      [a-zA-Z0-9_]+:/{sub(/^      /,""); sub(/:.*/,""); print; if (++n==2) exit}' "${FIXTURE_DIR}/to-fix.yml"
    [ "$output" == $'alpha\nzebra' ]
}
