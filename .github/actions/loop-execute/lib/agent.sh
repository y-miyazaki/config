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
# - run_agent maps ENGINE to the correct CLI and token env var
# - run_agent_capture avoids pipe subshells so USAGE_* globals persist
# - Implementer sessions may write; verifier sessions are read-only
#######################################

#######################################
# build_agent_prompt: Build implementer prompt with optional verifier feedback
#
# Globals:
#   PROMPT_TEXT - Base implementer prompt
#   PROMPT_IMPLEMENTER_FEEDBACK - Retry prompt template
#
# Arguments:
#   $1 - Verifier feedback markdown (may be empty)
#
# Outputs:
#   Full implementer prompt to stdout
#
# Returns:
#   0 on success
#
#######################################
function build_agent_prompt {
    local feedback="$1"
    if [[ -z ${feedback} ]]; then
        printf '%s\n' "${PROMPT_TEXT}"
        return
    fi
    render_template "${PROMPT_IMPLEMENTER_FEEDBACK}" \
        base_prompt "${PROMPT_TEXT}" \
        feedback "${feedback}"
    printf '\n'
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
#   AGENT_TOKEN - Authentication token for the selected engine
#   ENGINE - Engine name (claude|copilot|codex|cursor)
#   MAX_TURNS - Optional max turns override
#   MODEL - Optional model override
#   PROMPT - Prompt text
#   WORKING_DIRECTORY - Working directory for write-capable engines
#
# Arguments:
#   $1 - allow_writes flag (true|false). Verifier uses false.
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

    prepare_agent_mcps "${ENGINE}" "${working_root}"

    case "${ENGINE}" in
        claude)
            export ANTHROPIC_API_KEY="${AGENT_TOKEN}"
            local -a ARGS=(-p "${PROMPT}" --bare)
            append_agent_mcp_args ARGS "${ENGINE}"
            if [[ -n ${MAX_TURNS:-} ]]; then ARGS+=(--max-turns "${MAX_TURNS}"); fi
            if [[ -n ${MODEL:-} ]]; then ARGS+=(--model "${MODEL}"); fi
            npx claude "${ARGS[@]}"
            ;;
        copilot)
            export COPILOT_GITHUB_TOKEN="${AGENT_TOKEN}"
            local -a ARGS=(-p "${PROMPT}" --no-ask-user)
            append_agent_mcp_args ARGS "${ENGINE}"
            if [[ -n ${MAX_TURNS:-} ]]; then ARGS+=(--max-turns "${MAX_TURNS}"); fi
            if [[ -n ${MODEL:-} ]]; then ARGS+=(--model "${MODEL}"); fi
            npx copilot "${ARGS[@]}"
            ;;
        codex)
            export OPENAI_API_KEY="${AGENT_TOKEN}"
            local -a ARGS=(--prompt "${PROMPT}" --auto-approve)
            append_agent_mcp_args ARGS "${ENGINE}"
            if [[ -n ${MODEL:-} ]]; then ARGS+=(--model "${MODEL}"); fi
            npx codex "${ARGS[@]}"
            ;;
        cursor)
            export CURSOR_API_KEY="${AGENT_TOKEN}"
            local -a ARGS=(-p "${PROMPT}" --print --output-format stream-json --trust)
            append_agent_mcp_args ARGS "${ENGINE}"
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
            echo "::error::Unsupported engine: ${ENGINE}"
            exit 1
            ;;
    esac
}
