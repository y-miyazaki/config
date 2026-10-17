# Loop `github-pr-review` 実装計画

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** PR の作成時に 1 回だけ、根拠つきの自動レビューを `COMMENT` として投稿する L2 loop `github-pr-review` を作る。

**Architecture:** `pull_request_target` で起動し、`ci-loop-caller-entity`(L2、`write_target: report`、`delivery: none`)に載せる。maker はレビュー案を JSON レポートに書くだけで、Checker(`loop-verifier`)が APPROVE したときだけ、finalize の `domain_persistence_script`(`post_review.sh`)が根拠を機械的に検証して投稿する。Meta はプラットフォーム(`finalize-l2`)が追記する。

**Tech Stack:** Bash(`set -euo pipefail`、`scripts/lib/all.sh` の JSON ヘルパー)、jq、gh CLI、GitHub Actions(reusable workflow / composite action)、Bats、APM スキル(`SKILL.md` + `references/` + `assets/` + `evals/`)。

**Spec:** [Loop `github-pr-review` 設計](../specs/2026-10-17-loop-pr-review-design.md)

## Global Constraints

- スキル本体(`SKILL.md`、`references/`、`assets/`)は英語。`.apm/packages/**` にはエンジン固有(`/code-review`)・リポジトリ固有(`apm.lock.yaml`、`.agents/` 等)の記述を書かない(D6)。
- 投稿の見出し・フィールド名・重大度・固定の案内文・マーカー・Meta は英語。エージェントが書く文面は回答言語。回答言語は `## Constraints` の `response_language` > PR のタイトル・本文の言語 > `en`(D23)。
- 重大度は `Critical` / `Warning` / `Suggestion` のみ(D10)。Pre-existing は指摘しない(D14)。
- 根拠の種類は `rule` / `criteria` / `bug` のみ(D4)。`rule` / `criteria` は base に実在するファイルの原文引用が必須。
- 投稿は `COMMENT` のみ。承認・Request changes は投稿しない(D3)。
- リンク: 行は SHA 固定の `https://github.com/{owner}/{repo}/blob/{full-sha}/{path}#L{start}-L{end}`。根拠は base の SHA、差分の行は head の SHA。PR / Issue は `#N`(D24)。
- マーカー文字列: `<!-- github-pr-review:v1 -->`(D9)。
- handoff_key: `entity:pr:<n>`。レポートのパス: `.loop-review/pr-<n>.json`。
- 新規・変更するシェルスクリプトは Bats を対にする(`.github/workflows/CLAUDE.md` の Verification、TEST-00)。Edit で `.sh` を編集した後は `shfmt -w` を直接実行する(`CLAUDE.md`)。
- 配布物(`.github/actions/**`、`ci-*`)は SHA ピン。`ci-*` から `./.github/...` を参照しない。`on-*` は dogfood 中に `./.github/workflows/...` を参照してよい。
- `.apm/packages/` を編集したら、同期先(`.agents/`、`.claude/` 等)は Stop フックの `sync_apm_artifacts.sh` が更新する。手で編集しない。
- 権限リストを変更する場合は 4 ファイル(`.claude/settings.json`、`.cursor/cli.json`、`.cursor/permissions.json`、`.lean-ctx.toml`)を同時に更新する。

## Review Focus

1. **`delivery: none` の既存 L2 以外への波及** — P1 は `open_pr` / `push` / `push_head` の push を変えてはならない。Task 1 に 3 方式すべての回帰テストを置く。
2. **引用の部分一致・空白差** — 引用が base のファイルに完全一致しない(改行・前後空白・全角)場合、指摘を投稿してはならない。Task 5 に「空白だけ違う引用は捨てる」テストを置く。
3. **差分外の行を `in_diff: true` にした指摘** — GitHub API は差分外の行へのインラインコメントを 422 で拒否し、レビュー全体が失敗する。Task 5 に「差分外の行は本文へ回し、投稿は成功する」テストを置く。
4. **指摘ゼロの PR** — 「指摘なし」を明記した本文を投稿し、マーカーも付く(再実行で二重にならない)。Task 5 にテストを置く。
5. **draft → ready の往復・手動再実行** — マーカーがあれば skip、`force: true` なら skip しない。Task 4 にテストを置く。

---

## ファイル構成

