#!/bin/bash
#######################################
# Description: Detect technical debt signals and hotspots for loop-tech-debt
#
# Usage: ./detect_tech_debt.sh [--scope staged|all|range] [--since <ref>]
#   --scope    Detection scope (default: all)
#              staged: not used for debt sensors (accepted for loop-detect parity)
#              all: scan the full repository tree (default)
#              range: accepted for loop-detect parity (requires --since)
#   --since    Git ref for range scope (commit SHA from loop state)
#
# Output:
# - JSON object with signals[], hotspots[], warnings[], and skip boolean
#
# Design Rules:
# - Emit facts only; Skill builds semantic findings[]
# - Output structured JSON via shared lib/json.sh
# - Exit 0 always (errors reported in JSON status field)
# - Default scan is full repository (scope=all); do not narrow sensors to lint territory
# - Per-sensor recoverable failures append to warnings[] and continue
# - Docs links use self-contained markdown-link-check (mlc) when Node is available
# - Source shared helpers from scripts/lib/all.sh (synced via scripts/ai/sync_skill_lib.sh)
#
# Dependencies:
# - bash (POSIX bash, /bin/bash)
# - git
#
# Optional dependencies:
# - jq (package.json dependency sensor)
#
# Optional environment:
#   TECH_DEBT_EOL_MODULES - Comma-separated module paths/names for eol_hint signals
#######################################

# Error handling: exit on error, unset variable, or failed pipeline
set -euo pipefail

# Secure defaults
umask 027
export LC_ALL=C.UTF-8

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/all.sh
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/all.sh"

#######################################
# Global variables
#######################################
SCOPE="all"
SINCE_REF=""

MARKER_PER_FILE_CAP=10
MARKER_GLOBAL_CAP=50
DEP_PER_FILE_CAP=20
DEP_GLOBAL_CAP=50

declare -a SIGNALS_JSON=()
declare -a HOTSPOTS_JSON=()
declare -a WARNINGS=()
declare -A MARKER_FILE_COUNTS=()
MARKER_GLOBAL_COUNT=0
MARKER_TRUNCATED=false
declare -A DEP_FILE_COUNTS=()
DEP_GLOBAL_COUNT=0
DEP_TRUNCATED=false

#######################################
# show_usage: Display script usage information
#
# Arguments:
#   None
#
# Global Variables:
#   None
#
# Returns:
#   Exits with code 0
#
# Usage:
#   show_usage
#
#######################################
function show_usage {
    cat << 'EOF'
Usage: detect_tech_debt.sh [--scope staged|all|range] [--since <ref>]

Description:
    Detect technical debt signals and hotspots for the loop-tech-debt skill.

Options:
    --scope    Detection scope (default: all)
               staged: accepted for loop-detect parity (not used by sensors)
               all: scan the full repository tree (default)
               range: accepted for loop-detect parity (requires --since)
    --since    Git ref for range scope (commit SHA from loop state)

Examples:
    ./detect_tech_debt.sh
    ./detect_tech_debt.sh --scope all
    ./detect_tech_debt.sh --scope range --since abc1234
EOF
    exit 0
}

