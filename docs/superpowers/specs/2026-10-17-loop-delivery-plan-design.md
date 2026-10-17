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

## 背景と課題

loop の「結果をどう届けるか」は、本来1つの判断である。ところが現状は、同じ判断が複数の変数の組み合わせで、複数の場所に書かれている。

| #   | 箇所                                                                                       | 現在の判断                                                                                                                                                                                                                                      | 問題                                                                                                                                                                                                                |
| --- | ------------------------------------------------------------------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1   | `ci-loop-caller.yaml:510` / `ci-loop-caller-entity.yaml:363` の `finalize_enabled`         | `delivery == open_pr \|\| (delivery == none && level != L1)`                                                                                                                                                                                    | 同じ式が2か所にある。値が情報を運んでいない。L1 では `finalize-l2` ジョブ自体が動かず(`ci-loop-agent.yaml:513-517`)、L2/L3 で検証を通る `delivery` は `open_pr` と `none` だけなので、式は常に true になる          |
| 2   | `auto_merge`(caller の式、`loop-finalize` の `Enable Auto-Merge`、`loop-notify-pr` の文面) | caller が `delivery == open_pr && level == L3 && target.finalize == open_pr` を計算し、下流が strategy と level を再び確かめる                                                                                                                  | 同じ判断が3か所にある。caller の式の `delivery == open_pr` は冗長である(`target.finalize == open_pr` が `delivery == open_pr` を含意する。`detect.sh:907-936`、`entity_target.sh:175`)                              |
| 3   | `entity_target.sh:175` の `finalize`                                                       | `delivery == open_pr ? open_pr : none`                                                                                                                                                                                                          | `loop-detect` の `resolve_git_finalize_strategies`(`detect.sh:907`)と、同じ導出を別に実装している                                                                                                                   |
| 4   | `validate_loop_write_contract.sh`                                                          | `may_edit × write_target × delivery × level`                                                                                                                                                                                                    | 4変数の許可表。`may_edit` は全 caller で `level != L1` と一致し、検証の大半は2つの食い違いを拒否するためにある                                                                                                      |
| 5   | `loop-finalize` の各ステップ                                                               | push / ブランチ削除 / state の書き方 / outcome が、それぞれ `verdict`・`has_changes`・`strategy` を個別に組み合わせて判断                                                                                                                       | `strategy == none` の特別扱いが、複数のステップに散在する                                                                                                                                                           |
| 6   | `delivery` の enum                                                                         | `log \| issue \| notion` は検証を通るが実装がなく、`none` と同じ挙動になる                                                                                                                                                                      | 宣言と挙動が食い違い、黙って何もしない                                                                                                                                                                              |
| 7   | 入力の既定値                                                                               | 同じ名前の入力が、層や reusable ごとに異なる既定値を持つ(第7節)                                                                                                                                                                                 | 同じ省略が、どの reusable や action を通るかで別の意味になる。判断を表す入力にも、宣言のない既定値がある(`loop-detect/action.yml:31-44`、`detect.sh:500`、`:535`、`:957`、`loop-entity-detect/lib/detect.sh:46-47`) |
| 8   | `delivery: open_pr` の意味                                                                 | 名前は「PR を開く」だが、pr-revise では `git_landing_pull_request: push_head` と組み合わさり、PR を作らずに既存 PR の head へ push する。`git_landing_integration: push` では、PR に関わらずブランチへ直接 push する                            | 値の名前が、実際の配信先を表していない                                                                                                                                                                              |
| 9   | outcome の値                                                                               | push で着地しても `pr-created` を返す(`determine_outcome.sh:56-59`)。値はハイフン区切りで、`merged` のように対象がない値もある                                                                                                                  | PR を作っていないのに「PR 作成」になる。書き方が、他の値(snake_case)と食い違う                                                                                                                                      |
| 10  | 入力名                                                                                     | 動詞が先頭の名前(`ack_trigger_comment`、`infer_files_pattern`、`write_target`、`may_edit`)、対象がない名前(`labels`、`allowlist`、`engine`)、層をまたいで名前が変わる値(caller の `branch_match_mode` が action では `loop_branch_match`)がある | 名前から、何の設定かが分からない。名前でソートしても、同じ対象の設定が並ばない                                                                                                                                      |

