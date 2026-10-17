#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2154

# Tests for scripts/terraform/aws_get_sqs_dlq_info.sh, aws_get_ecs_container_sights.sh and aws_get_version.sh
#
# Use cases:
# - generate_terraform_output emits one block per item with values copied verbatim
# - output_csv_data keeps the blank line that separates blocks for sorted and grouped output
# - values containing backslashes are not interpreted as escape sequences

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

TERRAFORM_DIR="$(bats_workspace_root)/scripts/terraform"

@test "generate_terraform_output emits one block per item with values copied verbatim" {
    run bash -c "source '${TERRAFORM_DIR}/aws_get_sqs_dlq_info.sh'; out=\$(generate_terraform_output q1 q-2 2>/dev/null); output_result \"\$out\" 2>/dev/null"
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "[" ]
    [ "${lines[1]}" = "  {" ]
    [ "${lines[2]}" = '    QueueName = "q1"' ]
    [ "${lines[3]}" = "  }," ]
    [ "${lines[5]}" = '    QueueName = "q-2"' ]
    [ "${lines[6]}" = "  }" ]
    [ "${lines[7]}" = "]" ]
}

@test "output_csv_data keeps the blank line that separates blocks for sorted and grouped output" {
    local out="${BATS_TEST_TMPDIR}/out.csv"
    run bash -c "
        source '${TERRAFORM_DIR}/aws_get_version.sh'
        GLUE_DATA=\$'4.0|ACTIVE|e1|l1|true\n3.0|DEPRECATED|e2|l2|false'
        OUTPUT_FILE='${out}'; : > \"\${OUTPUT_FILE}\"
        buffer=\$(collect_glue_versions us-east-1 2>/dev/null)
        header=\$(collect_glue_versions header 2>/dev/null)
        output_csv_data glue \"\$header\" \"\$buffer\" true 2>/dev/null
        output_csv_data glue \"\$header\" \"\$buffer\" false 2>/dev/null"
    [ "$status" -eq 0 ]
    # Each block is header + 2 rows + one blank separator line (8 lines); sorted block first, then grouped
    [ "$(wc -l < "${out}")" -eq 8 ]
    [ "$(sed -n '4p;8p' "${out}" | grep -c '^$')" -eq 2 ]
    [[ $(sed -n '2p' "${out}") == "Glue,Version,glue,3.0,"* ]]
    [[ $(sed -n '6p' "${out}") == "Glue,Version,glue,4.0,"* ]]
}

@test "values containing backslashes are not interpreted as escape sequences" {
    run bash -c "source '${TERRAFORM_DIR}/aws_get_ecs_container_sights.sh'; out=\$(generate_terraform_output 'a\\nb' 2>/dev/null); output_result \"\$out\" 2>/dev/null"
    [ "$status" -eq 0 ]
    [[ $output == *'TaskDefinitionFamily = "a\nb"'* ]]
    [ "${#lines[@]}" -eq 6 ]
}
