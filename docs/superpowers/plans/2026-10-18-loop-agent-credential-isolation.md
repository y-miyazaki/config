# Loop Agent Credential Isolation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `agent-l1` と `agent-l2` のジョブから、GitHub に書き込める認証情報(App の秘密鍵、App のトークン、`GH_TOKEN`、書き込み権限の `github.token`)をなくす。エージェントのブランチの push は、bundle の artifact を経て `loop-finalize` の新しいステップ Push Agent Branch が、検証してから行う。

**Architecture:** `loop-execute` の Push Branch(`lib/push.sh`)を Bundle Branch(`lib/bundle.sh`)に置き換える。agent-l2 は bundle を artifact に上げ、finalize-l2 が取得して `loop-finalize` に `agent_bundle_dir` で渡す。`loop-finalize` の Push Agent Branch(`lib/push_agent_branch.sh`)は、ブランチ名、bundle の中身、`from.ref` の子孫、denylist・allowlist・`.github/workflows/` のかけ直し、既存のブランチを確かめてから push する。失敗は段階 `push` で `LOOP_FAILURE_FILE` に記録して 0 で終え、後のステップは出力 `failed` / `pushed` で分岐する。パスの判定の関数は `loop-execute/lib/paths.sh` から共有の `lib/loop/edit_paths.sh` に移す。

**Tech Stack:** GitHub Actions(reusable workflow、composite action、`actions/upload-artifact` / `download-artifact`)、bash、git(`bundle`)、jq、bats。

**Spec:** `docs/superpowers/specs/2026-10-18-loop-agent-credential-isolation-design.md`。spec の行番号は配信、detect hook の削除、run-log の outcome の実装(`feat/loop-delivery-message`、HEAD `199f957d`)の後でずれている。この plan の行番号は HEAD で確かめた値である(対応は末尾の「spec との差」)。

## Global Constraints

- エージェントのジョブ(`agent-l1`、`agent-l2`)は `loop-resolve-push-token` を実行せず、`secrets.BOT_APP_CLIENT_ID`・`secrets.BOT_APP_PRIVATE_KEY`・`secrets.GH_TOKEN` を参照しない。`secrets.AGENT_TOKEN` だけは残す。`loop-worktree-setup`・`loop-execute`・`loop-agent-once` の `github_token` は `${{ github.token }}`。
- 権限: `agent-l1` は `contents: read`、`copilot-requests: write`、`issues: read`、`pull-requests: read`。`agent-l2` はそれに `actions: read` を足す。どちらも `write` は `copilot-requests` だけ。
- artifact の名前: `loop-agent-bundle-<GITHUB_RUN_ATTEMPT>-<printf '%s' key | sha256sum の先頭16文字>`(例: key `integration:main`、attempt `1` → `loop-agent-bundle-1-138c728d71ab409c`。key `pull_request:7` → `d4cedacd722526b8`)。両方の Parse Target が同じ式で出力 `bundle_artifact_name` を出す。`retention-days: 1`。上げるステップは `overwrite` を指定しない(既定 `false`。同名があればエージェントのジョブが失敗する)。
- bundle のファイルは `${{ runner.temp }}/loop-agent-bundle/branch.bundle`(agent-l2 の `loop-execute` が作り、finalize-l2 は同じディレクトリに取得する)。中身は `git bundle create <file> "^origin/<base_branch>" "refs/heads/<branch>"`。
- 出力 `has_changes` は「bundle を作った」を意味する(現在は「リモートにブランチがある」)。
- ブランチ名の検証: 空でなければ、`<agent_branch_prefix>/<agent_maker_skill_name>/` で始まり(`[[ ${b} == "${prefix}"* ]]` の文字列比較。正規表現に埋め込まない)、残りが `^[0-9]{8}-[0-9]{6}$`、`to_branch` とも `state_branch` とも違う。空なら検証せず何もしない。検証を通った名前を Push Agent Branch の出力 `branch` とし、Run Finalize Hook の `EXECUTE_BRANCH`、Push to Target Branch、Create PR、Delete Agent Branch はその出力だけを使う。push は force しない。
- Push Agent Branch の失敗(名前の検証と spec の 1〜6)は `loop_failure_record push <msg> "${LOOP_FAILURE_FILE}"`、出力 `pushed=false`・`failed=true`、終了コード 0。失敗のときにステップを失敗させる Fail Agent Push は Delete Agent Branch の後、Resolve Run Outcome の前(Resolve Run Outcome は記録があれば `error` にし、記録を上書きしない。`resolve_run_outcome.sh`)。
- `.github/workflows/` の変更は、`.github/` で始まる allowlist のパターンに当たるときだけ許す。`**` や空の allowlist では許さない。`.loop/` は除外しない。差分は `git diff --name-only --no-renames`。
- 権限の4ファイル(`.claude/settings.json` ほか。CLAUDE.md の Permission parity)は変えない(spec「残るもの」)。`on-ci-push-mise-update-lock.yaml` の `branches: [main]` も範囲外(spec が別の修正とする)。
- シェルの変更には bats を対にする(`.claude/rules/bats.md`)。テストを先に書く。`shfmt`・`prettier` は PostToolUse フック、`shellcheck`・`actionlint`・`ghalint`・`zizmor`・`markdownlint-cli2`・`markdown-link-check`・`gitleaks` は Stop フックが実行する。**実装者は直接実行しない**(結果はフックの出力で見る)。
- 作業ツリーに無関係の変更がある(`.claude/settings.json`、`.cursor/mcp.json`、`.mcp.json`、`apm.lock.yaml`、`.claude/worktrees/`)。コミットは**明示したパスだけ**を stage する。`git add -A` は使わない。skill は変えないので APM の同期は要らない(Stop フックの同期で差分が出ても stage しない)。
- 一時ファイルは `tmp/` に置き、使い終えたら消す。
- `ci-*` から `./.github/...` を参照しない。pin は変えない。リリースと pin の更新、GitHub Actions のワークフローの実行(dogfood)は、この plan に含めない。push しない。

## Review Focus

