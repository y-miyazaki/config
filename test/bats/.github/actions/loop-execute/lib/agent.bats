#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154
bats_require_minimum_version 1.5.0

# Tests for .github/actions/loop-execute/lib/agent.sh
#
# Use cases:
# - run_agent_capture preserves USAGE_* unlike pipe to tee
# - harvest_workspace_into_worktree copies modified files from GITHUB_WORKSPACE
# - harvest_workspace_into_worktree deletes paths removed in GITHUB_WORKSPACE
# - harvest_workspace_into_worktree is a no-op when workspace equals worktree
# - harvest_workspace_into_worktree harvests a renamed file instead of failing
# - harvest_workspace_into_worktree keeps the source file of a copy
# - run_agent runs claude makers in acceptEdits and checkers in dontAsk, and forwards model/max-turns
# - run_agent forwards EFFORT to claude and warns when the engine has no effort flag
# - run_agent opens one usage session per invocation and tags it with USAGE_ROLE
# - run_agent loads project settings but never grants workspace trust
# - run_agent passes the fixed read baseline plus caller rules, and the fixed deny list
# - the fixed deny list blocks --output writes from git diff/log/show and env dumps,
#   leaves the platform's read commands and the read-only gh rules callers declare
#   reachable, and neither fixed list names a consumer path
# - run_agent leaves the copilot/codex/cursor arguments free of claude permission flags
# - run_agent reads AGENT_ENGINE / AGENT_TOOL_ALLOWLIST, not the legacy ENGINE /
#   AGENT_ALLOWED_TOOLS names
# - warn_unsupported_allowed_tools warns for engines with incompatible rule syntax

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

# Fixed values copied from the plan, not derived from agent.sh, so a drift in
# CLAUDE_PLATFORM_*_RULES fails these tests.
EXPECTED_ALLOW_BASELINE='Bash(git diff:*) Bash(git log:*) Bash(git show:*) Bash(git status:*)'
EXPECTED_DENY_RULES='Bash(curl:*) Bash(env:*) Bash(gh api *--method*) Bash(gh api *-X DELETE*) Bash(gh api *-X PATCH*) Bash(gh api *-X POST*) Bash(gh api *-X PUT*) Bash(gh issue close:*) Bash(gh issue comment:*) Bash(gh issue create:*) Bash(gh issue delete:*) Bash(gh issue edit:*) Bash(gh label create:*) Bash(gh label delete:*) Bash(gh label edit:*) Bash(gh pr close:*) Bash(gh pr comment:*) Bash(gh pr create:*) Bash(gh pr edit:*) Bash(gh pr merge:*) Bash(gh pr review:*) Bash(gh release create:*) Bash(gh release delete:*) Bash(gh release edit:*) Bash(gh release upload:*) Bash(gh run cancel:*) Bash(gh run rerun:*) Bash(gh secret:*) Bash(gh variable:*) Bash(gh workflow run:*) Bash(git diff *--output*) Bash(git log *--output*) Bash(git push:*) Bash(git show *--output*) Bash(printenv:*) Bash(sudo:*) Bash(wget:*)'

setup() {
    bats_source_rel ".github/actions/loop-execute/lib/usage.sh"
    bats_source_rel ".github/actions/loop-execute/lib/agent.sh"
    reset_usage_totals
    FIXTURE="$(bats_workspace_root)/test/fixtures/loop-execute/cursor-stream-json-usage.ndjson"
}

# _deny_rule_matching: Print the first platform deny rule that matches a command
#
# Arguments:
#   $1 - Command text as the agent would write it
#
# Returns:
#   0 when a rule matches (printed), 1 when none does
_deny_rule_matching() {
    local cmd="$1" deny_rule pattern

    for deny_rule in "${CLAUDE_PLATFORM_DENY_RULES[@]}"; do
        pattern="${deny_rule#Bash(}"
        pattern="${pattern%)}"
        # ":*" means the same as a trailing " *" and also matches the bare command.
        if [[ ${pattern} == *':*' ]]; then
            pattern="${pattern%:\*}"
            # shellcheck disable=SC2053
            if [[ ${cmd} == ${pattern} || ${cmd} == ${pattern}' '* ]]; then
                echo "${deny_rule}"
                return 0
            fi
            continue
        fi
        # shellcheck disable=SC2053
        if [[ ${cmd} == ${pattern} ]]; then
            echo "${deny_rule}"
            return 0
        fi
    done
    return 1
}