#######################################
# parse_arguments: Parse command line arguments
#
# Arguments:
#   $@ - Command line arguments
#
# Global Variables:
#   SCOPE - Detection scope
#   SINCE_REF - Git ref for range scope
#
# Returns:
#   None (calls output_error on invalid input)
#
# Usage:
#   parse_arguments "$@"
#
#######################################
function parse_arguments {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h | --help)
                show_usage
                ;;
            --scope)
                if [[ $# -lt 2 ]]; then
                    output_error "--scope requires a value"
                fi
                SCOPE="$2"
                shift 2
                ;;
            --since)
                if [[ $# -lt 2 ]]; then
                    output_error "--since requires a value"
                fi
                SINCE_REF="$2"
                shift 2
                ;;
            *)
                output_error "Unknown argument: $1"
                ;;
        esac
    done

    if [[ ${SCOPE} != "staged" && ${SCOPE} != "all" && ${SCOPE} != "range" ]]; then
        output_error "--scope must be staged, all, or range"
    fi

    if [[ ${SCOPE} == "range" && -z ${SINCE_REF} ]]; then
        output_error "--scope range requires --since <ref>"
    fi
}

#######################################
# append_dependency_signal: Append one dependency signal when dep caps allow
#
# Arguments:
#   $1-$6 - kind, path, line, snippet, source, hint (hint optional)
#
# Global Variables:
#   SIGNALS_JSON - Output array of signal objects
#   DEP_FILE_COUNTS - Per-file dependency signal counts
#   DEP_GLOBAL_COUNT - Total dependency signals collected
#   DEP_TRUNCATED - Set true when a dep cap is reached
#   DEP_PER_FILE_CAP - Maximum dependency signals per manifest file
#   DEP_GLOBAL_CAP - Maximum dependency signals across the repository
#
# Returns:
#   0 when appended; 1 when skipped due to caps
#
# Usage:
#   append_dependency_signal "eol_hint" "go.mod" "5" "require x v1" "go_mod" "dependency_version"
#
#######################################
function append_dependency_signal {
    local kind="$1"
    local path="$2"
    local line="$3"
    local snippet="$4"
    local source="$5"
    local hint="${6:-}"
    local file_count

    if [[ ${DEP_GLOBAL_COUNT} -ge ${DEP_GLOBAL_CAP} ]]; then
        DEP_TRUNCATED=true
        return 1
    fi

    file_count="${DEP_FILE_COUNTS[${path}]:-0}"
    if [[ ${file_count} -ge ${DEP_PER_FILE_CAP} ]]; then
        DEP_TRUNCATED=true
        return 1
    fi

    DEP_FILE_COUNTS[${path}]=$((file_count + 1))
    DEP_GLOBAL_COUNT=$((DEP_GLOBAL_COUNT + 1))
    SIGNALS_JSON+=("$(signal_object_json "${kind}" "${path}" "${line}" "${snippet}" "${source}" "${hint}")")
}

#######################################
# append_signal: Append one marker signal object when marker caps allow
#
# Arguments:
#   $1-$6 - kind, path, line, snippet, source, hint (hint optional)
#
# Global Variables:
#   SIGNALS_JSON - Output array of signal objects
#   MARKER_FILE_COUNTS - Per-file marker counts
#   MARKER_GLOBAL_COUNT - Total marker signals collected
#   MARKER_TRUNCATED - Set true when a cap is reached
#   MARKER_PER_FILE_CAP - Maximum markers per file
#   MARKER_GLOBAL_CAP - Maximum markers across the repository
#
# Returns:
#   0 when appended; 1 when skipped due to caps
#
# Usage:
#   append_signal "todo_comment" "src/main.go" "2" "// TODO: x" "git_grep" "code_quality"
#
#######################################
function append_signal {
    local kind="$1"
    local path="$2"
    local line="$3"
    local snippet="$4"
    local source="$5"
    local hint="${6:-}"
    local file_count

    if [[ ${MARKER_GLOBAL_COUNT} -ge ${MARKER_GLOBAL_CAP} ]]; then
        MARKER_TRUNCATED=true
        return 1
    fi

    file_count="${MARKER_FILE_COUNTS[${path}]:-0}"
    if [[ ${file_count} -ge ${MARKER_PER_FILE_CAP} ]]; then
        MARKER_TRUNCATED=true
        return 1
    fi

    MARKER_FILE_COUNTS[${path}]=$((file_count + 1))
    MARKER_GLOBAL_COUNT=$((MARKER_GLOBAL_COUNT + 1))
    SIGNALS_JSON+=("$(signal_object_json "${kind}" "${path}" "${line}" "${snippet}" "${source}" "${hint}")")
}

#######################################
# collect_dependency_signals: Scan manifests for dependency version facts
#
# Arguments:
#   None
#
# Global Variables:
#   SIGNALS_JSON - Output array of signal objects
#   WARNINGS - Warning messages
#   DEP_FILE_COUNTS - Per-file dependency signal counts (reset per run)
#   DEP_GLOBAL_COUNT - Total dependency signals collected (reset per run)
#   DEP_TRUNCATED - Truncation flag (reset per run)
#
# Returns:
#   None
#
# Usage:
#   collect_dependency_signals
#
#######################################
function collect_dependency_signals {
    local file

    DEP_FILE_COUNTS=()
    DEP_GLOBAL_COUNT=0
    DEP_TRUNCATED=false

    if ! git rev-parse --is-inside-work-tree > /dev/null 2>&1; then
        return 0
    fi

    while IFS= read -r file; do
        [[ -z ${file} ]] && continue
        if path_is_pruned "${file}"; then
            continue
        fi
        case "${file}" in
            go.mod | */go.mod)
                dependency_signals_from_go_mod "${file}"
                ;;
            package.json | */package.json)
                dependency_signals_from_package_json "${file}"
                ;;
        esac
    done < <(git ls-files 2> /dev/null | grep -E '(^|/)go\.mod$|(^|/)package\.json$' || true)

    if [[ ${DEP_TRUNCATED} == "true" ]]; then
        WARNINGS+=("dependency signals truncated")
    fi
}

