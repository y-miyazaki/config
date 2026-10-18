#!/bin/bash
#######################################
# Description: Agent session helpers for loop-execute
#
# Usage: source "${SCRIPT_DIR}/lib/agent.sh"
#
# Output:
# - None (library file, sourced by other scripts)
#
# Design Rules:
# - run_agent maps AGENT_ENGINE to the correct CLI and token env var
# - run_agent_capture avoids pipe subshells so USAGE_* globals persist
# - Maker sessions may write; checker sessions are read-only
# - Workspace trust is never granted, so the host repository's
#   .claude/settings.json permissions.allow and additionalDirectories stay
#   unused in CI (its deny, ask, hooks and env still apply)
# - Claude permissions come only from the role's --permission-mode, the fixed
#   read-only git baseline, the caller's rules, and the fixed deny list
# - Permission rule syntax is engine-specific; engines that cannot apply the
#   supplied rules warn instead of silently dropping them
#######################################

# Read-only git commands every claude session needs: the maker's synthesis
# prompt and the checker's diff review both run them.
CLAUDE_PLATFORM_ALLOW_RULES=(
    'Bash(git diff:*)'
    'Bash(git log:*)'
    'Bash(git show:*)'
    'Bash(git status:*)'
)

# Commands no claude session may run: GitHub writes, push, outbound transfer,
# environment dumps, privilege escalation, and git diff --output file writes.
CLAUDE_PLATFORM_DENY_RULES=(
    'Bash(curl:*)'
    'Bash(gh api *--method*)'
    'Bash(gh api *-X DELETE*)'
    'Bash(gh api *-X PATCH*)'
    'Bash(gh api *-X POST*)'
    'Bash(gh api *-X PUT*)'
    'Bash(gh issue close:*)'
    'Bash(gh issue comment:*)'
    'Bash(gh issue create:*)'
    'Bash(gh issue delete:*)'
    'Bash(gh issue edit:*)'
    'Bash(gh label create:*)'
    'Bash(gh label delete:*)'
    'Bash(gh label edit:*)'
    'Bash(gh pr close:*)'
    'Bash(gh pr comment:*)'
    'Bash(gh pr create:*)'
    'Bash(gh pr edit:*)'
    'Bash(gh pr merge:*)'
    'Bash(gh pr review:*)'
    'Bash(gh release create:*)'
    'Bash(gh release delete:*)'
    'Bash(gh release edit:*)'
    'Bash(gh release upload:*)'
    'Bash(gh run cancel:*)'
    'Bash(gh run rerun:*)'
    'Bash(gh secret:*)'
    'Bash(gh variable:*)'
    'Bash(gh workflow run:*)'
    'Bash(git diff *--output*)'
    'Bash(git push:*)'
    'Bash(printenv:*)'
    'Bash(sudo:*)'
    'Bash(wget:*)'
)

#######################################
# append_claude_permission_args: Add permission flags for a Claude print session
#
# Description:
#   A print-mode session has no approver, and workspace trust is never granted,
#   so the permission surface is exactly these four parts:
#   - --setting-sources project loads the host repository's project settings
#     (deny/ask rules, hooks, env, .mcp.json); its allow rules stay inactive
#     without workspace trust.
#   - --permission-mode follows the role: acceptEdits for makers (Edit/Write
#     allowed, commands still need a rule) and dontAsk for checkers (every call
#     without an allow rule is denied).
#   - --allowedTools carries CLAUDE_PLATFORM_ALLOW_RULES followed by the rules
#     the calling workflow declared in AGENT_TOOL_ALLOWLIST.
#   - --disallowedTools carries CLAUDE_PLATFORM_DENY_RULES, which outrank every
#     allow rule.
#
# Globals:
#   AGENT_TOOL_ALLOWLIST - Optional newline-separated permission rules (may be unset)
#   CLAUDE_PLATFORM_ALLOW_RULES - Fixed read-only allow baseline (read)
#   CLAUDE_PLATFORM_DENY_RULES - Fixed deny list (read)
#
# Arguments:
#   $1 - Name of the ARGS array variable (nameref)
#   $2 - allow_writes flag (true|false). Checker uses false.
#
# Outputs:
#   None
#
# Returns:
#   None
#
#######################################
function append_claude_permission_args {
    local -n args_ref=$1
    local allow_writes="${2:-true}"
    local -a allow_rules=("${CLAUDE_PLATFORM_ALLOW_RULES[@]}")
    local rule

    args_ref+=(--setting-sources project)
    if [[ ${allow_writes} == "true" ]]; then
        args_ref+=(--permission-mode acceptEdits)
    else
        args_ref+=(--permission-mode dontAsk)
    fi
    if [[ -n ${AGENT_TOOL_ALLOWLIST:-} ]]; then
        while IFS= read -r rule; do
            [[ -n ${rule} ]] && allow_rules+=("${rule}")
        done <<< "${AGENT_TOOL_ALLOWLIST}"
    fi
    args_ref+=(--allowedTools "${allow_rules[@]}")
    args_ref+=(--disallowedTools "${CLAUDE_PLATFORM_DENY_RULES[@]}")
}