# _stub_claude_engine: Stub the claude CLI and MCP helpers so run_agent records its args
#
# Arguments:
#   $1 - File that receives the recorded argument line
_stub_claude_engine() {
    local args_file="$1"

    mkdir -p "${BATS_TEST_TMPDIR}/bin"
    cat > "${BATS_TEST_TMPDIR}/bin/claude" << STUB
#!/usr/bin/env bash
printf '%s\n' "\$*" > "${args_file}"
STUB
    chmod +x "${BATS_TEST_TMPDIR}/bin/claude"
    PATH="${BATS_TEST_TMPDIR}/bin:${PATH}"
    function prepare_agent_mcps { :; }
    function append_agent_mcp_args { :; }
    AGENT_ENGINE="claude"
    AGENT_TOKEN="dummy-token"
    PROMPT="test prompt"
    MAX_TURNS="5"
    MODEL="claude-sonnet-5"
    WORKING_DIRECTORY="."
    DETECT_JSON_FILE=""
}

@test "run_agent_capture preserves USAGE_* unlike pipe to tee" {
    local out_file

    # Simulate cursor engine by stubbing run_agent to accumulate fixture usage.
    function run_agent {
        accumulate_cursor_stream_usage "${FIXTURE}"
        echo "agent-ok"
        return 0
    }

    out_file="${BATS_TEST_TMPDIR}/agent-out.txt"
    reset_usage_totals
    run_agent_capture "${out_file}" "true" > /dev/null
    [[ ${USAGE_INPUT_TOTAL} -eq 1842 ]]
    [[ ${USAGE_OUTPUT_TOTAL} -eq 17 ]]
    [[ "$(cat "${out_file}")" == "agent-ok" ]]

    # Contrasting anti-pattern: pipe creates a subshell and drops USAGE_*.
    reset_usage_totals
    run_agent "true" 2>&1 | tee "${BATS_TEST_TMPDIR}/tee-out.txt" > /dev/null || true
    [[ ${USAGE_INPUT_TOTAL} -eq 0 ]]
    [[ ${USAGE_OUTPUT_TOTAL} -eq 0 ]]
}

@test "harvest_workspace_into_worktree copies modified files from GITHUB_WORKSPACE" {
    local ws wt

    ws="${BATS_TEST_TMPDIR}/ws-copy"
    wt="${BATS_TEST_TMPDIR}/wt-copy"
    bats_git_fresh_repo "${ws}"
    bats_git_fresh_repo "${wt}"
    printf 'orig\n' > "${ws}/foo.txt"
    printf 'orig\n' > "${wt}/foo.txt"
    bats_git_commit "${ws}" "init"
    bats_git_commit "${wt}" "init"
    printf 'edited\n' > "${ws}/foo.txt"
    printf 'new\n' > "${ws}/added.txt"

    GITHUB_WORKSPACE="${ws}"
    WORKTREE_PATH="${wt}"
    harvest_workspace_into_worktree
    [[ "$(cat "${wt}/foo.txt")" == "edited" ]]
    [[ "$(cat "${wt}/added.txt")" == "new" ]]
}

@test "harvest_workspace_into_worktree deletes paths removed in GITHUB_WORKSPACE" {
    local ws wt

    ws="${BATS_TEST_TMPDIR}/ws-del"
    wt="${BATS_TEST_TMPDIR}/wt-del"
    bats_git_fresh_repo "${ws}"
    bats_git_fresh_repo "${wt}"
    printf 'gone\n' > "${ws}/gone.txt"
    printf 'gone\n' > "${wt}/gone.txt"
    bats_git_commit "${ws}" "init"
    bats_git_commit "${wt}" "init"
    rm -f "${ws}/gone.txt"

    GITHUB_WORKSPACE="${ws}"
    WORKTREE_PATH="${wt}"
    harvest_workspace_into_worktree
    [[ ! -e "${wt}/gone.txt" ]]
}