| ファイル                                                                        | 責務                                                           | Task |
| ------------------------------------------------------------------------------- | -------------------------------------------------------------- | ---- |
| `.github/actions/loop-finalize/action.yml`                                      | P1: `none` で push しない。P2: `none` + APPROVE でブランチ削除 | 1    |
| `.github/actions/loop-finalize/lib/should_push_target.sh`(新規)                 | push 判定の純関数                                              | 1    |
| `.github/actions/loop-finalize/lib/should_delete_rejected_branch.sh`            | 削除判定に `finalize_strategy` を追加                          | 1    |
| `.github/actions/lib/loop/entity_meta.sh`                                       | P3: PR レビュー本文への Meta 追記と `entity_pr_number`         | 2    |
| `.github/workflows/ci-loop-agent.yaml`                                          | `finalize-l2` に Meta 追記ステップ                             | 2    |
| `.apm/packages/github/.apm/skills/github-pr-review/scripts/detect_pr_review.sh` | Detect: 機械的な事実                                           | 4    |
| `.apm/packages/github/.apm/skills/github-pr-review/scripts/post_review.sh`      | 検証と投稿                                                     | 5    |
| `.apm/packages/github/.apm/skills/github-pr-review/SKILL.md` ほか               | スキル本体                                                     | 6    |
| `.apm/packages/github/.apm/skills/github-pr-revise/`                            | D19: PR 全体の文脈                                             | 7    |
| `.github/workflows/on-loop-github-pr-review.yaml`                               | caller                                                         | 8    |
| `docs/...`                                                                      | 設計文書と一覧                                                 | 9    |

---

### Task 1: `loop-finalize` の `delivery: none` 対応(P1、P2)

**Files:**

- Create: `.github/actions/loop-finalize/lib/should_push_target.sh`
- Modify: `.github/actions/loop-finalize/lib/should_delete_rejected_branch.sh`
- Modify: `.github/actions/loop-finalize/action.yml`(「Push to Target Branch」の `if:`、「Delete Branch on Rejection」の `if:` と env)
- Test: `test/bats/.github/actions/loop-finalize/lib/should_push_target.bats`(新規)、`test/bats/.github/actions/loop-finalize/lib/should_delete_rejected_branch.bats`(新規)

**Interfaces:**

- Produces: `should_push_target VERDICT HAS_CHANGES BRANCH FINALIZE_STRATEGY` → 0(push する)/ 1。`should_delete_rejected_branch VERDICT HAS_CHANGES [FINALIZE_STRATEGY]` → 0(削除する)/ 1。第 3 引数省略時は従来どおり。

- [ ] **Step 1: 失敗するテストを書く**

`should_push_target.bats`(`entity_meta.bats` と同じ `support/common.bash` 読み込み):

```bash
@test "pushes on APPROVE with changes for push and push_head" {
    run should_push_target APPROVE true loop/x/1 push;      [ "$status" -eq 0 ]
    run should_push_target APPROVE true loop/x/1 push_head; [ "$status" -eq 0 ]
}
@test "does not push for open_pr or none" {
    run should_push_target APPROVE true loop/x/1 open_pr; [ "$status" -eq 1 ]
    run should_push_target APPROVE true loop/x/1 none;    [ "$status" -eq 1 ]
}
@test "does not push on REJECT, no changes, or empty branch" {
    run should_push_target REJECT true loop/x/1 push;  [ "$status" -eq 1 ]
    run should_push_target APPROVE false loop/x/1 push; [ "$status" -eq 1 ]
    run should_push_target APPROVE true "" push;        [ "$status" -eq 1 ]
}
```

`should_delete_rejected_branch.bats`:

```bash
@test "keeps legacy behavior without strategy" {
    run should_delete_rejected_branch REJECT false; [ "$status" -eq 0 ]
    run should_delete_rejected_branch REJECT true;  [ "$status" -eq 1 ]
    run should_delete_rejected_branch APPROVE true; [ "$status" -eq 1 ]
}
@test "deletes after APPROVE when strategy is none" {
    run should_delete_rejected_branch APPROVE true none; [ "$status" -eq 0 ]
}
@test "keeps APPROVE branches for open_pr, push, push_head" {
    for s in open_pr push push_head; do
        run should_delete_rejected_branch APPROVE true "$s"; [ "$status" -eq 1 ]
    done
}
@test "REJECT with changes is kept for none too" {
    run should_delete_rejected_branch REJECT true none; [ "$status" -eq 1 ]
}
```

- [ ] **Step 2: 失敗を確認する**

Run: `bats test/bats/.github/actions/loop-finalize/lib/should_push_target.bats test/bats/.github/actions/loop-finalize/lib/should_delete_rejected_branch.bats`
Expected: FAIL(`should_push_target` 未定義、`none` のケースが 1 を返す)

- [ ] **Step 3: 実装する**

- `should_push_target.sh`: `should_delete_rejected_branch.sh` と同じヘッダ形式。条件は `VERDICT == APPROVE && HAS_CHANGES == true && BRANCH != "" && STRATEGY ∈ {push, push_head}`(`none` と `open_pr` を除外。未知の値も push しない)。
- `should_delete_rejected_branch.sh`: 第 3 引数 `strategy`(既定 `""`)を追加し、`APPROVE && strategy == none` でも 0 を返す。関数名は既存呼び出しのため変えない。ヘッダの説明を更新する。
- `action.yml`:
  - 「Push to Target Branch」: `if:` の `finalize_strategy != 'open_pr'` を `contains(fromJSON('["push","push_head"]'), steps.target.outputs.finalize_strategy)` に変える。
  - 「Delete Branch on Rejection」: ステップ名を「Delete Agent Branch」に変え、`if:` を `inputs.branch != '' && (inputs.verdict == 'REJECT' || steps.target.outputs.finalize_strategy == 'none')` にする。env に `FINALIZE_STRATEGY: ${{ steps.target.outputs.finalize_strategy }}` を足し(ORD-01 でアルファベット順)、`should_delete_rejected_branch "${VERDICT}" "${HAS_CHANGES}" "${FINALIZE_STRATEGY}"` と呼ぶ。このステップは「Run Domain Persistence」より後にあることを確認する(レポートを読み終えてから削除)。

