# autofix の定期実行 L2 と Webhook の対象ごとのキー(PR 4 / 段階 E)Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `loop-scheduled` を L2(`delivery: pr_create`)に上げ、checker が APPROVE した修正 PR だけを作る。Webhook / `repository_dispatch` / `workflow_dispatch` の経路も、定期実行と同じ Issue ごとのキー(`integration:main#issue:<N>`)にして、pending と circuit breaker を共有する。あわせて、PR 3 の最終レビューが「段階 E の前提」とした2点(閉じた PR の窓、`jq -e` の終了コード)を直す。

**Architecture:** `detect_autofix.sh` の単一 Issue のモードに、`result.items`(1件)を返す出力の形を足す(環境変数で選ぶ)。`on-loop-github-issue-autofix.yaml` の `loop`(Webhook)と `loop-scheduled`(定期実行)の両方を `detect_items: true`、L2、`delivery: pr_create` にする。platform(PR 1、v1.9.7)が、要素ごとの state(pending、breaker、`last_run`)、作業ブランチ名(`#` を含むキーの slug)、run-log の `target_key` を扱う。

**Tech Stack:** bash、jq、`gh`、GitHub Actions、bats。

**Spec:** [定期実行での取り込み 設計書](../specs/2026-11-11-loop-scheduled-intake-design.md)(第6.1節、第6.3節、第6.4節、第6.5節「段階 E」と「段階 E の前提」、第8節、第15.3節、第15.4節)。前の plan: [autofix の定期実行 L1](2026-11-11-loop-scheduled-intake-autofix-l1.md)。

## Global Constraints

- コミットの末尾に `Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>`。bats は触ったディレクトリだけ(全体は走らせない)。hook が走らせるツール(actionlint、ghalint、zizmor、shellcheck、shfmt、prettier、markdownlint-cli2、markdown-link-check)は手で走らせない。workflow は実行しない(`AGENT_TOKEN` 未更新)。push はしない。
- `detect_autofix.sh` の編集元は `.apm/packages/github/.apm/skills/github-issue-autofix/scripts/detect_autofix.sh`。同期は `bash scripts/self/apm/sync_apm_artifacts.sh`(出力はファイルへ。パイプで切らない。`.agents/` と `.claude/` の複製が元と byte 単位で同じになることを確かめる)。bats は `test/bats/.apm/packages/github/github-issue-autofix/detect_autofix.bats`。配布物なので、このリポジトリ固有の語は環境変数で受け取る。
- **既存の単一 Issue のモード(`AUTOFIX_ITEMS` なし)の出力は変えない。** `AUTOFIX_SCAN=true` の一覧のモードの出力の形も変えない。
- workflow の map のキーは A-Z 順(ORD-01)。workflow レベルの `permissions` は `{}`、各ジョブに置く(今のまま)。
- L2 の契約(`validate_loop_write_contract.sh`): `agent_edit_target`(`fix`)、`agent_edit_allowlist`(`"**"`)、`agent_unchanged_verdict`(`REJECT`)が必須。`delivery: pr_create`。`finalize_script` は不要(`pr_create`)。
- 段階 E の caller 設定(spec 6.5): `loop-scheduled` は `loop` と同じ L2 の設定(`agent_edit_*`、`agent_unchanged_verdict: REJECT`、`delivery: pr_create`、`pr_draft`)に上げる。`loop` は `detect_items: true`、`detect_branch_match: main`、`detect_max_targets` は既定のまま(1件なので無関係)。`loop-scheduled` の `detect_max_targets: 3`、`AUTOFIX_MAX_OPEN_PRS: 3` は変えない。`concurrency` は変えない。
- 昇格の判断(overview 第2.2節、spec 第8節の観察)はユーザーが引き受ける。**この plan は実装まで**。push とリリースの判断は報告に書く(workflow の挙動は実機で未確認)。
- 閉じた PR と開いている PR の一覧の窓の修正(spec 第6.5節の前提(a)、(b))は、ここで直す。**方針の決定(plan の判断):** 閉じた PR の取得は `--limit 1000` に上げ、`headRefName` が `AUTOFIX_BRANCH_PREFIX` で始まるものだけを使う(クライアント側の絞り込み。GitHub の search の `head:` が前方一致かは確認できないので使わない)。取得件数が上限(1000)に達したら fail closed(`status: error`、exit 1)にする。開いている PR の一覧(`--limit 200`)も、件数が上限に達したら fail closed にする。上限は環境変数 `AUTOFIX_PR_SCAN_LIMIT`(既定 1000、正の整数)で変えられる。`jq -e` は終了コード 1(不一致)とそれ以外(jq の実行時エラー)を区別し、後者は `status: error` にする。

