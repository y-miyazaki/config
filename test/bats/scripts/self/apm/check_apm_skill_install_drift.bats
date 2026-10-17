#!/usr/bin/env bats
# shellcheck disable=SC2016,SC2030,SC2031,SC2034,SC2154

# Tests for scripts/self/apm/check_apm_skill_install_drift.sh
#
# Use cases:
# - record_drift appends a line and increments the counter
# - check_skill_target_drift reports a missing install mirror
# - check_skill_target_drift reports a missing APM source
# - check_skill_target_drift finds no drift for identical directories
# - check_skill_target_drift records diff lines for differing directories
# - main returns 1 and prints drift lines plus a stderr summary when drift exists
# - main returns 0 and prints an OK summary when no drift exists

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

setup() {
    REPO_ROOT="$(bats_workspace_root)"
    SCRIPT_PATH="${REPO_ROOT}/scripts/self/apm/check_apm_skill_install_drift.sh"

    FIXTURE_ROOT="${BATS_TEST_TMPDIR}/workspace"
    mkdir -p "${FIXTURE_ROOT}/.apm/packages/pkg1/.apm/skills/skill-ok" \
        "${FIXTURE_ROOT}/.claude/skills/skill-ok" \
        "${FIXTURE_ROOT}/.apm/packages/pkg1/.apm/skills/skill-diff" \
        "${FIXTURE_ROOT}/.claude/skills/skill-diff"
    echo "same content" > "${FIXTURE_ROOT}/.apm/packages/pkg1/.apm/skills/skill-ok/SKILL.md"
    echo "same content" > "${FIXTURE_ROOT}/.claude/skills/skill-ok/SKILL.md"
    echo "source content" > "${FIXTURE_ROOT}/.apm/packages/pkg1/.apm/skills/skill-diff/SKILL.md"
    echo "mirror content" > "${FIXTURE_ROOT}/.claude/skills/skill-diff/SKILL.md"
}

@test "record_drift appends a line and increments the counter" {
    run env SCRIPT_PATH="${SCRIPT_PATH}" bash -c '
        source "$SCRIPT_PATH"
        record_drift "first issue"
        record_drift "second issue"
        printf "%s\n" "$DRIFT_COUNT" "${DRIFT_LINES[@]}"
    '
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "2" ]
    [ "${lines[1]}" = "first issue" ]
    [ "${lines[2]}" = "second issue" ]
}

@test "check_skill_target_drift reports a missing install mirror" {
    run env SCRIPT_PATH="${SCRIPT_PATH}" FIXTURE_ROOT="${FIXTURE_ROOT}" bash -c '
        source "$SCRIPT_PATH"
        WORKSPACE_ROOT="$FIXTURE_ROOT"
        check_skill_target_drift skill-ok .claude/skills-missing
        printf "%s\n" "$DRIFT_COUNT" "${DRIFT_LINES[@]}"
    '
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "1" ]
    [ "${lines[1]}" = "Missing install mirror: .claude/skills-missing/skill-ok" ]
}

@test "check_skill_target_drift reports a missing APM source" {
    mkdir -p "${FIXTURE_ROOT}/.claude/skills/skill-no-source"

    run env SCRIPT_PATH="${SCRIPT_PATH}" FIXTURE_ROOT="${FIXTURE_ROOT}" bash -c '
        source "$SCRIPT_PATH"
        WORKSPACE_ROOT="$FIXTURE_ROOT"
        check_skill_target_drift skill-no-source .claude/skills
        printf "COUNT=%s\n" "$DRIFT_COUNT"
        printf "LINE=%s\n" "${DRIFT_LINES[@]}"
    '
    [ "$status" -eq 0 ]
    [[ ${output} == *"COUNT=1"* ]]
    [[ ${output} == *"LINE=Missing APM source for skill: skill-no-source"* ]]
}

@test "check_skill_target_drift finds no drift for identical directories" {
    run env SCRIPT_PATH="${SCRIPT_PATH}" FIXTURE_ROOT="${FIXTURE_ROOT}" bash -c '
        source "$SCRIPT_PATH"
        WORKSPACE_ROOT="$FIXTURE_ROOT"
        check_skill_target_drift skill-ok .claude/skills
        printf "%s\n" "$DRIFT_COUNT"
    '
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "0" ]
}

@test "check_skill_target_drift records diff lines for differing directories" {
    run env SCRIPT_PATH="${SCRIPT_PATH}" FIXTURE_ROOT="${FIXTURE_ROOT}" bash -c '
        source "$SCRIPT_PATH"
        WORKSPACE_ROOT="$FIXTURE_ROOT"
        check_skill_target_drift skill-diff .claude/skills
        printf "%s\n" "$DRIFT_COUNT" "${DRIFT_LINES[@]}"
    '
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "1" ]
    [[ ${lines[1]} == *"SKILL.md"* ]]
}

@test "main returns 1 and prints drift lines plus a stderr summary when drift exists" {
    run env SCRIPT_PATH="${SCRIPT_PATH}" FIXTURE_ROOT="${FIXTURE_ROOT}" bash -c '
        source "$SCRIPT_PATH"
        WORKSPACE_ROOT="$FIXTURE_ROOT"
        LOOP_SKILLS=(skill-diff)
        INSTALL_TARGETS=(.claude/skills)
        main
    '
    [ "$status" -eq 1 ]
    [[ ${output} == *"SKILL.md"* ]]
    [[ ${output} == *"apm skill install drift: 1 issue(s); run: apm install --update"* ]]
}

@test "main returns 0 and prints an OK summary when no drift exists" {
    run env SCRIPT_PATH="${SCRIPT_PATH}" FIXTURE_ROOT="${FIXTURE_ROOT}" bash -c '
        source "$SCRIPT_PATH"
        WORKSPACE_ROOT="$FIXTURE_ROOT"
        LOOP_SKILLS=(skill-ok)
        INSTALL_TARGETS=(.claude/skills)
        main
    '
    [ "$status" -eq 0 ]
    [ "$output" = "apm skill install drift: OK (1 skills × 1 targets)" ]
}
