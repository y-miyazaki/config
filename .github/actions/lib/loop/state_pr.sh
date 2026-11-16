#!/bin/bash
#######################################
# Description:
#   Open a loop state pull request when a direct push to the state branch is blocked.
#
# Usage:
#   source state_pr.sh
#   state_pr_open BASE_BRANCH BRANCH_PREFIX TITLE BODY LABEL
#
# Output:
#   None (library file, sourced by other scripts)
#
# Design Rules:
#   - The state branch is named <prefix>-<run id>-<run attempt>-<random hex>
#   - Auto-merge is tried first, then an immediate squash merge, then a warning
#   - A failed branch push or PR creation exits 1; a PR that cannot be merged only warns
#######################################

#######################################
# state_pr_open: Push the current HEAD to a new branch and open a state PR
#
# Globals:
#   GITHUB_REPOSITORY - owner/repo for gh pr create (read)
#   GITHUB_RUN_ATTEMPT - Run attempt used in the branch name (read; defaults to 0)
#   GITHUB_RUN_ID - Run id used in the branch name (read; defaults to 0)
#
# Arguments:
#   $1 - Base branch for the PR
#   $2 - State branch name prefix (for example loop/state)
#   $3 - PR title
#   $4 - PR body
#   $5 - Label used in log lines (for example "State PR")
#
# Outputs:
#   Progress lines on stdout; ::error:: or ::warning:: annotations
#
# Returns:
#   0 on success; exits 1 when the state branch push or PR creation fails
#
#######################################
function state_pr_open {
    local base_branch="$1"
    local branch_prefix="$2"
    local title="$3"
    local body="$4"
    local label="$5"
    local state_branch pr_url

    state_branch="${branch_prefix}-${GITHUB_RUN_ID:-0}-${GITHUB_RUN_ATTEMPT:-0}-$(openssl rand -hex 4)"
    git checkout -B "${state_branch}"
    if ! git push origin "${state_branch}"; then
        echo "::error::Failed to push state branch ${state_branch}"
        exit 1
    fi
    if ! pr_url="$(gh pr create \
        --repo "${GITHUB_REPOSITORY}" \
        --base "${base_branch}" \
        --head "${state_branch}" \
        --title "${title}" \
        --body "${body}")"; then
        echo "::error::Failed to open ${label} from ${state_branch} (branch left on origin)"
        exit 1
    fi
    if gh pr merge "${pr_url}" --auto --delete-branch --squash 2> /dev/null; then
        echo "${label} queued for auto-merge: ${pr_url}"
    elif gh pr merge "${pr_url}" --delete-branch --squash 2> /dev/null; then
        echo "${label} merged: ${pr_url}"
    else
        echo "::warning::${label} requires manual merge: ${pr_url}"
    fi
}
