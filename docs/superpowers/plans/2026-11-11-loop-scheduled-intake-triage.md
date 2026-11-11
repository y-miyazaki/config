# triage の定期実行(PR 2 / 段階 F)Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** code-review loop が起票した Issue を、1日1回の定期実行で triage(ラベルとコメント)する。Webhook の経路は変えず、定期実行との対象の重なりを作らない。

**Architecture:** `on-loop-github-issue-triage.yaml` に `schedule` を足し、`list` ジョブ(対象の Issue 番号の配列を作るだけ)と、既存の `loop` ジョブの matrix 化(`ci-loop-caller-entity.yaml` を Issue ごとに呼ぶ)に分ける。拾う条件の判断は一覧のスクリプトに、実行するかの判定は各 cell の `detect_issue.sh` に置く。PR 1(v1.9.7)で入った `handoff_artifact_suffix` と run-log の `target_key` を使う。

**Tech Stack:** bash、jq、`gh api`、GitHub Actions(reusable workflow、matrix)、bats。

**Spec:** [定期実行での取り込み 設計書](../specs/2026-11-11-loop-scheduled-intake-design.md)(第5節、第10節、第12節、第15.2節、第15.4節)。この plan は PR 2 だけを扱う。PR 3 以降は別の plan。

## Global Constraints

- 日本語で書く文書は既存の docs の文体に合わせる。コミットの末尾に `Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>` を付ける。
- 一覧のスクリプトは `scripts/self/loop/` に snake_case で置く(リポジトリ専用。配布物の skill には入れない)。対の bats を同じ commit で足す(BAT-01)。
- `detect_issue.sh` の編集元は `.apm/packages/github/.apm/skills/github-issue-triage/scripts/detect_issue.sh`。`.agents/`、`.claude/` などは `apm install`(Stop hook の `scripts/self/apm/sync_apm_artifacts.sh`)で同期し、手で編集しない。
- workflow の map のキーは A-Z 順(ORD-01)。`on` と `jobs` のキーは意味の順。
- hook が走らせるツール(actionlint、ghalint、zizmor、shellcheck、shfmt、prettier、markdownlint-cli2 など)は手で走らせない。bats は触ったディレクトリだけを走らせる(全体は走らせない)。
- `AGENT_TOKEN` が未更新なので、workflow の実行(`gh workflow run`)による確認はしない。
- 一覧のジョブは対象の集合を作るだけで、skip の判定はしない。判定は cell の `detect_issue.sh` が行う(不変条件6)。
- action のコードは変えない。したがって SHA pin の更新とリリースは不要。
- 拾う条件の値(spec 第5.4節): ラベル `loop:code-review` あり。`triage:needs-info`、`triage:ready`、`triage:failed` なし。open で PR でない。作成者の `user.type` が `Bot` で、本文に `<!-- code-review:fp:` を含む。triage の marker は `<!-- github-issue-triage:v1 -->`(`issue_comment.sh` の `COMMENT_MARKER`)。1回の件数は3、読む上限は200件、失敗の窓は7日、失敗の上限は3回。

## Review Focus

- 一覧の API が PR を返す(`pull_request` キーあり)。PR は対象にしない。
- 本文が `null` の Issue。marker なしとして除外し、スクリプトを落とさない。
- 一覧の API が失敗する(403、5xx)。`list` ジョブは失敗として見え、空配列で成功扱いにしない(Webhook の run は影響を受けない)。
- run-log に JSON でない行、`target_key` のない行(PR 1 より前の行)がある。無視して続ける。run-log が読めないときは外さずに進む(fail-open)。
- 最新の marker のコメントより古い人間のコメントだけがある Issue は、対応済みとして除外する。Bot のコメントは人間と数えない。
- 失敗が続く Issue が先頭3件を占めない(失敗3回で外れる。最終試行が古い順に並ぶ)。
- Webhook の `issue_comment` の再 triage は `loop:code-review` の Issue でも拒否しない。

---

### Task 1: `detect_issue.sh` の hydrate と `schedule`

**Files:**

- Modify: `.apm/packages/github/.apm/skills/github-issue-triage/scripts/detect_issue.sh`(`main` の hydrate 条件、`should_skip_issue`)
- Test: `test/bats/.apm/packages/github/github-issue-triage/detect_issue.bats`
- Sync(`apm install` による生成物。手で編集しない): `.agents/skills/github-issue-triage/scripts/detect_issue.sh` と、同じ内容の他の同期先

