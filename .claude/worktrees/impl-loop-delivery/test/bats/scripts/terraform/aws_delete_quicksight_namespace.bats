#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2154

# Tests for scripts/terraform/aws_delete_quicksight_namespace.sh
#
# Use cases:
# - --dry-run lists namespaces without deleting any
# - deletion without --yes is refused when stdin is not a terminal
# - --yes deletes every listed namespace
# - a failed delete aborts with a non-zero status

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"
# shellcheck disable=SC1091
source "$(bats_support_dir)/aws_mock.bash"

QS_SCRIPT="$(bats_workspace_root)/scripts/terraform/aws_delete_quicksight_namespace.sh"

setup() {
    mock_aws_setup
    DELETE_LOG="${BATS_TEST_TMPDIR}/deleted.log"
    export DELETE_LOG
    mock_aws_write << 'EOF'
#!/usr/bin/env bash
case "$*" in
    *"sts get-caller-identity"*"Arn"*) echo "arn:aws:iam::123456789012:user/test" ;;
    *"sts get-caller-identity"*) echo "123456789012" ;;
    *"quicksight list-namespaces"*) echo '{"Namespaces":[{"Name":"default"},{"Name":"ns1"}]}' ;;
    *"quicksight delete-namespace"*)
        [[ -n ${FAIL_DELETE:-} ]] && exit 1
        echo "$*" >> "$DELETE_LOG"
        ;;
esac
EOF
}

teardown() {
    mock_aws_teardown
}

@test "--dry-run lists namespaces without deleting any" {
    run env VERBOSE=true bash "${QS_SCRIPT}" --dry-run
    [ "$status" -eq 0 ]
    [[ $output == *"ns1"* ]]
    [ ! -s "${DELETE_LOG}" ]
}

@test "--yes deletes every listed namespace" {
    run bash "${QS_SCRIPT}" --yes
    [ "$status" -eq 0 ]
    [ "$(grep -c 'delete-namespace' "${DELETE_LOG}")" -eq 2 ]
}

@test "a failed delete aborts with a non-zero status" {
    run env FAIL_DELETE=1 bash "${QS_SCRIPT}" --yes
    [ "$status" -ne 0 ]
    [[ $output == *"Failed to delete namespace"* ]]
}

@test "deletion without --yes is refused when stdin is not a terminal" {
    run bash "${QS_SCRIPT}" < /dev/null
    [ "$status" -ne 0 ]
    [[ $output == *"--yes"* ]]
    [ ! -s "${DELETE_LOG}" ]
}
