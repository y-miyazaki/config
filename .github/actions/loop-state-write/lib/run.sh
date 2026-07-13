#!/usr/bin/env bash
# Write loop state JSON and commit/push. Env mirrors loop-state-write action inputs.
set -euo pipefail

REJECT_REASON="${REJECT_REASON:-}"
OPEN_REJECTIONS="${OPEN_REJECTIONS:-[]}"
WRITE_TARGET_STATE="${WRITE_TARGET_STATE:-true}"
ACTING_ON_ACTION="${ACTING_ON_ACTION:-}"
ACTING_ON_TARGET_KEY="${ACTING_ON_TARGET_KEY:-}"
ACTING_ON_LOOP_NAME="${ACTING_ON_LOOP_NAME:-}"
ADDITIONAL_COMMIT_PATHS="${ADDITIONAL_COMMIT_PATHS:-}"
STATE_PUSH_BRANCH="${STATE_PUSH_BRANCH:-}"
BASE_BRANCH="${BASE_BRANCH:-main}"
TARGET_KEY="${TARGET_KEY:-}"
OUTCOME="${OUTCOME:-}"
SHA="${SHA:-}"

: "${GH_TOKEN:?}"
: "${STATE_FILE:?}"

git config user.name "github-actions[bot]"
git config user.email "github-actions[bot]@users.noreply.github.com"
git config http.https://github.com/.extraheader "AUTHORIZATION: basic $(printf 'x-access-token:%s' "${GH_TOKEN}" | base64 -w0)"

TARGET_BRANCH="${STATE_PUSH_BRANCH:-${BASE_BRANCH}}"
if ! [[ ${TARGET_BRANCH} =~ ^[a-zA-Z0-9/_.-]+$ ]]; then
    echo "::error::Invalid state push branch: ${TARGET_BRANCH}"
    exit 1
fi

git fetch origin "${TARGET_BRANCH}" --prune
if git show-ref --verify --quiet "refs/remotes/origin/${TARGET_BRANCH}"; then
    git checkout -B "${TARGET_BRANCH}" "origin/${TARGET_BRANCH}"
else
    git checkout -B "${TARGET_BRANCH}"
fi

mkdir -p "$(dirname "${STATE_FILE}")"

if [[ -z ${TARGET_KEY} ]]; then
    echo "::error::target_key is required for loop-state-write"
    exit 1
fi

if [[ ! -f ${STATE_FILE} ]]; then
    echo '{"targets":{}}' > "${STATE_FILE}"
fi

if ! jq -e '.targets' "${STATE_FILE}" > /dev/null 2>&1; then
    echo '{"targets":{}}' > "${STATE_FILE}"
fi

NOW="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

