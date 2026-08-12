#!/bin/bash
#######################################
# Description:
#   Validate loop automation skills under .apm/packages for PR body contract drift.
#
# Usage:
#   bash check_loop_pr_body_contract.sh
#
# Design Rules:
#   - Source of truth: .apm/packages/common/.apm/skills/<skill>/
#   - Contract spec: docs/explanation/loop-engineering/loop-pr-body-skill-contract.md
#   - Exit 0 when valid; exit 1 when violations are reported
#
# Output:
#   Violation lines to stdout
#######################################

set -euo pipefail

umask 027
export LC_ALL=C.UTF-8

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

SKILLS_ROOT="${SKILLS_ROOT:-${WORKSPACE_ROOT}/.apm/packages/common/.apm/skills}"

declare -a LOOP_SKILLS=(
    changelog
    ci-sweeper
    docs-updater
    issue-autofix
    pr-revise
    refactor
    tech-debt
)

declare -a REQUIRED_FILES=(
    assets/pr-body-template.md
    assets/pr-body-template-survey.md
    references/category-automation-envelope.md
    references/common-output-format.md
)

# Skills that ship category-pr-body-links.md (per-skill link rules).
declare -a LOOP_PR_BODY_LINKS_SKILLS=(
    changelog
    ci-sweeper
    docs-updater
    issue-autofix
    pr-revise
    refactor
    tech-debt
)

# Skills that ship a separate automation-path output contract file.
declare -a LOOP_SPLIT_OUTPUT_SKILLS=(
    docs-updater
    refactor
)

declare -a FORBIDDEN_PATTERNS=(
    '~280'
    'one or two sentences'
    '1–2 sentences (max'
    '1-2 sentences (max'
    '](https://github.com/org/repo'
)

declare -a LOOP_LINK_CHECK_PATHS=(
    assets/pr-body-template.md
    assets/pr-body-template-survey.md
    references/common-output-format.md
    references/common-output-format-automation.md
)

declare -a VIOLATIONS=()

#######################################
# loop_skill_uses_pr_body_links: Return whether a loop skill ships link rules
#
# Globals:
#   LOOP_PR_BODY_LINKS_SKILLS
#
# Arguments:
#   $1 - Skill name
#
# Outputs:
#   None
#
# Returns:
#   0 when the skill ships category-pr-body-links.md; 1 otherwise
#
#######################################
function loop_skill_uses_pr_body_links {
    local skill="${1:-}"
    local links_skill

    for links_skill in "${LOOP_PR_BODY_LINKS_SKILLS[@]}"; do
        if [[ ${skill} == "${links_skill}" ]]; then
            return 0
        fi
    done
    return 1
}

#######################################
# loop_skill_deferred_subsection: Return deferred subsection name for a loop skill
#
# Globals:
#   None
#
# Arguments:
#   $1 - Skill name
#
# Outputs:
#   Subsection title without hashes
#
# Returns:
#   0 on success
#
#######################################
function loop_skill_deferred_subsection {
    case "${1:-}" in
        changelog) printf '%s' "Skipped" ;;
        *) printf '%s' "Deferred" ;;
    esac
}

#######################################
# check_template_link_placeholders: Forbid example org/repo markdown links in templates
#
# Globals:
#   SKILLS_ROOT
#   LOOP_LINK_CHECK_PATHS
#
# Arguments:
#   $1 - Skill name
#
# Outputs:
#   None
#
# Returns:
#   0 on success
#
#######################################
function check_template_link_placeholders {
    local skill="$1"
    local rel_path full_path

    for rel_path in "${LOOP_LINK_CHECK_PATHS[@]}"; do
        full_path="${SKILLS_ROOT}/${skill}/${rel_path}"
        [[ -f ${full_path} ]] || continue
        if grep -qF '](https://github.com/org/repo' "${full_path}"; then
            record_violation "Example org/repo markdown link in ${skill}/${rel_path} — use backtick placeholders (see category-pr-body-links.md)"
        fi
    done
}