#######################################
# build_agent_prompt: Build maker prompt with optional checker feedback
#
# Globals:
#   PROMPT_TEXT - Base maker prompt
#   PROMPT_IMPLEMENTER_FEEDBACK - Retry prompt template
#
# Arguments:
#   $1 - Checker feedback markdown (may be empty)
#
# Outputs:
#   Full maker prompt to stdout
#
# Returns:
#   0 on success
#
#######################################
function build_agent_prompt {
    local feedback="$1"
    local synthesis_block="${2:-}"
    local prompt=""

    if [[ -z ${feedback} ]]; then
        prompt="${PROMPT_TEXT}"
    else
        prompt="$(render_template "${PROMPT_IMPLEMENTER_FEEDBACK}" \
            base_prompt "${PROMPT_TEXT}" \
            feedback "${feedback}")"
    fi
    if [[ -n ${synthesis_block} ]]; then
        prompt="${prompt}"$'\n\n'"${synthesis_block}"
    fi
    printf '%s\n' "${prompt}"
}

#######################################
# build_branch_diff_synthesis_block: Prompt block listing full branch diff paths
#
# Globals:
#   BASE_BRANCH - Branch diff baseline (read)
#
# Arguments:
#   $1 - Changed files (newline-separated, repository-relative)
#
# Outputs:
#   Synthesis checklist markdown to stdout
#
# Returns:
#   0 on success
#
#######################################
function build_branch_diff_synthesis_block {
    local changed_files="$1"
    local path

    printf '%s\n' \
        "## Report synthesis (required before finishing)" \
        "The mechanical checker compares your \`### Changes\` table to the **full branch diff** (\`origin/${BASE_BRANCH}...HEAD\`), including files committed in earlier loop attempts on this branch." \
        "Run \`git diff --name-only origin/${BASE_BRANCH}...HEAD -- . ':!.loop/'\` and ensure **every** listed path has a row under \`### Changes\`." \
        "" \
        "Paths currently in the branch diff:"
    while IFS= read -r path; do
        [[ -z ${path} ]] && continue
        printf -- "- \`%s\`\n" "${path}"
    done <<< "${changed_files}"
}

#######################################
# commit_worktree_if_needed: Commit worktree changes when dirty
#
# Globals:
#   WORKTREE_PATH - Absolute path to the isolated worktree
#
# Arguments:
#   $1 - Commit message
#
# Outputs:
#   None
#
# Returns:
#   0 when a commit was created, 1 when no changes existed
#
#######################################
function commit_worktree_if_needed {
    local msg="$1"
    (
        cd "${WORKTREE_PATH}" || exit
        if git diff --quiet && git diff --cached --quiet && [[ -z "$(git status --porcelain)" ]]; then
            return 1
        fi
        git add -A
        git commit -m "${msg}"
        return 0
    )
}

