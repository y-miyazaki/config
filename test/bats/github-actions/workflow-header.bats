#!/usr/bin/env bats

# Tests for the header block of .github/workflows/*.yaml and .github/workflows/example/*.yaml
#
# Use cases:
# - every workflow opens with the 39-character separator and closes it right before name:
# - the header holds only comment lines and all five sections (Description, Usage, Design Rules, Dependencies, References) in the fixed order
# - Description starts with a workflow kind line and Usage is present
# - every section has at least one content line (None when a section does not apply)

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

SEPARATOR="#######################################"
KIND_RE='^#   (Reusable|Loop|CI|CD|Manual|Platform) workflow: .+'

setup() {
    WORKFLOW_DIR="$(bats_workspace_root)/.github/workflows"
    mapfile -t WORKFLOWS < <(find "${WORKFLOW_DIR}" -maxdepth 2 -name '*.yaml' | sort)
}

# header_of prints the lines before the top-level name: key.
header_of() {
    awk '/^name:/ { exit } { print }' "$1"
}

@test "every workflow header starts and ends with the separator right before name:" {
    local f header checked=0
    for f in "${WORKFLOWS[@]}"; do
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
    [ "${checked}" -gt 50 ]
}

@test "every workflow header holds only comment lines and allowed sections in order" {
    local f line section last_rank rank seen_count checked=0
    for f in "${WORKFLOWS[@]}"; do
        last_rank=0
        seen_count=0
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
                [ "${rank}" -gt "${last_rank}" ] || {
                    echo "section order in ${f}: ${section}"
                    return 1
                }
                last_rank="${rank}"
                seen_count=$((seen_count + 1))
            fi
        done < <(header_of "${f}")
        [ "${last_rank}" -ge 2 ] || {
            echo "missing Usage in ${f}"
            return 1
        }
        checked=$((checked + 1))
    done
    [ "${checked}" -gt 50 ]
}

@test "every Description starts with a workflow kind line" {
    local f first checked=0
    for f in "${WORKFLOWS[@]}"; do
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
    [ "${checked}" -gt 50 ]
}

@test "every section has at least one content line" {
    local f header prev line checked=0
    for f in "${WORKFLOWS[@]}"; do
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
    [ "${checked}" -gt 50 ]
}