**Interfaces:**

- Consumes: 既存の `hydrate_issue_from_api_if_needed`、`should_skip_issue`。呼び出し側の `detect_env_json` が `ISSUE_NUMBER` と `ISSUE_EVENT_NAME` を渡す(Task 3)。
- Produces: `ISSUE_NUMBER` があり title / body / labels が空のとき、イベントの種別を問わず API で補う。`ISSUE_EVENT_NAME=schedule` のとき、`triage:*` のラベルが1つでもあれば skip し、なければ skip しない(`triage:failed` と Bot の作成者は今までどおり skip)。

- [ ] **Step 1: 失敗する bats を足す。** 既存のファイルの `gh` のスタブの方式に合わせる。ケース: (a) `GITHUB_EVENT_NAME=schedule`、`ISSUE_NUMBER=7`、`ISSUE_EVENT_NAME=schedule`、title / body / labels 空で API のスタブが title、body、`["loop:code-review"]` を返すとき、出力の `skip` が `false` で `result.title` が補われる。(b) 同じで labels が `["loop:code-review","triage:ready"]` のとき `skip` が `true`。(c) `["loop:code-review","triage:needs-info"]` と `["triage:failed"]` でも `true`。(d) `ISSUE_EVENT_NAME=schedule` で `needs-triage` だけのとき `false`。(e) `workflow_dispatch` の既存のケースは変えず、`triage:ready` ありでも `false` のままであること。
- [ ] **Step 2: 失敗を確かめる。** `bats test/bats/.apm/packages/github/github-issue-triage/detect_issue.bats`。(a)〜(d) が失敗する。
- [ ] **Step 3: 実装。** `main` の hydrate の条件を、`ISSUE_NUMBER` があり title / body / labels のどれかが空のとき(`GITHUB_EVENT_NAME` を問わない)に API で補うよう変える。`ISSUE_EVENT_NAME` の既定(`workflow_dispatch`)は、変数が未設定のときだけ働くので変えない。`should_skip_issue` の `triage:failed` の判定の後、`workflow_dispatch` の分岐の前に `schedule` の分岐を置く(`triage:` で始まるラベルが1つでもあれば `return 0`、なければ `return 1`)。関数の header コメント(Globals など)と、ファイル先頭の使い方の説明も更新する。
- [ ] **Step 4: 同期して確かめる。** `apm install` で同期先を更新する(Stop hook でも走る)。Step 2 の bats が通る。`test/bats/scripts/self/apm/sync_validate_mirror.bats` を走らせて、同期先との一致を確かめる。
- [ ] **Step 5: Commit。** `fix(triage): hydrate issue fields and honor schedule in detect_issue.sh`

---

### Task 2: 一覧のスクリプト `list_triage_issues.sh`

**Files:**

- Create: `scripts/self/loop/list_triage_issues.sh`
- Test: `test/bats/scripts/self/loop/list_triage_issues.bats`(`render_code_review_issues.bats` の `setup` と `gh` のスタブの書き方に合わせる)

**Interfaces:**

- Consumes: PR 1 で run-log に入った `target_key`(`entity:issue:<N>`)。run-log は `.loop/loop-run-log.md` の JSONL(行頭が `{`)。各行に `run_id`(ISO 8601 の時刻)、`loop_name`、`outcome`、`target_key`。
- Produces: 環境変数 `GITHUB_REPOSITORY`、`GH_TOKEN`、`RUN_LOG_FILE`(既定 `.loop/loop-run-log.md`)、`LOOP_NAME`(既定 `github-issue-triage`)、`TRIAGE_LIST_LIMIT`(既定 3)、`TRIAGE_SCAN_LIMIT`(既定 200)、`TRIAGE_FAIL_WINDOW_DAYS`(既定 7)、`TRIAGE_FAIL_MAX`(既定 3)、`GITHUB_OUTPUT`。`GITHUB_OUTPUT` に `issues=<Issue 番号の昇順でなく、選んだ順のコンパクトな JSON 配列>` と `count=<件数>` を書く。0件のとき `::notice` を出して `issues=[]`、`count=0`、終了コード 0。`gh api` が失敗したときは終了コード 1。

関数(それぞれ header コメントを付ける。名前は例):

