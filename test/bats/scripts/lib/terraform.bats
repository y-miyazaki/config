#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154,SC2329

# Tests for scripts/lib/terraform.sh

# Use cases:
# - terraform_apply uses plan file when provided (dry-run)
# - terraform_apply without plan uses var file (dry-run)
# - terraform_destroy uses var file (dry-run)
# - terraform_apply places auto-approve before the plan file
# - terraform_apply errors when an explicit plan file does not exist
# - terraform_lint returns 1 on failure so the caller keeps running
# - terraform_validate returns 1 on failure so the caller keeps running
# - terraform_workflow aborts before apply when validation fails
# - validate_terraform_env accepts an explicit environment when ENV is unset
# - terraform_format check mode returns 0 in dry-run
# - terraform_format non-check runs in dry-run mode
# - terraform_get_workspace falls back to default when terraform not available
# - terraform_init succeeds when backend config file exists (dry-run)
# - terraform_plan succeeds when var file exists (dry-run)
# - terraform_select_workspace creates workspace when select fails (dry-run)
# - terraform_select_workspace errors when no name provided
# - terraform_apply passes a plan file path with spaces and shell metacharacters as one argument
# - terraform_plan splits additional options into separate arguments and keeps the plan path intact
# - validate_terraform_env rejects an environment name with shell metacharacters

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

setup() {
    bats_source_rel "scripts/lib/terraform.sh"
}

@test "terraform_apply uses plan file when provided (dry-run)" {
    DRY_RUN=true
    run terraform_format check
    [ "$status" -eq 0 ]
    [[ $output == *"DRY-RUN: Would execute: terraform fmt -check -diff"* ]]
}

@test "terraform_apply without plan uses var file (dry-run)" {
    DRY_RUN=true
    run terraform_format
    [ "$status" -eq 0 ]
    [[ $output == *"DRY-RUN: Would execute: terraform fmt -recursive"* ]]
}

@test "terraform_destroy uses var file (dry-run)" {
    ENV=testenv
    backend_file="terraform.${ENV}.tfbackend"
    echo "backend" > "$backend_file"
    DRY_RUN=true
    run terraform_init "$ENV"
    [ "$status" -eq 0 ]
    rm -f "$backend_file"
}

@test "terraform_format check mode returns 0 in dry-run" {
    ENV=testenv
    var_file="terraform.${ENV}.tfvars"
    echo "var = 1" > "$var_file"
    DRY_RUN=true
    run terraform_plan "$ENV" "plan.out"
    [ "$status" -eq 0 ]
    rm -f "$var_file" "plan.out"
}

@test "terraform_format non-check runs in dry-run mode" {
    tmpplan=$(mktemp)
    DRY_RUN=true
    run terraform_apply testenv "$tmpplan" "auto-approve"
    [ "$status" -eq 0 ]
    rm -f "$tmpplan"
}

@test "terraform_get_workspace falls back to default when terraform not available" {
    ENV=testenv
    var_file="terraform.${ENV}.tfvars"
    echo "var = 1" > "$var_file"
    DRY_RUN=true
    run terraform_apply "$ENV" "" "auto-approve"
    [ "$status" -eq 0 ]
    rm -f "$var_file"
}

@test "terraform_init succeeds when backend config file exists (dry-run)" {
    ENV=testenv
    var_file="terraform.${ENV}.tfvars"
    echo "var = 1" > "$var_file"
    DRY_RUN=true
    run terraform_destroy "$ENV" "auto-approve"
    [ "$status" -eq 0 ]
    rm -f "$var_file"
}

@test "terraform_plan succeeds when var file exists (dry-run)" {
    run terraform_get_workspace
    [ "$status" -eq 0 ]
    [ "$output" = "default" ]
}

@test "terraform_select_workspace creates workspace when select fails (dry-run)" {
    DRY_RUN=true
    run terraform_select_workspace "ci-test-ws"
    [ "$status" -eq 0 ]
    [[ $output == *"DRY-RUN: Would execute: terraform workspace new ci-test-ws"* ]]
}

@test "terraform_select_workspace errors when no name provided" {
    run terraform_select_workspace ""
    [ "$status" -ne 0 ]
    [[ $output == *"Workspace name is required"* ]]
}

@test "terraform_apply places auto-approve before the plan file" {
    DRY_RUN=true
    touch plan.out
    run terraform_apply "testenv" "plan.out" "auto-approve"
    rm -f plan.out
    [ "$status" -eq 0 ]
    [[ $output == *"terraform apply -auto-approve plan.out"* ]]
}

@test "validate_terraform_env accepts an explicit environment when ENV is unset" {
    export TF_PLUGIN_CACHE_DIR="${BATS_TEST_TMPDIR}/plugin-cache"
    mkdir -p "${BATS_TEST_TMPDIR}/bin"
    cat > "${BATS_TEST_TMPDIR}/bin/terraform" << 'EOF'
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "${BATS_TEST_TMPDIR}/bin/terraform"
    PATH="${BATS_TEST_TMPDIR}/bin:$PATH"
    unset ENV
    DRY_RUN=true
    VERBOSE=true
    run validate_terraform_env "staging"
    [ "$status" -eq 0 ]
    [[ $output == *"staging"* ]]
}

@test "terraform_apply errors when an explicit plan file does not exist" {
    DRY_RUN=true
    ENV=testenv
    echo "var = 1" > "terraform.${ENV}.tfvars"
    run terraform_apply "$ENV" "missing.tfplan" "auto-approve"
    rm -f "terraform.${ENV}.tfvars"
    [ "$status" -ne 0 ]
    [[ $output == *"Plan file not found: missing.tfplan"* ]]
    [[ $output != *"terraform apply"* ]]
}