1. **検証の名前を後のステップが使うこと。** `inputs.branch` を直接読むステップが1つでも残ると、名前の検証が素通りになる。Task 6 の `no step after push agent branch reads inputs.branch` で、Push Agent Branch 以外の `inputs.branch` の参照が0件であることを見る。
2. **`--no-renames` と三点の差分。** denylist のファイルを許されたパスへ `git mv` した変更は、改名の検出があると新しいパスだけが出る。Task 1(`list_non_loop_branch_files` と verifier)と Task 5(`renaming a denylisted file is rejected`)で見る。
3. **`.loop/` を除外しないこと。** エージェントのブランチに `.loop/` の変更があり、allowlist がそれを含まない caller は、今まで通っていた push が `push` で失敗するようになる(spec の意図)。dogfood で既存の caller の `.loop/` のコミットの有無を確かめる(bats では確かめられない)。
4. **`from.ref` が bundle の外にある場合。** `from.ref` が base の祖先なら bundle に含まれず、finalize の checkout(`fetch-depth: 0`)にあるはずだが、PR の head が force-push された後は消えていることがある。`git merge-base --is-ancestor` が「オブジェクトがない」で失敗したときも `failed` にする(fail closed)。Task 5 の `force-pushed PR head` のテストで、bundle が base 基準で検証に通ることと、`from.ref` が取得できないときに失敗することの両方を見る。
5. **GitHub の MCP サーバと `github.token`。** `.mcp.json` の `github`(HEAD の `:13-18`)は `GH_TOKEN:-GITHUB_TOKEN` を使う。`github.token` を受け付けるか、受け付けないときにエージェントが読み取りの `gh` で続けられるかは dogfood でしか確かめられない(spec「検証」)。

---

## ファイル構成

| ファイル                                                                                                                                                                               | 責務                                                     | Task |
| -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------- | ---- |
| `.github/actions/lib/loop/edit_paths.sh`(新規)、`.github/actions/loop-execute/lib/paths.sh`、`verifier.sh`、`_init.sh`                                                                 | パスの判定の共有化、`--no-renames`                       | 1    |
| `.github/actions/{loop-execute,loop-agent-once,loop-install-cli}/action.yml`                                                                                                           | キャッシュを止める                                       | 2    |
| `.github/actions/loop-execute/lib/bundle.sh`(新規。`push.sh` を削除)、`action.yml`                                                                                                     | Bundle Branch                                            | 3    |
| `.github/actions/loop-finalize/lib/{determine_outcome,resolve_state_write_mode,parse_target}.sh`                                                                                       | `failed` の優先、`base_branch`                           | 4    |
| `.github/actions/loop-finalize/lib/push_agent_branch.sh`(新規)                                                                                                                         | Push Agent Branch の判断と push                          | 5    |
| `.github/actions/loop-finalize/action.yml`                                                                                                                                             | 入力、ステップ、`if`、Fail Agent Push                    | 6    |
| `.github/workflows/ci-loop-agent.yaml`、`.github/actions/loop-worktree-setup/action.yml`(説明)                                                                                         | 権限、秘密情報、artifact の上げ下ろし、finalize への入力 | 7    |
| `.github/workflows/on-loop-{github-pr-revise,github-issue-autofix,ci-sweeper}.yaml`                                                                                                    | 許可リストの整理                                         | 8    |
| `docs/reference/specification.md`、`docs/explanation/github-workflows-design.md`、`docs/explanation/loop-engineering/` の該当ファイル、`.github/actions/loop-run-log/action.yml`(説明) | 記述                                                     | 9    |

---

### Task 1: パスの判定を `lib/loop/edit_paths.sh` に移し、差分を `--no-renames` にする

**Files:**

- Create: `.github/actions/lib/loop/edit_paths.sh`(`paths.sh:16-20` の `DEFAULT_EXECUTE_DENYLIST`、`apply_platform_denylist_default`、`collect_allowlist_violations`、`collect_denylist_violations`、`component_to_ere`、`glob_to_ere`、`path_matches_glob` をそのまま移す)
- Modify: `.github/actions/loop-execute/lib/paths.sh`(移した定義を消し、`$(cd "$(dirname "${BASH_SOURCE[0]}")/../../lib/loop" && pwd)/edit_paths.sh` を source。`:331` に `--no-renames`。ヘッダーの Design Rules を更新)
- Modify: `.github/actions/loop-execute/lib/verifier.sh:233`(`--no-renames`)
- Test: `test/bats/.github/actions/lib/loop/edit_paths.bats`(新規。`paths.bats:36-146` のテストを移す)、`test/bats/.github/actions/loop-execute/lib/paths.bats`(移したテストを消す。`infer_files_from_text` は残す)、`test/bats/github-actions/loop-branch-diff.bats`、`test/bats/.github/actions/loop-execute/lib/verifier.bats`

**Interfaces:** Produces `edit_paths.sh`(ライブラリ。関数名・引数・Globals は現在と同じ)。Task 5 が `apply_platform_denylist_default`、`collect_allowlist_violations`、`collect_denylist_violations`、`path_matches_glob` を使う。`paths.sh` を source する既存の呼び出し(`_init.sh:31-32`)は変えない。

- [ ] **Step 1: 失敗するテストを書く。**
  - `edit_paths.bats`: `bats_source_rel ".github/actions/lib/loop/edit_paths.sh"` で、`paths.bats:36-146` の14件を同じ名前で移す。
  - `loop-branch-diff.bats` に `@test "list_non_loop_branch_files lists both paths of a rename"`: base に `secrets.txt` を置き、ブランチで `git mv secrets.txt docs/notes.txt` をコミット。出力に `secrets.txt` と `docs/notes.txt` の両方が含まれる。
  - `verifier.bats` に、同じ改名で denylist `secrets*` のとき verdict が `REJECT` になるテスト(既存の denylist のテストと同じ組み立て方)。
- [ ] **Step 2: 失敗を確認する。** `bats test/bats/.github/actions/lib/loop/edit_paths.bats test/bats/github-actions/loop-branch-diff.bats test/bats/.github/actions/loop-execute/lib/verifier.bats`。Expected: FAIL(ファイルがない、改名の新しいパスだけが出る)。
- [ ] **Step 3: 実装する。** Files のとおり。関数は a-z の順を保つ。
- [ ] **Step 4: 通ることを確認する。** `bats test/bats/.github/actions/lib/loop/ test/bats/.github/actions/loop-execute/ test/bats/github-actions/loop-branch-diff.bats`。Expected: PASS。兄弟の箇所: `git grep -n "diff --name-only" -- .github/actions` の残り(`notify_context.sh:375`、`:377` は通知の文脈で、判定に使わない)は変えず、完了の報告に書く。
- [ ] **Step 5: コミットする。** `git add .github/actions/lib/loop/edit_paths.sh .github/actions/loop-execute/lib/paths.sh .github/actions/loop-execute/lib/verifier.sh test/bats/.github/actions/lib/loop/edit_paths.bats test/bats/.github/actions/loop-execute/lib/paths.bats test/bats/github-actions/loop-branch-diff.bats test/bats/.github/actions/loop-execute/lib/verifier.bats`、`refactor(loop): share the edit path guards and diff without rename detection`。

---

