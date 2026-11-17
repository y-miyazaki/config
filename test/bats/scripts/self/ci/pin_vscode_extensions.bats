#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154

# Tests for scripts/self/ci/pin_vscode_extensions.sh
#
# Use cases:
# - pinned entries move to the highest stable Marketplace version; pre-release versions are skipped
# - commented-out and unpinned entries stay unchanged
# - --dry-run reports updates without rewriting the file
# - --vscode-version skips versions whose engines.vscode minimum is newer (equal is allowed)
# - versions younger than --min-age-days (default 7; exactly 7 days is allowed) or without a publish date are skipped
# - a pin newer than every allowed version is never downgraded
# - one Marketplace query carries every pinned ID once across files
# - an extension missing from the Marketplace keeps its pin and makes the script exit 1
# - a failed Marketplace request exits 1 without touching the file
# - --help succeeds; unknown options, malformed --min-age-days, and malformed --vscode-version fail

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

PIN_SCRIPT="$(bats_workspace_root)/scripts/self/ci/pin_vscode_extensions.sh"

setup() {
    FIXTURE_DIR="$(mktemp -d)"
    DEVCONTAINER="${FIXTURE_DIR}/devcontainer.json"
    export FAKE_RESPONSE="${FIXTURE_DIR}/response.json"
    export FAKE_REQUEST="${FIXTURE_DIR}/request.json"
    export FAKE_CURL_EXIT=0
    export MARKETPLACE_URL="https://marketplace.invalid/extensionquery"
    # 2026-11-17T00:00:00Z: the 7-day cutoff is 2026-11-10T00:00:00Z
    export NOW_EPOCH=1794873600

    # curl stub: records the request body and writes FAKE_RESPONSE to the -o target.
    mkdir -p "${FIXTURE_DIR}/bin"
    cat > "${FIXTURE_DIR}/bin/curl" << 'EOF'
#!/bin/bash
out=""
while [[ $# -gt 0 ]]; do
    [[ $1 == "-o" ]] && out="$2"
    shift
done
cat > "${FAKE_REQUEST}"
[[ ${FAKE_CURL_EXIT} -eq 0 ]] || exit "${FAKE_CURL_EXIT}"
cp "${FAKE_RESPONSE}" "${out}"
EOF
    chmod +x "${FIXTURE_DIR}/bin/curl"
    export PATH="${FIXTURE_DIR}/bin:${PATH}"

    cat > "${DEVCONTAINER}" << 'EOF'
{
  "customizations": {
    "vscode": {
      "extensions": [
        "redhat.vscode-yaml@1.0.0",
        "hashicorp.terraform@2.40.1",
        "esbenp.prettier-vscode",
        // "redhat.vscode-yaml@0.1.0",
        "golang.go@0.58.0" // for Go
      ]
    }
  }
}
EOF

    # HashiCorp is capitalized as the Marketplace returns it; IDs match case-insensitively.
    cat > "${FAKE_RESPONSE}" << 'EOF'
{ "results": [ { "extensions": [
  { "publisher": { "publisherName": "redhat" }, "extensionName": "vscode-yaml",
    "versions": [
      { "version": "2.1.2026111208", "lastUpdated": "2026-10-01T00:00:00.123Z", "properties": [ { "key": "Microsoft.VisualStudio.Code.PreRelease", "value": "true" } ] },
      { "version": "1.10.0", "lastUpdated": "2026-10-01T00:00:00.123Z", "properties": [ { "key": "Microsoft.VisualStudio.Code.Engine", "value": "^1.200.0" } ] },
      { "version": "1.9.0", "lastUpdated": "2026-10-01T00:00:00Z", "properties": [ { "key": "Microsoft.VisualStudio.Code.Engine", "value": "^1.100.0" } ] },
      { "version": "1.9.0", "lastUpdated": "2026-10-01T00:00:00Z", "targetPlatform": "linux-x64" }
    ] },
  { "publisher": { "publisherName": "HashiCorp" }, "extensionName": "terraform",
    "versions": [
      { "version": "2.42.0" },
      { "version": "2.41.0", "lastUpdated": "2026-11-12T00:00:00.5Z" },
      { "version": "2.40.2", "lastUpdated": "2026-11-10T00:00:00Z" },
      { "version": "2.40.1", "lastUpdated": "2026-10-01T00:00:00Z" }
    ] }
] } ] }
EOF
}

teardown() {
    rm -rf "${FIXTURE_DIR}"
}

@test "--dry-run reports updates without rewriting the file" {
    local before
    before="$(cat "${DEVCONTAINER}")"
    run bash "${PIN_SCRIPT}" --dry-run "${DEVCONTAINER}"
    [[ ${output} == *"redhat.vscode-yaml 1.0.0 -> 1.10.0"* ]]
    [ "$(cat "${DEVCONTAINER}")" = "${before}" ]
}

@test "--help exits successfully" {
    run bash "${PIN_SCRIPT}" --help
    [ "${status}" -eq 0 ]
    [[ ${output} == *"pin_vscode_extensions.sh"* ]]
}

@test "--min-age-days 0 adopts a fresh version but still skips one without a publish date" {
    run bash "${PIN_SCRIPT}" --min-age-days 0 --dry-run "${DEVCONTAINER}"
    [[ ${output} == *"hashicorp.terraform 2.40.1 -> 2.41.0"* ]]
}

@test "--min-age-days rejects a non-integer value" {
    run bash "${PIN_SCRIPT}" --min-age-days 7d "${DEVCONTAINER}"
    [ "${status}" -eq 1 ]
    [[ ${output} == *"--min-age-days needs a non-negative integer"* ]]
}

@test "--vscode-version allows an engine minimum equal to the version" {
    run bash "${PIN_SCRIPT}" --vscode-version 1.100.0 --dry-run "${DEVCONTAINER}"
    [[ ${output} == *"redhat.vscode-yaml 1.0.0 -> 1.9.0"* ]]
}

@test "--vscode-version rejects a malformed version" {
    run bash "${PIN_SCRIPT}" --vscode-version 1.100 "${DEVCONTAINER}"
    [ "${status}" -eq 1 ]
    [[ ${output} == *"--vscode-version needs X.Y.Z"* ]]
}

@test "--vscode-version skips versions that need a newer VS Code" {
    run bash "${PIN_SCRIPT}" --vscode-version 1.150.0 "${DEVCONTAINER}"
    [[ ${output} == *"redhat.vscode-yaml 1.0.0 -> 1.9.0"* ]]
    grep -q '"redhat.vscode-yaml@1.9.0",' "${DEVCONTAINER}"
}

@test "a failed Marketplace request exits 1 and leaves the file unchanged" {
    local before
    before="$(cat "${DEVCONTAINER}")"
    FAKE_CURL_EXIT=22 run bash "${PIN_SCRIPT}" "${DEVCONTAINER}"
    [ "${status}" -eq 1 ]
    [[ ${output} == *"Marketplace query failed"* ]]
    [ "$(cat "${DEVCONTAINER}")" = "${before}" ]
}

@test "a pin newer than every allowed version is not downgraded" {
    sed -i 's/hashicorp.terraform@2.40.1/hashicorp.terraform@2.41.0/' "${DEVCONTAINER}"
    run bash "${PIN_SCRIPT}" "${DEVCONTAINER}"
    [[ ${output} == *"hashicorp.terraform 2.41.0 (newer than latest allowed 2.40.2; unchanged)"* ]]
    grep -q '"hashicorp.terraform@2.41.0",' "${DEVCONTAINER}"
}

@test "an extension missing from the Marketplace keeps its pin and exits 1" {
    run bash "${PIN_SCRIPT}" "${DEVCONTAINER}"
    [ "${status}" -eq 1 ]
    [[ ${output} == *"golang.go 0.58.0 (no stable Marketplace version found; unchanged)"* ]]
    grep -q '"golang.go@0.58.0" // for Go' "${DEVCONTAINER}"
    # Other pins are still updated.
    grep -q '"redhat.vscode-yaml@1.10.0",' "${DEVCONTAINER}"
}

@test "commented-out and unpinned entries stay unchanged" {
    run bash "${PIN_SCRIPT}" "${DEVCONTAINER}"
    grep -q '// "redhat.vscode-yaml@0.1.0",' "${DEVCONTAINER}"
    grep -q '"esbenp.prettier-vscode",' "${DEVCONTAINER}"
}

@test "default 7-day age skips fresh and undated versions and allows exactly 7 days" {
    run bash "${PIN_SCRIPT}" "${DEVCONTAINER}"
    [[ ${output} == *"hashicorp.terraform 2.40.1 -> 2.40.2"* ]]
    grep -q '"hashicorp.terraform@2.40.2",' "${DEVCONTAINER}"
}

@test "one query carries every pinned ID once across files" {
    cp "${DEVCONTAINER}" "${FIXTURE_DIR}/second.json"
    run bash "${PIN_SCRIPT}" --dry-run "${DEVCONTAINER}" "${FIXTURE_DIR}/second.json"
    [ "$(jq -c '[.filters[0].criteria[].value]' "${FAKE_REQUEST}")" = '["redhat.vscode-yaml","hashicorp.terraform","golang.go"]' ]
    [ "$(jq -c '.flags' "${FAKE_REQUEST}")" = "17" ]
}

@test "pinned entries move to the highest stable version and skip pre-release" {
    run bash "${PIN_SCRIPT}" "${DEVCONTAINER}"
    [[ ${output} == *"redhat.vscode-yaml 1.0.0 -> 1.10.0"* ]]
    grep -q '"redhat.vscode-yaml@1.10.0",' "${DEVCONTAINER}"
}

@test "unknown options exit with an error" {
    run bash "${PIN_SCRIPT}" --bogus
    [ "${status}" -eq 1 ]
    [[ ${output} == *"Unknown option: --bogus"* ]]
}
