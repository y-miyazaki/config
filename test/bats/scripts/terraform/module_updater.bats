#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154

# Tests for scripts/terraform/module_updater.sh

# Use cases:
# - artifact_dir_for creates sanitized directory path
# - artifact_dir_for strips leading slash and replaces separators
# - extract_modules_from_file extracts source and version pairs
# - extract_modules_from_file ignores local modules without version
# - find_terraform_modules finds files with module declarations
# - find_terraform_project_root finds directory with versions.tf
# - process_modules_in_terraform_file lists modules in check-only mode
# - cleanup_transient_terraform_plan_logs removes workspace plan artifacts
# - compare_terraform_plan_artifacts returns 0 when rendered plans match
# - compare_terraform_plan_artifacts returns 1 when rendered plans differ
# - report_terraform_plan_differences warns without detailed diff when verbose is disabled

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

setup() {
    # Minimal globals required by module_updater.sh
    export VERBOSE=false
    export DRY_RUN=false
    export CHECK_ONLY=false
    export RECURSIVE_SEARCH=false
    export TERRAFORM_DIR=""
    export DEFAULT_ENV="dev"
    export NO_PLAN=false
    export TOTAL_MODULES=0
    export UPDATED_MODULES=0
    export FAILED_MODULES=0
    export CURRENT_FILE_BEING_SCANNED=""

    bats_source_rel "scripts/lib/all.sh"
    bats_source_rel "scripts/terraform/module_updater.sh" 2> /dev/null || true

    # Create temp directory for test fixtures
    TEST_TMPDIR=$(mktemp -d)
    export BACKUP_DIR="$TEST_TMPDIR/backups"
    mkdir -p "$BACKUP_DIR"
}

teardown() {
    rm -rf "${TEST_TMPDIR:-}"
}

@test "artifact_dir_for creates sanitized directory path" {
    run artifact_dir_for "/workspace/terraform/base"
    [ "$status" -eq 0 ]
    [[ $output == *"workspace__terraform__base"* ]]
}

@test "artifact_dir_for strips leading slash and replaces separators" {
    run artifact_dir_for "/a/b/c"
    [ "$status" -eq 0 ]
    [[ $output == *"a__b__c"* ]]
}

@test "cleanup_transient_terraform_plan_logs removes workspace plan artifacts" {
    local workspace_dir="${TEST_TMPDIR}/workspace"
    mkdir -p "${workspace_dir}"
    cd "${workspace_dir}" || return 1
    touch .terraform_baseline.plan .terraform_current.log .terraform_validate.log

    cleanup_transient_terraform_plan_logs

    [ ! -f .terraform_baseline.plan ]
    [ ! -f .terraform_current.log ]
    [ ! -f .terraform_validate.log ]
}

@test "compare_terraform_plan_artifacts returns 0 when rendered plans match" {
    local artifacts workspace_dir
    artifacts="${TEST_TMPDIR}/artifacts"
    workspace_dir="${TEST_TMPDIR}/workspace"
    mkdir -p "${artifacts}" "${workspace_dir}"

    printf 'plan-a\n' > "${artifacts}/.terraform_baseline.plan"
    cp "${artifacts}/.terraform_baseline.plan" "${artifacts}/.terraform_current.plan"

    MOCK_BIN="${TEST_TMPDIR}/bin"
    mkdir -p "${MOCK_BIN}"
    cat > "${MOCK_BIN}/terraform" << EOF
#!/usr/bin/env bash
if [[ "\$1" == "show" ]]; then
    cat "\${3}"
    exit 0
fi
exit 1
EOF
    chmod +x "${MOCK_BIN}/terraform"
    export PATH="${MOCK_BIN}:${PATH}"

    artifact_dir_for() {
        printf '%s' "${artifacts}"
    }

    cd "${workspace_dir}" || return 1
    run compare_terraform_plan_artifacts
    [ "$status" -eq 0 ]
}

