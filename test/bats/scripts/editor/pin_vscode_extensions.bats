#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154

# Tests for scripts/editor/pin_vscode_extensions.sh
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
# - --registry openvsx reads versions and publish dates from the Open VSX API, skips pre-release and undated versions, and defaults to the Cursor example
# - --registry openvsx adopts a version published exactly 7 days ago and skips one a second younger
# - --registry rejects an unknown value
# - --registry openvsx with --vscode-version skips versions whose engines.vscode minimum is newer (equal is allowed); without it engines.vscode is ignored
# - --registry openvsx keeps the pin and exits 1 when the API request fails
# - without a FILE argument only the VS Code example (env/example/.devcontainer/vscode/devcontainer.json) is targeted

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

PIN_SCRIPT="$(bats_workspace_root)/scripts/editor/pin_vscode_extensions.sh"

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

# openvsx_fixture <key> <json>: serve <json> for the Open VSX request whose URL maps to <key>.
# Key = URL path after the API base with / ? = & replaced by _ (for example redhat_vscode-yaml_versions_size_20).
openvsx_fixture() {
    mkdir -p "${FIXTURE_DIR}/openvsx"
    printf '%s' "$2" > "${FIXTURE_DIR}/openvsx/$1"
}

# openvsx_detail <namespace/name> <version> <timestamp|-> <prerelease> [engines.vscode]: serve one version detail.
openvsx_detail() {
    local key="${1//\//_}_$2"
    local engines=""
    [[ -z ${5:-} ]] || engines=",\"engines\":{\"vscode\":\"$5\"}"
    if [[ $3 == "-" ]]; then
        openvsx_fixture "${key}" "{\"version\":\"$2\",\"preRelease\":$4${engines}}"
    else
        openvsx_fixture "${key}" "{\"version\":\"$2\",\"timestamp\":\"$3\",\"preRelease\":$4${engines}}"
    fi
}