- [ ] **Step 4: テストが通ることを確認する**

Run: `bats test/bats/.github/actions/loop-finalize/lib/`
Expected: 既存の `push_target.bats` などを含めて全 PASS

- [ ] **Step 5: `shfmt -w` を変更した `.sh` に実行し、コミットする**

```bash
git add .github/actions/loop-finalize test/bats/.github/actions/loop-finalize
git commit -m "fix(loop-finalize): skip push and delete agent branch when finalize is none"
```

---

### Task 2: PR レビューへの Meta 追記(P3)

**Files:**

- Modify: `.github/actions/lib/loop/entity_meta.sh`
- Modify: `.github/workflows/ci-loop-agent.yaml`(`finalize-l2` の「Append Run Log」の後にステップを追加)
- Test: `test/bats/.github/actions/lib/loop/entity_meta.bats`

**Interfaces:**

- Produces: `entity_pr_number KEY` → `entity:pr:<n>` から `<n>`、それ以外は空。`append_pr_review_meta PR_NUMBER MARKER OUTCOME ENGINE USAGE_JSON RUN_URL` → 常に 0(best-effort)。
- Consumes: `build_loop_meta_block`、`LOOP_META_MARKER`(`loop_meta.sh`)。

- [ ] **Step 1: 失敗するテストを書く**(既存の `gh` モックの書き方に合わせる)

```bash
@test "entity_pr_number extracts the number from an entity pr key" {
    run entity_pr_number "entity:pr:77"; [ "$output" = "77" ]
    run entity_pr_number "entity:issue:77"; [ -z "$output" ]
}
@test "append_pr_review_meta no-ops for a non-numeric pr number" {
    run append_pr_review_meta "x" "<!-- m -->" "pr-created" claude "$(usage_fixture)" "https://x/run/1"
    [ "$status" -eq 0 ]; [ -z "$output" ]
}
@test "append_pr_review_meta reports when no marker review exists" {
    # gh mock: GET pulls/77/reviews → []
    run append_pr_review_meta 77 "<!-- github-pr-review:v1 -->" pr-created claude "$(usage_fixture)" "https://x/run/1"
    [ "$status" -eq 0 ]; [[ $output == *"meta not appended"* ]]
}
@test "append_pr_review_meta updates the newest marker review once" {
    # gh mock: GET returns two reviews with the marker (ids 1, 2); records PUT target in a file
    # assert: PUT went to pulls/77/reviews/2 and body ends with the meta block
}
@test "append_pr_review_meta skips a review that already carries meta" {
    # gh mock: GET returns one review whose body contains "<!-- loop-meta:v1 -->"
    # assert: no PUT recorded
}
```

- [ ] **Step 2: 失敗を確認する**

Run: `bats test/bats/.github/actions/lib/loop/entity_meta.bats`
Expected: FAIL(関数未定義)

- [ ] **Step 3: 実装する**

- `find_marker_comment_id` と同じ選び方(マーカーを含み、`LOOP_META_MARKER` を含まない最新)で、`gh api --paginate repos/${REPOSITORY}/pulls/<n>/reviews` を検索する `find_marker_review_id PR_NUMBER MARKER` を追加。
- 更新は `gh api --method PUT repos/${REPOSITORY}/pulls/<n>/reviews/<id> -F body=@file`。
- 失敗時は `::warning::`、成功時は `::notice title=loop-meta::`。ファイル先頭の Description と Usage を PR レビュー対応に更新する。
- `ci-loop-agent.yaml` の `finalize-l2` に「Append Loop Meta To Pull Request Review」を追加: `if: always() && inputs.handoff_key != ''`。env は L1 側のステップに合わせる(`ENGINE`、`GITHUB_TOKEN`、`HANDOFF_KEY`、`LOOP_NAME`、`OUTCOME: ${{ steps.finalize.outputs.outcome || 'error' }}`(`loop-finalize` の output `outcome`)、`REPOSITORY`、`RUN_URL`、`USAGE_JSON: ${{ needs.agent-l2.outputs.usage_json || '' }}`)。`pr_number="$(entity_pr_number "${HANDOFF_KEY}")"` が空なら `exit 0`。マーカーは `<!-- ${LOOP_NAME}:v1 -->`。

- [ ] **Step 4: テストが通ることを確認する**

Run: `bats test/bats/.github/actions/lib/loop/entity_meta.bats`
Expected: PASS

- [ ] **Step 5: コミットする**

```bash
git add .github/actions/lib/loop/entity_meta.sh .github/workflows/ci-loop-agent.yaml test/bats/.github/actions/lib/loop/entity_meta.bats
git commit -m "feat(loop): append loop meta to marker pull request reviews in finalize-l2"
```

