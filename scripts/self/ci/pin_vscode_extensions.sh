#!/bin/bash
#######################################
# Description:
#   Update pinned VS Code extension versions ("publisher.name@x.y.z") in
#   devcontainer.json files to the latest stable Visual Studio Marketplace release.
#
# Usage:
#   bash scripts/self/ci/pin_vscode_extensions.sh [--dry-run] [--min-age-days N] [--vscode-version X.Y.Z] [FILE...]
#
# Design Rules:
#   - Only uncommented array entries of the form "publisher.name@version" are read and rewritten;
#     "// ..." lines and unpinned entries stay unchanged
#   - One Marketplace extensionquery POST covers every pinned ID
#   - Pre-release versions are skipped; with --vscode-version, versions whose engines.vscode
#     minimum is newer than that VS Code version are skipped too
#   - Versions published less than --min-age-days ago (default 7, matching Renovate
#     minimumReleaseAge) are skipped; versions without a publish date are skipped too
#   - A pin is never downgraded: a pin newer than every allowed version stays unchanged
#   - Marketplace only: do not run on Open VSX pins (env/example/.devcontainer/cursor/devcontainer.json)
#   - Lookup failures leave the pin unchanged and make the script exit 1 after all other updates
#
# Output:
#   One line per pinned extension on stdout ("FILE: ID OLD -> NEW", "FILE: ID OLD (up to date)",
#   or "FILE: ID OLD (newer than latest allowed NEW; unchanged)")
#######################################

# Error handling: exit on error, unset variable, or failed pipeline
set -euo pipefail

# Secure defaults
umask 027
export LC_ALL=C.UTF-8

#######################################
# Global variables
#######################################
# Default target, relative to the repository root
DEFAULT_FILE="env/example/.devcontainer/vscode/devcontainer.json"
DRY_RUN=false
FILES=()
# Overridable for tests; the public Marketplace endpoint needs no credentials
MARKETPLACE_URL="${MARKETPLACE_URL:-https://marketplace.visualstudio.com/_apis/public/gallery/extensionquery}"
# Minimum days since a version was published before it is adopted (0 disables the filter)
MIN_AGE_DAYS=7
# Current time in epoch seconds; overridable for tests
NOW_EPOCH="${NOW_EPOCH:-$(date +%s)}"
# VS Code version (X.Y.Z) used to filter engines.vscode; empty disables the filter
VSCODE_VERSION=""

#######################################
# show_usage: Display script usage
#
# Description:
#   Prints usage information and exits successfully.
#
# Globals:
#   DEFAULT_FILE - Default target shown in the help text
#
# Arguments:
#   None
#
# Outputs:
#   Usage text to stdout
#
# Returns:
#   Exits 0
#
#######################################
function show_usage {
    cat << EOF
Usage: $(basename "$0") [--dry-run] [--min-age-days N] [--vscode-version X.Y.Z] [FILE...]

Update pinned VS Code extensions ("publisher.name@x.y.z") in devcontainer.json
to the latest stable Visual Studio Marketplace version.

Arguments:
  FILE                    devcontainer.json to update (default: ${DEFAULT_FILE})

Options:
  -h, --help              Display this help message
  --dry-run               Report updates without rewriting files
  --min-age-days N        Skip versions published less than N days ago (default: ${MIN_AGE_DAYS}; 0 disables)
  --vscode-version X.Y.Z  Skip versions whose engines.vscode needs a newer VS Code

Examples:
  bash scripts/self/ci/pin_vscode_extensions.sh --dry-run
  bash scripts/self/ci/pin_vscode_extensions.sh --vscode-version 1.106.0
  bash scripts/self/ci/pin_vscode_extensions.sh --min-age-days 0
  bash scripts/self/ci/pin_vscode_extensions.sh .devcontainer/devcontainer.json
EOF
    exit 0
}

#######################################
# parse_arguments: Parse CLI options
#
# Description:
#   Supports --dry-run, --min-age-days, --vscode-version, --help, and positional FILE arguments.
#
# Globals:
#   DRY_RUN        - Set to true when --dry-run is passed
#   FILES          - Appended with positional arguments
#   MIN_AGE_DAYS   - Set from --min-age-days
#   VSCODE_VERSION - Set from --vscode-version
#
# Arguments:
#   $@ - Command line arguments
#
# Outputs:
#   Error messages to stderr
#
# Returns:
#   Exits 1 on unknown options, an invalid --min-age-days, or an invalid --vscode-version
#
#######################################
function parse_arguments {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h | --help)
                show_usage
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --min-age-days)
                if [[ $# -lt 2 || ! $2 =~ ^[0-9]+$ ]]; then
                    echo "--min-age-days needs a non-negative integer" >&2
                    exit 1
                fi
                MIN_AGE_DAYS="$2"
                shift 2
                ;;
            --vscode-version)
                if [[ $# -lt 2 || ! $2 =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                    echo "--vscode-version needs X.Y.Z" >&2
                    exit 1
                fi
                VSCODE_VERSION="$2"
                shift 2
                ;;
            -*)
                echo "Unknown option: $1" >&2
                exit 1
                ;;
            *)
                FILES+=("$1")
                shift
                ;;
        esac
    done
}

