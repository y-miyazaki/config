#!/bin/bash
#######################################
# Description:
#   Pin y-miyazaki/config actions and workflows to SHA refs (no @vX.Y.Z).
#
# Usage:
#   bash scripts/self/ci/pin_config_actions.sh [TAG] [--dry-run] [--no-push]
#
# Design Rules:
#   - fix commit → BASE_SHA; tag comes last
#   - Step 4 aligns pins to RELEASE_SHA for zizmor ref-version-mismatch
#   - Tag stays on the release commit; the align commit updates yaml
#
# Output:
#   Git commits, annotated tag, and optional push to origin
#######################################

set -euo pipefail

umask 027
export LC_ALL=C.UTF-8

#######################################
# Global variables
#######################################
DRY_RUN=false
NO_PUSH=false
REPO_ROOT=""
TAG=""

#######################################
# show_usage: Display script usage
#
# Description:
#   Prints usage information and exits successfully.
#
# Globals:
#   None
#
# Arguments:
#   None
#
# Outputs:
#   Usage text to stdout
#
# Returns:
#   Exits 0
#
#######################################
function show_usage {
    cat << EOF
Usage: $0 [TAG] [--dry-run] [--no-push]

Pin y-miyazaki/config actions/workflows to SHA refs (no @vX.Y.Z refs).

Options:
  -h, --help     Display this help message
  --dry-run      Print planned steps without committing, tagging, or pushing
  --no-push      Commit and tag locally without pushing to origin

Examples:
  bash scripts/self/ci/pin_config_actions.sh
  bash scripts/self/ci/pin_config_actions.sh v1.8.14
  bash scripts/self/ci/pin_config_actions.sh --dry-run
  bash scripts/self/ci/pin_config_actions.sh --no-push
EOF
    exit 0
}

#######################################
# parse_arguments: Parse CLI options
#
# Description:
#   Supports TAG, --dry-run, --no-push, and --help.
#
# Globals:
#   DRY_RUN - Set to true when --dry-run is passed
#   NO_PUSH - Set to true when --no-push is passed
#   TAG     - Optional release tag (for example v1.8.14)
#
# Arguments:
#   $@ - Command line arguments
#
# Outputs:
#   None
#
# Returns:
#   Exits 1 on unknown options or duplicate TAG
#
#######################################
function parse_arguments {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h | --help)
                show_usage
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --no-push)
                NO_PUSH=true
                shift
                ;;
            --*)
                echo "Unknown option: $1" >&2
                exit 1
                ;;
            *)
                if [[ -n ${TAG} ]]; then
                    echo "Unexpected argument: $1" >&2
                    exit 1
                fi
                TAG="$1"
                shift
                ;;
        esac
    done
}

#######################################
# all_yaml_files: List workflow and action YAML files
#
# Description:
#   Finds *.yml and *.yaml under .github/workflows and .github/actions.
#
# Globals:
#   None
#
# Arguments:
#   None
#
# Outputs:
#   Sorted file paths, one per line
#
# Returns:
#   None
#
#######################################
function all_yaml_files {
    find . \
        \( -path './.git' -o -path './apm_modules' -o -path './node_modules' \) -prune \
        -o \( -path './.github/workflows/*' -o -path './.github/actions/*' \) \
        \( -name '*.yml' -o -name '*.yaml' \) -type f -print | sort
}

#######################################
# apply_pin_sha: Replace config action pins in YAML files
#
# Description:
#   Rewrites y-miyazaki/config refs to the given SHA and tag comment.
#
# Globals:
#   None
#
# Arguments:
#   $1 - Full commit SHA to pin
#   $2 - Tag comment (for example v1.8.14)
#   $3+ - YAML file paths
#
# Outputs:
#   None
#
# Returns:
#   None
#
#######################################
function apply_pin_sha {
    local sha="$1"
    local tag="$2"
    local file

    shift 2
    for file in "$@"; do
        [[ -f ${file} ]] || continue
        grep -q 'y-miyazaki/config/' "${file}" || continue
        SHA="${sha}" TAG="${tag}" perl -pi -e \
            's/y-miyazaki\/config\/(.+?)\@(?:[a-fA-F0-9]+|v[0-9.]+) # v[0-9.]+/y-miyazaki\/config\/$1\@$ENV{SHA} # $ENV{TAG}/g' \
            "${file}"
    done
}

