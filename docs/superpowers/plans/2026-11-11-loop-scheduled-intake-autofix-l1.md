# autofix の定期実行 L1(PR 3 / 段階 D)Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** code-review が起票した Issue を、autofix が定期実行で直接拾い、L1(観察。PR は作らず、修正方針をログに出す)で動かす。Webhook / `repository_dispatch` / `workflow_dispatch` の既存の経路(L2)は変えない。

**Architecture:** `detect_autofix.sh` に一覧のモード(`AUTOFIX_SCAN=true`)を足し、`result.items` を返す。`on-loop-github-issue-autofix.yaml` に、`schedule` 専用のジョブ `loop-scheduled`(`ci-loop-caller.yaml`、L1、`delivery: none`、`detect_items: true`)を足す。対象ごとのキー(`integration:main#issue:<N>`)の breaker・pending・`last_run` の並べ替え・上限は、PR 1(v1.9.7)で入った platform が行う。

**Tech Stack:** bash、jq、`gh`、GitHub Actions、bats。

**Spec:** [定期実行での取り込み 設計書](../specs/2026-11-11-loop-scheduled-intake-design.md)(第6節、第10節、第12節、第15.3節、第15.4節)。段階 E(L2 への昇格と Webhook の経路のキー化、PR 4)はこの plan の範囲外(2週間以上の観察の後)。

## Global Constraints

- コミットの末尾に `Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>`。bats は触ったディレクトリだけ(全体は走らせない)。hook が走らせるツール(actionlint、ghalint、zizmor、shellcheck、shfmt、prettier、markdownlint-cli2、markdown-link-check)は手で走らせない。`AGENT_TOKEN` が未更新なので workflow は実行しない。push はしない。
- `detect_autofix.sh` の編集元は `.apm/packages/github/.apm/skills/github-issue-autofix/scripts/detect_autofix.sh`。`.agents/`、`.claude/` などは `scripts/self/apm/sync_apm_artifacts.sh`(`apm install`)で同期し、手で編集しない。bats は `test/bats/.apm/packages/github/github-issue-autofix/detect_autofix.bats`。**既存の単一 Issue のモード(`AUTOFIX_SCAN` なし)の挙動と出力は変えない。**
- 配布物(`.apm/packages/**`)は他のリポジトリにも配られるので、このリポジトリ固有の語(`loop:code-review`、`loop-automation`、code-review の marker)は、環境変数で受け取る(既定値は持たせず、一覧のモードで未設定なら失敗させる)か、一覧のモードを caller の `detect_env_json` で明示させる。値は caller(dogfood)が渡す: `AUTOFIX_SCAN=true`、`AUTOFIX_SOURCE_LABEL=loop:code-review`、`AUTOFIX_SOURCE_MARKER=<!-- code-review:fp:`、`AUTOFIX_PR_LABEL=loop-automation`、`AUTOFIX_BRANCH_PREFIX=loop/github-issue-autofix/`、`AUTOFIX_MAX_OPEN_PRS=3`。
- workflow の map のキーは A-Z 順(ORD-01)。**workflow レベルの `permissions` は `{}` にし、各ジョブに置く**(PR 2 の最終レビューの指摘。ジョブが2つ以上ある workflow は ghalint の `job_permissions` に当たる)。`loop` ジョブの permissions は今のブロックと同じ。
- 拾う条件(spec 6.2): open、PR でない、`AUTOFIX_SOURCE_LABEL` あり、`autofix` ラベルなし、作成者の `user.type` が `Bot`、本文に `AUTOFIX_SOURCE_MARKER` を含む。除外: `Fixes #N` の PR が開いている Issue。対応済み(その Issue を `Fixes #N` で参照する閉じた autofix の PR があり、その最新の `closedAt` が、人間(`user.type != "Bot"`)の最新のコメントの時刻より新しい)。**最大50件まで、切らずに返す**(切るのは platform の `detect_max_targets`)。
- 段階 D の caller 設定(spec 6.1、6.5): `level: L1`、`delivery: none`、`detect_items: true`、`detect_branch_match: main`、`detect_script` は `detect_autofix.sh`、`detect_max_targets: 3`、`agent_edit_*` / `agent_unchanged_verdict` / `finalize_script` は渡さない(L1 の検証)。concurrency の group は `schedule` のとき `loop-state-main`(workflow 全体)、それ以外は今の式。