#######################################
# engine_allows: Check an engines.vscode range against a VS Code version
#
# Description:
#   Reads the minimum version from ranges such as "^1.90.0", ">=1.60.0", or "*"
#   and compares it with the given VS Code version. Upper bounds are not evaluated.
#
# Globals:
#   None
#
# Arguments:
#   $1 - engines.vscode value (may be empty)
#   $2 - VS Code version X.Y.Z (empty allows everything)
#
# Outputs:
#   None
#
# Returns:
#   0 when the version is allowed; 1 otherwise
#
#######################################
function engine_allows {
    local engine="$1"
    local vscode="$2"
    local minimum

    [[ -n ${vscode} ]] || return 0
    minimum="$(sed -E 's/^[[:space:]]*[\^~>=]*[[:space:]]*//; s/-.*$//' <<< "${engine}")"
    [[ ${minimum} =~ ^[0-9]+(\.[0-9]+)*$ ]] || return 0
    [[ "$(printf '%s\n%s\n' "${minimum}" "${vscode}" | sort -V | head -1)" == "${minimum}" ]]
}

#######################################
# extract_pins: List pinned extension entries in a file
#
# Description:
#   Prints uncommented array entries that look like "publisher.name@version".
#
# Globals:
#   None
#
# Arguments:
#   $1 - devcontainer.json path
#
# Outputs:
#   "publisher.name@version" lines on stdout
#
# Returns:
#   0 always
#
#######################################
function extract_pins {
    local file="$1"

    { grep -E '^[[:space:]]*"[A-Za-z0-9-]+\.[A-Za-z0-9._-]+@[A-Za-z0-9.+_-]+"[[:space:]]*,?[[:space:]]*(//.*)?$' "${file}" || true; } \
        | sed -E 's/^[[:space:]]*"([^"]+)".*$/\1/'
}

