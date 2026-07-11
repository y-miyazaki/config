#!/bin/bash
#######################################
# Description: Shared prompt and parsing utilities for loop-execute
#
# Usage: source "${SCRIPT_DIR}/lib/common.sh"
#
# Output:
# - None (library file, sourced by other scripts)
#
# Design Rules:
# - Prompt defaults are applied only when caller env vars are empty
# - Template placeholders use {{key}} syntax
#######################################

#######################################
# load_default_prompts: Apply built-in prompt defaults
#
# Description:
#   Fills empty PROMPT_* env vars with loop-execute defaults.
#
# Arguments:
#   None
#
# Global Variables:
#   PROMPT_IMPLEMENTER_FEEDBACK - Implementer retry template
#   PROMPT_VERIFIER_INITIAL - Verifier initial-mode intro
#   PROMPT_VERIFIER_REGRESSION - Verifier regression-mode body
#   PROMPT_VERIFIER_TASK - Verifier task section
#   PROMPT_VERIFIER_OUTPUT_CONTRACT - Verifier JSON output contract
#   PROMPT_VERIFIER_DEFAULT_CRITERIA - Default APPROVE/REJECT criteria
#
# Returns:
#   None
#
#######################################
function load_default_prompts {
    if [[ -z ${PROMPT_IMPLEMENTER_FEEDBACK:-} ]]; then
        PROMPT_IMPLEMENTER_FEEDBACK=$'{{base_prompt}}\n\n## Verifier Feedback (must address)\n\nPrevious attempt(s) were REJECTED. Edit **only** the files listed under **Files** and apply each **Required fix**:\n\n{{feedback}}\n\nAfter editing, your changes must be written to disk. Do not make unrelated changes.'
    fi
    if [[ -z ${PROMPT_VERIFIER_INITIAL:-} ]]; then
        PROMPT_VERIFIER_INITIAL=$'You are in INITIAL verification mode (attempt {{attempt}}).\nScrutinize the branch diff for factual blockers and scope violations.'
    fi
    if [[ -z ${PROMPT_VERIFIER_REGRESSION:-} ]]; then
        PROMPT_VERIFIER_REGRESSION=$'You are in REGRESSION verification mode (attempt {{attempt}}).\nCheck whether prior open rejections were fixed. Do not hunt for new nits.\n\n### Rules\n\n- REJECT only if a prior open rejection is still unfixed or factually wrong\n- REJECT if this attempt introduced a new factual error in changed files\n- Do NOT REJECT for style, preference, or unrelated nits\n- Do NOT re-litigate an open rejection that this attempt correctly fixed\n\n### Prior Open Rejections\n\n{{open_rejections}}\n\n### This Attempt\047s Delta\n```\n{{attempt_delta}}\n```'
    fi
    if [[ -z ${PROMPT_VERIFIER_TASK:-} ]]; then
        PROMPT_VERIFIER_TASK=$'Review the changes produced by the loop implementer agent and determine whether they should be merged.'
    fi
    if [[ -z ${PROMPT_VERIFIER_OUTPUT_CONTRACT:-} ]]; then
        PROMPT_VERIFIER_OUTPUT_CONTRACT=$'## Output (machine-readable — required)\n\nEnd your response with a single fenced JSON block (no prose after it):\n\n```json\n{\n  "verdict": "APPROVE",\n  "reason": "one-line summary"\n}\n```\n\nor on REJECT:\n\n```json\n{\n  "verdict": "REJECT",\n  "files": ["path/to/file"],\n  "issue": "what is factually wrong",\n  "fix": "specific change the implementer must make",\n  "reason": "one-line summary for logs"\n}\n```\n\nRules:\n- "verdict" must be "APPROVE" or "REJECT"\n- On REJECT, "files" (array), "issue", "fix", and "reason" are required\n- Use repo-relative paths in files'
    fi
    if [[ -z ${PROMPT_VERIFIER_DEFAULT_CRITERIA:-} ]]; then
        PROMPT_VERIFIER_DEFAULT_CRITERIA=$'## Criteria for APPROVE\n\nALL of the following must be true:\n1. Changes are consistent with the codebase\n2. No sensitive information is exposed\n3. No files outside the expected scope are modified\n4. Changes are coherent and non-destructive\n\n## Criteria for REJECT\n\nANY of the following triggers REJECT:\n- Changes outside expected scope\n- Factual inaccuracies or hallucinated content\n- Sensitive data exposure\n- Gratuitous or unrelated changes'
    fi
}

#######################################
# normalize_no_changes_verdict: Normalize NO_CHANGES_VERDICT env var
#
# Description:
#   Coerces NO_CHANGES_VERDICT to APPROVE or REJECT (default APPROVE).
#
# Arguments:
#   None
#
# Global Variables:
#   NO_CHANGES_VERDICT - Verdict when implementer produces no file changes
#
# Returns:
#   None
#
#######################################
function normalize_no_changes_verdict {
    NO_CHANGES_VERDICT=$(printf '%s' "${NO_CHANGES_VERDICT:-APPROVE}" | tr '[:lower:]' '[:upper:]')
    if [[ ${NO_CHANGES_VERDICT} != "REJECT" ]]; then
        NO_CHANGES_VERDICT="APPROVE"
    fi
}

#######################################
# parse_output_field: Extract a legacy line-oriented field from agent output
#
# Arguments:
#   $1 - Output file path
#   $2 - Field name (e.g. REASON, FILES)
#
# Global Variables:
#   None
#
# Returns:
#   Field value to stdout, or empty string
#
#######################################
function parse_output_field {
    local output_file="$1"
    local field="$2"
    grep -E "^${field}:[[:space:]]+" "${output_file}" 2> /dev/null | tail -1 | sed -E "s/^${field}:[[:space:]]*//" || true
}

#######################################
# render_template: Replace {{key}} placeholders in a template string
#
# Arguments:
#   $1 - Template string
#   $2.. - Alternating key/value pairs
#
# Global Variables:
#   None
#
# Returns:
#   Rendered template to stdout
#
#######################################
function render_template {
    local template="$1"
    local key value result="${template}"
    shift
    while [[ $# -gt 0 ]]; do
        key="$1"
        value="$2"
        result="${result//\{\{${key}\}\}/${value}}"
        shift 2
    done
    printf '%s' "${result}"
}
