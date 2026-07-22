#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154

# Tests for scripts/lib/aws.sh

# Use cases:
# - extract_jq_value returns default for empty json
# - extract_jq_value extracts value from json
# - extract_jq_array returns joined quoted list for array
# - extract_jq_array returns default when key missing
# - aws_safe_exec returns stdout on success
# - aws_safe_exec returns non-zero on failure
# - is_service_available_in_region returns 0 for iam
# - is_service_available_in_region handles lambda with aws success
# - get_waf_association returns WebACL ARN
# - format_aws_timestamp converts seconds
# - format_aws_timestamp handles milliseconds
# - parse_arn returns json with components
# - get_resource_name_from_arn extracts resource name
# - get_waf_name extracts name from ARN path
# - get_security_group_name resolves Name tag via resolve_ec2_tagged_resource_name
# - get_subnet_name resolves Name tag from describe-subnets
# - get_subnet_name returns non-id input unchanged
# - get_vpc_name resolves Name tag from describe-vpcs
# - get_vpc_name falls back to vpc id when AWS call fails
# - get_security_group_name / get_subnet_name fall back on AWS failure
# - Name-tag-absent falls back to GroupName / resource id
# - get_vpc_name falls back to vpc id when AWS call fails

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

setup() {
    bats_source_rel "scripts/lib/aws.sh"
    # shellcheck disable=SC1091
    source "$(bats_support_dir)/aws_mock.bash"
    mock_aws_setup
}

teardown() {
    mock_aws_teardown
}

@test "extract_jq_value returns default for empty json" {
    run extract_jq_value "" '.Name' "DEFAULT"
    [ "$status" -eq 0 ]
    [ "$output" = "DEFAULT" ]
}

@test "extract_jq_value extracts value from json" {
    local js
    js='{"Name":"Alice","Age":30}'
    run extract_jq_value "$js" '.Name' "DEFAULT"
    [ "$status" -eq 0 ]
    [ "$output" = "Alice" ]
}

@test "extract_jq_array returns joined quoted list for array" {
    local js
    js='{"Tags":["a","b","c"]}'
    run extract_jq_array "$js" '.Tags'
    [ "$status" -eq 0 ]
    [ "$output" = '"a,b,c"' ]
}

@test "extract_jq_array returns default when key missing" {
    local js
    js='{}'
    run extract_jq_array "$js" '.Tags' 'DEFAULT'
    [ "$status" -eq 0 ]
    [ "$output" = "DEFAULT" ]
}

@test "aws_safe_exec returns stdout on success" {
    run aws_safe_exec "echo hello"
    [ "$status" -eq 0 ]
    [ "$output" = "hello" ]
}

@test "aws_safe_exec returns non-zero on failure" {
    run aws_safe_exec "bash -c 'exit 2'"
    [ "$status" -ne 0 ]
}

@test "is_service_available_in_region returns 0 for iam" {
    run is_service_available_in_region iam
    [ "$status" -eq 0 ]
}

@test "is_service_available_in_region handles lambda with aws success" {
    # mock aws to succeed on lambda list-functions
    mock_aws_write << 'EOF'
#!/usr/bin/env bash
if [[ "$*" == *"lambda list-functions"* ]]; then
  exit 0
fi
exit 1
EOF
    chmod +x "$MOCK_DIR/aws"

    run is_service_available_in_region lambda us-east-1
    [ "$status" -eq 0 ]
}

@test "get_waf_association returns WebACL ARN" {
    mock_aws_write << 'EOF'
#!/usr/bin/env bash
echo '{"WebACL":{"ARN":"arn:aws:waf::123:regional/webacl/MyWebACL/uuid"}}'
EOF
    chmod +x "$MOCK_DIR/aws"

    run get_waf_association "arn:aws:apigateway:us-east-1::/restapis/abc" us-east-1
    [ "$status" -eq 0 ]
    [ "$output" = "arn:aws:waf::123:regional/webacl/MyWebACL/uuid" ]
}

@test "format_aws_timestamp converts seconds" {
    run format_aws_timestamp 1609459200
    [ "$status" -eq 0 ]
    [[ $output == 2021* ]]
}

@test "format_aws_timestamp handles milliseconds" {
    run format_aws_timestamp 1609459200000
    [ "$status" -eq 0 ]
    [[ $output == 2021* ]]
}

@test "parse_arn returns json with components" {
    run parse_arn "arn:aws:ec2:us-east-1:123456789012:instance/i-0123456789abcdef0"
    [ "$status" -eq 0 ]
    [[ $output =~ '"service": "ec2"' ]]
    [[ $output =~ '"region": "us-east-1"' ]]
}

@test "get_resource_name_from_arn extracts resource name" {
    run get_resource_name_from_arn "arn:aws:ec2:us-east-1:123456789012:instance/i-0123456789abcdef0"
    [ "$status" -eq 0 ]
    [ "$output" = "i-0123456789abcdef0" ]
}

@test "get_waf_name extracts name from ARN path" {
    local arn="arn:aws:wafv2:us-east-1:123456789012:regional/webacl/MyWebACL/uuid"
    run get_waf_name "$arn"
    [ "$status" -eq 0 ]
    [ "$output" = "MyWebACL" ]
}

