#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154

# Tests for scripts/self/ai/sync_validate_mirror.sh

# Use cases:
# - --help exits successfully
# - --domain rejects invalid names and missing values
# - --check / sync / --from-skill work against fixture trees (no live repo mutation)
# - path transforms rewrite shellcheck source and WORKSPACE_ROOT for shell-script validate.sh
# - terraform domain check and sync are covered
# - fix_function_doc_order.sh mirrors follow the same sync/check path

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

SYNC_SCRIPT="$(bats_workspace_root)/scripts/self/ai/sync_validate_mirror.sh"

repo_validate_body() {
    cat << 'EOF'
#!/bin/bash
# shellcheck source=../lib/all.sh
source "${SCRIPT_DIR}/../lib/all.sh"
WORKSPACE_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
echo repo-validate
EOF
}

skill_validate_body() {
    cat << 'EOF'
#!/bin/bash
# shellcheck source=./lib/all.sh
source "${SCRIPT_DIR}/lib/all.sh"
WORKSPACE_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
echo repo-validate
EOF
}

repo_fix_doc_body() {
    cat << 'EOF'
#!/bin/bash
# shellcheck source=../lib/all.sh
source "${SCRIPT_DIR}/../lib/all.sh"
echo repo-fix-doc
EOF
}

skill_fix_doc_body() {
    cat << 'EOF'
#!/bin/bash
# shellcheck source=./lib/all.sh
source "${SCRIPT_DIR}/lib/all.sh"
echo repo-fix-doc
EOF
}

repo_go_validate_body() {
    cat << 'EOF'
#!/bin/bash
# shellcheck source=../lib/all.sh
source "${SCRIPT_DIR}/../lib/all.sh"
echo repo-go-validate
EOF
}

skill_go_validate_body() {
    cat << 'EOF'
#!/bin/bash
# shellcheck source=./lib/all.sh
source "${SCRIPT_DIR}/lib/all.sh"
echo repo-go-validate
EOF
}

repo_tf_validate_body() {
    cat << 'EOF'
#!/bin/bash
# shellcheck source=../lib/all.sh
source "${SCRIPT_DIR}/../lib/all.sh"
echo repo-tf-validate
EOF
}

skill_tf_validate_body() {
    cat << 'EOF'
#!/bin/bash
# shellcheck source=./lib/all.sh
source "${SCRIPT_DIR}/lib/all.sh"
echo repo-tf-validate
EOF
}

setup_fixture_tree() {
    FIXTURE_ROOT="${BATS_TEST_TMPDIR}/mirror-root"
    mkdir -p \
        "${FIXTURE_ROOT}/scripts/shell-script" \
        "${FIXTURE_ROOT}/scripts/go" \
        "${FIXTURE_ROOT}/scripts/terraform" \
        "${FIXTURE_ROOT}/.apm/packages/shell-script/.apm/skills/shell-script-validation/scripts" \
        "${FIXTURE_ROOT}/.apm/packages/go/.apm/skills/go-validation/scripts" \
        "${FIXTURE_ROOT}/.apm/packages/terraform/.apm/skills/terraform-validation/scripts"

    REPO_VALIDATE="${FIXTURE_ROOT}/scripts/shell-script/validate.sh"
    SKILL_VALIDATE="${FIXTURE_ROOT}/.apm/packages/shell-script/.apm/skills/shell-script-validation/scripts/validate.sh"
    REPO_FIX_DOC="${FIXTURE_ROOT}/scripts/shell-script/fix_function_doc_order.sh"
    SKILL_FIX_DOC="${FIXTURE_ROOT}/.apm/packages/shell-script/.apm/skills/shell-script-validation/scripts/fix_function_doc_order.sh"
    GO_REPO_VALIDATE="${FIXTURE_ROOT}/scripts/go/validate.sh"
    GO_SKILL_VALIDATE="${FIXTURE_ROOT}/.apm/packages/go/.apm/skills/go-validation/scripts/validate.sh"
    TF_REPO_VALIDATE="${FIXTURE_ROOT}/scripts/terraform/validate.sh"
    TF_SKILL_VALIDATE="${FIXTURE_ROOT}/.apm/packages/terraform/.apm/skills/terraform-validation/scripts/validate.sh"

    repo_validate_body > "${REPO_VALIDATE}"
    skill_validate_body > "${SKILL_VALIDATE}"
    repo_fix_doc_body > "${REPO_FIX_DOC}"
    skill_fix_doc_body > "${SKILL_FIX_DOC}"
    repo_go_validate_body > "${GO_REPO_VALIDATE}"
    skill_go_validate_body > "${GO_SKILL_VALIDATE}"
    repo_tf_validate_body > "${TF_REPO_VALIDATE}"
    skill_tf_validate_body > "${TF_SKILL_VALIDATE}"

    export SYNC_VALIDATE_MIRROR_ROOT="${FIXTURE_ROOT}"
}

setup() {
    setup_fixture_tree
}

@test "sync_validate_mirror --check passes when shell-script mirror is in sync" {
    run bash "${SYNC_SCRIPT}" --check --domain shell-script
    [ "$status" -eq 0 ]
    [[ $output == *"OK: All validation mirrors are in sync."* ]]
}

@test "sync_validate_mirror --check passes when go mirror is in sync" {
    run bash "${SYNC_SCRIPT}" --check --domain go
    [ "$status" -eq 0 ]
    [[ $output == *"OK: All validation mirrors are in sync."* ]]
}

@test "sync_validate_mirror --check passes when terraform mirror is in sync" {
    run bash "${SYNC_SCRIPT}" --check --domain terraform
    [ "$status" -eq 0 ]
    [[ $output == *"OK: All validation mirrors are in sync."* ]]
}

