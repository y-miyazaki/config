#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2154

# Tests for scripts/db/aws_schemaspy.sh and scripts/db/install_schemaspy.sh (shared cache directory)
#
# Use cases:
# - the default cache directory is under the user cache, not the repository tree
# - SCHEMASPY_CACHE_DIR overrides the default
# - XDG_CACHE_HOME is honored when SCHEMASPY_CACHE_DIR is unset
# - install_schemaspy.sh and aws_schemaspy.sh agree on the default location
# - download_file removes the partial file and fails when the download fails

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

AWS_SCHEMASPY="$(bats_workspace_root)/scripts/db/aws_schemaspy.sh"
INSTALL_SCHEMASPY="$(bats_workspace_root)/scripts/db/install_schemaspy.sh"

@test "download_file removes the partial file and fails when the download fails" {
    mkdir -p "${BATS_TEST_TMPDIR}/bin"
    cat > "${BATS_TEST_TMPDIR}/bin/curl" << 'EOF'
#!/usr/bin/env bash
out=""
while [[ $# -gt 0 ]]; do
    [[ $1 == -o ]] && out="$2"
    shift
done
echo partial > "$out"
exit 22
EOF
    chmod +x "${BATS_TEST_TMPDIR}/bin/curl"
    run bash -c "export PATH='${BATS_TEST_TMPDIR}/bin':\$PATH; source '${AWS_SCHEMASPY}'; download_file http://example.invalid/x.jar '${BATS_TEST_TMPDIR}/x.jar'"
    [ "$status" -ne 0 ]
    [ ! -e "${BATS_TEST_TMPDIR}/x.jar" ]
    [ ! -e "${BATS_TEST_TMPDIR}/x.jar.part" ]
}

@test "install_schemaspy.sh and aws_schemaspy.sh agree on the default location" {
    run bash -c "unset SCHEMASPY_CACHE_DIR XDG_CACHE_HOME; export HOME='${BATS_TEST_TMPDIR}/home'; source '${INSTALL_SCHEMASPY}'; echo \"\${INSTALL_DIR}\"; source '${AWS_SCHEMASPY}'; schemaspy_cache_dir"
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "${BATS_TEST_TMPDIR}/home/.cache/schemaspy" ]
    [ "${lines[1]}" = "${lines[0]}" ]
}

@test "SCHEMASPY_CACHE_DIR overrides the default" {
    run bash -c "export SCHEMASPY_CACHE_DIR='${BATS_TEST_TMPDIR}/custom'; source '${AWS_SCHEMASPY}'; schemaspy_cache_dir"
    [ "$status" -eq 0 ]
    [ "$output" = "${BATS_TEST_TMPDIR}/custom" ]
}

@test "the default cache directory is under the user cache, not the repository tree" {
    run bash -c "unset SCHEMASPY_CACHE_DIR XDG_CACHE_HOME; export HOME='${BATS_TEST_TMPDIR}/home'; source '${AWS_SCHEMASPY}'; schemaspy_cache_dir"
    [ "$status" -eq 0 ]
    [ "$output" = "${BATS_TEST_TMPDIR}/home/.cache/schemaspy" ]
    [[ $output != *"$(bats_workspace_root)"* ]]
}

@test "XDG_CACHE_HOME is honored when SCHEMASPY_CACHE_DIR is unset" {
    run bash -c "unset SCHEMASPY_CACHE_DIR; export XDG_CACHE_HOME='${BATS_TEST_TMPDIR}/xdg'; source '${AWS_SCHEMASPY}'; schemaspy_cache_dir"
    [ "$status" -eq 0 ]
    [ "$output" = "${BATS_TEST_TMPDIR}/xdg/schemaspy" ]
}