#######################################
# collect_marker_signals: Scan tracked files for TODO/FIXME/HACK/XXX markers
#
# Arguments:
#   None
#
# Global Variables:
#   SIGNALS_JSON - Output array of signal objects
#   WARNINGS - Warning messages
#   MARKER_FILE_COUNTS - Per-file marker counts (reset per run)
#   MARKER_GLOBAL_COUNT - Total marker signals collected (reset per run)
#   MARKER_TRUNCATED - Truncation flag (reset per run)
#
# Returns:
#   None
#
# Usage:
#   collect_marker_signals
#
#######################################
function collect_marker_signals {
    local marker_pattern='//[[:space:]]*(TODO|FIXME|HACK|XXX)\b|#[[:space:]]*(TODO|FIXME|HACK|XXX)\b|/\*[[:space:]]*(TODO|HACK|FIXME|XXX)\b|\b(TODO|FIXME|HACK|XXX):'
    local grep_line file rest line content kind

    MARKER_FILE_COUNTS=()
    MARKER_GLOBAL_COUNT=0
    MARKER_TRUNCATED=false

    if ! git rev-parse --is-inside-work-tree > /dev/null 2>&1; then
        return 0
    fi

    while IFS= read -r grep_line; do
        [[ -z ${grep_line} ]] && continue
        if [[ ${MARKER_GLOBAL_COUNT} -ge ${MARKER_GLOBAL_CAP} ]]; then
            MARKER_TRUNCATED=true
            break
        fi

        file="${grep_line%%:*}"
        rest="${grep_line#*:}"
        line="${rest%%:*}"
        content="${rest#*:}"

        if path_is_pruned "${file}"; then
            continue
        fi

        kind="$(marker_kind_from_line "${content}")"
        [[ -z ${kind} ]] && continue

        append_signal "${kind}" "${file}" "${line}" "${content}" "git_grep" "code_quality" || true
    done < <(git grep -nI -E "${marker_pattern}" 2> /dev/null || true)

    if [[ ${MARKER_TRUNCATED} == "true" ]]; then
        WARNINGS+=("marker signals truncated")
    fi
}

#######################################
# dependency_eol_module_listed: Return whether a module is in TECH_DEBT_EOL_MODULES
#
# Arguments:
#   $1 - Module path or package name
#
# Global Variables:
#   None
#
# Returns:
#   0 when listed; 1 otherwise
#
# Usage:
#   dependency_eol_module_listed "github.com/old/lib"
#
#######################################
function dependency_eol_module_listed {
    local module="$1"
    local entry trimmed

    [[ -n ${TECH_DEBT_EOL_MODULES:-} ]] || return 1

    IFS=',' read -ra eol_entries <<< "${TECH_DEBT_EOL_MODULES}"
    for entry in "${eol_entries[@]}"; do
        trimmed="${entry#"${entry%%[![:space:]]*}"}"
        trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"
        [[ -z ${trimmed} ]] && continue
        if [[ ${module} == "${trimmed}" ]]; then
            return 0
        fi
    done
    return 1
}

#######################################
# dependency_is_version_range: Return whether a version string is a loose range
#
# Arguments:
#   $1 - Version string from a manifest
#
# Global Variables:
#   None
#
# Returns:
#   0 when the version uses a range prefix; 1 otherwise
#
# Usage:
#   dependency_is_version_range "^1.0.0"
#
#######################################
function dependency_is_version_range {
    local version="$1"

    case "${version}" in
        ^* | ~* | \** | x* | X*)
            return 0
            ;;
    esac
    return 1
}