### Task 2: エージェントのジョブのキャッシュを止める

**Files:**

- Modify: `.github/actions/loop-execute/action.yml:177-187`、`.github/actions/loop-agent-once/action.yml:66-75`、`.github/actions/loop-install-cli/action.yml:33-42`(`setup-node` の `with` に `package-manager-cache: false`、`setup-uv` の `enable-cache: true` を `false`。`prune-cache` は変えない)
- Test: `test/bats/.github/actions/{loop-execute,loop-agent-once,loop-install-cli}/action.bats`

**Interfaces:** なし。

- [ ] **Step 1: 失敗するテストを書く。** 3つの bats に同じ `@test "setup actions do not use or save the Actions cache"`: `grep -c 'enable-cache: true'` が `0`、`grep -c 'enable-cache: false'` が `1`、`grep -c 'package-manager-cache: false'` が `1`。Use cases に1行足す。
- [ ] **Step 2: 失敗を確認する。** `bats test/bats/.github/actions/loop-execute/action.bats test/bats/.github/actions/loop-agent-once/action.bats test/bats/.github/actions/loop-install-cli/action.bats`。Expected: FAIL。
- [ ] **Step 3: 実装する。** `with` のキーは a-z の順(ORD-01)。
- [ ] **Step 4: 通ることを確認する。** Step 2 のコマンド。Expected: PASS。兄弟の箇所: `git grep -n "enable-cache: true\|cache: " -- .github/actions` で loop の他の action に残りがないことを確かめる(loop 以外は範囲外として報告)。
- [ ] **Step 5: コミットする。** `git add` で3つの `action.yml` と3つの bats、`fix(loop): disable setup caches in agent jobs`。

---

### Task 3: `loop-execute` の Push Branch を Bundle Branch に置き換える

**Files:**

- Create: `.github/actions/loop-execute/lib/bundle.sh`
- Delete: `.github/actions/loop-execute/lib/push.sh`、`test/bats/.github/actions/loop-execute/lib/push.bats`
- Modify: `.github/actions/loop-execute/action.yml:236-246`(ステップ)、`:155-157`(`has_changes` の値と説明)、出力 `bundle_file` を足す、`:254`(Build Notify Context の `HAS_CHANGES`)、`:85-87`(`github_token` の説明: `Read-only GitHub token for fetches and read-only gh calls`)
- Test: `test/bats/.github/actions/loop-execute/lib/bundle.bats`(新規)、`test/bats/.github/actions/loop-execute/action.bats`

**Interfaces:**

- Produces `bundle.sh`(実行スクリプト。`push.sh` の形)。env: `BASE_BRANCH`、`BRANCH`、`BUNDLE_FILE`、`GITHUB_OUTPUT`、`LOOP_DENYLIST_BLOCKED`(任意。既定 `false`)、`LOOP_HAS_CHANGES`、`STATUS_DIR`(任意)、`WORKTREE_PATH`。`GITHUB_TOKEN` は読まない。
  - 名前が `^[a-zA-Z0-9/_.-]+$` に合わなければ 1。denylist に当たった、または変更がなければ `has_changes=false`(denylist は今の警告を残す)。
  - それ以外は `git -C "${WORKTREE_PATH}" bundle create "${BUNDLE_FILE}" "^origin/${BASE_BRANCH}" "refs/heads/${BRANCH}"`。失敗したら段階 `bundle` で `${STATUS_DIR}/failure.json` に記録して 1。成功したら `has_changes=true`。
- Produces ステップ `Bundle Branch`(`id: bundle`)。env は上の env、`BUNDLE_FILE: ${{ runner.temp }}/loop-agent-bundle/branch.bundle`。出力 `has_changes`: `${{ steps.bundle.outputs.has_changes }}`、説明 `true when a bundle of the agent branch was written (commits not on origin/<base_branch>)`。出力 `bundle_file`: `${{ steps.bundle.outputs.has_changes == 'true' && format('{0}/loop-agent-bundle/branch.bundle', runner.temp) || '' }}`。

- [ ] **Step 1: 失敗するテストを書く(`bundle.bats`)。** 一時のリポジトリ(bare の origin に `main` を push し、`loop/x/20261018-000000` でコミット)で:
  - `@test "main rejects invalid branch names"`、`@test "main writes has_changes=false when loop produced no commits"`、`@test "main skips the bundle and warns when LOOP_DENYLIST_BLOCKED is true"`(`push.bats` の3件の移し。bundle のファイルができない)
  - `@test "main bundles only commits not on origin/base"`: `has_changes=true`、`git bundle list-heads` が `refs/heads/loop/x/20261018-000000` の1行だけ、`git bundle verify` の前提が `origin/main` の SHA、空のリポジトリに `git fetch <file> refs/heads/...` すると前提がないので失敗し、`main` を持つクローンでは通る。
  - `@test "main records a bundle failure"`: `BASE_BRANCH` が origin にない → 1、`${STATUS_DIR}/failure.json` の `failure_stage` が `bundle`。
  - `@test "main does not read GITHUB_TOKEN"`: `grep -c GITHUB_TOKEN` が `0`。
- [ ] **Step 2: `action.bats` にテストを足す。** `@test "bundle branch replaces push branch and gets no token"`: ステップ名に `Push Branch` がなく `Bundle Branch` がある、その env に `GITHUB_TOKEN` がなく `BUNDLE_FILE: ${{ runner.temp }}/loop-agent-bundle/branch.bundle` がある、Build Notify Context の `HAS_CHANGES` が `steps.bundle.outputs.has_changes`、出力 `has_changes` と `bundle_file` が Interfaces の値。
- [ ] **Step 3: 失敗を確認する。** `bats test/bats/.github/actions/loop-execute/lib/bundle.bats test/bats/.github/actions/loop-execute/action.bats`。Expected: FAIL。
- [ ] **Step 4: 実装する。** Interfaces のとおり。`git rm` で `push.sh` と `push.bats` を消す。
- [ ] **Step 5: 通ることを確認する。** `bats test/bats/.github/actions/loop-execute/`。Expected: PASS。`git grep -n "lib/push.sh" -- .github test docs ':!docs/superpowers'` の出力がない。
- [ ] **Step 6: コミットする。** `git add .github/actions/loop-execute/lib/bundle.sh .github/actions/loop-execute/action.yml test/bats/.github/actions/loop-execute/lib/bundle.bats test/bats/.github/actions/loop-execute/action.bats`(削除は Step 4 の `git rm` で stage 済み)、`feat(loop-execute): bundle the agent branch instead of pushing it`。

---

### Task 4: `failed` を outcome と state のモードに入れ、`base_branch` を出す