#######################################
# latest_version: Pick the newest allowed version from a Marketplace response
#
# Description:
#   Matches the extension ID case-insensitively, drops pre-release versions, versions
#   published within MIN_AGE_DAYS (or without a publish date), and versions rejected by
#   engine_allows, and prints the highest remaining version.
#
# Globals:
#   MIN_AGE_DAYS   - Minimum age in days of an adopted version
#   NOW_EPOCH      - Current time in epoch seconds
#   VSCODE_VERSION - Passed to engine_allows
#
# Arguments:
#   $1 - Marketplace response JSON file
#   $2 - Extension ID (publisher.name)
#
# Outputs:
#   Version on stdout
#
# Returns:
#   0 on success; 1 when the extension or an allowed version is not found
#
#######################################
function latest_version {
    local response="$1"
    local id="$2"
    local version prerelease engine old_enough
    local -a candidates=()

    # \x1f separates fields: tab is IFS whitespace, so read would merge an empty engine field
    while IFS=$'\x1f' read -r version prerelease engine old_enough; do
        [[ ${prerelease} == "true" ]] && continue
        [[ ${old_enough} == "true" ]] || continue
        engine_allows "${engine}" "${VSCODE_VERSION}" || continue
        [[ ${version} =~ ^[A-Za-z0-9.+_-]+$ ]] || continue
        candidates+=("${version}")
    done < <(jq -r --arg id "${id,,}" --argjson cutoff "$((NOW_EPOCH - MIN_AGE_DAYS * 86400))" '
        .results[0].extensions[]?
        | select(((.publisher.publisherName + "." + .extensionName) | ascii_downcase) == $id)
        | .versions[]?
        | (reduce (.properties // [])[] as $p ({}; .[$p.key] = $p.value)) as $props
        | [.version,
           ($props["Microsoft.VisualStudio.Code.PreRelease"] // "false"),
           ($props["Microsoft.VisualStudio.Code.Engine"] // ""),
           ((.lastUpdated // "" | sub("\\.[0-9]+"; "") | try fromdateiso8601 catch null) as $t
            | if $t == null then "false" else ($t <= $cutoff | tostring) end)]
        | join("\u001f")' "${response}")

    [[ ${#candidates[@]} -gt 0 ]] || return 1
    printf '%s\n' "${candidates[@]}" | sort -uV | tail -1
}

#######################################
# query_marketplace: Fetch version data for extension IDs
#
# Description:
#   Sends one extensionquery POST (IncludeVersions | IncludeVersionProperties).
#
# Globals:
#   MARKETPLACE_URL - extensionquery endpoint
#
# Arguments:
#   $1  - Output JSON file
#   $2+ - Extension IDs (publisher.name)
#
# Outputs:
#   Response JSON written to $1
#
# Returns:
#   Non-zero when the request fails
#
#######################################
function query_marketplace {
    local out="$1"
    shift

    jq -n '{filters: [{criteria: [$ARGS.positional[] | {filterType: 7, value: .}], pageSize: 1000}], flags: 17}' \
        --args "$@" \
        | curl -fsS --max-time 60 -X POST "${MARKETPLACE_URL}" \
            -H 'Accept: application/json;api-version=3.0-preview.1' \
            -H 'Content-Type: application/json' \
            --data-binary @- -o "${out}"
}

#######################################
# rewrite_pin: Replace one pinned version in a file
#
# Description:
#   Rewrites "ID@OLD" to "ID@NEW" on uncommented array entry lines only.
#
# Globals:
#   None
#
# Arguments:
#   $1 - File path
#   $2 - Extension ID as written in the file
#   $3 - Current version
#   $4 - New version
#
# Outputs:
#   None
#
# Returns:
#   Non-zero when perl fails
#
#######################################
function rewrite_pin {
    ID="$2" OLD="$3" NEW="$4" perl -pi -e \
        's/^(\s*")\Q$ENV{ID}\E\@\Q$ENV{OLD}\E"/$1$ENV{ID}\@$ENV{NEW}"/' "$1"
}

#######################################
# main: Update pinned extensions in every target file
#
# Description:
#   Collects pins, queries the Marketplace once, prints each result, and
#   rewrites files unless --dry-run is set.
#
# Globals:
#   DEFAULT_FILE - Used when no FILE is given
#   DRY_RUN      - Skips rewriting when true
#   FILES        - Target files
#
# Arguments:
#   $@ - Command line arguments
#
# Outputs:
#   Results to stdout; errors to stderr
#
# Returns:
#   Exits 1 on missing commands, unreadable files, a failed query, or any unresolved pin
#
#######################################
function main {
    local cmd file pin id old new key repo_root response
    local failed=0
    local -a ids=()
    local -A latest=()
    local -A seen=()

    parse_arguments "$@"

    for cmd in curl jq perl; do
        if ! command -v "${cmd}" > /dev/null 2>&1; then
            echo "Required command not found: ${cmd}" >&2
            exit 1
        fi
    done

    if [[ ${#FILES[@]} -eq 0 ]]; then
        repo_root="$(git rev-parse --show-toplevel 2> /dev/null || pwd)"
        FILES=("${repo_root}/${DEFAULT_FILE}")
    fi
    for file in "${FILES[@]}"; do
        if [[ ! -f ${file} ]]; then
            echo "File not found: ${file}" >&2
            exit 1
        fi
        while IFS= read -r pin; do
            id="${pin%@*}"
            [[ -n ${seen[${id,,}]:-} ]] && continue
            seen[${id,,}]=1
            ids+=("${id}")
        done < <(extract_pins "${file}")
    done

    if [[ ${#ids[@]} -eq 0 ]]; then
        echo "No pinned extensions found"
        return 0
    fi

    response="$(mktemp)"
    # shellcheck disable=SC2064 # expand now: response is local to main
    trap "rm -f '${response}'" EXIT
    if ! query_marketplace "${response}" "${ids[@]}"; then
        echo "Marketplace query failed: ${MARKETPLACE_URL}" >&2
        exit 1
    fi

    for id in "${ids[@]}"; do
        key="${id,,}"
        latest[${key}]="$(latest_version "${response}" "${id}" || true)"
    done

    for file in "${FILES[@]}"; do
        while IFS= read -r pin; do
            id="${pin%@*}"
            old="${pin##*@}"
            new="${latest[${id,,}]}"
            if [[ -z ${new} ]]; then
                echo "${file}: ${id} ${old} (no stable Marketplace version found; unchanged)" >&2
                failed=1
            elif [[ ${new} == "${old}" ]]; then
                echo "${file}: ${id} ${old} (up to date)"
            elif [[ "$(printf '%s\n%s\n' "${old}" "${new}" | sort -V | tail -1)" == "${old}" ]]; then
                echo "${file}: ${id} ${old} (newer than latest allowed ${new}; unchanged)"
            else
                echo "${file}: ${id} ${old} -> ${new}"
                [[ ${DRY_RUN} == true ]] || rewrite_pin "${file}" "${id}" "${old}" "${new}"
            fi
        done < <(extract_pins "${file}")
    done

    return "${failed}"
}

if [[ ${BASH_SOURCE[0]} == "${0}" ]]; then
    main "$@"
fi
