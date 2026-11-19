#!/usr/bin/env bats

# Tests for .github/workflows/ci-vsix-audit.yaml
#
# Use cases:
# - the openvsx download uses the universal build, else linux-x64, for extensions published only as platform builds
# - the openvsx download fails when no usable build exists or the download URL is not on open-vsx.org
# - the marketplace download still goes through vsix-audit download
# - the embedded extractor reads devcontainer.json extensions and ignores commented-out entries
# - the embedded extractor reads .vscode/extensions.json recommendations and de-duplicates across files
# - the embedded extractor keeps // inside strings and tolerates trailing commas
# - the embedded extractor rejects entries that are not publisher.name[@version] and unreadable files
# - the embedded extractor writes nothing when no configuration file exists
# - the input validation accepts a sha256 image digest and rejects tags, short or uppercase digests
# - the scan gates only on the intel and ioc modules without --strict, at critical severity by default
# - the workflow declares the reusable inputs in alphabetical order

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

setup() {
    WORKFLOW="$(bats_workspace_root)/.github/workflows/ci-vsix-audit.yaml"
    FIXTURE_DIR="$(mktemp -d)"
    EXTRACTOR="${FIXTURE_DIR}/extract.js"
    IDS_FILE="${FIXTURE_DIR}/ids.txt"
    VALIDATOR="${FIXTURE_DIR}/validate.sh"
    DOWNLOADER="${FIXTURE_DIR}/download.sh"
    # Pull the node heredoc out of the "Extract Extension IDs" step and drop the YAML indent.
    awk '/^ +node - .*<<.NODE.$/ { in_js = 1; next } /^ +NODE$/ { in_js = 0 } in_js { print }' "${WORKFLOW}" \
        | sed 's/^ \{10\}//' > "${EXTRACTOR}"
    # Pull the run script of the "Validate Inputs" step (up to the next step) and drop the YAML indent.
    awk '/^      - name: Validate Inputs$/ { in_step = 1; next } in_step && /^      - name:/ { in_step = 0 } in_step && in_run { print } in_step && /^        run: \|$/ { in_run = 1 }' "${WORKFLOW}" \
        | sed 's/^ \{10\}//' > "${VALIDATOR}"
    # Pull the run script of the "Download Extensions" step (up to the next step) and drop the YAML indent.
    awk '/^      - name: Download Extensions$/ { in_step = 1; next } in_step && /^      - name:/ { in_step = 0 } in_step && in_run { print } in_step && /^        run: \|$/ { in_run = 1 }' "${WORKFLOW}" \
        | sed 's/^ \{10\}//' > "${DOWNLOADER}"
}

teardown() {
    rm -rf "${FIXTURE_DIR}"
}

