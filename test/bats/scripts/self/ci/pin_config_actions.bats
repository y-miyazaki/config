#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154

# Tests for scripts/self/ci/pin_config_actions.sh
#
# Use cases:
# - --help exits successfully
# - unknown options exit with an error
# - --dry-run completes without mutating an isolated repository
# - next_patch_tag increments the latest v-prefixed tag
# - an existing origin tag is refused before anything is pushed (unless --force-tag)
# - --help documents --force-tag
# - --pin-only pins to HEAD in one commit without creating a tag
# - --pin-only --dry-run leaves the tree untouched
# - a failing git commit aborts before anything is tagged or pushed
# - pin changes already staged in the index are committed, not skipped
# - unrelated staged files are not swept into the pin commit
# - a transient git commit failure is retried and the run still succeeds

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

PIN_SCRIPT="$(bats_workspace_root)/scripts/self/ci/pin_config_actions.sh"

setup() {
    git_test_repo_setup
}

@test "pin_config_actions --dry-run completes in an isolated repository" {
    mkdir -p "${GIT_TEST_REPO}/.github/workflows"
    cat > "${GIT_TEST_REPO}/.github/workflows/test.yaml" << 'EOF'
jobs:
  test:
    steps:
      - uses: y-miyazaki/config/.github/actions/example@c4ca6c4193026059c93c165fdff772bf894a1274 # v1.9.2
EOF
    git_test_repo_commit "add workflow"

    git_test_repo_run "bash '${PIN_SCRIPT}' --dry-run --no-push"
    [ "$status" -eq 0 ]
    [[ $output == *"Done."* ]]
    [[ $output == *"[dry-run]"* ]]
}

@test "pin_config_actions --help exits successfully" {
    run bash "${PIN_SCRIPT}" --help
    [ "$status" -eq 0 ]
    [[ $output == *"pin_config_actions.sh"* ]]
}

@test "next_patch_tag increments the latest patch version" {
    git_test_repo_commit "init"
    git -C "${GIT_TEST_REPO}" tag v1.2.3

    run bash -c "cd '${GIT_TEST_REPO}' && source '${PIN_SCRIPT}' && next_patch_tag"
    [ "$status" -eq 0 ]
    [ "$output" = "v1.2.4" ]
}

@test "pin_config_actions rejects unknown options" {
    run bash "${PIN_SCRIPT}" --unknown-option
    [ "$status" -eq 1 ]
    [[ $output == *"Unknown option"* ]]
}

@test "pin_config_actions refuses an existing origin tag before pushing anything" {
    local origin="${BATS_TEST_TMPDIR}/origin.git"
    git init -q --bare "${origin}"
    git_test_repo_commit "init"
    git_test_repo_git remote add origin "${origin}"
    git_test_repo_git branch -M main
    git_test_repo_git push -q origin main
    git_test_repo_git tag v9.9.9
    git_test_repo_git push -q origin v9.9.9
    local head_before
    head_before="$(git -C "${origin}" rev-parse main)"

    git_test_repo_run "bash '${PIN_SCRIPT}' v9.9.9"
    [ "$status" -eq 1 ]
    [[ $output == *"already exists on origin"* ]]
    [[ $output == *"--force-tag"* ]]
    [ "$(git -C "${origin}" rev-parse main)" = "${head_before}" ]
}

@test "pin_config_actions --help documents --force-tag" {
    run bash "${PIN_SCRIPT}" --help
    [ "$status" -eq 0 ]
    [[ $output == *"--force-tag"* ]]
}

@test "pin_config_actions --pin-only pins to HEAD in one commit without a tag" {
    mkdir -p "${GIT_TEST_REPO}/.github/workflows"
    cat > "${GIT_TEST_REPO}/.github/workflows/test.yaml" << 'EOF'
jobs:
  test:
    steps:
      - uses: y-miyazaki/config/.github/actions/example@c4ca6c4193026059c93c165fdff772bf894a1274 # v1.9.2
EOF
    git_test_repo_commit "add workflow"
    git_test_repo_git tag v1.0.0
    local head_before commits_before
    head_before="$(git -C "${GIT_TEST_REPO}" rev-parse HEAD)"
    commits_before="$(git -C "${GIT_TEST_REPO}" rev-list --count HEAD)"

    git_test_repo_run "bash '${PIN_SCRIPT}' --pin-only"
    [ "$status" -eq 0 ]
    grep -q "example@${head_before} # v1.0.0" "${GIT_TEST_REPO}/.github/workflows/test.yaml"
    [ "$(git -C "${GIT_TEST_REPO}" rev-list --count HEAD)" -eq $((commits_before + 1)) ]
    [ "$(git -C "${GIT_TEST_REPO}" tag -l | wc -l | tr -d ' ')" -eq 1 ]
}

@test "pin_config_actions --pin-only --dry-run leaves the tree untouched" {
    mkdir -p "${GIT_TEST_REPO}/.github/workflows"
    cat > "${GIT_TEST_REPO}/.github/workflows/test.yaml" << 'EOF'
jobs:
  test:
    steps:
      - uses: y-miyazaki/config/.github/actions/example@c4ca6c4193026059c93c165fdff772bf894a1274 # v1.9.2
EOF
    git_test_repo_commit "add workflow"
    git_test_repo_git tag v1.0.0
    local head_before
    head_before="$(git -C "${GIT_TEST_REPO}" rev-parse HEAD)"
    cp "${GIT_TEST_REPO}/.github/workflows/test.yaml" "${BATS_TEST_TMPDIR}/test.yaml.before"

    git_test_repo_run "bash '${PIN_SCRIPT}' --pin-only --dry-run"
    [ "$status" -eq 0 ]
    cmp -s "${BATS_TEST_TMPDIR}/test.yaml.before" "${GIT_TEST_REPO}/.github/workflows/test.yaml"
    [ "$(git -C "${GIT_TEST_REPO}" rev-parse HEAD)" = "${head_before}" ]
}

