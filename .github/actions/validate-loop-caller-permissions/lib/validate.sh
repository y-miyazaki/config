#!/bin/bash
#######################################
# Description:
#   Validate on-loop-* caller workflow permissions against the bundled
#   detect-permissions-profiles registry.
#
# Usage:
#   REGISTRY_FILE=... WORKFLOWS_DIR=... bash lib/validate.sh [--verbose]
#
# Design Rules:
#   - REGISTRY_FILE and WORKFLOWS_DIR are required environment variables
#   - Scans checked-out caller workflows; registry ships with the composite action
#
# Output:
#   Prints validation summary to stdout; errors to stderr
#
# Dependencies:
#   - python3 with PyYAML
#######################################

# Error handling: exit on error, unset variable, or failed pipeline
set -euo pipefail

# Secure defaults
umask 027
export LC_ALL=C.UTF-8

#######################################
# Global variables
#######################################
VERBOSE="${VERBOSE:-false}"

#######################################
# show_usage: Display script usage
#
# Description:
#   Prints usage information and exits successfully.
#
# Arguments:
#   None
#
# Global Variables:
#   None
#
# Returns:
#   Exits 0
#
#######################################
function show_usage {
    cat << EOF
Usage: REGISTRY_FILE=... WORKFLOWS_DIR=... bash lib/validate.sh [--verbose]

Environment:
  REGISTRY_FILE  Path to detect-permissions-profiles.yaml (required)
  WORKFLOWS_DIR  Path to .github/workflows (required)
  VERBOSE        true|false (optional, default false)
EOF
    exit 0
}

#######################################
# parse_arguments: Parse CLI options
#
# Description:
#   Supports --verbose and --help.
#
# Arguments:
#   $@ - Command line arguments
#
# Global Variables:
#   VERBOSE - Set to true when --verbose is passed
#
# Returns:
#   None
#
#######################################
function parse_arguments {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --verbose)
                VERBOSE=true
                shift
                ;;
            -h | --help)
                show_usage
                ;;
            *)
                echo "Unknown option: $1" >&2
                exit 1
                ;;
        esac
    done
}

#######################################
# require_dependencies: Verify required commands and inputs
#
# Description:
#   Ensures python3 is available and required environment variables are set.
#
# Arguments:
#   None
#
# Global Variables:
#   REGISTRY_FILE - Required registry path
#   WORKFLOWS_DIR - Required workflows directory path
#
# Returns:
#   Exits 1 when a dependency or input is missing
#
#######################################
function require_dependencies {
    if ! command -v python3 > /dev/null 2>&1; then
        echo "python3 is required" >&2
        exit 1
    fi

    if [[ -z ${REGISTRY_FILE:-} ]]; then
        echo "REGISTRY_FILE is required" >&2
        exit 1
    fi

    if [[ -z ${WORKFLOWS_DIR:-} ]]; then
        echo "WORKFLOWS_DIR is required" >&2
        exit 1
    fi

    if [[ ! -f ${REGISTRY_FILE} ]]; then
        echo "Profile registry not found: ${REGISTRY_FILE}" >&2
        exit 1
    fi
}