- `fetch_open_issues`: `gh api --paginate "repos/${GITHUB_REPOSITORY}/issues?labels=loop%3Acode-review&state=open&sort=created&direction=asc&per_page=100"` を `TRIAGE_SCAN_LIMIT` 件で打ち切る。
- `is_candidate`(jq の式でよい): `pull_request` なし、ラベルの条件、`user.type == "Bot"`、本文(`null` は空文字)に `<!-- code-review:fp:` を含む。
- `is_handled`: Issue のコメント(`gh api repos/{repo}/issues/{N}/comments --paginate`。Issue ごとに最大1回)から、本文に triage の marker を含む最新の `created_at` を求め、それより新しい `user.type != "Bot"` のコメントがなければ対応済み(除外)。marker のコメントがなければ対応済みでない。
- `recent_failure_count` / `last_attempt`: run-log の行を1行ずつ `jq` で読み(JSON でない行は無視)、`loop_name` と `target_key` が一致する行から、直近 `TRIAGE_FAIL_WINDOW_DAYS` 日の `outcome` が `error` または `rejected` の数と、`outcome != skipped` の最大の `run_id` を求める。run-log が読めない(ファイルなし、読み取り失敗)ときは 0 件・記録なしとして進む。
- 並び: 除外をすべてかけた後で、最終試行の古い順(記録なしが先、同順位は API の順)に並べて `TRIAGE_LIST_LIMIT` 件で切る。header に、読む件数の上限(200)とコメント API の呼び出し回数の上限(Issue ごとに最大1回)を書く。

- [ ] **Step 1: 失敗する bats を足す。** ケース(各ケースの Issue は `gh` のスタブの JSON の fixture): (a) 条件を満たす Issue が選ばれる。(b) `triage:ready`、`triage:needs-info`、`triage:failed` のいずれかがあると外れる。(c) `pull_request` ありは外れる。(d) 作成者が `User` の Issue、marker のない Issue、本文 `null` の Issue は外れる。(e) marker のコメントがあり、より新しい人間のコメントがなければ外れる。(f) 同じで、marker より新しい人間のコメントがあれば選ばれる。(g) marker より新しい Bot のコメントだけなら外れたまま。(h) marker より古い人間のコメントだけなら外れたまま。(i) run-log に直近7日の `error` / `rejected` が3回ある Issue は外れ、2回なら残り、8日前の3回は数えない。(j) `skipped` は失敗に数えない。(k) 除外の後で3件に切る(先頭3件が除外される Issue でも、後ろの Issue が選ばれる)。(l) 最終試行が古い順で、記録のない Issue が先。(m) run-log がない、JSON でない行や `target_key` のない行があっても落ちず、外さずに進む。(n) 0件のとき `::notice`、`issues=[]`、終了コード 0。(o) `gh api` の失敗で終了コード 1(空配列で成功しない)。(p) 200件で打ち切る。
- [ ] **Step 2: 失敗を確かめる。** `bats test/bats/scripts/self/loop/list_triage_issues.bats`。
- [ ] **Step 3: 実装。** 上の Interfaces と関数の分け方に従う。`set -euo pipefail`、`umask 027`、他の `scripts/self/loop/*.sh` と同じ header と関数の doc コメントの形式。`jq` の引数は `--arg` / `--argjson` で渡し、Issue のタイトルや本文をシェルの式に展開しない。
- [ ] **Step 4: 通ることを確かめる。** Step 2 のコマンド。
- [ ] **Step 5: 3層の包含の bats を足す。** 同じファイルに、(q) 一覧が選んだ各 Issue のラベル(`loop:code-review` のみ)で `detect_issue.sh`(Task 1 の同期済みの `.agents/skills/github-issue-triage/scripts/detect_issue.sh`)を `ISSUE_EVENT_NAME=schedule`、`ISSUE_ACTOR_TYPE=User` で走らせると `skip` が `false`。(r) 一覧が外す `triage:*` ありの Issue では `skip` が `true`(一覧と detect の対応)。
- [ ] **Step 6: Commit。** `feat(loop): add scheduled triage issue lister`

---

### Task 3: workflow(`schedule`、`list` ジョブ、matrix、`if`、concurrency)

**Files:**

