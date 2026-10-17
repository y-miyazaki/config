# Loop 配信設計: 1つの判断を1つの値で宣言し、名前を1つの規則にそろえる

**Status:** Draft(ユーザーの承認待ち)
**Date:** 2026-10-17
**Primary consumers:** `.github/actions/lib/loop/`、`loop-detect`、`loop-entity-detect`、`loop-execute`、`loop-finalize`、`loop-notify-pr`、`loop-run-log`、`loop-state-promote`、`ci-loop-caller.yaml`、`ci-loop-caller-entity.yaml`、`ci-loop-agent.yaml`、`on-loop-*.yaml`、`.apm/packages/{github,repo-maintenance}/` の loop 対応 skill
**Related:** [Loop Write Target and Delivery Design](2026-07-23-loop-write-target-delivery-design.md)(四つの層。本 spec はその `delivery` 層を具体化する)、[Loop Agent Finalize Levels](2026-08-13-loop-agent-finalize-levels-design.md)、[Loop `github-pr-review` 設計](2026-10-17-loop-pr-review-design.md)
注記: 既存 spec に合わせて日本語で記述する。

## 方針(ユーザー承認済み)

- 1つの判断は、1つの値で宣言する。複数の変数を組み合わせて判断する配線は、なくす。
- 値と入力の名前は、1つの規則(第1節)にそろえる。既存の名前も対象にする。
- 破壊的変更を許す。その代わり、設計の改訂ごとに独立したレビューを行う。
- `delivery` の値は `issue_comment` / `issue_create` / `none` / `pr_create` / `pr_push` / `pr_review` の6つにする。PR の種別は、別の入力ではなく `delivery` の値で分ける。
- リリースは `scripts/self/ci/pin_config_actions.sh` で一度に行う。push までは、pin のずれを考えなくてよい。

## 背景と課題

loop の「結果をどう届けるか」は、本来1つの判断である。ところが現状は、同じ判断が複数の変数の組み合わせで、複数の場所に書かれている。

| #   | 箇所                                                                                       | 現在の判断                                                                                                                                                                                                                                                             | 問題                                                                                                                                                                                                                                                                                                                                                  |
| --- | ------------------------------------------------------------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1   | `ci-loop-caller.yaml:510` / `ci-loop-caller-entity.yaml:363` の `finalize_enabled`         | `delivery == open_pr \|\| (delivery == none && level != L1)`                                                                                                                                                                                                           | 同じ式が2か所にある。値が情報を運んでいない。L1 では `finalize-l2` ジョブ自体が動かず(`ci-loop-agent.yaml:513-517`)、L2/L3 で検証を通る `delivery` は `open_pr` と `none` だけなので、式は常に true になる                                                                                                                                            |
| 2   | `auto_merge`(caller の式、`loop-finalize` の `Enable Auto-Merge`、`loop-notify-pr` の文面) | caller が `delivery == open_pr && level == L3 && target.finalize == open_pr` を計算し、下流が strategy と level を再び確かめる                                                                                                                                         | 同じ判断が3か所にある。3項のうち `delivery == open_pr` は冗長である(`target.finalize == open_pr` が `delivery == open_pr` を含意する。`detect.sh:907-936`、`entity_target.sh:175`)                                                                                                                                                                    |
| 3   | `entity_target.sh:175` の `finalize`                                                       | `delivery == open_pr ? open_pr : none`                                                                                                                                                                                                                                 | `loop-detect` の `resolve_git_finalize_strategies`(`detect.sh:907`)と、同じ導出を別に実装している                                                                                                                                                                                                                                                     |
| 4   | `validate_loop_write_contract.sh`                                                          | `may_edit × write_target × delivery × level`                                                                                                                                                                                                                           | 4変数の許可表。`may_edit` は全 caller で `level != L1` と一致し、検証の大半は2つの食い違いを拒否するためにある                                                                                                                                                                                                                                        |
| 5   | `loop-finalize` の各ステップ                                                               | push / ブランチ削除 / state の書き方 / outcome が、それぞれ `verdict`・`has_changes`・`strategy` を個別に組み合わせて判断                                                                                                                                              | `strategy == none` の特別扱いが、複数のステップに散在する                                                                                                                                                                                                                                                                                             |
| 6   | `delivery` の enum                                                                         | `log \| issue \| notion` は検証を通るが実装がなく、`none` と同じ挙動になる                                                                                                                                                                                             | 宣言と挙動が食い違い、黙って何もしない                                                                                                                                                                                                                                                                                                                |
| 7   | 入力の既定値                                                                               | 同じ名前の入力が、層や reusable ごとに異なる既定値を持つ(第7節)                                                                                                                                                                                                        | 同じ省略が、どの reusable や action を通るかで別の意味になる。判断を表す入力にも、宣言のない既定値がある(`delivery` と `git_landing_*` は `loop-detect/action.yml:31-44`、`detect.sh:500`、`:535`、`:957`。entity の `level` と `delivery` は `loop-entity-detect/lib/detect.sh:46-47`。`level` は `loop-notify-pr/action.yml:36-37`、`notify.sh:40`) |
| 8   | PR の種別                                                                                  | `delivery: open_pr` に、pull_request ターゲットだけ `git_landing_pull_request`(`open_pr` / `push_head`)、integration ターゲットだけ `git_landing_integration`(`open_pr` / `push`)を組み合わせて、ターゲットごとの `target_json.finalize` を決める(`detect.sh:907-936`) | 「新しい PR を作る」「既存 PR に push する」は配信先が違う判断なのに、1つの値 `open_pr` と、ターゲット種別ごとの別の入力に分かれている。pr-revise は `delivery: open_pr` なのに PR を作らない(`on-loop-github-pr-revise.yaml:126`、`:132`)。`git_landing_integration: push` は PR を経由しない                                                        |
| 9   | outcome の値                                                                               | push で着地しても `pr-created` を返す(`determine_outcome.sh:56-59`)。値はハイフン区切りで、`merged` のように対象がない値もある                                                                                                                                         | PR を作っていないのに「PR 作成」になる。書き方が、他の値(snake_case)と食い違う                                                                                                                                                                                                                                                                        |
| 10  | 入力名                                                                                     | 動詞が先頭の名前(`ack_trigger_comment`、`infer_files_pattern`、`write_target`、`may_edit`)、対象がない名前(`labels`、`allowlist`、`engine`)、層をまたいで名前が変わる値(caller の `branch_match_mode` が action では `loop_branch_match`)がある                        | 名前から、何の設定かが分からない。名前でソートしても、同じ対象の設定が並ばない                                                                                                                                                                                                                                                                        |