**Files:**

- Modify: `.github/actions/loop-finalize/lib/determine_outcome.sh`、`resolve_state_write_mode.sh`、`parse_target.sh:89-101`
- Test: `test/bats/.github/actions/loop-finalize/lib/{determine_outcome,resolve_state_write_mode,parse_target}.bats`

**Interfaces:**

- `determine_outcome <override> <agent_result> <has_changes> <verdict> <delivery> [<push_failed>]`: `$6 == "true"` なら最初に `error`(override より先)。省略は `false`。
- `resolve_state_write_mode <verdict> <has_changes> <delivery> [<push_failed>]`: `$4 == "true"` なら `metadata`。
- `parse_target.sh` は `base_branch=<(if .mode == "pull_request" then .base.branch else .to.branch end) // "">` を足す(空を許す。必要かは Task 5 が決める)。出力の行の並びは `base_branch`、`target_key`、`pr_base_branch`、`to_branch`。

- [ ] **Step 1: 失敗するテストを書く。** `@test "push failure is error even with an outcome override"`(`determine_outcome watch success true APPROVE pr_create true` → `error`)、`@test "push failure records metadata"`(`resolve_state_write_mode APPROVE true pr_push true` → `metadata`、`pr_create` も `metadata`)、`@test "writes base_branch from base.branch for pull_request and to.branch otherwise"`(2件)。既存の出力の完全一致のテストは `base_branch=` の行を足して直す。
- [ ] **Step 2: 失敗を確認する。** `bats test/bats/.github/actions/loop-finalize/lib/determine_outcome.bats test/bats/.github/actions/loop-finalize/lib/resolve_state_write_mode.bats test/bats/.github/actions/loop-finalize/lib/parse_target.bats`。Expected: FAIL。
- [ ] **Step 3: 実装する。** ヘッダーの Design Rules と関数のドキュメントに `push_failed` を書く。
- [ ] **Step 4: 通ることを確認する。** Step 2 のコマンドと `bats test/bats/github-actions/loop-outcome.bats`。Expected: PASS。
- [ ] **Step 5: コミットする。** 3つのスクリプトと3つの bats を `git add`、`feat(loop-finalize): let a failed agent push force error and metadata state`。

---

### Task 5: `push_agent_branch.sh`

**Files:**

- Create: `.github/actions/loop-finalize/lib/push_agent_branch.sh`
- Test: `test/bats/.github/actions/loop-finalize/lib/push_agent_branch.bats`(新規。git の組み立ては `push_target.bats:21-36` の形)

**Interfaces:**

- Consumes `edit_paths.sh`(Task 1)、`failure_record.sh` の `loop_failure_record`。source は `$(cd "$(dirname "${BASH_SOURCE[0]}")/../../lib/loop" && pwd)`。
- Produces 実行スクリプト(`push_target.sh` の形)。env: `AGENT_BRANCH`、`AGENT_BRANCH_PREFIX`、`AGENT_BUNDLE_DIR`、`AGENT_EDIT_ALLOWLIST`、`AGENT_EDIT_DENYLIST`、`AGENT_MAKER_SKILL_NAME`、`AGENT_RESULT`、`BASE_BRANCH`、`GITHUB_OUTPUT`、`GITHUB_TOKEN`、`HAS_CHANGES`、`LOOP_FAILURE_FILE`(必須)、`STATE_BRANCH`、`TARGET_JSON`、`TO_BRANCH`。
- 出力(常に3行): `branch=<検証済みの名前 or 空>`、`pushed=true|false`、`failed=true|false`。終了コードは `LOOP_FAILURE_FILE` か `GITHUB_OUTPUT` がないときだけ 1、ほかは 0。
- 関数(a-z):
  - `fail_push <message>`: `loop_failure_record push`、`::error::` を出し、`branch=` は検証済みならその名前、`pushed=false`、`failed=true` を書いて `exit 0`。
  - `list_changed_files <from_ref> <base_branch> <branch>`: `from_ref` があれば `git diff --name-only --no-renames "<from_ref>..<branch>"`、なければ `"origin/<base_branch>...<branch>"`。git が失敗したら 1(呼び手は `fail_push`)。
  - `collect_workflow_violations <files>`: `.github/workflows/` で始まるファイルのうち、`.github/` で始まる allowlist のパターンのどれにも `path_matches_glob` で当たらないもの。
  - `validate_agent_branch <branch> <prefix> <skill> <to_branch> <state_branch>`: Global Constraints の規則。`prefix` か `skill` が空なら不合格。
  - `main`: 次の順。
    1. `AGENT_BRANCH` が空 → `branch=`、`pushed=false`、`failed=false` で終わる。
    2. 名前の検証 → 不合格は `fail_push`。
    3. `AGENT_RESULT != success` か `HAS_CHANGES != true` → `pushed=false`、`failed=false`。
    4. `${AGENT_BUNDLE_DIR}/branch.bundle` がない、`BASE_BRANCH` が空 → `fail_push`。
    5. `configure_git_auth` 相当(`push_target.sh:53-59` と同じ3行)、`git fetch origin "<base>"`、`git bundle verify <file>`、`git fetch <file> "refs/heads/<b>:refs/heads/<b>"`。
    6. `from.ref`(`jq -r '.from.ref // ""'`)が空でなければ `git merge-base --is-ancestor <from_ref> refs/heads/<b>`。
    7. `apply_platform_denylist_default`、差分のファイルに denylist → allowlist → workflow の順で違反を集め、あれば `fail_push`(メッセージに最初の数件のパス)。
    8. `git ls-remote --exit-code origin "refs/heads/<b>"` が見つかれば `fail_push`。
    9. `git push origin "refs/heads/<b>:refs/heads/<b>"`(force なし)。失敗は `fail_push`(stderr は `loop_failure_record` がマスクする)。成功で `pushed=true`、`failed=false`。