# use_openvsx_stub: replace the Marketplace curl stub with an Open VSX one that serves openvsx_fixture files
# and fails (exit 22, like curl -f on HTTP 404) for any other URL.
use_openvsx_stub() {
    export OPENVSX_URL="https://openvsx.invalid/api"
    export OPENVSX_FIXTURES="${FIXTURE_DIR}/openvsx"
    mkdir -p "${OPENVSX_FIXTURES}"
    cat > "${FIXTURE_DIR}/bin/curl" << 'EOF'
#!/bin/bash
url="${*: -1}"
file="${OPENVSX_FIXTURES}/$(printf '%s' "${url#"${OPENVSX_URL}/"}" | tr '/?=&' '____')"
[[ -f ${file} ]] || exit 22
cat "${file}"
EOF
    chmod +x "${FIXTURE_DIR}/bin/curl"
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

@test "--registry rejects an unknown value" {
    run bash "${PIN_SCRIPT}" --registry npm "${DEVCONTAINER}"
    [ "${status}" -eq 1 ]
    [[ ${output} == *"--registry needs marketplace or openvsx"* ]]
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

@test "openvsx a failed request keeps the pin and exits 1" {
    use_openvsx_stub
    cat > "${DEVCONTAINER}" << 'EOF'
{ "customizations": { "vscode": { "extensions": [
  "redhat.vscode-yaml@1.0.0"
] } } }
EOF
    run bash "${PIN_SCRIPT}" --registry openvsx "${DEVCONTAINER}"
    [ "${status}" -eq 1 ]
    [[ ${output} == *"redhat.vscode-yaml 1.0.0 (no stable Open VSX version found; unchanged)"* ]]
    grep -q '"redhat.vscode-yaml@1.0.0"' "${DEVCONTAINER}"
}

@test "openvsx adopts a version published exactly 7 days ago and skips one a second younger" {
    use_openvsx_stub
    cat > "${DEVCONTAINER}" << 'EOF'
{ "customizations": { "vscode": { "extensions": [
  "a.old@1.0.0",
  "a.young@1.0.0"
] } } }
EOF
    openvsx_fixture "a_old_versions_size_20" '{"versions":{"1.1.0":"u"}}'
    openvsx_detail "a/old" "1.1.0" "2026-11-10T00:00:00Z" false
    openvsx_fixture "a_young_versions_size_20" '{"versions":{"1.1.0":"u"}}'
    openvsx_detail "a/young" "1.1.0" "2026-11-10T00:00:01Z" false
    run bash "${PIN_SCRIPT}" --registry openvsx --dry-run "${DEVCONTAINER}"
    [[ ${output} == *"a.old 1.0.0 -> 1.1.0"* ]]
    [[ ${output} == *"a.young 1.0.0 (no stable Open VSX version found; unchanged)"* ]]
}

@test "openvsx moves pins to the highest stable version and skips pre-release and undated versions" {
    use_openvsx_stub
    cat > "${DEVCONTAINER}" << 'EOF'
{ "customizations": { "vscode": { "extensions": [
  "redhat.vscode-yaml@1.0.0",
  "hashicorp.terraform@2.40.1",
  "esbenp.prettier-vscode",
  // "redhat.vscode-yaml@0.1.0"
  "golang.go@9.0.0"
] } } }
EOF
    # versions are listed newest first, as Open VSX returns them
    openvsx_fixture "redhat_vscode-yaml_versions_size_20" '{"versions":{"2.1.2026111208":"u","1.10.0":"u","1.9.0":"u"}}'
    openvsx_detail "redhat/vscode-yaml" "2.1.2026111208" "2026-10-01T00:00:00.123456Z" true
    openvsx_detail "redhat/vscode-yaml" "1.10.0" "2026-11-12T00:00:00Z" false
    openvsx_detail "redhat/vscode-yaml" "1.9.0" "2026-10-01T00:00:00.5Z" false
    openvsx_fixture "hashicorp_terraform_versions_size_20" '{"versions":{"2.41.0":"u","2.40.1":"u"}}'
    openvsx_detail "hashicorp/terraform" "2.41.0" "-" false
    openvsx_detail "hashicorp/terraform" "2.40.1" "2026-10-01T00:00:00Z" false
    openvsx_fixture "golang_go_versions_size_20" '{"versions":{"0.58.0":"u"}}'
    openvsx_detail "golang/go" "0.58.0" "2026-10-01T00:00:00Z" false
    run bash "${PIN_SCRIPT}" --registry openvsx "${DEVCONTAINER}"
    [ "${status}" -eq 0 ]
    [[ ${output} == *"redhat.vscode-yaml 1.0.0 -> 1.9.0"* ]]
    [[ ${output} == *"hashicorp.terraform 2.40.1 (up to date)"* ]]
    [[ ${output} == *"golang.go 9.0.0 (newer than latest allowed 0.58.0; unchanged)"* ]]
    grep -q '"redhat.vscode-yaml@1.9.0"' "${DEVCONTAINER}"
    grep -q '// "redhat.vscode-yaml@0.1.0"' "${DEVCONTAINER}"
    grep -q '"esbenp.prettier-vscode",' "${DEVCONTAINER}"
}

@test "openvsx uses the Cursor example as the default target" {
    use_openvsx_stub
    run bash "${PIN_SCRIPT}" --registry openvsx --dry-run
    [[ ${output} == *"env/example/.devcontainer/cursor/devcontainer.json: "* ]]
    [[ ${output} != *"/vscode/devcontainer.json"* ]]
}

@test "openvsx with --vscode-version keeps the pin and exits 1 when every version needs a newer VS Code" {
    use_openvsx_stub
    cat > "${DEVCONTAINER}" << 'EOF'
{ "customizations": { "vscode": { "extensions": [
  "a.new@1.0.0"
] } } }
EOF
    openvsx_fixture "a_new_versions_size_20" '{"versions":{"1.1.0":"u"}}'
    openvsx_detail "a/new" "1.1.0" "2026-10-01T00:00:00Z" false "^1.100.0"
    run bash "${PIN_SCRIPT}" --registry openvsx --vscode-version 1.99.3 "${DEVCONTAINER}"
    [ "${status}" -eq 1 ]
    [[ ${output} == *"a.new 1.0.0 (no stable Open VSX version found; unchanged)"* ]]
    grep -q '"a.new@1.0.0"' "${DEVCONTAINER}"
}

@test "openvsx with --vscode-version skips versions that need a newer VS Code and allows an equal minimum" {
    use_openvsx_stub
    cat > "${DEVCONTAINER}" << 'EOF'
{ "customizations": { "vscode": { "extensions": [
  "a.skip@1.0.0",
  "a.equal@1.0.0",
  "a.plain@1.0.0"
] } } }
EOF
    openvsx_fixture "a_skip_versions_size_20" '{"versions":{"1.3.0":"u","1.2.0":"u"}}'
    openvsx_detail "a/skip" "1.3.0" "2026-10-01T00:00:00Z" false "^1.100.0"
    openvsx_detail "a/skip" "1.2.0" "2026-10-01T00:00:00Z" false "^1.99.0"
    openvsx_fixture "a_equal_versions_size_20" '{"versions":{"1.1.0":"u"}}'
    openvsx_detail "a/equal" "1.1.0" "2026-10-01T00:00:00Z" false ">=1.99.3"
    openvsx_fixture "a_plain_versions_size_20" '{"versions":{"1.1.0":"u"}}'
    openvsx_detail "a/plain" "1.1.0" "2026-10-01T00:00:00Z" false
    run bash "${PIN_SCRIPT}" --registry openvsx --vscode-version 1.99.3 --dry-run "${DEVCONTAINER}"
    [ "${status}" -eq 0 ]
    [[ ${output} == *"a.skip 1.0.0 -> 1.2.0"* ]]
    [[ ${output} == *"a.equal 1.0.0 -> 1.1.0"* ]]
    [[ ${output} == *"a.plain 1.0.0 -> 1.1.0"* ]]
}

@test "openvsx without --vscode-version ignores engines.vscode" {
    use_openvsx_stub
    cat > "${DEVCONTAINER}" << 'EOF'
{ "customizations": { "vscode": { "extensions": [
  "a.new@1.0.0"
] } } }
EOF
    openvsx_fixture "a_new_versions_size_20" '{"versions":{"1.1.0":"u"}}'
    openvsx_detail "a/new" "1.1.0" "2026-10-01T00:00:00Z" false "^1.200.0"
    run bash "${PIN_SCRIPT}" --registry openvsx --dry-run "${DEVCONTAINER}"
    [ "${status}" -eq 0 ]
    [[ ${output} == *"a.new 1.0.0 -> 1.1.0"* ]]
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

@test "without a FILE argument the VS Code example is the target and the Cursor example is untouched" {
    run bash "${PIN_SCRIPT}" --dry-run
    [[ ${output} == *"env/example/.devcontainer/vscode/devcontainer.json: "* ]]
    [[ ${output} != *"/cursor/"* ]]
}
