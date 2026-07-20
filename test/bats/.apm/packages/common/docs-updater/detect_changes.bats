#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154

# Tests for .apm/packages/common/.apm/skills/docs-updater/scripts/detect_changes.sh

# Use cases:
# - detect_changes range scope lists changed_files for .apm package source edits
# - detect_changes range scope lists changed_files for .github workflow edits
# - detect_changes range scope asserts exact changed_files for github workflow edits
# - detect_changes range scope includes affected docs when workflows change
# - detect_changes range scope skips when only markdown files change
# - detect_changes range scope records scannable path renames in renamed_files
# - detect_changes range scope excludes agent directory renames from renamed_files
# - detect_changes range scope excludes env paths from changed_files
# - detect_changes honors DOCS_UPDATER_DOCS_ROOT and DOCS_UPDATER_SITE_CONFIG
# - detect_changes range scope includes affected docs when markdown is renamed
# - detect_changes range scope records cross-zone renames between agent and scannable paths

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

DETECT_SCRIPT="$(bats_workspace_root)/.apm/packages/common/.apm/skills/docs-updater/scripts/detect_changes.sh"

@test "detect_changes range scope lists changed_files for apm package source edits" {
    git_test_repo_setup
    mkdir -p "${GIT_TEST_REPO}/.apm/packages/common/.apm/skills/foo" "${GIT_TEST_REPO}/docs"
    printf '# Docs\n' > "${GIT_TEST_REPO}/docs/index.md"
    printf '%s\n' '---' 'name: foo' '---' > "${GIT_TEST_REPO}/.apm/packages/common/.apm/skills/foo/SKILL.md"
    git -C "${GIT_TEST_REPO}" add .
    git -C "${GIT_TEST_REPO}" commit -q -m "chore: init"
    local base
    base="$(git -C "${GIT_TEST_REPO}" rev-parse HEAD)"
    printf '\nMore skill content\n' >> "${GIT_TEST_REPO}/.apm/packages/common/.apm/skills/foo/SKILL.md"
    git -C "${GIT_TEST_REPO}" add .apm/packages/common/.apm/skills/foo/SKILL.md
    git -C "${GIT_TEST_REPO}" commit -q -m "skill: update foo"
    git_test_repo_run "bash '${DETECT_SCRIPT}' --scope range --since '${base}'"
    [ "$status" -eq 0 ]
    [[ $output == *'"status": "ok"'* ]]
    [[ $output == *'.apm/packages/common/.apm/skills/foo/SKILL.md'* ]]
}

@test "detect_changes range scope lists changed_files for github workflow edits" {
    git_test_repo_setup
    mkdir -p "${GIT_TEST_REPO}/.github/workflows" "${GIT_TEST_REPO}/docs"
    printf '# Docs\n' > "${GIT_TEST_REPO}/docs/index.md"
    printf 'name: ci\n' > "${GIT_TEST_REPO}/.github/workflows/ci.yaml"
    git -C "${GIT_TEST_REPO}" add .
    git -C "${GIT_TEST_REPO}" commit -q -m "chore: init"
    local base
    base="$(git -C "${GIT_TEST_REPO}" rev-parse HEAD)"
    printf '  concurrency: test\n' >> "${GIT_TEST_REPO}/.github/workflows/ci.yaml"
    git -C "${GIT_TEST_REPO}" add .github/workflows/ci.yaml
    git -C "${GIT_TEST_REPO}" commit -q -m "ci: update workflow"
    git_test_repo_run "bash '${DETECT_SCRIPT}' --scope range --since '${base}'"
    [ "$status" -eq 0 ]
    [[ $output == *'"status": "ok"'* ]]
    [[ $output == *'.github/workflows/ci.yaml'* ]]
}