- [ ] **Step 1: 失敗するテストを書く。** 組み立て: bare の origin に `main`(と、必要なテストで `feature/pr-head`)。エージェント側のクローンで `loop/changelog/20261018-123456` を作ってコミットし、Task 3 と同じ形で `${AGENT_BUNDLE_DIR}/branch.bundle` を作る。finalize 側は別のクローン。補助関数 `run_push` は既定の env(`AGENT_BRANCH_PREFIX=loop`、`AGENT_MAKER_SKILL_NAME=changelog`、`AGENT_RESULT=success`、`HAS_CHANGES=true`、`BASE_BRANCH=main`、`TO_BRANCH=main`、`STATE_BRANCH=main`、`TARGET_JSON='{}'`、`GITHUB_TOKEN=dummy`)を上書きできる形で `bash "${SCRIPT}"` を実行し、出力の3行と記録の `failure_stage` を読む。テスト(a-z):
  - `a bundle with other refs imports only the agent branch`: 別の ref を足した bundle で成功し、origin に別の ref がない。
  - `a descendant tip of from.ref is pushed`、`a tip that is not a descendant of from.ref fails`、`an empty from.ref diffs against origin/base`
  - `a force-pushed PR head still verifies against base`: bundle を作った後に origin の `feature/pr-head` を force-push し、`from.ref` が空なら成功。`from.ref` が消えた SHA なら `failed=true`(Review Focus 4)。
  - `allowlist and denylist are re-applied`: allowlist `docs/**` で `src/a.sh` の変更 → 失敗。denylist 空で `config/.env` → 失敗(プラットフォームの既定)。
  - `an existing remote branch fails without force`: 同名のブランチを先に origin に置く → 失敗、origin のブランチは変わらない。
  - `changes under .loop/ are checked like any other path`: allowlist `docs/**` で `.loop/x.json` → 失敗。
  - `has_changes true with no bundle fails`(取得の失敗と同じ)
  - `invalid branch names fail`: `main`、`loop/changelog/../x`、`loop/other/20261018-123456`、`loop/changelog/2026-10-18`、`STATE_BRANCH` と同じ名前、`TO_BRANCH` と同じ名前、`AGENT_BRANCH_PREFIX` が空。すべて `failed=true`、`branch=`。
  - `nothing happens for an empty branch`: `failed=false`、`pushed=false`、記録なし。
  - `nothing is pushed when the agent failed or has no changes`: `AGENT_RESULT=failure`(bundle あり)と `HAS_CHANGES=false` で `pushed=false`・`failed=false`、`branch` は検証済みの名前。
  - `pushes a valid bundle and updates origin/<branch>`: `pushed=true`、origin の ref の SHA が bundle の先端、finalize 側の `refs/remotes/origin/<b>` もある。
  - `renaming a denylisted file is rejected`: base の `secrets.txt` を `docs/notes.txt` に `git mv`、allowlist `docs/**` → 失敗。
  - `workflow changes need a .github/ allowlist pattern`: `.github/workflows/x.yaml` の変更が、allowlist `.github/**` で成功、`**` で失敗、空で失敗。
- [ ] **Step 2: 失敗を確認する。** `bats test/bats/.github/actions/loop-finalize/lib/push_agent_branch.bats`。Expected: FAIL(スクリプトがない)。
- [ ] **Step 3: 実装する。** Interfaces のとおり。ヘッダーの Design Rules に、順序、force しないこと、`.loop/` を除外しないこと、出力の意味を書く。
- [ ] **Step 4: 通ることを確認する。** Step 2 のコマンドと `bats test/bats/.github/actions/loop-finalize/lib/`。Expected: PASS。
- [ ] **Step 5: コミットする。** `git add .github/actions/loop-finalize/lib/push_agent_branch.sh test/bats/.github/actions/loop-finalize/lib/push_agent_branch.bats`、`feat(loop-finalize): verify and push the agent branch from its bundle`。

---

### Task 6: `loop-finalize/action.yml` に Push Agent Branch をつなぐ

**Files:**

- Modify: `.github/actions/loop-finalize/action.yml`
  - 入力を足す(a-z の位置): `agent_branch_prefix`、`agent_bundle_dir`、`agent_edit_allowlist`、`agent_edit_denylist`、`agent_maker_skill_name`(すべて `default: ""`、`required: false`)。`execute_branch`(`:31-34`)を消す(下の「spec との差」)。`github_token` の説明に「agent branch push」を足す。
  - Parse Target(`:164-171`)の後に Push Agent Branch(`id: agent_push`、`if` なし、`run: bash "${GITHUB_ACTION_PATH}/lib/push_agent_branch.sh"`、env は Task 5 の env。`AGENT_BRANCH: ${{ inputs.branch }}`、`BASE_BRANCH: ${{ steps.target.outputs.base_branch }}`、`TO_BRANCH: ${{ steps.target.outputs.to_branch }}`、`LOOP_FAILURE_FILE: ${{ runner.temp }}/loop-finalize-failure.json`)。
  - Determine Outcome(`:185-199`)と Resolve State Write Mode(`:201-212`)に `PUSH_FAILED: ${{ steps.agent_push.outputs.failed }}` を渡し、6番目・4番目の引数にする。
  - Run Finalize Hook(`:215`): `if: inputs.finalize_script != '' && steps.agent_push.outputs.failed != 'true'`、`EXECUTE_BRANCH: ${{ steps.agent_push.outputs.branch }}`(`:219`)。
  - Deliver Message(`:235-238`): 条件に `&& steps.agent_push.outputs.failed != 'true'`。
  - Push to Target Branch(`:269-273`)と Create PR(`:283-287`): `inputs.has_changes == 'true' && inputs.branch != ''` を `steps.agent_push.outputs.pushed == 'true'` に置き換え、`AGENT_BRANCH: ${{ steps.agent_push.outputs.branch }}`(`:276`、`:290`)。
  - Delete Agent Branch(`:342`、`:345`): `if: always() && steps.agent_push.outputs.pushed == 'true' && (inputs.verdict == 'REJECT' || inputs.delivery == 'none' || inputs.delivery == 'issue_comment' || inputs.delivery == 'pr_review')`、`AGENT_BRANCH: ${{ steps.agent_push.outputs.branch }}`。
  - Delete Agent Branch と Resolve Run Outcome の間に:

    ```yaml
    - name: Fail Agent Push
      if: always() && steps.agent_push.outputs.failed == 'true'
      shell: bash
      run: |
        echo "::error::loop-finalize: the agent branch was not pushed (see the push failure record)"
        exit 1
    ```

- Test: `test/bats/.github/actions/loop-finalize/action_delivery.bats`、`action_finalize_hook_env.bats`

**Interfaces:**

- Consumes `push_agent_branch.sh`(Task 5)、`determine_outcome`・`resolve_state_write_mode` の新しい引数と `base_branch`(Task 4)。
- Produces 入力5つ(Task 7 が渡す)。