---

### Task 3: プラットフォームのリリースと SHA ピン更新

`ci-loop-caller-entity.yaml` は `ci-loop-agent.yaml` を SHA ピンで参照し、`ci-loop-agent.yaml` は `loop-finalize` を SHA ピンで参照する。Task 1、2 の変更は、ピンを更新するまで loop に効かない。

- [ ] **Step 1:** Task 1、2 を含む PR をマージし、リポジトリのリリース手順(`docs/` のリリースチェックリスト、または既存のピン更新コミットの形)に従ってリリースする。
- [ ] **Step 2:** `ci-loop-agent.yaml` 内の `loop-finalize` のピン、`ci-loop-caller-entity.yaml` 内の `ci-loop-agent.yaml` のピン、`example/` のピンを新しい SHA に更新する(`.github/workflows/CLAUDE.md` の Pins / Release)。
- [ ] **Step 3:** `grep -rn "loop-finalize@\|ci-loop-agent.yaml@" .github/workflows` で旧 SHA が残っていないことを確認し、コミットする。

この Task はユーザーのリリース判断を要する。実施前に確認すること。

---

### Task 4: `detect_pr_review.sh`

**Files:**

- Create: `.apm/packages/github/.apm/skills/github-pr-review/scripts/detect_pr_review.sh`
- Create: `.apm/packages/github/.apm/skills/github-pr-review/scripts/lib/`(`scripts/self/apm/sync_skill_lib.sh` で生成。手で書かない)
- Test: `test/bats/.apm/packages/github/github-pr-review/detect_pr_review.bats`

**Interfaces:**

- 入力(環境変数): `PR_NUMBER`、`PR_FORCE`(`true|false`)、`PR_AUTHOR_TYPE`、`PR_DRAFT`、`PR_IS_FORK`、`PR_LABELS_JSON`、`PR_BASE_SHA`、`PR_HEAD_SHA`、`PR_REVIEWS_JSON`(テスト用。未設定なら `gh api` で取得)、`PR_EXCLUDE_LABELS`(カンマ区切り、caller が渡す)、`GITHUB_EVENT_PATH`(未設定の `PR_*` を補う。`pull_request` と `workflow_dispatch` の `inputs.pr_number` / `inputs.force` の両方)。
- 出力(stdout、`json_object` を使う。`detect_issue.sh` と同じ共通エンベロープ):

```json
{
  "status": "ok",
  "skip": false,
  "message": "",
  "result": {
    "handoff_key": "entity:pr:77",
    "pr_number": 77,
    "base_sha": "…",
    "head_sha": "…",
    "changed_files": ["a.sh"],
    "report_path": ".loop-review/pr-77.json",
    "event_name": "pull_request_target",
    "event_action": "opened",
    "force": false
  },
  "verifier_context": "PR #77 base … head … files: 1"
}
```

- [ ] **Step 1: 失敗するテストを書く**(`detect_issue.bats` の `run env … bash "${DETECT_SCRIPT}"` 形式)

| テスト名                                           | 入力                                                                                      | 期待                                                                                                            |
| -------------------------------------------------- | ----------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------- |
| `emits handoff_key and report_path for a human PR` | `PR_NUMBER=77`、`PR_REVIEWS_JSON='[]'`                                                    | `.skip == false and .result.handoff_key == "entity:pr:77" and .result.report_path == ".loop-review/pr-77.json"` |
| `skips bot-authored PR`                            | `PR_AUTHOR_TYPE=Bot`                                                                      | `.skip == true`                                                                                                 |
| `skips draft PR`                                   | `PR_DRAFT=true`                                                                           | `.skip == true`                                                                                                 |
| `skips fork PR`                                    | `PR_IS_FORK=true`                                                                         | `.skip == true`                                                                                                 |
| `skips excluded label`                             | `PR_LABELS_JSON='["loop-automation"]'`、`PR_EXCLUDE_LABELS=no-loop,loop-automation`       | `.skip == true`                                                                                                 |
| `skips when a marker review exists`                | `PR_REVIEWS_JSON='[{"body":"<!-- github-pr-review:v1 -->\n…"}]'`                          | `.skip == true and (.message \| test("already reviewed"))`                                                      |
| `force ignores the marker`                         | 上記 + `PR_FORCE=true`                                                                    | `.skip == false and .result.force == true`                                                                      |
| `hydrates from workflow_dispatch event`            | `GITHUB_EVENT_PATH` に `{"inputs":{"pr_number":"77","force":"true"}}`、`PR_NUMBER` 未設定 | `.result.pr_number == 77 and .result.force == true`                                                             |
| `errors without a PR number`                       | 何も渡さない                                                                              | `status != 0` かつ `.status == "error"`                                                                         |

- [ ] **Step 2: 失敗を確認する**

Run: `bats test/bats/.apm/packages/github/github-pr-review/detect_pr_review.bats`
Expected: FAIL(スクリプトなし)

