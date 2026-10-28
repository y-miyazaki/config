#!/bin/bash
#######################################
# Description: Resolve caller-supplied checker skill path for Input / slash load
#
# Usage: source "${LIB_DIR}/verifier_skill.sh"
#
# Design Rules:
#   - Skill name comes from AGENT_CHECKER_SKILL_NAME (caller). Execute does not default it.
#   - Execute does not inline SKILL.md; it passes /skill <path> and the skill path as Input
#   - Search .claude/skills, .agents/skills, .apm/packages, and apm_modules
#   - VERIFIER_SKILL_ROOT overrides discovery for tests
#######################################

#######################################
# verifier_skill_workspace_roots: Collect deduplicated workspace search roots
#
# Globals:
#   GITHUB_WORKSPACE - GitHub Actions checkout root (read)
#   WORKTREE_PATH - Loop worktree path (read)
#   WORKSPACE_ROOT - Explicit repo root override (read)
#
# Arguments:
#   None
#
# Outputs:
#   Roots one per line to stdout
#
# Returns:
#   0
#
#######################################
function verifier_skill_workspace_roots {
    local -a roots=()
    local root seen

    for root in "${GITHUB_WORKSPACE:-}" "${WORKSPACE_ROOT:-}" "${WORKTREE_PATH:-}"; do
        [[ -z ${root} ]] && continue
        if ! root="$(cd "${root}" 2> /dev/null && pwd)"; then
            continue
        fi
        if [[ -z ${seen:-} || ${seen} != *"|${root}|"* ]]; then
            roots+=("${root}")
            seen="${seen:-}|${root}|"
        fi
    done

    if [[ ${#roots[@]} -eq 0 ]]; then
        return 0
    fi
    printf '%s\n' "${roots[@]}"
}

#######################################
# resolve_verifier_skill_root: Locate installed checker skill directory
#
# Globals:
#   AGENT_CHECKER_SKILL_NAME - Caller-supplied skill name (read)
#   VERIFIER_SKILL_ROOT - Optional absolute override (read)
#
# Arguments:
#   None
#
# Outputs:
#   Absolute skill directory on stdout
#
# Returns:
#   0 when found; 1 when missing or name unset
#
#######################################
function resolve_verifier_skill_root {
    local skill="${AGENT_CHECKER_SKILL_NAME:-}"
    local root candidate pkg_dir mod_dir

    if [[ -n ${VERIFIER_SKILL_ROOT:-} ]]; then
        if [[ -d ${VERIFIER_SKILL_ROOT} ]]; then
            printf '%s\n' "${VERIFIER_SKILL_ROOT}"
            return 0
        fi
        echo "::warning::VERIFIER_SKILL_ROOT is set but not a directory: ${VERIFIER_SKILL_ROOT}" >&2
        return 1
    fi

    if [[ -z ${skill} ]]; then
        return 1
    fi

    while IFS= read -r root; do
        [[ -z ${root} ]] && continue

        for candidate in \
            "${root}/.claude/skills/${skill}" \
            "${root}/.agents/skills/${skill}"; do
            if [[ -d ${candidate} ]]; then
                printf '%s\n' "${candidate}"
                return 0
            fi
        done

        shopt -s nullglob
        for pkg_dir in "${root}/.apm/packages"/*/; do
            candidate="${pkg_dir}.apm/skills/${skill}"
            if [[ -d ${candidate} ]]; then
                shopt -u nullglob
                printf '%s\n' "${candidate}"
                return 0
            fi
        done
        for mod_dir in "${root}/apm_modules"/*/*/; do
            candidate="${mod_dir}.apm/skills/${skill}"
            if [[ -d ${candidate} ]]; then
                shopt -u nullglob
                printf '%s\n' "${candidate}"
                return 0
            fi
        done
        shopt -u nullglob
    done < <(verifier_skill_workspace_roots)

    echo "::warning::checker skill not found: ${skill}; using embedded checker prompt fallbacks" >&2
    return 1
}

#######################################
# bind_verifier_skill: Resolve skill dir into VERIFIER_SKILL_ROOT
#
# Globals:
#   AGENT_CHECKER_SKILL_NAME - Caller-supplied skill name (read)
#   VERIFIER_SKILL_ROOT - Skill directory (write when resolved)
#
# Arguments:
#   None
#
# Outputs:
#   None
#
# Returns:
#   0
#
#######################################
function bind_verifier_skill {
    local skill_root
    if [[ -z ${AGENT_CHECKER_SKILL_NAME:-} ]]; then
        return 0
    fi
    if skill_root="$(resolve_verifier_skill_root)"; then
        VERIFIER_SKILL_ROOT="${skill_root}"
    fi
}

#######################################
# write_verifier_skill_slash: Print slash load line for the checker prompt
#
# Globals:
#   AGENT_CHECKER_SKILL_NAME - Caller-supplied skill name (read)
#   VERIFIER_SKILL_ROOT - Bound skill directory (read)
#
# Arguments:
#   None
#
# Outputs:
#   Slash invocation line to stdout (or nothing)
#
# Returns:
#   0
#
#######################################
function write_verifier_skill_slash {
    if [[ -n ${VERIFIER_SKILL_ROOT:-} && -f ${VERIFIER_SKILL_ROOT}/SKILL.md ]]; then
        printf '/skill %s\n' "${VERIFIER_SKILL_ROOT}/SKILL.md"
    fi
}

#######################################
# write_verifier_skill_input: Print checker-skill Input for the checker prompt
#
# Globals:
#   AGENT_CHECKER_SKILL_NAME - Caller-supplied skill name (read)
#   VERIFIER_SKILL_ROOT - Bound skill directory (read)
#
# Arguments:
#   None
#
# Outputs:
#   Markdown Input block to stdout
#
# Returns:
#   0
#
#######################################
function write_verifier_skill_input {
    local name="${AGENT_CHECKER_SKILL_NAME:-}"
    if [[ -n ${VERIFIER_SKILL_ROOT:-} && -f ${VERIFIER_SKILL_ROOT}/SKILL.md ]]; then
        echo "Checker skill: ${name}"
        echo "Follow ${VERIFIER_SKILL_ROOT}/SKILL.md and its references."
        echo "Do not implement fixes in this role."
        return 0
    fi
    if [[ -n ${name} ]]; then
        echo "Checker skill: ${name} (skill files not found; use prompt fallbacks)"
        return 0
    fi
    echo "Checker skill: (none supplied)"
}
