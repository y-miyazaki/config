#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2154

# Tests for scripts/terraform/aws_get_version.sh
#
# Use cases:
# - collect_rds_versions marks the numerically highest engine version as latest
# - collect_rds_versions returns the header for region "header"
# - collect_rds_versions ranks a suffixed version above its plain base version

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
    bats_source_rel "scripts/terraform/aws_get_version.sh"
}

teardown() {
    mock_aws_teardown
}

@test "collect_rds_versions marks the numerically highest engine version as latest" {
    mock_aws_write << 'EOF'
#!/usr/bin/env bash
if [[ "$*" == *"--engine mysql "* ]]; then
    echo '{"DBEngineVersions":[{"EngineVersion":"8.0.9","Status":"available"},{"EngineVersion":"8.0.40","Status":"available"},{"EngineVersion":"8.0.100","Status":"available"}]}'
else
    echo '{"DBEngineVersions":[]}'
fi
EOF
    run collect_rds_versions us-east-1
    [ "$status" -eq 0 ]
    [[ $output == *"RDS,Engine,mysql,8.0.100,us-east-1,Yes,"* ]]
    [[ $output == *"RDS,Engine,mysql,8.0.40,us-east-1,,"* ]]
    [[ $output == *"RDS,Engine,mysql,8.0.9,us-east-1,,"* ]]
}

@test "collect_rds_versions returns the header for region header" {
    run collect_rds_versions header
    [ "$status" -eq 0 ]
    [[ $output == "Category,SubCategory,"* ]]
}

@test "collect_rds_versions ranks a suffixed version above its plain base version" {
    mock_aws_write << 'EOF'
#!/usr/bin/env bash
if [[ "$*" == *"--engine mysql "* ]]; then
    echo '{"DBEngineVersions":[{"EngineVersion":"15.4","Status":"available"},{"EngineVersion":"15.4-R2","Status":"available"},{"EngineVersion":"13.10","Status":"available"}]}'
else
    echo '{"DBEngineVersions":[]}'
fi
EOF
    run collect_rds_versions us-east-1
    [ "$status" -eq 0 ]
    [[ $output == *"RDS,Engine,mysql,15.4-R2,us-east-1,Yes,"* ]]
    [[ $output == *"RDS,Engine,mysql,15.4,us-east-1,,"* ]]
}
