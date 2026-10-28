#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154

# Tests for .github/actions/loop-execute/lib/mcp.sh

# Use cases:
# - append_agent_mcp_args adds engine-specific MCP approval flags
# - prepare_agent_mcps writes Codex config into CODEX_HOME
# - resolve_mcp_json_path finds git root from relative working directory
# - resolve_mcp_json_path prefers .mcp.json
# - write_codex_mcp_config renders stdio servers from mcp.json

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

setup() {
    bats_source_rel ".github/actions/loop-execute/lib/mcp.sh"
    MCP_ROOT="${BATS_TEST_TMPDIR}/workspace"
    mkdir -p "${MCP_ROOT}/.cursor"
    cat > "${MCP_ROOT}/.mcp.json" << 'EOF'
{
  "mcpServers": {
    "fetch": {
      "type": "stdio",
      "command": "uvx",
      "args": ["mcp-server-fetch==2025.4.7"]
    },
    "context7": {
      "type": "stdio",
      "command": "npx",
      "args": ["-y", "@upstash/context7-mcp@2.2.5"]
    }
  }
}
EOF
    cp "${MCP_ROOT}/.mcp.json" "${MCP_ROOT}/.cursor/mcp.json"
}

@test "append_agent_mcp_args adds engine-specific MCP approval flags" {
    local -a args=()

    append_agent_mcp_args args cursor
    [[ " ${args[*]} " == *" --approve-mcps "* ]]

    args=()
    append_agent_mcp_args args claude
    [[ " ${args[*]} " == *" --settings "* ]]
    [[ " ${args[*]} " == *"enableAllProjectMcpServers"* ]]

    args=()
    append_agent_mcp_args args copilot
    [[ " ${args[*]} " == *" --allow-all-tools "* ]]
}

@test "prepare_agent_mcps writes Codex config into CODEX_HOME" {
    CODEX_HOME="${BATS_TEST_TMPDIR}/codex-home"
    export CODEX_HOME

    prepare_agent_mcps codex "${MCP_ROOT}"

    [ -f "${CODEX_HOME}/config.toml" ]
    grep -Fq '[mcp_servers.fetch]' "${CODEX_HOME}/config.toml"
}

@test "resolve_mcp_json_path finds git root from relative working directory" {
    local subdir="${MCP_ROOT}/subdir"
    local output

    git -C "${MCP_ROOT}" init -q
    mkdir -p "${subdir}"
    pushd "${subdir}" > /dev/null
    output="$(resolve_mcp_json_path "subdir")"
    popd > /dev/null

    [ "${output}" = "${MCP_ROOT}/.mcp.json" ]
}

@test "resolve_mcp_json_path prefers .mcp.json" {
    run resolve_mcp_json_path "${MCP_ROOT}"
    [ "$status" -eq 0 ]
    [ "${output}" = "${MCP_ROOT}/.mcp.json" ]
}

@test "write_codex_mcp_config renders stdio servers from mcp.json" {
    local config_toml="${BATS_TEST_TMPDIR}/config.toml"

    write_codex_mcp_config "${MCP_ROOT}/.mcp.json" "${config_toml}"

    grep -Fq '[mcp_servers.fetch]' "${config_toml}"
    grep -Fq 'command = "uvx"' "${config_toml}"
    grep -Fq 'mcp-server-fetch==2025.4.7' "${config_toml}"
    grep -Fq '[mcp_servers.context7]' "${config_toml}"
}