- [ ] **Step 1: 失敗するテストを書く(`action_delivery.bats`)。**
  - `action inputs are the delivery contract in alphabetical order`(`:64-76`): `agent_branch_prefix agent_bundle_dir agent_edit_allowlist agent_edit_denylist` を `agent_engine` の前後の a-z の位置に、`agent_maker_skill_name` を `agent_result` の前に足し、`execute_branch` を消す。
  - `steps run in spec order`(`:159-164`)の期待値: `Materialize Message, Parse Target, Push Agent Branch, Resolve State File, Determine Outcome, Resolve State Write Mode, Run Finalize Hook, Deliver Message, Push to Target Branch, Create PR, Enable Auto-Merge, Write State, Delete Agent Branch, Fail Agent Push, Resolve Run Outcome, Export Failure Diagnostics`。
  - `delete agent branch keys on REJECT or a delivery that never lands the branch`(`:94-97`)の期待値を上の `if` にする。
  - `every failure record step uses the same LOOP_FAILURE_FILE`(`:200`)に Push Agent Branch を足す(件数 `5`)。
  - 足す:
    - `@test "no step after push agent branch reads inputs.branch"`: Push Agent Branch の env の `AGENT_BRANCH: ${{ inputs.branch }}` 以外に `inputs.branch` が0件(Review Focus 1)。
    - `@test "push agent branch failure gates the hook, delivery, landing and deletion"`: `step_if` で Run Finalize Hook と Deliver Message が `steps.agent_push.outputs.failed != 'true'` を含み、Push to Target Branch・Create PR・Delete Agent Branch が `steps.agent_push.outputs.pushed == 'true'` を含み `inputs.has_changes` を含まない。
    - `@test "fail agent push runs after delete agent branch and before resolve run outcome"`: `if` が `always() && steps.agent_push.outputs.failed == 'true'`、`run` が `exit 1` を含む。
    - `@test "determine outcome and state mode receive the push failure"`: 両方の env に `PUSH_FAILED: ${{ steps.agent_push.outputs.failed }}`。
    - `@test "a recorded push failure resolves to error"`: `resolve_run_outcome.sh` を `ACTION_STATUS=failure`、`DELIVERED_OUTCOME=error`、記録 `push` で実行して `outcome=error`、記録の段階が `push` のまま(既存の `resolve run outcome runs the lib script` の形)。
  - `action_finalize_hook_env.bats`: `EXECUTE_BRANCH: ${{ steps.agent_push.outputs.branch }}` と、`finalize hook runs whenever finalize_script is set, regardless of delivery`(`:66`)の期待値を新しい `if` にする(変更がなくても ledger の hook が動くこと = `has_changes` を見ないこと)。
- [ ] **Step 2: 失敗を確認する。** `bats test/bats/.github/actions/loop-finalize/`。Expected: FAIL。
- [ ] **Step 3: 実装する。** Files のとおり。env と入力は a-z の順(ORD-01)。
- [ ] **Step 4: 通ることを確認する。** `bats test/bats/.github/actions/loop-finalize/ test/bats/github-actions/loop-delete-rejected-branch.bats test/bats/github-actions/loop-delivery.bats`。Expected: PASS。`test/bats/github-actions/loop-caller-parity.bats` は、`ci-loop-agent.yaml` がまだ `execute_branch` を渡すので `Every with: key ...` が落ちる。Task 7 で直す(この Task では実行しない)。
- [ ] **Step 5: コミットする。** `git add .github/actions/loop-finalize/action.yml test/bats/.github/actions/loop-finalize/action_delivery.bats test/bats/.github/actions/loop-finalize/action_finalize_hook_env.bats`、`feat(loop-finalize): push the agent branch in finalize and gate later steps on it`。

---

### Task 7: `ci-loop-agent.yaml` のエージェントのジョブから書き込みの認証情報をなくす

**Files:**

- Modify: `.github/workflows/ci-loop-agent.yaml`
  - `:9-12`(Token resolution のコメント: agent ジョブは `github.token`(読み取り)だけ、finalize ジョブだけが解決する)、`:247-255`(`BOT_APP_*`・`GH_TOKEN` の説明に「finalize jobs only」)
  - agent-l1: `:274-276`(権限)、`:284-291`(Resolve GitHub Token を削除)、`:305`(`github_token: ${{ github.token }}`)
  - agent-l2: `:401-405`(権限)、`:420-427`(削除)、`:431-451`(Parse Target に `bundle_artifact_name`)、`:462`、`:490`(`${{ github.token }}`)、`:464-495` の後に Upload Agent Bundle
  - finalize-l2: `:528-546`(Parse Target に `bundle_artifact_name`)、Resolve GitHub Token の後・Finalize の前に Download Agent Bundle、Finalize の `with`(`:566-598`): `execute_branch`(`:574`)を消し、`agent_branch_prefix`・`agent_bundle_dir`・`agent_edit_allowlist`・`agent_edit_denylist`・`agent_maker_skill_name` を足す
- Modify: `.github/actions/loop-worktree-setup/action.yml:24-26`(`github_token` の説明: `Read-only GitHub token for fetch`)
- Test: `test/bats/github-actions/loop-caller-parity.bats`(`:6-23` の Use cases、`:205-215`、`:228-239`、`:789-800`、テストを足す)

**Interfaces:**

- Parse Target(両方)の追加の行(agent-l2 は `key` が必ずある。finalize-l2 は `key` が空なら空の名前):

  ```bash
  bundle_artifact_name="loop-agent-bundle-${GITHUB_RUN_ATTEMPT}-$(printf '%s' "${key}" | sha256sum | cut -c1-16)"
  ```

  出力は a-z の順で `bundle_artifact_name` が先頭。

- agent-l2 の追加のステップ:

  ```yaml
  - name: Upload Agent Bundle
    if: steps.execute.outputs.has_changes == 'true'
    uses: actions/upload-artifact@cf430e030ddbb5b0abf93d22962f4752f3646cd9 # v7.0.2
    with:
      if-no-files-found: error
      name: ${{ steps.target.outputs.bundle_artifact_name }}
      path: ${{ steps.execute.outputs.bundle_file }}
      retention-days: 1
  ```

- finalize-l2 の追加のステップ(`actions/download-artifact` は既存の pin `9000827ccba6bdab643e8b6fd33ac0654aef8333 # v8.0.2`):

  ```yaml
  - name: Download Agent Bundle
    continue-on-error: true
    if: needs.agent-l2.result == 'success' && needs.agent-l2.outputs.has_changes == 'true'
    uses: actions/download-artifact@9000827ccba6bdab643e8b6fd33ac0654aef8333 # v8.0.2
    with:
      name: ${{ steps.target.outputs.bundle_artifact_name }}
      path: ${{ runner.temp }}/loop-agent-bundle
  ```

- Finalize の追加の `with`: `agent_branch_prefix: ${{ inputs.agent_branch_prefix }}`、`agent_bundle_dir: ${{ runner.temp }}/loop-agent-bundle`、`agent_edit_allowlist: ${{ inputs.agent_edit_allowlist }}`、`agent_edit_denylist: ${{ inputs.agent_edit_denylist }}`、`agent_maker_skill_name: ${{ inputs.agent_maker_skill_name }}`。finalize-l1 には渡さない(`branch` が空)。

