#!/usr/bin/env bats

# Tests for the header block of .github/actions/*/action.yml
#
# Use cases:
# - every composite action opens with the 39-character separator and closes it right before name:
# - the header holds only comment lines and all five sections (Description, Usage, Design Rules, Dependencies, References) in the fixed order
# - Description starts with a composite action kind line and Usage names the action
# - every section has at least one content line (None when a section does not apply)
# - every path listed under References exists in the repository

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

SEPARATOR="#######################################"
KIND_RE='^#   Composite action: .+'

setup() {
    ROOT_DIR="$(bats_workspace_root)"
    mapfile -t ACTIONS < <(find "${ROOT_DIR}/.github/actions" -mindepth 2 -maxdepth 2 -name 'action.yml' | sort)
}

# header_of prints the lines before the top-level name: key.
header_of() {
    awk '/^name:/ { exit } { print }' "$1"
}

@test "every Description starts with a composite action kind line" {
    local f first checked=0
    for f in "${ACTIONS[@]}"; do
        [ "$(header_of "${f}" | sed -n 2p)" = "# Description:" ] || {
            echo "Description must be first: ${f}"
            return 1
        }
        first="$(header_of "${f}" | sed -n 3p)"
        [[ ${first} =~ ${KIND_RE} ]] || {
            echo "bad kind line in ${f}: ${first}"
            return 1
        }
        checked=$((checked + 1))
    done
    [ "${checked}" -gt 20 ]
}

@test "every action header holds only comment lines and all sections in order" {
    local f line section last_rank rank checked=0
    for f in "${ACTIONS[@]}"; do
        last_rank=0
        while IFS= read -r line; do
            [[ ${line} == "#"* ]] || {
                echo "non-comment header line in ${f}: ${line}"
                return 1
            }
            if [[ ${line} =~ ^#\ ([A-Z][A-Za-z\ ]*):$ ]]; then
                section="${BASH_REMATCH[1]}"
                case "${section}" in
                    Description) rank=1 ;;
                    Usage) rank=2 ;;
                    "Design Rules") rank=3 ;;
                    Dependencies) rank=4 ;;
                    References) rank=5 ;;
                    *)
                        echo "unknown section ${section} in ${f}"
                        return 1
                        ;;
                esac
                [ "${rank}" -eq $((last_rank + 1)) ] || {
                    echo "section order in ${f}: ${section}"
                    return 1
                }
                last_rank="${rank}"
            fi
        done < <(header_of "${f}")
        [ "${last_rank}" -eq 5 ] || {
            echo "missing sections in ${f}"
            return 1
        }
        checked=$((checked + 1))
    done
    [ "${checked}" -gt 20 ]
}

@test "every action header starts and ends with the separator right before name:" {
    local f header checked=0
    for f in "${ACTIONS[@]}"; do
        header="$(header_of "${f}")"
        [ "$(head -n 1 <<< "${header}")" = "${SEPARATOR}" ] || {
            echo "bad first line: ${f}"
            return 1
        }
        [ "$(tail -n 1 <<< "${header}")" = "${SEPARATOR}" ] || {
            echo "bad last line: ${f}"
            return 1
        }
        checked=$((checked + 1))
    done
    [ "${checked}" -gt 20 ]
}

@test "every section has at least one content line" {
    local f prev line checked=0
    for f in "${ACTIONS[@]}"; do
        prev=""
        while IFS= read -r line; do
            if [[ ${prev} =~ ^#\ [A-Z][A-Za-z\ ]*:$ ]]; then
                [[ ${line} == "#   "* ]] || {
                    echo "empty section ${prev} in ${f}"
                    return 1
                }
            fi
            prev="${line}"
        done < <(header_of "${f}")
        checked=$((checked + 1))
    done
    [ "${checked}" -gt 20 ]
}

@test "every Usage names its own action" {
    local f name checked=0
    for f in "${ACTIONS[@]}"; do
        name="$(basename "$(dirname "${f}")")"
        header_of "${f}" | grep -q "^#   uses: y-miyazaki/config/.github/actions/${name}@" || {
            echo "Usage does not name ${name}: ${f}"
            return 1
        }
        checked=$((checked + 1))
    done
    [ "${checked}" -gt 20 ]
}

@test "every References path exists in the repository" {
    local f path checked=0
    for f in "${ACTIONS[@]}"; do
        while IFS= read -r path; do
            [ -e "${ROOT_DIR}/${path}" ] || {
                echo "missing reference ${path} in ${f}"
                return 1
            }
            checked=$((checked + 1))
        done < <(header_of "${f}" | awk '/^# References:/ { r = 1; next } r && /^#   - / { sub(/^#   - /, ""); print }')
    done
    [ "${checked}" -gt 20 ]
}
