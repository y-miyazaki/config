#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154

# Tests for .github/actions/lib/loop/detect_env.sh
#
# Use cases:
# - loop_build_detect_env_args yields no entries for empty input and {}
# - loop_build_detect_env_args builds KEY=VALUE entries and skips empty and null values
# - loop_build_detect_env_args does not export entries or write GITHUB_ENV
# - loop_build_detect_env_args rejects non-object JSON
# - loop_build_detect_env_args rejects keys that do not match the allowed pattern
# - loop_build_detect_env_args rejects reserved names
# - loop_build_detect_env_args rejects a key that is already set
# - loop_build_detect_env_args rejects array and object values
# - loop_build_detect_env_args rejects values containing a newline
# - the entries reach a child process through env

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

setup() {
    bats_source_rel ".github/actions/lib/loop/detect_env.sh"
    GITHUB_ENV="${BATS_TEST_TMPDIR}/github_env"
    : > "${GITHUB_ENV}"
    export GITHUB_ENV
}

@test "loop_build_detect_env_args builds KEY=VALUE entries and skips empty and null values" {
    loop_build_detect_env_args '{"DETECT_T_A":"one","DETECT_T_B":"","DETECT_T_C":3,"DETECT_T_D":null,"DETECT_T_E":true}'
    [ "${#LOOP_DETECT_ENV_ARGS[@]}" -eq 3 ]
    [ "${LOOP_DETECT_ENV_ARGS[0]}" = "DETECT_T_A=one" ]
    [ "${LOOP_DETECT_ENV_ARGS[1]}" = "DETECT_T_C=3" ]
    [ "${LOOP_DETECT_ENV_ARGS[2]}" = "DETECT_T_E=true" ]
}

@test "loop_build_detect_env_args does not export entries or write GITHUB_ENV" {
    loop_build_detect_env_args '{"DETECT_T_F":"x"}'
    [ -z "${DETECT_T_F+x}" ]
    [ ! -s "${GITHUB_ENV}" ]
}

@test "loop_build_detect_env_args rejects a key that is already set" {
    export DETECT_T_G="existing"
    run loop_build_detect_env_args '{"DETECT_T_G":"x"}'
    [ "$status" -eq 1 ]
    [[ $output == *"conflicts with an existing variable: DETECT_T_G"* ]]
}

@test "loop_build_detect_env_args rejects array and object values" {
    run loop_build_detect_env_args '{"DETECT_T_H":[1,2]}'
    [ "$status" -eq 1 ]
    [[ $output == *"must be scalars (key: DETECT_T_H)"* ]]
    run loop_build_detect_env_args '{"DETECT_T_H":{"a":1}}'
    [ "$status" -eq 1 ]
}

@test "loop_build_detect_env_args rejects keys that do not match the allowed pattern" {
    run loop_build_detect_env_args '{"lower":"x"}'
    [ "$status" -eq 1 ]
    [[ $output == *"keys must match"* ]]
}

@test "loop_build_detect_env_args rejects non-object JSON" {
    run loop_build_detect_env_args '["A"]'
    [ "$status" -eq 1 ]
    [[ $output == *"must be a JSON object"* ]]
}

@test "loop_build_detect_env_args rejects reserved names" {
    local key
    for key in BASH_ENV GH_TOKEN GIT_DIR GITHUB_TOKEN HTTPS_PROXY LD_PRELOAD NODE_OPTIONS PATH RUNNER_TEMP SSL_CERT_FILE TMPDIR; do
        run loop_build_detect_env_args "{\"${key}\":\"x\"}"
        [ "$status" -eq 1 ]
        [[ $output == *"reserved: ${key}"* ]]
    done
}

@test "loop_build_detect_env_args rejects values containing a newline" {
    run loop_build_detect_env_args '{"DETECT_T_I":"a\nb"}'
    [ "$status" -eq 1 ]
    [[ $output == *"must not contain newlines (key: DETECT_T_I)"* ]]
}

@test "loop_build_detect_env_args yields no entries for empty input and {}" {
    LOOP_DETECT_ENV_ARGS=(stale)
    loop_build_detect_env_args ""
    [ "${#LOOP_DETECT_ENV_ARGS[@]}" -eq 0 ]
    loop_build_detect_env_args "{}"
    [ "${#LOOP_DETECT_ENV_ARGS[@]}" -eq 0 ]
}

@test "the entries reach a child process through env" {
    loop_build_detect_env_args '{"DETECT_T_J":"child value"}'
    # shellcheck disable=SC2016 # expansion must happen in the child shell
    run env "${LOOP_DETECT_ENV_ARGS[@]}" bash -c 'printf %s "${DETECT_T_J}"'
    [ "$status" -eq 0 ]
    [ "$output" = "child value" ]
    [ -z "${DETECT_T_J+x}" ]
}