@test "detect_changes range scope asserts exact changed_files for github workflow edits" {
    git_test_repo_setup
    mkdir -p "${GIT_TEST_REPO}/.github/workflows" "${GIT_TEST_REPO}/docs"
    printf '# Docs\n' > "${GIT_TEST_REPO}/docs/index.md"
    printf 'name: ci\n' > "${GIT_TEST_REPO}/.github/workflows/ci.yaml"
    git -C "${GIT_TEST_REPO}" add .
    git -C "${GIT_TEST_REPO}" commit -q -m "chore: init"
    local base
    base="$(git -C "${GIT_TEST_REPO}" rev-parse HEAD)"
    printf '  concurrency: test\n' >> "${GIT_TEST_REPO}/.github/workflows/ci.yaml"
    git -C "${GIT_TEST_REPO}" add .github/workflows/ci.yaml
    git -C "${GIT_TEST_REPO}" commit -q -m "ci: update workflow"
    git_test_repo_run "bash '${DETECT_SCRIPT}' --scope range --since '${base}'"
    [ "$status" -eq 0 ]
    run jq -e '
        .status == "ok"
        and .skip == false
        and (.changed_files | length) == 1
        and .changed_files[0] == ".github/workflows/ci.yaml"
    ' <<< "${output}"
    [ "$status" -eq 0 ]
}

@test "detect_changes range scope includes affected docs when workflows change" {
    git_test_repo_setup
    mkdir -p "${GIT_TEST_REPO}/.github/workflows" "${GIT_TEST_REPO}/docs"
    printf '# Docs\n' > "${GIT_TEST_REPO}/docs/index.md"
    printf 'name: ci\n' > "${GIT_TEST_REPO}/.github/workflows/ci.yaml"
    git -C "${GIT_TEST_REPO}" add .
    git -C "${GIT_TEST_REPO}" commit -q -m "chore: init"
    local base
    base="$(git -C "${GIT_TEST_REPO}" rev-parse HEAD)"
    printf '  concurrency: test\n' >> "${GIT_TEST_REPO}/.github/workflows/ci.yaml"
    git -C "${GIT_TEST_REPO}" add .github/workflows/ci.yaml
    git -C "${GIT_TEST_REPO}" commit -q -m "ci: update workflow"
    git_test_repo_run "bash '${DETECT_SCRIPT}' --scope range --since '${base}'"
    [ "$status" -eq 0 ]
    [[ $output == *'"skip": false'* ]]
    [[ $output == *'"affected_docs":'* ]]
    [[ $output == *"docs/index.md"* ]]
}

@test "detect_changes range scope excludes agent directory renames from renamed_files" {
    git_test_repo_setup
    mkdir -p "${GIT_TEST_REPO}/.agents/skills/foo" "${GIT_TEST_REPO}/docs"
    printf '# Docs\n' > "${GIT_TEST_REPO}/docs/index.md"
    printf 'skill\n' > "${GIT_TEST_REPO}/.agents/skills/foo/SKILL.md"
    git -C "${GIT_TEST_REPO}" add .
    git -C "${GIT_TEST_REPO}" commit -q -m "chore: init"
    local base
    base="$(git -C "${GIT_TEST_REPO}" rev-parse HEAD)"
    git -C "${GIT_TEST_REPO}" mv .agents/skills/foo/SKILL.md .agents/skills/foo/SKILL2.md
    git -C "${GIT_TEST_REPO}" commit -q -m "chore: rename agent skill"
    git_test_repo_run "bash '${DETECT_SCRIPT}' --scope range --since '${base}'"
    [ "$status" -eq 0 ]
    run jq -e '
        .status == "ok"
        and .skip == true
        and (.renamed_files | length) == 0
    ' <<< "${output}"
    [ "$status" -eq 0 ]
}

@test "detect_changes range scope includes affected docs when markdown is renamed" {
    git_test_repo_setup
    mkdir -p "${GIT_TEST_REPO}/docs"
    printf '# Old\n' > "${GIT_TEST_REPO}/docs/old.md"
    git -C "${GIT_TEST_REPO}" add .
    git -C "${GIT_TEST_REPO}" commit -q -m "chore: init"
    local base
    base="$(git -C "${GIT_TEST_REPO}" rev-parse HEAD)"
    git -C "${GIT_TEST_REPO}" mv docs/old.md docs/new.md
    git -C "${GIT_TEST_REPO}" commit -q -m "docs: rename page"
    git_test_repo_run "bash '${DETECT_SCRIPT}' --scope range --since '${base}'"
    [ "$status" -eq 0 ]
    run jq -e '
        .status == "ok"
        and .skip == false
        and (.renamed_files | length) == 1
        and .renamed_files[0] == "docs/old.md->docs/new.md"
        and (.affected_docs | length) > 0
    ' <<< "${output}"
    [ "$status" -eq 0 ]
}