- [ ] **Step 3: 実装する**

`detect_pr_revise.sh` と同じ構成(ヘッダ、`set -euo pipefail`、`umask 027`、`source "${SCRIPT_DIR}/lib/all.sh"`、`hydrate_pr_env_from_event`、`output_error`、`build_result_json`、`main`)。`PR_*` が未設定で `PR_NUMBER` だけある場合(`workflow_dispatch`)は `gh pr view <n> --json author,isDraft,isCrossRepository,labels,baseRefOid,headRefOid,files` で補う。マーカー判定は `PR_REVIEWS_JSON`(未設定なら `gh api --paginate repos/${GITHUB_REPOSITORY}/pulls/<n>/reviews`)の `body` に `<!-- github-pr-review:v1 -->` を含むか。

- [ ] **Step 4: `bash scripts/self/apm/sync_skill_lib.sh` で `scripts/lib/` を生成し、テストが通ることを確認する**

Run: `bats test/bats/.apm/packages/github/github-pr-review/detect_pr_review.bats`
Expected: PASS

- [ ] **Step 5: コミットする**

```bash
git add .apm/packages/github/.apm/skills/github-pr-review/scripts test/bats/.apm/packages/github/github-pr-review/detect_pr_review.bats
git commit -m "feat(github-pr-review): add detect script for first PR review"
```

---

### Task 5: `post_review.sh`(検証と投稿)

**Files:**

- Create: `.apm/packages/github/.apm/skills/github-pr-review/scripts/post_review.sh`
- Test: `test/bats/.apm/packages/github/github-pr-review/post_review.bats`

**Interfaces:**

- 入力(finalize の環境変数): `VERDICT`、`EXECUTE_BRANCH`、`TARGET_JSON`(`.entity.handoff_key` または `.key` から PR 番号)、`GITHUB_REPOSITORY`。テスト用に `REPORT_FILE`(設定時は `git fetch` せずに読む)、`PR_DIFF_FILE`(設定時は `gh pr diff` の代わり)、`BASE_TREE_DIR`(設定時は base の作業ツリーとして引用を検証する。既定はカレントの checkout)。
- レポート JSON の形式は spec の「レポートファイル(レビュー案)」に従う(`pr_number`、`head_sha`、`base_sha`、`response_language`、`premises`、`summary`、`findings[]`(`id`、`severity`、`title`、`evidence{kind,path,quote}`、`location{path,line,start_line,side,in_diff}`、`impact`))。
- 出力: `POST repos/{repo}/pulls/{n}/reviews` に `event: COMMENT`、`body`、`comments[]`、`commit_id: head_sha`。本文とインラインは `assets/review-body-template.md` / `assets/inline-comment-template.md`(Task 6)の固定表記と同じ英語の見出し・ラベルで組み立てる。
- 関数(テストから `source` して呼べるよう `main` を `BASH_SOURCE` ガード): `validate_finding FINDING_JSON` → 0/1、`diff_contains_line PATH LINE SIDE` → 0/1、`render_review_body REPORT_JSON` → stdout、`render_inline_comment FINDING_JSON` → stdout、`main`。

- [ ] **Step 1: 失敗するテストを書く**

| テスト名                                                      | 期待                                                                                                                                                                             |
| ------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `does nothing unless VERDICT is APPROVE`                      | `VERDICT=REJECT` で `gh` モックの呼び出し記録が空、`status 0`                                                                                                                    |
| `keeps a rule finding whose quote exists in the base file`    | `BASE_TREE_DIR/AGENTS.md` に原文あり → `validate_finding` が 0                                                                                                                   |
| `drops a rule finding whose quote differs only by whitespace` | 末尾空白・改行違い → 1(完全一致のみ。Review Focus 2)                                                                                                                             |
| `drops a criteria finding whose file does not exist on base`  | → 1                                                                                                                                                                              |
| `keeps a bug finding without evidence path`                   | `kind: bug` で `location` あり → 0                                                                                                                                               |
| `moves an in_diff finding outside the diff into the body`     | `PR_DIFF_FILE` にない行 → インラインに入らず本文の Findings に詳細つきで載る、投稿は成功(Review Focus 3)                                                                         |
| `posts COMMENT with marker, counts, and premises`             | 送信 JSON の `.event == "COMMENT"`、`.body` が `<!-- github-pr-review:v1 -->` で始まり `Findings: 2 (Critical: 1 / Warning: 1 / Suggestion: 0)` と `### Premises checked` を含む |
| `posts an explicit no-findings review`                        | `findings: []` → 本文に `Findings: 0` とマーカー(Review Focus 4)                                                                                                                 |
| `numbers inline comments to match the body`                   | インラインの本文が `**#1 [Critical]**` で始まり、本文 1 行目の指摘が `inline:` リンクを持つ                                                                                      |
| `links evidence to base sha and location to head sha`         | 本文に `blob/<base_sha>/AGENTS.md#L` と `blob/<head_sha>/a.sh#L` が出る                                                                                                          |
| `reports dropped findings count in the body`                  | 検証で 1 件捨てる → 本文に `Dropped: 1`                                                                                                                                          |
| `never sends REQUEST_CHANGES or APPROVE`                      | どの入力でも `.event == "COMMENT"`                                                                                                                                               |