@test "sync_validate_mirror --check reports drift when skill copy differs from repo" {
    echo "# drift-marker" >> "${SKILL_VALIDATE}"

    run bash "${SYNC_SCRIPT}" --check --domain shell-script
    [ "$status" -eq 1 ]
    [[ $output == *"DRIFT: shell-script"* ]]
}

@test "sync_validate_mirror --check reports drift when fix_function_doc_order.sh differs" {
    echo "# drift-marker" >> "${SKILL_FIX_DOC}"

    run bash "${SYNC_SCRIPT}" --check --domain shell-script
    [ "$status" -eq 1 ]
    [[ $output == *"DRIFT: shell-script/fix_function_doc_order.sh"* ]]
}

@test "sync_validate_mirror --check reports drift when terraform skill copy differs" {
    echo "# drift-marker" >> "${TF_SKILL_VALIDATE}"

    run bash "${SYNC_SCRIPT}" --check --domain terraform
    [ "$status" -eq 1 ]
    [[ $output == *"DRIFT: terraform/validate.sh"* ]]
}

@test "sync_validate_mirror --domain rejects invalid domain names" {
    run bash "${SYNC_SCRIPT}" --domain invalid-name --check
    [ "$status" -eq 1 ]
    [[ $output == *"Invalid domain"* ]]
}

@test "sync_validate_mirror --domain rejects missing values" {
    run bash "${SYNC_SCRIPT}" --domain
    [ "$status" -eq 1 ]
    [[ $output == *"requires a value"* || $output == *"Invalid domain"* || $output == *"Unknown argument"* ]]
}

@test "sync_validate_mirror --from-skill restores repo validate.sh from skill copy" {
    echo "# drift-marker" >> "${REPO_VALIDATE}"

    bash "${SYNC_SCRIPT}" --from-skill --domain shell-script

    run bash "${SYNC_SCRIPT}" --check --domain shell-script
    [ "$status" -eq 0 ]
}

@test "sync_validate_mirror --from-skill restores repo fix_function_doc_order.sh" {
    echo "# drift-marker" >> "${REPO_FIX_DOC}"

    bash "${SYNC_SCRIPT}" --from-skill --domain shell-script

    run bash "${SYNC_SCRIPT}" --check --domain shell-script
    [ "$status" -eq 0 ]
}

@test "sync_validate_mirror --help exits successfully" {
    run bash "${SYNC_SCRIPT}" --help
    [ "$status" -eq 0 ]
    [[ $output == *"--check"* ]]
    [[ $output == *"--from-skill"* ]]
}

@test "sync_validate_mirror sync restores skill copy from repo validate.sh" {
    echo "# drift-marker" >> "${SKILL_VALIDATE}"

    bash "${SYNC_SCRIPT}" --domain shell-script

    run bash "${SYNC_SCRIPT}" --check --domain shell-script
    [ "$status" -eq 0 ]
    [[ $output == *"OK: All validation mirrors are in sync."* ]]
}

@test "sync_validate_mirror sync restores skill fix_function_doc_order.sh from repo" {
    echo "# drift-marker" >> "${SKILL_FIX_DOC}"

    bash "${SYNC_SCRIPT}" --domain shell-script

    run bash "${SYNC_SCRIPT}" --check --domain shell-script
    [ "$status" -eq 0 ]
}

@test "sync_validate_mirror sync restores terraform skill copy from repo" {
    echo "# drift-marker" >> "${TF_SKILL_VALIDATE}"

    bash "${SYNC_SCRIPT}" --domain terraform

    run bash "${SYNC_SCRIPT}" --check --domain terraform
    [ "$status" -eq 0 ]
}

@test "sync_validate_mirror transform_repo_to_skill rewrites shellcheck and WORKSPACE_ROOT" {
    local out
    out="$(mktemp)"

    # shellcheck disable=SC1090  # SYNC_SCRIPT path is runtime-resolved
    source "${SYNC_SCRIPT}"
    transform_repo_to_skill "shell-script" "validate.sh" "${REPO_VALIDATE}" "${out}"

    run grep -Fq '# shellcheck source=./lib/all.sh' "${out}"
    [ "$status" -eq 0 ]
    # shellcheck disable=SC2016  # assert literal ${SCRIPT_DIR} in transformed file
    run grep -Fq 'source "${SCRIPT_DIR}/lib/all.sh"' "${out}"
    [ "$status" -eq 0 ]
    # shellcheck disable=SC2016
    run grep -Fq 'WORKSPACE_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"' "${out}"
    [ "$status" -eq 0 ]
    # shellcheck disable=SC2016
    run grep -Fq 'WORKSPACE_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"' "${out}"
    [ "$status" -ne 0 ]
}

@test "sync_validate_mirror transform_skill_to_repo rewrites shellcheck and WORKSPACE_ROOT" {
    local out
    out="$(mktemp)"

    # shellcheck disable=SC1090  # SYNC_SCRIPT path is runtime-resolved
    source "${SYNC_SCRIPT}"
    transform_skill_to_repo "shell-script" "validate.sh" "${SKILL_VALIDATE}" "${out}"

    run grep -Fq '# shellcheck source=../lib/all.sh' "${out}"
    [ "$status" -eq 0 ]
    # shellcheck disable=SC2016  # assert literal ${SCRIPT_DIR} in transformed file
    run grep -Fq 'source "${SCRIPT_DIR}/../lib/all.sh"' "${out}"
    [ "$status" -eq 0 ]
    # shellcheck disable=SC2016
    run grep -Fq 'WORKSPACE_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"' "${out}"
    [ "$status" -eq 0 ]
    # shellcheck disable=SC2016
    run grep -Fq 'WORKSPACE_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"' "${out}"
    [ "$status" -ne 0 ]
}