## Review Focus

- Webhook の1件が、要素ごとのキー `integration:main#issue:<N>` で動き、既存の `integration:main` の state(古い breaker や pending)に引きずられない(items モードは branch のキーを見ない)。
- 開いている `Fixes #N` の PR がある Issue を `autofix` ラベルで付け直したとき、Webhook は skip し、通常の出力(`skip: true`)を返す(items の形でも、`items` が空でなく `skip` で終わる)。
- 同じ Issue を、定期実行と Webhook が同時に処理しない(pending と breaker を同じキーで共有する。`concurrency` は定期実行が `loop-state-main`、Webhook が Issue ごとなので、実行の重なりは起きうる。pending で2回目が止まることを bats では確かめられないので、残リスクとして docs に書く)。
- `result.items` の形が、platform の `validate_item_key`、`extract_items` を通る(キー `issue:<N>`)。
- 閉じた PR が1000件に達したときに、エラーで止まり、空の対象で成功扱いにしない。

---

### Task 1: `detect_autofix.sh` の前提の修正(窓と終了コード)と、単一 Issue のモードの items 出力

**Files:**

- Modify: `.apm/packages/github/.apm/skills/github-issue-autofix/scripts/detect_autofix.sh`
- Test: `test/bats/.apm/packages/github/github-issue-autofix/detect_autofix.bats`
- Sync(生成物): `.agents/`、`.claude/` の複製、`apm.lock.yaml`

**Interfaces:**

- Consumes: 既存の `scan_*` 関数、`open_pr_fixes_issue`、`build_result_json`、`output_json`、`output_error`、`json_object`。
- Produces:
  - 環境変数 `AUTOFIX_ITEMS=true`(単一 Issue のモードだけ)のとき、skip でない出力を `{"status":"ok","skip":false,"message":"...","result":{"items":[{"key":"issue:<N>","entity":{"kind":"issue","number":<N>},"context":{"issue_number":<N>}}]}}` にする。skip のときは `{"status":"ok","skip":true,"message":"...","result":{}}`(`ISSUE_NUMBER` が空のときも同じ)。`AUTOFIX_ITEMS` が `true` 以外なら、今までと同じ出力。`AUTOFIX_SCAN=true` と同時に指定されたら無視する(一覧のモードの出力を優先する)。
  - 環境変数 `AUTOFIX_PR_SCAN_LIMIT`(正の整数、既定 1000)。一覧のモードで取る閉じた PR の上限と、開いている PR の上限の両方に使う(開いている PR の取得も同じ上限。今の200を置き換える)。取得件数が上限に等しい(以上の)ときは `output_error`(fail closed)。無効な値(正の整数でない、`0`、先頭が `0` の八進数に見える値は十進として扱う)は `output_error`。
  - 閉じた PR は `headRefName` が `AUTOFIX_BRANCH_PREFIX` で始まるものだけを、`Fixes #N` の照合と最新の `closedAt` の判定に使う(`AUTOFIX_BRANCH_PREFIX` が空のときの扱いは、一覧のモードで必須にするか、絞り込みなしにするかを既存の検証に合わせて決め、header に書く)。
  - `jq -e` の終了コードの区別: `scan_has_newer_human_comment` と、開いている PR の `any()` の判定で、終了コード 1(不一致)は「いいえ」、0 は「はい」、それ以外(jq の実行時エラーなど)は `output_error`。