#######################################
# record_violation: Append a violation message
#
# Globals:
#   VIOLATIONS
#
# Arguments:
#   $1 - Violation text
#
# Outputs:
#   None
#
# Returns:
#   0 on success
#
#######################################
function record_violation {
    VIOLATIONS+=("$1")
}

#######################################
# check_required_file: Ensure a required skill file exists
#
# Globals:
#   None
#
# Arguments:
#   $1 - Skill name
#   $2 - Relative path under skill root
#
# Outputs:
#   None
#
# Returns:
#   0 on success
#
#######################################
function check_required_file {
    local skill="$1"
    local rel_path="$2"
    local full_path="${SKILLS_ROOT}/${skill}/${rel_path}"

    if [[ ! -f ${full_path} ]]; then
        record_violation "Missing ${rel_path} for skill ${skill}"
    fi
}

#######################################
# check_forbidden_patterns: Fail on deprecated Overview / template wording
#
# Globals:
#   None
#
# Arguments:
#   $1 - Skill name
#   $2 - Relative path under skill root
#
# Outputs:
#   None
#
# Returns:
#   0 on success
#
#######################################
function check_forbidden_patterns {
    local skill="$1"
    local rel_path="$2"
    local full_path="${SKILLS_ROOT}/${skill}/${rel_path}"
    local pattern

    [[ -f ${full_path} ]] || return 0

    for pattern in "${FORBIDDEN_PATTERNS[@]}"; do
        if grep -qF "${pattern}" "${full_path}"; then
            record_violation "Deprecated pattern '${pattern}' in ${skill}/${rel_path}"
        fi
    done
}

#######################################
# check_apply_template: Validate apply PR body template headings
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
#   0 on success
#
#######################################
function check_apply_template {
    local skill="$1"
    local template="${SKILLS_ROOT}/${skill}/assets/pr-body-template.md"
    local deferred
    deferred="$(loop_skill_deferred_subsection "${skill}")"

    [[ -f ${template} ]] || return 0

    for heading in Overview Summary Verification; do
        if ! grep -qE "^## ${heading}[[:space:]]*$" "${template}"; then
            record_violation "Apply template for ${skill} missing ## ${heading}"
        fi
    done

    if ! grep -qE '^### Changes[[:space:]]*$' "${template}"; then
        record_violation "Apply template for ${skill} missing ### Changes"
    fi

    if ! grep -qE "^### ${deferred}[[:space:]]*$" "${template}"; then
        record_violation "Apply template for ${skill} missing ### ${deferred}"
    fi

    if grep -qE '^### Candidates[[:space:]]*$' "${template}"; then
        record_violation "Apply template for ${skill} must not include ### Candidates"
    fi
}

#######################################
# check_survey_template: Validate survey PR body template headings
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
#   0 on success
#
#######################################
function check_survey_template {
    local skill="$1"
    local template="${SKILLS_ROOT}/${skill}/assets/pr-body-template-survey.md"

    [[ -f ${template} ]] || return 0

    for heading in Overview Summary; do
        if ! grep -qE "^## ${heading}[[:space:]]*$" "${template}"; then
            record_violation "Survey template for ${skill} missing ## ${heading}"
        fi
    done

    if ! grep -qE '^### Candidates[[:space:]]*$' "${template}"; then
        record_violation "Survey template for ${skill} missing ### Candidates"
    fi

    if grep -qE '^## Verification[[:space:]]*$' "${template}"; then
        record_violation "Survey template for ${skill} must not include ## Verification"
    fi

    if grep -qE '^### Changes[[:space:]]*$' "${template}"; then
        record_violation "Survey template for ${skill} must not include ### Changes"
    fi
}

