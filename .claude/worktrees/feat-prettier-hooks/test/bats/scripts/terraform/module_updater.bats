#!/usr/bin/env bats
# shellcheck disable=SC2016

# Tests for scripts/terraform/module_updater.sh
#
# Use cases:
# - extract_modules_from_file reads only top-level source/version of module blocks
# - update_module_version rewrites only modules whose source matches
# - update_module_version leaves nested attributes such as engine_version untouched
# - update_module_version fails and keeps the file when no module matches
# - find_terraform_project_root falls back to a clean directory path
# - CLI exits non-zero with usage when the directory argument is missing

TARGET_SCRIPT="${BATS_TEST_DIRNAME}/../../../../scripts/terraform/module_updater.sh"

setup() {
    FIXTURE_DIR="${BATS_TEST_TMPDIR}/project"
    mkdir -p "${FIXTURE_DIR}"
    cat > "${FIXTURE_DIR}/main.tf" << 'EOF'
module "a" {
  source         = "terraform-aws-modules/vpc/aws"
  engine_version = "3.0.0"
  tags           = { x = "${var.y}" }
  version        = "3.0.0"
}

module "b" {
  source  = "terraform-aws-modules/rds/aws"
  version = "3.0.0"
}
EOF
}

teardown() {
    rm -rf "${FIXTURE_DIR}"
}

# Run a function from the target script in an isolated shell (the script sets -e/trap on source)
run_fn() {
    run bash -c 'source "$1"; shift; BACKUP_DIR="${BATS_TEST_TMPDIR}/backup"; mkdir -p "$BACKUP_DIR"; "$@"' _ "${TARGET_SCRIPT}" "$@"
}

@test "cli exits non-zero with usage when directory is missing" {
    run bash "${TARGET_SCRIPT}"
    [ "$status" -eq 1 ]
    [[ $output == *"Terraform directory is required"* ]]
    [[ $output == *"Usage:"* ]]
}

@test "cli help exits zero" {
    run bash "${TARGET_SCRIPT}" --help
    [ "$status" -eq 0 ]
    [[ $output == *"Usage:"* ]]
}

@test "extract_modules_from_file ignores engine_version and reads top-level version" {
    run_fn extract_modules_from_file "${FIXTURE_DIR}/main.tf"
    [ "$status" -eq 0 ]
    [[ $output == *"terraform-aws-modules/vpc/aws||3.0.0||"* ]]
    [[ $output == *"terraform-aws-modules/rds/aws||3.0.0||"* ]]
    [ "$(echo "$output" | wc -l)" -eq 2 ]
}

@test "find_terraform_project_root fallback returns unquoted directory" {
    run_fn find_terraform_project_root "/nonexistent_dir/x/main.tf"
    [ "$status" -eq 0 ]
    [ "$output" = "/nonexistent_dir/x" ]
}

@test "update_module_version changes only the matching module" {
    run_fn update_module_version "${FIXTURE_DIR}/main.tf" "terraform-aws-modules/vpc/aws" "3.0.0" "4.1.0"
    [ "$status" -eq 0 ]
    run grep -c 'version *= *"4.1.0"' "${FIXTURE_DIR}/main.tf"
    [ "$output" = "1" ]
    # nested attribute and other module keep 3.0.0
    grep -q 'engine_version = "3.0.0"' "${FIXTURE_DIR}/main.tf"
    run grep -c '^  version *= *"3.0.0"' "${FIXTURE_DIR}/main.tf"
    [ "$output" = "1" ]
}

@test "update_module_version fails and keeps file when no module matches" {
    cp "${FIXTURE_DIR}/main.tf" "${BATS_TEST_TMPDIR}/before.tf"
    run_fn update_module_version "${FIXTURE_DIR}/main.tf" "nonexistent/x/aws" "3.0.0" "4.1.0"
    [ "$status" -eq 1 ]
    diff "${BATS_TEST_TMPDIR}/before.tf" "${FIXTURE_DIR}/main.tf"
}