- [ ] **Step 1: 失敗するテストを書く(`loop-caller-parity.bats`)。**
  - `@test "agent jobs hold no write credentials"`: `agent-l1`・`agent-l2` の `job_block` に `loop-resolve-push-token`、`secrets.BOT_APP_`、`secrets.GH_TOKEN`、`resolve_github_token` がない。`permissions` の行が、agent-l1 は `contents: read`・`copilot-requests: write ...`・`issues: read`・`pull-requests: read` の4行、agent-l2 はそれに `actions: read` の5行(`grep -E '^      [a-z-]+: '` を permissions のブロックで取り、完全一致)。`github_token:` の行がすべて `${{ github.token }}`(agent-l1 は1件、agent-l2 は2件)。
  - `@test "both parse target steps name the bundle artifact the same way"`: 両方の Parse Target を `GITHUB_RUN_ATTEMPT=2` と key `pull_request:7` の target_json で実行し、`bundle_artifact_name=loop-agent-bundle-2-d4cedacd722526b8` が両方にある。
  - `@test "agent-l2 uploads the bundle without overwrite"`: Upload Agent Bundle の `if`・`with` が Interfaces と一致し、`overwrite` がない。
  - `@test "finalize-l2 downloads the bundle and passes the push inputs"`: Download Agent Bundle の `if`・`continue-on-error: true`、Finalize の `with` に5行があり `execute_branch` がない。
  - 既存の直し: `:228-239` と `:789-800` の出力の期待値に `bundle_artifact_name=...` を足す(`GITHUB_RUN_ATTEMPT=1` を渡し、`integration:main` は `138c728d71ab409c`)。`:205` の名前の `no issues write` は残し、上の新しいテストが権限を見る。Use cases に「agent jobs hold only read GitHub permissions and no App or GH_TOKEN secret; agent-l2 hands the branch to finalize-l2 as a bundle artifact」を足す。
- [ ] **Step 2: 失敗を確認する。** `bats test/bats/github-actions/loop-caller-parity.bats`。Expected: FAIL(新しいテスト、出力の期待値、Task 6 の `execute_branch`)。
- [ ] **Step 3: 実装する。** Files と Interfaces のとおり。`with` と `permissions` は a-z の順(ORD-01)。
- [ ] **Step 4: 通ることを確認する。** `bats test/bats/github-actions/loop-caller-parity.bats test/bats/.github/actions/loop-worktree-setup/ test/bats/scripts/self/ci/loop_input_topology.bats` と `python3 -I scripts/self/ci/loop_input_topology.py . > /dev/null; echo $?`。Expected: PASS、`0`。
- [ ] **Step 5: コミットする。** `git add .github/workflows/ci-loop-agent.yaml .github/actions/loop-worktree-setup/action.yml test/bats/github-actions/loop-caller-parity.bats`、`feat(loop): remove write credentials from agent jobs and hand the branch over as a bundle`。

---

### Task 8: caller の許可リストから書き込みのコマンドを外す

**Files:**

- Modify: `.github/workflows/on-loop-github-pr-revise.yaml:120-124`(`Bash(gh api:*)` → `Bash(gh api -X GET:*)`、`Bash(gh pr comment:*)` を削除)
- Modify: `.github/workflows/on-loop-github-issue-autofix.yaml:74`、`.github/workflows/on-loop-ci-sweeper.yaml:109`(`Bash(gh api:*)` → `Bash(gh api -X GET:*)`)
- Modify: `on-loop-ci-sweeper.yaml` の `agent_edit_denylist omitted` のコメント(`lib/paths.sh DEFAULT_EXECUTE_DENYLIST` → `lib/loop/edit_paths.sh`)
- Test: `test/bats/github-actions/loop-caller-parity.bats`(`:1028-1041` の隣)

**Interfaces:** なし。

- [ ] **Step 1: 失敗するテストを書く。** `@test "L2 callers grant no write gh commands to the agent"`: pr-revise・autofix・ci-sweeper・pr-review の `triage_block "${wf}" agent_tool_allowlist` に `Bash(gh api:*)`、`gh pr comment`、`gh issue comment`、`gh issue edit`、`gh label create` がない(`triage caller grants no write gh commands to the agent` と同じ形)。
- [ ] **Step 2: 失敗を確認する。** `bats test/bats/github-actions/loop-caller-parity.bats`。Expected: FAIL。
- [ ] **Step 3: 実装する。** 行の並びは各ファイルの今の並びを保つ。
- [ ] **Step 4: 通ることを確認する。** Step 2 のコマンド。Expected: PASS。兄弟の箇所: `git grep -n "Bash(gh api:\*)" -- .github/workflows example` の残りを報告する(`example/` は範囲外として記録)。
- [ ] **Step 5: コミットする。** 3つの caller と bats を `git add`、`chore(loop): grant L2 agents read-only gh commands`。

---

### Task 9: docs

**Files:**

- Modify: `docs/reference/specification.md:399`(`loop-execute`: push ではなく bundle を作り、`has_changes` は bundle を作ったこと、`failure_stage` に `bundle`)、`:400`(`loop-finalize`: Push Agent Branch がブランチ名と bundle を検証して push する)、`:486-489`(`failure_stage` の例に `bundle`)、`:493-505`(入力の表に `agent_branch_prefix`、`agent_bundle_dir`、`agent_edit_allowlist`、`agent_edit_denylist`、`agent_maker_skill_name`。`finalize_script` の行の `EXECUTE_BRANCH` は検証済みの名前)
- Modify: `docs/explanation/loop-engineering/loop-caller-reusable-design.md:308-316`(GitHub token resolution: agent ジョブは解決しない。`github.token` の読み取りだけ)、`docs/explanation/loop-engineering/workflows/loop-caller-inputs-reference.md:53`
- Modify: `docs/explanation/loop-engineering/loop-engineering-design.md:513`、`:745`、`:766`(`has_changes` の意味、push は finalize)
- Modify: `docs/explanation/github-workflows-design.md:59-70`(copilot の `AGENT_TOKEN` は Copilot Requests だけの fine-grained PAT にする)
- Modify: `docs/explanation/loop-engineering/workflows/loop-ci-sweeper-workflow-design.md`、`loop-github-pr-revise-workflow-design.md`、`loop-github-issue-autofix-workflow-design.md`(`agent_tool_allowlist` の記述と、ci-sweeper の `.github/**` が push の workflow を動かすこと)。該当行は `git grep -n "gh api\|gh pr comment\|\.github/\*\*" -- <file>` で決める。
- Modify: `docs/explanation/loop-engineering/index.md`(agent ジョブに書き込みの認証情報がないことを1文。該当の節は `git grep -n "agent" -- docs/explanation/loop-engineering/index.md` で決める)
- Modify: `.github/actions/loop-run-log/action.yml:23`(段階の例に `bundle`)
- 変えない: `CHANGELOG.md`(リリースのとき)、`docs/superpowers/`

