#!/usr/bin/env bats
# shellcheck disable=SC2154

# Tests for scripts/terraform/aws_*.sh, scripts/go/build.sh, scripts/go/deploy.sh, scripts/go/clean_binaries.sh
#
# Use cases:
# - --help exits 0 for scripts whose show_usage is also used on error paths
# - missing required arguments exit non-zero (show_usage 1), not 0
# - value options without a value fail with a clear message
# - clean_binaries refuses unsafe root directories

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

SCRIPTS_DIR="$(bats_workspace_root)/scripts"

@test "clean_binaries refuses the filesystem root" {
    run bash "${SCRIPTS_DIR}/go/clean_binaries.sh" --dry-run /
    [ "$status" -ne 0 ]
    [[ $output == *"Refusing to clean unsafe root directory"* ]]
}

@test "clean_binaries refuses the home directory" {
    run env HOME="${BATS_TEST_TMPDIR}" bash "${SCRIPTS_DIR}/go/clean_binaries.sh" --dry-run "${BATS_TEST_TMPDIR}"
    [ "$status" -ne 0 ]
    [[ $output == *"Refusing to clean unsafe root directory"* ]]
}

@test "deploy-style scripts exit 0 for --help" {
    local script
    for script in terraform/aws_deploy_sam.sh terraform/aws_deploy_ecs_service.sh terraform/aws_deploy_ecs_scheduled_task.sh terraform/aws_upload_ecr.sh terraform/aws_get_vpc_info.sh go/build.sh go/deploy.sh; do
        run bash "${SCRIPTS_DIR}/${script}" --help
        [ "$status" -eq 0 ]
    done
}

@test "deploy-style scripts exit non-zero when required arguments are missing" {
    local script
    for script in terraform/aws_deploy_sam.sh terraform/aws_deploy_ecs_service.sh terraform/aws_deploy_ecs_scheduled_task.sh terraform/aws_upload_ecr.sh terraform/aws_get_vpc_info.sh go/build.sh go/deploy.sh; do
        run bash "${SCRIPTS_DIR}/${script}"
        [ "$status" -ne 0 ]
    done
}

@test "value options without a value fail with a clear message" {
    run bash "${SCRIPTS_DIR}/terraform/aws_deploy_sam.sh" --path
    [ "$status" -ne 0 ]
    [[ $output == *"requires a value"* ]]
}
