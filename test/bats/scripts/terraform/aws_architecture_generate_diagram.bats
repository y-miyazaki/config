#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154

# Tests for scripts/terraform/aws_architecture_generate_diagram.sh
#
# Use cases:
# - generate_generic_resources lists DynamoDB tables returned by the paginated list-tables call
# - generate_generic_resources emits no DynamoDB stack when there are no tables
# - generate_generic_resources emits no DynamoDB stack when the AWS call fails

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"
# shellcheck disable=SC1091
source "$(bats_support_dir)/aws_mock.bash"

setup() {
    mock_aws_setup
    bats_source_rel "scripts/terraform/aws_architecture_generate_diagram.sh"
    TEMP_YAML_FILE="${BATS_TEST_TMPDIR}/out.yaml"
    : > "${TEMP_YAML_FILE}"
    REGIONS_TO_CHECK=("us-east-1")
    # Sourcing inside setup() leaves the script's own declare -A function-local
    declare -gA RESOURCE_CONFIGS=([dynamodb]="dynamodb|list-tables|TableName|AWS::DynamoDB::Table|true")
}

teardown() {
    mock_aws_teardown
}

@test "generate_generic_resources emits no DynamoDB stack when there are no tables" {
    mock_aws_write << 'EOF'
#!/usr/bin/env bash
echo '{"TableNames":[]}'
EOF
    run generate_generic_resources dynamodb ignored yaml
    [ "$status" -eq 0 ]
    [ ! -s "${TEMP_YAML_FILE}" ]
}

@test "generate_generic_resources lists DynamoDB tables returned by the paginated list-tables call" {
    mock_aws_write << 'EOF'
#!/usr/bin/env bash
if [[ "$*" == *"--exclusive-start-table-name"* ]]; then
    echo '{"TableNames":["orders"]}'
else
    echo '{"TableNames":["users"],"LastEvaluatedTableName":"users"}'
fi
EOF
    generate_generic_resources dynamodb ignored yaml
    grep -q "Title: users" "${TEMP_YAML_FILE}"
    grep -q "Title: orders" "${TEMP_YAML_FILE}"
    grep -q "AWS::DynamoDB::Table" "${TEMP_YAML_FILE}"
}

@test "generate_generic_resources emits no DynamoDB stack when the AWS call fails" {
    mock_aws_write << 'EOF'
#!/usr/bin/env bash
echo "An error occurred (AccessDenied) when calling the ListTables operation" >&2
exit 254
EOF
    run generate_generic_resources dynamodb ignored yaml
    [ "$status" -eq 0 ]
    [ ! -s "${TEMP_YAML_FILE}" ]
}