- [ ] **Step 1: 失敗する bats を足す。** ケース: (a) `AUTOFIX_ITEMS=true`、`ISSUE_NUMBER=7`、開いている PR なしで、`result.items` が1件(`key` が `issue:7`、`entity`、`context`)。(b) 同じで開いている `Fixes #7` の PR があれば `skip: true`、`result: {}`。(c) `ISSUE_NUMBER` が空のとき `skip: true`。(d) `AUTOFIX_ITEMS` なしの出力が今までと同じ(`result.issue_number`)。(e) `AUTOFIX_ITEMS=true` と `AUTOFIX_SCAN=true` を同時に指定したとき、一覧のモードの出力。(f) 閉じた PR が上限(`AUTOFIX_PR_SCAN_LIMIT=3` にして3件返すスタブ)に達したら `status: error` と exit 1。(g) 開いている PR が上限に達したら同じ。(h) 上限未満なら通常どおり。(i) `AUTOFIX_PR_SCAN_LIMIT` が無効(`0`、`abc`、空以外の非数)なら `status: error`。`010` が十進の10として扱われる。(j) 閉じた PR のうち `headRefName` が prefix で始まらないもの(別の loop の PR)は、`Fixes #N` の照合に使われない。(k) コメントの jq が実行時エラー(スタブが壊れた JSON を返す)のとき `status: error`、exit 1(Issue を黙って除外しない)。(l) 開いている PR の一覧が壊れた JSON のとき `status: error`(Issue を黙って含めない)。
- [ ] **Step 2: 失敗を確かめる。** `bats test/bats/.apm/packages/github/github-issue-autofix/detect_autofix.bats`。
- [ ] **Step 3: 実装する。** 上の Interfaces に従う。header(Design Rules、Optional environment)と関数の doc コメントを更新する。
- [ ] **Step 4: 同期して確かめる。** `bash scripts/self/apm/sync_apm_artifacts.sh > tmp/sync.log 2>&1`。複製が元と同じこと、Step 2 の bats と `test/bats/scripts/self/apm/sync_validate_mirror.bats` が通ること。
- [ ] **Step 5: Commit。** `feat(autofix): emit items for single-issue mode and fail closed on PR list limits`

---

### Task 2: workflow を L2 と対象ごとのキーに上げる

**Files:**

- Modify: `.github/workflows/on-loop-github-issue-autofix.yaml`
- Modify: `test/bats/github-actions/loop-autofix-schedule.bats`(L1 を前提にした検査を L2 に改める。ファイル名は変えない)
- 確認: `loop-caller-parity.bats`、`workflow-header.bats`、`loop-write-contract.bats`

**Interfaces:**

- Consumes: Task 1 の `AUTOFIX_ITEMS`、`AUTOFIX_PR_SCAN_LIMIT`。`ci-loop-caller.yaml` の入力。
- Produces: 次の変更。

1. **`loop`(Webhook / dispatch)**: `detect_items: true` を足す。`detect_env_json` に `AUTOFIX_ITEMS: "true"` を足す(今の `ISSUE_NUMBER` の式は保つ。JSON を組み立てる式を直す。`ISSUE_NUMBER` は数値や空を `format('{0}', ...)` で文字列にする今の方式のまま)。`detect_branch_match: main` は既にある。ほかの設定(L2、`pr_create`、`agent_*`、`pr_draft`)は変えない。
2. **`loop-scheduled`(定期実行)**: `level: L2`、`delivery: pr_create`、`agent_edit_allowlist: "**"`、`agent_edit_target: fix`、`agent_unchanged_verdict: REJECT`、`pr_draft: ${{ inputs.pr_draft || false }}`(`schedule` では `inputs` は空で `false`)を足す。`agent_maker_instructions` は L2 用(`loop` と同じ内容。PR を作る前提で、`Fixes #<N>` を含む PR 本文。ファイルを編集してよい。`repository_dispatch` を呼ばない。検証 skill の `validate.sh` の形)にする。`agent_tool_allowlist` は `loop` と同じ(検証 skill の `validate.sh` の行を含む)。`agent_checker_*` の L1 用のコメント(checker の rubric は L1 で走らない)は、L2 では checker が走るので削除する。`detect_env_json` は一覧のモードの環境変数に、`AUTOFIX_PR_SCAN_LIMIT: "1000"` を足す。
3. ファイル先頭の `Description` / `Usage` を、L2 と対象ごとのキーに合わせる。

- [ ] **Step 1: 失敗する bats を直す。** `loop-autofix-schedule.bats` の L1 前提のケース(L1、`delivery: none`、`agent_edit_*` を渡さない、maker が編集を禁じる、checker のコメント)を L2 に改める: (a) `loop-scheduled` が `level: L2`、`delivery: pr_create`、`agent_edit_target: fix`、`agent_edit_allowlist: "**"`、`agent_unchanged_verdict: REJECT`、`detect_items: true`、`detect_branch_match: main`、`detect_max_targets: 3`。(b) `loop-scheduled` の maker の instructions が `Fixes #` と、`repository_dispatch` を呼ばないことを含む。(c) `loop` が `detect_items: true` で、`detect_env_json` が `AUTOFIX_ITEMS` を含み、`level: L2`、`delivery: pr_create` が変わらない。(d) 両ジョブの `detect_env_json` が有効な JSON になる形。(e) `loop-scheduled` の `detect_env_json` が `AUTOFIX_PR_SCAN_LIMIT` を含む。(f) 両ジョブの `agent_tool_allowlist` が同じ。(g) `permissions`、`if`、`concurrency` が PR 3 のまま(既存のケース)。
- [ ] **Step 2: 失敗を確かめる。** `bats test/bats/github-actions/loop-autofix-schedule.bats`。
- [ ] **Step 3: workflow を編集する。** 上の変更1〜3。
- [ ] **Step 4: 通ることを確かめる。** Step 2 のコマンド、`loop-caller-parity.bats`、`workflow-header.bats`、`loop-write-contract.bats`。actionlint、ghalint、zizmor は Stop hook の結果を見る(手で走らせない)。
- [ ] **Step 5: Commit。** `feat(autofix): promote scheduled job to L2 and key webhook runs per issue`

