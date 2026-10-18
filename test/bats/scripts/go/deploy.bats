#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2154

# Tests for scripts/go/deploy.sh
#
# Use cases:
# - show_usage prints the error message and exits 1 when given one
# - show_usage exits 0 when called without an error message
# - validate_arguments exits via show_usage when the stage is empty
# - validate_arguments accepts a non-empty stage without exiting
# - main prints usage and exits 0 for -h/--help
# - main exits 1 when the stage argument is missing
# - main completes the full deploy flow successfully in dry-run mode

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

DEPLOY_SCRIPT="$(bats_workspace_root)/scripts/go/deploy.sh"

@test "deploy.sh main completes successfully in dry-run mode" {
    run bash -c "DRY_RUN=true bash '${DEPLOY_SCRIPT}' dev"
    [ "$status" -eq 0 ]
    [[ $output == *"Deploying to AWS (dev)"* ]]
    [[ $output == *"Deployment completed successfully!"* ]]
}

@test "deploy.sh main exits 1 when the stage argument is missing" {
    run bash -c "bash '${DEPLOY_SCRIPT}'"
    [ "$status" -eq 1 ]
    [[ $output == *"Stage argument is required"* ]]
}

@test "deploy.sh main prints usage and exits 0 for --help" {
    run bash -c "bash '${DEPLOY_SCRIPT}' --help"
    [ "$status" -eq 0 ]
    [[ $output == *"Usage:"* ]]
}

@test "show_usage exits 0 when called without an error message" {
    run bash -c "source '${DEPLOY_SCRIPT}' && show_usage"
    [ "$status" -eq 0 ]
    [[ $output == *"Usage:"* ]]
}

@test "show_usage prints the error message and exits 1 with a message" {
    run bash -c "source '${DEPLOY_SCRIPT}' && show_usage 'boom'"
    [ "$status" -eq 1 ]
    [[ $output == *"Error: boom"* ]]
}

@test "validate_arguments accepts a non-empty stage without exiting" {
    run bash -c "source '${DEPLOY_SCRIPT}' && validate_arguments 'dev' && echo ok"
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "validate_arguments exits via show_usage when the stage is empty" {
    run bash -c "source '${DEPLOY_SCRIPT}' && validate_arguments ''"
    [ "$status" -eq 1 ]
    [[ $output == *"Stage argument is required"* ]]
}
