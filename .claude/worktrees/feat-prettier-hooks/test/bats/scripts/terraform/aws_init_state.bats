#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2154

# Tests for scripts/terraform/aws_init_state.sh
#
# Use cases:
# - create_s3_bucket continues when the bucket already exists in this account
# - create_s3_bucket stops on any other creation error such as access denied
# - create_s3_bucket stops when the bucket name is owned by another account
# - create_s3_bucket succeeds when the bucket is created

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"
# shellcheck disable=SC1091
source "$(bats_support_dir)/aws_mock.bash"

INIT_STATE_SCRIPT="$(bats_workspace_root)/scripts/terraform/aws_init_state.sh"

setup() {
    mock_aws_setup
}

teardown() {
    mock_aws_teardown
}

# run_create: Run create_s3_bucket against a mock aws that prints $1 to stderr and exits with $2
function run_create {
    local message="$1"
    local code="$2"
    export MOCK_MESSAGE="${message}" MOCK_CODE="${code}"
    mock_aws_write << 'EOF'
#!/usr/bin/env bash
[[ -n $MOCK_MESSAGE ]] && echo "$MOCK_MESSAGE" >&2
exit "$MOCK_CODE"
EOF
    run bash -c "source '${INIT_STATE_SCRIPT}'; BUCKET=test-bucket; REGION=us-east-1; create_s3_bucket"
}

@test "create_s3_bucket continues when the bucket already exists in this account" {
    run_create "An error occurred (BucketAlreadyOwnedByYou) when calling the CreateBucket operation" 1
    [ "$status" -eq 0 ]
}

@test "create_s3_bucket stops on any other creation error such as access denied" {
    run_create "An error occurred (AccessDenied) when calling the CreateBucket operation" 1
    [ "$status" -ne 0 ]
    [[ $output == *"Failed to create S3 bucket test-bucket"* ]]
    [[ $output == *"AccessDenied"* ]]
}

@test "create_s3_bucket stops when the bucket name is owned by another account" {
    run_create "An error occurred (BucketAlreadyExists) when calling the CreateBucket operation" 1
    [ "$status" -ne 0 ]
    [[ $output == *"BucketAlreadyExists"* ]]
}

@test "create_s3_bucket succeeds when the bucket is created" {
    run_create "" 0
    [ "$status" -eq 0 ]
}
