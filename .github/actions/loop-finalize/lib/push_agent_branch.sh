#!/bin/bash
#######################################
# Description:
#   Verify the agent branch bundle that the credential-free agent job produced,
#   re-apply the edit path guards, and push the branch to origin. This is the
#   only place the agent branch reaches the remote.
#
# Usage:
#   AGENT_BRANCH=loop/skill/20261018-123456 AGENT_BRANCH_PREFIX=loop \
#   AGENT_MAKER_SKILL_NAME=skill AGENT_BUNDLE_DIR=... AGENT_RESULT=success \
#   HAS_CHANGES=true BASE_BRANCH=main TO_BRANCH=main STATE_BRANCH=main \
#   TARGET_JSON='{...}' GITHUB_TOKEN=... GITHUB_OUTPUT=... LOOP_FAILURE_FILE=... \
#   bash lib/push_agent_branch.sh
#
# Environment:
#   AGENT_BRANCH - Agent branch name from the agent job (untrusted; may be empty)
#   AGENT_BRANCH_PREFIX - Caller agent_branch_prefix
#   AGENT_BUNDLE_DIR - Directory holding branch.bundle (may be missing)
#   AGENT_EDIT_ALLOWLIST - Comma-separated glob allowlist (empty: no allowlist)
#   AGENT_EDIT_DENYLIST - Comma-separated glob denylist (empty: platform default)
#   AGENT_MAKER_SKILL_NAME - Caller agent_maker_skill_name
#   AGENT_RESULT - Agent job result (success, failure, ...)
#   BASE_BRANCH - Base branch the bundle excludes (parse_target base_branch)
#   GITHUB_OUTPUT - GitHub Actions output file (required)
#   GITHUB_TOKEN - Token for fetch/push auth
#   HAS_CHANGES - Agent job has_changes output (true when a bundle was made)
#   LOOP_FAILURE_FILE - Failure record path (required)
#   STATE_BRANCH - Loop state branch; the agent branch must differ
#   TARGET_JSON - Target JSON; .from.ref is the required ancestor when set
#   TO_BRANCH - Delivery branch; the agent branch must differ
#
# Design Rules:
#   - Order: name check, agent result/changes gate, bundle and base branch
#     presence, base fetch, bundle verify, import of refs/heads/<branch> only,
#     from.ref ancestry, denylist/allowlist/workflow re-check, remote branch
#     absence, push. Nothing reaches the remote before every check passes.
#   - The branch name is compared as a string (<prefix>/<skill>/ then
#     YYYYMMDD-HHMMSS), never embedded in a regex. Later steps must use the
#     branch output, never the raw input.
#   - The diff uses --no-renames so a denylisted file moved to an allowed path
#     still shows its old path. .loop/ is not excluded.
#   - .github/workflows/ changes need an allowlist pattern starting with
#     .github/; ** or an empty allowlist does not allow them.
#   - Changed paths come from list_diff_paths (-z, core.quotePath=false), so
#     non-ASCII names are checked unquoted; a path with a control character,
#     double quote, or backslash fails the push.
#   - Never force-push; an existing remote branch fails. The ls-remote check
#     and the push are not atomic: a branch created in between is
#     fast-forwarded when the agent tip descends from it. Accepted (names are
#     per-second and per-skill, and finalize-only re-runs have no bundle).
#   - Every failure writes pushed=false failed=true first, then records stage
#     push in LOOP_FAILURE_FILE (a recording error only warns), and exits 0 so
#     later steps can branch on it.
#
# Output:
#   GITHUB_OUTPUT, always three lines:
#     branch=<validated name, or empty when empty or invalid>
#     pushed=true|false (true only after a successful push)
#     failed=true|false (true when a check or git step failed)
#   Exit 1 only when GITHUB_OUTPUT or LOOP_FAILURE_FILE is unset; 0 otherwise.
#
#######################################

# Error handling: exit on error, unset variable, or failed pipeline
set -euo pipefail

# Secure defaults
umask 027
export LC_ALL=C.UTF-8

_LOOP_PUSH_AGENT_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../lib/loop" && pwd)"
# shellcheck source=../../lib/loop/edit_paths.sh disable=SC1091
source "${_LOOP_PUSH_AGENT_LIB_DIR}/edit_paths.sh"
# shellcheck source=../../lib/loop/failure_record.sh disable=SC1091
source "${_LOOP_PUSH_AGENT_LIB_DIR}/failure_record.sh"