#######################################
# check_automation_envelope: Validate category-automation-envelope.md PR rules
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
#   0 on success
#
#######################################
function check_automation_envelope {
    local skill="$1"
    local envelope="${SKILLS_ROOT}/${skill}/references/category-automation-envelope.md"
    local deferred
    deferred="$(loop_skill_deferred_subsection "${skill}")"

    [[ -f ${envelope} ]] || return 0

    if ! grep -qF '**Overview contract:**' "${envelope}"; then
        record_violation "Envelope for ${skill} missing Overview contract line"
    fi

    if ! grep -qF 'pr-body-template-survey.md' "${envelope}"; then
        record_violation "Envelope for ${skill} missing pr-body-template-survey.md reference"
    fi

    if ! grep -qF 'pr-body-template.md' "${envelope}"; then
        record_violation "Envelope for ${skill} missing pr-body-template.md reference"
    fi

    if loop_skill_uses_pr_body_links "${skill}"; then
        if ! grep -qF 'category-pr-body-links.md' "${envelope}"; then
            record_violation "Envelope for ${skill} missing category-pr-body-links.md reference"
        fi

        if ! grep -qF -- '- **Links:** At synthesis, read [category-pr-body-links.md](category-pr-body-links.md).' "${envelope}"; then
            record_violation "Envelope for ${skill} must use canonical Links line pointing to category-pr-body-links.md"
        fi
    fi

    if [[ ${skill} == changelog ]]; then
        if ! grep -qF '### Skipped' "${envelope}"; then
            record_violation "Envelope for changelog missing ### Skipped guidance"
        fi
    elif ! grep -qF "### ${deferred}" "${envelope}"; then
        record_violation "Envelope for ${skill} missing ### ${deferred} guidance"
    fi
}

#######################################
# check_loop_skill: Run all contract checks for one loop skill
#
# Globals:
#   REQUIRED_FILES
#   LOOP_SPLIT_OUTPUT_SKILLS
#
# Arguments:
#   $1 - Skill name
#
# Outputs:
#   None
#
# Returns:
#   0 on success
#
#######################################
function check_loop_skill {
    local skill="$1"
    local rel_path

    if [[ ! -d ${SKILLS_ROOT}/${skill} ]]; then
        record_violation "Missing skill directory ${skill} under ${SKILLS_ROOT}"
        return 0
    fi

    for rel_path in "${REQUIRED_FILES[@]}"; do
        check_required_file "${skill}" "${rel_path}"
        check_forbidden_patterns "${skill}" "${rel_path}"
    done

    if loop_skill_uses_pr_body_links "${skill}"; then
        check_required_file "${skill}" "references/category-pr-body-links.md"
        check_forbidden_patterns "${skill}" "references/category-pr-body-links.md"
    fi

    local split_skill
    for split_skill in "${LOOP_SPLIT_OUTPUT_SKILLS[@]}"; do
        if [[ ${skill} == "${split_skill}" ]]; then
            check_required_file "${skill}" "references/common-output-format-automation.md"
            check_forbidden_patterns "${skill}" "references/common-output-format-automation.md"
        fi
    done

    check_apply_template "${skill}"
    check_survey_template "${skill}"
    check_automation_envelope "${skill}"
    check_template_link_placeholders "${skill}"
}

#######################################
# main: Validate all loop automation skills
#
# Globals:
#   LOOP_SKILLS
#   VIOLATIONS
#
# Arguments:
#   None
#
# Outputs:
#   Violation lines to stdout
#
# Returns:
#   0 when valid; 1 when violations exist
#
#######################################
function main {
    local skill

    if [[ ! -d ${SKILLS_ROOT} ]]; then
        echo "ERROR: Skills root not found: ${SKILLS_ROOT}" >&2
        return 1
    fi

    for skill in "${LOOP_SKILLS[@]}"; do
        check_loop_skill "${skill}"
    done

    if [[ ${#VIOLATIONS[@]} -gt 0 ]]; then
        printf '%s\n' "${VIOLATIONS[@]}"
        return 1
    fi

    printf 'loop PR body contract: OK (%d skills)\n' "${#LOOP_SKILLS[@]}"
    return 0
}

if [[ ${BASH_SOURCE[0]} == "${0}" ]]; then
    main "$@"
fi