## Review Focus

- 一覧のモードで GitHub の API が失敗した(Issue 一覧、PR 一覧、コメント)。空の対象で成功扱いにせず、`status: error` で exit 1 にする(既存の `output_error`)。
- Issue の本文が `null`、`user` が欠けている、ラベルが多い。落とさずに除外する。
- 同じ Issue を `Fixes #N` で参照する閉じた PR が複数ある。最新の `closedAt` を使う。マージ済みの閉じた PR(Issue はたいてい閉じている)も同じ扱い。
- `Fixes #1` が `Fixes #12` に誤って当たらない(`\b` つきの照合)。
- 開いている autofix の PR が `AUTOFIX_MAX_OPEN_PRS` 以上のとき、一覧のモードだけが skip し、単一 Issue のモード(Webhook)は止まらない。
- Webhook の `issues` イベントは `loop` ジョブだけ、`schedule` は `loop-scheduled` ジョブだけが動く(両方の `if`)。

---

### Task 1: `detect_autofix.sh` の一覧のモード

**Files:**

- Modify: `.apm/packages/github/.apm/skills/github-issue-autofix/scripts/detect_autofix.sh`(関数を足す。`main` に `AUTOFIX_SCAN=true` の分岐を足す)
- Test: `test/bats/.apm/packages/github/github-issue-autofix/detect_autofix.bats`(既存の `gh` のスタブの方式に合わせる)
- Sync(生成物。手で編集しない): `.agents/skills/github-issue-autofix/scripts/detect_autofix.sh` と同内容の他の同期先、`apm.lock.yaml`(同期が再生成する分)

**Interfaces:**

- Consumes: 環境変数 `AUTOFIX_SCAN`、`AUTOFIX_SOURCE_LABEL`、`AUTOFIX_SOURCE_MARKER`、`AUTOFIX_PR_LABEL`、`AUTOFIX_BRANCH_PREFIX`、`AUTOFIX_MAX_OPEN_PRS`(整数。未設定なら上限なし)、`GITHUB_REPOSITORY`、`GH_TOKEN` / `GITHUB_TOKEN`。既存の `ensure_pr_scan_prerequisites`、`output_error`、`json_object`(`lib/json.sh`)。
- Produces: `AUTOFIX_SCAN=true` のとき、`{"status":"ok","skip":false,"message":"...","result":{"items":[{"key":"issue:<N>","entity":{"kind":"issue","number":<N>},"context":{"issue_number":<N>}}]}}`(古い Issue が先)。対象が0件、または開いている autofix の PR が `AUTOFIX_MAX_OPEN_PRS` 以上のときは `{"status":"ok","skip":true,"message":"...","result":{}}`。`AUTOFIX_SCAN=true` で `AUTOFIX_SOURCE_LABEL`、`AUTOFIX_SOURCE_MARKER`、`AUTOFIX_PR_LABEL` のどれかが空なら `output_error`。

関数(それぞれ header コメントを付ける。名前は例):

- `scan_validate_env`: 上の必須の環境変数を検証する。
- `scan_open_pr_count`: `gh pr list --repo ... --state open --label "${AUTOFIX_PR_LABEL}" --json headRefName` を1回取り、`headRefName` が `AUTOFIX_BRANCH_PREFIX` で始まるものを jq で数える(`--arg` で渡す)。
- `scan_fetch_issues`: `gh api --paginate "repos/${GITHUB_REPOSITORY}/issues?labels=<URL エンコードしたラベル>&state=open&sort=created&direction=asc&per_page=100"` を、Issue ごとの jq の候補フィルタに通す(`pull_request` なし、`autofix` ラベルなし、`user.type == "Bot"`、本文(`null` は空)に marker を含む)。
- 開いている PR の除外は、`gh pr list --state open --json number,title,body` を**1回だけ**取り、既存の `open_pr_fixes_issue` と同じ正規表現(`(?i)\b(fix(?:e[sd])?|close[sd]?|resolve[sd]?)\s+#N\b`)を各候補にかける。
- 対応済みの除外: `gh pr list --repo ... --state closed --label "${AUTOFIX_PR_LABEL}" --limit 200 --json number,body,closedAt,headRefName` を**1回だけ**取り、候補ごとに `Fixes #N` で参照する PR の最新の `closedAt` を求める。ある場合だけ、その Issue のコメントを REST(`gh api --paginate repos/.../issues/N/comments`)で取り、`user.type != "Bot"` の最新の `created_at` が `closedAt` 以前(または人間のコメントなし)なら除外する。`closedAt` より新しい人間のコメントがあれば拾う(spec 6.2、第15.3節 A4→A1)。コメント API は、閉じた PR で参照された候補だけに、Issue ごと最大1回。
- 最大50件に切る(spec 6.2)。