@test "detect_changes range scope records scannable path renames in renamed_files" {
    git_test_repo_setup
    mkdir -p "${GIT_TEST_REPO}/src" "${GIT_TEST_REPO}/docs"
    printf '# Docs\n' > "${GIT_TEST_REPO}/docs/index.md"
    printf 'package main\n' > "${GIT_TEST_REPO}/src/app.go"
    git -C "${GIT_TEST_REPO}" add .
    git -C "${GIT_TEST_REPO}" commit -q -m "chore: init"
    local base
    base="$(git -C "${GIT_TEST_REPO}" rev-parse HEAD)"
    git -C "${GIT_TEST_REPO}" mv src/app.go src/main.go
    git -C "${GIT_TEST_REPO}" commit -q -m "refactor: rename app"
    git_test_repo_run "bash '${DETECT_SCRIPT}' --scope range --since '${base}'"
    [ "$status" -eq 0 ]
    run jq -e '
        .status == "ok"
        and (.renamed_files | length) == 1
        and .renamed_files[0] == "src/app.go->src/main.go"
    ' <<< "${output}"
    [ "$status" -eq 0 ]
}

@test "detect_changes range scope records cross-zone rename from agent path to scannable markdown" {
    git_test_repo_setup
    mkdir -p "${GIT_TEST_REPO}/.agents/skills/foo" "${GIT_TEST_REPO}/docs"
    printf '# Docs\n' > "${GIT_TEST_REPO}/docs/index.md"
    printf 'skill\n' > "${GIT_TEST_REPO}/.agents/skills/foo/SKILL.md"
    git -C "${GIT_TEST_REPO}" add .
    git -C "${GIT_TEST_REPO}" commit -q -m "chore: init"
    local base
    base="$(git -C "${GIT_TEST_REPO}" rev-parse HEAD)"
    git -C "${GIT_TEST_REPO}" mv .agents/skills/foo/SKILL.md docs/from-agent.md
    git -C "${GIT_TEST_REPO}" commit -q -m "docs: move skill to docs"
    git_test_repo_run "bash '${DETECT_SCRIPT}' --scope range --since '${base}'"
    [ "$status" -eq 0 ]
    run jq -e '
        .status == "ok"
        and .skip == false
        and (.renamed_files | length) == 1
        and .renamed_files[0] == ".agents/skills/foo/SKILL.md->docs/from-agent.md"
        and (.changed_files | index("docs/from-agent.md")) != null
        and (.affected_docs | length) > 0
    ' <<< "${output}"
    [ "$status" -eq 0 ]
}

@test "detect_changes range scope records cross-zone rename from scannable markdown to agent path" {
    git_test_repo_setup
    mkdir -p "${GIT_TEST_REPO}/.agents/skills/foo" "${GIT_TEST_REPO}/docs"
    printf '# Docs\n' > "${GIT_TEST_REPO}/docs/index.md"
    printf '# Old\n' > "${GIT_TEST_REPO}/docs/old.md"
    git -C "${GIT_TEST_REPO}" add .
    git -C "${GIT_TEST_REPO}" commit -q -m "chore: init"
    local base
    base="$(git -C "${GIT_TEST_REPO}" rev-parse HEAD)"
    git -C "${GIT_TEST_REPO}" mv docs/old.md .agents/skills/foo/SKILL.md
    git -C "${GIT_TEST_REPO}" commit -q -m "chore: move doc to agent"
    git_test_repo_run "bash '${DETECT_SCRIPT}' --scope range --since '${base}'"
    [ "$status" -eq 0 ]
    run jq -e '
        .status == "ok"
        and .skip == false
        and (.renamed_files | length) == 1
        and .renamed_files[0] == "docs/old.md->.agents/skills/foo/SKILL.md"
        and (.deleted_files | index("docs/old.md")) != null
        and (.affected_docs | length) > 0
    ' <<< "${output}"
    [ "$status" -eq 0 ]
}