@test "harvest_workspace_into_worktree keeps the source file of a copy" {
    local ws wt

    ws="${BATS_TEST_TMPDIR}/ws-copy"
    wt="${BATS_TEST_TMPDIR}/wt-copy"
    bats_git_fresh_repo "${ws}"
    bats_git_fresh_repo "${wt}"
    printf 'line1\nline2\nline3\nline4\nline5\n' > "${ws}/src.txt"
    printf 'line1\nline2\nline3\nline4\nline5\n' > "${wt}/src.txt"
    bats_git_commit "${ws}" "init"
    bats_git_commit "${wt}" "init"
    printf 'line1\nline2\nline3\nline4\nline5\nextra\n' > "${ws}/src.txt"
    printf 'line1\nline2\nline3\nline4\nline5\n' > "${ws}/copy.txt"
    bats_git_cmd -C "${ws}" add src.txt copy.txt

    GITHUB_WORKSPACE="${ws}"
    WORKTREE_PATH="${wt}"
    export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=status.renames GIT_CONFIG_VALUE_0=copies
    run bats_git_cmd -C "${ws}" status --porcelain
    [[ $output == *"C  src.txt -> copy.txt"* ]]
    run harvest_workspace_into_worktree
    [ "$status" -eq 0 ]
    [ -e "${wt}/src.txt" ]
    [ -e "${wt}/copy.txt" ]
}

@test "harvest_workspace_into_worktree harvests a renamed file instead of failing" {
    # Regression guard: `git status --porcelain` renders a rename as a single
    # "R  old -> new" line. Treating that whole string as one literal path
    # made harvest fail outright instead of copying the rename.
    local ws wt

    ws="${BATS_TEST_TMPDIR}/ws-rename"
    wt="${BATS_TEST_TMPDIR}/wt-rename"
    bats_git_fresh_repo "${ws}"
    bats_git_fresh_repo "${wt}"
    printf 'content\n' > "${ws}/old.txt"
    printf 'content\n' > "${wt}/old.txt"
    bats_git_commit "${ws}" "init"
    bats_git_commit "${wt}" "init"
    bats_git_cmd -C "${ws}" mv old.txt new.txt

    GITHUB_WORKSPACE="${ws}"
    WORKTREE_PATH="${wt}"
    run harvest_workspace_into_worktree
    [ "$status" -eq 0 ]
    [[ "$(cat "${wt}/new.txt")" == "content" ]]
    [[ ! -e "${wt}/old.txt" ]]
}

@test "harvest_workspace_into_worktree is a no-op when workspace equals worktree" {
    local wt

    wt="${BATS_TEST_TMPDIR}/wt-same"
    bats_git_fresh_repo "${wt}"
    printf 'keep\n' > "${wt}/keep.txt"
    bats_git_commit "${wt}" "init"
    printf 'dirty\n' > "${wt}/keep.txt"

    GITHUB_WORKSPACE="${wt}"
    WORKTREE_PATH="${wt}"
    harvest_workspace_into_worktree
    [[ "$(cat "${wt}/keep.txt")" == "dirty" ]]
}

@test "platform deny rules block --output file writes from git diff, log and show" {
    local cmd

    for cmd in 'git diff --output=/tmp/x HEAD' 'git log -1 --format=x --output=/tmp/x' \
        'git show -s --format=x --output=/tmp/x HEAD' 'env' 'env FOO=1 bash' 'printenv'; do
        run _deny_rule_matching "${cmd}"
        [ "${status}" -eq 0 ] || {
            echo "no deny rule matches: ${cmd}" >&2
            return 1
        }
    done
}

@test "platform deny rules do not cover the read-only gh rules callers declare" {
    local read_rule cmd deny_rule pattern

    for read_rule in 'Bash(gh api -X GET:*)' 'Bash(gh issue view:*)' 'Bash(gh label list:*)' \
        'Bash(gh pr diff:*)' 'Bash(gh pr list:*)' 'Bash(gh pr view:*)' 'Bash(gh repo view:*)' \
        'Bash(gh run list:*)' 'Bash(gh run view:*)'; do
        cmd="${read_rule#Bash(}"
        cmd="${cmd%:\*)}"
        for deny_rule in "${CLAUDE_PLATFORM_DENY_RULES[@]}"; do
            pattern="${deny_rule#Bash(}"
            pattern="${pattern%)}"
            # ":*" means the same as a trailing " *".
            [[ ${pattern} == *':*' ]] && pattern="${pattern%:\*} *"
            # shellcheck disable=SC2053
            if [[ ${cmd} == ${pattern} || "${cmd} x" == ${pattern} ]]; then
                echo "${deny_rule} covers ${read_rule}"
                return 1
            fi
        done
    done
}