#######################################
# dependency_signals_from_go_mod: Emit eol_hint signals from a go.mod file
#
# Arguments:
#   $1 - Repository-relative path to go.mod
#
# Global Variables:
#   SIGNALS_JSON - Output array of signal objects
#
# Returns:
#   None
#
# Usage:
#   dependency_signals_from_go_mod "go.mod"
#
#######################################
function dependency_signals_from_go_mod {
    local path="$1"
    local line line_content module version snippet line_num in_require=false
    local -a go_mod_lines=()

    [[ -f ${path} ]] || return 0
    [[ -n ${TECH_DEBT_EOL_MODULES:-} ]] || return 0

    mapfile -t go_mod_lines < "${path}"
    for line_num in "${!go_mod_lines[@]}"; do
        line_content="${go_mod_lines[${line_num}]}"
        line="${line_content%%#*}"
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"
        [[ -z ${line} ]] && continue

        if [[ ${line} == "require (" ]]; then
            in_require=true
            continue
        fi
        if [[ ${in_require} == "true" && ${line} == ")" ]]; then
            in_require=false
            continue
        fi

        module=""
        version=""
        if [[ ${line} =~ ^require[[:space:]]+([^[:space:]]+)[[:space:]]+([^[:space:]]+) ]]; then
            module="${BASH_REMATCH[1]}"
            version="${BASH_REMATCH[2]}"
        elif [[ ${in_require} == "true" && ${line} =~ ^([^[:space:]]+)[[:space:]]+([^[:space:]]+) ]]; then
            module="${BASH_REMATCH[1]}"
            version="${BASH_REMATCH[2]}"
        else
            continue
        fi

        if ! dependency_eol_module_listed "${module}"; then
            continue
        fi

        snippet="require ${module} ${version}"
        append_dependency_signal "eol_hint" "${path}" "$((line_num + 1))" "${snippet}" "go_mod" "dependency_version" || true
    done
}