この構造は、実際に配線の不具合を生んだ。github-pr-review の導入(#989)では、(a) `delivery: none` の L2 で finalize が動かない(`finalize_enabled` の式)、(b) `target_json.from.branch` が出ない、(c) `strategy none` で agent ブランチが main にマージされ得る、という問題を、個別の条件追加で直した。同種の問題は、loop が増えるたびに再発する。

もう1つの課題は `domain_persistence_script` である。これは finalize 内で任意のスクリプトを実行し、`GH_TOKEN` を渡す。スクリプトの中身によって必要な権限が変わるが、権限は caller の `permissions:` で固定されるため、スクリプトが何をできるかが暗黙の取り決めになっている。現状の2つの利用例(ci-sweeper、test-gap の ledger)は、リポジトリ内の JSON を jq で更新するだけで、`gh` も `curl` も呼ばない(確認済み)。一方 pr-review の `post_review.sh` は、GitHub にレビューを投稿する。

## 目標

- caller が宣言する配信は、**`delivery` の1つだけ**にする。
- finalize の判断(ターゲットごとの `finalize` と `auto_merge`)は、`.github/actions/lib/loop/` の**1つの関数**で導出する。`loop-detect` と `loop-entity-detect` は、その関数を呼んで結果を `target_json` に載せるだけにする。caller、`ci-loop-agent.yaml`、`loop-finalize`、`loop-notify-pr` に、`delivery` や `level` を組み合わせる式を残さない。
- `delivery` の値は、すべて実装がある値にする。未実装の値は検証で失敗させる(fail closed)。
- 判断を表す入力(`delivery`、`level`)には、どの層にも既定値を置かない。`level` に従属する入力は、`level` ごとに検証する(第6節)。
- 効かない値は受け付けない。L1 で、L2/L3 だけに効く入力を指定したら、検証で拒否する。
- 値、入力名、プロンプトのキー、環境変数の名前を、第1節の規則にそろえる。同じ値は、どの層でも同じ名前で運ぶ。

## 非目標

- Linear / JIRA / Notion など外部システムへの配信。秘密情報の受け渡しを設計しない限り権限が曖昧になるため、将来の追加枠として記すだけにする。
- 1回の実行での複合配信(`pr` と `issue` の同時実行)。既存 spec の方針を踏襲し、loop を分ける。
- `post_review.sh` の分割(第10節の Phase P として別 spec)。
- `level` の意味(L1/L2/L3 のエージェント権限)の変更。
- caller の `permissions:` を `delivery` ごとに絞ること。理由は第5節に書く。
- `ci-loop-agent.yaml` と各 composite action を、caller を経由せずに直接呼ぶ利用者との互換性。docs が示す経路は `on-loop-* → ci-loop-caller* → ci-loop-agent` だけである(`loop-caller-reusable-design.md:356`)。

## アンチゴール(これが起きたら失敗)

- 導出の場所が増える(別の action や caller に、新しい `delivery` の判断式が入る)。
- 移行の途中で、dogfood の loop の挙動が変わる(PR が開かない、開きすぎる、auto-merge の条件が変わる、state やブランチの扱いが変わる、loop が検証で止まる)。第8節の outcome の改名による値の変化だけは、意図した変更とする。
- 新しい設定値が増える(既存の入力を置き換えずに、並行して別の入力が生まれる)。

## 設計

### 1. 命名規則と `delivery` の値

**命名規則(MUST):**

- snake_case で書く。
- **対象(domain)を先、属性や動作を後**にする(`pr_review`、`issue_comment`、`agent_edit_target`)。名前でソートしたとき、同じ対象のものが隣に並ぶようにするためである。
- 動詞を先頭にした名前は作らない(`open_pr`、`ack_trigger_comment`、`may_edit` は改名する)。
- 対象だけの値は、その対象を作ることを表す(`delivery` の `pr` と `issue`)。結果を表す値は、対象と過去分詞にする(`pr_created`、`pr_merged`)。
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

**`delivery` の値:** `delivery` は、「エージェントの出力を、どこへ届けるか」を表す。閉じた集合とする。

| 値              | 意味                                                                                                                              | 状態                                             |
| --------------- | --------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------ |
| `pr`            | 変更を PR に届ける。新しい PR を作るか、既存 PR の head へ push するかは、ターゲットごとの `finalize`(第2節)が決める              | 実装済み(現在の名前は `open_pr`。改名する)       |
| `none`          | プラットフォームは何も配信しない。エージェントが自分で完結する(L1 triage)か、レポートファイルを finalize の hook スクリプトが扱う | 実装済み                                         |
| `issue`         | レポートから Issue を新規作成する                                                                                                 | 未実装。実装されるまで検証で拒否                 |
| `issue_comment` | 既存の Issue にコメントを投稿する(対象は `target_json` の Issue 番号)                                                             | 未実装。実装されるまで検証で拒否                 |
| `pr_review`     | 検証済みのレポートを、既存 PR へのレビュー(COMMENT 形式、インラインコメント付き)として投稿する                                    | **Phase P まで未実装**。実装されるまで検証で拒否 |

- `log` と `notion` は enum から削除する。実装がなく、必要になったときに、複数の loop が使うと分かった時点で追加する。
- `issue` は「作る」、`issue_comment` は「既存に書く」で、1つの値に分岐を隠さない。
- `none` は「何もしない」の意味に限定する。pr-review が `none` で動いている現状は、Phase P で `pr_review` に移るまでの暫定である。
- `issue` / `issue_comment` / `pr_review` は finalize が配信するので、L2 以上でしか使えない(第6節)。
- **`delivery: pr` で、PR に関わらない着地をなくす。** 現在の `git_landing_integration: push`(integration ブランチへ直接 push する)は、PR を経由しない。dogfood の caller は使っていない。ユーザーの方針(「いらないなら削除」)に従い、削除する。これで `delivery: pr` は、常に PR に届く(新しい PR か、既存 PR の head)。

### 2. 導出は `lib/loop/` の1つの関数で行う

`.github/actions/lib/loop/` に、ターゲットごとの finalize の判断を導出する関数を1つ置く。`.github/workflows/CLAUDE.md` の Composition の規則により、2つの composite が共有するロジックは `lib/loop/` に置く必要がある(別の composite の `lib/` は共有契約にできない)。

| 出力(`target_json` のフィールド) | 値                           | 導出                                                                                                                                                                                          |
| -------------------------------- | ---------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `finalize`                       | `pr \| pr_head_push \| none` | `delivery == none` なら `none`。`delivery == pr` なら、integration と entity のターゲットは `pr`、pull_request のターゲットは `finalize_pull_request`(`pr` か `pr_head_push`、既定値なし)の値 |
| `auto_merge`                     | bool                         | `level == L3` かつ `finalize == pr`                                                                                                                                                           |

- `loop-detect`(`target_json` を組み立てる `detect.sh:302-372` の各関数)と `loop-entity-detect`(`entity_target.sh`)は、この関数を呼ぶ。`detect.sh` の `resolve_git_finalize_strategies` と、`entity_target.sh:175` の独自の導出は削除する。
- `finalize` の値の意味: `pr` は新規ブランチを作って PR を作る。`pr_head_push` は、既存 PR の head ブランチへ、最新の head を merge して push する(pr-revise。現在の `push_head`)。`none` は着地させない。`pr` と `pr_head_push` は、安全条件(merge、fail closed、`fetch-depth: 0`)が異なるため、区別を残す。現在の `push` は、第1節のとおり削除する。
- `finalize_pull_request` は、現在の `git_landing_pull_request` の改名である。`delivery: pr` で、pull_request のターゲットを持つ loop(`detect_pr_enabled: true`)では必須にする。既定値の `open_pr` は置かない(背景 #7)。
- `auto_merge` は、`finalize` と同じくターゲット単位の値である。1回の実行に `finalize` の異なるターゲットが混在しうる(integration は `pr`、pull_request は `pr_head_push`)ため、run 単位の値では表せない。

**旧式との一致(`auto_merge`):** 旧式は `delivery == open_pr && level == L3 && target.finalize == open_pr` である。`target.finalize == open_pr` は `delivery == open_pr` を含意するので、旧式は `level == L3 && target.finalize == open_pr` と等しい。新式は、この式そのものである。

**下流の変更:**

- `loop-finalize` の `Enable Auto-Merge` は、`target_json.auto_merge` だけを見る。`loop-notify-pr` の L3 の文面(`notify.sh:208`)も、`target_json.auto_merge` を見る。
- `auto_merge` の入力は、`ci-loop-caller.yaml`、`ci-loop-caller-entity.yaml`、`ci-loop-agent.yaml`、`loop-finalize`、`loop-notify-pr` から削除する。

**`finalize_enabled` の廃止:** `finalize_enabled` は、`finalize-l2` ジョブ内の `loop-finalize` **ステップ**だけを止めるフラグである(`ci-loop-agent.yaml:3-4`、`:568`)。

- `finalize_enabled` を、caller と `ci-loop-agent.yaml` から削除する。`finalize-l2` では、`loop-finalize` ステップを常に実行する。
- 背景 #1 のとおり、検証を通る設定では、L2/L3 の旧 `finalize_enabled` は常に true である。dogfood の全 caller で、次のとおり挙動は変わらない。

| loop                                                         | `delivery` | `level`             | 旧: `loop-finalize` ステップ | 新: `loop-finalize` ステップ |
| ------------------------------------------------------------ | ---------- | ------------------- | ---------------------------- | ---------------------------- |
| changelog、autofix、pr-revise、tech-debt、refactor、test-gap | `open_pr`  | L2                  | 実行                         | 実行                         |
| docs-updater、ci-sweeper                                     | `open_pr`  | 指定なし(既定値 L2) | 実行                         | 実行                         |
| github-pr-review                                             | `none`     | L2                  | 実行                         | 実行                         |
| github-issue-triage                                          | `none`     | L1                  | `finalize-l2` が動かない     | `finalize-l2` が動かない     |

- 旧式で `loop-finalize` が止まる L2/L3 の組み合わせは、`delivery` が `log` / `issue` / `notion` のときだけで、これらは `may_edit: true` で検証が拒否する(`validate_loop_write_contract.sh:114-118`)。到達しない。

### 3. `loop-finalize` は `target_json` だけを見る

- push・ブランチ削除・state の書き方・outcome の判断は、`target_json.finalize` を入力にする。「`strategy == none` なら…」という特別扱いを、`finalize == none` の1つの規則にまとめる。
- `determine_outcome` は、`finalize == none` で APPROVE のとき `reported` を返す現在の挙動を保つ。
- `TARGET_JSON` が空のとき `open_pr` とみなす現在のフォールバック(`loop-finalize/action.yml:155`、`:160`)は削除し、失敗させる。黙って PR を作る既定値は、本 spec が取り除く「宣言のない判断」である。dogfood の2つの caller は、常に `target_json` を渡している。

### 4. finalize の hook スクリプトの契約

現在の `domain_persistence_script` を `finalize_hook_script` に改名する(第7節)。

- 位置づけ: 配信ではなく、finalize に差し込む**副次的な独自処理**(ledger、ログなど)。
- 許される範囲: リポジトリルート配下の相対パスのファイル更新のみ(現在の ledger スクリプトが、すでにこれを検証している)。外部システムへの書き込みはしない。
- 権限: 書き込みトークンを必要としない。ただし、Phase P までは `post_review.sh` が `GH_TOKEN` を使うため、`GH_TOKEN` の受け渡しは残す(過渡的な例外として明記する)。
- 実行条件: `finalize` に関係なく、`loop-finalize` が動くとき(L2/L3)に1回実行する。失敗の扱いは現在の挙動を変えない。
- 環境: スクリプトは、`detect_env_json`(現在の `detect_domain_env_json`)の値を受け取らない。この値は detect ジョブの `GITHUB_ENV` にだけ入り、finalize ジョブには届かない。スクリプトが書くファイルのパスは、スクリプトの既定値で決め、caller の `finalize_commit_paths` と一致させる。test-gap はすでに従っている(`update_test_gap_ledger.sh:17`)。ci-sweeper は反している(第9節)。
- `finalize_commit_paths`(現在の `additional_commit_paths`)は、スクリプトの出力のうち commit してよいパスの許可リストとして残す。`loop-finalize` は、スクリプトを先に実行し、後続の `Write State` が、列挙されたパスだけを commit に加える(`write_state.sh:114-150`)。

### 5. 権限は本 spec では変えない

caller の `permissions:` を `delivery` から導くことはしない。reusable の各ジョブが、`delivery` に関係なく固定の書き込み権限を要求しているためである(`ci-loop-caller.yaml` の execute ジョブ、`ci-loop-agent.yaml` の `agent-l2` と `finalize-l2`)。caller はこの権限を与えないとワークフローを起動できないので、「`delivery` に必要な権限を含むか」という静的テストは常に通り、何も検証しない。権限を `delivery` ごとに絞るには、reusable のジョブを `delivery` ごとに分ける構造の変更が必要で、本 spec の範囲を超える。

### 6. 入力の検証は `level` を主キーにする

`may_edit` を入力から外す(第7節)と、許容値を決めているのは `level` になる。`validate_loop_write_contract.sh` を、`level` を主キーにした表に書き直す。新しい入力名(第7節)で示す。

| `level` | `delivery`                                                                      | `agent_edit_target`     | `agent_edit_allowlist`                       | `agent_edit_denylist`     | `agent_unchanged_verdict`   |
| ------- | ------------------------------------------------------------------------------- | ----------------------- | -------------------------------------------- | ------------------------- | --------------------------- |
| L1      | `none`                                                                          | 指定は拒否              | 指定は拒否                                   | 指定は拒否                | 指定は拒否                  |
| L2 / L3 | `pr`、`none`(Phase P で `pr_review`、実装時に `issue` / `issue_comment` を追加) | `fix` か `report`(必須) | 必須(空は拒否)。制限しないときは `**` を書く | 任意(空は既定の denylist) | `APPROVE` か `REJECT`(必須) |

- L1 で `delivery: pr` を拒否するのは、現在の検証と同じである。L1 で `issue` / `log` / `notion` を通している現在の検証は、第1節の削除と fail closed により、`none` だけを通すようになる。
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

| 現在の名前                  | 新しい名前                   | 理由                                                              |
| --------------------------- | ---------------------------- | ----------------------------------------------------------------- |
| `ack_trigger_comment`       | `trigger_comment_ack`        | 動詞が先頭                                                        |
| `additional_commit_paths`   | `finalize_commit_paths`      | 対象がない。finalize の commit に加えるパス                       |
| `agent_allowed_tools`       | `agent_tool_allowlist`       | `agent_edit_allowlist` と同じ形にそろえる                         |
| `allowlist`                 | `agent_edit_allowlist`       | 対象がない。maker が編集してよいパス                              |
| `branch_match`              | `detect_branch_match`        | 対象がない。監視するブランチのパターン                            |
| `branch_match_mode`         | `detect_branch_match_mode`   | 対象がない                                                        |
| `branch_prefix`             | `agent_branch_prefix`        | 対象がない。agent の作業ブランチの接頭辞                          |
| `branch_state`              | `state_branch`               | 対象が後ろにある。第7-3節で、監視の意味を切り離す                 |
| `cli_version`               | `agent_cli_version`          | 対象がない                                                        |
| `commit_message`            | `agent_commit_message`       | 対象がない。agent の試行ごとの commit メッセージ                  |
| `denylist`                  | `agent_edit_denylist`        | 対象がない                                                        |
| `detect_domain_env_json`    | `detect_env_json`            | `domain` は情報を足していない                                     |
| `dispatch_hook_script`      | `detect_hook_script`         | detect の後に動く hook。`finalize_hook_script` と対にする         |
| `domain_persistence_script` | `finalize_hook_script`       | finalize に差し込む hook(第4節)                                   |
| `engine`                    | `agent_engine`               | 対象がない                                                        |
| `git_landing_pull_request`  | `finalize_pull_request`      | `target_json.finalize` と語をそろえる。値は `pr` / `pr_head_push` |
| `infer_files_pattern`       | `agent_checker_path_pattern` | 動詞が先頭。checker の出力からパスを拾う正規表現                  |
| `labels`                    | `pr_labels`                  | 対象がない。作る PR のラベル                                      |
| `max_targets_per_schedule`  | `detect_max_targets`         | 対象がない                                                        |
| `no_changes_verdict`        | `agent_unchanged_verdict`    | 対象がない。maker が差分を作らなかったときの判定                  |
| `outcome_override`          | `finalize_outcome_override`  | 対象がない                                                        |
| `pr_enabled`                | `detect_pr_enabled`          | `pr_` は作る PR を表す。これは監視の設定                          |
| `pr_exclude`                | `detect_pr_exclusions`       | 監視の設定。動詞を名詞にする                                      |
| `pr_include_bots`           | `detect_pr_bot_allowlist`    | 監視の設定。動詞が入っている                                      |
| `priority`                  | `detect_priority`            | 対象がない                                                        |
| `scoped_pr_number`          | `detect_pr_number`           | 監視の設定。形容詞が先頭                                          |
| `write_target`              | `agent_edit_target`          | 動詞が先頭。値は `fix` / `report`                                 |

**プロンプトのキー:** `build_constraints.sh` がプロンプトの `## Constraints` に出すキーも、同じ名前にする。skill は、このキーで分岐している。

| 現在のキー     | 新しいキー           |
| -------------- | -------------------- |
| `may_edit`     | `agent_edit_allowed` |
| `write_target` | `agent_edit_target`  |
| `report_file`  | `agent_report_file`  |

`agent_edit_allowed` は caller の入力ではなく、`level` から導出する(7-2)。「Allowed paths: …」の行の文言は変えない。

**action の入力と環境変数:** `loop-detect` の `loop_` 接頭辞の入力(`loop_branch_match`、`loop_integration_branches`、`loop_max_targets_per_schedule`、`loop_pr_enabled`、`loop_pr_exclude`、`loop_pr_include_bots`、`loop_priority`、`loop_scoped_pr_number`)は、caller の新しい名前と同じにする。現在は caller の `branch_match_mode` が `loop_branch_match` に、`branch_match` が `loop_integration_branches` に入り(`ci-loop-caller.yaml:359-360`)、同じ語が層ごとに別の値を指している。環境変数(`LOOP_BRANCH_MATCH` など)も、入力名を大文字にした名前にする。`ci-loop-agent.yaml` の `state_push_branch` は `state_branch` にする。

#### 7-2. 削除

| 入力                                                                | 理由                                                                                                                                                                                                                                                  | 代わり                                                                                                                                                           |
| ------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `may_edit`(2つの reusable、`loop-detect`、`loop-entity-detect`)     | 全10 caller で `level != L1` と一致する。検証が食い違いを拒否しているだけ                                                                                                                                                                             | `lib/loop/` で `level` から導出し、プロンプトの `agent_edit_allowed` に出す。非推奨のシム `emit_loop_constraints_from_level` も削除する                          |
| `finalize_enabled`、`auto_merge`                                    | 第2節                                                                                                                                                                                                                                                 | `target_json`                                                                                                                                                    |
| `git_landing_integration`                                           | 第1節(`push` の削除で、選べる値が `pr` だけになる)                                                                                                                                                                                                    | なし                                                                                                                                                             |
| `dispatch_hook_token`(reusable と `loop-entity-detect`)             | トークンを `with:` で渡す。`.github/workflows/CLAUDE.md` は、reusable workflow にトークンを `with:` で渡すことを禁じている。dogfood は使っていない                                                                                                    | dispatch hook は、常に detect のトークンを使う(`loop-entity-detect/lib/detect.sh:51`、`:238` の分岐もなくす)。別のトークンが必要になったら `secrets:` で宣言する |
| `ci-loop-agent.yaml` の `detect_result_json`                        | 2つの caller が、常に `"{}"` を渡している(`ci-loop-caller.yaml` と `ci-loop-caller-entity.yaml` の execute ジョブ)。値を運んでいない                                                                                                                  | なし(`loop-finalize` の同名の入力も削除する)                                                                                                                     |
| `ci-loop-agent.yaml` の `handoff_key`、`current_sha`、`base_branch` | どれも `target_json` から導ける(`target_json.key`、`target_json.from.ref`、pull_request なら `target_json.base.branch`、それ以外は `target_json.to.branch`)。`base_branch` は、2つの caller で式が異なる(entity の式は pull_request の分岐を持たない) | `ci-loop-agent.yaml` の中で `target_json` から取り出す。`matrix.sh:136` の `handoff_key` の複製もなくす                                                          |

#### 7-3. 1つの入力が持つ2つの意味を分ける(`branch_state`)

`branch_state` は、「`.loop/` の状態を保存するブランチ」と、「`branch_match` が空のときに監視するブランチ」の2つを兼ねている(`ci-loop-caller.yaml:349`、`branches.sh:93-106`、`detect.sh:1223`)。

- `state_branch` は、状態の保存先だけを表す。
- `detect_branch_match` は、branch caller で必須にする。空のときに `state_branch` を監視するフォールバックは削除する。
- 現在の8本の branch caller は、どれも `branch_match: main` と `branch_state: main` を両方渡しているので、値はそのまま移せる(挙動は変わらない)。entity caller は監視ブランチを持たないので、`state_branch` だけになる。

#### 7-4. 既定値の整理

- **判断を表す入力(`delivery`、`level`):** どの層にも既定値を置かない。2つの reusable では必須にする。`loop-detect` と `loop-entity-detect` の action とスクリプトにある既定値(`loop-detect/action.yml:31-44`、`detect.sh:500`、`:535`、`:957`、`loop-entity-detect/lib/detect.sh:46-47`)も削除し、空なら失敗させる。docs-updater と ci-sweeper には `level: L2` を足す(他の caller は明示済み)。
- **`level` に従属する入力(第6節の表の4つ):** 2つの reusable と2つの action で、`required: false`、既定値 `""` にそろえる。現在の既定値は、reusable ごとに異なる(`write_target` は branch で必須・entity で `report`、`allowlist` は branch で必須・entity で `""`、`no_changes_verdict` は branch で `REJECT`・entity で `APPROVE`)。許容値は第6節の表で検証する。triage からは、`write_target`・`allowlist`・`denylist`・`no_changes_verdict` の4行を削除する。autofix、pr-revise、pr-review の `allowlist: ""` は `"**"` にする(挙動は変わらない)。
- **配管の入力の明示された既定値:** caller が既定値と同じ値を書いている行は、削除する(挙動は変わらない)。対象は `environment: default`(10本)、`agent_checker_skill_name: loop-verifier`(10本)、`pr_body: ""`(6本)、`pr_enabled: false`(5本)、`max_targets_per_schedule: 3`(changelog、ci-sweeper、docs-updater)、`detect_domain_env_json: "{}"`(tech-debt、test-gap)、`pr_exclude: fork,draft,label:no-loop` と `pr_include_bots: ""`(ci-sweeper)。L2/L3 の caller の `denylist: ""`(6本)も、第6節の表で任意の入力なので、ここで削除する。判断を表す入力と、`level` に従属する必須の入力は、既定値と同じでも caller が書く。

**確認して、残すもの:**

- `agent_unchanged_verdict`: 「maker が差分を作らなかったときに、`APPROVE` と `REJECT` のどちらにするか」は、L2/L3 の loop ごとのドメイン判断で、`level` からは決まらない。L2/L3 で必須にする。
- `agent_edit_target` は、`delivery` から導出しない。tech-debt は `delivery: pr` で `write_target: report` であり、`delivery` と1対1にならない。
- `finalize_commit_paths` と `finalize_hook_script` は、同じファイルのパスを両方に書くが、冗長ではない(第4節)。
- `state_file` / `run_log_file` / `budget_file` / `pr_labels` / `agent_branch_prefix` / `agent_commit_message` / `detect_priority`: dogfood の caller は、どれも上書きしていない。配布先が調整するための入力なので残す。

### 8. outcome の値

| 現在の値     | 新しい値         | 書く場所                                                            | 変更の理由                                                                  |
| ------------ | ---------------- | ------------------------------------------------------------------- | --------------------------------------------------------------------------- |
| `pr-created` | `pr_created`     | `determine_outcome.sh:59`、ledger スクリプト                        | snake_case。`finalize == pr` のときだけ返す                                 |
| (なし)       | `pr_head_pushed` | `determine_outcome.sh`                                              | `finalize == pr_head_push` で着地したとき。現在は `pr-created` を返している |
| `merged`     | `pr_merged`      | `loop-state-promote/lib/run.sh:407`                                 | 対象がない                                                                  |
| `pr-closed`  | `pr_closed`      | `loop-state-promote/lib/run.sh:410`                                 | snake_case                                                                  |
| `no-changes` | `unchanged`      | `determine_outcome.sh:53`、`ci-loop-agent.yaml:365`、`:381`、`:654` | snake_case にすると対象のない2語になるため、1語の状態にする                 |
| `no-action`  | `unchanged`      | ci-sweeper の ledger(`update_run_ledger.sh:194`)                    | `no-changes` を ledger で言い換えているだけ。同じ意味に1つの名前            |

`rejected`、`reported`、`skipped`、`error`、`watch`(ci-sweeper の override)、`escalated`(ledger)は変えない。

**読む側の変更**(コードの全件。`pr-created` などを含むファイルを grep した結果):

| ファイル                                                                      | 現在の読み方                                                          | 新しい読み方                                                                                                                                                                                             |
| ----------------------------------------------------------------------------- | --------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `loop-finalize/lib/write_state.sh:163`                                        | advance モードで `pr-created` なら、state PR へのフォールバックを拒否 | advance モードで `pr_head_pushed` なら拒否。advance モードは `pr_head_push` の着地だけなので、現在と同じ条件になる。字面どおり `pr_created` に置き換えると条件が成立しなくなるので、置き換えてはならない |
| `loop-finalize/lib/write_state.sh:312`、`prune_targets.sh:87`                 | `pr-closed`                                                           | `pr_closed`                                                                                                                                                                                              |
| `loop-notify-pr/lib/notify.sh:207`                                            | `pr-created` で、修正 PR の URL があるとき次の手順を出す              | `pr_created`。`pr_head_pushed` は修正 PR を持たず、現在も URL が空で文面が出ないので、挙動は変わらない                                                                                                   |
| `lib/loop/loop_meta.sh:147`                                                   | `no-changes` / `skipped` / `watch`                                    | `unchanged` / `skipped` / `watch`                                                                                                                                                                        |
| `ci-loop-agent.yaml:654`                                                      | `no-changes` を書く(フォールバック)                                   | `unchanged` を書く                                                                                                                                                                                       |
| `loop-run-log/action.yml:44`                                                  | 説明文に値を列挙                                                      | 新しい値に直す                                                                                                                                                                                           |
| ci-sweeper の `update_run_ledger.sh:189-195`、`detect_ci_failures.sh:535-538` | `pr-created` / `no-changes` → `no-action`                             | `pr_created` と `pr_head_pushed` を「着地した」として同じに扱う。`unchanged` はそのまま記録する                                                                                                          |
| test-gap の `update_test_gap_ledger.sh:141-147`                               | `pr-created`、`no-action` / `no-changes`                              | ci-sweeper と同じ                                                                                                                                                                                        |

- outcome は `.loop/` の state(`.loop/state-*.json`)、run-log、ledger に永続化されている。現在の dogfood の state にも `merged`・`pr-created` が残っている。state のターゲットの outcome は、そのターゲットが次に実行されるまで書き換わらないので、期限で消えるとは限らない。
- そのため、読む側は旧い値を新しい値に読み替える。読み替えは移行期間だけのものではなく、残す。platform 側は `lib/loop/` の1つの関数で読み替える。配布 skill のスクリプトは `lib/loop/` を読めない(skill は platform と別に配布される)ので、各スクリプトに同じ対応表を持たせる。

### 9. 調査中に見つかった既存の不具合(ci-sweeper の ledger)

- ci-sweeper の caller は、`CI_SWEEPER_LEDGER_FILE` を `.loop/state-ci-sweeper-run-ledger.json` に設定している(`on-loop-ci-sweeper.yaml:121`)。この値は `detect_domain_env_json` の一部で、detect ジョブにしか届かない(第4節)。
- finalize で動く `update_run_ledger.sh` は、既定値 `ci-sweeper-run-ledger.json`(リポジトリ直下)に書く(`update_run_ledger.sh:47`)。
- `additional_commit_paths` は `.loop/state-ci-sweeper-run-ledger.json` なので、書いたファイルは commit されない。detect は `.loop/` 側を読むので、ledger が更新されない。
- 静的に読んだ範囲での結論で、実行時には確認していない。状況証拠として、`.loop/state-ci-sweeper-run-ledger.json` はリポジトリに存在しない。
- 対応: `update_run_ledger.sh` の既定値を `.loop/state-ci-sweeper-run-ledger.json` にする(test-gap と同じ形)。source は `.apm/packages/repo-maintenance/.apm/skills/ci-sweeper/scripts/update_run_ledger.sh` である。他の変更とは独立した不具合修正なので、最初に別 PR で直す。

## 移行

### pin による制約

dogfood の `on-loop-*.yaml` は、ローカルの `./.github/workflows/ci-loop-caller*.yaml` を呼ぶ。一方、`ci-loop-caller*.yaml` は `loop-detect`・`loop-entity-detect`・`ci-loop-agent.yaml` を、`ci-loop-agent.yaml` は `loop-execute`・`loop-finalize`・`loop-notify-pr`・`loop-agent-once` を、リリースの SHA で pin している(`ci-loop-caller.yaml:343`、`:483`、`ci-loop-caller-entity.yaml:303`、`:336`、`ci-loop-agent.yaml:312`、`:481`、`:571`、`:710`)。pin は、リリースのときに `scripts/self/ci/pin_config_actions.sh` が、すべて同じリリースの SHA へまとめて上げる。

そのため、caller(`ci-loop-caller*.yaml` と `on-loop-*.yaml`)の変更はマージした時点で効くが、action と `ci-loop-agent.yaml` の変更は、次のリリースまで効かない。両方を1つの PR で変えると、マージからリリースまでの間、新しい caller が古い action を呼び、dogfood が壊れる(例: caller から `finalize_enabled` を消すと、古い `ci-loop-agent.yaml` では既定値 false になり、`loop-finalize` が止まる)。

### 3段階の手順

すべての変更を、次の3段階で進める。各段階は、話題ごとの複数の PR に分けてよい。段階の境目では、必ずリリースする。

| 段階    | 変える層                                 | 内容                                                                                                                                                                                                                                                                    | 段階の終わり                                  |
| ------- | ---------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------- |
| E(拡張) | action、`ci-loop-agent.yaml`、配布 skill | 新しい入力名・値・プロンプトのキー・outcome を受け付けるようにする。旧い入力名と値も、引き続き受け付ける。削除する入力は、宣言を残して無視する(`finalize_enabled` は無視して `loop-finalize` を常に実行し、`auto_merge` は `target_json.auto_merge` があればそれを使う) | リリースし、`apm install` で skill を同期する |
| M(移行) | `ci-loop-caller*.yaml`、`on-loop-*.yaml` | 新しい入力名と値だけを使う。削除する入力を渡すのをやめる                                                                                                                                                                                                                | リリース                                      |
| C(縮小) | action、`ci-loop-agent.yaml`、配布 skill | 旧い入力名・値・キーを受け付ける処理と、削除した入力の宣言を消す。outcome を書く側を新しい値に切り替える。outcome の旧い値の読み替え(第8節)は残す                                                                                                                       | リリース                                      |

- 段階 E のマージからリリースまでは、caller が変わっていないので、古い組み合わせのまま動く。リリース後は、古い caller が新しい action を呼ぶが、旧い入力を受け付けるので動く。
- 段階 M のマージ後は、新しい caller が段階 E の action を呼ぶ。新しい入力を受け付けるので動く。
- 段階 C のマージからリリースまでは、caller が段階 E の action を pin したままである。リリース後は、caller も action も新しい名前だけになる。
- outcome を書く側の切り替えを段階 C に置くのは、読む側(配布 skill の ledger スクリプトを含む)が新しい値を読めるようになった後にするためである。
- 段階 E で旧い値と新しい値の両方を受け付けるとき、両方が指定されたら、値が一致しない限り失敗させる。

### 話題と段階

| 話題                                                    | E                                                                                                             | M                                                              | C                                                                             |
| ------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------- | ----------------------------------------------------------------------------- |
| 0. ci-sweeper の ledger(第9節)                          | 1つの PR で直す(skill だけの変更なので、段階に乗せない)                                                       | —                                                              | —                                                                             |
| 1. 導出関数、`finalize_enabled`、`auto_merge`(第2〜3節) | 導出関数と `target_json.finalize` / `auto_merge`。`loop-finalize` と `loop-notify-pr` が `target_json` を読む | caller が `finalize_enabled` と `auto_merge` を渡すのをやめる  | 入力の宣言と、`TARGET_JSON` のフォールバックを消す                            |
| 2. `delivery` と `finalize` の値(第1節)                 | `pr`、`pr_head_push` を受け付ける。`log` / `notion` と未実装の値を拒否する                                    | caller が `pr` と `finalize_pull_request: pr_head_push` を使う | `open_pr`、`push_head`、`push` を消す                                         |
| 3. 入力の改名と削除(第7節)                              | 新しい名前を受け付ける。detect に検証用の入力を足す(第6節)                                                    | caller が新しい名前を使い、既定値の行を消す                    | 旧い名前と、削除した入力の宣言を消す                                          |
| 4. 検証の表(第6節)                                      | 新しい表で検証する。ただし、旧い入力名から来た値も検証する                                                    | caller が表を満たす(triage の4行削除、`allowlist: "**"` など)  | —                                                                             |
| 5. プロンプトのキー(第7-1節)                            | skill が新旧両方のキーを読む                                                                                  | —                                                              | `build_constraints.sh` が新しいキーだけを出し、skill から旧いキーの記述を消す |
| 6. outcome(第8節)                                       | 読む側が新旧両方の値を読む                                                                                    | —                                                              | 書く側を新しい値に切り替える                                                  |

- 話題 4 の段階 E は、話題 3 の段階 E と同時か後にする(新しい入力が届いている必要がある)。
- 話題 5 の段階 C は、skill の同期(`apm install`)が済んでから行う。

### Phase P(別 spec)

`post_review.sh` を、投稿内容の生成(トークン不要)と投稿(プラットフォーム)に分割し、`delivery: pr_review` を実装する。pr-review が `pr_review` に移る。

## 検証

- 導出関数のゴールデンテスト: `delivery`(`pr` / `none`)× `level`(L1 / L2 / L3)× ターゲット種別(integration / pull_request / entity)× `finalize_pull_request` の全組み合わせで、`finalize` と `auto_merge` が、現在の実装と一致することを bats で確認する。比較の相手は、`resolve_git_finalize_strategies` と `entity_target.sh:175` の旧い関数(段階 C まで残る)と、caller の `auto_merge` の式を bash に書き写した関数である。GitHub の式は bats で実行できないため、書き写しが必要になる。書き写しは、現在の `loop-caller-parity.bats:33-42` が式の文字列を確かめていることで、元の式と対応づける。
- `finalize_enabled` の廃止: 検証を通る全組み合わせで、旧式が L2/L3 で true になることを、上記と同じテストで確認する。
- `loop-caller-parity.bats` の、旧い配線そのものを assert しているテスト(`:33-42` の `auto_merge` の式、`:44-` の `finalize_enabled` の式、`:127-128` の `loop-finalize` ステップの `if`)は、段階 C で新しい不変条件に置き換える: caller が `auto_merge` / `finalize_enabled` を渡さないこと、`finalize-l2` が `loop-finalize` を条件なしで実行すること。仕様の変更に伴うテストの更新であり、検証を弱めるものではない。
- 第6節の検証の表: 表の全セルについて、許可と拒否の両方を `loop-write-contract.bats` で確認する。
- 段階 E の互換: 旧い入力名だけ、新しい入力名だけ、両方(一致と不一致)の各場合を、action ごとの bats で確認する。
- outcome: 読み替えの関数と、各 ledger スクリプトの対応表が、旧い値と新しい値の両方を正しく扱うことを確認する。`write_state.sh:163` の条件が、`pr_head_push` の着地で成立することを確認する。
- 各段階のリリース後、dogfood の loop が1回ずつ成功することを、run-log で確認する。
- zizmor / actionlint / ghalint が通ること(Stop フックで検証)。

## 影響を受ける箇所

grep で確認した範囲である。各 PR で、同じ grep を実行して漏れがないことを確かめる。旧い名前(改名表の左列、削除する入力、旧い値、旧いプロンプトのキー)を grep の対象にする。

**workflow:** `.github/workflows/{ci-loop-caller,ci-loop-caller-entity,ci-loop-agent}.yaml`、全 `on-loop-*.yaml`(10本。`on-loop-github-pr-revise.yaml:21-25` の workflow_dispatch の説明文、`on-loop-github-pr-review.yaml:10` のコメントを含む)、`.github/workflows/CLAUDE.md`(「`open_pr` untouched」、`push` / `push_head` の規則)。

**action:**

- `lib/loop/`: 導出関数(新設)、outcome の読み替え関数(新設)、`validate_loop_write_contract.sh`、`build_constraints.sh`、`loop_meta.sh`、`entity_meta.sh`
- `loop-detect/{action.yml,lib/_init.sh,lib/branches.sh,lib/detect.sh,lib/matrix.sh,lib/prs.sh}`
- `loop-entity-detect/{action.yml,lib/detect.sh,lib/entity_target.sh}`
- `loop-execute`(`no_changes_verdict` の入力と `NO_CHANGES_VERDICT`、`allowlist` / `denylist` の受け取り)
- `loop-finalize/{action.yml,lib/create_pr.sh,lib/determine_outcome.sh,lib/should_push_target.sh,lib/should_delete_rejected_branch.sh,lib/write_state.sh,lib/prune_targets.sh,lib/push_target.sh}`
- `loop-notify-pr/{action.yml,lib/notify.sh}`、`loop-run-log/action.yml`、`loop-state-promote/lib/run.sh`

**配布 skill(`.apm/packages/` が source。同期先は手で直さない):**

- プロンプトのキー(`may_edit`、`write_target`、`report_file`)を読む skill: `github/` の `github-issue-autofix`、`github-issue-triage`、`github-pr-review`、`github-pr-revise`、`repo-maintenance/` の `changelog`、`ci-sweeper`、`docs-updater`、`refactor`、`tech-debt`、`test-gap`。各 skill の `SKILL.md`、`references/`、`assets/`、`evals/`(`may-edit-false.yaml` などのファイル名を含む)
- `open_pr` を含む記述: `github-pr-revise/{SKILL.md,references/common-checklist.md}`、`github-issue-autofix/{scripts/detect_autofix.sh,evals/tasks/skip-open-pr.yaml}`(後の2つは、`open_pr` が「開いている PR」の意味かを読み分ける)
- outcome を読む・書くスクリプト: `ci-sweeper/scripts/{update_run_ledger,detect_ci_failures}.sh`、`test-gap/scripts/update_test_gap_ledger.sh`、`test-gap/references/category-input-schema.md`

**bats:**

- `test/bats/github-actions/` の `loop-caller-parity`、`loop-detect-delivery`、`loop-detect-enrich`、`loop-detect-matrix`、`loop-entity-detect`、`loop-write-contract`、`loop-write-state`、`loop-build-constraints`、`loop-prune-targets`
- `test/bats/.github/actions/` の `loop-detect/lib/{branches,detect,pending,prs,guards}.bats`、`loop-entity-detect/lib/{entity_target,detect_dispatch_hook}.bats`、`loop-finalize/lib/{determine_outcome,should_delete_rejected_branch,should_push_target,push_target,create_pr_body}.bats`、`loop-notify-pr/lib/notify.bats`、`loop-run-log/lib/{append,run}.bats`、`lib/loop/{entity_meta,loop_meta,trigger_thread}.bats`、`loop-state-promote/` の bats
- `test/bats/.apm/packages/repo-maintenance/{ci-sweeper,test-gap}/`

**docs:**

- `docs/reference/{specification,loop-engineering-checklist,loop-notify-pr-specification}.md`
- `docs/explanation/loop-engineering/` の `common-loop-triage-format.md`、`loop-caller-reusable-design.md`(`:44`、`:392` を含む)、`loop-caller-workflows-design.md`(`:56`、`:70`、`:83`、`:88`、`:184`、`:194`、`:226` を含む)、`loop-engineering-design.md`(`:251` を含む)、`multi-branch-loops-design.md`(`:44` を含む)、`documentation-maintenance.md`、`loop-capable-skills.md`、`loop-pr-body-skill-contract.md`、`workflows/` の各 design と `loop-caller-inputs-reference.md`
- `docs/explanation/apm-package-design.md`

## この設計者(私)が決めたこと

次は、ユーザーとの対話で決めたことではなく、設計者の判断である。

- `ci-loop-agent.yaml` と composite action を直接呼ぶ利用者との互換性は、保証しない(非目標)。
- 導出した値は、すべて `target_json` に載せる。run 単位の出力は作らない(`auto_merge` がターゲット単位であるため)。以前の版にあった `finalize_plan` と `publish` は作らない。`publish` は `delivery` の部分集合に別の名前を付けただけで、`loop-finalize` は Phase P で `delivery` を直接読めばよい。
- L2/L3 で空の allowlist を拒否し、無制限は `**` で明示させる。
- `TARGET_JSON` が空のときの `open_pr` へのフォールバックを削除する。
- 改名表の新しい名前(第7-1節)。とくに、`no_changes` を `unchanged` にしたこと、`dispatch_hook_script` と `domain_persistence_script` を `detect_hook_script` と `finalize_hook_script` の対にしたこと、`write_target` と `may_edit` を `agent_edit_target` と `agent_edit_allowed` にしたこと。
- outcome の旧い値の読み替えは、期限を設けずに残す。
- 移行は、段階 E・M・C の3段階にする。

## ビルダーに任せること

- 導出関数と読み替え関数の名前と、`lib/loop/` 内のファイル名。
- `target_json.auto_merge` を `loop-notify-pr` に渡す方法(`target_json` をそのまま読むか、`ci-loop-agent.yaml` で取り出して渡すか)。
- `validate_loop_write_contract.sh` の新しい表の、コード上の書き方。
- 段階 E で旧い名前と新しい名前を受け付ける処理の書き方。
- 各段階の PR の分け方。

## 未決(設計者の推測・要確認)

- **composite action の入力の扱い。** GitHub は、composite action の `required: true` を強制せず、宣言のない入力は警告だけで無視する、と理解している。リポジトリ内では確かめていない。本 spec は、この挙動に依存しない(必須の確認はスクリプトで行い、段階 E で旧い入力の宣言を残す)。
- 第9節の ledger の不具合は、静的な読みによる結論で、実行時には確認していない。最初の PR で、finalize の実行後に `.loop/state-ci-sweeper-run-ledger.json` が commit されることを確かめる。
- 外部の利用者が、`git_landing_integration: push` を使っているかは分からない。使っていれば、段階 C のリリースで失敗する(破壊的変更として許容する)。
