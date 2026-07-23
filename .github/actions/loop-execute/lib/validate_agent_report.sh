#!/bin/bash
#######################################
# Description: Mechanical validation of loop implementer agent-output.txt
#
# Usage: source lib/validate_agent_report.sh
#        validate_agent_report <output_file> <changed_files_newline> <skill_name>
#
# Output:
# - Prints violation lines to stdout (empty when valid)
#
# Design Rules:
# - Deterministic checks only; runs before the LLM verifier
# - Applies to loop fix skills listed in agent_report_skill_requires_format_check
#######################################

#######################################
# agent_report_skill_requires_format_check: Return whether skill uses fix-skill report format
#
# Globals:
#   None
#
# Arguments:
#   $1 - Skill name
#
# Outputs:
#   None
#
# Returns:
#   0 when format checks apply; 1 otherwise
#
#######################################
function agent_report_skill_requires_format_check {
    case "${1:-}" in
        changelog | ci-sweeper | docs-updater | refactor | tech-debt) return 0 ;;
        *) return 1 ;;
    esac
}

#######################################
# agent_report_primary_subsection: Return primary Summary subsection name for skill
#
# Globals:
#   None
#
# Arguments:
#   $1 - Skill name
#
# Outputs:
#   Subsection title without hashes to stdout
#
# Returns:
#   0 on success
#
#######################################
function agent_report_primary_subsection {
    case "${1:-}" in
        *) printf '%s' "Changes" ;;
    esac
}

#######################################
# agent_report_is_survey_output: Return whether output is survey-shaped
#
# Globals:
#   None
#
# Arguments:
#   $1 - Agent output file path
#   $2 - Changed files (newline-separated, repository-relative)
#
# Outputs:
#   None
#
# Returns:
#   0 when survey-shaped; 1 when apply-shaped
#
#######################################
function agent_report_is_survey_output {
    local output_file="$1"
    local changed_files="$2"

    if [[ -n ${changed_files} ]]; then
        return 1
    fi
    if grep -qE '^### Changes[[:space:]]*$' "${output_file}"; then
        return 1
    fi
    return 0
}

#######################################
# agent_report_deferred_subsection: Return deferred Summary subsection name for skill
#
# Globals:
#   None
#
# Arguments:
#   $1 - Skill name
#
# Outputs:
#   Subsection title without hashes to stdout
#
# Returns:
#   0 on success
#
#######################################
function agent_report_deferred_subsection {
    case "${1:-}" in
        changelog) printf '%s' "Skipped" ;;
        *) printf '%s' "Deferred" ;;
    esac
}

