#!/bin/bash
#######################################
# Description:
#   Install Session Manager plugin and resolve EC2 bastion instance ID.
#
# Usage:
#   BASTION_INSTANCE_ID=i-123 BASTION_TAG_NAME='*bastion*' bash lib/connect.sh
#
# Design Rules:
#   - Use explicit bastion instance ID when provided
#   - Auto-detect running instance by Name tag when ID is empty
#
# Output:
#   BASTION_ID on GITHUB_ENV and bastion_id on GITHUB_OUTPUT
#######################################

# Error handling: exit on error, unset variable, or failed pipeline
set -euo pipefail

# Secure defaults
umask 027
export LC_ALL=C.UTF-8

#######################################
# setup_bastion_connection: Resolve bastion and verify SSM connectivity
#
# Globals:
#   BASTION_INSTANCE_ID, BASTION_TAG_NAME, GITHUB_ENV, GITHUB_OUTPUT
#
# Arguments:
#   None
#
# Outputs:
#   Writes BASTION_ID to GITHUB_ENV and bastion_id to GITHUB_OUTPUT
#
# Returns:
#   Exits non-zero when bastion cannot be resolved
#
#######################################
function setup_bastion_connection {
    local bastion_id=""
    local instance_count=""
    local plugin_deb=""

    echo "Setting up EC2 Bastion connection via AWS Systems Manager Session Manager"

    echo "Installing AWS Session Manager plugin..."
    plugin_deb="$(mktemp /tmp/session-manager-plugin.XXXXXX.deb)"
    trap 'rm -f "${plugin_deb:-}"' EXIT
    curl -fsSL "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/ubuntu_64bit/session-manager-plugin.deb" -o "${plugin_deb}"
    sudo dpkg -i "${plugin_deb}"
    rm -f "${plugin_deb}"
    trap - EXIT

    if [[ -n ${BASTION_INSTANCE_ID} ]]; then
        if ! [[ ${BASTION_INSTANCE_ID} =~ ^i-[0-9a-f]+$ ]]; then
            echo "Error: invalid bastion_instance_id format: ${BASTION_INSTANCE_ID}" >&2
            return 1
        fi
        bastion_id="${BASTION_INSTANCE_ID}"
        echo "Using specified Bastion instance ID: ${bastion_id}"
    else
        if [[ -z ${BASTION_TAG_NAME} || ! ${BASTION_TAG_NAME} =~ ^[a-zA-Z0-9*_.-]+$ ]]; then
            echo "Error: invalid bastion_tag_name filter: ${BASTION_TAG_NAME:-<empty>}" >&2
            return 1
        fi
        echo "Auto-detecting Bastion instance with tag Name=${BASTION_TAG_NAME}..."
        instance_count=$(aws ec2 describe-instances \
            --filters "Name=tag:Name,Values=${BASTION_TAG_NAME}" "Name=instance-state-name,Values=running" \
            --query 'length(Reservations[*].Instances[*])' \
            --output text)
        if [[ ${instance_count} != "1" ]]; then
            echo "Error: expected exactly one running Bastion instance for tag Name=${BASTION_TAG_NAME}, found ${instance_count}" >&2
            return 1
        fi
        bastion_id=$(aws ec2 describe-instances \
            --filters "Name=tag:Name,Values=${BASTION_TAG_NAME}" "Name=instance-state-name,Values=running" \
            --query 'Reservations[0].Instances[0].InstanceId' \
            --output text)

        if [[ -z ${bastion_id} ]]; then
            echo "Error: No running Bastion instance found with tag Name=${BASTION_TAG_NAME}" >&2
            echo "Please specify bastion_instance_id explicitly or check the bastion_tag_name filter" >&2
            return 1
        fi

        echo "Auto-detected Bastion instance ID: ${bastion_id}"
    fi

    echo "BASTION_ID=${bastion_id}" >> "$GITHUB_ENV"
    echo "bastion_id=${bastion_id}" >> "$GITHUB_OUTPUT"

    echo "Verifying Session Manager connectivity to ${bastion_id}..."
    aws ssm describe-instance-information --filters "Key=InstanceIds,Values=${bastion_id}" --query 'InstanceInformationList[*].[InstanceId,PingStatus]' --output table

    echo "Bastion setup completed successfully"
}

if [[ ${BASH_SOURCE[0]} == "${0}" ]]; then
    setup_bastion_connection || exit $?
fi