#######################################
# commit_yaml: Commit changed YAML files
#
# Description:
#   Stages modified YAML files and creates a commit when not in dry-run mode.
#
# Globals:
#   DRY_RUN - Skips git operations when true
#
# Arguments:
#   $1 - Commit message
#
# Outputs:
#   Progress messages to stderr
#
# Returns:
#   1 when there are no YAML changes; 0 on success
#
#######################################
function commit_yaml {
    local message="$1"
    local -a dirty=()

    if [[ ${DRY_RUN} == true ]]; then
        echo "[dry-run] commit: ${message}" >&2
        return 0
    fi

    while IFS= read -r f; do
        dirty+=("${f}")
    done < <(git diff --name-only -- '*.yml' '*.yaml')
    [[ ${#dirty[@]} -gt 0 ]] || return 1

    git add -- "${dirty[@]}"
    git commit --no-verify -m "${message}"
    echo "committed: ${message}" >&2
}

#######################################
# next_patch_tag: Compute the next patch release tag
#
# Description:
#   Increments the latest vMAJOR.MINOR.PATCH tag or returns v0.0.1.
#
# Globals:
#   None
#
# Arguments:
#   None
#
# Outputs:
#   Next tag on stdout (for example v1.2.4)
#
# Returns:
#   None
#
#######################################
function next_patch_tag {
    local latest
    local major minor patch

    latest="$(git tag -l 'v[0-9]*.[0-9]*.[0-9]*' | sort -V | tail -1)"
    if [[ -z ${latest} ]]; then
        echo "v0.0.1"
        return 0
    fi

    latest="${latest#v}"
    IFS='.' read -r major minor patch <<< "${latest}"
    echo "v${major}.${minor}.$((patch + 1))"
}

#######################################
# pin_all_to_head: Pin all config refs to HEAD
#
# Description:
#   Updates every matching YAML pin to the current HEAD SHA and commits.
#
# Globals:
#   DRY_RUN - Skips file updates when true
#   TAG     - Tag comment written beside each pin
#
# Arguments:
#   $1 - Commit message label
#
# Outputs:
#   Progress messages to stderr
#
# Returns:
#   None
#
#######################################
function pin_all_to_head {
    local label="$1"
    local sha
    local -a files=()

    sha="$(git rev-parse HEAD)"
    echo "=== ${label}: all pins → ${sha:0:7} # ${TAG} ===" >&2
    if [[ ${DRY_RUN} == true ]]; then
        echo "[dry-run] pin all to ${sha}" >&2
        return 0
    fi

    mapfile -t files < <(all_yaml_files)
    apply_pin_sha "${sha}" "${TAG}" "${files[@]}"
    commit_yaml "chore: ${label} ${TAG} (${sha:0:7})" || true
}

#######################################
# main: Run the pin-and-tag release workflow
#
# Description:
#   Pins config actions through four commit steps, tags RELEASE_SHA, and pushes.
#
# Globals:
#   DRY_RUN - Skips mutating git operations when true
#   NO_PUSH - Skips git push when true
#   REPO_ROOT - Repository root directory
#   TAG - Release tag to apply and create
#
# Arguments:
#   $@ - Command line arguments
#
# Outputs:
#   Progress and summary to stdout/stderr
#
# Returns:
#   Exits 1 when the repository cannot be resolved
#
#######################################
function main {
    local base_sha=""
    local release_sha=""
    local -a all_files=()
    local -a files=()

    parse_arguments "$@"

    REPO_ROOT="${REPO_ROOT:-$(git rev-parse --show-toplevel 2> /dev/null || true)}"
    if [[ ! -d ${REPO_ROOT}/.git ]]; then
        echo "Repository not found" >&2
        exit 1
    fi
    cd "${REPO_ROOT}"

    git fetch --tags origin 2> /dev/null || true

    if [[ -z ${TAG} ]]; then
        TAG="$(next_patch_tag)"
    fi
    base_sha="$(git rev-parse HEAD)"

    echo "tag:      ${TAG}"
    echo "base_sha: ${base_sha}"
    echo "mode:     SHA only (no @vX.Y.Z refs)"
    echo

    mapfile -t all_files < <(all_yaml_files)

    echo "=== 1: all pins → base SHA ${base_sha:0:7} ==="
    if [[ ${DRY_RUN} == true ]]; then
        echo "[dry-run]"
    else
        apply_pin_sha "${base_sha}" "${TAG}" "${all_files[@]}"
        commit_yaml "chore: pin all to ${TAG} (${base_sha:0:7})" || true
    fi

    pin_all_to_head "pin all to release"
    pin_all_to_head "finalize all pins"

    release_sha="$(git rev-parse HEAD)"
    echo "=== 4: align pins to tag target ${release_sha:0:7} # ${TAG} ==="
    if [[ ${DRY_RUN} == true ]]; then
        echo "[dry-run]"
    else
        mapfile -t files < <(all_yaml_files)
        apply_pin_sha "${release_sha}" "${TAG}" "${files[@]}"
        commit_yaml "chore: align pins to ${TAG} (${release_sha:0:7})" || true
    fi

    echo "=== tag ${TAG} @ ${release_sha:0:7} ==="
    if [[ ${DRY_RUN} != true ]]; then
        git tag -f "${TAG}" "${release_sha}"
        if [[ ${NO_PUSH} != true ]]; then
            git push origin HEAD
            git push --force origin "${TAG}" 2> /dev/null || git push origin "${TAG}"
        fi
    fi

    echo
    echo "Done."
    echo "  release_sha: ${release_sha}"
    echo "  tag_target:  ${release_sha} (${TAG})"
    echo "  yaml pins:   y-miyazaki/config/...@${release_sha} # ${TAG}"
}

if [[ ${BASH_SOURCE[0]} == "${0}" ]]; then
    main "$@"
fi
