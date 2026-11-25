#!/bin/bash
#######################################
# Description:
#   Stop hook: block the stop when files were edited after the last code review in this session.
#
# Usage:
#   Called by Claude Code Stop hook (configured in .claude/settings.local.json);
#   receives hook event JSON (transcript_path, stop_hook_active) on stdin.
#
# Design Rules:
#   - Repository-specific: not distributed through apm; registered only in git-ignored
#     .claude/settings.local.json.
#   - Reads the session transcript: an Edit/Write/NotebookEdit tool call on a source-of-truth file
#     counts as a change; a Skill call named code-review counts as a review.
#   - A typed /code-review (command tag in a user message) also counts as a review.
#   - Synced and generated paths (.claude/{rules,skills,agents,hooks,commands,tmp}, .cursor/{rules,
#     skills,agents,hooks}, .agents/, .kiro/, .codex/, .vscode/, apm_modules/, apm.lock.yaml,
#     .github/hooks/, <repo>/tmp/, /tmp/) never count as changes; hand-edited settings do.
#   - Only files under the repository root count; unparsable transcript lines are skipped.
#   - Limits: edits made through Bash (sed, heredoc) are not seen; fixes after a review block once more.
#   - Blocks only when the last change is newer than the last review (or no review exists).
#   - Never re-blocks while stop_hook_active is true (avoids endless stop loops).
#   - Exit 0 silently when jq or the transcript is unavailable.
#
# Output:
#   Claude Code Stop JSON {"decision":"block","reason":...} when a review is missing; nothing otherwise.
#######################################
set -euo pipefail
umask 027
export LC_ALL=C.UTF-8

HOOK_STDIN_DATA=""
if [[ ! -t 0 ]]; then
    HOOK_STDIN_DATA=$(cat)
fi

#######################################
# review_is_missing: Decide whether a change lacks a later review
#
# Globals:
#   None
#
# Arguments:
#   $1 - Transcript JSONL path
#
# Outputs:
#   None
#
# Returns:
#   0 when a change is newer than the last review (or unreviewed), 1 otherwise
#######################################
function review_is_missing() {
    local transcript="$1" result root
    root=$(git rev-parse --show-toplevel 2> /dev/null || pwd)
    result=$(jq -n -R -r --arg root "$root" '
        [inputs | fromjson?] | to_entries as $lines
        | ($lines | map(select(.value.type == "assistant") | . as $l
            | ($l.value.message.content // [] | if type == "array" then . else [] end)[]
            | select(.type == "tool_use") | {idx: $l.key, name: .name, input: .input})) as $calls
        | ($calls
            | map(select(.name | IN("Edit", "Write", "NotebookEdit"))
                | select((.input.file_path // .input.notebook_path // "") as $f
                    | ($f | startswith($root + "/")) and (($f | test("(^|/)\\.(agents|codex|kiro|vscode)/|(^|/)apm_modules/|apm\\.lock\\.yaml$|(^|/)\\.claude/(rules|skills|agents|hooks|commands|tmp)/|(^|/)\\.cursor/(rules|skills|agents|hooks)/|/\\.github/hooks/|^/tmp/")
                        or ($f | startswith($root + "/tmp/"))) | not)))
            | map(.idx) | max // -1) as $edit
        | ([$calls[] | select(.name == "Skill" and ((.input.skill // "") | test("(^|:)code-review$"))) | .idx]
            + [$lines[] | select(.value.type == "user" and ((.value.message.content | if type == "string" then . else ([.[]? | select(.type == "text") | .text] | join(" ")) end) | contains("<command-name>/code-review"))) | .key]
            | max // -1) as $review
        | if $edit > $review then "missing" else "ok" end
    ' "$transcript" 2> /dev/null || printf 'ok')
    [[ $result == "missing" ]]
}

#######################################
# main: Entry point
#
# Globals:
#   HOOK_STDIN_DATA - Hook event JSON
#
# Arguments:
#   None
#
# Outputs:
#   Stop-hook JSON when a review is missing
#
# Returns:
#   0 always
#######################################
function main() {
    command -v jq > /dev/null 2>&1 || exit 0
    [[ -n $HOOK_STDIN_DATA ]] || exit 0
    if [[ $(printf '%s' "$HOOK_STDIN_DATA" | jq -r '.stop_hook_active // false' 2> /dev/null) == "true" ]]; then
        exit 0
    fi
    local transcript
    transcript=$(printf '%s' "$HOOK_STDIN_DATA" | jq -r '.transcript_path // empty' 2> /dev/null || true)
    [[ -n $transcript && -f $transcript ]] || exit 0
    if review_is_missing "$transcript"; then
        printf '%s' "Files were edited after the last /code-review in this session. Run /code-review on the diff, fix in-scope findings, then report (AGENTS.md Self-Review)." \
            | jq -Rs '{decision: "block", reason: .}'
    fi
    exit 0
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
    main "$@"
fi