- [ ] **Step 1: 失敗する bats を足す。** ケース: (a) 条件を満たす Issue が `result.items` に入り、`key` が `issue:<N>`、順が古い順。(b) `pull_request` あり、`autofix` ラベルあり、ラベルなし、作成者が `User`、marker なし、本文 `null` は外れる。(c) 開いている PR が `Fixes #N` で参照する Issue は外れ、`Fixes #1` が Issue 12 を外さない。(d) 閉じた autofix の PR があり、人間のコメントがない Issue は外れる。(e) 同じで `closedAt` より新しい人間のコメントがあれば入る。(f) 新しいコメントが Bot なら外れたまま。(g) 閉じた PR が複数あるとき最新の `closedAt` を使う。(h) 閉じた PR のない Issue ではコメント API を呼ばない(スタブの呼び出しログで確認)。(i) 51件以上の候補でも50件で切る(3件に切らない)。(j) 0件で `skip: true`。(k) 開いている autofix の PR(`AUTOFIX_BRANCH_PREFIX` で始まる head)が `AUTOFIX_MAX_OPEN_PRS` 以上なら `skip: true`、未満なら通常。(l) `AUTOFIX_SCAN` なし(単一 Issue のモード)では `AUTOFIX_MAX_OPEN_PRS` を無視し、出力が今までと同じ。(m) 必須の環境変数の欠落で `status: error` と exit 1。(n) `gh` の失敗で `status: error` と exit 1(空の items で成功しない)。(o) 本文のテキストにシェルや jq の特殊文字を含む Issue でも落ちない。
- [ ] **Step 2: 失敗を確かめる。** `bats test/bats/.apm/packages/github/github-issue-autofix/detect_autofix.bats`。
- [ ] **Step 3: 実装。** 上の関数と `main` の分岐。`main` は `AUTOFIX_SCAN=true` のとき `ISSUE_NUMBER` を要求せず、`ensure_pr_scan_prerequisites` の後に一覧を作る。header(Design Rules、Optional environment)と関数の doc コメントを更新する。
- [ ] **Step 4: 同期して確かめる。** `bash scripts/self/apm/sync_apm_artifacts.sh`(出力はファイルへ。パイプで切らない)で同期し、Step 2 の bats が通ること、`test/bats/scripts/self/apm/sync_validate_mirror.bats` が通ることを確かめる。
- [ ] **Step 5: Commit。** `feat(autofix): add scan mode that lists code-review Issues as result.items`

---

### Task 2: workflow(`loop-scheduled`、concurrency、`if`、permissions)

**Files:**

- Modify: `.github/workflows/on-loop-github-issue-autofix.yaml`
- Create: `test/bats/github-actions/loop-autofix-schedule.bats`(`loop-triage-schedule.bats` の読み方に合わせる)
- 確認: `loop-caller-parity.bats`(dogfood の caller が宣言済みの入力だけを渡し、必須の入力を渡すこと)、`workflow-header.bats`、`loop-write-contract.bats`(L1 の契約)

**Interfaces:**

- Consumes: Task 1 の一覧のモード(`detect_env_json` で環境変数を渡す)。`ci-loop-caller.yaml` の入力(`detect_items`、`detect_branch_match`、`detect_max_targets`、`detect_pr_enabled`、`delivery`、`level`、`loop_name` ほか。宣言は `.github/workflows/ci-loop-caller.yaml`)。
- Produces: `on.schedule`(1日1回。`rg -n 'cron:' .github/workflows/on-loop-*.yaml` で他と重ならない時刻を選ぶ。報告する)。`loop-scheduled` ジョブ。

変更の内容(spec 6.1、6.3、6.5):

