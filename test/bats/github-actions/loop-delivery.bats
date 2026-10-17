#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2154

# Tests for .github/actions/lib/loop/delivery.sh
#
# Use cases:
# - derive_pr_auto_merge over level x delivery
# - validate_delivery_value accepts implemented values and rejects the rest
# - validate_delivery_detect_config rules for branch callers
# - delivery_requires_pr_number_skip for pr_push
# - validate_delivery_target per target kind
# - golden table frozen from the pre-delivery implementation

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

DELIVERY_LIB="$(bats_workspace_root)/.github/actions/lib/loop/delivery.sh"

setup() {
    # shellcheck disable=SC1090
    source "${DELIVERY_LIB}"
}

@test "delivery_requires_pr_number_skip: pr_create empty does not skip" {
    run delivery_requires_pr_number_skip pr_create ""
    [ "$status" -eq 1 ]
}

@test "delivery_requires_pr_number_skip: pr_push empty skips" {
    run delivery_requires_pr_number_skip pr_push ""
    [ "$status" -eq 0 ]
}

@test "delivery_requires_pr_number_skip: pr_push with number does not skip" {
    run delivery_requires_pr_number_skip pr_push 12
    [ "$status" -eq 1 ]
}

@test "delivery_requires_pr_number_skip: pr_push zero skips" {
    run delivery_requires_pr_number_skip pr_push 0
    [ "$status" -eq 0 ]
}

@test "derive_pr_auto_merge: only L3 pr_create is true" {
    local level delivery expected out
    for level in L1 L2 L3; do
        for delivery in none pr_create pr_push; do
            expected=false
            [[ ${level} == L3 && ${delivery} == pr_create ]] && expected=true
            out="$(derive_pr_auto_merge "${level}" "${delivery}")"
            [ "${out}" = "${expected}" ] || {
                echo "${level} ${delivery}: got ${out}, want ${expected}"
                return 1
            }
        done
    done
}

@test "golden: every old combination maps or is rejected consistently" {
    # Old behavior frozen from resolve_git_finalize_strategies (detect.sh) and the
    # caller auto_merge expression (ci-loop-caller.yaml). Row format:
    #   delivery git_landing_integration git_landing_pull_request finalize_integration finalize_pull_request
    local -a rows=(
        "none open_pr open_pr none none"
        "none open_pr push_head none none"
        "none push open_pr none none"
        "none push push_head none none"
        "open_pr open_pr open_pr open_pr open_pr"
        "open_pr open_pr push_head open_pr push_head"
        "open_pr push open_pr push open_pr"
        "open_pr push push_head push push_head"
    )
    local -a target_sets=("integration" "pull_request" "integration pull_request")
    local row targets level old_delivery fin_i fin_p kind fin mapped new_delivery old_am
    local -a fins
    local mappable cand cand_ok i mapped_cand
    for row in "${rows[@]}"; do
        read -r old_delivery _ _ fin_i fin_p <<< "${row}"
        for targets in "${target_sets[@]}"; do
            fins=()
            for kind in ${targets}; do
                [[ ${kind} == integration ]] && fins+=("${fin_i}") || fins+=("${fin_p}")
            done
            # Map old finalize values to new delivery values.
            mappable=true
            new_delivery=""
            for fin in "${fins[@]}"; do
                case "${fin}" in
                    open_pr) mapped=pr_create ;;
                    push_head) mapped=pr_push ;;
                    none) mapped=none ;;
                    *) mapped="" ;;
                esac
                if [[ -z ${mapped} ]] || { [[ -n ${new_delivery} ]] && [[ ${new_delivery} != "${mapped}" ]]; }; then
                    mappable=false
                    break
                fi
                new_delivery="${mapped}"
            done
            for level in L1 L2 L3; do
                if [[ ${mappable} == true ]]; then
                    validate_delivery_value "${new_delivery}"
                    # Old auto_merge: delivery == open_pr && level == L3 && target finalize == open_pr
                    for fin in "${fins[@]}"; do
                        old_am=false
                        [[ ${old_delivery} == open_pr && ${level} == L3 && ${fin} == open_pr ]] && old_am=true
                        [ "$(derive_pr_auto_merge "${level}" "${new_delivery}")" = "${old_am}" ] || {
                            echo "auto_merge mismatch: ${row} | ${targets} | ${level}"
                            return 1
                        }
                    done
                    for kind in ${targets}; do
                        validate_delivery_target "${new_delivery}" "{\"mode\":\"${kind}\"}" || {
                            echo "target rejected: ${row} | ${kind} -> ${new_delivery}"
                            return 1
                        }
                    done
                    # Old finalize_enabled: true for L2/L3 on every validated combination.
                    if [[ ${level} != L1 ]]; then
                        [[ ${old_delivery} == open_pr || ${old_delivery} == none ]]
                    fi
                else
                    # No single new delivery reproduces the old per-target finalize values.
                    for cand in none pr_create pr_push; do
                        cand_ok=true
                        i=0
                        for kind in ${targets}; do
                            validate_delivery_target "${cand}" "{\"mode\":\"${kind}\"}" 2> /dev/null || cand_ok=false
                            case "${cand}" in
                                pr_create) mapped_cand=open_pr ;;
                                pr_push) mapped_cand=push_head ;;
                                *) mapped_cand=none ;;
                            esac
                            [[ ${fins[i]} == "${mapped_cand}" ]] || cand_ok=false
                            i=$((i + 1))
                        done
                        [[ ${cand_ok} == false ]] || {
                            echo "unmappable row accepted: ${row} | ${targets} | ${cand}"
                            return 1
                        }
                    done
                fi
            done
        done
    done
}

