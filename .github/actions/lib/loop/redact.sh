#!/bin/bash
#######################################
# Description:
#   Redact common secret patterns from loop failure and notify text.
#
# Usage:
#   source redact.sh
#   redact_sensitive_text TEXT
#
# Output:
#   None (library file, sourced by other scripts)
#
# Design Rules:
#   - Keep patterns aligned with loop-ci-sweeper sanitize_log_excerpt
#######################################

#######################################
# redact_sensitive_text: Redact common secret patterns
#
# Globals:
#   None
#
# Arguments:
#   $1 - Input text
#
# Outputs:
#   Redacted text to stdout
#
# Returns:
#   0 on success
#
#######################################
function redact_sensitive_text {
    local text="$1"
    text=$(sed -E 's/-----BEGIN [A-Z ]+-----[^-]*-----END [A-Z ]+-----/[REDACTED-PEM]/g' <<< "${text}")
    text=$(sed -E 's/eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+/[REDACTED-JWT]/g' <<< "${text}")
    text=$(sed -E 's/x-access-token:[A-Za-z0-9._-]+/x-access-token:[REDACTED]/g' <<< "${text}")
    text=$(sed -E 's/Bearer[[:space:]]+[A-Za-z0-9._-]+/Bearer [REDACTED]/g' <<< "${text}")
    text=$(sed -E 's/Authorization:[[:space:]]*[^[:space:]\"]+/Authorization: [REDACTED]/gi' <<< "${text}")
    text=$(sed -E 's/gh[pousr]_[A-Za-z0-9_]{20,}/[REDACTED]/g' <<< "${text}")
    text=$(sed -E 's/AKIA[0-9A-Z]{16}/[REDACTED]/g' <<< "${text}")
    text=$(sed -E 's/(password|secret|token|api[_-]?key)[[:space:]]*[:=][[:space:]]*[^[:space:]\"]+/\1=[REDACTED]/gi' <<< "${text}")
    printf '%s' "${text}"
}