- Modify: `.github/workflows/on-loop-github-issue-triage.yaml`
- Create: `test/bats/github-actions/loop-triage-schedule.bats`(`loop-caller-parity.bats` の `yq` / `grep` の読み方に合わせる)
- 確認: `test/bats/github-actions/loop-caller-parity.bats`(dogfood の caller が宣言済みの入力だけを渡すこと、`loop-state-main` の group など既存の検査)が通ること

**Interfaces:**

- Consumes: Task 2 の `scripts/self/loop/list_triage_issues.sh`(出力 `issues`、`count`)。`ci-loop-caller-entity.yaml` の入力 `handoff_artifact_suffix`(PR 1、v1.9.7)。run-log は `.loop/loop-run-log.md`(main の checkout にある)。
- Produces: `on.schedule`(1日1回。時刻は `rg -n 'cron:' .github/workflows/on-loop-*.yaml` で他の定期実行と重ならない時刻を選ぶ)。`list` ジョブ(`if: github.event_name == 'schedule'`、permissions は `contents: read` と `issues: read`、checkout に `persist-credentials: false`、GitHub トークンは `github.token`)。`loop` ジョブの matrix。

変更の内容(spec 第5.2節、第5.3節):

1. **`list` ジョブ。** checkout の後、`bash scripts/self/loop/list_triage_issues.sh` を `GH_TOKEN: ${{ github.token }}`、`GITHUB_REPOSITORY` で走らせ、出力 `issues`、`count` をジョブの outputs にする。`timeout-minutes` を付ける。
2. **`loop` ジョブ。** `needs: list`。`if` は `!cancelled()` を先頭に置き、`needs.list.result == 'success' || needs.list.result == 'skipped'` を要求し、かつ「`schedule` なら `needs.list.outputs.count > 0`(`fromJSON` は使わない。出力が空文字でも式が失敗しない)、それ以外なら今の Webhook / dispatch のゲート」。`ci-loop-caller.yaml` の `execute` の `if` の書き方に揃える。
3. **Webhook の `if`。** `issues` の分岐に、`!contains(github.event.issue.labels.*.name, 'loop:code-review')` を足す。`issue_comment` の分岐と `workflow_dispatch` は変えない。コメントの説明も更新する。
4. **matrix。** `strategy: { fail-fast: false, matrix: { issue: <式> }, max-parallel: 3 }`(キーは A-Z 順)。式は `fromJSON(needs.list.outputs.issues || format('[{0}]', github.event.issue.number || inputs.issue_number || 0))`。`list` が skipped のときの出力は空文字で、`||` の右辺に落ちる。**短絡評価には頼らない**(右辺は常に評価されても害がない形)。`detect_env_json` は、`schedule` のとき `{"ISSUE_EVENT_NAME":"schedule","ISSUE_NUMBER":<matrix.issue>}`、`workflow_dispatch` のとき `{"ISSUE_NUMBER":<番号>}`、それ以外は `{}`(今のまま。Webhook は event payload から補う)。`handoff_artifact_suffix: -issue-${{ matrix.issue }}`。
5. **concurrency。** `group` は `schedule` のとき `loop-state-main`、それ以外は今の式のまま。`queue: max` と `cancel-in-progress: false` は変えない。`run-name` は `schedule` でも読める形にする。

- [ ] **Step 1: 失敗する bats を足す。** `loop-triage-schedule.bats` に: (a) `on` に `schedule` が1つあり、`workflow_dispatch` と `issues`、`issue_comment` が残る。(b) `list` ジョブの `if` が `schedule` だけ、permissions が `contents: read` と `issues: read` だけ。(c) `loop` ジョブが `needs: list` で、`if` が `!cancelled()` と `needs.list.result` を含み、`github.event_name == 'schedule'` の分岐を持つ。(d) `strategy.fail-fast` が `false`、`max-parallel` が `3`、matrix の式が `needs.list.outputs.issues` を読み、`handoff_artifact_suffix` が `-issue-` で始まる。(e) concurrency の group が `schedule` のとき `loop-state-main`。(f) Webhook の `if` の `issues` の分岐に `loop:code-review` の拒否があり、`issue_comment` の分岐にはない(`yq` で `if` の文字列を取り、分岐ごとに分けて確かめる)。(g) `if` の `issues` の分岐で、Bot の送信者の拒否(`sender.type != 'Bot'`)と `triage:failed` の拒否が残る。
- [ ] **Step 2: 失敗を確かめる。** `bats test/bats/github-actions/loop-triage-schedule.bats`。
- [ ] **Step 3: workflow を編集する。** 上の変更1〜5。ファイル先頭の `Usage:`(Runs on)と `Description` に `schedule` を足す。
- [ ] **Step 4: 通ることを確かめる。** Step 2 のコマンドと `bats test/bats/github-actions/loop-caller-parity.bats`。actionlint、ghalint、zizmor は Stop hook の結果を見る(手で走らせない)。matrix の式と `if` の指摘が出たら式を直す。
- [ ] **Step 5: Commit。** `feat(loop): schedule github-issue-triage and gate webhook intake by label`