@test "detect_changes range scope excludes env paths from changed_files" {
    git_test_repo_setup
    mkdir -p "${GIT_TEST_REPO}/.env/common" "${GIT_TEST_REPO}/docs"
    printf '# Docs\n' > "${GIT_TEST_REPO}/docs/index.md"
    printf 'local-only\n' > "${GIT_TEST_REPO}/.env/common/local.env"
    git -C "${GIT_TEST_REPO}" add docs/index.md
    git -C "${GIT_TEST_REPO}" commit -q -m "chore: init"
    local base
    base="$(git -C "${GIT_TEST_REPO}" rev-parse HEAD)"
    printf 'updated\n' > "${GIT_TEST_REPO}/.env/common/local.env"
    git -C "${GIT_TEST_REPO}" add -f .env/common/local.env
    git -C "${GIT_TEST_REPO}" commit -q -m "chore: touch env"
    git_test_repo_run "bash '${DETECT_SCRIPT}' --scope range --since '${base}'"
    [ "$status" -eq 0 ]
    run jq -e '
        .status == "ok"
        and (.changed_files | index(".env/common/local.env")) == null
    ' <<< "${output}"
    [ "$status" -eq 0 ]
}

@test "detect_changes honors DOCS_UPDATER_DOCS_ROOT and DOCS_UPDATER_SITE_CONFIG" {
    git_test_repo_setup
    mkdir -p "${GIT_TEST_REPO}/guides" "${GIT_TEST_REPO}/src"
    printf '# Guide\n' > "${GIT_TEST_REPO}/guides/index.md"
    printf 'package main\n' > "${GIT_TEST_REPO}/src/app.go"
    printf 'site_name: Test\n' > "${GIT_TEST_REPO}/site.yml"
    git -C "${GIT_TEST_REPO}" add .
    git -C "${GIT_TEST_REPO}" commit -q -m "chore: init"
    local base
    base="$(git -C "${GIT_TEST_REPO}" rev-parse HEAD)"
    printf '\n' >> "${GIT_TEST_REPO}/src/app.go"
    git -C "${GIT_TEST_REPO}" add src/app.go
    git -C "${GIT_TEST_REPO}" commit -q -m "feat: update app"
    git_test_repo_run "env DOCS_UPDATER_DOCS_ROOT='guides' DOCS_UPDATER_SITE_CONFIG='site.yml' bash '${DETECT_SCRIPT}' --scope range --since '${base}'"
    [ "$status" -eq 0 ]
    run jq -e '
        .status == "ok"
        and .skip == false
        and (.affected_docs | index("guides/index.md")) != null
        and (.affected_docs | index("site.yml")) != null
        and (.affected_docs | index("docs/index.md")) == null
    ' <<< "${output}"
    [ "$status" -eq 0 ]
}

@test "detect_changes range scope skips when only markdown files change" {
    git_test_repo_setup
    mkdir -p "${GIT_TEST_REPO}/docs"
    printf '# Docs\n' > "${GIT_TEST_REPO}/docs/index.md"
    git -C "${GIT_TEST_REPO}" add .
    git -C "${GIT_TEST_REPO}" commit -q -m "chore: init"
    local base
    base="$(git -C "${GIT_TEST_REPO}" rev-parse HEAD)"
    printf '\nMore docs\n' >> "${GIT_TEST_REPO}/docs/index.md"
    git -C "${GIT_TEST_REPO}" add docs/index.md
    git -C "${GIT_TEST_REPO}" commit -q -m "docs: expand index"
    git_test_repo_run "bash '${DETECT_SCRIPT}' --scope range --since '${base}'"
    [ "$status" -eq 0 ]
    [[ $output == *'"skip": true'* ]]
    [[ $output == *'"affected_docs": []'* ]]
}