if [[ ${WRITE_TARGET_STATE} == "true" ]]; then
    if [[ -z ${OUTCOME} || -z ${SHA} ]]; then
        echo "::error::outcome and sha are required when write_target_state=true"
        exit 1
    fi
    PREV_CONSECUTIVE="$(jq -r --arg key "${TARGET_KEY}" '.targets[$key].consecutive_failures // 0' "${STATE_FILE}" 2> /dev/null || echo "0")"
    if ! jq -e . <<< "${OPEN_REJECTIONS}" > /dev/null 2>&1; then
        echo "::warning::open_rejections is not valid JSON; using []"
        OPEN_REJECTIONS='[]'
    fi

    case "${OUTCOME}" in
        rejected)
            CONSECUTIVE=$((PREV_CONSECUTIVE + 1))
            ;;
        watch | error | escalated)
            CONSECUTIVE="${PREV_CONSECUTIVE}"
            if [[ ${OUTCOME} != "watch" ]]; then
                OPEN_REJECTIONS='[]'
            fi
            ;;
        *)
            CONSECUTIVE=0
            OPEN_REJECTIONS='[]'
            ;;
    esac

    jq \
        --arg key "${TARGET_KEY}" \
        --arg sha "${SHA}" \
        --arg last_run "${NOW}" \
        --arg outcome "${OUTCOME}" \
        --arg last_reject_reason "${REJECT_REASON}" \
        --argjson consecutive_failures "${CONSECUTIVE}" \
        --argjson open_rejections "${OPEN_REJECTIONS}" \
        '
        .targets = (.targets // {}) |
        .targets[$key] = (
          (.targets[$key] // {})
          | .last_sha = $sha
          | .last_run = $last_run
          | .outcome = $outcome
          | .consecutive_failures = $consecutive_failures
          | .open_rejections = $open_rejections
          | if $last_reject_reason != "" then .last_reject_reason = $last_reject_reason else . end
        )
        ' "${STATE_FILE}" > "${STATE_FILE}.tmp"
    mv "${STATE_FILE}.tmp" "${STATE_FILE}"
fi

case "${ACTING_ON_ACTION}" in
    set)
        jq \
            --arg target_key "${ACTING_ON_TARGET_KEY}" \
            --arg loop_name "${ACTING_ON_LOOP_NAME}" \
            --arg started_at "${NOW}" \
            '.acting_on = {target_key: $target_key, loop_name: $loop_name, started_at: $started_at}' \
            "${STATE_FILE}" > "${STATE_FILE}.tmp"
        mv "${STATE_FILE}.tmp" "${STATE_FILE}"
        ;;
    clear)
        jq 'del(.acting_on)' "${STATE_FILE}" > "${STATE_FILE}.tmp"
        mv "${STATE_FILE}.tmp" "${STATE_FILE}"
        ;;
esac

declare -a paths_to_add=("${STATE_FILE}")
if [[ -n ${ADDITIONAL_COMMIT_PATHS} ]]; then
    item=""
    declare -a extra=()
    IFS=',' read -r -a extra <<< "${ADDITIONAL_COMMIT_PATHS}"
    for item in "${extra[@]}"; do
        item="${item#"${item%%[![:space:]]*}"}"
        item="${item%"${item##*[![:space:]]}"}"
        [[ -z ${item} ]] && continue
        paths_to_add+=("${item}")
    done
fi

has_changes="false"
for path in "${paths_to_add[@]}"; do
    if ! git diff --quiet "${path}" 2> /dev/null || [[ -n $(git status --porcelain "${path}") ]]; then
        has_changes="true"
        break
    fi
done
if [[ ${has_changes} != "true" ]]; then
    echo "No state changes to commit."
    exit 0
fi

for path in "${paths_to_add[@]}"; do
    if [[ -e ${path} ]] || [[ -n $(git status --porcelain "${path}") ]]; then
        git add "${path}" || true
    fi
done
git commit -m "chore(loop): update state [skip ci]"
if git push origin HEAD:"${TARGET_BRANCH}" 2> /dev/null; then
    echo "State pushed to ${TARGET_BRANCH}."
    exit 0
fi

echo "Direct push blocked; opening state PR."
STATE_BRANCH="loop/state-${GITHUB_RUN_ID}-${GITHUB_RUN_ATTEMPT}-$(openssl rand -hex 4)"
git checkout -B "${STATE_BRANCH}"
if ! git push origin "${STATE_BRANCH}"; then
    echo "::error::Failed to push state branch ${STATE_BRANCH}"
    exit 1
fi
PR_URL=$(gh pr create \
    --repo "${GITHUB_REPOSITORY}" \
    --base "${TARGET_BRANCH}" \
    --head "${STATE_BRANCH}" \
    --title "chore(loop): update state [skip ci]" \
    --body "Automated loop state advance to ${SHA} (outcome: ${OUTCOME}).")
if gh pr merge "${PR_URL}" --auto --delete-branch --squash 2> /dev/null; then
    echo "State PR queued for auto-merge: ${PR_URL}"
elif gh pr merge "${PR_URL}" --delete-branch --squash 2> /dev/null; then
    echo "State PR merged: ${PR_URL}"
else
    echo "::warning::State PR requires manual merge: ${PR_URL}"
fi
