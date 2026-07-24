#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154

# Tests for .github/actions/loop-execute/lib/validate_agent_report.sh

# Use cases:
# - agent_report_skill_requires_format_check matches fix skills only
# - validate_agent_report accepts canonical apply output with matching git diff
# - validate_agent_report accepts survey output with Candidates and Watch
# - validate_agent_report accepts survey no-op without Candidates
# - validate_agent_report accepts watch-only survey without Candidates
# - reconcile_agent_report_with_branch_diff appends missing branch-diff rows after table body
# - reconcile_agent_report_with_branch_diff skips commit-based changelog Changes tables
# - validate_agent_report accepts changelog apply output without path rows in Changes

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

setup() {
    bats_source_rel ".github/actions/loop-execute/lib/validate_agent_report.sh"
    TEST_TMP="${BATS_TEST_TMPDIR}/validate_agent_report"
    mkdir -p "${TEST_TMP}"
}

@test "agent_report_skill_requires_format_check matches fix skills only" {
    run agent_report_skill_requires_format_check "docs-updater"
    [ "$status" -eq 0 ]
    run agent_report_skill_requires_format_check "unknown-skill"
    [ "$status" -eq 1 ]
}

@test "validate_agent_report accepts canonical output with matching git diff" {
    local out="${TEST_TMP}/good.txt"
    cat > "${out}" << 'EOF'
# Refactor Result

## Overview

Refactor scan found duplicated diff logic; this run deduplicated one call.

## Summary

### Changes

| Target | What was wrong | What changed |
| ------ | -------------- | ------------ |
| `scripts/self/ai/sync_skill_lib.sh` | diff ran twice | capture once |

## Verification

| Check | Result |
| ----- | ------ |
| shellcheck | pass |
EOF
    run validate_agent_report "${out}" $'scripts/self/ai/sync_skill_lib.sh\n' "refactor"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "validate_agent_report accepts survey no-op without Candidates" {
    local out="${TEST_TMP}/survey-noop.txt"
    cat > "${out}" << 'EOF'
## Overview

No actionable CI failures after triage; no edits applied.

## Summary

EOF
    run validate_agent_report "${out}" "" "ci-sweeper"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "validate_agent_report accepts survey output without Verification" {
    local out="${TEST_TMP}/survey.txt"
    cat > "${out}" << 'EOF'
## Overview

Debt scan over abc..def found broken links in docs/guide; no edits applied.

## Summary

### Candidates

| Target | Evidence | Suggested approach | Priority |
| ------ | -------- | ------------------ | -------- |
| docs/guide/overview.md | broken link | update href | high |

### Watch

| Target | Evidence | Why not now |
| ------ | -------- | ----------- |
| scripts/foo.sh | TODO marker | low urgency |
EOF
    run validate_agent_report "${out}" "" "tech-debt"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "validate_agent_report accepts watch-only survey without Candidates" {
    local out="${TEST_TMP}/survey-watch-only.txt"
    cat > "${out}" << 'EOF'
## Overview

Infra flake on workflow lint; logged as Watch; no edits applied.

## Summary

### Watch

| Target | Evidence | Why not now |
| ------ | -------- | ----------- |
| ci/lint | runner timeout | infra flake |
EOF
    run validate_agent_report "${out}" "" "ci-sweeper"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "validate_agent_report rejects Deferred path still in branch diff" {
    local out="${TEST_TMP}/deferred-mismatch.txt"
    cat > "${out}" << 'EOF'
## Overview

Docs drift found stale inventory; updated specification only.

## Summary

### Changes

| File | What was wrong | What changed |
| ---- | -------------- | ------------ |
| docs/reference/specification.md | missing rows | added rows |

### Deferred

| File | Why deferred |
| ---- | ------------ |
| docs/index.md | no inventory table |

## Verification

| Check | Result |
| ----- | ------ |
| markdownlint | pass |
EOF
    run validate_agent_report "${out}" $'docs/reference/specification.md\ndocs/index.md\n' "docs-updater"
    [ "$status" -eq 1 ]
    [[ $output == *"docs/index.md"* ]]
}

@test "validate_agent_report rejects apply output with Candidates subsection" {
    local out="${TEST_TMP}/apply-candidates.txt"
    cat > "${out}" << 'EOF'
## Overview

Fixed docs/foo.md heading style.

## Summary

### Candidates

| Target | Evidence | Suggested approach | Priority |
| ------ | -------- | ------------------ | -------- |
| docs/foo.md | MD001 | fix heading | high |

### Changes

| Target | What was wrong | What changed |
| ------ | -------------- | ------------ |
| docs/foo.md | MD001 | fixed heading |

## Verification

| Check | Result |
| ----- | ------ |
| lint | pass |
EOF
    run validate_agent_report "${out}" $'docs/foo.md\n' "ci-sweeper"
    [ "$status" -eq 1 ]
    [[ $output == *"must not include ### Candidates"* ]]
}

@test "validate_agent_report rejects apply output with Watch subsection" {
    local out="${TEST_TMP}/apply-watch.txt"
    cat > "${out}" << 'EOF'
## Overview

Fixed docs/foo.md heading style.

## Summary

### Changes

| Target | What was wrong | What changed |
| ------ | -------------- | ------------ |
| docs/foo.md | MD001 | fixed heading |

### Watch

| Target | Evidence | Why not now |
| ------ | -------- | ----------- |
| docs/bar.md | stale | later |

## Verification

| Check | Result |
| ----- | ------ |
| lint | pass |
EOF
    run validate_agent_report "${out}" $'docs/foo.md\n' "docs-updater"
    [ "$status" -eq 1 ]
    [[ $output == *"must not include ### Watch"* ]]
}

@test "validate_agent_report rejects branch diff path missing from Changes table" {
    local out="${TEST_TMP}/missing-change.txt"
    cat > "${out}" << 'EOF'
## Overview

Updated one doc file.

## Summary

### Changes

| File | What was wrong | What changed |
| ---- | -------------- | ------------ |
| docs/a.md | stale | fixed |

## Verification

| Check | Result |
| ----- | ------ |
| markdownlint | pass |
EOF
    run validate_agent_report "${out}" $'docs/a.md\ndocs/b.md\n' "docs-updater"
    [ "$status" -eq 1 ]
    [[ $output == *"docs/b.md"* ]]
}

@test "reconcile_agent_report_with_branch_diff appends missing branch-diff rows" {
    local out="${TEST_TMP}/reconcile.txt"
    cat > "${out}" << 'EOF'
## Overview

Updated one doc file.

## Summary

### Changes

| File | What was wrong | What changed |
| ---- | -------------- | ------------ |
| docs/a.md | stale | fixed |

## Verification

| Check | Result |
| ----- | ------ |
| markdownlint | pass |
EOF
    reconcile_agent_report_with_branch_diff "${out}" $'docs/a.md\ndocs/b.md\n' "docs-updater"
    run validate_agent_report "${out}" $'docs/a.md\ndocs/b.md\n' "docs-updater"
    [ "$status" -eq 0 ]
    grep -q 'docs/b.md' "${out}"
    # Placeholder row must follow existing data rows, not sit between header and separator.
    awk '
        /\| File \| What was wrong \| What changed \|/ { after_header = 1; next }
        after_header && /^\|[-: ]+\|/ { after_sep = 1; next }
        after_sep && /docs\/b\.md/ { found = 1 }
        END { exit !found }
    ' "${out}"
}

@test "reconcile_agent_report_with_branch_diff skips changelog commit-based Changes table" {
    local out="${TEST_TMP}/reconcile-changelog.txt"
    cat > "${out}" << 'EOF'
## Overview

Added changelog entries.

## Summary

### Changes

| Commit | Type | Entry |
| ------ | ---- | ----- |
| ee4621c | chore | Unreleased / Changed — example |

### Skipped

| Commit | Why skipped |
| ------ | ----------- |
| — | None |

## Verification

| Check | Result |
| ----- | ------ |
| CHANGELOG.md structure | pass |
EOF
    reconcile_agent_report_with_branch_diff "${out}" $'CHANGELOG.md\n' "changelog"
    run validate_agent_report "${out}" $'CHANGELOG.md\n' "changelog"
    [ "$status" -eq 0 ]
    run grep -q 'Updated in an earlier loop attempt' "${out}"
    [ "$status" -eq 1 ]
}

@test "validate_agent_report accepts changelog apply output with commit rows only" {
    local out="${TEST_TMP}/changelog-apply.txt"
    cat > "${out}" << 'EOF'
## Overview

Processed commits since abc..def; added Unreleased bullets and promoted releases.

## Summary

### Changes

| Commit | Type | Entry |
| ------ | ---- | ----- |
| ee4621c | chore | Unreleased / Changed — example |
| (230 SHAs) | chore/feat | Promoted into 1.8.43–1.8.58 |

### Skipped

| Commit | Why skipped |
| ------ | ----------- |
| — | None |

## Verification

| Check | Result |
| ----- | ------ |
| CHANGELOG.md structure | pass |
EOF
    run validate_agent_report "${out}" $'CHANGELOG.md\n' "changelog"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "validate_agent_report rejects legacy Fixes Applied and Outcome sections" {
    local out="${TEST_TMP}/legacy.txt"
    cat > "${out}" << 'EOF'
## Overview

Loop done.

## Summary

### Fixes Applied

| File | Reason | Change |
| ---- | ------ | ------ |
| docs/a.md | stale | fix |

**Outcome:** fixed 1

## Verification

| Check | Result |
| ----- | ------ |
| lint | pass |
EOF
    run validate_agent_report "${out}" $'docs/a.md\n' "docs-updater"
    [ "$status" -eq 1 ]
    [[ $output == *"Fixes Applied"* ]]
    [[ $output == *"Outcome"* ]]
}

@test "validate_agent_report rejects survey output with Deferred subsection" {
    local out="${TEST_TMP}/survey-deferred.txt"
    cat > "${out}" << 'EOF'
## Overview

Survey only.

## Summary

### Candidates

| Target | Evidence | Suggested approach | Priority |
| ------ | -------- | ------------------ | -------- |
| docs/a.md | stale | fix | high |

### Deferred

| Target | Why deferred |
| ------ | ------------ |
| docs/b.md | later |
EOF
    run validate_agent_report "${out}" "" "tech-debt"
    [ "$status" -eq 1 ]
    [[ $output == *"use ### Watch"* ]]
}

@test "validate_agent_report rejects survey output with Skipped subsection" {
    local out="${TEST_TMP}/survey-skipped.txt"
    cat > "${out}" << 'EOF'
## Overview

Survey only.

## Summary

### Candidates

| Target | Evidence | Suggested approach | Priority |
| ------ | -------- | ------------------ | -------- |
| abc1234 | feat: add widget | add bullet | high |

### Skipped

| Target | Why skipped |
| ------ | ----------- |
| def5678 | chore only |
EOF
    run validate_agent_report "${out}" "" "changelog"
    [ "$status" -eq 1 ]
    [[ $output == *"must not include ### Skipped"* ]]
}

@test "validate_agent_report rejects survey output with Verification section" {
    local out="${TEST_TMP}/survey-verif.txt"
    cat > "${out}" << 'EOF'
## Overview

Survey only.

## Summary

### Candidates

| Target | Evidence | Suggested approach | Priority |
| ------ | -------- | ------------------ | -------- |
| docs/a.md | stale | fix | high |

## Verification

| Check | Result |
| ----- | ------ |
| lint | pass |
EOF
    run validate_agent_report "${out}" "" "tech-debt"
    [ "$status" -eq 1 ]
    [[ $output == *"must not include ## Verification"* ]]
}

@test "validate_agent_report rejects survey output with branch diff" {
    local out="${TEST_TMP}/survey-diff.txt"
    cat > "${out}" << 'EOF'
## Overview

Survey only.

## Summary

### Candidates

| Target | Evidence | Suggested approach | Priority |
| ------ | -------- | ------------------ | -------- |
| docs/a.md | stale | fix | high |
EOF
    run validate_agent_report "${out}" $'docs/a.md\n' "tech-debt"
    [ "$status" -eq 1 ]
    [[ $output == *"non-empty branch diff"* ]]
}