@test "compare_terraform_plan_artifacts returns 1 when rendered plans differ" {
    local artifacts workspace_dir
    artifacts="${TEST_TMPDIR}/artifacts-diff"
    workspace_dir="${TEST_TMPDIR}/workspace-diff"
    mkdir -p "${artifacts}" "${workspace_dir}"

    printf 'plan-a\n' > "${artifacts}/.terraform_baseline.plan"
    printf 'plan-b\n' > "${artifacts}/.terraform_current.plan"

    MOCK_BIN="${TEST_TMPDIR}/bin-diff"
    mkdir -p "${MOCK_BIN}"
    cat > "${MOCK_BIN}/terraform" << EOF
#!/usr/bin/env bash
if [[ "\$1" == "show" ]]; then
    cat "\${3}"
    exit 0
fi
exit 1
EOF
    chmod +x "${MOCK_BIN}/terraform"
    export PATH="${MOCK_BIN}:${PATH}"

    artifact_dir_for() {
        printf '%s' "${artifacts}"
    }

    cd "${workspace_dir}" || return 1
    run compare_terraform_plan_artifacts
    [ "$status" -eq 1 ]
}

@test "extract_modules_from_file extracts source and version pairs" {
    cat > "$TEST_TMPDIR/test.tf" << 'EOF'
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.1.0"

  name = "my-vpc"
}
EOF

    run extract_modules_from_file "$TEST_TMPDIR/test.tf"
    [ "$status" -eq 0 ]
    [[ $output == *"terraform-aws-modules/vpc/aws"* ]]
    [[ $output == *"5.1.0"* ]]
}

@test "extract_modules_from_file ignores local modules without version" {
    cat > "$TEST_TMPDIR/local.tf" << 'EOF'
module "internal" {
  source = "../../modules/aws/budgets/create"

  name = "test"
}
EOF

    run extract_modules_from_file "$TEST_TMPDIR/local.tf"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "find_terraform_modules finds files with module declarations" {
    mkdir -p "$TEST_TMPDIR/project"
    cat > "$TEST_TMPDIR/project/main.tf" << 'EOF'
module "test" {
  source = "example/module/aws"
  version = "1.0.0"
}
EOF

    run find_terraform_modules "$TEST_TMPDIR/project"
    [ "$status" -eq 0 ]
    [[ $output == *"main.tf"* ]]
}

@test "find_terraform_project_root finds directory with versions.tf" {
    mkdir -p "$TEST_TMPDIR/root/sub"
    touch "$TEST_TMPDIR/root/versions.tf"
    touch "$TEST_TMPDIR/root/sub/main.tf"

    run find_terraform_project_root "$TEST_TMPDIR/root/sub/main.tf"
    [ "$status" -eq 0 ]
    [[ $output == *"$TEST_TMPDIR/root"* ]]
}

@test "process_modules_in_terraform_file lists modules in check-only mode" {
    CHECK_ONLY=true
    mkdir -p "$TEST_TMPDIR/project"
    cat > "$TEST_TMPDIR/project/main.tf" << 'EOF'
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.1.0"
}
EOF

    run process_modules_in_terraform_file "$TEST_TMPDIR/project/main.tf"
    [ "$status" -eq 0 ]
    [[ $output == *"Found: terraform-aws-modules/vpc/aws (current: 5.1.0)"* ]]
}

@test "report_terraform_plan_differences warns without detailed diff when verbose is disabled" {
    local artifacts
    artifacts="${TEST_TMPDIR}/artifacts-report"
    mkdir -p "${artifacts}"
    printf 'baseline\n' > "${artifacts}/.terraform_baseline.txt"
    printf 'current\n' > "${artifacts}/.terraform_current.txt"
    VERBOSE=false

    run report_terraform_plan_differences "${artifacts}"
    [ "$status" -eq 0 ]
    [[ $output == *"Infrastructure changes detected between baseline and current plan"* ]]
    [[ $output != *"TERRAFORM SHOW DIFFERENCES DETECTED"* ]]
}