#######################################
# harvest_workspace_into_worktree: Copy GITHUB_WORKSPACE dirt into WORKTREE_PATH
#
# Description:
#   Cursor and other engines may write the default checkout instead of the
#   isolated worktree. Copy porcelain paths into WORKTREE_PATH so
#   commit_worktree_if_needed can include them. No-op when paths match.
#
# Globals:
#   GITHUB_WORKSPACE - Default checkout (optional)
#   WORKTREE_PATH - Isolated git worktree (required)
#
# Arguments:
#   None
#
# Outputs:
#   Warning when harvest copies or deletes at least one path
#
# Returns:
#   0 on success or no-op; 1 when a path cannot be copied
#
#######################################
function harvest_workspace_into_worktree {
    local workspace worktree line xy path dest src old_path harvested=0

    : "${WORKTREE_PATH:?}"
    if [[ -z ${GITHUB_WORKSPACE:-} || ! -d ${GITHUB_WORKSPACE} ]]; then
        return 0
    fi
    workspace="$(cd "${GITHUB_WORKSPACE}" && pwd)" || return 0
    worktree="$(cd "${WORKTREE_PATH}" && pwd)" || return 1
    if [[ ${workspace} == "${worktree}" ]]; then
        return 0
    fi
    if ! git -C "${workspace}" rev-parse --is-inside-work-tree > /dev/null 2>&1; then
        return 0
    fi

    while IFS= read -r line; do
        [[ -z ${line} ]] && continue
        xy="${line:0:2}"
        path="${line:3}"
        if [[ ${xy} == R* || ${xy} == C* ]] && [[ ${path} == *" -> "* ]]; then
            # Rename/copy porcelain lines are "old -> new"; only the new path
            # is harvested, and the stale old path is dropped from the
            # worktree so the rename isn't recreated as a duplicate add.
            old_path="${path%% -> *}"
            path="${path##* -> }"
            old_path="${old_path#\"}"
            old_path="${old_path%\"}"
            old_path="${old_path//\\\"/\"}"
            # A copy leaves the source in place, so only renames drop it.
            if [[ ${xy} == R* && -n ${old_path} && ${old_path} != .git/* ]]; then
                rm -rf "${worktree:?}/${old_path}"
            fi
        fi
        if [[ ${path} == \"* ]]; then
            path="${path#\"}"
            path="${path%\"}"
            path="${path//\\\"/\"}"
        fi
        [[ -z ${path} || ${path} == .git/* ]] && continue
        dest="${worktree}/${path}"
        src="${workspace}/${path}"
        if [[ ${xy} == *D* && ! -e ${src} ]]; then
            rm -rf "${dest}"
            harvested=1
            continue
        fi
        if [[ -d ${src} ]]; then
            mkdir -p "${dest}"
            continue
        fi
        if [[ ! -e ${src} ]]; then
            echo "::error::Failed to harvest ${path} from GITHUB_WORKSPACE into worktree"
            return 1
        fi
        mkdir -p "$(dirname "${dest}")"
        if ! cp -a "${src}" "${dest}"; then
            echo "::error::Failed to harvest ${path} from GITHUB_WORKSPACE into worktree"
            return 1
        fi
        harvested=1
    done < <(git -C "${workspace}" status --porcelain)

    if [[ ${harvested} -eq 1 ]]; then
        echo "::warning::Harvested maker edits from GITHUB_WORKSPACE into worktree"
    fi
    return 0
}

# run_agent_capture: Run agent and capture output without a pipe subshell
#
# Description:
#   Writes stdout/stderr to output_file, mirrors the same content to stdout for
#   CI logs, and returns the agent exit code. Avoids `cmd | tee` so USAGE_*
#   globals updated inside run_agent remain visible to the caller.
#
# Globals:
#   USAGE_* - Preserved from run_agent / run_cursor_agent_with_usage
#
# Arguments:
#   $1 - Output file path
#   $2 - allow_writes flag (true|false), forwarded to run_agent
#
# Outputs:
#   None
#
# Returns:
#   Engine CLI exit code
#
#######################################
function run_agent_capture {
    local output_file="${1:?output_file required}"
    local allow_writes="${2:-true}"
    local rc=0

    run_agent "${allow_writes}" > "${output_file}" 2>&1 || rc=$?
    cat "${output_file}"
    return "${rc}"
}

#######################################
# run_agent: Execute the configured AI engine CLI
#
# Globals:
#   AGENT_TOOL_ALLOWLIST - Optional newline-separated extra tool rules (claude only)
#   AGENT_TOKEN - Authentication token for the selected engine
#   ATTEMPT - Optional loop attempt number recorded on the usage session
#   DETECT_JSON_FILE - Optional materialized detect JSON path granted as an extra read directory
#   EFFORT - Optional reasoning effort level (engines with a dedicated flag only)
#   AGENT_ENGINE - Engine name (claude|copilot|codex|cursor)
#   LOOP_MESSAGE_DIR - Optional directory the agent writes message files into, granted as an extra directory (claude only)
#   MAX_TURNS - Optional max turns override
#   MODEL - Optional model override
#   PROMPT - Prompt text
#   USAGE_ROLE - Session role recorded in the usage breakdown (default: agent)
#   WORKING_DIRECTORY - Working directory for write-capable engines
#
# Arguments:
#   $1 - allow_writes flag (true|false). Checker uses false.
#
# Outputs:
#   None
#
# Returns:
#   Engine CLI exit code
#
#######################################
function run_agent {
    local allow_writes="${1:-true}"
    local working_root="${WORKING_DIRECTORY:-.}"
    local rc=0

    prepare_agent_mcps "${AGENT_ENGINE:-}" "${working_root}"
    warn_unsupported_allowed_tools "${AGENT_ENGINE:-}"
    warn_unsupported_effort "${AGENT_ENGINE:-}"

    # Opened here rather than in run_agent_capture: loop-agent-once calls
    # run_agent directly when it has no output file, and that session must be
    # measured too.
    begin_usage_session "${USAGE_ROLE:-agent}" "${ATTEMPT:-}"
    run_agent_engine "${allow_writes}" || rc=$?
    end_usage_session
    return "${rc}"
}

#######################################
# run_agent_engine: Dispatch one session to the configured engine CLI
#
# Globals:
#   Same as run_agent
#
# Arguments:
#   $1 - allow_writes flag (true|false). Checker uses false.
#
# Outputs:
#   None
#
# Returns:
#   Engine CLI exit code
#
#######################################
function run_agent_engine {
    local allow_writes="${1:-true}"
    local session_prompt="${PROMPT:-}"

    case "${AGENT_ENGINE:-}" in
        claude)
            export ANTHROPIC_API_KEY="${AGENT_TOKEN}"
            # stream-json (not --bare) so usage.sh can read the usage event;
            # the wrapper restores the final text on stdout for report parsing.
            local -a ARGS=(-p "${session_prompt}" --output-format stream-json --verbose)
            append_agent_mcp_args ARGS "${AGENT_ENGINE:-}"
            append_claude_permission_args ARGS "${allow_writes}"
            # Detect JSON lives in STATUS_DIR, outside the worktree; without this the
            # agent cannot read the path the prompt points at.
            if [[ -n ${DETECT_JSON_FILE:-} ]]; then ARGS+=(--add-dir "$(dirname "${DETECT_JSON_FILE}")"); fi
            if [[ -n ${LOOP_MESSAGE_DIR:-} ]]; then ARGS+=(--add-dir "${LOOP_MESSAGE_DIR}"); fi
            if [[ -n ${EFFORT:-} ]]; then ARGS+=(--effort "${EFFORT}"); fi
            if [[ -n ${MAX_TURNS:-} ]]; then ARGS+=(--max-turns "${MAX_TURNS}"); fi
            if [[ -n ${MODEL:-} ]]; then ARGS+=(--model "${MODEL}"); fi
            run_claude_agent_with_usage "${ARGS[@]}"
            ;;
        copilot)
            export COPILOT_GITHUB_TOKEN="${AGENT_TOKEN}"
            local -a ARGS=(-p "${session_prompt}" --no-ask-user)
            append_agent_mcp_args ARGS "${AGENT_ENGINE:-}"
            if [[ -n ${MAX_TURNS:-} ]]; then ARGS+=(--max-turns "${MAX_TURNS}"); fi
            if [[ -n ${MODEL:-} ]]; then ARGS+=(--model "${MODEL}"); fi
            copilot "${ARGS[@]}"
            ;;
        codex)
            export OPENAI_API_KEY="${AGENT_TOKEN}"
            local -a ARGS=(--prompt "${session_prompt}" --auto-approve)
            append_agent_mcp_args ARGS "${AGENT_ENGINE:-}"
            if [[ -n ${MODEL:-} ]]; then ARGS+=(--model "${MODEL}"); fi
            codex "${ARGS[@]}"
            ;;
        cursor)
            export CURSOR_API_KEY="${AGENT_TOKEN}"
            local -a ARGS=(-p "${session_prompt}" --print --output-format stream-json --trust)
            append_agent_mcp_args ARGS "${AGENT_ENGINE:-}"
            local agent_bin
            if [[ ${allow_writes} == "true" && ${WORKING_DIRECTORY} != "." ]]; then
                ARGS+=(--force)
            fi
            if [[ -n ${MODEL:-} ]]; then ARGS+=(--model "${MODEL}"); fi
            if command -v agent > /dev/null 2>&1; then
                agent_bin="agent"
            elif command -v cursor-agent > /dev/null 2>&1; then
                agent_bin="cursor-agent"
            else
                echo "::error::Cursor CLI (agent) not found in PATH"
                exit 1
            fi
            run_cursor_agent_with_usage "${agent_bin}" "${ARGS[@]}"
            ;;
        *)
            echo "::error::Unsupported engine: ${AGENT_ENGINE:-}"
            exit 1
            ;;
    esac
}

#######################################
# warn_unsupported_allowed_tools: Report rules the selected engine cannot apply
#
# Description:
#   Permission rule syntax is engine-specific and does not translate: claude
#   scopes a command to any depth, copilot's shell() stops at the first
#   subcommand, cursor reads its own .cursor/cli.json, and codex has no per-tool
#   allowlist at all. Rather than mistranslate, non-claude engines surface the
#   unused rules so the caller moves them to that engine's own config.
#
# Globals:
#   AGENT_TOOL_ALLOWLIST - Optional newline-separated permission rules (read)
#
# Arguments:
#   $1 - Engine name
#
# Outputs:
#   Workflow warning when rules are set for an engine that ignores them
#
# Returns:
#   0 always
#
#######################################
function warn_unsupported_allowed_tools {
    local engine_name="${1:?engine name required}"

    [[ -z ${AGENT_TOOL_ALLOWLIST:-} ]] && return 0
    case "${engine_name}" in
        claude) return 0 ;;
        *)
            echo "::warning::engine=${engine_name} ignores agent_tool_allowlist;" \
                "declare its permissions in the engine's own config" \
                "(copilot: --allow-tool, cursor: .cursor/cli.json, codex: sandbox/approval policy)"
            ;;
    esac
    return 0
}

#######################################
# warn_unsupported_effort: Report EFFORT when the engine has no effort flag
#
# Description:
#   Only engines exposing a dedicated effort flag consume EFFORT. Engines that
#   encode effort in the model ID (for example cursor's `-low` suffix) must set
#   it there instead, so a stray EFFORT is surfaced rather than silently dropped.
#
# Globals:
#   EFFORT - Optional reasoning effort level (read)
#
# Arguments:
#   $1 - Engine name
#
# Outputs:
#   Workflow warning when EFFORT is set for an engine that ignores it
#
# Returns:
#   0 always
#
#######################################
function warn_unsupported_effort {
    local engine_name="${1:?engine name required}"

    [[ -z ${EFFORT:-} ]] && return 0
    case "${engine_name}" in
        claude) return 0 ;;
        *)
            echo "::warning::engine=${engine_name} ignores effort='${EFFORT}'; encode the effort level in the model ID instead"
            ;;
    esac
    return 0
}
