#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154

# Tests for scripts/terraform/validate.sh

# Use cases:
# - parse_arguments sets VERBOSE on -v
# - parse_arguments sets GENERATE_DOCS on -d
# - parse_arguments sets AUTO_FIX on -f
# - parse_arguments collects positional args as TARGET_DIRS
# - parse_arguments fails on unknown option
# - parse_arguments sets GENERATE_DOCS on -g
# - --changed-only exits 0 without scanning when no Terraform file changed
# - --changed-only fails for a target directory that does not exist
# - --changed-only scans only directories with changed Terraform files
# - resolve_changed_module_dirs maps files to the nearest directory with tf files and drops nested modules
# - resolve_changed_module_dirs skips files with no module above them
# - resolve_changed_module_dirs selects the nearest surviving ancestor module for a removed directory
# - resolve_changed_module_dirs returns . when the current directory is the module
# - run_recursive_validation warns and skips a non-existent target directory
# - show_usage example uses -g, not the deprecated -d

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

setup() {
    export VERBOSE=false
    export GENERATE_DOCS=false
    export AUTO_FIX=false
    TARGET_DIRS=()

    bats_source_rel "scripts/lib/all.sh"

    # Source only the parse_arguments function (avoid main execution)
    eval "$(sed -n '/^function parse_arguments/,/^}/p' scripts/terraform/validate.sh)"
}

@test "parse_arguments sets VERBOSE on -v" {
    parse_arguments -v
    [ "$VERBOSE" = "true" ]
}

@test "parse_arguments sets GENERATE_DOCS on -d" {
    parse_arguments -d
    [ "$GENERATE_DOCS" = "true" ]
}

@test "parse_arguments sets AUTO_FIX on -f" {
    parse_arguments -f
    [ "$AUTO_FIX" = "true" ]
}

@test "parse_arguments collects positional args as TARGET_DIRS" {
    parse_arguments "terraform/base" "terraform/monitor"
    [ "${#TARGET_DIRS[@]}" -eq 2 ]
    [ "${TARGET_DIRS[0]}" = "terraform/base" ]
    [ "${TARGET_DIRS[1]}" = "terraform/monitor" ]
}

@test "parse_arguments fails on unknown option" {
    run parse_arguments --unknown
    [ "$status" -ne 0 ]
}

@test "parse_arguments sets GENERATE_DOCS on -g" {
    parse_arguments -g
    [ "$GENERATE_DOCS" = "true" ]
}

@test "run_recursive_validation warns and skips a non-existent target directory" {
    run bash -c "source '$(bats_workspace_root)/scripts/terraform/validate.sh' && TARGET_DIRS=('${BATS_TEST_TMPDIR}/missing') && run_recursive_validation"
    [ "$status" -eq 0 ]
    [[ $output == *"Skipping non-existent directory for validation"* ]]
}

@test "show_usage example uses -g, not the deprecated -d" {
    run bash "$(bats_workspace_root)/scripts/terraform/validate.sh" --help
    [ "$status" -eq 0 ]
    [[ $output == *"-g modules/aws/vpc"* ]]
    [[ $output != *"-d modules/aws/vpc"* ]]
}

@test "--changed-only exits 0 without scanning when no terraform file changed" {
    local repo="${BATS_TEST_TMPDIR}/repo"
    bats_git_fresh_repo "${repo}"
    echo 'x' > "${repo}/readme.md"
    bats_git_commit "${repo}" init
    run bash -c "cd '${repo}' && '$(bats_workspace_root)/scripts/terraform/validate.sh' --changed-only"
    [ "$status" -eq 0 ]
}

@test "--changed-only scans only directories with changed terraform files" {
    local repo="${BATS_TEST_TMPDIR}/repo"
    bats_git_fresh_repo "${repo}"
    mkdir -p "${repo}/m1" "${repo}/m2"
    echo '# a' > "${repo}/m1/main.tf"
    echo '# b' > "${repo}/m2/main.tf"
    bats_git_commit "${repo}" init
    echo '# c' >> "${repo}/m2/main.tf"
    run bash -c "cd '${repo}' && source '$(bats_workspace_root)/scripts/terraform/validate.sh' && parse_arguments --changed-only && echo \"\${TARGET_DIRS[*]}\""
    [ "$status" -eq 0 ]
    [ "$output" = "m2" ]
}

@test "resolve_changed_module_dirs maps files to the nearest directory with tf files and drops nested modules" {
    local repo="${BATS_TEST_TMPDIR}/repo"
    mkdir -p "${repo}/m1/sub" "${repo}/m2/inner" "${repo}/m3/inner" "${repo}/env/prod"
    touch "${repo}/m1/main.tf" "${repo}/m2/main.tf" "${repo}/m2/inner/main.tf" "${repo}/m3/inner/main.tf" "${repo}/env/prod/variables.tf"
    run bash -c "cd '${repo}' && source '$(bats_workspace_root)/scripts/terraform/validate.sh' && resolve_changed_module_dirs m1/sub/x.tfvars m1/vars.tfvars m2/inner/a.tf m2/b.tf m3/inner/c.tf env/prod/terraform.tfvars 2>/dev/null"
    [ "$status" -eq 0 ]
    [ "$output" = $'env/prod\nm1\nm2\nm3/inner' ]
}

@test "resolve_changed_module_dirs returns . when the current directory is the module" {
    local repo="${BATS_TEST_TMPDIR}/repo"
    mkdir -p "${repo}/m1" "${repo}/loose"
    touch "${repo}/main.tf" "${repo}/m1/main.tf"
    run bash -c "cd '${repo}' && source '$(bats_workspace_root)/scripts/terraform/validate.sh' && resolve_changed_module_dirs main.tf m1/a.tf loose/l.hcl 2>/dev/null"
    [ "$status" -eq 0 ]
    [ "$output" = "." ]
}

@test "resolve_changed_module_dirs skips files with no module above them" {
    local repo="${BATS_TEST_TMPDIR}/repo"
    mkdir -p "${repo}/loose"
    run bash -c "cd '${repo}' && source '$(bats_workspace_root)/scripts/terraform/validate.sh' && resolve_changed_module_dirs loose/l.hcl 2>/dev/null"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "resolve_changed_module_dirs selects the nearest surviving ancestor module for a removed directory" {
    local repo="${BATS_TEST_TMPDIR}/repo"
    mkdir -p "${repo}/m1"
    touch "${repo}/m1/main.tf"
    run bash -c "cd '${repo}' && source '$(bats_workspace_root)/scripts/terraform/validate.sh' && resolve_changed_module_dirs m1/removed.tf m1/gone/main.tf 2>/dev/null"
    [ "$status" -eq 0 ]
    [ "$output" = "m1" ]
}

@test "--changed-only fails for a target directory that does not exist" {
    local repo="${BATS_TEST_TMPDIR}/repo"
    bats_git_fresh_repo "${repo}"
    echo x > "${repo}/readme.md"
    bats_git_commit "${repo}" init
    run bash -c "cd '${repo}' && '$(bats_workspace_root)/scripts/terraform/validate.sh' --changed-only no/such/dir"
    [ "$status" -ne 0 ]
    [[ $output == *"Target directory does not exist"* ]]
}