@test "platform deny rules leave the platform's own read commands reachable" {
    local cmd

    for cmd in "git diff --name-only origin/main...HEAD -- . ':!.loop/'" \
        'git show 0123abc:path/to/file.sh' 'git log --oneline' 'git status --porcelain' \
        'gh api -X GET repos/o/r/pulls/1/files --paginate' 'gh pr view 1 --json body,comments'; do
        if run _deny_rule_matching "${cmd}" && [ "${status}" -eq 0 ]; then
            echo "${output} denies ${cmd}" >&2
            return 1
        fi
    done
}

@test "platform rules name no consumer path" {
    local rule

    [ "${#CLAUDE_PLATFORM_ALLOW_RULES[@]}" -eq 4 ]
    [ "${#CLAUDE_PLATFORM_DENY_RULES[@]}" -eq 37 ]
    for rule in "${CLAUDE_PLATFORM_ALLOW_RULES[@]}" "${CLAUDE_PLATFORM_DENY_RULES[@]}"; do
        case "${rule}" in
            *.agents/* | *.claude/* | *.apm/* | *scripts/* | *skills/*)
                echo "consumer path in ${rule}"
                return 1
                ;;
        esac
    done
}

@test "run_agent claude maker session grants edit permission and passes model" {
    local args_file

    args_file="${BATS_TEST_TMPDIR}/claude-maker-args.txt"
    _stub_claude_engine "${args_file}"
    run_agent "true" > /dev/null
    grep -q -- "--permission-mode acceptEdits" "${args_file}"
    grep -q -- "--model claude-sonnet-5" "${args_file}"
    grep -q -- "--max-turns 5" "${args_file}"
}

@test "run_agent claude grants read access to the detect JSON directory" {
    local args_file

    args_file="${BATS_TEST_TMPDIR}/claude-add-dir-args.txt"
    _stub_claude_engine "${args_file}"
    mkdir -p "${BATS_TEST_TMPDIR}/status"
    DETECT_JSON_FILE="${BATS_TEST_TMPDIR}/status/tmp.detect"
    run_agent "true" > /dev/null
    grep -q -- "--add-dir ${BATS_TEST_TMPDIR}/status" "${args_file}"
}

@test "run_agent claude adds LOOP_MESSAGE_DIR with --add-dir" {
    local args_file

    args_file="${BATS_TEST_TMPDIR}/claude-message-dir-args.txt"
    _stub_claude_engine "${args_file}"
    LOOP_MESSAGE_DIR="${BATS_TEST_TMPDIR}/loop-message"
    run_agent "true" > /dev/null
    grep -q -- "--add-dir ${BATS_TEST_TMPDIR}/loop-message" "${args_file}"
}

@test "run_agent claude omits the message add-dir when LOOP_MESSAGE_DIR is empty" {
    local args_file

    args_file="${BATS_TEST_TMPDIR}/claude-no-message-dir-args.txt"
    _stub_claude_engine "${args_file}"
    LOOP_MESSAGE_DIR=""
    run_agent "true" > /dev/null
    run ! grep -q -- "--add-dir" "${args_file}"
}

@test "run_agent claude omits add-dir when no detect JSON was materialized" {
    local args_file

    args_file="${BATS_TEST_TMPDIR}/claude-no-add-dir-args.txt"
    _stub_claude_engine "${args_file}"
    DETECT_JSON_FILE=""
    run_agent "true" > /dev/null
    run ! grep -q -- "--add-dir" "${args_file}"
}

@test "run_agent claude appends caller rules after the read baseline" {
    local args_file

    args_file="${BATS_TEST_TMPDIR}/claude-allowed-tools-args.txt"
    _stub_claude_engine "${args_file}"
    AGENT_TOOL_ALLOWLIST="$(printf '%s\n' 'Bash(gh issue view:*)' '' 'Bash(gh label list:*)')"
    run_agent "false" > /dev/null
    grep -qF -- "--allowedTools ${EXPECTED_ALLOW_BASELINE} Bash(gh issue view:*) Bash(gh label list:*) --disallowedTools " "${args_file}"
}

@test "run_agent claude checker session runs in dontAsk mode with the read baseline" {
    local args_file

    args_file="${BATS_TEST_TMPDIR}/claude-checker-args.txt"
    _stub_claude_engine "${args_file}"
    MODEL="claude-opus-5"
    run_agent "false" > /dev/null
    grep -q -- "--permission-mode dontAsk" "${args_file}"
    run ! grep -q -- "acceptEdits" "${args_file}"
    grep -qF -- "--allowedTools ${EXPECTED_ALLOW_BASELINE}" "${args_file}"
    grep -q -- "--model claude-opus-5" "${args_file}"
}

@test "run_agent claude keeps project setting sources for both roles" {
    local args_file

    args_file="${BATS_TEST_TMPDIR}/claude-setting-sources-args.txt"
    _stub_claude_engine "${args_file}"
    run_agent "true" > /dev/null
    grep -q -- "--setting-sources project" "${args_file}"
    : > "${args_file}"
    run_agent "false" > /dev/null
    grep -q -- "--setting-sources project" "${args_file}"
}

@test "run_agent claude never writes workspace trust" {
    local args_file

    args_file="${BATS_TEST_TMPDIR}/claude-no-trust-args.txt"
    _stub_claude_engine "${args_file}"
    HOME="${BATS_TEST_TMPDIR}/home-no-trust"
    GITHUB_WORKSPACE="${BATS_TEST_TMPDIR}/ws-no-trust"
    mkdir -p "${HOME}" "${GITHUB_WORKSPACE}"
    run_agent "true" > /dev/null
    run_agent "false" > /dev/null
    [ ! -e "${HOME}/.claude.json" ]
    run ! declare -F grant_claude_workspace_trust
}

@test "run_agent claude passes only the read baseline when the caller declared no rules" {
    local args_file line allowed

    args_file="${BATS_TEST_TMPDIR}/claude-no-allowed-tools-args.txt"
    _stub_claude_engine "${args_file}"
    AGENT_TOOL_ALLOWLIST=""
    run_agent "true" > /dev/null
    line="$(cat "${args_file}")"
    allowed="${line#*--allowedTools }"
    allowed="${allowed%% --disallowedTools *}"
    [ "${allowed}" = "${EXPECTED_ALLOW_BASELINE}" ]
}

@test "run_agent claude passes the fixed deny list for maker and checker" {
    local args_file role

    args_file="${BATS_TEST_TMPDIR}/claude-deny-args.txt"
    _stub_claude_engine "${args_file}"
    for role in true false; do
        : > "${args_file}"
        run_agent "${role}" > /dev/null
        # Nothing follows the variadic list here except --max-turns/--model.
        grep -qF -- "--disallowedTools ${EXPECTED_DENY_RULES} --max-turns 5 --model claude-sonnet-5" "${args_file}"
    done

    mkdir -p "${BATS_TEST_TMPDIR}/status"
    DETECT_JSON_FILE="${BATS_TEST_TMPDIR}/status/tmp.detect"
    run_agent "false" > /dev/null
    grep -qF -- "--disallowedTools ${EXPECTED_DENY_RULES} --add-dir ${BATS_TEST_TMPDIR}/status" "${args_file}"
}

@test "run_agent ignores the legacy ENGINE and AGENT_ALLOWED_TOOLS names" {
    local args_file

    args_file="${BATS_TEST_TMPDIR}/claude-legacy-args.txt"
    _stub_claude_engine "${args_file}"
    AGENT_TOOL_ALLOWLIST=""
    AGENT_ALLOWED_TOOLS="Bash(gh issue edit:*)"
    run_agent "true" > /dev/null
    run ! grep -qF -- "Bash(gh issue edit:*) --disallowedTools" "${args_file}"

    rm -f "${args_file}"
    unset AGENT_ENGINE
    ENGINE="claude"
    run run_agent "true"
    [ "${status}" -ne 0 ]
    [ ! -f "${args_file}" ]
}

@test "run_agent leaves copilot, codex and cursor arguments without claude permission flags" {
    local engine bin args_file

    mkdir -p "${BATS_TEST_TMPDIR}/bin"
    for bin in copilot codex agent; do
        cat > "${BATS_TEST_TMPDIR}/bin/${bin}" << STUB
#!/usr/bin/env bash
printf '%s\n' "\$*" > "${BATS_TEST_TMPDIR}/${bin}-args.txt"
STUB
        chmod +x "${BATS_TEST_TMPDIR}/bin/${bin}"
    done
    PATH="${BATS_TEST_TMPDIR}/bin:${PATH}"
    function prepare_agent_mcps { :; }
    function append_agent_mcp_args { :; }
    function run_cursor_agent_with_usage {
        local agent_bin="$1"
        shift
        "${agent_bin}" "$@"
    }
    AGENT_TOKEN="dummy-token"
    PROMPT="test prompt"
    WORKING_DIRECTORY="."
    AGENT_TOOL_ALLOWLIST=""

    for engine in copilot codex cursor; do
        AGENT_ENGINE="${engine}"
        run_agent "false" > /dev/null
    done
    for args_file in copilot codex agent; do
        args_file="${BATS_TEST_TMPDIR}/${args_file}-args.txt"
        [ -s "${args_file}" ]
        run ! grep -qE -- "--(permission-mode|allowedTools|disallowedTools|setting-sources)" "${args_file}"
    done
}

@test "warn_unsupported_allowed_tools stays silent for claude and when unset" {
    AGENT_TOOL_ALLOWLIST="Bash(gh issue edit:*)"
    run warn_unsupported_allowed_tools "claude"
    [ "${status}" -eq 0 ]
    [ -z "${output}" ]
    AGENT_TOOL_ALLOWLIST=""
    run warn_unsupported_allowed_tools "copilot"
    [ "${status}" -eq 0 ]
    [ -z "${output}" ]
}

@test "warn_unsupported_allowed_tools warns for engines with incompatible rule syntax" {
    AGENT_TOOL_ALLOWLIST="Bash(gh issue edit:*)"
    run warn_unsupported_allowed_tools "copilot"
    [ "${status}" -eq 0 ]
    [[ ${output} == *"::warning::engine=copilot ignores agent_tool_allowlist"* ]]
    [[ ${output} == *"--allow-tool"* ]]
}

@test "run_agent forwards effort to claude" {
    local args_file

    args_file="${BATS_TEST_TMPDIR}/claude-effort-args.txt"
    _stub_claude_engine "${args_file}"
    EFFORT="high"
    run_agent "true" > /dev/null
    grep -q -- "--effort high" "${args_file}"
}

@test "run_agent omits effort flag when EFFORT is empty" {
    local args_file

    args_file="${BATS_TEST_TMPDIR}/claude-no-effort-args.txt"
    _stub_claude_engine "${args_file}"
    EFFORT=""
    run_agent "true" > /dev/null
    run ! grep -q -- "--effort" "${args_file}"
}

@test "warn_unsupported_effort stays silent for claude and when EFFORT is unset" {
    EFFORT="high"
    run warn_unsupported_effort "claude"
    [[ ${status} -eq 0 ]]
    [[ -z ${output} ]]

    EFFORT=""
    run warn_unsupported_effort "cursor"
    [[ ${status} -eq 0 ]]
    [[ -z ${output} ]]
}

@test "warn_unsupported_effort warns for engines without an effort flag" {
    EFFORT="high"
    run warn_unsupported_effort "cursor"
    [[ ${status} -eq 0 ]]
    [[ ${output} == *"::warning::engine=cursor ignores effort='high'"* ]]
}

@test "run_agent records one usage session tagged with USAGE_ROLE and attempt" {
    local args_file

    args_file="${BATS_TEST_TMPDIR}/claude-role-args.txt"
    _stub_claude_engine "${args_file}"
    USAGE_ROLE="checker"
    ATTEMPT=2
    run_agent "false" > /dev/null

    [ "$(jq -r 'length' <<< "${USAGE_SESSIONS_JSON}")" -eq 1 ]
    [ "$(jq -r '.[0].role' <<< "${USAGE_SESSIONS_JSON}")" = "checker" ]
    [ "$(jq -r '.[0].attempt' <<< "${USAGE_SESSIONS_JSON}")" -eq 2 ]
    [ "${USAGE_SESSION_ROLE}" = "" ]
}