- [ ] **Step 2: 失敗を確認する**

Run: `bats test/bats/.apm/packages/github/github-pr-review/post_review.bats`
Expected: FAIL

- [ ] **Step 3: 実装する**

- レポートは `git fetch origin "${EXECUTE_BRANCH}"` の後 `git show "origin/${EXECUTE_BRANCH}:${report_path}"` で読む(`REPORT_FILE` 指定時はそれを読む)。
- 引用の検証は `grep -F -x` ではなく、ファイル内容に `quote` が部分文字列として**そのまま**含まれるか(改行を含む引用も可)。正規化はしない。
- `diff_contains_line`: unified diff の hunk ヘッダ `@@ -a,b +c,d @@` から、`side == RIGHT` は新側、`LEFT` は旧側の行範囲を求め、`+` / `-` / 文脈行を数えて対象行が hunk 内にあるかを判定する。`start_line` があれば両端とも同じ hunk 内であること。
- インラインの `comments[]` 要素は `{path, line, side, body}`(`start_line` があれば `start_line`, `start_side` も)。
- 本文の `inline:` リンクは投稿前に URL が決まらないため、`[`<path>#L<line>`](https://github.com/<repo>/pull/<n>/files)` を使い、`#N` 番号で対応させる(spec の「投稿の形式」と同じ)。
- 投稿は `gh api --method POST repos/${GITHUB_REPOSITORY}/pulls/<n>/reviews --input <json>`。失敗時は `::warning::` を出して終了コード 0(finalize を落とさない)。

- [ ] **Step 4: テストが通ることを確認する**

Run: `bats test/bats/.apm/packages/github/github-pr-review/post_review.bats`
Expected: PASS

- [ ] **Step 5: コミットする**

```bash
git add .apm/packages/github/.apm/skills/github-pr-review/scripts/post_review.sh test/bats/.apm/packages/github/github-pr-review/post_review.bats
git commit -m "feat(github-pr-review): validate evidence and post COMMENT review after APPROVE"
```

---

### Task 6: スキル本体(`SKILL.md`、`references/`、`assets/`、`evals/`)

**Files:**

- Create: `.apm/packages/github/.apm/skills/github-pr-review/SKILL.md`
- Create: `references/common-checklist.md`、`references/common-output-format.md`、`references/category-automation-envelope.md`、`references/category-review-rules.md`、`references/category-pr-body-links.md`
- Create: `assets/review-body-template.md`、`assets/inline-comment-template.md`、`assets/report-template.json`
- Create: `eval.yaml`、`evals/tasks/{basic,skip-detect,rule-citation,no-evidence-suppressed,pre-existing-excluded,trigger-negative}.yaml`
- Modify: `scripts/self/apm/check_loop_pr_body_contract.sh`(`LOOP_PR_BODY_LINKS_SKILLS` に `github-pr-review` を追加。他の配列は、このスキルが PR 本文テンプレートを持たないため追加しない)

**Interfaces:**

- Consumes: Task 4 の detect JSON(`result.*`)、Task 5 のレポート形式。
- Produces: `SKILL.md` の `name: github-pr-review`(`agent_maker_skill_name` と一致)。

- [ ] **Step 1: evals を先に書く**(`github-issue-triage/evals/tasks/basic.yaml` の形式)

| タスク                   | `expected.output_contains` / 禁止                                  |
| ------------------------ | ------------------------------------------------------------------ |
| `basic`                  | レポート JSON に `findings`、`premises`、`response_language`       |
| `skip-detect`            | `skip: true` の detect → レポートを書かず skip 理由を報告          |
| `rule-citation`          | ルール違反の差分 → `"kind": "rule"` と原文の `quote`               |
| `no-evidence-suppressed` | 好みだけの差分 → `findings` が空                                   |
| `pre-existing-excluded`  | 差分外の既存の問題のみ → `findings` が空                           |
| `trigger-negative`       | 「この PR を直して」→ ファイル編集をせず `github-pr-revise` を案内 |

- [ ] **Step 2: スキル本体を書く**(英語)

- `SKILL.md`: `github-pr-revise/SKILL.md` の節構成(Input / Output Specification / Execution Scope / Reference Files Guide / Workflow / Error Handling)に合わせる。Workflow は spec の「スキル `github-pr-review` の手順」1〜7。`may_edit` / `write_target` の分岐は `github-pr-revise` と同じ表で、`write_target: report` のときだけレポートを書く。**投稿しない**(D15)、**`--comment` 等で別に投稿しない**、`gh` は読み取りのみ、と明記。
- `category-review-rules.md`: D4 の根拠 3 種、D14、「指摘しないこと」(可搬な表現のみ)、D20(変更ファイルを base の作業ツリーで開く)、D11(意図確認)、回答言語の決定順(D23)。
- `category-pr-body-links.md`: D24 のリンク規則(SHA 固定、base / head の使い分け、`#N`、テンプレートに例の URL を書かない)。
- `assets/*-template.md`: spec の「投稿の形式」の英語の固定表記。冒頭の HTML コメントに「Load ONLY …」と言語規則、各節に GOOD / BAD 例(`github-pr-revise/assets/pr-body-template.md` に合わせる)。`post_review.sh` の固定文字列と一致させる。
- `assets/report-template.json`: spec のレポート形式。