**Interfaces:** なし。

- [ ] **Step 1: docs を直す。** DOC-00 に従い該当の行だけを変える。表の桁揃えは prettier のフックに任せる。
- [ ] **Step 2: 残りを確かめる。** `git grep -n -e "lib/push.sh" -e "Push Branch" -e "execute_branch" -- docs .github ':!docs/superpowers'`。Expected: 出力がない。
- [ ] **Step 3: コミットする。** 変えたファイルを列挙して `git add`、`docs(loop): document agent jobs without write credentials and the finalize push`。

---

### Task 10: 全体の確認

**Files:** なし(直しが要れば原因の Task のファイルを直して別のコミットにする)。

- [ ] **Step 1: 全部の bats。** `mkdir -p tmp && bats -r test/bats > tmp/bats-credential-isolation.txt 2>&1; echo $?`。Expected: `0`。確認の後 `rm -f tmp/bats-credential-isolation.txt`。
- [ ] **Step 2: 秘密情報の参照。** `awk '/^  agent-l[12]:/{f=1} /^  finalize-l[12]:/{f=0} f' .github/workflows/ci-loop-agent.yaml | grep -n -e 'secrets\.' -e 'write'`。Expected: `secrets.AGENT_TOKEN` と `copilot-requests: write` の行だけ。
- [ ] **Step 3: 作業ツリー。** `git status --porcelain`。Expected: 作業の前からある5つだけ。
- [ ] **Step 4: lint。** actionlint、ghalint、zizmor、shellcheck、markdownlint は Stop フックの結果を見る。直接は実行しない。

---

## リリースと dogfood(手動。この plan の範囲外)

1. 明示の承認を得てから、`loop-execute`・`loop-finalize`・`loop-agent-once`・`loop-install-cli`・`loop-worktree-setup` と `ci-loop-agent.yaml` の pin を1回で上げる(`ci-loop-agent.yaml` の新しい `with` は新しい `loop-finalize` を前提にする)。CHANGELOG に、`has_changes` の意味、`execute_branch` の削除、`bundle` の段階、許可リストの変更を書く。
2. dogfood(使い捨てのブランチ。spec「検証」): `pr_create`(changelog)、`pr_push`(pr-revise)、`pr_review`(pr-review)が現在と同じブランチと PR を作る。GitHub の MCP サーバが `github.token` で認証できるか(Review Focus 5)。agent のジョブのプロセスの環境と `_temp` を App の秘密鍵のハッシュで grep して見つからないこと。既存の caller の `.loop/` のコミット(Review Focus 3)。

## Self-review(writing-plans のチェックリスト)

- **spec の網羅:** 第1節(権限、秘密情報、`github.token`、キャッシュ、MCP)→ Task 2, 7、dogfood。第2節 Bundle Branch → Task 3。artifact の名前と上げ下ろし → Task 7。ブランチ名の検証と Push Agent Branch の 1〜6 → Task 5。失敗の扱い(記録、`failed` の優先、`metadata`、hook と配信、`pushed`、Delete の `if`、fail のステップ)→ Task 4, 6。`paths.sh` の移動と `--no-renames` → Task 1。第3節 → Task 8。検証の bats → Task 1〜8。docs → Task 9。
- **プレースホルダー:** docs の一部の行は `git grep` で決める(Task 9)。ほかは行番号で決めた。
- **名前の一貫性:** `edit_paths.sh` / `bundle.sh` / `push_agent_branch.sh` / `agent_push` / `pushed` / `failed` / `bundle_artifact_name` / `bundle_file` / `agent_bundle_dir` / `Fail Agent Push` / `branch.bundle` は全 Task で同じ綴り。
- **分量:** スクリプトの本体は書かず、順序、出力、テストの名前と期待値だけにした。

## spec との差(HEAD `199f957d` で確かめた値)

- 行番号: `ci-loop-agent.yaml:279-304` → agent-l1 の Resolve GitHub Token `:284-291`・`github_token` `:305`。`:388-394` → agent-l2 の `:420-427`。`:536`・`:539` → `:571`・`:574`。`:425-426` → `:458-459`。`:412` → `:445`。`loop-execute/action.yml:196` → `GITHUB_TOKEN` は `:221`、push の env `:241`。`loop-agent-once/action.yml:71`・`:78` → `setup-node` `:66`、`enable-cache` `:73`。`loop-finalize/action.yml:244`・`:318` → `LOOP_FAILURE_FILE` `:246`・`:295`・`:374`・`:382`。Create PR `:232-236` → `:281-307`。auto-merge `:258-268` → `:309-319`。`.mcp.json:25` → HEAD の `:13-18`(作業ツリーの未コミットの変更で `:25` になっている)。`agent.sh:445` → `:447`。`loop-detect/action.yml:190-192` → `:196-202`。`verifier.sh:232` → fetch `:232`、diff `:233`。
- `execute_branch`: spec は「hook の `EXECUTE_BRANCH` は検証を通った名前」とするが、`loop-finalize` には `execute_branch` の上書きがある(`:31`、`:219`)。上書きを残すと検証を迂回できるので、この plan は入力を削除する(破壊的。呼ぶのは `ci-loop-agent.yaml:574` だけ)。
- bundle の作成の失敗の段階名は spec にない。この plan は `bundle` とした(`loop-run-log` と specification の例に足す)。
- `base_branch` が空のときの扱いは spec にない。push が要るときだけ `failed`(Task 5 の 4)。
- 「ほかの ref を含む bundle」の期待は spec にない。2 の「そのブランチだけを取り込む」から、失敗ではなくそのブランチだけを push するとした。
- `agent_branch_prefix` と `agent_maker_skill_name` が空で `branch` が空でないときは spec にない。不合格(`failed`)とした。`ci-loop-agent.yaml` の `agent_maker_skill_name` は既定 `""`(`:97-101`)。
- Push Agent Branch の位置は「Parse Target の後、Determine Outcome の前」で、間に Resolve State File がある。この plan は Parse Target の直後に置いた。
- GitHub の MCP サーバが `github.token` を受け付けないときの「MCP なしで続ける」仕組みは spec にもコードにもない。dogfood で確かめ、必要なら別に扱う。