@test "pin_config_actions aborts without tagging or pushing when git commit fails" {
    mkdir -p "${GIT_TEST_REPO}/.github/workflows" "${BATS_TEST_TMPDIR}/shim"
    cat > "${GIT_TEST_REPO}/.github/workflows/test.yaml" << 'EOF'
jobs:
  test:
    steps:
      - uses: y-miyazaki/config/.github/actions/example@c4ca6c4193026059c93c165fdff772bf894a1274 # v1.9.2
EOF
    git_test_repo_commit "add workflow"
    local real_git
    real_git="$(command -v git)"
    cat > "${BATS_TEST_TMPDIR}/shim/git" << 'EOF'
#!/bin/bash
[[ $1 == commit ]] && exit 1
exec "${REAL_GIT}" "$@"
EOF
    chmod +x "${BATS_TEST_TMPDIR}/shim/git"

    git_test_repo_run "REAL_GIT='${real_git}' GIT_RETRY_DELAY=0 PATH='${BATS_TEST_TMPDIR}/shim':\$PATH bash '${PIN_SCRIPT}' v1.0.0"
    [ "$status" -ne 0 ]
    [[ $output == *"git commit failed"* ]]
    [ -z "$(git -C "${GIT_TEST_REPO}" tag -l)" ]
}

@test "pin_config_actions --pin-only commits pin changes that are already staged" {
    mkdir -p "${GIT_TEST_REPO}/.github/workflows"
    cat > "${GIT_TEST_REPO}/.github/workflows/test.yaml" << 'EOF2'
jobs:
  test:
    steps:
      - uses: y-miyazaki/config/.github/actions/example@c4ca6c4193026059c93c165fdff772bf894a1274 # v1.9.2
EOF2
    git_test_repo_commit "add workflow"
    git_test_repo_git tag v1.0.0
    local head_before commits_before
    head_before="$(git -C "${GIT_TEST_REPO}" rev-parse HEAD)"
    commits_before="$(git -C "${GIT_TEST_REPO}" rev-list --count HEAD)"
    sed -i.bak "s/@c4ca6c4193026059c93c165fdff772bf894a1274 # v1.9.2/@${head_before} # v1.0.0/" "${GIT_TEST_REPO}/.github/workflows/test.yaml"
    rm -f "${GIT_TEST_REPO}/.github/workflows/test.yaml.bak"
    git_test_repo_git add .github/workflows/test.yaml

    git_test_repo_run "bash '${PIN_SCRIPT}' --pin-only"
    [ "$status" -eq 0 ]
    [ -z "$(git -C "${GIT_TEST_REPO}" diff --cached --name-only)" ]
    [ "$(git -C "${GIT_TEST_REPO}" rev-list --count HEAD)" -eq $((commits_before + 1)) ]
}

@test "pin_config_actions --pin-only leaves unrelated staged files out of the pin commit" {
    mkdir -p "${GIT_TEST_REPO}/.github/workflows"
    cat > "${GIT_TEST_REPO}/.github/workflows/test.yaml" << 'EOF2'
jobs:
  test:
    steps:
      - uses: y-miyazaki/config/.github/actions/example@c4ca6c4193026059c93c165fdff772bf894a1274 # v1.9.2
EOF2
    echo one > "${GIT_TEST_REPO}/other.txt"
    git_test_repo_commit "add workflow"
    git_test_repo_git tag v1.0.0
    echo two > "${GIT_TEST_REPO}/other.txt"
    git_test_repo_git add other.txt

    git_test_repo_run "bash '${PIN_SCRIPT}' --pin-only"
    [ "$status" -eq 0 ]
    [ "$(git -C "${GIT_TEST_REPO}" diff --cached --name-only)" = "other.txt" ]
    [[ "$(git -C "${GIT_TEST_REPO}" show --name-only --format= HEAD)" != *other.txt* ]]
}

@test "pin_config_actions --pin-only retries a transient git commit failure" {
    mkdir -p "${GIT_TEST_REPO}/.github/workflows" "${BATS_TEST_TMPDIR}/shim"
    cat > "${GIT_TEST_REPO}/.github/workflows/test.yaml" << 'EOF2'
jobs:
  test:
    steps:
      - uses: y-miyazaki/config/.github/actions/example@c4ca6c4193026059c93c165fdff772bf894a1274 # v1.9.2
EOF2
    git_test_repo_commit "add workflow"
    git_test_repo_git tag v1.0.0
    local real_git commits_before
    real_git="$(command -v git)"
    commits_before="$(git -C "${GIT_TEST_REPO}" rev-list --count HEAD)"
    cat > "${BATS_TEST_TMPDIR}/shim/git" << 'EOF2'
#!/bin/bash
if [[ $1 == commit && ! -e "${FAIL_MARK}" ]]; then
    : > "${FAIL_MARK}"
    exit 1
fi
exec "${REAL_GIT}" "$@"
EOF2
    chmod +x "${BATS_TEST_TMPDIR}/shim/git"

    git_test_repo_run "FAIL_MARK='${BATS_TEST_TMPDIR}/failed' REAL_GIT='${real_git}' GIT_RETRY_DELAY=0 PATH='${BATS_TEST_TMPDIR}/shim':\$PATH bash '${PIN_SCRIPT}' --pin-only"
    [ "$status" -eq 0 ]
    [[ $output == *"retrying"* ]]
    [ "$(git -C "${GIT_TEST_REPO}" rev-list --count HEAD)" -eq $((commits_before + 1)) ]
}