1. `on` に `schedule` を足す。`on` のキーは意味の順で、`workflow_dispatch` の入力は変えない。
2. workflow レベルの `permissions` を `{}` にし、現在のブロック(`actions`、`contents`、`copilot-requests`(`# zizmor: ignore[excessive-permissions]` を保つ)、`issues`、`pull-requests` の `write`)を `loop` と `loop-scheduled` の両方に置く(called workflow が必要とする権限を満たすこと。`ci-loop-caller.yaml` のジョブの permissions を確かめる)。
3. `concurrency.group`: `github.event_name == 'schedule' && 'loop-state-main' || <今の式>`。`queue: max`、`cancel-in-progress: false` は変えない。`run-name` は `schedule` でも読める形にする。
4. `loop` の `if`: `github.event_name != 'schedule' && (github.event_name != 'issues' || github.event.label.name == 'autofix')`。設定は変えない(L2、段階 E まで)。
5. `loop-scheduled`: `if: github.event_name == 'schedule'`、`uses: ./.github/workflows/ci-loop-caller.yaml`、`level: L1`、`delivery: none`、`detect_items: true`、`detect_branch_match: main`、`detect_script: .agents/skills/github-issue-autofix/scripts/detect_autofix.sh`、`detect_max_targets: 3`、`loop_name: github-issue-autofix`、`state_branch: main`、`detect_env_json` に Task 1 の環境変数(値は Global Constraints)、`agent_engine`、`agent_maker_*`、`agent_checker_*`(L1 で checker を使うかは `ci-loop-caller.yaml` と他の L1 の caller(`on-loop-github-issue-triage.yaml`)の渡し方に合わせる。L1 で渡してはいけない入力は渡さない)、`agent_tool_allowlist`(`loop` と同じ読み取り専用の許可。`bash .claude/skills/*/scripts/validate.sh` の行は不要なので外す)、`budget_*`(`loop` と同じ)、secrets は `loop` と同じ。`agent_maker_instructions`: 修正の方針(対象のファイル、変更の概要、リスク)を出力するだけで、ファイルを編集せず、PR を作らず、`repository_dispatch` を呼ばない。方針がログ(ジョブの step summary か、L1 の出力先)に出ることを、`ci-loop-agent.yaml` の L1 の経路で確かめ、出ない場合は報告する。
6. ファイル先頭の `Description` / `Usage`(Runs on)に `schedule` と一覧のモードを足す。

- [ ] **Step 1: 失敗する bats を足す。** `loop-autofix-schedule.bats`: (a) `on` に `schedule` が1つ、`issues`(`labeled`)、`repository_dispatch`、`workflow_dispatch` が残る。(b) workflow レベルの `permissions` が `{}`、`loop` と `loop-scheduled` の各ジョブの permissions が同じ5つの write。(c) `concurrency.group` が `schedule` のとき `loop-state-main`、`queue: max`。(d) `loop` の `if` が `schedule` を除外し、`issues` は `autofix` ラベルだけ。(e) `loop-scheduled` の `if` が `schedule` だけ、`level: L1`、`delivery: none`、`detect_items: true`、`detect_branch_match: main`、`detect_max_targets: 3`、`detect_script` が `detect_autofix.sh`。(f) `loop-scheduled` が `agent_edit_target`、`agent_edit_allowlist`、`agent_edit_denylist`、`agent_unchanged_verdict`、`finalize_script`、`pr_draft`、`pr_title`、`pr_body` を渡さない。(g) `loop-scheduled` の `detect_env_json` が `AUTOFIX_SCAN`、`AUTOFIX_SOURCE_LABEL`、`AUTOFIX_SOURCE_MARKER`、`AUTOFIX_PR_LABEL`、`AUTOFIX_BRANCH_PREFIX`、`AUTOFIX_MAX_OPEN_PRS` を含み、有効な JSON になる形(`fromJSON` で解釈できるリテラル)。(h) `loop` ジョブの設定(`level: L2`、`delivery: pr_create`、`detect_env_json`)が今までと同じ。(i) `loop-scheduled` の maker の instructions が編集と PR の作成を禁じている。
- [ ] **Step 2: 失敗を確かめる。** `bats test/bats/github-actions/loop-autofix-schedule.bats`。
- [ ] **Step 3: workflow を編集する。** 上の変更1〜6。
- [ ] **Step 4: 通ることを確かめる。** Step 2 のコマンド、`loop-caller-parity.bats`、`workflow-header.bats`、`loop-write-contract.bats`。actionlint、ghalint、zizmor は Stop hook の結果を見る(手で走らせない)。
- [ ] **Step 5: Commit。** `feat(autofix): add scheduled L1 observation job for code-review Issues`

