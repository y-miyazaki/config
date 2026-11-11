# 定期実行での取り込み(対象ごとのターゲット、triage / autofix の定期実行)

**Status:** Draft(第3版。独立レビュー第3回までの High・Medium を反映し、第4回で High・Medium なし(矛盾1件と古い記述を修正済み))
**Date:** 2026-11-11
**Related:** [全体構想と論点](2026-11-09-loop-improvement-handoff-overview.md)(第3.2、3.3、3.5、5節の具体化)、[code-review loop](2026-11-09-loop-code-review-design.md)(段階 B・C。実装済み)、[Loop Engineering Design — Design Principles](../../explanation/loop-engineering/loop-engineering-design.md#design-principles)、[Issue triage / autofix の entity loop](2026-08-11-issue-triage-entity-loops-design.md)

## 0. ユーザーが決めたこと(2026-11-11)

overview から外れる決定は、ここに記録する。

1. **autofix は triage の出力を入力にしない。** autofix は、code-review が起票した Issue(第6.2節の条件)を直接拾う。triage(L1、checker なし)が付けたラベルを L2 の autofix の入力にしない(Maker-Checker と Graduated Autonomy を守る)。overview 第5.2節の「人間が作った Issue も、triage で `triage:ready` と `bug` になれば拾われる」は**取り下げる**。人間が作った Issue は、今までどおり人間が `autofix` ラベルを付ける。
2. **対応済みの Issue は、人間の新しいコメントがあるまで拾わない**(第5.4節、第6.2節)。`consecutive_failures` は処理の失敗(checker の REJECT の連続など)を数える circuit breaker のままにし、PR を人間が閉じたことは数えない。Issue を閉じるかどうかは人間の判断とする。
3. **triage の低確信の Issue は、一覧側で除外する**(第5.4節)。skill の契約(FSM)は変えない。

## 1. 目的と範囲

code-review loop が起票した Issue を、定期実行で triage(ラベルとコメント)し、autofix が直接拾って修正 PR を作る。引き継ぎは「Issue に残ったラベルとコメント」を次のループが定期実行で読む形にする(どのループも他を起動しない)。

| 段階 | 内容                                                                                         | この spec |
| ---- | -------------------------------------------------------------------------------------------- | --------- |
| A'   | 対象ごとのターゲット、prune、`write_state` の再試行、ブランチ名、artifact 名、run-log のキー | 含む      |
| F    | triage の定期実行(L1。人間への情報提供。autofix の入力にはしない)                            | 含む      |
| D    | autofix の定期実行(L1、観察)                                                                 | 含む      |
| E    | autofix の定期実行(L2、修正 PR)と、Webhook の経路の対象ごとのキー化                          | 含む      |

- 段階 A は、code-review の PR(#1210、#1213)で組み込みの範囲検出と `issue_create` が入っている。この spec はその残りを扱う。
- 範囲外: 既存の `detect_script` の caller の、到達できない `last_sha` での縮退。`loop-state-promote` の push の競合。

## 2. 現状の事実(2026-11-11 時点のコード。独立レビューで検証済み)

| 事実                                                                                                                                                                                           | 場所                                                                            |
| ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------- |
| detect は branch と PR ごとに候補を作る。detect の**前**に、そのキーで state を読み、breaker と pending で止まれば detect を走らせない                                                         | `loop-detect/lib/detect.sh` の `append_detect_candidate`                        |
| circuit breaker の閾値は連続失敗3回。finalize が書く `rejected` と `pr_closed` で +1、`error` / `watch` / `escalated` は維持、それ以外は 0。`loop-state-promote` の `pr_closed` は数えない     | `loop-detect/lib/guards.sh`、`write_state.sh`、`loop-state-promote/lib/run.sh`  |
| branch の名前は `^[a-zA-Z0-9/_.-]+$` に限る。`#` は入らない                                                                                                                                    | `detect.sh` の `checkout_context`                                               |
| `prune_targets.sh` は `pull_request:*` だけを消す。終端の outcome は `rejected` と `pr_closed` で、integration / watch の cooldown にも同じ定義を使う                                          | `loop-finalize/lib/prune_targets.sh`                                            |
| `write_state` の push は stderr を捨てていて、失敗すると競合かどうかを区別せず state PR のフォールバックへ進む                                                                                 | `loop-finalize/lib/write_state.sh`                                              |
| `issue_comment` と `pr_review` は branch の caller では拒否される(entity の caller 専用)                                                                                                       | `lib/loop/delivery.sh`                                                          |
| 作業ブランチ名は `<prefix>/<skill>/<秒単位の日時>`。finalize の push は suffix を `^[0-9]{8}-[0-9]{6}$` に限り、不一致は失敗にする。`loop-worktree-setup` は L2 の job だけが呼ぶ              | `loop-worktree-setup/action.yml`、`push_agent_branch.sh`、`ci-loop-agent.yaml`  |
| entity の detect の handoff artifact 名は `loop-handoff-${run_id}` で固定。download 側は detect の出力 `handoff_artifact_name` を使う                                                          | `loop-entity-detect/action.yml`、`ci-loop-caller-entity.yaml`                   |
| `loop-run-log` の入力に target のキーがない。run-log は JSONL。run-log の push は3回再試行する                                                                                                 | `loop-run-log/action.yml`、`append.sh`                                          |
| `detect_issue.sh` は `workflow_dispatch` のときだけ空の title / body / labels を API で補い、`ISSUE_EVENT_NAME` の既定は `workflow_dispatch`                                                   | `github-issue-triage/scripts/detect_issue.sh`                                   |
| triage の concurrency は workflow 全体で1つ(末尾が `github.run_id` へのフォールバック)。schedule では run ごとに一意になる                                                                     | `on-loop-github-issue-triage.yaml`                                              |
| triage の L1 は state を書かない。agent が失敗するとラベルもコメントも付かない                                                                                                                 | `ci-loop-agent.yaml`、`loop-github-issue-triage-workflow-design.md`             |
| `ci-loop-caller.yaml` の detect ジョブの permissions は `contents: read` と `pull-requests: read` など(`issues` なし)。`ci-loop-caller-entity.yaml` は `issues: read` を持つ                   | `ci-loop-caller.yaml`                                                           |
| autofix は branch の caller で、L2 の設定(`agent_edit_*`、`agent_unchanged_verdict`、`delivery: pr_create`)が静的。L1 はこれらが空で delivery が `none` / `issue_comment` であることを要求する | `on-loop-github-issue-autofix.yaml`、`lib/loop/validate_loop_write_contract.sh` |

## 3. 準拠する設計原則

| 原則                                          | この spec での決定                                                                                                                                                                                                                                                                |
| --------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Maker-Checker Separation**                  | 報告を超える行動(修正 PR)は L2 の autofix だけ。checker が APPROVE した結果だけで行う。triage は L1 でラベルとコメントだけ。**triage の出力は autofix の入力にしない**(第0節)                                                                                                     |
| **Graduated Autonomy**                        | autofix の定期実行は L1(段階 D)で2週間以上観察してから L2(段階 E)に上げる。Webhook の経路の既存 L2 の挙動変更(キー化)は、L1 の観察の後(段階 E)に入れる                                                                                                                            |
| **Design Stop Conditions First**              | 止まり方を先に決める(第9節)                                                                                                                                                                                                                                                       |
| **Phase Contract / 不変条件6**                | 変えない。引き継ぎは Issue のラベルとコメントを次のループが読むだけ。**一覧のジョブ(triage)と一覧のモード(autofix)は、対象の集合を作るだけで、実行するかの判定(skip)はしない。判定は各 cell の detect が行う**(caller が detect を二重に呼ぶのではなく、集合の列挙と判定を分ける) |
| **Intake Gating / 不変条件9**                 | Webhook の Bot 拒否は変えない。経路の分離は作成者ではなく**ラベル**で、Webhook 側の `if` と一覧と detect の `should_skip_issue` の3層に実装する(第5.3節、第6.3節)                                                                                                                 |
| **Multi-loop Coordination**                   | 定期実行(autofix、triage)は `loop-state-main` で直列にする(第5.2節、第6.1節)                                                                                                                                                                                                      |
| **Failure Mode(State Rot、Retry limit of 3)** | 対象ごとのキーも30日の prune の対象にする(第4.3節)。triage の再試行の上限は、run-log の失敗の記録で守る(第5.4節)                                                                                                                                                                  |
| **Component Design Principles**               | プラットフォームは汎用のまま。どの Issue を拾うかの条件は caller と、caller が指定するスクリプトに置く                                                                                                                                                                            |

## 4. プラットフォームの変更(段階 A')

### 4.1 対象ごとのターゲット(`result.items`)

detect スクリプトの結果に `result.items` を返せるようにする。**caller の入力 `detect_items`(boolean、既定 `false`)で、items モードを事前に宣言する。** `false` のときは今までの挙動と順序のまま。

```json
{ "status": "ok", "skip": false, "result": { "items": [{ "key": "issue:123", "entity": { "kind": "issue", "number": 123 }, "context": { "issue_number": 123 }, "verifier_context": "" }] } }
```

- **前提の検証:** `detect_items: true` のときは、`detect_branch_match` がちょうど1つのブランチで、`detect_pr_enabled` が `false` であることを検証する(ブランチごとに detect スクリプトが呼ばれて同じ要素が重複するのを防ぐ)。満たさなければ detect を失敗させる。
- **処理順:** checkout → detect スクリプトを実行 → 要素ごとに state を判定。branch のキー(`integration:<branch>`)の breaker と pending は**判定しない**(items モードでは使わないキー。古い `integration:main` の breaker が全件を止めるのを避ける)。
- **キー:** `integration:<branch>#<key>`。`key` は `^[A-Za-z0-9._-]+(:[A-Za-z0-9._-]+)*$`、長さ64以下、`..` を含まず、先頭と末尾が `.` でないこと。要素のキーの重複、不正なキーは detect を失敗させる。`items` が空配列なら `{"skip": true}` と同じ扱い。区切りの `#` は、branch の検証が `#` を許さないので曖昧にならない(最初の `#` で分ける)。
- **要素ごとの state の判定:** 要素のキーで circuit breaker、pending、却下内容の持ち越しを読む。止められた要素はターゲットにせず、`::warning` を出し、`CIRCUIT_BREAKER_BLOCKED` / `PENDING_PR_BLOCKED` を増やす(全件が落ちたときの `skip_reason` が `no_changes` ではなく `circuit_breaker` / `pending_pr` になり、観測できる)。要素ごとの run-log の skip の記録は出ない。
- **並びと上限:** 要素を、state の `last_run` が古い順(state がない要素が先)に並べ直してから `detect_max_targets` で切る。同順位は detect の返した順を保つ。並べ替えは、要素を候補にした後、`sort_candidates_by_priority` と `apply_target_cap` の前で行う。超えた分は次の実行で拾う。
- **候補の `result` の形:** skill の期待(`{status, skip, result:{...}}`、`result.issue_number` など)を保つため、その要素について `{"status":"ok","skip":false,"result":{<context>, "key":"<key>"}}` に組み直す。ほかの要素の内容は入れない(M5)。`verifier_context` は要素の `verifier_context`(文字列)があればそれを、なければ `context` から既存の `build_verifier_context_from_result` で作る。
- **`entity`:** `{"kind": "issue", "number": N}` だけを入れ、`handoff_key` は入れない(handoff の保存は `target_json.key` を使い、`entity.handoff_key` を優先する既存の読み手と食い違うのを避ける。`pr_create` は `entity` を読まない)。`target_json.mode` は `integration` のまま。`validate_delivery_target` は `pr_create` と `none` で種別を問わないので、規則は変えない。
- **`from.since` と `Last SHA`:** その要素のキーの state の `last_sha`、なければ `HEAD~10`(組み込みの範囲検出と同じ縮退)。
- **予算:** detect で1回判定する(既存)。並行数は `detect_max_targets` 以下。
- **既存の matrix:** `ci-loop-caller.yaml` の execute がそのまま並行で動き、finalize がそれぞれのキーで state を書く。`loop-state-promote` は `pending.pr` で探すので、キーの形式に依存せず動く。
- **permissions:** `ci-loop-caller.yaml` の detect ジョブに `issues: read` を足す(一覧のスクリプトが `gh` で Issue を読むため。`GITHUB_TOKEN` へのフォールバックでの 403 を避ける)。
- **実装の分け方(builder に任せる):** `append_detect_candidate` を「checkout と detect の実行」と「要素ごとの state の判定と候補の組み立て」に分ける。

### 4.2 並行するセルの作業ブランチ名と artifact 名

作業ブランチ名(M6):

- `loop-worktree-setup`(L2 の job だけが呼ぶ)に入力 `target_key`(既定 `""`)を足し、`ci-loop-agent.yaml` の L2 の呼び出しから渡す。ブランチ名は `<prefix>/<skill>/<日時>-<slug>`。`items` でないターゲットは今までの名前のまま。
- `slug` は、キーの `#` 以降を `[A-Za-z0-9._-]` に正規化(`:` は `-`)し、先頭と末尾の `.` を除き、`..` と `.lock` で終わる形を避けて32文字以下に切る。**常に、キー全体の短いハッシュ(8桁)を足す**(`issue:1-2` と `issue-1:2` のような正規化後の衝突を防ぐ)。`git check-ref-format` に通ることを bats で確かめる。
- **`push_agent_branch.sh` の suffix の検証を `^[0-9]{8}-[0-9]{6}(-[A-Za-z0-9._-]{1,48})?$` に広げる**(広げないと L2 の finalize の push で全件が失敗する)。エラーメッセージと、既存の bats(`push_agent_branch.bats`、`loop-worktree-setup/action.bats`)も更新する。
- ブランチ名から対象を引く処理がないことを、実装時に `rg` で確認する。

handoff artifact 名(triage の matrix で必要):

- `loop-entity-detect` と `ci-loop-caller-entity.yaml` に、任意の入力 `handoff_artifact_suffix`(既定 `""`)を足し、artifact 名を `loop-handoff-${run_id}${suffix}` にする(upload と、detect の出力 `handoff_artifact_name`)。suffix が空なら今までの名前。matrix の呼び出しは `-issue-<番号>` を渡す。`ci-loop-agent.yaml` は detect の出力を使うので、変更は要らない。
- `loop-agent-bundle-*` の名前はキーのハッシュを含むので衝突しない(確認済み)。

### 4.3 prune の拡張(M1)

- `prune_targets.sh` は、キーに `#` を含む integration のキーも消す。条件は **pending がなく、30日を過ぎている**(outcome は問わない。終端の集合を列挙すると、`pr_created` や `escalated` などで残るキーが永久に消えない)。
- `last_run` が欠けているか不正なキーは残す(既存の fail-safe)。
- **既存の `terminal` と、`pull_request:*` / `#` を含まない integration / `watch` の挙動は変えない。** `#` を含むキーの判定を、`startswith("pull_request:")` の分岐の前に置く。
- `#` を含まない `integration:<branch>` と `watch` のキーは、今までどおり消さない。
- `error` は breaker に数えない(既存の意味を変えない)。`#` のキーは30日で消えるので、state が増え続けない。

### 4.4 `write_state` の再試行

- 並行するターゲットが同じ state ファイルへ push して競合する。push の stderr を捕まえ、`! [rejected] ... (fetch first|non-fast-forward)` のときだけ(`[remote rejected]` の ruleset の拒否は除く)、**最大3回**やり直す。1回の手順: `git fetch origin <READ_BRANCH>` → 作業ブランチを `origin/<push_branch>` に戻す(`git reset --hard`。fetch の後に置く)→ state の読み直し(`load_state_tmp`)→ prune → `resolve_consecutive_failures` → `write_target_state` → commit → push。
- **`FINALIZE_COMMIT_PATHS` が空のときだけ再試行する。** 読み直しで台帳ファイルの変更が消えるため。それ以外と、再試行を使い切ったときは、今までどおり state PR のフォールバック。
- `load_state_tmp` は呼ぶたびに `trap ... EXIT` を設定し直す。再試行で `STATE_TMP` を作り直すので、前の一時ファイルを消してから作る。
- 競合は、並行する対象に加えて run-log の push と他ループの push でも起きうる。再試行を使い切ったときの state PR のフォールバックは、起きうるものとして扱う(第11節)。
- 実機の push のエラー文言は bats ではモックでしか確かめられない。PR 1 の dogfood で確認する。

### 4.5 run-log に target のキーを足す(M8)

- `loop-run-log` の入力に `target_key`(既定 `""`)を足し、JSONL の1行にフィールド `target_key` を**末尾に**足す。`loop_run_log_build_entry` の位置引数の末尾に足し、既存の読み手(`budget_exceeded` など)が壊れないことを bats で確かめる。
- `ci-loop-agent.yaml` の run-log の呼び出し(L1 と L2 の2か所)から渡す。値は、items の対象ではキー全体、entity の対象(triage)では handoff のキー(`entity:issue:<N>`)。

## 5. triage の定期実行(段階 F、L1)

triage は人間への情報提供(ラベルとコメント)で、autofix の入力にはしない(第0節)。

### 5.1 方式の決定

overview の第5.1節は、triage を branch の caller の対象ごとのターゲットで動かす案だった。これは `validate_delivery_detect_config` の規則を変える必要があり(H3)、triage は L1 で state を書かないので、対象ごとの state の利点もない。

**決定: 一覧のジョブ + entity の caller の matrix(方式 X)。** 検証の規則を変えない。必要な変更は、handoff artifact 名(第4.2節)、run-log の `target_key`(第4.5節)、`detect_issue.sh` の hydrate と `schedule` の扱い(第5.5節)、一覧のスクリプト(第5.2節)。

### 5.2 構成

- `on-loop-github-issue-triage.yaml` に `schedule`(1日1回)を足し、ジョブを分ける。
  1. `list`(`schedule` のときだけ。checkout と `issues: read` が要る): 一覧のスクリプトが対象の Issue 番号の配列(最大3件)を出力する。
  2. `loop`(既存を matrix 化): `needs: list`。**`if` は `!cancelled()` を付け、`needs.list.result` が `success` または `skipped` で、かつ(`schedule` なら件数が1以上、それ以外なら既存のゲート)のときだけ通す**(状態関数がないと、`list` が skipped のとき `loop` も skipped になり、Webhook の triage が全部止まる。`ci-loop-caller.yaml` の `execute` の `if` と同じ書き方に揃える)。matrix の式は、`schedule` のときは `list` の出力、そうでなければ Webhook の1件(`github.event.issue.number` または `inputs.issue_number`)。`strategy: { fail-fast: false, max-parallel: 3 }` を指定する。`detect_env_json` に `{"ISSUE_NUMBER": <番号>}` を、`handoff_artifact_suffix` に `-issue-<番号>` を渡す。
  - matrix の式と `if` は actionlint で確かめ、**PR 2 の dogfood で Webhook の run が動くことを確認する**(短絡評価と、`list` が skipped のときの `fromJSON` の挙動は、実際の run で確認する)。
- **`concurrency`:** `schedule` のときの group は `loop-state-main`(`queue: max`、Multi-loop Coordination の第1原則。`loop-run-log` が main に push するため)。Webhook と `workflow_dispatch` のときは今までどおり Issue の番号ごとの group。
- **一覧のスクリプト**(リポジトリ専用。`scripts/self/loop/` に snake_case で置く。出所ラベルと marker はこのリポジトリのドメインなので配布物の skill には入れない)。
- **配信**は既存の `issue_comment`(L1)。

### 5.3 経路の分離(M4)

- **Webhook の経路:** `issues` の `opened` / `reopened` / `labeled` で、ラベル `loop:code-review` の Issue を**拒否**する条件を `if` に足す。Bot の送信者の拒否は今までどおり。
- **`issue_comment` の経路は変えない。** `triage:needs-info` が付いた Issue への人間のコメントは、`loop:code-review` の Issue でも再 triage する(拒否すると、人間の返信が二度と再 triage されなくなる)。
- **定期実行の経路:** 第5.4節の条件の Issue だけを拾う。`triage:*` のラベルがある Issue は拾わない(`triage:needs-info` 後の再 triage は Webhook の `issue_comment` が担当)。
- **3層の対応の検査:** 「一覧のスクリプトが選ぶ集合 ⊆ detect(`should_skip_issue`)が skip しない集合」であること、かつ「一覧が選ぶ Issue を Webhook の `if` が拒否すること」を bats で確かめる(不変条件9の検査に足す)。

### 5.4 拾う条件、対応済みの除外、再試行の上限(M2)

**拾う対象:** open、PR でない、ラベル `loop:code-review` あり、`triage:needs-info` / `triage:ready` / `triage:failed` のいずれもない(`gh` の `-label:` は wildcard が使えないので3つを列挙する)。さらに、**作成者が Bot(App)で、本文に code-review の marker(`<!-- code-review:fp:`)がある**こと(ラベルだけを人間が付けた Issue を、この経路の入力にしない)。Issue の一覧と作成者の型(`user.type`)、`pull_request` の有無、ラベル、本文は、REST(`gh api repos/{repo}/issues`)で1回に取る(`gh issue list --json author` は GraphQL で、Bot の login の見分けが曖昧)。App ではなく PAT で起票する構成では作成者が `User` になり、対象が0件になる(このリポジトリは App 構成。0件のときは `::notice` を出す)。

**対応済みの除外:** triage が付けたコメントの marker(`<!-- github-issue-triage:v1 -->`。`deliver_message.sh` が `<!-- ${LOOP_NAME}:v1 -->` を付ける。実際の文字列は実装時に確認する)がある Issue は、**最新の marker のコメントの `created_at` より新しい人間のコメントがあるまで**拾わない。

- コメントは REST(`gh api repos/{repo}/issues/{N}/comments --paginate`)で取り、`user.type != "Bot"` で人間を判定する(GraphQL の `gh issue view --json comments` は `author.login` しか返さず、Bot の見分けが曖昧になる)。基準は `created_at`(`updated_at` は使わない。triage は新規コメントを作り、PATCH しない)。

**再試行の上限(Failure Mode の「再試行は3回」):** L1 は state を書かないので、run-log を使う。`loop-run-log` に記録される `target_key`(`entity:issue:<N>`、第4.5節)で、**直近7日に triage の実行が失敗した記録が3回以上ある Issue を、一覧から外す**(7日の窓だと、毎日実行では古い記録が窓から出て、4日おきに再び拾われる)。さらに、**run-log の最終試行が古い Issue(記録のない Issue が先)から並べる**。失敗が続く Issue が先頭3件を占めて、ほかの Issue が拾われなくなる飢餓を防ぐ。

- **「失敗」の定義:** その `target_key`(`entity:issue:<N>`)の run-log の行で `outcome` が `error`、`rejected`、または `unchanged`(triage では message.md が空、または message_labels.json が不正で何も届けられなかった場合)。`skipped`(予算の skip など)は数えない。Webhook 経由の再 triage の失敗も同じキーで数える(意図どおり)。detect ジョブ自体の失敗は run-log に残らないので数えられない。
- **fail-open:** run-log が読めないとき、外さずに進む。run-log の push は3回失敗すると記録を捨てるため、並行する実行が重なると失敗が過小に数えられうる(残るリスク)。読み方は `budget_exceeded` と同じ(JSONL を1行ずつ `jq` で読む)。

**切り詰めの順序:** スクリプトは、古い順に `gh` で最大200件まで読み(ページ送りを含む)、上のすべての除外をかけた後で、先頭3件を返す(除外の前に3件で切ると、除外される Issue が窓を埋める)。200件を読んでも3件に満たなければ、満たした分だけ返す。件数とコメント API の呼び出し回数(Issue ごとに最大1回)の上限を、スクリプトの header に書く。

**残るリスク:** run-log の窓の外(7日より前)に失敗した Issue は、再び拾われる。歯止めは、1回の件数(3)、1日の予算、1日1回の間隔。

### 5.5 `detect_issue.sh` の hydrate と `schedule`(M-4)

- `ISSUE_NUMBER` があり、title / body / labels が空のときは、イベントの種別を問わず API で補う(今は `workflow_dispatch` のときだけ)。
- `schedule` のとき、`ISSUE_EVENT_NAME` は `schedule` にする(既定の `workflow_dispatch` のままにすると、`should_skip_issue` の `workflow_dispatch` の分岐に入り、`triage:ready` を見ずに実行する)。`should_skip_issue` の `schedule` の扱い: `triage:*` のラベルが1つでもあれば skip する(一覧と detect の対応)。
- 編集は `.apm/packages/github/.apm/skills/github-issue-triage/scripts/detect_issue.sh` で行い、`apm install` で同期する。bats も足す。

## 6. autofix の定期実行(段階 D・E)

### 6.1 構成

- **ジョブを2つに分ける。** `on-loop-github-issue-autofix.yaml` は現在、L2 の静的な設定を持つ1つの `loop` ジョブで、同じジョブの入力の `level` だけを式にしても L1 の検証(`agent_edit_*` が空、delivery が `none` / `issue_comment`)で detect が失敗する。そこで:
  - `loop`(既存、Webhook / `repository_dispatch` / `workflow_dispatch`。L2。段階 E まで変えない)。
  - `loop-scheduled`(新規、`schedule`。段階 D は L1 / `delivery: none` / `agent_edit_*` なし。段階 E で L2 / `delivery: pr_create` に上げる)。それぞれの `if` で `github.event_name` を見る。
- `loop-scheduled` は `ci-loop-caller` で、`detect_items: true`、`detect_branch_match: main`、`detect_script`(`detect_autofix.sh`)を**一覧のモード**(`AUTOFIX_SCAN=true`)で呼び、`result.items` を返す(第4.1節)。
- **`concurrency`:** workflow 全体の group を `schedule` のときだけ `loop-state-main`(`queue: max`)にする式にする(既存の `on-loop-*.yaml` と同じ workflow 全体の指定。`uses:` のジョブ単位の `queue: max` は使わない)。Webhook と `workflow_dispatch` の group は今までどおり Issue の番号ごと。
- 拾う件数は `detect_max_targets`(段階 D は3)。

### 6.2 拾う条件(autofix の detect スクリプトに置く。ドメインの判断)

- **拾う対象:** open、PR でない、`loop:code-review` あり、`autofix` ラベルなし、**作成者が Bot(App)で本文に code-review の marker がある** Issue(`loop:code-review` ラベルだけを人間が付けた Issue を L2 の入力にしない。第0節の決定1を実装で担保する)。
- **除外:**
  - `Fixes #N` の PR が開いている Issue(既存の `open_pr_fixes_issue`)。
  - **対応済みの Issue(M3):** その Issue を `Fixes #N` で参照する、閉じた autofix の PR(マージ済みも含む。`loop-automation` ラベルで絞る)があり、その `closedAt` が、人間(`user.type != "Bot"`)の最新のコメントの時刻より新しい Issue は、人間の新しいコメントがあるまで拾わない。PR を人間が閉じても、`consecutive_failures` には数えない。
  - 要素のキーの state で pending か circuit breaker(連続失敗3回)に当たるもの(platform が判定する。第4.1節)。
- **取得の方法:** 閉じた PR は `gh pr list --state closed --label loop-automation --limit 200 --json number,body,closedAt,headRefName` で1回だけ取り、`Fixes #N` との照合は `\b` つきの正規表現でクライアント側(jq)で行う(既存の `open_pr_fixes_issue` と同じ方式。Issue ごとの検索は API が増える)。コメントは Issue ごとに REST で取る。直近200件より古い閉じた PR は参照できず、その Issue が再び拾われうる(残るリスク)。
- **切り詰めない:** スクリプトは、除外をかけた対象を**最大50件まで、上限で切らずに**返す。切るのは platform の `detect_max_targets` と `last_run` の並べ替えの仕事(スクリプトが先に3件に絞ると、platform が breaker で落とした後に何も残らず、4件目以降が拾われない)。

### 6.3 経路の分離と二重起動

- `autofix` ラベルの付いた Issue は Webhook の経路だけが扱い、一覧から除く(M4。ラベルで除く)。
- 人間が `autofix` を付けた時点で、定期実行がすでにその Issue を拾っている窓は、agent の実行時間(長いと数十分)の間ずっと開く。同じ per-Issue のキーに揃うのは段階 E 以降で、それまでは PR を作る前の競合が起きうる。**残るリスク**。
- **circuit breaker に当たったキーは、Webhook の経路でも止まる**(段階 E 以降。キーが揃うため)。コメントや `autofix` の付け直しでは再開しない。再開は、state(`.loop/state-github-issue-autofix.json`)からそのキーを消す PR を出す(30日で自動に消える)。

### 6.4 同時に開く PR の上限(Low)

- 暗黙の「同時に1つの PR」が段階 E で外れるので、autofix の detect スクリプトが、開いている autofix の PR(`gh pr list --label loop-automation --json headRefName` で取り、jq で head が `loop/github-issue-autofix/` で始まるものを数える)が `AUTOFIX_MAX_OPEN_PRS`(caller の `detect_env_json`、dogfood は 3)以上なら `{"skip": true}` を返す。
- **定期実行にだけ効かせる。** 人間が `autofix` ラベルを付けた Webhook の経路は、人間の意図なので上限で止めない。
- 上限は run の**前**に判定する。1回の run で作る PR は `detect_max_targets` 以下なので、上限を超える分は `detect_max_targets - 1` 以下(soft)。定期実行どうしは `loop-state-main` で直列。定期実行と Webhook の間は厳密ではない。

### 6.5 段階 D(L1)と段階 E(L2)

- **D:** `loop-scheduled` は L1、`delivery: none`。エージェントは修正方針を出すだけで PR を作らない(ログに出る)。拾う対象の選び方と方針の妥当性を2週間以上観察する。L1 は state を書かないので `last_run` による並べ替えが働かず、毎回、古い順の同じ3件を見る(標本が増えにくいことを受け入れる)。**Webhook の経路は変えない。**
- **E(L2):** `loop-scheduled` を L2、`delivery: pr_create`(既存の Webhook と同じ設定)に上げる。checker が APPROVE した修正 PR だけを作る。人間のマージ承認は変えない。**この段階で Webhook の経路も `detect_items: true`、`result.items` に1件だけを返す形にする**(定期実行と同じ per-Issue のキーで pending と breaker を共有するため。既存の L2 のキーが変わる挙動変更を、L1 の観察の後に入れる)。
- 「triage を経由する構成」は取らない(第0節)。`github-issue-triage` の skill の文書の変更は不要。

## 7. 論点の扱い(overview の H1〜Low)

| 論点 | 扱い                                                                                                                               |
| ---- | ---------------------------------------------------------------------------------------------------------------------------------- |
| H1   | 第0節。autofix は triage の出力を入力にしない(直接拾う)。triage は L1 のまま                                                       |
| H2   | 定期実行の autofix と triage は `loop-state-main` で直列(第5.2節、第6.1節)                                                         |
| H3   | 方式 X により、`validate_delivery_detect_config` と `validate_delivery_target` は変えない。autofix の `pr_create` は種別を問わない |
| M1   | 第4.3節(`#` を含むキーは、pending なしで30日を過ぎたら消す)                                                                        |
| M2   | 第5.4節(marker と人間のコメントで除外。run-log の失敗の記録で再試行を3回に上限)                                                    |
| M3   | 第6.2節(閉じた PR の後は、人間の新しいコメントまで拾わない。`consecutive_failures` には数えない)                                   |
| M4   | 第5.3節、第6.3節。ラベルで両方の層に実装し、3層の包含を bats で確かめる                                                            |
| M5   | 第4.1節(`result` と `verifier_context` を要素に絞る。形は skill の期待を保つ)                                                      |
| M6   | 第4.2節(ブランチ名、`push_agent_branch.sh` の検証、artifact 名)                                                                    |
| M8   | 第4.5節                                                                                                                            |
| Low  | 第6.4節(同時に開く PR の上限)。`#` の区切りは branch の検証が `#` を許さないので曖昧にならない(第4.1節)                            |

## 8. 昇格と減速の条件

overview の第2.2節を踏襲する。この spec で足す指標(計測は `gh` の PR 検索で行う。state は30日で prune されるので使わない):

- **autofix の Slow Down:** 作った修正 PR のうち、マージされずに閉じられた率が50%を超えたら、`detect_max_targets` を 1 に下げるか L1 に戻す。
- **triage の Slow Down:** 8日以上 `loop:code-review` のまま triage されない Issue(7日の失敗の窓で除外中の Issue は、窓が明ける日数を超えたものだけ)が出たら、人間が原因を見る(第5.4節の残るリスク)。
- **Kill(autofix):** 2週続けて、修正 PR のマージ数がゼロで予算を使い切った。

## 9. 止まり方(Design Stop Conditions First)

| 止める仕組み                                                                         | 対象                                   |
| ------------------------------------------------------------------------------------ | -------------------------------------- |
| checker の REJECT と circuit breaker(対象ごと、連続3回)                              | autofix                                |
| 1回の件数の上限(triage は一覧の上限 3、autofix は `detect_max_targets`)              | 並行数も上限                           |
| 開いている autofix の PR の上限(`AUTOFIX_MAX_OPEN_PRS`、定期実行のみ。soft)          | autofix                                |
| 予算(detect で1回判定)                                                               | 全ループ                               |
| 経路の分離(ラベルで Webhook と定期実行の対象が重ならない)                            | 二重起動                               |
| 対応済みの Issue は、人間の新しいコメントがあるまで拾わない                          | 同じ Issue の拾い直し(autofix、triage) |
| run-log の失敗の記録で、直近7日に3回失敗した Issue を一覧から外す                    | triage の失敗による飢餓と、予算の浪費  |
| `last_run` の古い順の並びと、スクリプトは切り詰めず platform が上限を適用            | autofix の失敗する要素による飢餓       |
| 引き継ぎは一方向。どのループも他を起動しない。triage の出力は autofix の入力にしない | 循環、L1 の出力による L2 の起動        |
| 人間のマージ(autofix は L2)                                                          | 修正の反映                             |

## 10. このリポジトリでの検査(bats)

実装した各 `*.sh` に、対の bats を同じ commit で足す(BAT-01)。bats はテストを足したディレクトリだけを走らせる。

- 対象ごとのターゲット: キーの検証(許可、`..`、先頭と末尾の `.`、長さ、重複、空の `items`)、`detect_items` の前提(1ブランチ、PR 監視なし)、items モードで branch のキーの breaker を見ないこと、要素ごとの breaker / pending / 持ち越しと `skip_reason`、`last_run` の古い順の並びと `detect_max_targets` の上限、`result` の形、`Last SHA` の縮退、`detect_items: false` の既存の挙動が変わらないこと。
- ブランチ名と artifact 名: 並行する2つの対象で名前が違うこと、正規化後に衝突するキー(`issue:1-2` と `issue-1:2`)で名前が違うこと、長いキーの切り詰め、`git check-ref-format`、`push_agent_branch.sh` が新しい suffix を受けること(古い形も受けること)、`handoff_artifact_suffix` が空のとき名前が変わらないこと。
- prune: `#` を含むキーが「pending なし、30日超」で消え(outcome は問わない)、pending ありと30日以内は残ること。`#` を含まないキーと既存の `terminal` の挙動が変わらないこと。
- `write_state` の再試行: non-fast-forward で再試行して成功、3回で諦めて state PR、`[remote rejected]` と `FINALIZE_COMMIT_PATHS` ありでは再試行しないこと、再試行で一時ファイルが残らないこと。
- run-log: `target_key` が末尾に出ること、既存の書式の読み手(予算の集計)が壊れないこと。
- triage の一覧のスクリプト: 第5.4節の各条件(Bot の作成者と marker、`triage:*` なし、PR でない、古い順、除外の後に3件で切ること、marker と人間のコメントの前後、Bot のコメントを人間と数えないこと、run-log の失敗3回で外れること、run-log が読めないとき外さないこと)。Webhook の `if` が `issues` の `loop:code-review` を拒否し、`issue_comment` は拒否しないこと。3層の包含。
- `detect_issue.sh`: `schedule` で空の title / body / labels を API で補うこと、`ISSUE_EVENT_NAME=schedule` で `triage:*` ありを skip すること。
- autofix の detect の一覧のモード: 第6.2節の各条件(Bot の作成者と marker、閉じた PR と人間のコメントの前後)、切り詰めないこと(最大50件)、`AUTOFIX_MAX_OPEN_PRS`(定期実行だけ)、`autofix` ラベルの除外。
- 新しい入力に合わせて `loop-caller-parity.bats`、`loop_input_topology.py` 等を更新する。

## 11. 残るリスク

- **反映の遅れ:** 定期実行の間隔ぶん遅れる。
- **triage の再試行の窓:** run-log の7日の窓の外の失敗は、再び拾われる(第5.4節)。
- **`autofix` ラベルと定期実行の競合:** 第6.3節。窓は agent の実行時間。
- **人間の選別なしの入力:** エージェントが書いた Issue が autofix の入力になる(ユーザーの意図どおり)。code-review 側で marker とメンションの無害化と根拠の再検証をしている。
- **人間のコメントで再び拾われる:** コメントの内容は見ないので、修正と無関係なコメントでも再び拾われる(ユーザーの方針。止めたければ Issue を閉じる)。
- **直近200件の閉じた PR の窓:** それより古い閉じた autofix の PR は参照できず、その Issue が再び拾われうる(第6.2節)。
- **`write_state` の再試行を使い切った場合:** state PR のフォールバックになり、並行する別の対象の state と食い違いうる。
- **`AUTOFIX_MAX_OPEN_PRS`:** 定期実行と Webhook の間は soft。上限を超える分は `detect_max_targets - 1` 以下。
- **`workflow_dispatch` と定期実行の重複:** 定期実行のセルが triage 中の Issue に `workflow_dispatch` すると、concurrency group が異なるため、triage のコメントが重複しうる(窓は小さく、許容する)。
- **`unchanged` を失敗に数える:** triage の lister は `unchanged` を失敗に数えるので、正当に空の triage 結果の Issue は7日に3回で除外され、窓が明けると自然に戻る。
- **GitHub Actions の仕様(未確認):** matrix の式の短絡評価、`list` が skipped のときの `fromJSON`、`loop-state-main` の `queue: max` の上限は、PR 2 の dogfood で確認する。

## 12. ドキュメントの更新

- `loop-engineering-design.md`: Intake Gating(定期実行の経路と Webhook の経路の分離、`if` の表、一覧のスクリプトという第3の層、不変条件6の言い換え「一覧は集合を作るだけで、判定は detect」)。STATE Files(対象ごとのキー、prune の拡張)。Multi-loop Coordination。Failure Mode Countermeasures(triage の再試行の上限)。
- `loop-caller-inputs-reference.md`、`docs/reference/specification.md`: `detect_items`、`result.items`、`handoff_artifact_suffix`、`loop-worktree-setup` の `target_key`、run-log の `target_key`。
- `common-loop-triage-format.md`、`loop-capable-skills.md`(detect JSON の `result.items`)。
- triage と autofix の workflow 設計書(`loop-github-issue-triage-workflow-design.md`、`loop-github-issue-autofix-workflow-design.md`): 定期実行の経路、経路の分離、対象ごとのキー。**各 workflow の設計書に「User actions」の節を置き、第15節のユースケースを転記する**(ユーザーが実際に起こす操作と、loop の応答、ユーザーに見える結果、次の操作を、全て書く)。autofix の非目標「`autofix` ラベルなしの自動 autofix」を改める。
- 新規 `docs/explanation/loop-engineering/loop-issue-handoff.md`: Issue の状態遷移(第15.4節)。各 workflow の User actions から遷移 ID で参照する。
- `2026-08-11-issue-triage-entity-loops-design.md`: 定期実行の経路を足したことを追記する。
- overview: 第5.2節の「人間が作った Issue も triage で拾われる」を取り下げたことを注記する(第0節)。

## 13. builder に任せること

- `append_detect_candidate` の分割の仕方。
- `write_state` の再試行の関数の分け方。
- 一覧のスクリプトの名前と引数。定期実行の時刻(triage と autofix)。
- matrix の式の書き方(actionlint で確かめる)。
- triage の marker の実際の文字列、run-log の失敗の判定のフィールド(`deliver_message.sh` と `loop-run-log` の書式で確認する)。
- **SHA pin は2段で更新する**(action のリリース → `ci-loop-agent.yaml` の pin → caller の pin)。リリースとタグの push は人間の承認を取る。

## 14. 段階ごとの PR

1. **PR 1(A'):** 第4節(`result.items` と `detect_items`、ブランチ名と `push_agent_branch.sh`、artifact 名、prune、`write_state` の再試行、run-log のキー、`issues: read`)。autofix と triage の挙動は変えない。
2. **PR 2(F):** 第5節(triage の定期実行、Webhook の `if`、`detect_issue.sh`)。dogfood で Webhook の run が動くことを確認する。
3. **PR 3(D):** 第6節の L1(`loop-scheduled`、autofix の一覧のモード、`AUTOFIX_MAX_OPEN_PRS`)。Webhook の経路は変えない。2週間観察する。
4. **PR 4(E):** `loop-scheduled` を L2 に上げ、Webhook の経路を対象ごとのキーにする。第2.2節の条件を確かめてから。

## 15. ユーザー操作のユースケース(各 workflow の設計書の「User actions」に転記する)

**docs の形式(ユースケースと状態遷移の整理):** 3つの見方を、1つの情報を1か所にだけ置く形で分ける。

| 見方               | 内容                                            | 置き場所(1つだけ)                                                                                                             |
| ------------------ | ----------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------- |
| イベントの起動判定 | イベント(送信者)→ どの caller が動くか          | `loop-engineering-design.md` の Intake Gating(横断。workflow ごとには書かない)                                                |
| **User actions**   | 人間の操作 → loop の応答 → 見える結果と次の操作 | 各 workflow の設計書(既存の `Supported use cases` を置き換える。**ユーザーが実際に起こす操作を全て書く**)                     |
| 状態遷移           | 1つの Issue の状態の流れ(workflow をまたぐ)     | 横断の1か所(新規 `docs/explanation/loop-engineering/loop-issue-handoff.md`)。User actions の各行は遷移 ID(第15.4節)で参照する |

- 状態遷移を各 workflow に書かない理由: code-review → triage → autofix をまたぐので、重複して食い違うため。
- **規則の本文は1か所だけ**に書く。User actions と状態遷移の表は、条件を繰り返さず、本文の節か遷移 ID を参照する。イベントの起動判定の表(Bot の送信者の拒否など)は User actions に書かない。
- User actions は、**状態を持つ workflow だけ**に遷移 ID の列を付ける。状態を持たない workflow(changelog など)は ID の列を省く。
- 段階 D〜F が入った後の挙動を書く(autofix の「(L1)」は段階 D、「(L2)」は段階 E 以降)。
- 各行は「操作 → loop の応答 → ユーザーに見える結果と次の操作」。

### 15.1 code-review(`on-loop-code-review.yaml`)

| ユーザーの操作                                             | loop の応答                                                                                    | 結果と次の操作                                                                        |
| ---------------------------------------------------------- | ---------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------- |
| 何もしない(週1回の定期実行)                                | 前回からの変更をレビューし、checker が承認した指摘を Issue にする(最大 `finalize_issue_limit`) | `loop:code-review` ラベルの Issue が増える(A0)。指摘0件なら何も起票せず cursor が進む |
| `workflow_dispatch` で手動実行                             | 定期実行と同じ                                                                                 | 同じ                                                                                  |
| 起票された Issue を閉じる(completed / not planned)         | 閉じた Issue も重複の判定に含めるので、同じ指紋は再起票しない                                  | 指摘を却下したい場合は、閉じるだけでよい(A6)                                          |
| Issue から `loop:code-review` ラベルを外す                 | 重複の判定は出所ラベルの Issue を探すので、**その指摘は将来また起票されうる**                  | 外す前に、Issue を閉じる方を勧める。triage と autofix の対象からも外れる              |
| Issue の本文の marker(`<!-- code-review:fp:... -->`)を消す | 重複を判定できなくなる。triage の定期実行と autofix の入力の条件(marker)も満たさなくなる       | marker は消さない                                                                     |
| 起票の上限を超えた指摘                                     | 捨てて、題名と指紋を step summary と run-log に残す                                            | 次回のレビューで同じ指摘が出れば、改めて起票される                                    |

### 15.2 triage(`on-loop-github-issue-triage.yaml`)

| ユーザーの操作                                              | loop の応答                                                                    | 結果と次の操作                                                                                   |
| ----------------------------------------------------------- | ------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------ |
| Issue を作る(人間。MEMBER / OWNER / COLLABORATOR)           | Webhook で triage し、ラベルとコメントを付ける(L1)                             | `triage:ready` / `triage:needs-info` などが付く。`bug` を自動修正させたいなら `autofix` を付ける |
| `needs-triage` または `triage:needs-info` ラベルを付ける    | Webhook で再 triage する                                                       | ラベルとコメントが更新される                                                                     |
| `triage:needs-info` の Issue に質問へ答えてコメントする(T2) | Webhook(`issue_comment`)で再 triage する。`loop:code-review` の Issue でも同じ | ラベルが更新される                                                                               |
| 何もしない(code-review が起票した Issue。T0)                | 定期実行(1日1回)が、第5.4節の条件の Issue を最大3件 triage する                | ラベルとコメントが付く(T1〜T4)。autofix の入力には**ならない**                                   |
| 低確信の code-review の Issue に、人間がコメントする(T4)    | 次の定期実行が、marker より新しい人間のコメントがあるので再 triage する(T0)    | コメントが更新される。コメントしない間は、再び triage されない                                   |
| `loop:code-review` の Issue に `needs-triage` を手で付ける  | 即時には動かない(経路の規則は Intake Gating を参照)                            | すぐ動かしたいなら `workflow_dispatch` で Issue 番号を指定する                                   |
| `workflow_dispatch` で Issue 番号を指定                     | その Issue を triage する                                                      | 同上                                                                                             |
| `triage:failed` の Issue(T3)                                | 拾わない(Webhook も定期実行も)                                                 | 原因を直したら、ラベルを外し、`workflow_dispatch` で再実行する                                   |
| 人間が `triage:ready` のラベルを外す(T1)                    | 拾わない(marker より新しい人間のコメントがないため)                            | 再 triage させたいなら、Issue にコメントする(T0)                                                 |
| `loop:code-review` ラベルだけを手で付けた Issue             | 拾わない(作成者が Bot で marker がある Issue だけが対象)                       | 手で triage したいなら `workflow_dispatch` で Issue 番号を指定する                               |

### 15.3 autofix(`on-loop-github-issue-autofix.yaml`)

| ユーザーの操作                                                  | loop の応答                                                                                                     | 結果と次の操作                                                        |
| --------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------- |
| Issue に `autofix` ラベルを付ける(人間)                         | Webhook で修正を実装し、`Fixes #N` の PR を作る(L2)                                                             | PR を確認してマージする(A3)                                           |
| `workflow_dispatch` / `repository_dispatch` で Issue 番号を指定 | 同じ                                                                                                            | 同じ                                                                  |
| 何もしない(code-review が起票した Issue。A1)                    | 定期実行(1日1回)が、第6.2節の条件の Issue を最大3件拾う。(L1)修正方針をログに出すだけ(A1)。(L2)PR を作る(A2→A3) | (L2)PR を確認してマージする                                           |
| autofix の PR をマージする(A3)                                  | `Fixes #N` で Issue が閉じ、pending が解ける(A6)                                                                | —                                                                     |
| autofix の PR をマージせずに閉じる(Issue は開いたまま。A3→A4)   | 人間の新しいコメントがあるまで、その Issue を拾わない。`consecutive_failures` は増えない                        | もう一度試させたいなら、Issue にコメントする。不要なら Issue を閉じる |
| PR を閉じた後、Issue にコメントする(A4→A1)                      | 次の定期実行が、その Issue をまた拾う                                                                           | コメントに修正の方向を書いておくと、エージェントが読める              |
| Issue を閉じる(A6)、閉じた Issue を reopen する                 | 閉じている間は拾わない。reopen すると、第6.2節の条件を満たせばまた拾う(A1)                                      | —                                                                     |
| `loop:code-review` ラベルを外す                                 | 定期実行の対象から外れる(ただし第15.1節のとおり、指摘は再起票されうる)                                          | 止めたいときは、ラベルを外すより Issue を閉じる                       |
| 定期実行が拾った Issue に、あとから `autofix` ラベルを付ける    | 定期実行の一覧から外れ、Webhook の経路が扱う。定期実行がすでに動いている間は両方が動きうる(第6.3節)             | 競合したら、先に作られた PR を残して、もう一方を閉じる                |
| 開いている autofix の PR が `AUTOFIX_MAX_OPEN_PRS` に達している | 定期実行は skip する。`autofix` ラベルの Webhook は上限で止めない                                               | PR をマージするか閉じると、次の定期実行から再開する                   |
| 同じ Issue で checker が3回続けて REJECT した(A5)               | その Issue のキーを拾わない(`::warning`)。Webhook の経路も止まる(段階 E 以降)                                   | 再開は第6.3節(state のキーを消す PR。30日で自動に消える)              |
| 予算を使い切った                                                | その日は実行しない(`skip_reason=budget`)                                                                        | 翌日に再開する。予算の上限は caller の `budget_*` で変える            |

### 15.4 Issue の状態遷移(`loop-issue-handoff.md` に置く。User actions の各行が ID で参照する)

code-review が起票した Issue 1件の流れ。triage は情報提供で、autofix の入力にならない(第0節)ので、**triage の状態と autofix の状態は別々に動く**。条件の本文は第5.4節と第6.2節に1か所だけ置き、この表は参照する。

**autofix 側**

| ID  | 状態                                   | きっかけ                                                | 次の状態                                 |
| --- | -------------------------------------- | ------------------------------------------------------- | ---------------------------------------- |
| A0  | 起票                                   | code-review(L2)の checker が APPROVE し、再検証を通った | A1                                       |
| A1  | 拾う対象(第6.2節)                      | 定期実行が拾う(上限を超えたら次の実行)                  | A2                                       |
| A2  | 実行中                                 | (L1)方針をログに出す                                    | A1                                       |
|     |                                        | (L2)checker が APPROVE し、PR を作る                    | A3                                       |
|     |                                        | (L2)REJECT                                              | A1(その Issue の失敗回数が +1。3回で A5) |
| A3  | PR が開いている(pending)               | 人間がマージ                                            | A6                                       |
|     |                                        | 人間が閉じる                                            | A4                                       |
| A4  | 静止(PR は閉じたが Issue は開いたまま) | 人間が Issue にコメントする                             | A1                                       |
|     |                                        | 人間が Issue を閉じる                                   | A6                                       |
| A5  | 停止(circuit breaker)                  | 30日で state が消える、または state のキーを消す PR     | A1                                       |
| A6  | 完了(Issue がクローズ)                 | 人間が reopen する                                      | A1(第6.2節の条件を満たすとき)            |

- A1 のとき `autofix` ラベルが付いていれば、Webhook の経路が扱う(定期実行の対象から外れる)。

**triage 側**

| ID  | 状態                                           | きっかけ                                                           | 次の状態                 |
| --- | ---------------------------------------------- | ------------------------------------------------------------------ | ------------------------ |
| T0  | 未 triage(第5.4節の条件)                       | 定期実行が拾う(最大3件)                                            | T1 / T2 / T3 / T4        |
| T1  | `triage:ready`                                 | 人間が `triage:ready` を外し、かつ marker より新しいコメントをする | T0                       |
| T2  | `triage:needs-info`                            | 人間がコメント(Webhook)                                            | 再 triage → T1 / T2 / T3 |
| T3  | `triage:failed`                                | 人間がラベルを外して `workflow_dispatch`                           | 再 triage                |
| T4  | 低確信(`needs-triage` のまま、marker あり)     | 人間が marker より新しいコメントをする                             | T0                       |
|     | エージェントが失敗(ラベルもコメントも付かない) | 次の実行(直近7日に3回失敗すると一覧から外れる)                     | T0(第5.4節)              |

User actions の表(第15.1〜15.3節)の各行の遷移 ID は、`loop-issue-handoff.md` と相互に参照する。
