# Loop `test-gap` 実装計画

> **実行者向け:** REQUIRED SUB-SKILL: `superpowers:subagent-driven-development`(推奨)または `superpowers:executing-plans` で、タスクごとに実装する。各ステップはチェックボックス(`- [ ]`)で進捗を管理する。

**Goal:** テスト不足を埋めるテスト追加 PR を、週 1 回(月曜 10:00 UTC)と手動実行で出す改善ループ `test-gap` を追加する。

**Architecture:** 言語非依存の薄い detect script(`skip:false`、churn、台帳の要約)が事実だけを返し、エージェント(Maker)がスタックの特定、対象の選定、テスト作成を行う。Checker(`loop-verifier` + caller の rubric)は実行を伴わない静的基準で判定し、緑かどうかは PR 後の CI に任せる。処理済み対象は別ファイル `.loop/state-test-gap-ledger.json` に、`domain_persistence_script` で記録する(`ci-sweeper` と同じ型)。共通コード(`loop-detect` / `loop-execute` / `loop-finalize`)は変更しない。

**Tech Stack:** bash、jq、git、Bats、GitHub Actions(reusable `ci-loop-caller.yaml`)、APM package(`repo-maintenance`)

**Spec:** [Loop `test-gap` 設計: テスト不足を埋める改善ループ](../specs/2026-10-11-loop-test-gap-design.md)。本計画は spec を実装する。実行者は両方を読む。

## Global Constraints

spec と既存規約から、全タスクに暗黙で適用される要件。

- **編集場所:** skill は `.apm/packages/repo-maintenance/.apm/skills/test-gap/` だけを編集する。`.agents/`、`.claude/`、`.codex/`、`.cursor/`、`.kiro/`、`.vscode/`、`apm_modules/` は `apm install` による同期先で、手編集しない(CLAUDE.md の Edit routing)。
- **共通コードは変更しない:** `.github/actions/loop-detect`、`loop-execute`、`loop-finalize`、`.github/workflows/ci-loop-*.yaml` は変更対象外。
- **`scripts/lib/` の同期:** skill の `scripts/lib/` は `scripts/lib/` の同期先。`bash scripts/self/apm/sync_skill_lib.sh` で作る(手編集しない)。
- **Test-first:** コード変更には、同じタスクで Bats を追加する(AGENTS.md、TEST-00)。Bats は `test/bats/.apm/packages/repo-maintenance/test-gap/` に置く(既存の `tech-debt/`、`ci-sweeper/` に倣う)。
- **ORD-01:** workflow、`with:`、`env`、`permissions` のキーはアルファベット順。
- **シェル規約:** `.claude/rules/shell-script.md`(ヘッダ、`set -euo pipefail`、`umask 027`、`LC_ALL=C.UTF-8`、関数は a-z 順で `main` が最後、関数ごとに Globals / Arguments / Outputs / Returns)に従う。
- **Bats 規約:** `.claude/rules/bats.md`(ヘッダの `# Tests for` と `# Use cases:`、`@test` は a-z 順)に従う。
- **ドキュメント:** `docs/` は kebab-case、リンクは相対 `.md` でリンクテキストは対象文書のタイトル(DOC-05)。`docs/` を追加・変更したら、`mkdocs.yml` の `nav` を同期する。
- **`.github/workflows/CLAUDE.md`:** `on-*` caller は `./.github/workflows/ci-loop-caller.yaml` を `uses:` で呼べる(dogfood)。第三者 action は SHA 固定。
- **allowlist:** caller は `test/**`。denylist は省略(プラットフォーム既定)。
- **スケジュール:** `cron: "0 10 * * 1"`、`timezone: Etc/UTC`、`workflow_dispatch: {}`。
- **モデル・上限:** `tech-debt` と同じ(maker `claude-sonnet-5`、checker `claude-opus-5`、`agent_loop_max_attempts: 3`、turns 100、`budget_max_runs_per_day: 2`、`budget_max_tokens_per_day: 1000000`)。
- **`pr_include_bots`:** `on-loop-ci-sweeper.yaml` は変更しない(spec の方針 B)。
- **コミット:** 日本語または英語の conventional commit。末尾に `Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>` を付ける。ユーザーが明示的に依頼するまでコミットしない場合は、各タスクの「Commit」ステップをユーザーの指示に従って実行する。

## Review Focus

spec が暗黙に求めるが、どのタスクのテストも直接は検証しない可能性が高い入力や失敗モード。それぞれ、担当タスクにテストを足す。

1. **台帳ファイルが壊れている、または存在しない** — detect は失敗せず、空の台帳として扱う(Task 2)。台帳更新は exit 0 で警告のみ(Task 3)。
2. **git 履歴が浅い、または `since` が無効な ref** — detect は失敗せず、`hotspots` を空にして `skip:false` を返す(Task 2)。
3. **`TARGET_JSON` や `OUTCOME` が未設定、または `error` / `escalated`** — 台帳更新はスキップして exit 0(Task 3)。
4. **同じファイルを複数回処理** — 台帳は重複を持たず、`attempts` を増やし `processed_at` を更新する(Task 3)。
5. **保持期間を過ぎた台帳の項目** — prune され、detect の `processed[]` にも出ない(Task 2、3)。
6. **`.loop` 以外のパスを `TEST_GAP_LEDGER_FILE` に指定、または絶対パス、`..` を含むパス** — 拒否して exit 0(Task 3)。
7. **テストファイルが 1 つも変更されていない実行(`no_changes`)** — 台帳に追記しない(Task 3)。

---

## File Structure

| パス                                                                                                                                                                                                            | 種別 | 責務                                                                                                      |
| --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---- | --------------------------------------------------------------------------------------------------------- |
| `.apm/packages/repo-maintenance/.apm/skills/test-gap/SKILL.md`                                                                                                                                                  | 新規 | entry skill。Interactive は survey が既定、Automation は `## Constraints` に従う                          |
| `.apm/packages/repo-maintenance/.apm/skills/test-gap/scripts/detect_test_gap.sh`                                                                                                                                | 新規 | 薄い detect。`skip:false`、`hotspots[]`(churn)、`ledger`(処理済み対象の要約)、`warnings[]` を JSON で返す |
| `.apm/packages/repo-maintenance/.apm/skills/test-gap/scripts/update_test_gap_ledger.sh`                                                                                                                         | 新規 | finalize 後に `git diff` で変更テストを台帳へ記録する(`domain_persistence_script`)                        |
| `.apm/packages/repo-maintenance/.apm/skills/test-gap/scripts/lib/`                                                                                                                                              | 同期 | `scripts/lib/` の同期先(`sync_skill_lib.sh` で生成)                                                       |
| `.apm/packages/repo-maintenance/.apm/skills/test-gap/references/*.md`                                                                                                                                           | 新規 | 入力スキーマ、automation envelope、出力形式、PR 本文リンク、チェックリスト                                |
| `.apm/packages/repo-maintenance/.apm/skills/test-gap/assets/pr-body-template*.md`                                                                                                                               | 新規 | PR 本文テンプレート(apply / survey)                                                                       |
| `.apm/packages/repo-maintenance/.apm/skills/test-gap/eval.yaml`、`evals/tasks/basic.yaml`                                                                                                                       | 新規 | waza 評価                                                                                                 |
| `.github/workflows/on-loop-test-gap.yaml`                                                                                                                                                                       | 新規 | caller(schedule + dispatch)                                                                               |
| `scripts/self/apm/check_apm_skill_install_drift.sh`                                                                                                                                                             | 変更 | `LOOP_SKILLS` に `test-gap` を追加                                                                        |
| `scripts/self/apm/check_loop_pr_body_contract.sh`                                                                                                                                                               | 変更 | `LOOP_SKILLS` と `LOOP_PR_BODY_LINKS_SKILLS` に `test-gap` を追加                                         |
| `test/bats/.apm/packages/repo-maintenance/test-gap/detect_test_gap.bats`、`update_test_gap_ledger.bats`                                                                                                         | 新規 | 上記 2 スクリプトのテスト                                                                                 |
| `docs/explanation/loop-engineering/workflows/loop-test-gap-workflow-design.md`                                                                                                                                  | 新規 | caller の入力と動作の設計書                                                                               |
| `docs/explanation/loop-engineering/loop-capable-skills.md`、`docs/reference/specification.md`、`docs/explanation/architecture.md`、`docs/explanation/loop-engineering/loop-engineering-design.md`、`mkdocs.yml` | 変更 | 一覧表、ステータス、nav                                                                                   |

**注意:** 変更後に `apm install` で `.agents/` と `.claude/` に同期する(Task 8)。同期先もコミットする(CLAUDE.md)。

---

## Task 1: 台帳更新スクリプトの Bats を先に書く(テストファースト)

台帳の形式をテストで固定する。実装は Task 3。

**Files:**

- Create: `test/bats/.apm/packages/repo-maintenance/test-gap/update_test_gap_ledger.bats`

**Interfaces:**

- Consumes: `apm_skill_script_path <skill> <script>`、`git_test_repo_setup`、`git_test_repo_git`、`git_test_repo_run`(`test/bats/support/common.bash`)
- Produces: 台帳 JSON の形式(Task 2、3 が依拠する)

```json
{
  "entries": {
    "test/bats/foo/bar.bats": {
      "attempts": 1,
      "last_loop_run_id": "123",
      "outcome": "pr-created",
      "processed_at": "2026-10-11T10:00:00Z"
    }
  }
}
```

- `entries` のキーは、変更されたテストファイルのリポジトリ相対パス。
- `outcome` は `pr-created` / `rejected` / `no-action`。`no-action` と、変更ファイルが 0 件の実行は追記しない。
- `TEST_GAP_RETENTION_DAYS`(既定 `30`)を過ぎた `processed_at` の項目は prune する。

- [ ] **Step 1: Bats を書く**

`test/bats/.apm/packages/repo-maintenance/test-gap/update_test_gap_ledger.bats`:

```bash
#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154

# Tests for .apm/packages/repo-maintenance/.apm/skills/test-gap/scripts/update_test_gap_ledger.sh
#
# Use cases:
# - update_test_gap_ledger records changed test files from the execute branch diff
# - update_test_gap_ledger increments attempts for an already recorded file
# - update_test_gap_ledger skips when outcome is no-action
# - update_test_gap_ledger skips when outcome is error
# - update_test_gap_ledger exits 0 and leaves the ledger unchanged when no files changed
# - update_test_gap_ledger recovers from a corrupt ledger file
# - update_test_gap_ledger creates the ledger file when it does not exist
# - update_test_gap_ledger prunes entries older than the retention window
# - update_test_gap_ledger preserves unrelated entries
# - update_test_gap_ledger rejects absolute and parent-relative ledger paths
# - update_test_gap_ledger maps VERDICT to outcome when OUTCOME is unset
# - update_test_gap_ledger exits 0 when the execute branch is not resolvable

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

LEDGER_SCRIPT="$(apm_skill_script_path test-gap update_test_gap_ledger.sh)"

# make_repo_with_test_change: base commit on main, one test file added on branch feature
make_repo_with_test_change() {
    git_test_repo_setup
    mkdir -p "${GIT_TEST_REPO}/test/bats" "${GIT_TEST_REPO}/.loop"
    printf 'base\n' > "${GIT_TEST_REPO}/README.md"
    git_test_repo_git add .
    git_test_repo_git commit -q -m "chore: init"
    git_test_repo_git branch -M main
    git_test_repo_git checkout -q -b feature
    printf '#!/usr/bin/env bats\n@test "x" { true; }\n' > "${GIT_TEST_REPO}/test/bats/foo.bats"
    git_test_repo_git add .
    git_test_repo_git commit -q -m "test: add foo"
    git_test_repo_git checkout -q main
}

@test "update_test_gap_ledger records changed test files from the execute branch diff" {
    make_repo_with_test_change
    git_test_repo_run "env OUTCOME=pr-created EXECUTE_BRANCH=feature TEST_GAP_BASE_BRANCH=main GITHUB_RUN_ID=111 bash '${LEDGER_SCRIPT}'"
    [ "$status" -eq 0 ]
    run jq -e '.entries["test/bats/foo.bats"].attempts == 1 and .entries["test/bats/foo.bats"].outcome == "pr-created" and .entries["test/bats/foo.bats"].last_loop_run_id == "111"' "${GIT_TEST_REPO}/.loop/state-test-gap-ledger.json"
    [ "$status" -eq 0 ]
}

@test "update_test_gap_ledger increments attempts for an already recorded file" {
    make_repo_with_test_change
    printf '%s' '{"entries":{"test/bats/foo.bats":{"attempts":1,"last_loop_run_id":"100","outcome":"rejected","processed_at":"2999-01-01T00:00:00Z"}}}' > "${GIT_TEST_REPO}/.loop/state-test-gap-ledger.json"
    git_test_repo_run "env OUTCOME=rejected EXECUTE_BRANCH=feature TEST_GAP_BASE_BRANCH=main GITHUB_RUN_ID=222 bash '${LEDGER_SCRIPT}'"
    [ "$status" -eq 0 ]
    run jq -e '.entries["test/bats/foo.bats"].attempts == 2 and .entries["test/bats/foo.bats"].last_loop_run_id == "222"' "${GIT_TEST_REPO}/.loop/state-test-gap-ledger.json"
    [ "$status" -eq 0 ]
}

@test "update_test_gap_ledger skips when outcome is no-action" {
    make_repo_with_test_change
    git_test_repo_run "env OUTCOME=no-action EXECUTE_BRANCH=feature TEST_GAP_BASE_BRANCH=main bash '${LEDGER_SCRIPT}'"
    [ "$status" -eq 0 ]
    [ ! -f "${GIT_TEST_REPO}/.loop/state-test-gap-ledger.json" ]
}

@test "update_test_gap_ledger skips when outcome is error" {
    make_repo_with_test_change
    git_test_repo_run "env OUTCOME=error EXECUTE_BRANCH=feature TEST_GAP_BASE_BRANCH=main bash '${LEDGER_SCRIPT}'"
    [ "$status" -eq 0 ]
    [ ! -f "${GIT_TEST_REPO}/.loop/state-test-gap-ledger.json" ]
}

@test "update_test_gap_ledger exits 0 and leaves the ledger unchanged when no files changed" {
    git_test_repo_setup
    mkdir -p "${GIT_TEST_REPO}/.loop"
    printf 'base\n' > "${GIT_TEST_REPO}/README.md"
    git_test_repo_git add .
    git_test_repo_git commit -q -m "chore: init"
    git_test_repo_git branch -M main
    git_test_repo_git branch feature
    git_test_repo_run "env OUTCOME=pr-created EXECUTE_BRANCH=feature TEST_GAP_BASE_BRANCH=main bash '${LEDGER_SCRIPT}'"
    [ "$status" -eq 0 ]
    [ ! -f "${GIT_TEST_REPO}/.loop/state-test-gap-ledger.json" ]
}

@test "update_test_gap_ledger recovers from a corrupt ledger file" {
    make_repo_with_test_change
    printf '%s' 'not json' > "${GIT_TEST_REPO}/.loop/state-test-gap-ledger.json"
    git_test_repo_run "env OUTCOME=pr-created EXECUTE_BRANCH=feature TEST_GAP_BASE_BRANCH=main bash '${LEDGER_SCRIPT}'"
    [ "$status" -eq 0 ]
    run jq -e '.entries["test/bats/foo.bats"].attempts == 1' "${GIT_TEST_REPO}/.loop/state-test-gap-ledger.json"
    [ "$status" -eq 0 ]
}

@test "update_test_gap_ledger creates the ledger file when it does not exist" {
    make_repo_with_test_change
    rm -f "${GIT_TEST_REPO}/.loop/state-test-gap-ledger.json"
    git_test_repo_run "env OUTCOME=pr-created EXECUTE_BRANCH=feature TEST_GAP_BASE_BRANCH=main bash '${LEDGER_SCRIPT}'"
    [ "$status" -eq 0 ]
    [ -f "${GIT_TEST_REPO}/.loop/state-test-gap-ledger.json" ]
}

@test "update_test_gap_ledger prunes entries older than the retention window" {
    make_repo_with_test_change
    printf '%s' '{"entries":{"test/bats/old.bats":{"attempts":1,"last_loop_run_id":"1","outcome":"pr-created","processed_at":"2000-01-01T00:00:00Z"}}}' > "${GIT_TEST_REPO}/.loop/state-test-gap-ledger.json"
    git_test_repo_run "env OUTCOME=pr-created EXECUTE_BRANCH=feature TEST_GAP_BASE_BRANCH=main TEST_GAP_RETENTION_DAYS=30 bash '${LEDGER_SCRIPT}'"
    [ "$status" -eq 0 ]
    run jq -e '(.entries | has("test/bats/old.bats") | not) and (.entries | has("test/bats/foo.bats"))' "${GIT_TEST_REPO}/.loop/state-test-gap-ledger.json"
    [ "$status" -eq 0 ]
}

@test "update_test_gap_ledger preserves unrelated entries" {
    make_repo_with_test_change
    printf '%s' '{"entries":{"test/bats/other.bats":{"attempts":3,"last_loop_run_id":"9","outcome":"pr-created","processed_at":"2999-01-01T00:00:00Z"}}}' > "${GIT_TEST_REPO}/.loop/state-test-gap-ledger.json"
    git_test_repo_run "env OUTCOME=pr-created EXECUTE_BRANCH=feature TEST_GAP_BASE_BRANCH=main bash '${LEDGER_SCRIPT}'"
    [ "$status" -eq 0 ]
    run jq -e '.entries["test/bats/other.bats"].attempts == 3 and (.entries | has("test/bats/foo.bats"))' "${GIT_TEST_REPO}/.loop/state-test-gap-ledger.json"
    [ "$status" -eq 0 ]
}

@test "update_test_gap_ledger rejects absolute and parent-relative ledger paths" {
    make_repo_with_test_change
    git_test_repo_run "env OUTCOME=pr-created EXECUTE_BRANCH=feature TEST_GAP_BASE_BRANCH=main TEST_GAP_LEDGER_FILE=/tmp/escape.json bash '${LEDGER_SCRIPT}'"
    [ "$status" -eq 0 ]
    [ ! -f /tmp/escape.json ]
    git_test_repo_run "env OUTCOME=pr-created EXECUTE_BRANCH=feature TEST_GAP_BASE_BRANCH=main TEST_GAP_LEDGER_FILE=../escape.json bash '${LEDGER_SCRIPT}'"
    [ "$status" -eq 0 ]
    [ ! -f "${GIT_TEST_REPO}/../escape.json" ]
}

@test "update_test_gap_ledger maps VERDICT to outcome when OUTCOME is unset" {
    make_repo_with_test_change
    git_test_repo_run "env VERDICT=REJECT EXECUTE_BRANCH=feature TEST_GAP_BASE_BRANCH=main bash '${LEDGER_SCRIPT}'"
    [ "$status" -eq 0 ]
    run jq -e '.entries["test/bats/foo.bats"].outcome == "rejected"' "${GIT_TEST_REPO}/.loop/state-test-gap-ledger.json"
    [ "$status" -eq 0 ]
}

@test "update_test_gap_ledger exits 0 when the execute branch is not resolvable" {
    make_repo_with_test_change
    git_test_repo_run "env OUTCOME=pr-created EXECUTE_BRANCH=does-not-exist TEST_GAP_BASE_BRANCH=main bash '${LEDGER_SCRIPT}'"
    [ "$status" -eq 0 ]
    [ ! -f "${GIT_TEST_REPO}/.loop/state-test-gap-ledger.json" ]
}
```

- [ ] **Step 2: テストが失敗することを確認する**

Run: `bats test/bats/.apm/packages/repo-maintenance/test-gap/update_test_gap_ledger.bats`
Expected: 全件 FAIL(スクリプトが無いため `apm_skill_script_path` が解決できない、またはファイルが無い)。

- [ ] **Step 3: Commit(ユーザーの指示がある場合のみ)**

```bash
git add test/bats/.apm/packages/repo-maintenance/test-gap/update_test_gap_ledger.bats
git commit -m "test(test-gap): add ledger update contract tests"
```

---

## Task 2: detect script の Bats と実装

`detect_test_gap.sh` は、言語を判定せず、`skip:false`、`hotspots[]`、`ledger`、`warnings[]` を返す。

**Files:**

- Create: `test/bats/.apm/packages/repo-maintenance/test-gap/detect_test_gap.bats`
- Create: `.apm/packages/repo-maintenance/.apm/skills/test-gap/scripts/detect_test_gap.sh`
- Sync: `.apm/packages/repo-maintenance/.apm/skills/test-gap/scripts/lib/`

**Interfaces:**

- Consumes: Task 1 の台帳 JSON 形式、`scripts/lib/all.sh` の `json_object`、`json_array`、`json_string_array`、`json_number`、`json_emit_minimal_error`、`repo_path_should_skip`(`scripts/lib/repo_paths.sh`)
- Produces: stdout の JSON

```json
{
  "status": "ok",
  "scope": "range",
  "since": "<ref>",
  "commit_range": "<ref>..HEAD",
  "skip": false,
  "hotspots": [{ "path": "...", "kind": "churn", "count": 7, "window": "90.days" }],
  "ledger": { "file": ".loop/state-test-gap-ledger.json", "processed": [{ "path": "...", "attempts": 1, "outcome": "pr-created", "processed_at": "..." }] },
  "warnings": []
}
```

- CLI: `--scope staged|all|range`(既定 `all`)、`--since <ref>`。`range` は `--since` 必須(`loop-detect` は常に `--scope range --since <last_sha>` で呼ぶ)。
- 環境変数: `TEST_GAP_LEDGER_FILE`(既定 `.loop/state-test-gap-ledger.json`)、`TEST_GAP_CHURN_WINDOW`(既定 `90.days`)、`TEST_GAP_CHURN_MIN`(既定 `3`)、`TEST_GAP_CHURN_TOP`(既定 `20`)、`TEST_GAP_RETENTION_DAYS`(既定 `30`)。
- `skip` は常に `false`(spec: 薄い detect)。`staged` スコープも `skip:false`。
- 失敗時: `{"status":"error",...}` を出力して exit 1(`json_emit_minimal_error`)。

- [ ] **Step 1: Bats を書く**

`test/bats/.apm/packages/repo-maintenance/test-gap/detect_test_gap.bats`:

```bash
#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034,SC2154

# Tests for .apm/packages/repo-maintenance/.apm/skills/test-gap/scripts/detect_test_gap.sh
#
# Use cases:
# - detect_test_gap defaults to scope all and returns skip false on an empty repo
# - detect_test_gap rejects unknown --scope
# - detect_test_gap range without --since returns error JSON exit 1
# - detect_test_gap accepts --scope range with --since and echoes since and commit_range
# - detect_test_gap never returns skip true
# - detect_test_gap emits churn hotspots for frequently edited files
# - detect_test_gap excludes skipped paths from hotspots
# - detect_test_gap honors TEST_GAP_CHURN_MIN and TEST_GAP_CHURN_TOP
# - detect_test_gap reports processed ledger entries within the retention window
# - detect_test_gap omits ledger entries older than the retention window
# - detect_test_gap treats a missing ledger file as empty
# - detect_test_gap warns and continues on a corrupt ledger file
# - detect_test_gap warns and returns empty hotspots when since is not a valid ref
# - detect_test_gap emits error JSON outside a git repository
# - detect_test_gap output is accepted by loop-detect helper functions

_bats_support="$(dirname "${BATS_TEST_FILENAME}")"
while [[ ! -f "${_bats_support}/support/common.bash" ]]; do
    _bats_support="$(dirname "${_bats_support}")"
done
# shellcheck disable=SC1091
source "${_bats_support}/support/common.bash"

DETECT_SCRIPT="$(apm_skill_script_path test-gap detect_test_gap.sh)"

# make_churn_repo <file> <commits>: repository where <file> is touched <commits> times
make_churn_repo() {
    local file="$1" commits="$2" i
    git_test_repo_setup
    mkdir -p "${GIT_TEST_REPO}/$(dirname "${file}")"
    for ((i = 1; i <= commits; i++)); do
        printf 'v%s\n' "${i}" > "${GIT_TEST_REPO}/${file}"
        git_test_repo_git add .
        git_test_repo_git commit -q -m "chore: edit ${i}"
    done
}

@test "detect_test_gap defaults to scope all and returns skip false on an empty repo" {
    git_test_repo_setup
    printf 'x\n' > "${GIT_TEST_REPO}/a.txt"
    git_test_repo_git add .
    git_test_repo_git commit -q -m "chore: init"
    git_test_repo_run "bash '${DETECT_SCRIPT}'"
    [ "$status" -eq 0 ]
    run jq -e '.status == "ok" and .scope == "all" and .skip == false and (.hotspots | length) == 0 and (.warnings | type) == "array"' <<< "${output}"
    [ "$status" -eq 0 ]
}

@test "detect_test_gap rejects unknown --scope" {
    git_test_repo_setup
    git_test_repo_run "bash '${DETECT_SCRIPT}' --scope bogus"
    [ "$status" -eq 1 ]
    run jq -e '.status == "error"' <<< "${output}"
    [ "$status" -eq 0 ]
}

@test "detect_test_gap range without --since returns error JSON exit 1" {
    git_test_repo_setup
    git_test_repo_run "bash '${DETECT_SCRIPT}' --scope range"
    [ "$status" -eq 1 ]
    run jq -e '.status == "error"' <<< "${output}"
    [ "$status" -eq 0 ]
}

@test "detect_test_gap accepts --scope range with --since and echoes since and commit_range" {
    make_churn_repo "src/a.sh" 2
    git_test_repo_run "bash '${DETECT_SCRIPT}' --scope range --since HEAD~1"
    [ "$status" -eq 0 ]
    run jq -e '.scope == "range" and .since == "HEAD~1" and .commit_range == "HEAD~1..HEAD"' <<< "${output}"
    [ "$status" -eq 0 ]
}

@test "detect_test_gap never returns skip true" {
    make_churn_repo "src/a.sh" 1
    git_test_repo_run "bash '${DETECT_SCRIPT}' --scope staged"
    [ "$status" -eq 0 ]
    run jq -e '.skip == false' <<< "${output}"
    [ "$status" -eq 0 ]
}

@test "detect_test_gap emits churn hotspots for frequently edited files" {
    make_churn_repo "src/hot.sh" 4
    git_test_repo_run "env TEST_GAP_CHURN_MIN=3 bash '${DETECT_SCRIPT}'"
    [ "$status" -eq 0 ]
    run jq -e '.hotspots[0].path == "src/hot.sh" and .hotspots[0].kind == "churn" and .hotspots[0].count == 4' <<< "${output}"
    [ "$status" -eq 0 ]
}

@test "detect_test_gap excludes skipped paths from hotspots" {
    make_churn_repo "node_modules/pkg/index.js" 5
    git_test_repo_run "env TEST_GAP_CHURN_MIN=3 bash '${DETECT_SCRIPT}'"
    [ "$status" -eq 0 ]
    run jq -e '(.hotspots | length) == 0' <<< "${output}"
    [ "$status" -eq 0 ]
}

@test "detect_test_gap honors TEST_GAP_CHURN_MIN and TEST_GAP_CHURN_TOP" {
    make_churn_repo "src/a.sh" 4
    printf 'b\n' > "${GIT_TEST_REPO}/src/b.sh"
    git_test_repo_git add .
    git_test_repo_git commit -q -m "chore: b1"
    git_test_repo_run "env TEST_GAP_CHURN_MIN=99 bash '${DETECT_SCRIPT}'"
    [ "$status" -eq 0 ]
    run jq -e '(.hotspots | length) == 0' <<< "${output}"
    [ "$status" -eq 0 ]
    git_test_repo_run "env TEST_GAP_CHURN_MIN=1 TEST_GAP_CHURN_TOP=1 bash '${DETECT_SCRIPT}'"
    [ "$status" -eq 0 ]
    run jq -e '(.hotspots | length) == 1' <<< "${output}"
    [ "$status" -eq 0 ]
}

@test "detect_test_gap reports processed ledger entries within the retention window" {
    make_churn_repo "src/a.sh" 1
    mkdir -p "${GIT_TEST_REPO}/.loop"
    printf '%s' '{"entries":{"test/bats/foo.bats":{"attempts":2,"last_loop_run_id":"7","outcome":"pr-created","processed_at":"2999-01-01T00:00:00Z"}}}' > "${GIT_TEST_REPO}/.loop/state-test-gap-ledger.json"
    git_test_repo_run "bash '${DETECT_SCRIPT}'"
    [ "$status" -eq 0 ]
    run jq -e '.ledger.file == ".loop/state-test-gap-ledger.json" and .ledger.processed[0].path == "test/bats/foo.bats" and .ledger.processed[0].attempts == 2' <<< "${output}"
    [ "$status" -eq 0 ]
}

@test "detect_test_gap omits ledger entries older than the retention window" {
    make_churn_repo "src/a.sh" 1
    mkdir -p "${GIT_TEST_REPO}/.loop"
    printf '%s' '{"entries":{"test/bats/old.bats":{"attempts":1,"last_loop_run_id":"1","outcome":"pr-created","processed_at":"2000-01-01T00:00:00Z"}}}' > "${GIT_TEST_REPO}/.loop/state-test-gap-ledger.json"
    git_test_repo_run "env TEST_GAP_RETENTION_DAYS=30 bash '${DETECT_SCRIPT}'"
    [ "$status" -eq 0 ]
    run jq -e '(.ledger.processed | length) == 0' <<< "${output}"
    [ "$status" -eq 0 ]
}

@test "detect_test_gap treats a missing ledger file as empty" {
    make_churn_repo "src/a.sh" 1
    git_test_repo_run "bash '${DETECT_SCRIPT}'"
    [ "$status" -eq 0 ]
    run jq -e '(.ledger.processed | length) == 0' <<< "${output}"
    [ "$status" -eq 0 ]
}

@test "detect_test_gap warns and continues on a corrupt ledger file" {
    make_churn_repo "src/a.sh" 1
    mkdir -p "${GIT_TEST_REPO}/.loop"
    printf '%s' 'not json' > "${GIT_TEST_REPO}/.loop/state-test-gap-ledger.json"
    git_test_repo_run "bash '${DETECT_SCRIPT}'"
    [ "$status" -eq 0 ]
    run jq -e '(.ledger.processed | length) == 0 and ([.warnings[] | test("ledger")] | any)' <<< "${output}"
    [ "$status" -eq 0 ]
}

@test "detect_test_gap warns and returns empty hotspots when since is not a valid ref" {
    make_churn_repo "src/a.sh" 4
    git_test_repo_run "env TEST_GAP_CHURN_MIN=1 bash '${DETECT_SCRIPT}' --scope range --since no-such-ref"
    [ "$status" -eq 0 ]
    run jq -e '.skip == false and ([.warnings[] | test("since")] | any)' <<< "${output}"
    [ "$status" -eq 0 ]
}

@test "detect_test_gap emits error JSON outside a git repository" {
    local d
    d="$(mktemp -d)"
    run bash -c "cd '${d}' && bash '${DETECT_SCRIPT}'"
    rm -rf "${d}"
    [ "$status" -eq 1 ]
    run jq -e '.status == "error"' <<< "${output}"
    [ "$status" -eq 0 ]
}

@test "detect_test_gap output is accepted by loop-detect helper functions" {
    make_churn_repo "src/a.sh" 1
    git_test_repo_run "bash '${DETECT_SCRIPT}' --scope range --since HEAD"
    [ "$status" -eq 0 ]
    local det="${output}"
    bats_source_rel ".github/actions/loop-detect/lib/detect.sh"
    run detect_result_skip "${det}"
    [ "$status" -eq 1 ]
    run build_verifier_context_from_result "${det}"
    [ "$status" -eq 0 ]
    [ -z "${output}" ]
}
```

- [ ] **Step 2: テストが失敗することを確認する**

Run: `bats test/bats/.apm/packages/repo-maintenance/test-gap/detect_test_gap.bats`
Expected: FAIL(スクリプトが無い)。

- [ ] **Step 3: skill のディレクトリと `scripts/lib` を用意する**

```bash
mkdir -p .apm/packages/repo-maintenance/.apm/skills/test-gap/scripts
bash scripts/self/apm/sync_skill_lib.sh
```

Expected: `.apm/packages/repo-maintenance/.apm/skills/test-gap/scripts/lib/` が作られる(同期対象は `scripts/` を持つ skill)。確認: `ls .apm/packages/repo-maintenance/.apm/skills/test-gap/scripts/lib/all.sh`。

- [ ] **Step 4: detect script を実装する**

`.apm/packages/repo-maintenance/.apm/skills/test-gap/scripts/detect_test_gap.sh`:

```bash
#!/bin/bash
#######################################
# Description: Detect language-agnostic facts for the test-gap automation (thin detect)
#
# Usage: ./detect_test_gap.sh [--scope staged|all|range] [--since <ref>]
#   --scope    Cursor axis (default: all)
#              all: full pass
#              range: requires --since; echoes since/commit_range
#              staged: accepted for CLI parity; same output as all
#   --since    Git ref for range scope (commit SHA from state cursor)
#
# Output:
# - JSON object: status, scope, since, commit_range, skip (always false),
#   hotspots[] (git churn), ledger {file, processed[]}, warnings[]
#
# Design Rules:
# - Emit facts only; never decide that tests are missing (the maker agent selects targets)
# - skip is always false so the schedule always reaches the maker (spec: thin detect)
# - Per-sensor recoverable failures append to warnings[] and continue
# - Fatal errors emit status=error JSON and exit 1
# - Source shared helpers from scripts/lib/all.sh (synced via scripts/self/apm/sync_skill_lib.sh)
#
# Dependencies:
# - bash (POSIX bash, /bin/bash)
# - git
# - jq
#
# Optional environment:
#   TEST_GAP_LEDGER_FILE     Ledger path, repository-relative (default: .loop/state-test-gap-ledger.json)
#   TEST_GAP_CHURN_WINDOW    Git log --since window for churn hotspots (default: 90.days)
#   TEST_GAP_CHURN_MIN       Minimum commit touches per path (default: 3)
#   TEST_GAP_CHURN_TOP       Maximum churn hotspots to emit (default: 20)
#   TEST_GAP_RETENTION_DAYS  Days a ledger entry stays visible (default: 30)
#######################################

# Error handling: exit on error, unset variable, or failed pipeline
set -euo pipefail

# Secure defaults
umask 027
export LC_ALL=C.UTF-8

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load all-in-one library
# shellcheck source=./lib/all.sh
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/all.sh"

#######################################
# Global variables
#######################################
SCOPE="all"
SINCE_REF=""
COMMIT_RANGE=""
LEDGER_FILE=""
LEDGER_PROCESSED_JSON="[]"
declare -a HOTSPOTS_JSON=()
declare -a WARNINGS=()

#######################################
# collect_churn_hotspots: Emit churn hotspots from git log
#
# Globals:
#   HOTSPOTS_JSON - Output array of hotspot objects (appended)
#   WARNINGS - Warning messages (appended)
#   SCOPE, SINCE_REF - Read; range scope limits the log to the since..HEAD range
#
# Arguments:
#   None
#
# Outputs:
#   None
#
# Returns:
#   0 always (failures become warnings)
#
#######################################
function collect_churn_hotspots {
    local window="${TEST_GAP_CHURN_WINDOW:-90.days}"
    local min_count="${TEST_GAP_CHURN_MIN:-3}"
    local top_n="${TEST_GAP_CHURN_TOP:-20}"
    local emitted=0
    local count path log_output
    local -a log_args=(--since="${window}" --name-only --pretty=format:)

    if [[ ${SCOPE} == "range" ]]; then
        if ! git rev-parse --verify --quiet "${SINCE_REF}^{commit}" > /dev/null 2>&1; then
            WARNINGS+=("since ref is not a valid commit: ${SINCE_REF}; churn sensor skipped")
            return 0
        fi
        log_args+=("${SINCE_REF}..HEAD")
    fi

    if ! log_output="$(git log "${log_args[@]}" 2> /dev/null)"; then
        WARNINGS+=("churn sensor skipped: git log failed")
        return 0
    fi
    [[ -z ${log_output} ]] && return 0

    while read -r count path; do
        [[ -z ${path} ]] && continue
        if repo_path_should_skip "${path}"; then
            continue
        fi
        if [[ ${count} -lt ${min_count} ]]; then
            break
        fi
        HOTSPOTS_JSON+=("$(json_object \
            path "${path}" \
            kind "churn" \
            count "$(json_number "${count}")" \
            window "${window}")")
        emitted=$((emitted + 1))
        if [[ ${emitted} -ge ${top_n} ]]; then
            break
        fi
    done < <(
        printf '%s\n' "${log_output}" \
            | grep -v '^[[:space:]]*$' \
            | sort \
            | uniq -c \
            | sort -rn
    )
}

#######################################
# load_ledger_summary: Read recent ledger entries into LEDGER_PROCESSED_JSON
#
# Globals:
#   LEDGER_FILE - Ledger path (repository-relative)
#   LEDGER_PROCESSED_JSON - Set to a JSON array of {path, attempts, outcome, processed_at}
#   WARNINGS - Warning messages (appended)
#
# Arguments:
#   None
#
# Outputs:
#   None
#
# Returns:
#   0 always (a missing file is empty; a corrupt file becomes a warning)
#
#######################################
function load_ledger_summary {
    local retention="${TEST_GAP_RETENTION_DAYS:-30}"
    local cutoff

    LEDGER_PROCESSED_JSON="[]"
    [[ -f ${LEDGER_FILE} ]] || return 0

    if ! jq -e '.entries | type == "object"' "${LEDGER_FILE}" > /dev/null 2>&1; then
        WARNINGS+=("ledger file is not valid JSON or has no entries object: ${LEDGER_FILE}")
        return 0
    fi

    cutoff="$(date -u -d "${retention} days ago" +%Y-%m-%dT%H:%M:%SZ)"
    LEDGER_PROCESSED_JSON="$(jq -c --arg cutoff "${cutoff}" '
        [.entries | to_entries[]
         | select((.value.processed_at // "") >= $cutoff)
         | {path: .key, attempts: (.value.attempts // 0), outcome: (.value.outcome // ""), processed_at: (.value.processed_at // "")}]
        | sort_by(.path)' "${LEDGER_FILE}")"
}

#######################################
# main: Entry point
#
# Globals:
#   SCOPE, SINCE_REF, COMMIT_RANGE, LEDGER_FILE - Set and read
#
# Arguments:
#   $@ - Command line arguments
#
# Outputs:
#   Detect JSON on stdout
#
# Returns:
#   0 on success; 1 on fatal error (error JSON on stdout)
#
#######################################
function main {
    parse_arguments "$@"

    if ! command -v jq > /dev/null 2>&1; then
        json_emit_minimal_error "jq is required"
        exit 1
    fi
    if ! git rev-parse --is-inside-work-tree > /dev/null 2>&1; then
        output_error "Not a git repository"
    fi

    LEDGER_FILE="${TEST_GAP_LEDGER_FILE:-.loop/state-test-gap-ledger.json}"
    [[ ${SCOPE} == "range" ]] && COMMIT_RANGE="${SINCE_REF}..HEAD"

    collect_churn_hotspots
    load_ledger_summary
    output_json
}

#######################################
# output_error: Print structured JSON error and exit 1
#
# Globals:
#   SCOPE, SINCE_REF - Read
#
# Arguments:
#   $1 - Error message
#
# Outputs:
#   Error JSON on stdout
#
# Returns:
#   Exits with code 1
#
#######################################
function output_error {
    json_object \
        status "error" \
        scope "${SCOPE}" \
        since "${SINCE_REF}" \
        skip "true" \
        error "$1"
    exit 1
}

#######################################
# output_json: Print the detect result
#
# Globals:
#   SCOPE, SINCE_REF, COMMIT_RANGE, LEDGER_FILE, LEDGER_PROCESSED_JSON, HOTSPOTS_JSON, WARNINGS - Read
#
# Arguments:
#   None
#
# Outputs:
#   Detect JSON on stdout
#
# Returns:
#   0
#
#######################################
function output_json {
    json_object \
        status "ok" \
        scope "${SCOPE}" \
        since "${SINCE_REF}" \
        commit_range "${COMMIT_RANGE}" \
        skip "false" \
        hotspots "$(json_array "${HOTSPOTS_JSON[@]}")" \
        ledger "$(json_object file "${LEDGER_FILE}" processed "${LEDGER_PROCESSED_JSON}")" \
        warnings "$(json_string_array "${WARNINGS[@]}")"
}

#######################################
# parse_arguments: Parse command line arguments
#
# Globals:
#   SCOPE, SINCE_REF - Set
#
# Arguments:
#   $@ - Command line arguments
#
# Outputs:
#   Calls output_error on invalid input; show_usage on -h/--help
#
# Returns:
#   None
#
#######################################
function parse_arguments {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h | --help)
                show_usage
                ;;
            --scope)
                [[ $# -lt 2 ]] && output_error "--scope requires a value"
                SCOPE="$2"
                shift 2
                ;;
            --since)
                [[ $# -lt 2 ]] && output_error "--since requires a value"
                SINCE_REF="$2"
                shift 2
                ;;
            *)
                output_error "Unknown argument: $1"
                ;;
        esac
    done

    case "${SCOPE}" in
        staged | all | range) ;;
        *) output_error "--scope must be staged, all, or range" ;;
    esac
    if [[ ${SCOPE} == "range" && -z ${SINCE_REF} ]]; then
        output_error "--scope range requires --since <ref>"
    fi
}

#######################################
# show_usage: Display script usage information
#
# Globals:
#   None
#
# Arguments:
#   None
#
# Outputs:
#   Usage text to stdout
#
# Returns:
#   Exits with code 0
#
#######################################
function show_usage {
    cat << 'EOF'
Usage: detect_test_gap.sh [--scope staged|all|range] [--since <ref>]

Description:
    Emit language-agnostic facts (git churn hotspots, processed ledger entries) for the
    test-gap skill. Never decides that tests are missing; skip is always false.

Options:
    --scope    Cursor axis (default: all)
               all: full pass
               range: requires --since
               staged: accepted for CLI parity
    --since    Git ref for range scope

Examples:
    ./detect_test_gap.sh
    ./detect_test_gap.sh --scope range --since abc1234
EOF
    exit 0
}

if [[ ${BASH_SOURCE[0]} == "${0}" ]]; then
    main "$@"
fi
```

注意: 関数は `collect_churn_hotspots`、`load_ledger_summary`、`main`、`output_error`、`output_json`、`parse_arguments`、`show_usage` の順で a-z に近いが、`main` が最後でない。`.claude/rules/shell-script.md` の G-03(`show_usage` → `parse_arguments` → a-z → `main` 最後)に合わせて、実装時に次の順に並べ替える: `show_usage`、`parse_arguments`、`collect_churn_hotspots`、`load_ledger_summary`、`output_error`、`output_json`、`main`。並べ替えても `output_error` は `parse_arguments` から呼ばれるが、bash は呼び出し時に解決するため問題ない。

- [ ] **Step 5: テストが通ることを確認する**

Run: `bats test/bats/.apm/packages/repo-maintenance/test-gap/detect_test_gap.bats`
Expected: 全件 PASS。失敗した場合は、`json_object` の引数形式(`scripts/lib/json.sh` のヘッダ)と `repo_path_should_skip` の挙動を確認して実装を直す(テストを弱めない)。

- [ ] **Step 6: shell の静的チェック**

Run: `shellcheck .apm/packages/repo-maintenance/.apm/skills/test-gap/scripts/detect_test_gap.sh && shfmt -d .apm/packages/repo-maintenance/.apm/skills/test-gap/scripts/detect_test_gap.sh`
Expected: 出力なし。

- [ ] **Step 7: Commit(ユーザーの指示がある場合のみ)**

```bash
git add .apm/packages/repo-maintenance/.apm/skills/test-gap/scripts test/bats/.apm/packages/repo-maintenance/test-gap/detect_test_gap.bats
git commit -m "feat(test-gap): add thin detect script"
```

---

## Task 3: 台帳更新スクリプトの実装

Task 1 の Bats を通す。

**Files:**

- Create: `.apm/packages/repo-maintenance/.apm/skills/test-gap/scripts/update_test_gap_ledger.sh`

**Interfaces:**

- Consumes: finalize が渡す環境変数 `OUTCOME`、`VERDICT`、`EXECUTE_BRANCH`、`TARGET_JSON`、`LOOP_NAME`、`STATE_FILE`、`GITHUB_RUN_ID`(`loop-finalize/action.yml` の Run Domain Persistence ステップ)。`TARGET_JSON.from.ref`(base)は使わず、`TEST_GAP_BASE_BRANCH`(既定 `main`)を base とする。
- Produces: Task 1 の台帳 JSON。`TEST_GAP_LEDGER_FILE`(既定 `.loop/state-test-gap-ledger.json`)。
- 失敗しても常に exit 0(ledger 更新の失敗で finalize を止めない。`update_run_ledger.sh` と同じ方針)。

動作:

1. `OUTCOME` が空なら `VERDICT`(`APPROVE`→`pr-created`、`REJECT`→`rejected`)から決める。`no-changes` は `no-action` に正規化。`pr-created` / `rejected` / `watch` 以外(`no-action`、`error`、`escalated`、未知)はスキップ(exit 0)。
2. `TEST_GAP_LEDGER_FILE` が空、絶対パス、または `..` を含む場合は警告して exit 0。
3. `git diff --name-only "<base>...<EXECUTE_BRANCH>"` で変更ファイルを取る。`EXECUTE_BRANCH` が解決できなければ警告して exit 0。base は `origin/<base>` があれば優先し、なければローカルの `<base>`。
4. 変更ファイルが 0 件なら台帳に触れず exit 0。
5. 台帳を読む(無ければ `{"entries":{}}`、壊れていれば警告して `{"entries":{}}`)。各ファイルについて `attempts` を +1(無ければ 1)、`last_loop_run_id`(`GITHUB_RUN_ID`)、`outcome`、`processed_at`(UTC 現在)を設定する。
6. `TEST_GAP_RETENTION_DAYS`(既定 30)を過ぎた項目を prune する。
7. `mktemp` に書いてから `mv` で置き換える(原子的)。

- [ ] **Step 1: 実装する**

`.apm/packages/repo-maintenance/.apm/skills/test-gap/scripts/update_test_gap_ledger.sh`:

```bash
#!/bin/bash
#######################################
# Description: Record test files changed by a test-gap run into the run ledger
#
# Usage: ./update_test_gap_ledger.sh
#   Intended as caller domain_persistence_script (loop-finalize). Inputs come from the environment.
#
# Output:
# - None on success (ledger file updated in place)
# - Warnings on stderr when prerequisites are missing or inputs are unusable
#
# Design Rules:
# - Always exit 0 so a ledger problem never blocks finalize (same policy as ci-sweeper update_run_ledger.sh)
# - Record only files in git diff <base>...<EXECUTE_BRANCH>; the maker does not have to cooperate
# - Skip no-action, error, escalated, and unknown outcomes
# - Prune entries older than the retention window
# - Write via mktemp + mv; keep unrelated entries intact
# - Source shared helpers from scripts/lib/all.sh (synced via scripts/self/apm/sync_skill_lib.sh)
#
# Dependencies:
# - bash (POSIX bash, /bin/bash)
# - git
# - jq
#
# Optional environment:
#   OUTCOME                  pr-created | rejected | watch | no-action | no-changes | error | escalated
#   VERDICT                  APPROVE | REJECT (used when OUTCOME is unset)
#   EXECUTE_BRANCH           Agent branch holding the test changes (required to record anything)
#   TEST_GAP_BASE_BRANCH     Base branch for the diff (default: main)
#   TEST_GAP_LEDGER_FILE     Ledger path, repository-relative (default: .loop/state-test-gap-ledger.json)
#   TEST_GAP_RETENTION_DAYS  Days an entry is kept (default: 30)
#   GITHUB_RUN_ID            Recorded as last_loop_run_id
#######################################

# Error handling: exit on error, unset variable, or failed pipeline
set -euo pipefail

# Secure defaults
umask 027
export LC_ALL=C.UTF-8

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load all-in-one library
# shellcheck source=./lib/all.sh
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/all.sh"

#######################################
# Global variables
#######################################
OUTCOME="${OUTCOME-}"
LEDGER_FILE="${TEST_GAP_LEDGER_FILE:-.loop/state-test-gap-ledger.json}"
BASE_BRANCH="${TEST_GAP_BASE_BRANCH:-main}"
RETENTION_DAYS="${TEST_GAP_RETENTION_DAYS:-30}"

#######################################
# changed_files: List files changed on the execute branch relative to the base
#
# Globals:
#   BASE_BRANCH, EXECUTE_BRANCH - Read
#
# Arguments:
#   None
#
# Outputs:
#   One repository-relative path per line on stdout
#
# Returns:
#   0 on success; 1 when the branch cannot be resolved or git diff fails
#
#######################################
function changed_files {
    local base="${BASE_BRANCH}"
    local head="${EXECUTE_BRANCH:-}"

    [[ -z ${head} ]] && return 1
    if git rev-parse --verify --quiet "origin/${base}^{commit}" > /dev/null 2>&1; then
        base="origin/${base}"
    fi
    git rev-parse --verify --quiet "${base}^{commit}" > /dev/null 2>&1 || return 1
    if git rev-parse --verify --quiet "origin/${head}^{commit}" > /dev/null 2>&1; then
        head="origin/${head}"
    fi
    git rev-parse --verify --quiet "${head}^{commit}" > /dev/null 2>&1 || return 1
    git diff --name-only "${base}...${head}" 2> /dev/null
}

#######################################
# main: Entry point
#
# Globals:
#   OUTCOME, LEDGER_FILE, RETENTION_DAYS - Read
#
# Arguments:
#   None
#
# Outputs:
#   Warnings on stderr
#
# Returns:
#   0 always
#
#######################################
function main {
    local files now cutoff tmp existing

    if ! command -v jq > /dev/null 2>&1; then
        log "WARN" "jq is required; skipping ledger update"
        return 0
    fi

    resolve_outcome
    if [[ -z ${OUTCOME} ]]; then
        return 0
    fi

    validate_ledger_file "${LEDGER_FILE}" || return 0

    if ! files="$(changed_files)"; then
        log "WARN" "cannot resolve execute branch '${EXECUTE_BRANCH:-}' against '${BASE_BRANCH}'; skipping ledger update"
        return 0
    fi
    if [[ -z ${files} ]]; then
        return 0
    fi

    existing='{"entries":{}}'
    if [[ -f ${LEDGER_FILE} ]]; then
        if jq -e '.entries | type == "object"' "${LEDGER_FILE}" > /dev/null 2>&1; then
            existing="$(cat "${LEDGER_FILE}")"
        else
            log "WARN" "ledger file is corrupt; starting from an empty ledger: ${LEDGER_FILE}"
        fi
    fi

    now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    cutoff="$(date -u -d "${RETENTION_DAYS} days ago" +%Y-%m-%dT%H:%M:%SZ)"
    mkdir -p "$(dirname "${LEDGER_FILE}")"
    tmp="$(mktemp)"
    # shellcheck disable=SC2016  # jq filter; $vars are bound via --arg/--argjson below
    if ! printf '%s\n' "${files}" | jq -R -s -c \
        --argjson ledger "${existing}" \
        --arg now "${now}" \
        --arg cutoff "${cutoff}" \
        --arg outcome "${OUTCOME}" \
        --arg run_id "${GITHUB_RUN_ID:-}" '
        (split("\n") | map(select(length > 0))) as $paths
        | reduce $paths[] as $p ($ledger;
            .entries[$p] = {
              attempts: ((.entries[$p].attempts // 0) + 1),
              last_loop_run_id: $run_id,
              outcome: $outcome,
              processed_at: $now
            })
        | .entries |= with_entries(select((.value.processed_at // "") >= $cutoff))' > "${tmp}"; then
        log "WARN" "ledger update failed; leaving the ledger unchanged"
        rm -f "${tmp}"
        return 0
    fi
    mv "${tmp}" "${LEDGER_FILE}"
}

#######################################
# resolve_outcome: Normalize OUTCOME (empty means skip)
#
# Globals:
#   OUTCOME, VERDICT - Read; OUTCOME is updated in place
#
# Arguments:
#   None
#
# Outputs:
#   Warning on stderr for unknown outcomes
#
# Returns:
#   0
#
#######################################
function resolve_outcome {
    if [[ -z ${OUTCOME} ]]; then
        case "${VERDICT:-}" in
            APPROVE) OUTCOME="pr-created" ;;
            REJECT) OUTCOME="rejected" ;;
        esac
    fi
    case "${OUTCOME}" in
        pr-created | rejected | watch) ;;
        "" | no-action | no-changes | error | escalated)
            OUTCOME=""
            ;;
        *)
            log "WARN" "Unknown ledger outcome '${OUTCOME}'; skipping ledger update"
            OUTCOME=""
            ;;
    esac
}

#######################################
# validate_ledger_file: Reject empty, absolute, and parent-relative ledger paths
#
# Globals:
#   None
#
# Arguments:
#   $1 - Ledger path
#
# Outputs:
#   Warning on stderr when rejected
#
# Returns:
#   0 when usable; 1 when rejected
#
#######################################
function validate_ledger_file {
    local path="$1"
    local repo_root resolved

    if [[ -z ${path} ]]; then
        log "WARN" "TEST_GAP_LEDGER_FILE must not be empty"
        return 1
    fi
    if [[ ${path} == /* ]]; then
        log "WARN" "TEST_GAP_LEDGER_FILE must be a repository-relative path (got: ${path})"
        return 1
    fi
    repo_root="$(git rev-parse --show-toplevel 2> /dev/null || pwd)"
    resolved="$(realpath -m "${repo_root}/${path}")"
    if [[ ${resolved} != "${repo_root}"/* ]]; then
        log "WARN" "TEST_GAP_LEDGER_FILE must stay under the repository root (got: ${path})"
        return 1
    fi
}

if [[ ${BASH_SOURCE[0]} == "${0}" ]]; then
    main "$@"
fi
```

注意: `log` は `scripts/lib/common.sh` の関数。存在しない場合は `update_run_ledger.sh` が使っているものと同じ(`log "WARN" "..."`)なので、`grep -n "^function log" scripts/lib/common.sh` で確認し、無ければ同ファイルの実際の名前に合わせる。

- [ ] **Step 2: テストが通ることを確認する**

Run: `bats test/bats/.apm/packages/repo-maintenance/test-gap/update_test_gap_ledger.bats`
Expected: 全件 PASS。

- [ ] **Step 3: shell の静的チェック**

Run: `shellcheck .apm/packages/repo-maintenance/.apm/skills/test-gap/scripts/update_test_gap_ledger.sh && shfmt -d .apm/packages/repo-maintenance/.apm/skills/test-gap/scripts/update_test_gap_ledger.sh`
Expected: 出力なし。

- [ ] **Step 4: Commit(ユーザーの指示がある場合のみ)**

```bash
git add .apm/packages/repo-maintenance/.apm/skills/test-gap/scripts/update_test_gap_ledger.sh
git commit -m "feat(test-gap): add ledger update script"
```

---

## Task 4: SKILL.md、references、assets

PR 本文契約(`check_loop_pr_body_contract.sh`)が要求するファイルを満たす。契約の必須: `assets/pr-body-template.md`、`assets/pr-body-template-survey.md`、`references/category-automation-envelope.md`、`references/common-output-format.md`、`references/category-pr-body-links.md`(`LOOP_PR_BODY_LINKS_SKILLS` に追加するため)。禁止パターン: `~280`、`one or two sentences`、`1–2 sentences (max`、`1-2 sentences (max`、`](https://github.com/org/repo`。

**Files:**

- Create: `.apm/packages/repo-maintenance/.apm/skills/test-gap/SKILL.md`
- Create: `.apm/packages/repo-maintenance/.apm/skills/test-gap/references/category-automation-envelope.md`
- Create: `.apm/packages/repo-maintenance/.apm/skills/test-gap/references/category-input-schema.md`
- Create: `.apm/packages/repo-maintenance/.apm/skills/test-gap/references/category-pr-body-links.md`
- Create: `.apm/packages/repo-maintenance/.apm/skills/test-gap/references/category-scope.md`
- Create: `.apm/packages/repo-maintenance/.apm/skills/test-gap/references/common-checklist.md`
- Create: `.apm/packages/repo-maintenance/.apm/skills/test-gap/references/common-output-format.md`
- Create: `.apm/packages/repo-maintenance/.apm/skills/test-gap/assets/pr-body-template.md`
- Create: `.apm/packages/repo-maintenance/.apm/skills/test-gap/assets/pr-body-template-survey.md`

**Interfaces:**

- Consumes: Task 2 の detect JSON(`hotspots[]`、`ledger.processed[]`)、`loop-detect` が prompt に付ける `## Constraints`(`may_edit`、`write_target`、`Allowed paths`)
- Produces: Maker の出力契約。PR 本文は `## Overview`、`## Summary`(`### Changes`、`### Deferred`)、`## Verification`。`write_target` は `fix`(テストファイルの編集)。

- [ ] **Step 1: SKILL.md を書く**

frontmatter は既存 skill(`tech-debt/SKILL.md`)に倣う。`description` は `loop-capable-skills.md` の Description contract(何をするか、Interactive の使い方、Automation の使い方、edit gate、workflow 専用に見せない)に従う。

`.apm/packages/repo-maintenance/.apm/skills/test-gap/SKILL.md`:

```markdown
---
name: test-gap
description: >-
  Find under-tested code and add meaningful tests without changing production code or existing assertions.
  Use in conversation when the user asks to find missing tests, add tests for an under-tested script or package, or improve test coverage.
  Also the loop entry skill for scheduled runs when automation supplies detect JSON (hotspots, ledger). Interactive default is survey only;
  edit test files when the user explicitly requests adding tests or automation sets may_edit in Constraints.
license: Apache-2.0
metadata:
  author: y-miyazaki
  version: "1.0.0"
---

**UTILITY SKILL** — add tests for under-tested code; never change production code or weaken existing tests.

## Input

- **Interactive (required):** natural-language request; optional target path. Constraints in `## Constraints` or [category-scope.md](references/category-scope.md).
- **Automation (optional):** detect JSON in the prompt (`hotspots[]`, `ledger.processed[]`) from the skill detect script. Detect never states that tests are missing — you select the target.

## Execution Scope

### USE FOR:

- Survey: pick under-tested targets (see Target selection) and report candidates
- Apply: add new test files or new test cases for one target within the allowlist

### DO NOT USE FOR:

- Editing production code (report a suspected bug in the PR body instead)
- Deleting, skipping, commenting out, or loosening existing tests or assertions
- CI repair (use `ci-sweeper`), structural refactors (use `refactor`), reports (use `tech-debt`)
- Editing caller state or ledger files (the caller owns them)

## Reference Files Guide

- [category-scope.md](references/category-scope.md) (always read)
- [common-checklist.md](references/common-checklist.md) (always read)
- [common-output-format.md](references/common-output-format.md) (always read)
- [category-input-schema.md](references/category-input-schema.md) (read when detect JSON is present)
- [category-automation-envelope.md](references/category-automation-envelope.md) (read on automation path)
- [category-pr-body-links.md](references/category-pr-body-links.md) (read at PR body synthesis)

## Workflow

Resolve `may_edit` first:

| Source                                 | `may_edit`                                                                                           |
| -------------------------------------- | ---------------------------------------------------------------------------------------------------- |
| Interactive — default                  | `false` — survey only                                                                                |
| Interactive — add/write tests language | `true` — examples: テストを追加して, add tests for, write tests                                      |
| Automation — `## Constraints`          | value of `may_edit` in [category-automation-envelope.md](references/category-automation-envelope.md) |

### Target selection

1. Discover the stack and test layout from the repository (existing test directories, CI config, `AGENTS.md`/`CLAUDE.md` rules). Do not assume a language.
2. Candidate sources, in order: files in `hotspots[]` (churn) without a matching test; production files with no paired test (for shell scripts, a missing Bats suite per the repository's TEST rules); public functions with no test.
3. Exclude every path in `ledger.processed[]` unless you can state a new reason (for example the file changed since). A re-selected path needs that reason in the PR body.
4. Choose exactly one target. Prefer the file with the highest churn and the clearest observable behavior.

### Apply

1. Read the target and its callers. Read the nearest existing tests and copy their layout, helpers, and naming.
2. Write tests that assert observable behavior: return values, side effects, error paths. A test that cannot fail is not acceptable.
3. Place files only within `Allowed paths`. Never edit production files.
4. You cannot run the tests in this environment. Do not claim you ran them. State the command CI will run and the expected result in `## Verification`.
5. When `may_edit` is `false`, or `write_target` is not `fix`, emit the survey shape and stop.

### Error Handling

| Condition                                      | Severity    | Action                                             |
| ---------------------------------------------- | ----------- | -------------------------------------------------- |
| Detect `status: "error"`                       | Fatal       | Stop; report the error text                        |
| No under-tested target outside the ledger      | Info        | Report no-op; do not write files                   |
| Target needs production changes to be testable | Recoverable | Choose another target or list it in `### Deferred` |
| Path outside the allowlist                     | Recoverable | List in `### Deferred`; do not edit                |
| Unable to find the repository's test layout    | Recoverable | Survey only; explain what is missing               |

## Output

Follow [common-output-format.md](references/common-output-format.md). Load `assets/pr-body-template.md` (apply) or `assets/pr-body-template-survey.md` (survey) only at synthesis.
```

- [ ] **Step 2: references を書く**

`references/category-scope.md`:

```markdown
# Scope

## Allowed

- New test files and new test cases under the paths in `Allowed paths`.

## Not allowed

- Any file outside `Allowed paths` (production code, workflows, docs, config).
- Deleting, skipping, commenting out, or loosening existing tests or assertions.
- Tests that call real network services, real cloud APIs, or use real credentials.

## Denylist

The automation checker enforces the platform default denylist. Treat denylisted paths as Watch and never edit them.

## Target size

One target per run. A target is one production file (or one public unit inside it) and its paired test file.
```

`references/common-checklist.md`:

```markdown
# Checklist

## Evidence (EVID)

- EVID-01: Cite the production file and the behavior each new test asserts.
- EVID-02: When a path appears in `ledger.processed[]`, state the new reason for selecting it again.

## Test quality (TEST)

- TEST-01: Every test asserts an observable result (return value, side effect, error path). No test may pass regardless of the implementation.
- TEST-02: Do not assert only on mocks. Mock external boundaries; assert on the unit's own behavior.
- TEST-03: Follow the nearest existing test file's layout, helpers, and naming.
- TEST-04: Tests are deterministic: no time-of-day, no randomness without a fixed seed, no network.

## Edit boundary (EDIT)

- EDIT-01: Touch only `Allowed paths`.
- EDIT-02: Never modify production code. A suspected production bug goes in the PR body under `### Deferred`.
- EDIT-03: Never delete, skip, comment out, or loosen an existing test or assertion.

## Honesty (HON)

- HON-01: You cannot run tests here. Never write that tests passed. Write the command CI will run and the expected result.
```

`references/category-input-schema.md`:

````markdown
# Detect JSON schema

The skill detect script (`scripts/detect_test_gap.sh`) emits:

```json
{
  "status": "ok",
  "scope": "range",
  "since": "<ref>",
  "commit_range": "<ref>..HEAD",
  "skip": false,
  "hotspots": [{ "path": "src/a.sh", "kind": "churn", "count": 7, "window": "90.days" }],
  "ledger": {
    "file": ".loop/state-test-gap-ledger.json",
    "processed": [{ "path": "test/bats/foo.bats", "attempts": 1, "outcome": "pr-created", "processed_at": "2026-10-11T10:00:00Z" }]
  },
  "warnings": []
}
```

- `skip` is always `false`. Detect never states that tests are missing.
- `hotspots[]` lists frequently edited paths. They are hints, not findings.
- `ledger.processed[]` lists recently processed test paths. Do not select a target whose test path is listed unless you can state a new reason.
- `warnings[]` lists recoverable sensor problems (for example an invalid `since` ref).
- `status: "error"` is fatal: stop and report the error text.
````

`references/category-automation-envelope.md`(契約が要求。`tech-debt` の構造に倣う。`write_target` は `fix`):

````markdown
# Automation Envelope

For automation-path runs. Load on the automation path — see SKILL.md Reference Files Guide.

## Constraints

The caller injects `## Constraints` after the detect JSON in the assembled prompt. Read:

| Field           | Type    | Description                                                                                    |
| --------------- | ------- | ---------------------------------------------------------------------------------------------- |
| `may_edit`      | boolean | `false` — survey shape only; do not write files. `true` — write tests and emit the apply shape |
| `write_target`  | string  | `fix` when `may_edit: true` for this skill (`report` is invalid here)                          |
| `Allowed paths` | string  | Allowlist globs from the caller                                                                |

The skill branches on `may_edit` and `write_target` only. Denylist is enforced by the automation checker — see [category-scope.md](category-scope.md).

Example (survey):

```text
## Constraints
may_edit: false
Allowed paths: test/**
```

Example (apply):

```text
## Constraints
may_edit: true
write_target: fix
Allowed paths: test/**
```

## PR body synthesis

Use [common-output-format.md](common-output-format.md). At synthesis, load:

| `may_edit` | Template                            |
| ---------- | ----------------------------------- |
| `false`    | `assets/pr-body-template-survey.md` |
| `true`     | `assets/pr-body-template.md`        |

When `may_edit: true` but the run emits the survey shape (`write_target` mismatch), use `assets/pr-body-template-survey.md`.

PR body rules:

- Top-level `## Overview`, `## Summary`, and `## Verification` (apply only).
- Under Summary use `### Candidates` (survey) or `### Changes` and `### Deferred` (apply). Use `### Deferred`, not `### Skipped`.
- Overview: trigger → substance → action. Name the target file and the behaviors covered. Write enough for a reviewer to understand without opening the diff.
- Links: read [category-pr-body-links.md](category-pr-body-links.md).
- Reconcile `### Changes` and `### Deferred` with `git diff --name-only` before synthesis. A path MUST NOT appear in both. Every path in the diff MUST appear in Changes.

## Session Metrics

Append `## Session Metrics` with the target, number of tests added, and files read.
````

`references/common-output-format.md`:

````markdown
# Test Gap Result Format

Deferred subsection name for this skill: `### Deferred` (not `### Skipped`).

## Survey result (`may_edit: false`)

```markdown
# Test Gap Result

## Overview

<scan scope → candidate targets and why → no edits applied>

## Summary

### Candidates

| Target         | Evidence                | Suggested tests       | Priority              |
| -------------- | ----------------------- | --------------------- | --------------------- |
| `path/to/file` | <churn, no paired test> | <behaviors to assert> | high \| medium \| low |
```

Survey rules: MUST NOT include `### Changes`, `### Deferred`, or `## Verification`. Zero candidates: Overview explains the no-op and omits `### Candidates`.

## Apply result (`may_edit: true`, `write_target: fix`)

```markdown
# Test Gap Result

## Overview

<trigger → target and reason (state the new reason if the path is in the ledger) → tests added>

## Summary

### Changes

| Target              | Gap                          | Tests added               |
| ------------------- | ---------------------------- | ------------------------- |
| `test/path/to/file` | <behavior that was untested> | <test names or behaviors> |

### Deferred

| Target         | Reason                         |
| -------------- | ------------------------------ |
| `path/to/file` | <needs production change, etc> |

## Verification

- Command CI runs: `<command>`
- Expected result: <pass; which new tests>
- Not run in this environment.
```

Apply rules: omit empty `###` headings. Never write that tests passed.
````

`references/category-pr-body-links.md`:

```markdown
# PR body links (file paths)

Apply at synthesis when emitting Summary tables in automation PR bodies.

## File paths

- Link repository paths as `[path](https://github.com/{owner}/{repo}/blob/{branch}/{path})`.
- Use the current git branch (the fix branch with your edits), not the default branch.
- Resolve `owner/repo` from `GITHUB_REPOSITORY` when set; otherwise parse `git remote get-url origin`.

## Template placeholders (skill assets)

- Use backtick placeholders in `assets/pr-body-template*.md` and `references/common-output-format*.md` (for example `` `test/path/to/file` ``).
- Do not embed example markdown links to a sample repository. They fail markdown-link-check with 404.
```

- [ ] **Step 3: assets を書く**

`assets/pr-body-template.md`:

```markdown
<!--
Apply PR template for test-gap automation (may_edit: true).

Load ONLY at synthesis time, after tests are written.

Rules:
- Keep top-level ## Overview, ## Summary, and ## Verification headings exactly as written.
- Use ### Deferred (not Skipped) for items not done in this run.
- Do NOT emit ### Candidates, Outcome, or Suggested next action.
- Never state that tests passed. You cannot run them here.
-->

## Overview

<!--
  GOOD: scripts/foo.sh had no paired Bats suite and was edited 7 times in 90 days. Added a suite covering argument parsing and the error exit path.
  BAD:  Added tests.
-->

<trigger → target and reason → tests added; name the file and behaviors>

## Summary

### Changes

| Target              | Gap                          | Tests added               |
| ------------------- | ---------------------------- | ------------------------- |
| `test/path/to/file` | <behavior that was untested> | <test names or behaviors> |

### Deferred

| Target         | Reason                         |
| -------------- | ------------------------------ |
| `path/to/file` | <needs production change, etc> |

## Verification

- Command CI runs: `<command>`
- Expected result: <pass; which new tests>
- Not run in this environment.
```

`assets/pr-body-template-survey.md`:

```markdown
<!--
Survey PR template for test-gap automation (may_edit: false).

Load ONLY at synthesis time.

Rules:
- Keep top-level ## Overview and ## Summary headings exactly as written.
- Do NOT emit ### Changes, ### Deferred, or ## Verification.
-->

## Overview

<!--
  GOOD: Scanned churn hotspots and found 3 files without paired tests; none were edited.
  BAD:  Survey done.
-->

<scan scope → candidates and why → no edits applied>

## Summary

### Candidates

| Target         | Evidence                | Suggested tests       | Priority              |
| -------------- | ----------------------- | --------------------- | --------------------- |
| `path/to/file` | <churn, no paired test> | <behaviors to assert> | high \| medium \| low |
```

- [ ] **Step 4: 禁止パターンが無いことを確認する**

Run: `grep -rnF -e '~280' -e 'one or two sentences' -e '1–2 sentences (max' -e '1-2 sentences (max' -e '](https://github.com/org/repo' .apm/packages/repo-maintenance/.apm/skills/test-gap/ || echo OK`
Expected: `OK`

- [ ] **Step 5: Commit(ユーザーの指示がある場合のみ)**

```bash
git add .apm/packages/repo-maintenance/.apm/skills/test-gap
git commit -m "feat(test-gap): add SKILL.md, references, and PR body templates"
```

---

## Task 5: 契約チェックと drift 一覧に `test-gap` を登録する

**Files:**

- Modify: `scripts/self/apm/check_apm_skill_install_drift.sh`(`LOOP_SKILLS`、31–40 行付近)
- Modify: `scripts/self/apm/check_loop_pr_body_contract.sh`(`LOOP_SKILLS`、59–67 行付近、`LOOP_PR_BODY_LINKS_SKILLS`、77–85 行付近)
- Test: `test/bats/scripts/self/apm/`(既存の対応する Bats を確認して更新する)

**Interfaces:**

- Consumes: Task 4 のファイル(契約の必須ファイル)
- Produces: `check_loop_pr_body_contract.sh` が `test-gap` を検証対象にする。`check_apm_skill_install_drift.sh` が `.agents/skills/test-gap`、`.claude/skills/test-gap` の同期を検証する(Task 8 で同期するまでは drift が出る)。

- [ ] **Step 1: 既存の Bats を確認する**

Run: `ls test/bats/scripts/self/apm/ && grep -ln "LOOP_SKILLS\|tech-debt" test/bats/scripts/self/apm/*.bats`
Expected: 対象の Bats ファイル名が分かる。`tech-debt` を列挙しているテストがあれば、同じ箇所に `test-gap` を足す(列挙していなければ変更不要)。

- [ ] **Step 2: 契約チェックのテストを先に書く(失敗させる)**

Step 1 で見つけた `check_loop_pr_body_contract` の Bats に、次のテストを追加する(ファイル名は Step 1 の結果に従う。既存のヘルパー `SKILLS_ROOT` の使い方に合わせる)。

```bash
@test "check_loop_pr_body_contract validates test-gap required files" {
    local root
    root="$(mktemp -d)"
    mkdir -p "${root}/test-gap/assets" "${root}/test-gap/references"
    run env SKILLS_ROOT="${root}" bash "${CHECK_SCRIPT}"
    [ "$status" -eq 1 ]
    [[ $output == *"test-gap"* ]]
    rm -rf "${root}"
}
```

`CHECK_SCRIPT` は、その Bats が既に定義している変数名に合わせる(無ければ `$(bats_workspace_root)/scripts/self/apm/check_loop_pr_body_contract.sh`)。

Run: `bats test/bats/scripts/self/apm/<対象>.bats -f "test-gap"`
Expected: FAIL(`LOOP_SKILLS` に `test-gap` が無く、出力に `test-gap` が含まれない)。

- [ ] **Step 3: 一覧に追加する**

`scripts/self/apm/check_apm_skill_install_drift.sh` の `LOOP_SKILLS`(アルファベット順で `tech-debt` の前、`refactor` の後)に追加:

```bash
declare -a LOOP_SKILLS=(
    changelog
    ci-sweeper
    docs-updater
    github-issue-autofix
    github-issue-triage
    github-pr-revise
    refactor
    tech-debt
    test-gap
)
```

`scripts/self/apm/check_loop_pr_body_contract.sh` の `LOOP_SKILLS` と `LOOP_PR_BODY_LINKS_SKILLS` の両方に `test-gap` を `tech-debt` の次に追加する(同ファイルは `tech-debt` が末尾のため、その後ろ)。

- [ ] **Step 4: テストと実チェックを実行する**

Run: `bats test/bats/scripts/self/apm/<対象>.bats && SKILLS_ROOT= bash scripts/self/apm/check_loop_pr_body_contract.sh`
Expected: Bats は全件 PASS。契約チェックは `test-gap` について違反なし(Task 4 の必須ファイルが揃っているため)。

- [ ] **Step 5: Commit(ユーザーの指示がある場合のみ)**

```bash
git add scripts/self/apm test/bats/scripts/self/apm
git commit -m "chore(apm): register test-gap in loop skill checks"
```

---

## Task 6: caller `on-loop-test-gap.yaml`

`on-loop-tech-debt.yaml` を雛形にする。`tech-debt` との違いは、`write_target: fix`、`allowlist: test/**`、`pr_enabled: false`、台帳(`domain_persistence_script` と `additional_commit_paths`)、`agent_allowed_tools` なし、`infer_files_pattern`、cron。

**Files:**

- Create: `.github/workflows/on-loop-test-gap.yaml`

**Interfaces:**

- Consumes: Task 2 の `detect_test_gap.sh`、Task 3 の `update_test_gap_ledger.sh`(インストール後は `.agents/skills/test-gap/scripts/...`)
- Produces: schedule と dispatch で動く loop caller

- [ ] **Step 1: ファイルを書く**

`.github/workflows/on-loop-test-gap.yaml`(`with:` のキーはアルファベット順。既存の `on-loop-tech-debt.yaml` と同じキー集合を使い、差分だけ変える):

```yaml
# Loop workflow: Add missing tests
# Selects an under-tested target (agent-driven), adds tests within the allowlist, and opens a PR.
# Design doc: docs/explanation/loop-engineering/workflows/loop-test-gap-workflow-design.md
# Caller inputs: docs/explanation/loop-engineering/workflows/loop-caller-inputs-reference.md
# Requires repository secret: AGENT_TOKEN (engine API key; see engine input).
# Pass credentials via secrets: (callee BOT_APP_* / AGENT_TOKEN; remap MAINTENANCE_BOT_*). Optional with.environment for env-scoped secrets inside the reusable.
name: on-loop-test-gap

run-name: "${{ github.workflow }} (${{ github.event_name }})"

on:
  schedule:
    - cron: "0 10 * * 1"
      timezone: Etc/UTC
  workflow_dispatch: {}

permissions:
  actions: write
  contents: write
  copilot-requests: write # zizmor: ignore[excessive-permissions]
  issues: write
  pull-requests: write

concurrency:
  cancel-in-progress: false
  group: loop-state-main
  queue: max

jobs:
  loop:
    uses: ./.github/workflows/ci-loop-caller.yaml
    with:
      additional_commit_paths: .loop/state-test-gap-ledger.json
      agent_checker_effort: medium
      agent_checker_instructions: |
        ## Criteria for APPROVE

        ALL of the following must be true:
        1. Changes are limited to files under the allowlist (`test/**`) and touch no denylist path
        2. No existing test is deleted, skipped, commented out, or loosened (no weakened assertion)
        3. Each added test asserts observable behavior of the target (return value, side effect, error path); no test can pass regardless of the implementation
        4. The added tests correspond to a target that actually lacked tests (a missing unit or a missing paired suite)
        5. The target is not in `ledger.processed[]`, or the PR body states a new reason for selecting it again
        6. The PR body names the target, the reason, the command CI will run, and the expected result, and does not claim the tests were run

        ## Criteria for REJECT

        ANY of the following triggers REJECT:
        - An added test does not verify the target's behavior (unused return value, always-true assertion, assertion only on a mock)
        - Any production file or denylist path is modified
        - An existing test is removed, skipped, or weakened
        - A ledger-listed target is selected again without a stated new reason
        - The PR body claims the tests were executed or passed
        - No test file was written
      agent_checker_max_turns: 100
      agent_checker_model: claude-opus-5
      agent_checker_skill_name: loop-verifier
      agent_loop_max_attempts: 3
      agent_maker_effort: medium
      agent_maker_instructions: |
        Select exactly one under-tested target and add tests for it.
        Discover the stack and test layout from the repository; do not assume a language.
        For shell scripts follow the shell-script-validation skill and the Bats rules (every script needs a paired suite).
        For Go follow the go-validation skill and the existing `*_test.go` layout.
        Do not select a path listed in `ledger.processed[]` unless you can state a new reason in the PR body.
        You cannot run the tests here. Do not claim you ran them; state the command CI will run and the expected result.
        Do not edit production code. Report a suspected production bug under Deferred.
      agent_maker_max_turns: 100
      agent_maker_model: claude-sonnet-5
      agent_maker_skill_name: test-gap
      allowlist: test/**
      branch_match: main
      branch_state: main
      budget_max_runs_per_day: 2
      budget_max_tokens_per_day: 1000000
      delivery: open_pr
      detect_domain_env_json: "{}"
      detect_script: .agents/skills/test-gap/scripts/detect_test_gap.sh
      domain_persistence_script: .agents/skills/test-gap/scripts/update_test_gap_ledger.sh
      engine: claude
      environment: default
      infer_files_pattern: 'test/[^[:space:],)]+\.(bats|go|sh|json|ya?ml)'
      level: L2
      loop_name: test-gap
      max_targets_per_schedule: 1
      may_edit: true
      no_changes_verdict: REJECT
      pr_body: ""
      pr_enabled: false
      pr_title: "test: add missing tests (loop-test-gap)"
      write_target: fix
    secrets:
      AGENT_TOKEN: ${{ secrets.AGENT_TOKEN }}
      BOT_APP_CLIENT_ID: ${{ secrets.MAINTENANCE_BOT_APP_CLIENT_ID }}
      BOT_APP_PRIVATE_KEY: ${{ secrets.MAINTENANCE_BOT_APP_PRIVATE_KEY }}
```

- [ ] **Step 2: `on-loop-tech-debt.yaml` と入力キーを突き合わせる**

Run: `diff <(grep -oE '^      [a-z_]+:' .github/workflows/on-loop-tech-debt.yaml | sort) <(grep -oE '^      [a-z_]+:' .github/workflows/on-loop-test-gap.yaml | sort)`
Expected: 差分は `additional_commit_paths`、`domain_persistence_script`(test-gap のみ)、`report_file` 関連(tech-debt のみ。`infer_files_pattern` は両方にある)。想定外のキーが test-gap だけに出ていたら、`ci-loop-caller.yaml` の `workflow_call.inputs` に存在するか確認する。

- [ ] **Step 3: 入力名が reusable に存在することを確認する**

Run: `for k in additional_commit_paths domain_persistence_script write_target no_changes_verdict infer_files_pattern pr_enabled max_targets_per_schedule; do grep -q "^      $k:" .github/workflows/ci-loop-caller.yaml && echo "ok $k" || echo "MISSING $k"; done`
Expected: すべて `ok`。

- [ ] **Step 4: ワークフローを検証する**

github-actions-validation skill に従う: `actionlint .github/workflows/on-loop-test-gap.yaml`、`ghalint run`、`zizmor .github/workflows/on-loop-test-gap.yaml`(手順は skill の SKILL.md)。ORD-01(キー順)は手動で確認する。
Expected: 新規の違反なし。

- [ ] **Step 5: Commit(ユーザーの指示がある場合のみ)**

```bash
git add .github/workflows/on-loop-test-gap.yaml
git commit -m "feat(test-gap): add loop caller workflow"
```

---

## Task 7: ドキュメントと nav

`loop-capable-skills.md` の「Cross-cutting edit checklist」に従う。

**Files:**

- Create: `docs/explanation/loop-engineering/workflows/loop-test-gap-workflow-design.md`
- Modify: `docs/explanation/loop-engineering/loop-capable-skills.md`(Loop entry skills の表)
- Modify: `docs/explanation/loop-engineering/loop-engineering-design.md`(ステータス表: `Spec draft` → `Dogfood L2`、ロードマップ表の追加)
- Modify: `docs/explanation/loop-engineering/workflows/loop-caller-inputs-reference.md`(該当表があれば `test-gap` の列/行)
- Modify: `docs/reference/specification.md`、`docs/explanation/architecture.md`(`tech-debt` を列挙している箇所に `test-gap` を追加)
- Modify: `mkdocs.yml`(`nav` に新規ドキュメントを追加)

**Interfaces:**

- Consumes: spec の決定事項、Task 6 の caller
- Produces: 設計書へのリンク(`workflow design`)

- [ ] **Step 1: `tech-debt` を列挙している箇所を洗い出す**

Run: `grep -rn "tech-debt" docs/explanation docs/reference mkdocs.yml | grep -v "docs/report/\|docs/superpowers/" | cut -c1-140`
Expected: 追加が必要な表や一覧の行が分かる。

- [ ] **Step 2: workflow 設計書を書く**

`docs/explanation/loop-engineering/workflows/loop-test-gap-workflow-design.md`(`loop-tech-debt-workflow-design.md` の章立てに倣う: 目的、スケジュール、入力表、detect の出力、台帳、Checker の基準、運用、参照)。内容は spec(`docs/superpowers/specs/2026-10-11-loop-test-gap-design.md`)の「決定事項」「アーキテクチャ」「Checker の基準」「検証経路」を、現行の実装に合わせて書き直す(spec へのリンクを張り、コピーはしない)。必須の記載:

- スケジュール: `0 10 * * 1`(月曜 10:00 UTC)と `workflow_dispatch`
- 入力表: Task 6 の `with:` の各キーと説明(`tech-debt` の入力表と同じ形式)
- 検証は CI に任せ、失敗は人間が対応する(`ci-sweeper` には拾わせない。理由は spec へのリンク)
- 台帳 `.loop/state-test-gap-ledger.json` の形式と保持期間
- 見出しの直下に、設計書として英語/日本語どちらで書くかは既存の `loop-*-workflow-design.md` に合わせる(既存は英語)。**既存に揃えて英語で書く**(spec のみ日本語の指定)。

- [ ] **Step 3: 一覧とステータスを更新する**

- `loop-capable-skills.md` の Loop entry skills の表に 1 行追加:

```markdown
| `test-gap` | `repo-maintenance` | `on-loop-test-gap.yaml` | find/add missing tests | scheduled detect JSON (hotspots, ledger) |
```

- `loop-engineering-design.md` のステータス表の `test-gap` 行を `Dogfood L2; weekly schedule` に変更し、ロードマップ表(Tier 1)に `test-gap` の行を追加して、設計書(`loop-test-gap-workflow-design.md`)へリンクする。
- Step 1 で見つけた他の一覧に `test-gap` を追加する。

- [ ] **Step 4: `mkdocs.yml` の `nav` を同期する**

`nav` で `loop-tech-debt-workflow-design.md` を参照している箇所の隣に `loop-test-gap-workflow-design.md` を追加する(Run: `grep -n "loop-tech-debt-workflow-design" mkdocs.yml`)。

- [ ] **Step 5: Markdown を検証する**

markdown-validation skill に従う: `markdownlint-cli2 <変更したファイル>` と `markdown-link-check <変更したファイル>`(Stop hook でも検証される)。
Expected: エラーなし。

- [ ] **Step 6: Commit(ユーザーの指示がある場合のみ)**

```bash
git add docs mkdocs.yml
git commit -m "docs(test-gap): add workflow design and register the loop"
```

---

## Task 8: インストール同期とドリフト確認、eval

**Files:**

- Sync: `.agents/skills/test-gap/`、`.claude/skills/test-gap/` ほか、`apm install` が生成する同期先
- Create: `.apm/packages/repo-maintenance/.apm/skills/test-gap/eval.yaml`
- Create: `.apm/packages/repo-maintenance/.apm/skills/test-gap/evals/tasks/basic.yaml`

**Interfaces:**

- Consumes: Task 4〜6 のすべて
- Produces: インストール済み skill、waza 評価

- [ ] **Step 1: eval を書く**

`tech-debt/eval.yaml` の構造を使う。`.apm/packages/repo-maintenance/.apm/skills/test-gap/eval.yaml`:

```yaml
name: test-gap-eval
description: >-
  Evaluation suite for test-gap.
  Verifies target selection, survey vs apply shape, ledger avoidance, and the no-claim-of-execution rule.
skill: test-gap
version: "1.0"
config:
  trials_per_task: 5
  timeout_seconds: 180
  parallel: false
  executor: mock
  model: claude-sonnet-4-20250514
metrics:
  - name: task_completion
    weight: 1.0
    threshold: 0.8
    description: Verify evaluation task completes successfully.
graders:
  - type: code
    name: has_structured_output
    weight: 1.0
    config:
      assertions:
        - "'## Overview' in output or 'Overview' in output"
        - "'## Summary' in output or 'Summary' in output"
        - "'Changes' in output or 'Candidates' in output or 'no under-tested' in output.lower()"
  - type: text
    name: report_sections
    weight: 0.5
    config:
      regex_match:
        - (### Candidates|### Changes|### Deferred)
  - type: behavior
    name: bounded_runtime
    weight: 0.5
    config:
      max_tool_calls: 30
      max_tokens: 120000
      max_duration_ms: 180000
tasks:
  - evals/tasks/*.yaml
```

`evals/tasks/basic.yaml`:

```yaml
id: test-gap-contract-001
name: test-gap emits apply shape without claiming execution
description: >-
  Validate test-gap emits ## Verification that states the command CI runs and does not claim the tests passed.
tags:
  - quality
  - output-contract
inputs:
  prompt: >-
    Use test-gap with may_edit true and write_target fix. The target scripts/foo.sh has no paired test.
    Emit the apply PR shape with ### Changes, ### Deferred when applicable, and ## Verification.
    You cannot run tests here; do not claim they passed.
  context:
    skip: false
    hotspots:
      - path: scripts/foo.sh
        kind: churn
        count: 7
        window: 90.days
    ledger:
      file: .loop/state-test-gap-ledger.json
      processed: []
expected:
  output_contains:
    - Changes
    - Verification
  outcomes:
    - type: task_completed
```

- [ ] **Step 2: `apm install` で同期する**

Run(リポジトリルート): `apm install`
Expected: `.agents/skills/test-gap/`、`.claude/skills/test-gap/` ほかが作られる(CLAUDE.md の Edit routing: `.apm/packages/` が source of truth)。`apm.lock` 等の更新があればそれも含める。

- [ ] **Step 3: ドリフトを確認する**

Run: `bash scripts/self/apm/check_apm_skill_install_drift.sh`
Expected: exit 0(drift なし)。drift が出たら `apm install` をやり直し、source を直す(同期先を手編集しない)。

- [ ] **Step 4: 同期した detect を、インストール済みパスで実行する**

Run: `bash .agents/skills/test-gap/scripts/detect_test_gap.sh --scope range --since HEAD~5 | jq .`
Expected: `status: "ok"`、`skip: false`、`hotspots`(churn の上位)、`ledger.processed: []`。

- [ ] **Step 5: skill の品質を確認する**

`agent-skills-review` skill に従い、`SKILL.md` が Waza readiness と description contract(Interactive、Automation、edit gate)を満たすか確認する。

- [ ] **Step 6: Commit(ユーザーの指示がある場合のみ)**

```bash
git add .apm/packages/repo-maintenance/.apm/skills/test-gap .agents .claude .codex .cursor .kiro .vscode apm_modules apm.lock.yaml 2>/dev/null
git commit -m "chore(test-gap): sync installed skill and add eval"
```

注意: `git add` するパスは、`git status` で実際に変更されたものに限定する(存在しないパスは無視される)。

---

## Task 9: ローカルでの結合確認

実 workflow はローカルで実行できないため、`loop-detect` の関数と detect script を組み合わせて確認する。

**Files:**

- なし(確認のみ)

- [ ] **Step 1: 全 Bats を実行する**

Run: `bats -r test/bats/.apm/packages/repo-maintenance/test-gap test/bats/scripts/self/apm test/bats/github-actions/loop-detect-enrich.bats`
Expected: すべて PASS。

- [ ] **Step 2: 台帳の往復を確認する(detect → ledger → detect)**

```bash
tmp="$(mktemp -d)" && cd "${tmp}" && git init -q -b main . \
  && git config user.email t@example.com && git config user.name t \
  && mkdir -p test/bats .loop && printf 'a\n' > README.md && git add . && git commit -q -m init \
  && git checkout -q -b feature && printf '@test "x" { true; }\n' > test/bats/foo.bats && git add . && git commit -q -m "test: foo" && git checkout -q main \
  && OUTCOME=pr-created EXECUTE_BRANCH=feature TEST_GAP_BASE_BRANCH=main GITHUB_RUN_ID=1 \
     bash /workspace/.agents/skills/test-gap/scripts/update_test_gap_ledger.sh \
  && bash /workspace/.agents/skills/test-gap/scripts/detect_test_gap.sh | jq '.ledger.processed'
```

Expected: `[{"path":"test/bats/foo.bats","attempts":1,"outcome":"pr-created","processed_at":"..."}]`。確認後 `cd /workspace && rm -rf "${tmp}"`。

- [ ] **Step 3: 実環境でしか確認できない事項を記録する**

次はローカルで検証できない。初回の `workflow_dispatch` 実行時に確認し、結果を spec の「未決事項」に反映する。

1. `domain_persistence_script` の実行時に `EXECUTE_BRANCH` が `git diff` で解決できるか(finalize ジョブの checkout が agent ブランチを fetch しているか)。解決できない場合、台帳は更新されず警告が出る(spec の Review Focus 1、3)。
2. PR の作成が GitHub App のトークンで行われ、`on-ci-push-shell-script` などの CI が起動するか。
3. `loop-finalize` が `additional_commit_paths` の `.loop/state-test-gap-ledger.json` を state コミットに含めるか。
4. Checker の rubric により、意味のないテストが REJECT されるか(Checker Theater の実測)。

- [ ] **Step 4: 最終確認**

Run: `git status --short` で、意図したファイルだけが変更されていることを確認する(`mise.toml`、`mise.lock`、Dockerfile の変更は別件として、同じ PR に混ぜるかを判断する)。

---

## Self-Review(計画の自己点検)

**1. Spec coverage**

| spec の要件                                                                                      | 担当タスク                                                             |
| ------------------------------------------------------------------------------------------------ | ---------------------------------------------------------------------- |
| 別 loop `test-gap`、`repo-maintenance` package                                                   | Task 4、6                                                              |
| 薄い detect(`skip:false`、churn、ledger 要約)                                                    | Task 2                                                                 |
| 台帳 `.loop/state-test-gap-ledger.json`、`domain_persistence_script` + `additional_commit_paths` | Task 3、6                                                              |
| Checker の静的基準                                                                               | Task 6(`agent_checker_instructions`)                                   |
| 検証は CI に任せ、失敗は人間が対応(`pr_include_bots` 不変)                                       | Global Constraints、Task 7(設計書)                                     |
| L2 開始、allowlist `test/**`                                                                     | Task 6                                                                 |
| 月曜 10:00 UTC + `workflow_dispatch`、tech-debt と同じモデル構成                                 | Task 6                                                                 |
| 共通コードを変更しない                                                                           | Global Constraints                                                     |
| チェックリスト(LOOP_SKILLS、PR 本文契約、docs、Bats)                                             | Task 5、7、1〜3                                                        |
| Selection Criteria 5 の記録                                                                      | 済み(`loop-engineering-design.md` に追記済み)。Task 7 でステータス更新 |
| ツール導入 action(拡張)                                                                          | **本計画の対象外**(spec で「拡張」。初期は案 2 で運用)                 |
| `ci-sweeper` の bot 判定(`app/renovate` 漏れ)の修正                                              | **対象外**(別件。Issue 化を推奨)                                       |

**2. Placeholder scan:** 本文に TBD/TODO は無い。Task 5 の Bats 追記と Task 7 の設計書本文は、既存ファイルの形式に依存するため、先に既存を確認する手順(Step 1)を置き、書く内容の必須項目を列挙した。

**3. Type consistency:** 台帳 JSON(`entries[path] = {attempts, last_loop_run_id, outcome, processed_at}`)は Task 1(テスト)、Task 2(`ledger.processed[]` への変換、`path` に改名)、Task 3(書き込み)で一致している。環境変数名 `TEST_GAP_LEDGER_FILE`、`TEST_GAP_RETENTION_DAYS`、`TEST_GAP_BASE_BRANCH` は Task 1〜3 で一致している。

**4. Review Focus:** 上記 7 件を Task 1〜3 のテストに割り当て済み(1: Task 2/3、2: Task 2、3: Task 1/3、4: Task 1、5: Task 1/2、6: Task 1、7: Task 1)。

**既知のリスク(実装中に確認する)**

- Task 2 の関数順(G-03)は、コード例が a-z 順に整っていない。実装時に並べ替える(本文に注記済み)。
- `scripts/lib` の関数名(`json_object` の引数形式、`log`、`repo_path_should_skip`、`json_emit_minimal_error`)は、`scripts/lib/json.sh`、`common.sh`、`repo_paths.sh` のヘッダで確認してから使う。
- 台帳は、finalize ジョブで `EXECUTE_BRANCH` が解決できることに依存する。解決できない場合は警告のみで、動作は止まらない。