---

### Task 3: docs

**Files:**

- Modify: `docs/explanation/loop-engineering/workflows/loop-github-issue-autofix-workflow-design.md`(`Supported use cases` を **User actions** に置き換え、spec 第15.3節を転記して遷移 ID の列(A0〜A6)を付ける。「Intake paths」の節を足し、拾う条件、除外、上限を**1か所だけ**に書く。非目標の「`autofix` ラベルなしの自動 autofix」を、段階 D(L1)の観察として改める。段階 E 以降の記述(L2、Webhook のキー化)は「未実装」と明記)
- Modify: `docs/explanation/loop-engineering/loop-issue-handoff.md`(autofix 側 A0〜A6 の表を「段階 D(L1)で動く部分」と「段階 E 以降(未実装)」に分ける。A2 の L1 は方針をログに出すだけ)
- Modify: `docs/explanation/loop-engineering/loop-engineering-design.md`(Intake Gating の autofix の行に、定期実行の経路と `autofix` ラベルによる Webhook との分離を足す。STATE Files に対象ごとのキー(`#`)と prune を足す。Multi-loop Coordination に定期実行の `loop-state-main` を足す)
- Modify: `docs/explanation/loop-engineering/workflows/loop-caller-inputs-reference.md`、`docs/reference/specification.md`(PR 1 で入った `detect_items`、`handoff_artifact_suffix`、`loop-worktree-setup` の `target_key`、run-log の `target_key` を、まだ書かれていなければ足す。既にあれば変えない)
- Modify: `docs/explanation/loop-engineering/common-loop-triage-format.md`、`loop-capable-skills.md`(`result.items` の説明を、実装に合わせて確かめる)

**Interfaces:**

- Consumes: Task 1、2 の実装(値は実装から読む。cron の時刻は workflow から)、spec の第12節、第15.3節、第15.4節、第6節。
- Produces: autofix の設計書の User actions と Intake paths、handoff の状態遷移の表(autofix 側)、横断の docs。

- [ ] **Step 1: 各ファイルを、今の内容を読んでから編集する。** `.claude/rules/markdown.md` に従う: 相対 `.md` リンクで、リンクのテキストは相手の題名(DOC-05)。「上記」「後述」は使わず節へのリンク(TERM-10)。コードのブロックに言語(TERM-07)。規則の本文は1か所だけに書き、User actions と遷移の表は節か遷移 ID を参照する(spec 第15節)。`docs/` にファイルを足さないので `mkdocs.yml` は変えない。
- [ ] **Step 2: 内容を実装と照らす。** 一覧の条件(ラベル、marker、`autofix` ラベルなし、開いている PR、対応済み、50件、`AUTOFIX_MAX_OPEN_PRS`)、`loop-scheduled` の設定(L1、`delivery: none`、`detect_max_targets: 3`)、cron の時刻が、docs と実装で一致している(TERM-08、TERM-09)。`result.items` の説明が実装(PR 1)と一致している。
- [ ] **Step 3: 検査。** markdownlint-cli2、markdown-link-check は Stop hook の結果を見る(手で走らせない)。
- [ ] **Step 4: Commit。** `docs(loop): document scheduled autofix L1 observation and issue handoff states`

---

## 完了の確認と報告

- [ ] **Step 1:** Task 1〜2 で触った bats のディレクトリだけを走らせる(`test/bats/.apm/packages/github/github-issue-autofix`、`test/bats/github-actions` の `loop-autofix-schedule.bats`、`loop-caller-parity.bats`、`workflow-header.bats`、`loop-write-contract.bats`、`test/bats/scripts/self/apm/sync_validate_mirror.bats`)。全体は走らせない。
- [ ] **Step 2:** 完了の報告(AGENTS.md の Completion)に、Implementation、Verification、Risks を書く。**未確認として明記する:** workflow を実行していない(`AGENT_TOKEN` の更新後に、`schedule` の手動確認、`loop-state-main` の直列、L1 の方針のログの出方、`detect_items` の実機の挙動を確かめる)。**段階 E(PR 4)は、2週間以上の観察と第2.2節の条件の確認の後**(この plan の範囲外)。