- [ ] **Step 3: 契約チェックを実行する**

Run: `bash scripts/self/apm/check_loop_pr_body_contract.sh`
Expected: violation なし

- [ ] **Step 4: `agent-skills-review` スキルで `SKILL.md` をレビューし、指摘を反映する**

- [ ] **Step 5: コミットする**(同期先は Stop フックが更新する)

```bash
git add .apm/packages/github/.apm/skills/github-pr-review scripts/self/apm/check_loop_pr_body_contract.sh
git commit -m "feat(github-pr-review): add engine-agnostic PR review skill"
```

---

### Task 7: `github-pr-revise` が PR 全体の文脈を読む(D19)

**Files:**

- Modify: `.apm/packages/github/.apm/skills/github-pr-revise/SKILL.md`(Workflow に手順を追加)
- Modify: `.apm/packages/github/.apm/skills/github-pr-revise/references/common-checklist.md`
- Modify: `.apm/packages/github/.apm/skills/github-pr-revise/scripts/detect_pr_revise.sh`(`in_reply_to_id` があれば親コメントの本文を `parent_body` として `comments[]` の各要素に付ける)
- Modify: `.apm/packages/github/.apm/skills/github-pr-revise/evals/tasks/`(`reply-to-bot-finding.yaml` を追加)
- Test: `test/bats/.apm/packages/github/github-pr-revise/detect_pr_revise.bats`

**Interfaces:**

- Produces: `result.comments[].parent_body`(文字列。親がない・取得できない場合はキー自体を出さない)。

- [ ] **Step 1: 失敗するテストを書く**

```bash
@test "adds parent_body for a reply to a review comment" {
    # PR_COMMENTS_JSON 未設定、gh モック: pulls/comments/<in_reply_to_id> → {"body":"**#1 [Critical]** ..."}
    # assert: .result.comments[0].parent_body | startswith("**#1 [Critical]**")
}
@test "omits parent_body when there is no in_reply_to_id" {
    # assert: .result.comments[0] | has("parent_body") | not
}
```

- [ ] **Step 2: 失敗を確認する** — Run: `bats test/bats/.apm/packages/github/github-pr-revise/detect_pr_revise.bats` / Expected: 新規 2 件が FAIL

- [ ] **Step 3: 実装する**

- `build_comment_object` に第 N 引数 `parent_body` を追加(空なら出さない)。親の取得は `gh api repos/${GITHUB_REPOSITORY}/pulls/comments/<id> --jq .body`(失敗時は空)。
- `SKILL.md` の Workflow に追加: インラインへの返信なら `parent_body` とそのスレッド全体・該当行を読む。それ以外なら `gh pr view <n> --json body,comments,reviews` で PR 本文とコメント全体を読む。bot のコメントは「依頼の文脈」としてのみ読み、トリガーにはしない(既存の bot 拒否は維持)。

- [ ] **Step 4: テストが通ることを確認する** — Run: 同上 / Expected: 全 PASS

- [ ] **Step 5: `shfmt -w` 後にコミットする**

```bash
git add .apm/packages/github/.apm/skills/github-pr-revise test/bats/.apm/packages/github/github-pr-revise
git commit -m "feat(github-pr-revise): read parent finding and full PR context for replies"
```

---

### Task 8: caller `on-loop-github-pr-review.yaml`

**Files:**

- Create: `.github/workflows/on-loop-github-pr-review.yaml`

**Interfaces:**

- Consumes: Task 3 のピン更新済み `ci-loop-caller-entity.yaml`、Task 4 の detect、Task 5 の `post_review.sh`、Task 6 のスキル名。

- [ ] **Step 1: ワークフローを書く**(`on-loop-github-issue-triage.yaml` を雛形にする。キーは ORD-01 でアルファベット順)