この構造は、実際に配線の不具合を生んだ。github-pr-review の導入(#989)では、(a) `delivery: none` の L2 で finalize が動かない(`finalize_enabled` の式)、(b) `target_json.from.branch` が出ない、(c) `strategy none` で agent ブランチが main にマージされ得る、という問題を、個別の条件追加で直した。同種の問題は、loop が増えるたびに再発する。

もう1つの課題は `domain_persistence_script` である。これは finalize 内で任意のスクリプトを実行し、`GH_TOKEN` を渡す。スクリプトの中身によって必要な権限が変わるが、権限は caller の `permissions:` で固定されるため、スクリプトが何をできるかが暗黙の取り決めになっている。現状の2つの利用例(ci-sweeper、test-gap の ledger)は、リポジトリ内の JSON を jq で更新するだけで、`gh` も `curl` も呼ばない(確認済み)。一方 pr-review の `post_review.sh` は、GitHub にレビューを投稿する。

## 目標

- caller が宣言する配信は、**`delivery` の1つだけ**にする。
- 配信の種別(PR を作るか、既存 PR に push するか、など)は、`delivery` の値だけで表す。種別を別の入力で補わない。
- `delivery` と `level` から決まる判断(`pr_auto_merge`)と、`delivery` とターゲットの整合の検証は、`.github/actions/lib/loop/` の**1つの関数**で行う。caller、`ci-loop-agent.yaml`、`loop-finalize`、`loop-notify-pr` に、`delivery` や `level` を組み合わせる式を残さない。
- `delivery` の値は、すべて実装がある値にする。未実装の値は検証で失敗させる(fail closed)。
- 判断を表す入力(`delivery`、`level`)には、どの層にも既定値を置かない。`level` に従属する入力は、`level` ごとに検証する(第6節)。
- 効かない値は受け付けない。L1 で、L2/L3 だけに効く入力を指定したら、検証で拒否する。
- 値、入力名、プロンプトのキー、環境変数の名前を、第1節の規則にそろえる。同じ値は、どの層でも同じ名前で運ぶ。

## 非目標

- Linear / JIRA / Notion など外部システムへの配信。秘密情報の受け渡しを設計しない限り権限が曖昧になるため、将来の追加枠として記すだけにする。
- 1回の実行での複合配信(`pr_create` と `issue_create` の同時実行、ターゲットごとに配信の種別を変えること)。既存 spec の方針を踏襲し、loop を分ける。
- `post_review.sh` の分割(移行の節の Phase P として別 spec)。
- `level` の意味(L1/L2/L3 のエージェント権限)の変更。
- caller の `permissions:` を `delivery` ごとに絞ること。理由は第5節に書く。
- `ci-loop-agent.yaml` と各 composite action を、caller を経由せずに直接呼ぶ利用者との互換性。docs が示す経路は `on-loop-* → ci-loop-caller* → ci-loop-agent` だけである(`loop-caller-reusable-design.md:356`)。

## アンチゴール(これが起きたら失敗)

- 導出の場所が増える(別の action や caller に、新しい `delivery` の判断式が入る)。
- リリースの前後で、dogfood の loop の挙動が変わる(PR が開かない、開きすぎる、auto-merge の条件が変わる、state やブランチの扱いが変わる、loop が検証で止まる)。第8節の outcome の改名による値の変化だけは、意図した変更とする。
- 新しい設定値が増える(既存の入力を置き換えずに、並行して別の入力が生まれる)。

## 設計

### 1. 命名規則と `delivery` の値

**命名規則(MUST):**

- snake_case で書く。
- **対象(domain)を先、属性や動作を後**にする(`pr_review`、`issue_comment`、`agent_edit_target`)。名前でソートしたとき、同じ対象のものが隣に並ぶようにするためである。
- 動詞を先頭にした名前は作らない(`open_pr`、`ack_trigger_comment`、`may_edit` は改名する)。
- 動作を表す値は、対象と動詞にする(`pr_create`、`pr_push`)。結果を表す値は、対象と過去分詞にする(`pr_created`、`pr_pushed`、`pr_merged`)。
- 1語で完結する状態の値(`none`、`rejected`、`reported`、`skipped`、`error`)は、そのままにする。
- 同じ値は、caller の入力、action の入力、`target_json`、プロンプトのキー、環境変数(大文字)のどこでも、同じ名前で運ぶ。

入力名の対象は、次の接頭辞で表す。

| 接頭辞                | 対象                                                         |
| --------------------- | ------------------------------------------------------------ |
| `agent_`              | maker と checker(実行するエージェント、その編集の範囲と出力) |
| `detect_`             | 検出(何を対象にするか)                                       |
| `finalize_`           | 着地と後処理                                                 |
| `pr_`                 | finalize が作る PR                                           |
| `state_`              | `.loop/` の状態の保存                                        |
| `budget_`、`run_log_` | 予算と実行ログ(既存の名前のまま)                             |
| `trigger_`            | 実行のきっかけになったイベント                               |

接頭辞のない入力は、loop 全体の設定である `delivery`、`level`、`loop_name`、`environment`(GitHub Actions の environment の名前)だけにする。

**規則を当てはめる範囲:** 設定の値と、設定から導いた判断の値である。具体的には、caller の入力、その値を運ぶ下の層(`ci-loop-agent.yaml`、各 action)の入力と出力、プロンプトのキー、環境変数、detect の JSON のキー、`delivery` と outcome の値である。新しく作る値も、この規則に従う(導出する `auto_merge` は `pr_auto_merge` にする)。

ジョブやステップの間で実行時のデータを受け渡すだけの入力(`target_json`、`prompt_text`、`verifier_context`、`skip_reason`、`run_started_at`、`handoff_artifact_name`、`loop-finalize` の `branch`・`execute_branch`・`has_changes`・`verdict`・`reject_reason` など)は、設定ではないので範囲外とし、名前を変えない。

**`delivery` の値:** `delivery` は、「エージェントの出力を、どこへ、どう届けるか」を表す。閉じた集合とする。

| 値              | 意味                                                                                                                              | 使えるターゲット           | 状態                                                                                      |
| --------------- | --------------------------------------------------------------------------------------------------------------------------------- | -------------------------- | ----------------------------------------------------------------------------------------- |
| `issue_comment` | 既存の Issue にコメントを投稿する                                                                                                 | Issue の entity            | 未実装。実装されるまで検証で拒否                                                          |
| `issue_create`  | レポートから Issue を新規作成する                                                                                                 | すべて                     | 未実装。実装されるまで検証で拒否                                                          |
| `none`          | プラットフォームは何も配信しない。エージェントが自分で完結する(L1 triage)か、レポートファイルを finalize の hook スクリプトが扱う | すべて                     | 実装済み                                                                                  |
| `pr_create`     | 新しいブランチと PR を作る(L3 では auto-merge を有効にする。draft にするかは `pr_draft`)                                          | すべて                     | 実装済み(現在の `open_pr`。PR ターゲットでは、現在の `git_landing_pull_request: open_pr`) |
| `pr_push`       | 既存 PR の head ブランチへ、最新の head を merge して push する。新しい PR は作らない                                             | pull_request(既存の PR)    | 実装済み(現在の `open_pr` + `git_landing_pull_request: push_head`)                        |
| `pr_review`     | 検証済みのレポートを、既存 PR へのレビュー(COMMENT 形式、インラインコメント付き)として投稿する                                    | pull_request、PR の entity | **Phase P まで未実装**。実装されるまで検証で拒否                                          |

- 名前でソートすると、`issue_*` と `pr_*` が、それぞれ隣に並ぶ。
- `log` と `notion` は enum から削除する。実装がなく、必要になったときに、複数の loop が使うと分かった時点で追加する。
- `issue_create` は「作る」、`issue_comment` は「既存に書く」で、1つの値に分岐を隠さない。`pr_create`・`pr_push`・`pr_review` も同じで、PR の扱いの種別ごとに値を分ける。
- `none` は「何もしない」の意味に限定する。pr-review が `none` で動いている現状は、Phase P で `pr_review` に移るまでの暫定である。
- `none` 以外は finalize が配信するので、L2 以上でしか使えない(第6節)。
- 「使えるターゲット」の種別は、`target_json` から読む。branch caller のターゲットは、既存の `target_json.mode`(`integration` / `pull_request`)で分ける。entity のターゲットは、現在 `target_json` に種別がない(`entity_target.sh:160-177`)。`loop-entity-detect` が、起動したイベントから `target_json.entity.kind`(`issue` / `pr`)を書き足す。skill の `handoff_key` の書式には頼らない。
- `pr_create` と `pr_push` は、安全条件が異なる。`pr_push` は、最新の head へ merge してから push し、衝突や non-fast-forward では fail closed にする(`push_target.sh`、`.github/workflows/CLAUDE.md` の push_head の規則)。
- 現在の `git_landing_integration: push`(integration ブランチへ直接 push する)は、PR を経由しないので、どの値にも当たらない。dogfood の caller は使っていない。ユーザーの方針(「いらないなら削除」)に従い、削除する。
- PR の種別を `delivery` に入れたので、`git_landing_integration` と `git_landing_pull_request` の入力は、どちらも削除する(第7-2節)。

**dogfood の caller の移り先:**

| loop                                                                        | 現在                                                                               | 新しい `delivery`                                                          |
| --------------------------------------------------------------------------- | ---------------------------------------------------------------------------------- | -------------------------------------------------------------------------- |
| changelog、autofix、tech-debt、refactor、test-gap、docs-updater、ci-sweeper | `open_pr`(ci-sweeper の PR ターゲットも、既定値の `open_pr` で新しい PR を作る)    | `pr_create`                                                                |
| pr-revise                                                                   | `open_pr` + `git_landing_pull_request: push_head`(手動起動では `open_pr` も選べる) | `pr_push`(手動起動の選択肢は `pr_push` / `pr_create` の `delivery` にする) |
| pr-review、triage                                                           | `none`                                                                             | `none`                                                                     |

### 2. 導出と検証は `lib/loop/` の1つの関数で行う

`.github/actions/lib/loop/` に、`delivery`・`level`・ターゲットから、finalize の判断を導き、整合を検証する関数を1つ置く。`.github/workflows/CLAUDE.md` の Composition の規則により、2つの composite が共有するロジックは `lib/loop/` に置く必要がある(別の composite の `lib/` は共有契約にできない)。

| 項目                  | 内容                                                                                                                                                                                                                                    |
| --------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `pr_auto_merge`(導出) | `level == L3` かつ `delivery == pr_create`。実行単位(run 単位)の値。現在の caller の `auto_merge` の式を置き換える                                                                                                                      |
| ターゲットの検証      | ターゲットの種別が、`delivery` の「使えるターゲット」(第1節の表)に入らないとき、失敗させる。例: `pr_push` で integration のターゲットが出たとき、`issue_comment` で PR の entity が来たとき。`pr_push` の追加の規則は、この表の下に書く |

- `loop-detect` と `loop-entity-detect` は、この関数を呼ぶ。`pr_auto_merge` を、`delivery` と並べて detect ジョブの出力にする(`delivery` は、すでに出力している。`ci-loop-caller.yaml:284`)。
- caller は、`needs.detect.outputs.delivery` と `needs.detect.outputs.pr_auto_merge` を、`ci-loop-agent.yaml` にそのまま渡す。式は書かない。
- `target_json.finalize` は削除する。1回の実行の全ターゲットで、`delivery` と同じ値になるためである。`detect.sh` の `resolve_git_finalize_strategies`(`detect.sh:907`)、`target_json` を組み立てる関数の `finalize` 引数(`detect.sh:302-372`)、`entity_target.sh:175` の独自の導出も削除する。
- `finalize` の値は `.loop/` に保存されていないので、削除しても永続データの互換は問題にならない。

**旧式との一致(`pr_auto_merge`):** caller の `auto_merge` の旧式は `delivery == open_pr && level == L3 && target.finalize == open_pr` である。旧式の `target.finalize == open_pr` は、新しい `delivery == pr_create` に当たる(第1節の移り先の表)。旧式の `delivery == open_pr` は、これに含意される。したがって、旧式は `level == L3 && delivery == pr_create` と等しい。

**ターゲットの混在:** 旧い入力では、1回の実行に `open_pr` と `push_head` のターゲットが混在できた(integration は `open_pr`、pull_request は `push_head`)。新しい値では、`pr_push` は integration のターゲットを受け付けないので、混在は検証で失敗する。

- pr-revise は、PR 番号で監視を絞るとき、integration のターゲットを捨てる(`detect.sh:259-283` の `apply_scoped_pr_number_filter`)。PR 番号がないときは、pr-revise の detect スクリプトがスキップする(`detect_pr_revise.sh:312-313`)。そのため dogfood では混在しない。
- 新しい設計では、この2つの守りを platform の規則にする。PR 番号を確かめる責任を、skill の detect スクリプトに任せない。
  - `pr_push` は、`detect_pr_enabled: true` を必須にし、`detect_branch_match` の指定を拒否する(設定の誤りなので、検証で失敗させる)。
  - `pr_push` で `detect_pr_number` が空か 0 の起動(PR 番号を持たない `repository_dispatch` など)は、detect がスキップを返す。理由は `skip_reason` に書き、`record-skip` が run-log に `skipped` を記録する。現在の `detect_pr_revise.sh:312-313` のスキップと、観測できる挙動は同じである。
  - `pr_push` で integration のターゲットが出たら、失敗させる。上の2つの規則があれば到達しないが、守りとして残す。

**下流の変更:**

- `ci-loop-agent.yaml`・`loop-finalize`・`loop-notify-pr` の入力 `auto_merge` は、`pr_auto_merge` に改名する。`loop-finalize` の `Enable Auto-Merge` は、`pr_auto_merge` の入力だけを見る(strategy の再確認をやめる)。`loop-notify-pr` の L3 の文面(`notify.sh:208`)も、`pr_auto_merge` の入力だけを見る。

**`finalize_enabled` の廃止:** `finalize_enabled` は、`finalize-l2` ジョブ内の `loop-finalize` **ステップ**だけを止めるフラグである(`ci-loop-agent.yaml:3-4`、`:568`)。

- `finalize_enabled` を、caller と `ci-loop-agent.yaml` から削除する。`finalize-l2` では、`loop-finalize` ステップを常に実行する。
- 背景 #1 のとおり、検証を通る設定では、L2/L3 の旧 `finalize_enabled` は常に true である。dogfood の全 caller で、次のとおり挙動は変わらない。

| loop                                                         | 現在の `delivery` | `level`             | 旧: `loop-finalize` ステップ | 新: `loop-finalize` ステップ |
| ------------------------------------------------------------ | ----------------- | ------------------- | ---------------------------- | ---------------------------- |
| changelog、autofix、pr-revise、tech-debt、refactor、test-gap | `open_pr`         | L2                  | 実行                         | 実行                         |
| docs-updater、ci-sweeper                                     | `open_pr`         | 指定なし(既定値 L2) | 実行                         | 実行                         |
| github-pr-review                                             | `none`            | L2                  | 実行                         | 実行                         |
| github-issue-triage                                          | `none`            | L1                  | `finalize-l2` が動かない     | `finalize-l2` が動かない     |

- 旧式で `loop-finalize` が止まる L2/L3 の組み合わせは、`delivery` が `log` / `issue` / `notion` のときだけで、これらは `may_edit: true` で検証が拒否する(`validate_loop_write_contract.sh:114-118`)。到達しない。

### 3. `loop-finalize` は `delivery` だけを見る

`loop-finalize` は、`delivery` を入力に受け取り、`target_json.finalize`(現在の `finalize_strategy`)の代わりに使う。各ステップの判断は、`delivery` の1つの値で決まる。

| `delivery`  | push                        | PR の作成 | state の書き方(APPROVE で変更あり) | outcome(APPROVE で変更あり) |
| ----------- | --------------------------- | --------- | ---------------------------------- | --------------------------- |
| `pr_create` | なし                        | 作る      | `pending`                          | `pr_created`                |
| `pr_push`   | PR の head へ merge と push | なし      | `advance`                          | `pr_pushed`                 |
| `none`      | なし                        | なし      | `metadata`                         | `reported`                  |

- push、PR の作成、state の書き方、agent ブランチの削除の条件は、現在の strategy による分岐(`loop-finalize/action.yml:193-315`、`should_push_target.sh`、`should_delete_rejected_branch.sh`)と同じにする。strategy の値を `delivery` の値に置き換えるだけで、挙動は変えない。outcome だけは、第8節のとおり `pr_push` で `pr_pushed` を返すように変える。
- `TARGET_JSON` が空のとき `open_pr` とみなす現在のフォールバック(`loop-finalize/action.yml:155`、`:160`)は削除し、失敗させる。黙って PR を作る既定値は、本 spec が取り除く「宣言のない判断」である。dogfood の2つの caller は、常に `target_json` を渡している。

### 4. finalize の hook スクリプトの契約

現在の `domain_persistence_script` を `finalize_hook_script` に改名する(第7節)。

- 位置づけ: 配信ではなく、finalize に差し込む**副次的な独自処理**(ledger、ログなど)。
- 許される範囲: リポジトリルート配下の相対パスのファイル更新のみ(現在の ledger スクリプトが、すでにこれを検証している)。外部システムへの書き込みはしない。
- 権限: 書き込みトークンを必要としない。ただし、Phase P までは `post_review.sh` が `GH_TOKEN` を使うため、`GH_TOKEN` の受け渡しは残す(過渡的な例外として明記する)。
- 実行条件: `delivery` に関係なく、`loop-finalize` が動くとき(L2/L3)に1回実行する。失敗の扱いは現在の挙動を変えない。
- 環境: スクリプトは、`detect_env_json`(現在の `detect_domain_env_json`)の値を受け取らない。この値は detect ジョブの `GITHUB_ENV` にだけ入り、finalize ジョブには届かない。スクリプトが書くファイルのパスは、スクリプトの既定値で決め、caller の `finalize_commit_paths` と一致させる。test-gap はすでに従っている(`update_test_gap_ledger.sh:57`)。ci-sweeper は反している(第9節)。
- `finalize_commit_paths`(現在の `additional_commit_paths`)は、スクリプトの出力のうち commit してよいパスの許可リストとして残す。`loop-finalize` は、スクリプトを先に実行し、後続の `Write State` が、列挙されたパスだけを commit に加える(`write_state.sh:114-150`)。

### 5. 権限は本 spec では変えない

caller の `permissions:` を `delivery` から導くことはしない。reusable の各ジョブが、`delivery` に関係なく固定の書き込み権限を要求しているためである(`ci-loop-caller.yaml` の execute ジョブ、`ci-loop-agent.yaml` の `agent-l2` と `finalize-l2`)。caller はこの権限を与えないとワークフローを起動できないので、「`delivery` に必要な権限を含むか」という静的テストは常に通り、何も検証しない。権限を `delivery` ごとに絞るには、reusable のジョブを `delivery` ごとに分ける構造の変更が必要で、本 spec の範囲を超える。

### 6. 入力の検証は `level` を主キーにする

`may_edit` を入力から外す(第7節)と、許容値を決めているのは `level` になる。`validate_loop_write_contract.sh` を、`level` を主キーにした表に書き直す。新しい入力名(第7節)で示す。

| `level` | `delivery`                                                                                               | `agent_edit_target`     | `agent_edit_allowlist`                       | `agent_edit_denylist`     | `agent_unchanged_verdict`   |
| ------- | -------------------------------------------------------------------------------------------------------- | ----------------------- | -------------------------------------------- | ------------------------- | --------------------------- |
| L1      | `none`                                                                                                   | 指定は拒否              | 指定は拒否                                   | 指定は拒否                | 指定は拒否                  |
| L2 / L3 | `pr_create`、`pr_push`、`none`(Phase P で `pr_review`、実装時に `issue_create` / `issue_comment` を追加) | `fix` か `report`(必須) | 必須(空は拒否)。制限しないときは `**` を書く | 任意(空は既定の denylist) | `APPROVE` か `REJECT`(必須) |

- L1 で `pr_create` / `pr_push` を拒否するのは、現在の検証(L1 で `open_pr` を拒否)と同じである。L1 で `issue` / `log` / `notion` を通している現在の検証は、第1節の削除と fail closed により、`none` だけを通すようになる。
- L1 で拒否する4つの入力は、どれも L1 の経路に届かない。`agent_unchanged_verdict`(現在の `no_changes_verdict`)は、`agent-l2` の `loop-execute` にだけ渡る(`ci-loop-agent.yaml:508`)。L1 の outcome は、成功なら常に「差分なし」になる(`ci-loop-agent.yaml:365`、`:381`)。
- `agent_edit_allowlist` の空は、現在「無制限」を意味する(`loop-execute/lib/paths.sh:63-65`、`loop-detect/action.yml:14`)。L2/L3 で空を拒否し、無制限は `**` で明示させる。`**` は全パスに一致する(`paths.sh` の `glob_to_ere`、`paths.bats:79-81`)。書き忘れが「無制限」として黙って通る状態を、なくすためである。
- `build_constraints.sh` は、allowlist が空でないとき「Allowed paths: …」をプロンプトに出す(`build_constraints.sh:96-99`)。`**` のときは、現在の空と同じく何も出さないようにし、プロンプトの内容を変えない。
- **検証に必要な値を detect に届ける。** 現在、`loop-entity-detect` には `allowlist`・`denylist`・`no_changes_verdict` の入力がなく、`loop-detect` には `denylist` と `no_changes_verdict` の入力がない(`loop-entity-detect/action.yml:6-65`、`loop-detect/action.yml`)。この表の検証を detect の時点で行うため、2つの action に、表の入力をすべて追加する。entity のプロンプトは allowlist を常に空で組み立てている(`entity_target.sh:69`)ので、受け取った値を使うように直す。
- **検証は、スクリプトで行う。** composite action の `required: true` には頼らない。必須の値が空のときは、`validate_loop_write_contract.sh` が失敗させる。

### 7. 入力の改名、削除、既定値の整理

調べた範囲は、`ci-loop-caller.yaml`・`ci-loop-caller-entity.yaml`・`ci-loop-agent.yaml` の全入力の定義と既定値(スクリプトで3つを並べて比較した)、`loop-detect`・`loop-entity-detect`・`loop-finalize` の action の入力、全 loop caller(`on-loop-*.yaml` の10本。`on-loop-state-promote.yaml` を除く)の `with:` の全値である。caller の値と既定値の突き合わせも、スクリプトで全件を比較した。

caller の内訳: `ci-loop-caller.yaml` を使うのは changelog、refactor、autofix、tech-debt、docs-updater、test-gap、pr-revise、ci-sweeper の8本。`ci-loop-caller-entity.yaml` を使うのは triage と pr-review の2本。

#### 7-1. 改名

caller の入力(2つの reusable)の改名表である。同じ値を運ぶ下の層(`ci-loop-agent.yaml` の入力、action の入力、環境変数、プロンプトのキー)も、同じ名前にする。表にない caller の入力(`agent_checker_*`、`agent_maker_*`、`agent_loop_max_attempts`、`budget_*`、`delivery`、`detect_script`、`environment`、`level`、`loop_name`、`pr_body`、`pr_draft`、`pr_title`、`run_log_file`、`state_file`)は、すでに規則に合っているので変えない。

| 現在の名前                  | 新しい名前                   | 理由                                                      |
| --------------------------- | ---------------------------- | --------------------------------------------------------- |
| `ack_trigger_comment`       | `trigger_comment_ack`        | 動詞が先頭                                                |
| `additional_commit_paths`   | `finalize_commit_paths`      | 対象がない。finalize の commit に加えるパス               |
| `agent_allowed_tools`       | `agent_tool_allowlist`       | `agent_edit_allowlist` と同じ形にそろえる                 |
| `allowlist`                 | `agent_edit_allowlist`       | 対象がない。maker が編集してよいパス                      |
| `branch_match`              | `detect_branch_match`        | 対象がない。監視するブランチのパターン                    |
| `branch_match_mode`         | `detect_branch_match_mode`   | 対象がない                                                |
| `branch_prefix`             | `agent_branch_prefix`        | 対象がない。agent の作業ブランチの接頭辞                  |
| `branch_state`              | `state_branch`               | 対象が後ろにある。第7-3節で、監視の意味を切り離す         |
| `cli_version`               | `agent_cli_version`          | 対象がない                                                |
| `commit_message`            | `agent_commit_message`       | 対象がない。agent の試行ごとの commit メッセージ          |
| `denylist`                  | `agent_edit_denylist`        | 対象がない                                                |
| `detect_domain_env_json`    | `detect_env_json`            | `domain` は情報を足していない                             |
| `dispatch_hook_script`      | `detect_hook_script`         | detect の後に動く hook。`finalize_hook_script` と対にする |
| `domain_persistence_script` | `finalize_hook_script`       | finalize に差し込む hook(第4節)                           |
| `engine`                    | `agent_engine`               | 対象がない                                                |
| `infer_files_pattern`       | `agent_checker_path_pattern` | 動詞が先頭。checker の出力からパスを拾う正規表現          |
| `labels`                    | `pr_labels`                  | 対象がない。作る PR のラベル                              |
| `max_targets_per_schedule`  | `detect_max_targets`         | 対象がない                                                |
| `no_changes_verdict`        | `agent_unchanged_verdict`    | 対象がない。maker が差分を作らなかったときの判定          |
| `outcome_override`          | `finalize_outcome_override`  | 対象がない                                                |
| `pr_enabled`                | `detect_pr_enabled`          | `pr_` は作る PR を表す。これは監視の設定                  |
| `pr_exclude`                | `detect_pr_exclusions`       | 監視の設定。動詞を名詞にする                              |
| `pr_include_bots`           | `detect_pr_bot_allowlist`    | 監視の設定。動詞が入っている                              |
| `priority`                  | `detect_priority`            | 対象がない                                                |
| `scoped_pr_number`          | `detect_pr_number`           | 監視の設定。形容詞が先頭                                  |
| `write_target`              | `agent_edit_target`          | 動詞が先頭。値は `fix` / `report`                         |

**プロンプトのキー:** `build_constraints.sh` がプロンプトの `## Constraints` に出すキーも、同じ名前にする。skill は、このキーで分岐している。

| 現在のキー     | 新しいキー           |
| -------------- | -------------------- |
| `may_edit`     | `agent_edit_allowed` |
| `write_target` | `agent_edit_target`  |
| `report_file`  | `agent_report_file`  |

`agent_edit_allowed` は caller の入力ではなく、`level` から導出する(7-2)。「Allowed paths: …」の行の文言は変えない。`build_constraints.sh` の指示文のうち、キーの名前を含むもの(`:79`、`:86` の `may_edit`・`report_file`・`allowlist` など)は、新しいキーの名前に直す。

**checker の判定基準:** `loop-execute/lib/agent_output_format_criteria.md` は、checker に、`## Constraints` の `may_edit`・`write_target`・`report_file` で mode を判断させている(`:7`、`:9`、`:11`、`:13`、`:22`)。この基準は、`verifier.sh:310-314` で checker のプロンプトに連結される。プロンプトのキーと同時に、新しいキーの名前に直す。直さないと、checker が mode を判別できず、`validate_agent_report.sh:34` が対象にする5つの skill(changelog、ci-sweeper、docs-updater、refactor、tech-debt)で判定を誤る。

**action の入力と環境変数:** `loop-detect` の `loop_` 接頭辞の入力(`loop_branch_match`、`loop_integration_branches`、`loop_max_targets_per_schedule`、`loop_pr_enabled`、`loop_pr_exclude`、`loop_pr_include_bots`、`loop_priority`、`loop_scoped_pr_number`)は、caller の新しい名前と同じにする。現在は caller の `branch_match_mode` が `loop_branch_match` に、`branch_match` が `loop_integration_branches` に入り(`ci-loop-caller.yaml:359-360`)、同じ語が層ごとに別の値を指している。環境変数(`LOOP_BRANCH_MATCH` など)も、入力名を大文字にした名前にする。

**state ブランチと base ブランチ:** 現在は、同じ state ブランチが層ごとに別の名前で運ばれ、`base_branch` という1つの名前が2つの意味を持つ。

| 層の入力                                                                           | 現在運ぶ値                                                                                                          | 新しい扱い                                                                                                                         |
| ---------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------- |
| `loop-detect` の `base_branch`                                                     | caller の `branch_state`(`ci-loop-caller.yaml:349`)                                                                 | `state_branch` に改名                                                                                                              |
| `loop-run-log` の `base_branch`                                                    | state ブランチ(`ci-loop-caller.yaml:569`、`ci-loop-agent.yaml:361`、`:648`)                                         | `state_branch` に改名。`ci-loop-agent.yaml` の `state_push_branch != '' && … \|\| base_branch` の式もなくし、`state_branch` を渡す |
| `ci-loop-agent.yaml`、`loop-finalize`、`loop-state-promote` の `state_push_branch` | state ブランチ(`loop-finalize/action.yml:107`、`loop-state-promote/action.yml:19`、`on-loop-state-promote.yaml:59`) | `state_branch` に改名。`on-loop-state-promote.yaml` も直す                                                                         |
| `loop-finalize` の `base_branch`                                                   | PR の base のフォールバック(`action.yml:149`、`:161`)と、state ブランチが空のときの代わり(`action.yml:109`、`:301`) | 削除。PR の base は `target_json` から読み、state ブランチは必須の `state_branch` を使う                                           |
| `loop-execute` の `base_branch`                                                    | 差分の比較先(`ci-loop-agent.yaml` がターゲットの base を `target_json` から取り出して渡す。`:497`)                  | 変えない。削除と改名の後は、この意味だけになる                                                                                     |

**detect の JSON のキー:** skill の detect スクリプトが出す `.report_file`(`matrix.sh:73-74`、`detect_tech_debt.sh:215`)は、プロンプトのキーと同じ `agent_report_file` にする。

#### 7-2. 削除

| 入力                                                                                    | 理由                                                                                                                                                                                                                                                  | 代わり                                                                                                                                                                                                           |
| --------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `may_edit`(2つの reusable、`loop-detect`、`loop-entity-detect`)                         | 全10 caller で `level != L1` と一致する。検証が食い違いを拒否しているだけ                                                                                                                                                                             | `lib/loop/` で `level` から導出し、プロンプトの `agent_edit_allowed` に出す。非推奨のシム `emit_loop_constraints_from_level` と、それを呼ぶ `emit_loop_constraints_legacy`(`build_constraints.sh:164`)も削除する |
| `ci-loop-agent.yaml` の `finalize_enabled`(`:137`、`:568`)、caller の `auto_merge` の式 | 第2節                                                                                                                                                                                                                                                 | `finalize_enabled` は代わりなし。`pr_auto_merge` は detect ジョブの出力を、そのまま渡す                                                                                                                          |
| `git_landing_integration`、`git_landing_pull_request`(caller、`loop-detect`)            | PR の種別を `delivery` の値で表す(第1節)。`push` は削除する                                                                                                                                                                                           | `delivery` の `pr_create` / `pr_push`                                                                                                                                                                            |
| `dispatch_hook_token`(reusable と `loop-entity-detect`)                                 | トークンを `with:` で渡す。`.github/workflows/CLAUDE.md` は、reusable workflow にトークンを `with:` で渡すことを禁じている。dogfood は使っていない                                                                                                    | dispatch hook は、常に detect のトークンを使う(`loop-entity-detect/lib/detect.sh:51`、`:238` の分岐もなくす)。別のトークンが必要になったら `secrets:` で宣言する                                                 |
| `ci-loop-agent.yaml` の `detect_result_json`                                            | 2つの caller が、常に `"{}"` を渡している(`ci-loop-caller.yaml` と `ci-loop-caller-entity.yaml` の execute ジョブ)。値を運んでいない                                                                                                                  | なし(`loop-execute` と `loop-finalize` の同名の入力と `DETECT_RESULT_JSON` も削除する)                                                                                                                           |
| `ci-loop-agent.yaml` の `handoff_key`、`current_sha`、`base_branch`                     | どれも `target_json` から導ける(`target_json.key`、`target_json.from.ref`、pull_request なら `target_json.base.branch`、それ以外は `target_json.to.branch`)。`base_branch` は、2つの caller で式が異なる(entity の式は pull_request の分岐を持たない) | `ci-loop-agent.yaml` の中で `target_json` から取り出す。`matrix.sh:136` の `handoff_key` の複製もなくす。`agent-l2` の Parse Target の、`target_json` が空のときのフォールバック(`:459-465`)は削除し、失敗させる |

#### 7-3. 1つの入力が持つ2つの意味を分ける(`branch_state`)

`branch_state` は、「`.loop/` の状態を保存するブランチ」と、「`branch_match` が空のときに監視するブランチ」の2つを兼ねている(`ci-loop-caller.yaml:349`、`branches.sh:93-106`、`detect.sh:1223`)。

- `state_branch` は、状態の保存先だけを表す。
- `detect_branch_match` は、integration ブランチを監視するときだけ指定する。空なら、integration ブランチを監視しない。空のときに `state_branch` を監視するフォールバックは削除する。
- branch caller では、`detect_branch_match` と `detect_pr_enabled: true` の少なくとも一方を必須にする。どちらもないと、ターゲットが常に0件になり、黙って何もしない loop になるためである。
- `delivery: pr_push` では、`detect_branch_match` の指定を拒否する(第2節)。
- 現在の8本の branch caller は、どれも `branch_match: main` と `branch_state: main` を両方渡している。pr-revise を除く7本は、値をそのまま移せる(挙動は変わらない)。
- pr-revise は、`branch_match` を削除する。`pr_push` でも、手動起動で選ぶ `pr_create` でも、`detect_pr_enabled: true` だけで検証を通る。integration のターゲットは、現在も PR 番号の絞り込みで捨てられている(第2節)ので、挙動は変わらない。手動起動の `pr_create` は、PR ターゲットに対して新しい PR を作る(現在の `git_landing_pull_request: open_pr` と同じ)。
- entity caller は監視ブランチを持たないので、`state_branch` だけになる。

#### 7-4. 既定値の整理

- **判断を表す入力(`delivery`、`level`):** どの層にも既定値を置かない。2つの reusable では必須にする。action とスクリプトにある既定値(`delivery` は `loop-detect/action.yml:31-33`、`detect.sh:957`。entity の `level` と `delivery` は `loop-entity-detect/lib/detect.sh:46-47`。`level` の `L2` は `loop-notify-pr/action.yml:36-37`、`notify.sh:40`)も削除し、空なら失敗させる。`git_landing_*` の既定値(`loop-detect/action.yml:35-42`、`detect.sh:500`、`:535`)は、入力ごと削除する(第7-2節)。docs-updater と ci-sweeper には `level: L2` を足す(他の caller は明示済み)。
- **`level` に従属する入力(第6節の表の4つ):** 値を運ぶすべての層(2つの reusable、`ci-loop-agent.yaml`、`loop-detect`、`loop-entity-detect`、`loop-execute`)で、`required: false`、既定値 `""` にそろえる。`ci-loop-agent.yaml:170-171` と `loop-execute/action.yml:96-97` の `no_changes_verdict` の既定値 `REJECT` も削除する(値は detect の時点で検証済みのものだけが届く)。現在の既定値は、reusable ごとに異なる(`write_target` は branch で必須・entity で `report`、`allowlist` は branch で必須・entity で `""`、`no_changes_verdict` は branch で `REJECT`・entity で `APPROVE`)。許容値は第6節の表で検証する。triage からは、`write_target`・`allowlist`・`denylist`・`no_changes_verdict` の4行を削除する。autofix、pr-revise、pr-review の `allowlist: ""` は `"**"` にする(挙動は変わらない)。
- **配管の入力の明示された既定値:** caller が既定値と同じ値を書いている行は、削除する(挙動は変わらない)。対象は `environment: default`(10本)、`agent_checker_skill_name: loop-verifier`(10本)、`pr_body: ""`(6本)、`pr_enabled: false`(5本)、`max_targets_per_schedule: 3`(changelog、ci-sweeper、docs-updater)、`detect_domain_env_json: "{}"`(tech-debt、test-gap)、`pr_exclude: fork,draft,label:no-loop` と `pr_include_bots: ""`(ci-sweeper)。L2/L3 の caller の `denylist: ""`(6本)も、第6節の表で任意の入力なので、ここで削除する。判断を表す入力と、`level` に従属する必須の入力は、既定値と同じでも caller が書く。

**確認して、残すもの:**

- `agent_unchanged_verdict`: 「maker が差分を作らなかったときに、`APPROVE` と `REJECT` のどちらにするか」は、L2/L3 の loop ごとのドメイン判断で、`level` からは決まらない。L2/L3 で必須にする。
- `agent_edit_target` は、`delivery` から導出しない。tech-debt は `delivery: pr_create` で `write_target: report` であり、`delivery` と1対1にならない。
- `finalize_commit_paths` と `finalize_hook_script` は、同じファイルのパスを両方に書くが、冗長ではない(第4節)。
- `state_file` / `run_log_file` / `budget_file` / `pr_labels` / `agent_branch_prefix` / `agent_commit_message` / `detect_priority`: dogfood の caller は、どれも上書きしていない。配布先が調整するための入力なので残す。

### 8. outcome の値

| 現在の値     | 新しい値     | 書く場所                                                            | 変更の理由                                                             |
| ------------ | ------------ | ------------------------------------------------------------------- | ---------------------------------------------------------------------- |
| `pr-created` | `pr_created` | `determine_outcome.sh:59`、ledger スクリプト                        | snake_case。`delivery == pr_create` のときだけ返す                     |
| (なし)       | `pr_pushed`  | `determine_outcome.sh`                                              | `delivery == pr_push` で着地したとき。現在は `pr-created` を返している |
| `merged`     | `pr_merged`  | `loop-state-promote/lib/run.sh:407`                                 | 対象がない                                                             |
| `pr-closed`  | `pr_closed`  | `loop-state-promote/lib/run.sh:410`                                 | snake_case                                                             |
| `no-changes` | `unchanged`  | `determine_outcome.sh:53`、`ci-loop-agent.yaml:365`、`:381`、`:654` | snake_case にすると対象のない2語になるため、1語の状態にする            |
| `no-action`  | `unchanged`  | ci-sweeper の ledger(`update_run_ledger.sh:194`)                    | `no-changes` を ledger で言い換えているだけ。同じ意味に1つの名前       |

`rejected`、`reported`、`skipped`、`error`、`watch`(ci-sweeper の override)、`escalated`(ledger)は変えない。

**読む側の変更**(コードの全件。`pr-created` などを含むファイルを grep した結果):

| ファイル                                                                      | 現在の読み方                                                          | 新しい読み方                                                                                                                                                                                   |
| ----------------------------------------------------------------------------- | --------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `loop-finalize/lib/write_state.sh:163`                                        | advance モードで `pr-created` なら、state PR へのフォールバックを拒否 | advance モードで `pr_pushed` なら拒否。advance モードは `pr_push` の着地だけなので、現在と同じ条件になる。字面どおり `pr_created` に置き換えると条件が成立しなくなるので、置き換えてはならない |
| `loop-finalize/lib/write_state.sh:312`、`prune_targets.sh:87`                 | `pr-closed`                                                           | `pr_closed`                                                                                                                                                                                    |
| `loop-notify-pr/lib/notify.sh:207`                                            | `pr-created` で、修正 PR の URL があるとき次の手順を出す              | `pr_created`。`pr_pushed` は修正 PR を持たず、現在も URL が空で文面が出ないので、挙動は変わらない                                                                                              |
| `lib/loop/loop_meta.sh:147`                                                   | `no-changes` / `skipped` / `watch`                                    | `unchanged` / `skipped` / `watch`                                                                                                                                                              |
| `ci-loop-agent.yaml:654`                                                      | `no-changes` を書く(フォールバック)                                   | `unchanged` を書く                                                                                                                                                                             |
| `loop-run-log/action.yml:44`                                                  | 説明文に値を列挙                                                      | 新しい値に直す                                                                                                                                                                                 |
| ci-sweeper の `update_run_ledger.sh:189-195`、`detect_ci_failures.sh:535-538` | `pr-created` / `no-changes` → `no-action`                             | `pr_created` と `pr_pushed` を「着地した」として同じに扱う。`unchanged` はそのまま記録する                                                                                                     |
| test-gap の `update_test_gap_ledger.sh:141-147`                               | `pr-created` を記録し、`no-action` / `no-changes` は記録しない        | `pr_created` と `pr_pushed` を記録する。`unchanged`(と旧い `no-action` / `no-changes`)は、現在と同じく記録しない                                                                               |

- outcome は `.loop/` の state(`.loop/state-*.json`)、run-log、ledger に永続化されている。現在の dogfood の state にも `merged`・`pr-created` が残っている。state のターゲットの outcome は、そのターゲットが次に実行されるまで書き換わらないので、期限で消えるとは限らない。
- そのため、読む側は旧い値を新しい値に読み替える。読み替えは移行期間だけのものではなく、残す。platform 側は `lib/loop/` の1つの関数で読み替える。配布 skill のスクリプトは `lib/loop/` を読めない(skill は platform と別に配布される)ので、各スクリプトに同じ対応表を持たせる。

### 9. 調査中に見つかった既存の不具合(ci-sweeper の ledger)

- ci-sweeper の caller は、`CI_SWEEPER_LEDGER_FILE` を `.loop/state-ci-sweeper-run-ledger.json` に設定している(`on-loop-ci-sweeper.yaml:121`)。この値は `detect_domain_env_json` の一部で、detect ジョブにしか届かない(第4節)。
- finalize で動く `update_run_ledger.sh` は、既定値 `ci-sweeper-run-ledger.json`(リポジトリ直下)に書く(`update_run_ledger.sh:47`)。
- `additional_commit_paths` は `.loop/state-ci-sweeper-run-ledger.json` なので、書いたファイルは commit されない。detect は `.loop/` 側を読むので、ledger が更新されない。
- 静的に読んだ範囲での結論で、実行時には確認していない。状況証拠として、`.loop/state-ci-sweeper-run-ledger.json` はリポジトリに存在しない。
- 対応: `update_run_ledger.sh` の既定値を `.loop/state-ci-sweeper-run-ledger.json` にする(test-gap と同じ形)。source は `.apm/packages/repo-maintenance/.apm/skills/ci-sweeper/scripts/update_run_ledger.sh` である。他の変更とは独立した不具合修正なので、最初に別 PR で直す。

## 移行

### pin とリリース

dogfood の `on-loop-*.yaml` は、ローカルの `./.github/workflows/ci-loop-caller*.yaml` を呼ぶ。一方、`ci-loop-caller*.yaml` は `loop-detect`・`loop-entity-detect`・`ci-loop-agent.yaml` を、`ci-loop-agent.yaml` は `loop-execute`・`loop-finalize`・`loop-notify-pr`・`loop-agent-once` を、SHA で pin している(`ci-loop-caller.yaml:343`、`:483`、`ci-loop-caller-entity.yaml:303`、`:336`、`ci-loop-agent.yaml:312`、`:481`、`:571`、`:710`)。

`scripts/self/ci/pin_config_actions.sh` は、変更のコミットの上に、すべての pin を HEAD の SHA へ上げるコミットを積み、タグを付けて、変更と pin を1回の push で送る(`pin_config_actions.sh:325-392`)。push の時点で、caller と、pin された action・`ci-loop-agent.yaml` が同じ版にそろう。そのため、caller と action を1つのリリースで同時に変えてよい。旧い入力名と新しい入力名を両方受け付ける互換の処理は作らない。

手順:

1. ci-sweeper の ledger の不具合(第9節)を、先に別のリリースで直す。他の変更と独立しており、早く直すほど ledger の欠落が減るためである。
2. 本 spec の残りの変更(第1〜8節)を、作業ブランチで進める。PR は話題ごとに分けてよいが、main に入れて push するのは、すべてがそろってからにする。
3. 配布 skill を変えたら、`apm install`(`scripts/self/apm/sync_apm_artifacts.sh`)で同期先を更新し、同じ変更に含める。
4. `pin_config_actions.sh` で、変更と pin を1回で push する。

- push までの間、ローカルの caller と pin された古い action は食い違うが、main に入っていないので、dogfood は古い組み合わせのまま動く。
- 例外は、`.loop/` に永続化されたデータである。push の前に書かれた outcome の旧い値は、push の後も state・run-log・ledger に残る。第8節の読み替えは、このために残す。

### Phase P(別 spec)

`post_review.sh` を、投稿内容の生成(トークン不要)と投稿(プラットフォーム)に分割し、`delivery: pr_review` を実装する。pr-review が `pr_review` に移る。

## 検証

- 導出と検証の関数のゴールデンテスト: 旧い入力の全組み合わせ(`delivery`(`open_pr` / `none`)× `git_landing_integration` × `git_landing_pull_request` × `level` × ターゲット種別)について、新しい `delivery` に写し、次を bats で確認する。写し方は、旧い実装が各ターゲットに付ける `target_json.finalize` で決める。`open_pr` は `pr_create`、`push_head` は `pr_push`、`none` は `none` に写す。1回の実行の全ターゲットが同じ値に写るときだけ、その値を新しい `delivery` とする(例: 旧い `open_pr` + `push_head` でも、ターゲットが integration だけなら `pr_create`)。写る値が混ざる組み合わせと `push` は、写せないものとして扱う。
  - 旧い `target_json.finalize`(`resolve_git_finalize_strategies` と `entity_target.sh:175`)と、`loop-finalize` が新しい `delivery` で選ぶ分岐が一致すること。
  - 旧い `auto_merge`(caller の式を bash に書き写した関数)と、新しい `pr_auto_merge` が一致すること。
  - 旧い入力でターゲットが混在する組み合わせと、`git_landing_integration: push` は、新しい値に写せず、検証で失敗すること。
  - 旧い実装は、テストの中に期待値の表として固定してから削除する。GitHub の式は bats で実行できないため、書き写しが必要になる。書き写しは、現在の `loop-caller-parity.bats:33-42` が式の文字列を確かめていることで、元の式と対応づける。
- `finalize_enabled` の廃止: 検証を通る全組み合わせで、旧式が L2/L3 で true になることを、上記と同じテストで確認する。
- ターゲットの検証: 第1節の表の「使えるターゲット」の全セルについて、許可と拒否の両方を確認する。
- `loop-caller-parity.bats` の、旧い配線そのものを assert しているテスト(`:33-42` の `auto_merge` の式、`:44-` の `finalize_enabled` の式、`:127-128` の `loop-finalize` ステップの `if`)は、新しい不変条件に置き換える: caller が `auto_merge` の式と `finalize_enabled` を持たず、`needs.detect.outputs.pr_auto_merge` をそのまま渡すこと、`finalize-l2` が `loop-finalize` を条件なしで実行すること。仕様の変更に伴うテストの更新であり、検証を弱めるものではない。
- 第6節の検証の表: 表の全セルについて、許可と拒否の両方を `loop-write-contract.bats` で確認する。
- 旧い入力名が残っていないこと: 改名表の左列、削除する入力、旧い値、旧いプロンプトのキーを grep し、`.loop/` のデータと第8節の読み替え以外に残っていないことを確認する。
- outcome: 読み替えの関数と、各 ledger スクリプトの対応表が、旧い値と新しい値の両方を正しく扱うことを確認する。`write_state.sh:163` の条件が、`pr_push` の着地で成立することを確認する。
- リリースの前に、作業ブランチで dogfood の loop を `workflow_dispatch` で1回ずつ動かして、成功することを確認する。作業ブランチの caller は、ローカルの action を一時的に参照する(`.github/workflows/CLAUDE.md` の Pins が dogfood に許す範囲)か、`pin_config_actions.sh --no-push` で作った pin を使う。どちらにするかは、ビルダーが決める。リリース後にも、run-log で1回ずつ成功を確認する。
- zizmor / actionlint / ghalint が通ること(Stop フックで検証)。

## 影響を受ける箇所

grep で確認した範囲である。各 PR で、同じ grep を実行して漏れがないことを確かめる。旧い名前(改名表の左列、削除する入力、旧い値、旧いプロンプトのキー)を grep の対象にする。

**workflow:** `.github/workflows/{ci-loop-caller,ci-loop-caller-entity,ci-loop-agent}.yaml`、全 `on-loop-*.yaml`(10本。`on-loop-github-pr-revise.yaml:21-25` の workflow_dispatch の入力 `git_landing_pull_request` を `delivery` の選択に置き換えること、同じファイルの checker の指示文 `:94` とコメント `:3`、`:43`、`on-loop-github-pr-review.yaml:10` のコメントを含む)、`on-loop-state-promote.yaml`(`:59` の `state_push_branch`)、`.github/workflows/CLAUDE.md`(「`open_pr` untouched」、`push` / `push_head` の規則)。

**action:**

- `lib/loop/`: 導出関数(新設)、outcome の読み替え関数(新設)、`validate_loop_write_contract.sh`、`build_constraints.sh`、`loop_meta.sh`、`entity_meta.sh`
- `loop-detect/{action.yml,lib/_init.sh,lib/branches.sh,lib/detect.sh,lib/matrix.sh,lib/prs.sh}`
- `loop-entity-detect/{action.yml,lib/detect.sh,lib/entity_target.sh}`
- `loop-execute/{action.yml,lib/paths.sh,lib/verifier.sh,lib/agent_output_format_criteria.md}`(改名する入力 `no_changes_verdict`・`allowlist`・`denylist`・`engine`・`cli_version`・`commit_message`・`infer_files_pattern`・`agent_allowed_tools` と対応する環境変数、削除する `detect_result_json`、checker の判定基準)
- `loop-agent-once/action.yml`(`agent_allowed_tools`、`cli_version`、`engine`。`ci-loop-agent.yaml:315-319`)、`loop-worktree-setup/action.yml`(`branch_prefix`。`ci-loop-agent.yaml:476`)
- `loop-finalize/{action.yml,lib/create_pr.sh,lib/determine_outcome.sh,lib/should_push_target.sh,lib/should_delete_rejected_branch.sh,lib/write_state.sh,lib/prune_targets.sh,lib/push_target.sh}`
- `loop-notify-pr/{action.yml,lib/notify.sh}`、`loop-run-log/action.yml`(`base_branch` の改名、outcome の説明)、`loop-state-promote/{action.yml,lib/run.sh}`

**配布 skill(`.apm/packages/` が source。同期先は手で直さない):**

- プロンプトのキー(`may_edit`、`write_target`、`report_file`)を読む skill: `github/` の `github-issue-autofix`、`github-issue-triage`、`github-pr-review`、`github-pr-revise`、`repo-maintenance/` の `changelog`、`ci-sweeper`、`docs-updater`、`refactor`、`tech-debt`、`test-gap`。各 skill の `SKILL.md`、`references/`、`assets/`、`evals/`(`may-edit-false.yaml` などのファイル名を含む)
- `open_pr` を含む記述: `github-pr-revise/{SKILL.md,references/common-checklist.md}`、`github-issue-autofix/{scripts/detect_autofix.sh,evals/tasks/skip-open-pr.yaml}`(後の2つは、`open_pr` が「開いている PR」の意味かを読み分ける)
- outcome を読む・書くスクリプト: `ci-sweeper/scripts/{update_run_ledger,detect_ci_failures}.sh`、`test-gap/scripts/update_test_gap_ledger.sh`、`test-gap/references/category-input-schema.md`
- detect の JSON の `.report_file` を出すスクリプト: `tech-debt/scripts/detect_tech_debt.sh`(`:215`)ほか、grep で見つかるもの

**bats:**

- `test/bats/github-actions/` の `loop-caller-parity`、`loop-detect-delivery`、`loop-detect-enrich`、`loop-detect-matrix`、`loop-entity-detect`、`loop-write-contract`、`loop-write-state`、`loop-build-constraints`、`loop-prune-targets`
- `test/bats/.github/actions/` の `loop-detect/lib/{branches,detect,pending,prs,guards}.bats`、`loop-entity-detect/lib/{entity_target,detect_dispatch_hook}.bats`、`loop-finalize/lib/{determine_outcome,should_delete_rejected_branch,should_push_target,push_target,create_pr_body}.bats`、`loop-notify-pr/lib/notify.bats`、`loop-run-log/lib/{append,run}.bats`、`lib/loop/{entity_meta,loop_meta,trigger_thread}.bats`、`loop-state-promote/` の bats、`loop-execute/lib/{paths,common,verifier}.bats`
- `test/bats/.apm/packages/repo-maintenance/{ci-sweeper,test-gap}/`

**docs:**

- `docs/reference/{specification,loop-engineering-checklist,loop-notify-pr-specification}.md`
- `docs/explanation/loop-engineering/` の `common-loop-triage-format.md`、`loop-caller-reusable-design.md`(`:44`、`:392` を含む)、`loop-caller-workflows-design.md`(`:56`、`:70`、`:83`、`:88`、`:184`、`:194`、`:226` を含む)、`loop-engineering-design.md`(`:251` を含む)、`multi-branch-loops-design.md`(`:44` を含む)、`documentation-maintenance.md`、`loop-capable-skills.md`、`loop-pr-body-skill-contract.md`、`workflows/` の各 design と `loop-caller-inputs-reference.md`
- `docs/explanation/apm-package-design.md`
- `.apm/CLAUDE.md`(`may_edit` の行)

## この設計者(私)が決めたこと

次は、ユーザーとの対話で決めたことではなく、設計者の判断である。

- `ci-loop-agent.yaml` と composite action を直接呼ぶ利用者との互換性は、保証しない(非目標)。
- PR の種別は `delivery` の値で表し、`target_json.finalize` と `git_landing_*` を削除する。1回の実行の配信の種別は1つにする。以前の版にあった `finalize_plan` と `publish` は作らない。`publish` は `delivery` の部分集合に別の名前を付けただけで、`loop-finalize` は Phase P で `delivery` を直接読めばよい。
- L2/L3 で空の allowlist を拒否し、無制限は `**` で明示させる。
- `TARGET_JSON` が空のときの `open_pr` へのフォールバックを削除する。
- 改名表の新しい名前(第7-1節)。とくに、`no_changes` を `unchanged` にしたこと、`dispatch_hook_script` と `domain_persistence_script` を `detect_hook_script` と `finalize_hook_script` の対にしたこと、`write_target` と `may_edit` を `agent_edit_target` と `agent_edit_allowed` にしたこと。
- outcome の旧い値の読み替えは、期限を設けずに残す。

## ビルダーに任せること

- 導出関数と読み替え関数の名前と、`lib/loop/` 内のファイル名。
- ターゲットの検証を、`loop-detect` のどの段階(絞り込みの後、matrix を組み立てる前)で行うか。
- `validate_loop_write_contract.sh` の新しい表の、コード上の書き方。
- 話題ごとの PR の分け方。
- リリース前の dogfood の確認方法(ローカルの action を参照するか、`--no-push` の pin を使うか)。

## 未決(設計者の推測・要確認)

- **composite action の入力の扱い。** GitHub は、composite action の `required: true` を強制せず、宣言のない入力は警告だけで無視する、と理解している。リポジトリ内では確かめていない。本 spec は、この挙動に依存しない(必須の確認はスクリプトで行う)。
- 第9節の ledger の不具合は、静的な読みによる結論で、実行時には確認していない。最初の PR で、finalize の実行後に `.loop/state-ci-sweeper-run-ledger.json` が commit されることを確かめる。
- 外部の利用者が、`git_landing_integration: push` や、1回の実行での `open_pr` と `push_head` の混在を使っているかは分からない。使っていれば、本 spec のリリースを取り込んだ時点で失敗する(破壊的変更として許容する)。