#######################################
# Global variables
#######################################
AGENT_BRANCH="${AGENT_BRANCH:-}"
AGENT_BRANCH_PREFIX="${AGENT_BRANCH_PREFIX:-}"
AGENT_BUNDLE_DIR="${AGENT_BUNDLE_DIR:-}"
AGENT_EDIT_ALLOWLIST="${AGENT_EDIT_ALLOWLIST:-}"
AGENT_EDIT_DENYLIST="${AGENT_EDIT_DENYLIST:-}"
AGENT_MAKER_SKILL_NAME="${AGENT_MAKER_SKILL_NAME:-}"
AGENT_RESULT="${AGENT_RESULT:-}"
BASE_BRANCH="${BASE_BRANCH:-}"
GITHUB_TOKEN="${GITHUB_TOKEN:-}"
HAS_CHANGES="${HAS_CHANGES:-}"
STATE_BRANCH="${STATE_BRANCH:-}"
TARGET_JSON="${TARGET_JSON:-}"
TO_BRANCH="${TO_BRANCH:-}"
# Maximum number of violating paths quoted in the failure message
MAX_REPORTED_PATHS=5
# Branch name after validate_agent_branch passed (empty until then)
VALIDATED_BRANCH=""

#######################################
# collect_workflow_violations: Find workflow files no .github/ pattern allows
#
# Globals:
#   AGENT_EDIT_ALLOWLIST - Comma-separated glob allowlist
#
# Arguments:
#   $1 - Newline-separated changed file paths
#
# Outputs:
#   Newline-separated .github/workflows/ paths not matched by an allowlist
#   pattern starting with .github/, to stdout
#
# Returns:
#   0 on success
#######################################
function collect_workflow_violations {
    local changed_files="$1"
    local -a github_patterns=() patterns=()
    local file matched pattern

    IFS=',' read -ra patterns <<< "${AGENT_EDIT_ALLOWLIST}"
    for pattern in "${patterns[@]}"; do
        pattern="${pattern#"${pattern%%[![:space:]]*}"}"
        pattern="${pattern%"${pattern##*[![:space:]]}"}"
        if [[ ${pattern} == .github/* ]]; then
            github_patterns+=("${pattern}")
        fi
    done
    while IFS= read -r file; do
        [[ ${file} == .github/workflows/* ]] || continue
        matched="false"
        for pattern in "${github_patterns[@]}"; do
            if path_matches_glob "${file}" "${pattern}"; then
                matched="true"
                break
            fi
        done
        if [[ ${matched} != "true" ]]; then
            printf '%s\n' "${file}"
        fi
    done <<< "${changed_files}"
}

#######################################
# configure_git_auth: Set commit identity and HTTPS push credentials
#
# Globals:
#   GITHUB_TOKEN - Token used for http.extraheader
#
# Arguments:
#   None
#
# Outputs:
#   None
#
# Returns:
#   0 on success, non-zero when git config fails
#######################################
function configure_git_auth {
    git config user.name "github-actions[bot]" \
        && git config user.email "github-actions[bot]@users.noreply.github.com" \
        && git config http.https://github.com/.extraheader "AUTHORIZATION: basic $(printf 'x-access-token:%s' "${GITHUB_TOKEN}" | base64 -w0)"
}

#######################################
# fail_push: Write the failure outputs, record the failure, and exit 0
#
# Globals:
#   LOOP_FAILURE_FILE - Failure record path
#   VALIDATED_BRANCH - Branch name written to the branch output
#
# Arguments:
#   $1 - Failure message
#
# Outputs:
#   Three lines to GITHUB_OUTPUT; redacted ::error:: line to stdout
#
# Returns:
#   Exits 0
#######################################
function fail_push {
    local message="$1"

    write_outputs "${VALIDATED_BRANCH}" "false" "true"
    if ! loop_failure_record "push" "${message}" "${LOOP_FAILURE_FILE}"; then
        echo "::warning::push_agent_branch: could not write the failure record"
    fi
    printf '::error::push_agent_branch: %s\n' "$(redact_sensitive_text "${message//$'\n'/ }")"
    exit 0
}

#######################################
# list_changed_files: List changed paths of the agent branch without renames
#
# Globals:
#   None
#
# Arguments:
#   $1 - from.ref (may be empty)
#   $2 - Base branch (used when from.ref is empty)
#   $3 - Agent branch
#
# Outputs:
#   Newline-separated paths to stdout; git errors and unsafe paths to stderr
#
# Returns:
#   0 on success, 1 when git diff fails, 2 when a path has unsafe characters
#   (see list_diff_paths)
#######################################
function list_changed_files {
    local from_ref="$1"
    local base_branch="$2"
    local branch="$3"
    local range

    if [[ -n ${from_ref} ]]; then
        range="${from_ref}..refs/heads/${branch}"
    else
        range="refs/remotes/origin/${base_branch}...refs/heads/${branch}"
    fi
    list_diff_paths "${range}" --
}

#######################################
# validate_agent_branch: Check the agent branch name against the loop shape
#
# Globals:
#   None
#
# Arguments:
#   $1 - Agent branch name
#   $2 - Agent branch prefix
#   $3 - Maker skill name
#   $4 - to.branch
#   $5 - State branch
#
# Outputs:
#   None
#
# Returns:
#   0 when the name is <prefix>/<skill>/YYYYMMDD-HHMMSS, is a valid ref, and
#   differs from to.branch and the state branch; 1 otherwise (also when the
#   prefix or skill is empty)
#######################################
function validate_agent_branch {
    local branch="$1"
    local prefix="$2"
    local skill="$3"
    local to_branch="$4"
    local state_branch="$5"
    local head suffix

    [[ -n ${branch} && -n ${prefix} && -n ${skill} ]] || return 1
    [[ ${branch} =~ ^[A-Za-z0-9/_.-]+$ && ${branch} != -* ]] || return 1
    head="${prefix}/${skill}/"
    [[ ${branch} == "${head}"* ]] || return 1
    suffix="${branch#"${head}"}"
    [[ ${suffix} =~ ^[0-9]{8}-[0-9]{6}$ ]] || return 1
    [[ ${branch} != "${to_branch}" && ${branch} != "${state_branch}" ]] || return 1
    git check-ref-format "refs/heads/${branch}" || return 1
}

#######################################
# write_outputs: Write the branch, pushed, and failed outputs
#
# Globals:
#   GITHUB_OUTPUT - GitHub Actions output file
#
# Arguments:
#   $1 - Branch output
#   $2 - pushed value
#   $3 - failed value
#
# Outputs:
#   Three lines to GITHUB_OUTPUT
#
# Returns:
#   0 on success
#######################################
function write_outputs {
    {
        echo "branch=$1"
        echo "pushed=$2"
        echo "failed=$3"
    } >> "${GITHUB_OUTPUT}"
}

#######################################
# main: Validate, import, re-check, and push the agent branch
#
# Globals:
#   All Environment variables listed in the header
#   VALIDATED_BRANCH - Set after the name check passes
#
# Arguments:
#   None
#
# Outputs:
#   GITHUB_OUTPUT branch/pushed/failed; ::error:: and the failure record on
#   failure
#
# Returns:
#   0 when done or failed (see failed output); 1 when GITHUB_OUTPUT or
#   LOOP_FAILURE_FILE is unset
#######################################
function main {
    local branch bundle changed diff_status err err_file from_ref quoted remote_status violations

    if [[ -z ${GITHUB_OUTPUT:-} || -z ${LOOP_FAILURE_FILE:-} ]]; then
        echo "::error::push_agent_branch: GITHUB_OUTPUT and LOOP_FAILURE_FILE are required" >&2
        exit 1
    fi

    # 1. No agent branch: nothing to do
    if [[ -z ${AGENT_BRANCH} ]]; then
        write_outputs "" "false" "false"
        return 0
    fi

    # 2. Branch name
    if ! validate_agent_branch "${AGENT_BRANCH}" "${AGENT_BRANCH_PREFIX}" "${AGENT_MAKER_SKILL_NAME}" "${TO_BRANCH}" "${STATE_BRANCH}"; then
        printf -v quoted '%q' "${AGENT_BRANCH}"
        fail_push "invalid agent branch ${quoted}: expected ${AGENT_BRANCH_PREFIX}/${AGENT_MAKER_SKILL_NAME}/YYYYMMDD-HHMMSS, different from to.branch and the state branch"
    fi
    branch="${AGENT_BRANCH}"
    VALIDATED_BRANCH="${branch}"

    # 3. Nothing to push
    if [[ ${AGENT_RESULT} != "success" || ${HAS_CHANGES} != "true" ]]; then
        write_outputs "${branch}" "false" "false"
        return 0
    fi

    # 4. Bundle and base branch
    bundle="${AGENT_BUNDLE_DIR%/}/branch.bundle"
    if [[ -z ${AGENT_BUNDLE_DIR} || ! -f ${bundle} ]]; then
        fail_push "agent bundle not found (has_changes=true): ${bundle}"
    fi
    if [[ -z ${BASE_BRANCH} ]]; then
        fail_push "base branch is empty"
    fi
    if ! [[ ${BASE_BRANCH} =~ ^[A-Za-z0-9/_.-]+$ ]] || [[ ${BASE_BRANCH} == -* ]]; then
        printf -v quoted '%q' "${BASE_BRANCH}"
        fail_push "invalid base branch ${quoted}"
    fi
    if [[ -z ${GITHUB_TOKEN} ]]; then
        fail_push "GITHUB_TOKEN is empty"
    fi

    # 5. Fetch base, verify the bundle, import only the agent branch
    if ! configure_git_auth; then
        fail_push "git auth configuration failed"
    fi
    if ! err="$(git fetch --no-tags origin "+refs/heads/${BASE_BRANCH}:refs/remotes/origin/${BASE_BRANCH}" 2>&1)"; then
        fail_push "fetch of base branch ${BASE_BRANCH} failed: ${err}"
    fi
    if ! err="$(git bundle verify -q "${bundle}" 2>&1)"; then
        fail_push "bundle verify failed: ${err}"
    fi
    if ! err="$(git fetch --no-tags "${bundle}" "refs/heads/${branch}:refs/heads/${branch}" 2>&1)"; then
        fail_push "import of ${branch} from the bundle failed: ${err}"
    fi

    # 6. from.ref ancestry (a missing from.ref object also fails)
    if ! from_ref="$(jq -r '.from.ref // ""' <<< "${TARGET_JSON}" 2>&1)"; then
        fail_push "target_json is not valid JSON: ${from_ref}"
    fi
    if [[ -n ${from_ref} ]]; then
        if ! [[ ${from_ref} =~ ^[A-Za-z0-9/_.-]+$ ]] || [[ ${from_ref} == -* ]]; then
            printf -v quoted '%q' "${from_ref}"
            fail_push "invalid from.ref ${quoted}"
        fi
        if ! err="$(git merge-base --is-ancestor "${from_ref}" "refs/heads/${branch}" 2>&1)"; then
            fail_push "tip of ${branch} is not a descendant of from.ref ${from_ref} (or from.ref is unavailable): ${err}"
        fi
    fi

    # 7. Denylist, allowlist, and workflow re-check on the --no-renames diff
    apply_platform_denylist_default
    if ! err_file="$(mktemp)"; then
        fail_push "could not create a temporary file for the diff"
    fi
    diff_status=0
    changed="$(list_changed_files "${from_ref}" "${BASE_BRANCH}" "${branch}" 2> "${err_file}")" || diff_status=$?
    err="$(cat "${err_file}" 2> /dev/null || true)"
    rm -f "${err_file}"
    if [[ ${diff_status} -eq 2 ]]; then
        fail_push "changed paths of ${branch} include unsafe characters: ${err}"
    fi
    if [[ ${diff_status} -ne 0 ]]; then
        fail_push "diff of ${branch} failed: ${err}"
    fi
    if ! violations="$(
        collect_denylist_violations "${changed}" \
            && collect_allowlist_violations "${changed}" \
            && collect_workflow_violations "${changed}"
    )"; then
        fail_push "edit path check failed"
    fi
    if [[ -n ${violations} ]]; then
        violations="$(awk 'NF && !seen[$0]++' <<< "${violations}" | head -n "${MAX_REPORTED_PATHS}" | paste -sd, -)"
        fail_push "changed paths blocked by denylist, allowlist, or workflow guard: ${violations}"
    fi

    # 8. The remote branch must not exist yet
    set +e
    err="$(git ls-remote --exit-code origin "refs/heads/${branch}" 2>&1)"
    remote_status=$?
    set -e
    if [[ ${remote_status} -eq 0 ]]; then
        fail_push "remote branch ${branch} already exists; refusing to overwrite without force"
    fi
    if [[ ${remote_status} -ne 2 ]]; then
        fail_push "ls-remote for ${branch} failed: ${err}"
    fi

    # 9. Push without force
    if ! err="$(git push --no-verify origin "refs/heads/${branch}:refs/heads/${branch}" 2>&1)"; then
        fail_push "push of ${branch} failed: ${err}"
    fi
    if ! git update-ref "refs/remotes/origin/${branch}" "refs/heads/${branch}"; then
        echo "::warning::push_agent_branch: pushed ${branch} but could not update refs/remotes/origin/${branch}"
    fi
    write_outputs "${branch}" "true" "false"
}

if [[ ${BASH_SOURCE[0]} == "${0}" ]]; then
    main "$@"
fi