@test "validate_delivery_detect_config: pr_create with branch match passes" {
    run validate_delivery_detect_config pr_create false main
    [ "$status" -eq 0 ]
}

@test "validate_delivery_detect_config: pr_create with no detect source fails" {
    run validate_delivery_detect_config pr_create false ""
    [ "$status" -eq 1 ]
}

@test "validate_delivery_detect_config: pr_create with pr detect passes" {
    run validate_delivery_detect_config pr_create true ""
    [ "$status" -eq 0 ]
}

@test "validate_delivery_detect_config: pr_push true empty passes" {
    run validate_delivery_detect_config pr_push true ""
    [ "$status" -eq 0 ]
}

@test "validate_delivery_detect_config: pr_push with branch match fails" {
    run validate_delivery_detect_config pr_push true main
    [ "$status" -eq 1 ]
}

@test "validate_delivery_detect_config: pr_push without pr detect fails" {
    run validate_delivery_detect_config pr_push false ""
    [ "$status" -eq 1 ]
}

@test "validate_delivery_target: none accepts entity issue" {
    run validate_delivery_target none '{"entity":{"kind":"issue"}}'
    [ "$status" -eq 0 ]
}

@test "validate_delivery_target: pr_create accepts entity pr" {
    run validate_delivery_target pr_create '{"entity":{"kind":"pr"}}'
    [ "$status" -eq 0 ]
}

@test "validate_delivery_target: pr_push accepts pull_request" {
    run validate_delivery_target pr_push '{"mode":"pull_request"}'
    [ "$status" -eq 0 ]
}

@test "validate_delivery_target: pr_push rejects entity pr and issue" {
    run validate_delivery_target pr_push '{"entity":{"kind":"pr"}}'
    [ "$status" -eq 1 ]
    run validate_delivery_target pr_push '{"entity":{"kind":"issue"}}'
    [ "$status" -eq 1 ]
}

@test "validate_delivery_target: pr_push rejects integration" {
    run validate_delivery_target pr_push '{"mode":"integration"}'
    [ "$status" -eq 1 ]
}

@test "validate_delivery_target: unknown kind fails" {
    run validate_delivery_target pr_create '{"foo":1}'
    [ "$status" -eq 1 ]
}

@test "validate_delivery_value: implemented values pass" {
    local v
    for v in none pr_create pr_push; do
        run validate_delivery_value "${v}"
        [ "$status" -eq 0 ]
    done
}

@test "validate_delivery_value: unimplemented values fail with not implemented" {
    local v
    for v in issue_comment issue_create pr_review; do
        run validate_delivery_value "${v}"
        [ "$status" -eq 1 ]
        [[ $output == *"not implemented"* ]]
    done
}

@test "validate_delivery_value: unknown and empty values fail" {
    local v
    for v in open_pr log ""; do
        run validate_delivery_value "${v}"
        [ "$status" -eq 1 ]
        [[ $output == *"::error::"* ]]
    done
}