@test "get_security_group_name resolves Name tag from describe-security-groups" {
    mock_aws_write << 'EOF'
#!/usr/bin/env bash
if [[ "$*" == *"describe-security-groups"* ]]; then
    echo '{"SecurityGroups":[{"GroupName":"default-sg","Tags":[{"Key":"Name","Value":"app-sg"}]}]}'
    exit 0
fi
exit 1
EOF
    chmod +x "$MOCK_DIR/aws"

    run get_security_group_name "sg-0123456789abcdef0" us-east-1
    [ "$status" -eq 0 ]
    [ "$output" = "app-sg" ]
}

@test "get_security_group_name returns input unchanged when not an sg id" {
    run get_security_group_name "not-an-sg" us-east-1
    [ "$status" -eq 0 ]
    [ "$output" = "not-an-sg" ]
}

@test "get_security_group_name returns N/A for empty input" {
    run get_security_group_name "" us-east-1
    [ "$status" -eq 1 ]
    [ "$output" = "N/A" ]
}

@test "get_subnet_name resolves Name tag from describe-subnets" {
    mock_aws_write << 'EOF'
#!/usr/bin/env bash
if [[ "$*" == *"describe-subnets"* ]]; then
    echo '{"Subnets":[{"SubnetId":"subnet-0123456789abcdef0","Tags":[{"Key":"Name","Value":"app-subnet"}]}]}'
    exit 0
fi
exit 1
EOF
    chmod +x "$MOCK_DIR/aws"

    run get_subnet_name "subnet-0123456789abcdef0" us-east-1
    [ "$status" -eq 0 ]
    [ "$output" = "app-subnet" ]
}

@test "get_subnet_name returns input unchanged when not a subnet id" {
    run get_subnet_name "custom-subnet-name" us-east-1
    [ "$status" -eq 0 ]
    [ "$output" = "custom-subnet-name" ]
}

@test "get_vpc_name resolves Name tag from describe-vpcs" {
    mock_aws_write << 'EOF'
#!/usr/bin/env bash
if [[ "$*" == *"describe-vpcs"* ]]; then
    echo '{"Vpcs":[{"VpcId":"vpc-0123456789abcdef0","Tags":[{"Key":"Name","Value":"app-vpc"}]}]}'
    exit 0
fi
exit 1
EOF
    chmod +x "$MOCK_DIR/aws"

    run get_vpc_name "vpc-0123456789abcdef0" us-east-1
    [ "$status" -eq 0 ]
    [ "$output" = "app-vpc" ]
}

@test "get_vpc_name falls back to vpc id when describe-vpcs fails" {
    mock_aws_write << 'EOF'
#!/usr/bin/env bash
exit 1
EOF
    chmod +x "$MOCK_DIR/aws"

    run get_vpc_name "vpc-0123456789abcdef0" us-east-1
    [ "$status" -eq 1 ]
    [ "$output" = "vpc-0123456789abcdef0" ]
}

@test "get_security_group_name falls back to GroupName when Name tag is absent" {
    mock_aws_write << 'MOCK'
#!/usr/bin/env bash
if [[ "$*" == *"describe-security-groups"* ]]; then
    echo '{"SecurityGroups":[{"GroupName":"default-sg","Tags":[]}]}'
    exit 0
fi
exit 1
MOCK
    chmod +x "$MOCK_DIR/aws"

    run get_security_group_name "sg-0123456789abcdef0" us-east-1
    [ "$status" -eq 0 ]
    [ "$output" = "default-sg" ]
}

@test "get_security_group_name falls back to sg id when describe-security-groups fails" {
    mock_aws_write << 'MOCK'
#!/usr/bin/env bash
exit 1
MOCK
    chmod +x "$MOCK_DIR/aws"

    run get_security_group_name "sg-0123456789abcdef0" us-east-1
    [ "$status" -eq 1 ]
    [ "$output" = "sg-0123456789abcdef0" ]
}

@test "get_subnet_name falls back to subnet id when Name tag is absent" {
    mock_aws_write << 'MOCK'
#!/usr/bin/env bash
if [[ "$*" == *"describe-subnets"* ]]; then
    echo '{"Subnets":[{"SubnetId":"subnet-0123456789abcdef0","Tags":[]}]}'
    exit 0
fi
exit 1
MOCK
    chmod +x "$MOCK_DIR/aws"

    run get_subnet_name "subnet-0123456789abcdef0" us-east-1
    [ "$status" -eq 0 ]
    [ "$output" = "subnet-0123456789abcdef0" ]
}

@test "get_subnet_name falls back to subnet id when describe-subnets fails" {
    mock_aws_write << 'MOCK'
#!/usr/bin/env bash
exit 1
MOCK
    chmod +x "$MOCK_DIR/aws"

    run get_subnet_name "subnet-0123456789abcdef0" us-east-1
    [ "$status" -eq 1 ]
    [ "$output" = "subnet-0123456789abcdef0" ]
}

@test "get_vpc_name falls back to vpc id when Name tag is absent" {
    mock_aws_write << 'MOCK'
#!/usr/bin/env bash
if [[ "$*" == *"describe-vpcs"* ]]; then
    echo '{"Vpcs":[{"VpcId":"vpc-0123456789abcdef0","Tags":[]}]}'
    exit 0
fi
exit 1
MOCK
    chmod +x "$MOCK_DIR/aws"

    run get_vpc_name "vpc-0123456789abcdef0" us-east-1
    [ "$status" -eq 0 ]
    [ "$output" = "vpc-0123456789abcdef0" ]
}