#######################################
# validate_loop_caller_permissions: Run registry-backed validation
#
# Description:
#   Compares on-loop-* caller workflow permissions against profile registry data.
#
# Arguments:
#   None
#
# Global Variables:
#   REGISTRY_FILE - Registry YAML path
#   WORKFLOWS_DIR - Directory containing caller workflows
#   VERBOSE       - Enables per-caller OK logging
#
# Returns:
#   Exits with python subprocess status
#
#######################################
function validate_loop_caller_permissions {
    python3 - "${REGISTRY_FILE}" "${WORKFLOWS_DIR}" "${VERBOSE}" << 'PY'
import re
import sys
from pathlib import Path

import yaml

registry_path = Path(sys.argv[1])
workflows_dir = Path(sys.argv[2])
verbose = sys.argv[3].lower() == "true"

registry = yaml.safe_load(registry_path.read_text(encoding="utf-8"))
baseline = registry.get("execute_baseline", {})
profiles = registry.get("profiles", {})

PROFILE_RE = re.compile(r"^\s*detect_permissions_profile:\s*([^\s#]+)\s*$", re.MULTILINE)
CALLER_USES_RE = re.compile(
    r"uses:\s*\./\.github/workflows/(ci-loop-caller(?:-full-github)?\.yaml)",
    re.MULTILINE,
)
PERMS_BLOCK_RE = re.compile(
    r"^permissions:\s*\n((?:[ \t]+[^\n]+\n)+)", re.MULTILINE
)
PERM_LINE_RE = re.compile(r"^\s*([a-z-]+):\s*([a-z]+)", re.MULTILINE)

def parse_permissions(block: str) -> dict[str, str]:
    return {key: value for key, value in PERM_LINE_RE.findall(block)}

def scope_satisfied(granted: dict[str, str], scope: str, required: str) -> bool:
    actual = granted.get(scope)
    if actual is None:
        return False
    if required == "read":
        return actual in {"read", "write"}
    return actual == required

def profile_for_caller_workflow(caller_workflow: str) -> str | None:
    for name, profile_def in profiles.items():
        if profile_def.get("caller_workflow") == caller_workflow:
            return name
    return None

errors: list[str] = []
checked = 0

if not workflows_dir.is_dir():
    print(f"Workflows directory not found: {workflows_dir}")
    sys.exit(0)

for workflow_path in sorted(workflows_dir.rglob("on-loop-*.yaml")):
    text = workflow_path.read_text(encoding="utf-8")
    uses_match = CALLER_USES_RE.search(text)
    if not uses_match:
        continue

    checked += 1
    rel = workflow_path.relative_to(workflows_dir.parent.parent)
    caller_workflow = uses_match.group(1)

    perms_match = PERMS_BLOCK_RE.search(text)
    if not perms_match:
        errors.append(f"{rel}: missing top-level permissions block")
        continue

    granted = parse_permissions(perms_match.group(1))

    profile_match = PROFILE_RE.search(text)
    profile = profile_match.group(1) if profile_match else profile_for_caller_workflow(caller_workflow)

    if profile is None:
        errors.append(f"{rel}: unknown reusable workflow '{caller_workflow}'")
        continue

    if profile not in profiles:
        errors.append(f"{rel}: unknown detect_permissions_profile '{profile}'")
        continue

    profile_def = profiles[profile]
    expected_workflow = profile_def.get("caller_workflow")
    if expected_workflow and expected_workflow != caller_workflow:
        errors.append(
            f"{rel}: profile '{profile}' expects {expected_workflow}, caller uses {caller_workflow}"
        )
        continue

    if not profile_def.get("implemented", False):
        errors.append(
            f"{rel}: profile '{profile}' is not implemented in {expected_workflow or 'ci-loop-caller'}"
        )
        continue

    for scope, level in baseline.items():
        if not scope_satisfied(granted, scope, level):
            errors.append(
                f"{rel}: workflow permissions missing execute baseline {scope}: {level}"
            )

    caller_adds = profile_def.get("caller_adds") or {}
    for scope, level in caller_adds.items():
        if not scope_satisfied(granted, scope, level):
            errors.append(
                f"{rel}: workflow permissions missing profile '{profile}' addition {scope}: {level}"
            )

    if verbose:
        print(f"OK {rel} profile={profile}")

if checked == 0:
    print("No on-loop-* callers referencing ci-loop-caller reusable workflows found")

if errors:
    print("Loop caller permissions validation failed:", file=sys.stderr)
    for err in errors:
        print(f"  - {err}", file=sys.stderr)
    sys.exit(1)

print(f"Loop caller permissions validation passed ({checked} caller(s))")
PY
}

#######################################
# main: Main process
#
# Description:
#   Parses arguments, validates dependencies, and runs caller permission checks.
#
# Arguments:
#   $@ - Command line arguments
#
# Global Variables:
#   VERBOSE - Verbose logging flag
#
# Returns:
#   Exits with validation status
#
#######################################
function main {
    parse_arguments "$@"
    require_dependencies
    validate_loop_caller_permissions
}

if [[ ${BASH_SOURCE[0]} == "${0}" ]]; then
    main "$@"
fi