---

### Task 4: docs

**Files:**

- Modify: `docs/explanation/loop-engineering/workflows/loop-github-issue-triage-workflow-design.md`(定期実行の経路、経路の分離、`Supported use cases` を **User actions** に置き換えて spec 第15.2節を転記し、状態を持つ workflow として遷移 ID の列を付ける)
- Create: `docs/explanation/loop-engineering/loop-issue-handoff.md`(spec 第15.4節の triage 側 T0〜T4 の表。autofix 側 A0〜A6 は PR 3 以降の挙動なので、「段階 D 以降」と明記して表だけ置く)
- Modify: `docs/explanation/loop-engineering/loop-engineering-design.md`(Intake Gating: 定期実行の経路と Webhook の経路の分離、一覧のスクリプトという第3の層、不変条件6の言い換え。Failure Mode Countermeasures: triage の再試行の上限)
- Modify: `docs/superpowers/specs/2026-08-11-issue-triage-entity-loops-design.md`(定期実行の経路を足したことの追記)、`docs/superpowers/specs/2026-11-09-loop-improvement-handoff-overview.md`(第5.2節の「人間が作った Issue も triage で拾われる」を取り下げたことの注記)
- Modify: `docs/explanation/loop-engineering/common-loop-triage-format.md`、`loop-capable-skills.md`(`result.items` は PR 3 で使うので、「PR 2 では未使用」と一言だけ書くか、PR 3 に回すかを、既存の文書の書き方で判断する)
- Modify: `mkdocs.yml`(`loop-issue-handoff.md` を `nav` に足す)

**Interfaces:**

- Consumes: spec 第12節の更新の一覧、第15.2節と第15.4節の表。規則の本文は1か所だけに書き、User actions と状態遷移の表は節か遷移 ID を参照する(spec 第15節)。
- Produces: ユーザーが実際に起こす操作と loop の応答、ユーザーに見える結果、次の操作が、triage の設計書にすべて書かれている。

- [ ] **Step 1: 上の各ファイルを、今の内容を読んでから編集する。** docs 内のリンクは、相対の `.md` で、リンクのテキストは相手の文書の題名にする(DOC-05)。「上記」「後述」は使わず節へのリンクにする(TERM-10)。コードのブロックには言語を付ける。
- [ ] **Step 2: 内容を実装と照らす。** 一覧の条件の値(ラベル、marker、件数3、窓7日、失敗3回、200件)、workflow の `if` の条件、cron の時刻が、docs と実装で一致している(TERM-08、TERM-09)。実際に決めた cron の時刻を書く。
- [ ] **Step 3: 検査。** markdownlint-cli2 と markdown-link-check は Stop hook の結果を見る(手で走らせない)。`mkdocs.yml` の `nav` が新しいファイルを指していることを確かめる。
- [ ] **Step 4: Commit。** `docs(loop): document scheduled triage intake and issue handoff states`

---

## 完了の確認と報告

- [ ] **Step 1:** Task 1〜3 で触った bats のディレクトリだけを走らせる(`test/bats/.apm/packages/github/github-issue-triage`、`test/bats/scripts/self/loop`、`test/bats/github-actions` のうち `loop-triage-schedule.bats` と `loop-caller-parity.bats`)。全体は走らせない。
- [ ] **Step 2:** 完了の報告(AGENTS.md の Completion)に、Implementation、Verification、Risks を書く。**未確認として明記する:** matrix の式と `if` の挙動(`list` が skipped のときの `fromJSON`)、`loop-state-main` の `queue: max`、Webhook の run が動くことは、`AGENT_TOKEN` の更新後の dogfood で確認する(`workflow_dispatch` で Issue 番号を指定、Webhook の `issues` の経路、`schedule` の `workflow_dispatch` 起動)。