#######################################
# extract_subsection_table_col1: Extract first column values from a ### subsection table
#
# Globals:
#   None
#
# Arguments:
#   $1 - Agent output file path
#   $2 - Subsection title without hashes (e.g. Changes)
#
# Outputs:
#   Cell values one per line
#
# Returns:
#   0 on success
#
#######################################
function extract_subsection_table_col1 {
    local output_file="$1"
    local subsection="$2"

    awk -v sec="${subsection}" '
        $0 ~ "^### " sec "[[:space:]]*$" { in_sec = 1; next }
        in_sec && /^### / { exit }
        in_sec && /^## / { exit }
        in_sec && /^\|/ {
            if ($0 ~ /^\|[[:space:]]*[-:]+/) next
            n = split($0, cells, "|")
            val = cells[2]
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", val)
            gsub(/`/, "", val)
            if (val == "" || val == "—" || val == "-" || val == "_None_") next
            if (val ~ /^(File|Target|Workflow|Commit|Path|What|Why|Root|Check)/) next
            print val
        }
    ' "${output_file}"
}

#######################################
# normalize_report_path: Normalize a path cell for comparison
#
# Globals:
#   None
#
# Arguments:
#   $1 - Raw path cell (may include symbol suffix)
#
# Outputs:
#   Normalized repository-relative path
#
# Returns:
#   0 on success
#
#######################################
function normalize_report_path {
    local raw="$1"
    raw="${raw%% *}"
    raw="${raw#./}"
    printf '%s' "${raw}"
}

#######################################
# validate_agent_report: Validate implementer output format and diff consistency
#
# Globals:
#   None
#
# Arguments:
#   $1 - Agent output file path
#   $2 - Changed files (newline-separated, repository-relative)
#   $3 - Skill name
#
# Outputs:
#   Violation lines to stdout (empty when valid)
#
# Returns:
#   0 when valid; 1 when violations were printed
#
#######################################
function validate_agent_report {
    local output_file="$1"
    local changed_files="$2"
    local skill_name="$3"
    local primary deferred survey=false
    local -a violations=()
    local path norm changed_path
    local -a change_paths=() deferred_paths=()

    if ! agent_report_skill_requires_format_check "${skill_name}"; then
        return 0
    fi
    if [[ ! -f ${output_file} ]]; then
        printf '%s\n' "Missing agent-output.txt for format validation"
        return 1
    fi

    if [[ -n ${changed_files} ]] && ! grep -qE '^### Changes[[:space:]]*$' "${output_file}"; then
        violations+=("Survey output must not accompany a non-empty branch diff")
    fi

    if agent_report_is_survey_output "${output_file}" "${changed_files}"; then
        survey=true
    fi

    for heading in Overview Summary; do
        if ! grep -qE "^## ${heading}[[:space:]]*$" "${output_file}"; then
            violations+=("Missing ## ${heading} in agent output")
        fi
    done

    if [[ ${survey} == true ]]; then
        if grep -qE '^### Changes[[:space:]]*$' "${output_file}"; then
            violations+=("Survey output must not include ### Changes")
        fi
        if grep -qE '^### Deferred[[:space:]]*$' "${output_file}"; then
            violations+=("Survey output must not include ### Deferred; use ### Watch")
        fi
        if grep -qE '^### Skipped[[:space:]]*$' "${output_file}"; then
            violations+=("Survey output must not include ### Skipped")
        fi
        if grep -qE '^## Verification[[:space:]]*$' "${output_file}"; then
            violations+=("Survey output must not include ## Verification")
        fi
        if [[ -n ${changed_files} ]]; then
            violations+=("Survey output must not accompany a non-empty branch diff")
        fi
    else
        if ! grep -qE '^## Verification[[:space:]]*$' "${output_file}"; then
            violations+=("Missing ## Verification in agent output")
        fi
        if grep -qE '^### Candidates[[:space:]]*$' "${output_file}"; then
            violations+=("Apply output must not include ### Candidates")
        fi
        if grep -qE '^### Watch[[:space:]]*$' "${output_file}"; then
            violations+=("Apply output must not include ### Watch; fold into ### Deferred")
        fi
    fi

    if grep -qE '^### Fixes Applied[[:space:]]*$' "${output_file}"; then
        violations+=("Legacy ### Fixes Applied subsection present; use ### Changes")
    fi
    if grep -qE '^\*\*Outcome:\*\*|^Outcome:' "${output_file}"; then
        violations+=("Redundant Outcome line in agent output; use Overview + Summary tables")
    fi
    if grep -qE '^### Suggested next action[[:space:]]*$' "${output_file}"; then
        violations+=("Redundant ### Suggested next action; merge into Overview if needed")
    fi
    if grep -qE '^## Changes[[:space:]]*$' "${output_file}"; then
        violations+=("Top-level ## Changes in agent output; use ### Changes under ## Summary")
    fi
    if grep -qE '\bO[123]\b' "${output_file}"; then
        violations+=("Internal depth tier label (O1/O2/O3) found in user-facing output")
    fi

    if [[ ${survey} == true ]]; then
        if [[ ${#violations[@]} -gt 0 ]]; then
            printf '%s\n' "${violations[@]}"
            return 1
        fi
        return 0
    fi

    primary="$(agent_report_primary_subsection "${skill_name}")"
    deferred="$(agent_report_deferred_subsection "${skill_name}")"

    if [[ -n ${changed_files} ]] && ! grep -qE "^### ${primary}[[:space:]]*$" "${output_file}"; then
        violations+=("Missing ### ${primary} under ## Summary while branch has file changes")
    fi

    mapfile -t change_paths < <(extract_subsection_table_col1 "${output_file}" "${primary}")
    if grep -qE "^### ${deferred}[[:space:]]*$" "${output_file}"; then
        mapfile -t deferred_paths < <(extract_subsection_table_col1 "${output_file}" "${deferred}")
    fi

    for path in "${change_paths[@]}"; do
        [[ -z ${path} ]] && continue
        norm="$(normalize_report_path "${path}")"
        for dep in "${deferred_paths[@]}"; do
            [[ -z ${dep} ]] && continue
            if [[ $(normalize_report_path "${dep}") == "${norm}" ]]; then
                violations+=("Path ${norm} appears in both ### ${primary} and ### ${deferred}")
            fi
        done
    done

    while IFS= read -r changed_path; do
        [[ -z ${changed_path} ]] && continue
        changed_path="${changed_path#./}"
        local found=false
        for path in "${change_paths[@]}"; do
            [[ -z ${path} ]] && continue
            if [[ $(normalize_report_path "${path}") == "${changed_path}" ]]; then
                found=true
                break
            fi
        done
        if [[ ${found} == false ]]; then
            violations+=("Branch diff includes ${changed_path} but ### ${primary} table omits it")
        fi
    done <<< "${changed_files}"

    for dep in "${deferred_paths[@]}"; do
        [[ -z ${dep} ]] && continue
        norm="$(normalize_report_path "${dep}")"
        while IFS= read -r changed_path; do
            [[ -z ${changed_path} ]] && continue
            changed_path="${changed_path#./}"
            if [[ ${changed_path} == "${norm}" ]]; then
                violations+=("### ${deferred} lists ${norm} but branch diff still modifies it (revert or move to ### ${primary})")
            fi
        done <<< "${changed_files}"
    done

    if [[ ${#violations[@]} -gt 0 ]]; then
        printf '%s\n' "${violations[@]}"
        return 1
    fi
    return 0
}
