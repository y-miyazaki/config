#!/usr/bin/env bash
# Install loop AI engine CLI. Requires ENGINE, CLI_VERSION; writes package/version to GITHUB_OUTPUT.
set -euo pipefail

: "${ENGINE:?}"
: "${CLI_VERSION:=latest}"

case "${ENGINE}" in
    claude) PKG="@anthropic-ai/claude-code" ;;
    copilot) PKG="@github/copilot" ;;
    codex) PKG="@openai/codex" ;;
    cursor) PKG="cursor" ;;
    *)
        echo "::error::Unsupported engine: ${ENGINE}"
        exit 1
        ;;
esac

if [[ ${ENGINE} == "cursor" ]]; then
    RESOLVED="${CLI_VERSION}"
elif [[ ${CLI_VERSION} == "latest" ]]; then
    RESOLVED="$(npm view "${PKG}" version)"
else
    RESOLVED="${CLI_VERSION}"
fi

{
    echo "package=${PKG}"
    echo "version=${RESOLVED}"
} >> "${GITHUB_OUTPUT}"

if [[ ${ENGINE} == "cursor" ]]; then
    curl https://cursor.com/install -fsS | bash
    for bindir in "${HOME}/.local/bin" "${HOME}/.cursor/bin"; do
        if [[ -x ${bindir}/agent ]] || [[ -x ${bindir}/cursor-agent ]]; then
            echo "${bindir}" >> "${GITHUB_PATH}"
            exit 0
        fi
    done
    echo "::error::Cursor CLI not found after install"
    exit 1
fi

npm install "${PKG}@${RESOLVED}" --no-save