---

### Task 3: docs

**Files:**

- Modify: `docs/explanation/loop-engineering/workflows/loop-github-issue-autofix-workflow-design.md`(「Stage E (not implemented)」を実装済みの記述に改める。`loop-scheduled` の表を L2 に、`loop` の表を対象ごとのキーに。Intake paths に `AUTOFIX_ITEMS`、`AUTOFIX_PR_SCAN_LIMIT`、閉じた PR の絞り込みと fail closed を、**1か所だけ**に書く。User actions の段階 E の行(「未実装」)を現在の挙動にする。Out of scope の「L2 の定期実行は後」を改める)
- Modify: `docs/explanation/loop-engineering/loop-issue-handoff.md`(autofix 側の「段階 E 以降(未実装)」を現在の挙動に。A3〜A6 が定期実行の経路でも動く。Webhook の経路が同じキーで pending / breaker を共有することを書く)
- Modify: `docs/explanation/loop-engineering/loop-engineering-design.md`(Intake Gating の autofix の行、STATE Files の対象ごとのキー(Webhook の autofix も `integration:<branch>#issue:<N>`)、Multi-loop Coordination)
- Modify: `docs/superpowers/specs/2026-11-11-loop-scheduled-intake-design.md`(第6.5節の「段階 E の前提」を、解決済みとして、実装した方針(1000件、前方一致の絞り込み、fail closed)に改める。第11節の「直近200件の閉じた PR の窓」を更新する。Status を、段階 E まで実装したことに更新する)
- 確認: `docs/explanation/loop-engineering/workflows/loop-caller-inputs-reference.md`(新しい入力はない。変えない)

**Interfaces:**

- Consumes: Task 1、2 の実装(値は実装から読む)。
- Produces: 段階 E の記述が、実装と一致している。昇格の判断(観察の期間、第2.2節の条件)は、運用の判断として、「昇格前に確認する条件」として残す(実機の確認が済んでいないことを書く)。

- [ ] **Step 1: 各ファイルを、今の内容を読んでから編集する。** `.claude/rules/markdown.md` に従う(相対 `.md` リンクで、リンクのテキストは相手の題名、「上記」「後述」を使わない、コードのブロックに言語)。規則の本文は1か所だけに書く(spec 第15節)。新しいファイルは作らない。
- [ ] **Step 2: 内容を実装と照らす。** `loop-scheduled` の L2 の設定、`loop` の `detect_items: true` と `AUTOFIX_ITEMS`、`AUTOFIX_PR_SCAN_LIMIT` の既定と fail closed の条件が、docs と実装で一致している。実機で未確認の挙動(`detect_items` の Webhook の経路、pending の共有、定期実行と Webhook の同時実行)を、「未確認」として書く。
- [ ] **Step 3: 検査。** markdownlint-cli2、markdown-link-check は Stop hook の結果を見る(手で走らせない)。
- [ ] **Step 4: Commit。** `docs(loop): document autofix L2 promotion and per-issue keys for webhook runs`

---

## 完了の確認と報告

- [ ] **Step 1:** Task 1〜2 で触った bats を走らせる(`test/bats/.apm/packages/github/github-issue-autofix`、`test/bats/github-actions` の `loop-autofix-schedule.bats`、`loop-caller-parity.bats`、`workflow-header.bats`、`loop-write-contract.bats`、`test/bats/scripts/self/apm/sync_validate_mirror.bats`)。全体は走らせない。
- [ ] **Step 2:** 完了の報告(AGENTS.md の Completion)に、Implementation、Verification、Risks を書く。**未確認として明記する:** workflow を実行していない。L1 の観察(2週間以上、spec 第8節)なしで L2 に上げたこと。`detect_items` の Webhook の経路、pending と breaker の共有、定期実行と Webhook の同時実行は、実機で未確認。push の前に `AGENT_TOKEN` を更新する。