#######################################
# dependency_signals_from_package_json: Emit npm dependency version signals
#
# Arguments:
#   $1 - Repository-relative path to package.json
#
# Global Variables:
#   SIGNALS_JSON - Output array of signal objects
#   WARNINGS - Warning messages
#
# Returns:
#   None
#
# Usage:
#   dependency_signals_from_package_json "package.json"
#
#######################################
function dependency_signals_from_package_json {
    local path="$1"
    local dir lock_path name version snippet resolved line_num
    local line_content current_line

    [[ -f ${path} ]] || return 0

    if ! command -v jq > /dev/null 2>&1; then
        WARNINGS+=("dependency sensor skipped for package.json: jq not available")
        return 0
    fi

    dir="$(dirname "${path}")"
    if [[ ${dir} == "." ]]; then
        lock_path="package-lock.json"
    else
        lock_path="${dir}/package-lock.json"
    fi

    declare -A dep_lines=()
    current_line=0
    while IFS= read -r line_content || [[ -n ${line_content} ]]; do
        current_line=$((current_line + 1))
        if [[ ${line_content} =~ \"([^\"]+)\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
            dep_lines["${BASH_REMATCH[1]}"]="${current_line}"
        fi
    done < "${path}"

    while IFS=$'\t' read -r name version; do
        [[ -z ${name} ]] && continue

        line_num="${dep_lines[${name}]:-1}"
        snippet="\"${name}\": \"${version}\""

        if dependency_is_version_range "${version}"; then
            append_dependency_signal "version_range" "${path}" "${line_num}" "${snippet}" "package_json" "dependency_version" || true
            continue
        fi

        if [[ ! -f ${lock_path} ]]; then
            continue
        fi

        resolved="$(jq -r --arg pkg "${name}" '
            .packages["node_modules/" + $pkg].version //
            .dependencies[$pkg].version //
            empty
        ' "${lock_path}" 2> /dev/null || true)"
        if [[ -n ${resolved} && ${version} != "${resolved}" ]]; then
            snippet="\"${name}\": \"${version}\" (lock: ${resolved})"
            append_dependency_signal "pin_drift" "${path}" "${line_num}" "${snippet}" "package_json" "dependency_version" || true
        fi
    done < <(jq -r '
        (.dependencies // {}), (.devDependencies // {}) | to_entries[] | [.key, .value] | @tsv
    ' "${path}" 2> /dev/null || true)
}

#######################################
# hotspot_object_json: Build one hotspot object as JSON
#
# Arguments:
#   $1-$4 - path, metric, value, window
#
# Global Variables:
#   None
#
# Returns:
#   JSON object on stdout
#
# Usage:
#   hotspot_object_json "pkg/foo.go" "churn" "12" "90d"
#
#######################################
function hotspot_object_json {
    local path="$1"
    local metric="$2"
    local value="$3"
    local window="$4"

    cat << EOF
{
  "path": "$(json_escape "${path}")",
  "metric": "$(json_escape "${metric}")",
  "value": ${value},
  "window": "$(json_escape "${window}")"
}
EOF
}

#######################################
# hotspots_array_json: Join hotspot objects into a JSON array string
#
# Arguments:
#   None
#
# Global Variables:
#   HOTSPOTS_JSON - Source hotspot objects
#
# Returns:
#   JSON array string on stdout
#
# Usage:
#   hotspots_array="$(hotspots_array_json)"
#
#######################################
function hotspots_array_json {
    local joined=""
    local hotspot

    if [[ ${#HOTSPOTS_JSON[@]} -eq 0 ]]; then
        printf '%s' "[]"
        return
    fi

    for hotspot in "${HOTSPOTS_JSON[@]}"; do
        if [[ -n ${joined} ]]; then
            joined+=","
        fi
        joined+="${hotspot}"
    done
    printf '[%s]' "${joined}"
}

#######################################
# marker_kind_from_line: Map a matched line to a closed marker kind
#
# Arguments:
#   $1 - Line content from git grep
#
# Global Variables:
#   None
#
# Returns:
#   Marker kind on stdout, or empty when no marker is recognized
#
# Usage:
#   kind="$(marker_kind_from_line "${content}")"
#
#######################################
function marker_kind_from_line {
    local line="$1"

    if [[ ${line} =~ (^|[^A-Za-z])TODO([^A-Za-z]|$|:) ]]; then
        printf 'todo_comment'
    elif [[ ${line} =~ (^|[^A-Za-z])FIXME([^A-Za-z]|$|:) ]]; then
        printf 'fixme'
    elif [[ ${line} =~ (^|[^A-Za-z])HACK([^A-Za-z]|$|:) ]]; then
        printf 'hack'
    elif [[ ${line} =~ (^|[^A-Za-z])XXX([^A-Za-z]|$|:) ]]; then
        printf 'xxx'
    fi
}

#######################################
# output_error: Print structured JSON error and exit
#
# Arguments:
#   $1 - Error message
#
# Global Variables:
#   SCOPE - Detection scope
#   SINCE_REF - Git ref for range scope
#   WARNINGS - Warning messages
#
# Returns:
#   Exits with code 0
#
# Usage:
#   output_error "Not a git repository"
#
#######################################
function output_error {
    local message="$1"
    json_object_start
    json_field_string "status" "error" ","
    json_field_string "scope" "${SCOPE}" ","
    json_field_string "since" "${SINCE_REF}" ","
    json_field_bool "skip" "true" ","
    json_field_array "signals" "[]" ","
    json_field_array "hotspots" "[]" ","
    json_field_array "warnings" "$(json_string_array "${WARNINGS[@]}")" ","
    json_field_string "message" "${message}" ""
    json_object_end
    exit 0
}

#######################################
# output_json: Print structured JSON result using lib/json.sh helpers
#
# Arguments:
#   None
#
# Global Variables:
#   SCOPE - Detection scope
#   SINCE_REF - Git ref for range scope
#   SIGNALS_JSON - Detected signal objects
#   HOTSPOTS_JSON - Detected hotspot objects
#   WARNINGS - Warning messages
#
# Returns:
#   None
#
# Usage:
#   output_json
#
#######################################
function output_json {
    local skip="false"
    local signals_array hotspots_array warnings_array

    if [[ ${#SIGNALS_JSON[@]} -eq 0 && ${#HOTSPOTS_JSON[@]} -eq 0 ]]; then
        skip="true"
    fi

    signals_array="$(signals_array_json)"
    hotspots_array="$(hotspots_array_json)"
    warnings_array="$(json_string_array "${WARNINGS[@]}")"

    json_object_start
    json_field_string "status" "ok" ","
    json_field_string "scope" "${SCOPE}" ","
    json_field_string "since" "${SINCE_REF}" ","
    json_field_bool "skip" "${skip}" ","
    json_field_array "signals" "${signals_array}" ","
    json_field_array "hotspots" "${hotspots_array}" ","
    json_field_array "warnings" "${warnings_array}" ""
    json_object_end
}

#######################################
# path_is_pruned: Return whether a repository path should be excluded
#
# Arguments:
#   $1 - Repository-relative file path
#
# Global Variables:
#   None
#
# Returns:
#   0 when pruned; 1 when the path should be scanned
#
# Usage:
#   path_is_pruned "node_modules/pkg/index.js"
#
#######################################
function path_is_pruned {
    local path="$1"
    local part

    path="${path#./}"

    case "${path}" in
        .git | .git/*) return 0 ;;
        .agents | .agents/*) return 0 ;;
        .cursor | .cursor/*) return 0 ;;
        .claude | .claude/*) return 0 ;;
        .kiro | .kiro/*) return 0 ;;
        .vscode | .vscode/*) return 0 ;;
        apm_modules | apm_modules/*) return 0 ;;
        node_modules | node_modules/*) return 0 ;;
        dist | dist/*) return 0 ;;
        build | build/*) return 0 ;;
        bin | bin/*) return 0 ;;
        docs/report | docs/report/*) return 0 ;;
    esac

    IFS='/' read -ra parts <<< "${path}"
    for part in "${parts[@]}"; do
        if [[ ${part} == .* ]]; then
            return 0
        fi
    done

    return 1
}

#######################################
# signal_object_json: Build one signal object as JSON
#
# Arguments:
#   $1-$6 - kind, path, line, snippet, source, hint (hint optional)
#
# Global Variables:
#   None
#
# Returns:
#   JSON object on stdout
#
# Usage:
#   signal_object_json "todo_comment" "pkg/foo.go" "10" "// TODO" "markers" ""
#
#######################################
function signal_object_json {
    local kind="$1"
    local path="$2"
    local line="$3"
    local snippet="$4"
    local source="$5"
    local hint="${6:-}"

    if [[ -n ${hint} ]]; then
        cat << EOF
{
  "kind": "$(json_escape "${kind}")",
  "path": "$(json_escape "${path}")",
  "line": ${line},
  "snippet": "$(json_escape "${snippet}")",
  "source": "$(json_escape "${source}")",
  "hint": "$(json_escape "${hint}")"
}
EOF
    else
        cat << EOF
{
  "kind": "$(json_escape "${kind}")",
  "path": "$(json_escape "${path}")",
  "line": ${line},
  "snippet": "$(json_escape "${snippet}")",
  "source": "$(json_escape "${source}")"
}
EOF
    fi
}

#######################################
# signals_array_json: Join signal objects into a JSON array string
#
# Arguments:
#   None
#
# Global Variables:
#   SIGNALS_JSON - Source signal objects
#
# Returns:
#   JSON array string on stdout
#
# Usage:
#   signals_array="$(signals_array_json)"
#
#######################################
function signals_array_json {
    local joined=""
    local signal

    if [[ ${#SIGNALS_JSON[@]} -eq 0 ]]; then
        printf '%s' "[]"
        return
    fi

    for signal in "${SIGNALS_JSON[@]}"; do
        if [[ -n ${joined} ]]; then
            joined+=","
        fi
        joined+="${signal}"
    done
    printf '[%s]' "${joined}"
}

#######################################
# main: Entry point
#
# Arguments:
#   $@ - Command line arguments
#
# Global Variables:
#   None
#
# Returns:
#   0 always
#
# Usage:
#   main "$@"
#
#######################################
function main {
    parse_arguments "$@"
    collect_marker_signals
    collect_dependency_signals
    output_json
}

if [[ ${BASH_SOURCE[0]} == "${0}" ]]; then
    main "$@"
fi