@test "terraform_lint returns 1 on failure so the caller keeps running" {
    mkdir -p "${BATS_TEST_TMPDIR}/bin"
    printf '#!/usr/bin/env bash\nexit 1\n' > "${BATS_TEST_TMPDIR}/bin/tflint"
    chmod +x "${BATS_TEST_TMPDIR}/bin/tflint"
    export PATH="${BATS_TEST_TMPDIR}/bin:${PATH}"
    wrapper() {
        if ! terraform_lint; then
            echo "caller-continued"
        fi
    }
    run wrapper
    [ "$status" -eq 0 ]
    [[ $output == *"caller-continued"* ]]
}

@test "terraform_validate returns 1 on failure so the caller keeps running" {
    mkdir -p "${BATS_TEST_TMPDIR}/bin"
    printf '#!/usr/bin/env bash\nexit 1\n' > "${BATS_TEST_TMPDIR}/bin/terraform"
    chmod +x "${BATS_TEST_TMPDIR}/bin/terraform"
    export PATH="${BATS_TEST_TMPDIR}/bin:${PATH}"
    wrapper() {
        if ! terraform_validate; then
            echo "caller-continued"
        fi
    }
    run wrapper
    [ "$status" -eq 0 ]
    [[ $output == *"caller-continued"* ]]
}

@test "terraform_workflow aborts before apply when validation fails" {
    ENV=testenv
    echo "backend" > "terraform.${ENV}.tfbackend"
    echo "var = 1" > "terraform.${ENV}.tfvars"
    mkdir -p "${BATS_TEST_TMPDIR}/bin"
    cat > "${BATS_TEST_TMPDIR}/bin/terraform" << 'EOF'
#!/usr/bin/env bash
case "$1" in
    validate) exit 1 ;;
    apply) echo "APPLY-RAN"; exit 0 ;;
    *) exit 0 ;;
esac
EOF
    chmod +x "${BATS_TEST_TMPDIR}/bin/terraform"
    export PATH="${BATS_TEST_TMPDIR}/bin:${PATH}"
    export TF_PLUGIN_CACHE_DIR="${BATS_TEST_TMPDIR}/plugin-cache"
    run terraform_workflow "$ENV" apply auto-approve
    rm -f "terraform.${ENV}.tfbackend" "terraform.${ENV}.tfvars"
    [ "$status" -ne 0 ]
    [[ $output != *"APPLY-RAN"* ]]
    [[ $output == *"validation failed"* ]]
}

@test "terraform_apply passes a plan file path with spaces and shell metacharacters as one argument" {
    mkdir -p "${BATS_TEST_TMPDIR}/bin"
    cat > "${BATS_TEST_TMPDIR}/bin/terraform" << 'EOF'
#!/usr/bin/env bash
printf 'ARG[%s]\n' "$@" >> "${ARGS_LOG}"
EOF
    chmod +x "${BATS_TEST_TMPDIR}/bin/terraform"
    export PATH="${BATS_TEST_TMPDIR}/bin:${PATH}"
    export ARGS_LOG="${BATS_TEST_TMPDIR}/args.log"
    local plan="${BATS_TEST_TMPDIR}/my plan;touch pwned.out"
    touch "${plan}"
    run terraform_apply "testenv" "${plan}" "auto-approve"
    [ "$status" -eq 0 ]
    grep -Fxq "ARG[${plan}]" "${ARGS_LOG}"
    grep -Fxq "ARG[-auto-approve]" "${ARGS_LOG}"
    [ ! -e "${BATS_TEST_TMPDIR}/pwned.out" ]
    [ ! -e pwned.out ]
}

@test "terraform_plan splits additional options into separate arguments and keeps the plan path intact" {
    mkdir -p "${BATS_TEST_TMPDIR}/bin"
    cat > "${BATS_TEST_TMPDIR}/bin/terraform" << 'EOF'
#!/usr/bin/env bash
printf 'ARG[%s]\n' "$@" >> "${ARGS_LOG}"
EOF
    chmod +x "${BATS_TEST_TMPDIR}/bin/terraform"
    export PATH="${BATS_TEST_TMPDIR}/bin:${PATH}"
    export ARGS_LOG="${BATS_TEST_TMPDIR}/args.log"
    echo "var = 1" > "terraform.testenv.tfvars"
    run terraform_plan "testenv" "${BATS_TEST_TMPDIR}/a b.tfplan" "-refresh=false -no-color"
    rm -f "terraform.testenv.tfvars"
    [ "$status" -eq 0 ]
    grep -Fxq "ARG[-out=${BATS_TEST_TMPDIR}/a b.tfplan]" "${ARGS_LOG}"
    grep -Fxq "ARG[-refresh=false]" "${ARGS_LOG}"
    grep -Fxq "ARG[-no-color]" "${ARGS_LOG}"
}

@test "validate_terraform_env rejects an environment name with shell metacharacters" {
    export TF_PLUGIN_CACHE_DIR="${BATS_TEST_TMPDIR}/plugin-cache"
    DRY_RUN=true
    run validate_terraform_env 'dev;touch pwned'
    [ "$status" -ne 0 ]
    [[ $output == *"Invalid environment name"* ]]
    run validate_terraform_env '../etc'
    [ "$status" -ne 0 ]
}