- `on`: `pull_request_target: types: [opened, ready_for_review]`(`# zizmor: ignore[dangerous-triggers]` と理由: head を checkout・実行しない、`on-loop-state-promote.yaml` に倣う)、`workflow_dispatch: inputs: { force: boolean (default false), pr_number: number (required) }`。
- `permissions`: `actions: write`、`contents: write`、`copilot-requests: write`、`issues: write`、`pull-requests: write`(他の `on-loop-*` と同じ)。
- `concurrency`: `group: loop-github-pr-review-${{ github.event.pull_request.number || inputs.pr_number || github.run_id }}`、`cancel-in-progress: false`、`queue: max`。
- `jobs.loop.if`: `workflow_dispatch` または(`pull_request_target` かつ `pull_request.draft == false` かつ `pull_request.head.repo.full_name == github.repository` かつ `pull_request.user.type != 'Bot'` かつ `!contains(pull_request.labels.*.name, 'no-loop')` かつ `!contains(…, 'loop-automation')`)。
- `uses: ./.github/workflows/ci-loop-caller-entity.yaml`。
- `with`:
  - `agent_allowed_tools`: `Bash(gh api:*)`、`Bash(gh pr view:*)`、`Bash(gh pr diff:*)`、`Bash(git show:*)`
  - `agent_checker_instructions`: spec の「Checker の基準」(英語に訳す)
  - `agent_checker_model: claude-opus-5`、`agent_checker_skill_name: loop-verifier`、`agent_loop_max_attempts: 3`
  - `agent_maker_instructions`: (1) Claude 用: `/code-review <pr_number>` を `--comment` なしで実行し、結果は材料としてのみ使う。D4 の形にできないものは捨て、スキルの指摘と重複するものは 1 件にまとめる(D7)。(2) このリポジトリ固有の除外: `apm install` の同期先(`.agents/`、`.claude/`、`.codex/`、`.cursor/`、`.kiro/`、`.vscode/`、`apm_modules/`)と `apm.lock.yaml` の再生成差分は指摘しない。ただし同期先の手編集は `CLAUDE.md` の Edit routing 違反として指摘する。
  - `agent_maker_model: claude-sonnet-5`、`agent_maker_skill_name: github-pr-review`
  - `budget_max_runs_per_day: 20`、`budget_max_tokens_per_day: 1000000`
  - `delivery: none`、`detect_script: .agents/skills/github-pr-review/scripts/detect_pr_review.sh`
  - `detect_domain_env_json`: `PR_NUMBER`、`PR_FORCE`、`PR_EXCLUDE_LABELS: no-loop,loop-automation` を JSON で渡す(`on-loop-github-issue-triage.yaml` の `format(...)` の書き方)
  - `domain_persistence_script: .agents/skills/github-pr-review/scripts/post_review.sh`
  - `engine: claude`、`environment: default`、`level: L2`、`loop_name: github-pr-review`、`may_edit: true`、`no_changes_verdict: REJECT`、`write_target: report`
- `secrets`: 他の `on-loop-*` と同じ 3 つ。

- [ ] **Step 2: 静的検証** — Stop フックの `actionlint` / `ghalint` / `zizmor` の結果を確認し、指摘を直す(直接実行しない)。

- [ ] **Step 3: コミットする**

```bash
git add .github/workflows/on-loop-github-pr-review.yaml
git commit -m "feat(loop): add on-loop-github-pr-review caller"
```

---

### Task 9: ドキュメント

**Files:**

- Create: `docs/explanation/loop-engineering/workflows/loop-github-pr-review-workflow-design.md`(`loop-github-issue-triage-workflow-design.md` の構成に合わせ、spec へのリンクを置く)
- Modify: `docs/explanation/loop-engineering/loop-engineering-design.md`(loop 一覧の表に 1 行)、`docs/explanation/loop-engineering/loop-capable-skills.md`、`docs/explanation/loop-engineering/workflows/loop-caller-inputs-reference.md`(`delivery: none` + L2 の挙動、P1 / P2)、`docs/explanation/loop-engineering/workflows/loop-github-pr-revise-workflow-design.md`(D19、`parent_body`)
- Modify: `mkdocs.yml`(新規文書を `nav` に追加)
- Modify: `docs/reference/loop-engineering-checklist.md`(Finalize の節に「`delivery: none` の L2 は push しない」を追記)

- [ ] **Step 1:** 各文書を更新する。リンクは対象文書のタイトルを文字列にした相対 `.md` リンク(DOC-05)。
- [ ] **Step 2:** Stop フックの `markdownlint-cli2` / `markdown-link-check` の結果を確認し、指摘を直す。
- [ ] **Step 3:** コミットする。

```bash
git add docs mkdocs.yml
git commit -m "docs(loop): document github-pr-review loop and finalize none delivery"
```

---

### Task 10: 実機確認(第 1 段階)

- [ ] **Step 1:** 検証用のブランチで、既知の違反(例: `.claude/rules/` にある MUST に反する行)を 1 件含む PR を作る。
- [ ] **Step 2:** `workflow_dispatch` で `pr_number` を指定して実行する。
- [ ] **Step 3:** 次を確認し、結果を PR 本文に記録する。
  - `/code-review` が Actions 上で動いたか(動かなければ `agent_maker_instructions` から外す)
  - レビューが `COMMENT` で 1 件だけ投稿され、マーカー・`### Premises checked`・番号つきインライン・SHA 固定リンク・Meta がある
  - 作業ブランチが削除され、`main` にレポートが push されていない
  - 同じ PR で再実行すると skip され、`force: true` なら再投稿される
- [ ] **Step 4:** 問題がなければ `pull_request_target` トリガーを有効のまま維持する。問題があれば、トリガーを `workflow_dispatch` のみに戻して報告する。