# run_downloader <registry> <id> <api_json>: run the download step with docker and curl stubbed.
# The API stub returns <api_json>; a curl with -o writes a placeholder VSIX; calls are logged.
run_downloader() {
    local registry="$1" id="$2" api_json="$3"
    mkdir -p "${FIXTURE_DIR}/bin" "${FIXTURE_DIR}/tmp"
    printf '%s\n' "${id}" > "${FIXTURE_DIR}/tmp/vsix-ids.txt"
    printf '%s' "${api_json}" > "${FIXTURE_DIR}/api.json"
    : > "${FIXTURE_DIR}/calls.log"
    cat > "${FIXTURE_DIR}/bin/docker" << 'EOF'
#!/bin/bash
echo "docker $*" >> "${CALLS_LOG}"
EOF
    cat > "${FIXTURE_DIR}/bin/curl" << 'EOF'
#!/bin/bash
out=""
args=("$@")
for ((i = 0; i < ${#args[@]}; i++)); do
    [[ ${args[i]} == "-o" ]] && out="${args[i + 1]}"
done
echo "curl ${args[*]: -1}" >> "${CALLS_LOG}"
if [[ -n ${out} ]]; then echo vsix > "${out}"; else cat "${API_JSON}"; fi
EOF
    chmod +x "${FIXTURE_DIR}/bin/docker" "${FIXTURE_DIR}/bin/curl"
    run env PATH="${FIXTURE_DIR}/bin:${PATH}" CALLS_LOG="${FIXTURE_DIR}/calls.log" API_JSON="${FIXTURE_DIR}/api.json" \
        RUNNER_TEMP="${FIXTURE_DIR}/tmp" REGISTRY="${registry}" VSIX_AUDIT_DIGEST="sha256:abc" bash "${DOWNLOADER}"
}

@test "download falls back to linux-x64 when the openvsx extension has no universal build" {
    run_downloader openvsx "anthropic.claude-code@2.1.326" \
        '{"downloads":{"darwin-arm64":"https://open-vsx.org/d/darwin.vsix","linux-x64":"https://open-vsx.org/d/linux-x64.vsix"}}'
    [ "${status}" -eq 0 ]
    grep -q "curl https://open-vsx.org/api/anthropic/claude-code/2.1.326$" "${FIXTURE_DIR}/calls.log"
    grep -q "curl https://open-vsx.org/d/linux-x64.vsix$" "${FIXTURE_DIR}/calls.log"
    run grep -q "download" "${FIXTURE_DIR}/calls.log"
    [ "${status}" -eq 1 ]
    [ -f "${FIXTURE_DIR}/tmp/vsix/anthropic.claude-code-2.1.326.vsix" ]
}

@test "download fails when the openvsx download URL is not on open-vsx.org" {
    run_downloader openvsx "a.b@1.0.0" '{"downloads":{"universal":"https://example.invalid/b.vsix"}}'
    [ "${status}" -eq 1 ]
    [[ ${output} == *"unexpected Open VSX download URL"* ]]
    [ ! -e "${FIXTURE_DIR}/tmp/vsix/a.b-1.0.0.vsix" ]
}

@test "download fails when the openvsx extension has neither a universal nor a linux-x64 build" {
    run_downloader openvsx "a.b@1.0.0" '{"downloads":{"darwin-arm64":"https://open-vsx.org/d/b.vsix"}}'
    [ "${status}" -eq 1 ]
    [[ ${output} == *"no universal or linux-x64 build on Open VSX: a.b@1.0.0"* ]]
}

@test "download queries the latest openvsx version when no version is pinned" {
    run_downloader openvsx "a.b" '{"downloads":{"universal":"https://open-vsx.org/d/b.vsix"}}'
    [ "${status}" -eq 0 ]
    grep -q "curl https://open-vsx.org/api/a/b$" "${FIXTURE_DIR}/calls.log"
    [ -f "${FIXTURE_DIR}/tmp/vsix/a.b.vsix" ]
}

@test "download uses the openvsx universal build when it exists" {
    run_downloader openvsx "a.b@1.0.0" \
        '{"downloads":{"universal":"https://open-vsx.org/d/universal.vsix","linux-x64":"https://open-vsx.org/d/linux-x64.vsix"}}'
    [ "${status}" -eq 0 ]
    grep -q "curl https://open-vsx.org/d/universal.vsix$" "${FIXTURE_DIR}/calls.log"
    run grep -q "linux-x64" "${FIXTURE_DIR}/calls.log"
    [ "${status}" -eq 1 ]
}

@test "download uses vsix-audit for the marketplace registry" {
    run_downloader marketplace "a.b@1.0.0" '{}'
    [ "${status}" -eq 0 ]
    grep -q "download a.b@1.0.0 -o /work" "${FIXTURE_DIR}/calls.log"
    run grep -q "^curl" "${FIXTURE_DIR}/calls.log"
    [ "${status}" -eq 1 ]
}

# run_extractor <config_files>: run the extractor inside the fixture directory.
run_extractor() {
    run bash -c 'cd "$1" && CONFIG_FILES="$2" node - "$3" < "$4"' _ \
        "${FIXTURE_DIR}" "${1:-}" "${IDS_FILE}" "${EXTRACTOR}"
}

@test "extractor fails on a configuration file that cannot be parsed" {
    printf '{ "recommendations": [' > "${FIXTURE_DIR}/extensions.json"
    run_extractor "extensions.json"
    [ "${status}" -eq 1 ]
    [[ ${output} == *"cannot read extensions.json"* ]]
}

@test "extractor fails on entries that are not publisher.name with an optional version" {
    cat > "${FIXTURE_DIR}/devcontainer.json" << 'EOF'
{ "customizations": { "vscode": { "extensions": ["../evil.vsix", "ok.ext@1.0.0"] } } }
EOF
    run_extractor "devcontainer.json"
    [ "${status}" -eq 1 ]
    [[ ${output} == *"unsupported extension entry"* ]]
}

@test "extractor ignores commented-out entries and keeps pinned versions" {
    cat > "${FIXTURE_DIR}/devcontainer.json" << 'EOF'
{
  "customizations": {
    "vscode": {
      "extensions": [
        "esbenp.prettier-vscode@12.4.0",
        // "github.copilot@1.388.0",
        /* "ms-python.python@2026.10.0", */
        "golang.go@0.58.0"
      ]
    }
  }
}
EOF
    run_extractor "devcontainer.json"
    [ "${status}" -eq 0 ]
    [ "$(cat "${IDS_FILE}")" = $'esbenp.prettier-vscode@12.4.0\ngolang.go@0.58.0' ]
}

@test "extractor keeps // inside strings and tolerates trailing commas" {
    cat > "${FIXTURE_DIR}/devcontainer.json" << 'EOF'
{
  "$schema": "https://example.com/schema.json",
  "customizations": { "vscode": { "extensions": ["a.b@1.0.0",], }, },
}
EOF
    run_extractor "devcontainer.json"
    [ "${status}" -eq 0 ]
    [ "$(cat "${IDS_FILE}")" = "a.b@1.0.0" ]
}

@test "extractor reads recommendations and de-duplicates across files" {
    cat > "${FIXTURE_DIR}/devcontainer.json" << 'EOF'
{ "customizations": { "vscode": { "extensions": ["a.b@1.0.0", "c.d@2.0.0"] } } }
EOF
    cat > "${FIXTURE_DIR}/extensions.json" << 'EOF'
{ "recommendations": ["c.d@2.0.0", "e.f"] }
EOF
    run_extractor $'devcontainer.json\nextensions.json'
    [ "${status}" -eq 0 ]
    [ "$(cat "${IDS_FILE}")" = $'a.b@1.0.0\nc.d@2.0.0\ne.f' ]
}

@test "extractor uses the standard locations when config_files is empty" {
    mkdir -p "${FIXTURE_DIR}/.devcontainer" "${FIXTURE_DIR}/.vscode"
    echo '{ "customizations": { "vscode": { "extensions": ["a.b@1.0.0"] } } }' > "${FIXTURE_DIR}/.devcontainer/devcontainer.json"
    echo '{ "recommendations": ["c.d"] }' > "${FIXTURE_DIR}/.vscode/extensions.json"
    run_extractor ""
    [ "${status}" -eq 0 ]
    [ "$(cat "${IDS_FILE}")" = $'a.b@1.0.0\nc.d' ]
}

@test "extractor writes an empty list when no configuration file exists" {
    run_extractor ""
    [ "${status}" -eq 0 ]
    [ ! -s "${IDS_FILE}" ]
}

# run_validator <digest>: run the input validation with valid registry and severity.
run_validator() {
    run env REGISTRY=marketplace SEVERITY=high VSIX_AUDIT_DIGEST="$1" bash "${VALIDATOR}"
}

@test "validation accepts the default sha256 image digest" {
    local digest
    digest="$(awk '/^      vsix_audit_digest:$/ { getline; gsub(/.*default: "|"$/, ""); print }' "${WORKFLOW}")"
    [[ ${digest} =~ ^sha256: ]]
    run_validator "${digest}"
    [ "${status}" -eq 0 ]
}

@test "validation rejects an image tag instead of a digest" {
    run_validator "0.3.0"
    [ "${status}" -eq 1 ]
    [[ ${output} == *"vsix_audit_digest must be sha256"* ]]
}

@test "validation rejects a digest one hex digit short or in uppercase" {
    run_validator "sha256:$(printf 'a%.0s' {1..63})"
    [ "${status}" -eq 1 ]
    run_validator "sha256:$(printf 'A%.0s' {1..64})"
    [ "${status}" -eq 1 ]
    run_validator "sha256:$(printf 'a%.0s' {1..64})"
    [ "${status}" -eq 0 ]
}

@test "scan gates on the intel and ioc modules without --strict" {
    run grep -E 'scan -r /work' "${WORKFLOW}"
    [ "${status}" -eq 0 ]
    [[ ${output} == *"-m intel,ioc"* ]]
    [[ ${output} != *"--strict"* ]]
    [[ ${output} != *"--require-yara"* ]]
    run awk '/^      severity:$/ { getline; print }' "${WORKFLOW}"
    [[ ${output} == *'default: "critical"'* ]]
}

@test "workflow declares reusable inputs in alphabetical order" {
    run bash -c 'awk "/^    inputs:/ { in_inputs = 1; next } /^permissions:/ { in_inputs = 0 } in_inputs && /^      [a-z_]+:\$/ { gsub(/[ :]/, \"\"); print }" "$1"' _ "${WORKFLOW}"
    [ "${status}" -eq 0 ]
    [ "${output}" = "$(sort <<< "${output}")" ]
    [ "$(wc -l <<< "${output}")" -eq 4 ]
}
