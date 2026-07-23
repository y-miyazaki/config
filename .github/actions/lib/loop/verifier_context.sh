#!/bin/bash
#######################################
# Description: Derive verifier_context markdown from detect script JSON
#
# Usage:
#   source "${LOOP_ACTION_LIB_DIR}/verifier_context.sh"
#   build_verifier_context_from_result "${detect_json}"
#
# Output:
#   Markdown context on stdout (may be empty)
#
# Design Rules:
#   - Prefer explicit .verifier_context when present
#   - Otherwise map known detect JSON shapes to markdown sections
#######################################

#######################################
# build_verifier_context_from_result: Derive verifier_context markdown
#
# Globals:
#   None
#
# Arguments:
#   $1 - Detect script JSON result
#
# Outputs:
#   Markdown context on stdout (may be empty)
#
# Returns:
#   0 on success
#
#######################################
function build_verifier_context_from_result {
    local detect_result="$1"
    local explicit
    explicit=$(jq -r '.verifier_context // empty' <<< "${detect_result}" 2> /dev/null || true)
    if [[ -n ${explicit} ]]; then
        printf '%s' "${explicit}"
        return 0
    fi

    if jq -e '.failures' <<< "${detect_result}" > /dev/null 2>&1; then
        jq -r '
            if (.failures | length) == 0 then ""
            else
                "## CI Failures\n"
                + (.failures[] |
                    "- **\(.workflow_name // "workflow")** run \(.workflow_run_id // "-") job \(.job_name // "-")\n"
                    + "  - branch: \(.head_branch // "-")\n"
                    + "  - type: \(.failure_type // "-")\n"
                    + "  - excerpt:\n```\n\(.log_excerpt // "" | .[0:2000])\n```\n"
                )
            end
        ' <<< "${detect_result}"
        return 0
    fi

    if jq -e '.commits' <<< "${detect_result}" > /dev/null 2>&1; then
        jq -r '
            if (.commits | length) == 0 then ""
            else
                (.repository_url // "") as $repo_url
                | "## Changelog Commits\n"
                + "- file: " + (.changelog_file // "CHANGELOG.md") + "\n"
                + "- count: " + ((.commits | length) | tostring) + "\n"
                + (if ((.compare_url // "") | length) > 0 then "- compare: " + .compare_url + "\n" else "" end)
                + (.commits[] |
                    "- **\(.type)\(if ((.scope // "") | length) > 0 then "(\(.scope))" else "" end)**: "
                    + .subject
                    + (
                        if ($repo_url | length) > 0 then
                            " ([\(.sha[0:7])](\($repo_url)/commit/\(.sha)))"
                        else
                            " (`\(.sha[0:8])`)"
                        end
                    )
                    + (if .breaking then " [breaking]" else "" end)
                    + "\n"
                )
            end
        ' <<< "${detect_result}"
        return 0
    fi

    if jq -e '.affected_docs' <<< "${detect_result}" > /dev/null 2>&1; then
        jq -r '
            "## Change Detection\n"
            + "- changed: " + ((.changed_files // []) | join(", ")) + "\n"
            + "- deleted: " + ((.deleted_files // []) | join(", ")) + "\n"
            + "- renamed: " + ((.renamed_files // []) | join(", ")) + "\n"
            + "- affected_docs: " + ((.affected_docs // []) | join(", "))
        ' <<< "${detect_result}"
        return 0
    fi

    if jq -e '.hints' <<< "${detect_result}" > /dev/null 2>&1; then
        jq -r '
            if (.hints | length) == 0 then ""
            else
                "## Refactor Hints\n"
                + "- scope: " + (.scope // "-") + "\n"
                + "- commit_range: " + (.commit_range // "-") + "\n"
                + (.hints[] |
                    "- **\(.kind)**: `\(.path)` — \(.detail)\n"
                )
            end
        ' <<< "${detect_result}"
        return 0
    fi

    if jq -e '.signals' <<< "${detect_result}" > /dev/null 2>&1; then
        jq -r '
            if ((.signals // []) | length) == 0 and ((.hotspots // []) | length) == 0 then ""
            else
                "## Tech Debt Signals\n"
                + "- report_file: " + (.report_file // "-") + "\n"
                + "- previous_report: " + (.previous_report // "-") + "\n"
                + "- signal_count: " + (((.signals // []) | length) | tostring) + "\n"
                + "- hotspot_count: " + (((.hotspots // []) | length) | tostring) + "\n"
                + (
                    if ((.warnings // []) | length) == 0 then ""
                    else "- warnings: " + ((.warnings // []) | join("; ")) + "\n"
                    end
                )
                + (
                    if ((.signals // []) | length) == 0 then ""
                    else (.signals[:10][] |
                        "- **\(.kind)**: `\(.path)`:\(.line) — \(.snippet // "" | .[0:120])\n"
                    )
                    end
                )
                + (
                    if ((.hotspots // []) | length) == 0 then ""
                    else
                        "\n## Hotspots\n"
                        + (.hotspots[:5][] |
                            "- `\(.path)` \(.metric)=\(.value) (\(.window))\n"
                        )
                    end
                )
            end
        ' <<< "${detect_result}"
        return 0
    fi

    printf ''
}
