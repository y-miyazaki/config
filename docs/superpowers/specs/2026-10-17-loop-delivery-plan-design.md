# Loop 配信設計: `delivery` を唯一の入力にし、finalize の判断を1か所で導出する

**Status:** Draft(ユーザーの承認待ち)
**Date:** 2026-10-17
**Primary consumers:** `.github/actions/lib/loop/`、`loop-detect`、`loop-entity-detect`、`loop-finalize`、`loop-notify-pr`、`ci-loop-caller.yaml`、`ci-loop-caller-entity.yaml`、`ci-loop-agent.yaml`、`validate_loop_write_contract.sh`
**Related:** [Loop Write Target and Delivery Design](2026-07-23-loop-write-target-delivery-design.md)(四つの層。本 spec はその `delivery` 層を具体化する)、[Loop Agent Finalize Levels](2026-08-13-loop-agent-finalize-levels-design.md)、[Loop `github-pr-review` 設計](2026-10-17-loop-pr-review-design.md)
注記: 既存 spec に合わせて日本語で記述する。

## 背景と課題

loop の「結果をどう届けるか」は、本来1つの判断である。ところが現状は、同じ判断が複数の変数の組み合わせで、複数の場所に書かれている。

| #   | 箇所                                                                                       | 現在の判断                                                                                                                     | 問題                                                                                                                                                                                   |
| --- | ------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1   | `ci-loop-caller.yaml:510` / `ci-loop-caller-entity.yaml:363` の `finalize_enabled`         | `delivery == open_pr \|\| (delivery == none && level != L1)`                                                                   | 同じ式が2か所にある。さらに、値が情報を運んでいない。L1 では `finalize-l2` ジョブ自体が動かない。L2/L3 で検証を通る `delivery` は `open_pr` と `none` だけなので、式は常に true になる |
| 2   | `auto_merge`(caller の式、`loop-finalize` の `Enable Auto-Merge`、`loop-notify-pr` の文面) | caller が `delivery == open_pr && level == L3 && target.finalize == open_pr` を計算し、下流が strategy と level を再び確かめる | 同じ判断が3か所にある。caller の式の `delivery == open_pr` は冗長である(`target.finalize == open_pr` が `delivery == open_pr` を含意する。`detect.sh:907-936`、`entity_target.sh:175`) |
| 3   | `entity_target.sh:175` の `finalize`                                                       | `delivery == open_pr ? open_pr : none`                                                                                         | `loop-detect` の `resolve_git_finalize_strategies`(`detect.sh:907`)と、同じ導出を別に実装している                                                                                      |
| 4   | `validate_loop_write_contract.sh`                                                          | `may_edit × write_target × delivery × level`                                                                                   | 4変数の許可表。`may_edit` は `level` と1対1で、検証の大半は2つの食い違いを拒否するためにある                                                                                           |
| 5   | `loop-finalize` の各ステップ                                                               | push / ブランチ削除 / state の書き方 / outcome が、それぞれ `verdict`・`has_changes`・`strategy` を個別に組み合わせて判断      | `strategy == none` の特別扱いが、複数のステップに散在する                                                                                                                              |
| 6   | `delivery` の enum                                                                         | `log \| issue \| notion` は検証を通るが実装がなく、`none` と同じ挙動になる                                                     | 宣言と挙動が食い違い、黙って何もしない                                                                                                                                                 |
| 7   | `ci-loop-caller.yaml` と `ci-loop-caller-entity.yaml` の入力                               | 同じ名前の入力が、2つの reusable で異なる既定値を持つ(第7節 7-2)                                                               | caller がどちらの reusable を使うかで、同じ省略の意味が変わる                                                                                                                          |
| 8   | outcome の値                                                                               | `push` / `push_head` で着地しても `pr-created` を返す(`determine_outcome.sh:56-59`)。値はハイフン区切り                        | PR を作っていないのに「PR 作成」になる。値の書き方が、他の値(snake_case)と食い違う                                                                                                     |

この構造は、実際に配線の不具合を生んだ。github-pr-review の導入(#989)では、(a) `delivery: none` の L2 で finalize が動かない(`finalize_enabled` の式)、(b) `target_json.from.branch` が出ない、(c) `strategy none` で agent ブランチが main にマージされ得る、という問題を、個別の条件追加で直した。同種の問題は、loop が増えるたびに再発する。

入力の側にも、同じ構造の冗長がある。全 caller の実値と、2つの reusable の入力と既定値を調べた結果は、第7節にまとめた。

もう1つの課題は `domain_persistence_script` である。これは finalize 内で任意のスクリプトを実行し、`GH_TOKEN` を渡す。スクリプトの中身によって必要な権限が変わるが、権限は caller の `permissions:` で固定されるため、スクリプトが何をできるかが暗黙の取り決めになっている。現状の2つの利用例(ci-sweeper、test-gap の ledger)は、リポジトリ内の JSON を jq で更新するだけで、`gh` も `curl` も呼ばない(確認済み)。一方 pr-review の `post_review.sh` は、GitHub にレビューを投稿する。

## 目標

- caller が宣言する配信は、**`delivery` の1つだけ**にする。
- finalize の判断(ターゲットごとの `finalize` と `auto_merge`)は、`.github/actions/lib/loop/` の**1つの関数**で導出する。`loop-detect` と `loop-entity-detect` は、その関数を呼んで結果を `target_json` に載せるだけにする。caller、`ci-loop-agent.yaml`、`loop-finalize`、`loop-notify-pr` に、`delivery` や `level` を組み合わせる式を残さない。
- `delivery` の値は、すべて実装がある値にする。未実装の値は検証で失敗させる(fail closed)。
- 1つの判断を、1つの入力で宣言する。`level` から決まる `may_edit` は入力から外す。判断を表す入力(`delivery`、`level`、`no_changes_verdict`)は、2つの reusable で同じ定義(必須、既定値なし)にする。
- 効かない値は受け付けない。L1 で `write_target` / `allowlist` / `denylist` を指定したら、検証で拒否する。
- 値の名前を、1つの規則(第1節)で統一する。

## 非目標

- Linear / JIRA / Notion など外部システムへの配信。秘密情報の受け渡しを設計しない限り権限が曖昧になるため、将来の追加枠として記すだけにする。
- 1回の実行での複合配信(`pr` と `issue` の同時実行)。既存 spec の方針を踏襲し、loop を分ける。
- `post_review.sh` の分割(Phase 6 として別 spec)。
- `level` の意味(L1/L2/L3 のエージェント権限)の変更。
- caller の `permissions:` を `delivery` ごとに絞ること。理由は第5節に書く。
- `ci-loop-agent.yaml` と各 composite action を、caller を経由せずに直接呼ぶ利用者との互換性。docs が示す経路は `on-loop-* → ci-loop-caller* → ci-loop-agent` だけである(`loop-caller-reusable-design.md:356`)。

## アンチゴール(これが起きたら失敗)

- 導出の場所が増える(別の action や caller に、新しい `delivery` の判断式が入る)。
- dogfood の loop の挙動が変わる(PR が開かない、開きすぎる、auto-merge の条件が変わる、state やブランチの扱いが変わる)。第8節の outcome の改名による値の変化だけは、意図した変更とする。
- 新しい設定値が増える(`delivery` を置き換えずに、並行して別の入力が生まれる)。

## 設計

### 1. caller の入力は `delivery` のみ

`delivery` は、「エージェントの出力を、git の外の世界へどう届けるか」を表す。閉じた集合とする。

| 値              | 意味                                                                                                                               | 状態                                             |
| --------------- | ---------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------ |
| `pr`            | PR を作る(L3 では auto-merge を有効にする。draft にするかは別入力 `pr_draft`)                                                      | 実装済み(現在の名前は `open_pr`。改名する)       |
| `none`          | プラットフォームは何も配信しない。エージェントが自分で完結する(L1 triage)か、レポートファイルを `domain_persistence_script` が扱う | 実装済み                                         |
| `issue`         | レポートから Issue を新規作成する                                                                                                  | 未実装。実装されるまで検証で拒否                 |
| `issue_comment` | 既存の Issue にコメントを投稿する(対象は `target_json` の Issue 番号)                                                              | 未実装。実装されるまで検証で拒否                 |
| `pr_review`     | 検証済みのレポートを、既存 PR へのレビュー(COMMENT 形式、インラインコメント付き)として投稿する                                     | **Phase 6 まで未実装**。実装されるまで検証で拒否 |

**命名規則(MUST):** 値(`delivery`、`finalize`、outcome)と、本 spec が追加・改名する入力名は、snake_case で、**対象(domain)を先、動作を後**に統一する(`pr_review`、`issue_comment`)。動詞を先頭にした値(`open_pr`)は作らない。名前でソートしたとき、同じ対象のものが隣に並ぶようにするためである。同じ意味の値に、別の名前を付けない(`delivery` と `finalize` の `pr` は、どちらも「PR を作る」)。既存の入力名への適用範囲は、未決の節に書く。

- `log` と `notion` は enum から削除する。実装がなく、必要になったときに、複数の loop が使うと分かった時点で追加する。
- `issue` は「作る」、`issue_comment` は「既存に書く」で、1つの値に分岐を隠さない(既存 spec の「Issue 番号があればコメント、なければ作成」は、この2値に分ける)。
- `none` は「何もしない」の意味に限定する。pr-review が `none` で動いている現状は、Phase 6 で `pr_review` に移るまでの暫定である。
- `issue` / `issue_comment` / `pr_review` は finalize が配信するので、L2 以上でしか使えない(第6節)。

### 2. 導出は `lib/loop/` の1つの関数で行う

`.github/actions/lib/loop/` に、ターゲットごとの finalize の判断を導出する関数を1つ置く。`.github/workflows/CLAUDE.md` の Composition の規則により、2つの composite が共有するロジックは `lib/loop/` に置く必要がある(別の composite の `lib/` は共有契約にできない)。

| 出力(`target_json` のフィールド) | 値                                | 導出                                                                                                                                                                                                         |
| -------------------------------- | --------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `finalize`                       | `pr \| push \| push_head \| none` | 現在の `resolve_git_finalize_strategies`(`detect.sh:907`)と同じ。`delivery` と、任意の `git_landing_integration` / `git_landing_pull_request`、ターゲット種別(integration / pull_request / entity)から決まる |
| `auto_merge`                     | bool                              | `level == L3` かつ `finalize == pr`                                                                                                                                                                          |

- `loop-detect`(`matrix.sh`)と `loop-entity-detect`(`entity_target.sh`)は、この関数を呼ぶ。`detect.sh` の `resolve_git_finalize_strategies` と、`entity_target.sh:175` の独自の導出は削除する。
- `finalize` の値は、どのブランチへ、どう着地させるかを表す。`pr` は新規ブランチを作って PR を作る。`push_head` は既存 PR の head ブランチへ、最新の `to.branch` を merge して push する(pr-revise)。`push` は integration ブランチへ直接 push する。`none` は着地させない。`pr` と `push_head` は、安全条件(merge、fail closed、`fetch-depth: 0`)が異なるため、区別を残す。
- `auto_merge` は、`finalize` と同じくターゲット単位の値である。1回の実行に `finalize` の異なるターゲットが混在しうる(integration は `pr`、pull_request は `push_head`)ため、run 単位の値では表せない。

**旧式との一致(`auto_merge`):** 旧式は `delivery == open_pr && level == L3 && target.finalize == open_pr` である。`target.finalize == open_pr` は `delivery == open_pr` を含意するので、旧式は `level == L3 && target.finalize == open_pr` と等しい。新式は、この式そのものである。

**下流の変更:**

- `loop-finalize` の `Enable Auto-Merge` は、`target_json.auto_merge` だけを見る。`loop-notify-pr` の L3 の文面(`notify.sh:208`)も、`target_json.auto_merge` を見る。
- `auto_merge` の入力は、`ci-loop-caller.yaml`、`ci-loop-caller-entity.yaml`、`ci-loop-agent.yaml`、`loop-finalize`、`loop-notify-pr` から削除する。

**`finalize_enabled` の廃止:** `finalize_enabled` は、`finalize-l2` ジョブ内の `loop-finalize` **ステップ**だけを止めるフラグである(`ci-loop-agent.yaml:3-4`、`:568`)。ジョブは、すでに `level` が L2/L3 のときだけ起動する(`ci-loop-agent.yaml:513-517`)。

- `finalize_enabled` を、caller と `ci-loop-agent.yaml` から削除する。`finalize-l2` では、`loop-finalize` ステップを常に実行する。
- 背景 #1 のとおり、検証を通る設定では、L2/L3 の旧 `finalize_enabled` は常に true である。dogfood の全 caller で、次のとおり挙動は変わらない。

| loop                                                         | `delivery` | `level`             | 旧: `loop-finalize` ステップ | 新: `loop-finalize` ステップ |
| ------------------------------------------------------------ | ---------- | ------------------- | ---------------------------- | ---------------------------- |
| changelog、autofix、pr-revise、tech-debt、refactor、test-gap | `pr`       | L2                  | 実行                         | 実行                         |
| docs-updater、ci-sweeper                                     | `pr`       | 指定なし(既定値 L2) | 実行                         | 実行                         |
| github-pr-review                                             | `none`     | L2                  | 実行                         | 実行                         |
| github-issue-triage                                          | `none`     | L1                  | `finalize-l2` が動かない     | `finalize-l2` が動かない     |

- 旧式で `loop-finalize` が止まる L2/L3 の組み合わせは、`delivery` が `log` / `issue` / `notion` のときだけで、これらは `may_edit: true` で検証が拒否する(`validate_loop_write_contract.sh:114-118`)。到達しない。
- 互換性への影響: `ci-loop-agent.yaml` を直接呼び、`finalize_enabled` を渡している利用者は、入力がなくなるため失敗する。`finalize_enabled` の既定値 `false` に頼って L2 で `loop-finalize` を止めていた利用者は、`loop-finalize` が動くようになり、state の書き込み、agent ブランチの削除、PR の作成が起きる。どちらも非目標(直接呼ぶ利用者との互換性)に当たる。

### 3. `loop-finalize` は `target_json` だけを見る

- push・ブランチ削除・state の書き方・outcome の判断は、`target_json.finalize` を入力にする。「`strategy == none` なら…」という特別扱いを、`finalize == none` の1つの規則にまとめる。
- `determine_outcome` は、`finalize == none` で APPROVE のとき `reported` を返す現在の挙動を保つ。
- `TARGET_JSON` が空のとき `open_pr` とみなす現在のフォールバック(`loop-finalize/action.yml:155`、`:160`)は削除し、失敗させる。黙って PR を作る既定値は、本 spec が取り除こうとしている「宣言のない判断」である。dogfood の2つの caller は、常に `target_json` を渡している。

### 4. `domain_persistence_script` の契約

- 位置づけ: 配信ではなく、finalize に差し込む**副次的な独自処理**(ledger、ログなど)。
- 許される範囲: リポジトリルート配下の相対パスのファイル更新のみ(現在の ledger スクリプトが、すでにこれを検証している)。外部システムへの書き込みはしない。
- 権限: 書き込みトークンを必要としない。ただし、Phase 6 までは `post_review.sh` が `GH_TOKEN` を使うため、`GH_TOKEN` の受け渡しは残す(過渡的な例外として明記する)。
- 実行条件: `finalize` に関係なく、`loop-finalize` が動くとき(L2/L3)に1回実行する。失敗の扱いは現在の挙動を変えない。
- 環境: スクリプトは、`detect_domain_env_json` の値を受け取らない。この値は detect ジョブの `GITHUB_ENV` にだけ入り、finalize ジョブには届かない。スクリプトが書くファイルのパスは、スクリプトの既定値で決め、caller の `additional_commit_paths` と一致させる。これは、test-gap がすでに従っている前提(`update_test_gap_ledger.sh:17`)を、契約として明文化するものである。ci-sweeper は、この前提に反している(第9節)。
- `additional_commit_paths` は、スクリプトの出力のうち commit してよいパスの許可リストとして残す。`loop-finalize` は、スクリプトを先に実行し、後続の `Write State` が、列挙されたパスだけを commit に加える(`write_state.sh:114-150`)。

### 5. 権限は本 spec では変えない

caller の `permissions:` を `delivery` から導くことはしない。reusable の各ジョブが、`delivery` に関係なく固定の書き込み権限を要求しているためである(`ci-loop-caller.yaml` の execute ジョブ、`ci-loop-agent.yaml` の `agent-l2` と `finalize-l2`)。caller はこの権限を与えないとワークフローを起動できないので、「`delivery` に必要な権限を含むか」という静的テストは常に通り、何も検証しない。権限を `delivery` ごとに絞るには、reusable のジョブを `delivery` ごとに分ける構造の変更が必要で、本 spec の範囲を超える。

### 6. `validate_loop_write_contract.sh` は `level` を主キーにする

`may_edit` を入力から外す(第7節 7-1)と、検証は `level × delivery × write_target × allowlist × denylist` の組み合わせになる。許容値を決めているのは `level` なので、`level` を主キーにした表に書き直す。

| `level` | 許す `delivery`                                                                 | `write_target`          | `allowlist`                                  | `denylist`                |
| ------- | ------------------------------------------------------------------------------- | ----------------------- | -------------------------------------------- | ------------------------- |
| L1      | `none`                                                                          | 空(指定は拒否)          | 空(指定は拒否)                               | 空(指定は拒否)            |
| L2 / L3 | `pr`、`none`(Phase 6 で `pr_review`、実装時に `issue` / `issue_comment` を追加) | `fix` か `report`(必須) | 必須(空は拒否)。制限しないときは `**` を書く | 任意(空は既定の denylist) |

- L1 で `delivery: pr` を拒否するのは、現在の検証と同じである。L1 で `issue` / `log` / `notion` を通している現在の検証は、第1節の削除と fail closed により、`none` だけを通すようになる。
- 現在の `write_target` は L1 で警告を出して無視するだけで、`allowlist` と `denylist` は L1 を検査しない。新しい表は、これらを拒否する。
- `allowlist` の空は、現在「無制限」を意味する(`loop-execute/lib/paths.sh:63-65`、`loop-detect/action.yml:14`)。L2/L3 で空を拒否し、無制限は `**` で明示させる。`**` は全パスに一致する(`paths.sh` の `glob_to_ere`、`paths.bats:79-81`)。書き忘れが「無制限」として黙って通る状態を、なくすためである。
- `build_constraints.sh` は、`allowlist` が空でないとき「Allowed paths: …」をプロンプトに出す(`build_constraints.sh:96-99`)。`**` のときは、現在の空と同じく何も出さないようにし、プロンプトの内容を変えない。

### 7. 入力の冗長と命名の整理

調べた範囲は、全 loop caller(`on-loop-*.yaml` の10本。`on-loop-state-promote.yaml` を除く)の `with:` の全入力の値、`ci-loop-caller.yaml` と `ci-loop-caller-entity.yaml` の全入力の定義と既定値、`loop-detect` と `loop-entity-detect` の action の入力、`build_constraints.sh`、`validate_loop_write_contract.sh` である。caller の値と既定値の突き合わせは、スクリプトで全件を比較した。

caller の内訳: `ci-loop-caller.yaml` を使うのは changelog、refactor、autofix、tech-debt、docs-updater、test-gap、pr-revise、ci-sweeper の8本。`ci-loop-caller-entity.yaml` を使うのは triage と pr-review の2本。

| #   | 対象                                                              | 現状の問題                                                                                                                                                                                                                                                                                                                                                                                                                        | 対応                                                                                                                                                                                                                                                                                                                                                          |
| --- | ----------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 7-1 | `may_edit`                                                        | 全10 caller で `level != L1` と一致する。検証が、食い違い(L1 で true、L2/L3 で false)を拒否しているだけである                                                                                                                                                                                                                                                                                                                     | 2つの reusable と、`loop-detect` / `loop-entity-detect` の action の入力から削除する。`lib/loop/` で `level` から導出する。プロンプトの `## Constraints` には、引き続き `may_edit` を出す(skills は `may_edit` と `write_target` で分岐し、`level` / `delivery` を見ない、という既存の規則を保つ)。非推奨のシム `emit_loop_constraints_from_level` は削除する |
| 7-2 | `delivery` / `level` / `no_changes_verdict`(判断を表す入力)       | 2つの reusable で既定値が異なる。`delivery` は `open_pr` と `none`、`level` は L2 と L1、`no_changes_verdict` は `REJECT` と `APPROVE`。docs-updater と ci-sweeper は `level` を省略し、既定値 L2 に頼っている                                                                                                                                                                                                                    | 2つの reusable と `loop-entity-detect` の action で、既定値をなくし、必須にする。caller は、既定値と同じ値でも必ず書く。docs-updater と ci-sweeper に `level: L2` を足す(他の caller は、3つとも明示済み)                                                                                                                                                     |
| 7-3 | `write_target` / `allowlist` / `denylist`(`level` に従属する入力) | 既定値が2つの reusable で異なる。`write_target` は必須と `report`、`allowlist` は必須と `""`。`write_target` の必須は L1 と両立しない(L1 では効かないのに、省略できない)。entity 側の既定値 `report` は、triage の caller から行を消しても L1 に渡る                                                                                                                                                                              | 2つの reusable と `loop-entity-detect` の action で、`required: false`、既定値 `""` にそろえる。許容値は第6節の表で、`level` ごとに検証する。triage からは3つの行を削除する。autofix、pr-revise、pr-review の `allowlist: ""` は `"**"` にする(挙動は変わらない)                                                                                              |
| 7-4 | 配管の入力に明示された既定値                                      | 既定値と同じ値を明示している。`environment: default`(10本)、`agent_checker_skill_name: loop-verifier`(10本)、`denylist: ""`(7本)、`pr_body: ""`(6本)、`pr_enabled: false`(5本)、`max_targets_per_schedule: 3`(changelog、ci-sweeper、docs-updater)、`detect_domain_env_json: "{}"`(tech-debt、test-gap)、`git_landing_integration: open_pr`(autofix)、`pr_exclude: fork,draft,label:no-loop` と `pr_include_bots: ""`(ci-sweeper) | これらの行を削除する(挙動は変わらない)。7-2 と 7-3 の入力(判断を表す入力と、`level` に従属する入力)は、この対象にしない。判断は、既定値と同じでも caller が宣言する                                                                                                                                                                                           |
| 7-5 | `branch_match` と `branch_state`                                  | 8本(branch caller の全部)が、同じ値 `main` を両方に渡している。`branch_match` が空のときは `branch_state` だけを監視する(`branches.sh:93-106`、`detect.sh:1223`)                                                                                                                                                                                                                                                                  | この8本から `branch_match` を削除する(挙動は変わらない)。入力自体は、複数ブランチを監視する用途のために残す                                                                                                                                                                                                                                                   |
| 7-6 | `dispatch_hook_token`                                             | `ci-loop-caller-entity.yaml:133` の入力は、トークンを `with:` で渡す。`.github/workflows/CLAUDE.md` は、reusable workflow にトークンを `with:` で渡すことを禁じている。dogfood の caller は使っていない。未指定のときは detect のトークンを使う                                                                                                                                                                                   | reusable の入力と、`loop-entity-detect` の action の入力(`action.yml:36`、`:112`)を、どちらも削除する。dispatch hook は、常に detect のトークンを使う(`loop-entity-detect/lib/detect.sh:51`、`:238` の分岐もなくす)。別のトークンが必要になった時点で、`secrets:` として宣言する                                                                              |
| 7-7 | `loop-detect` の `loop_branch_match`                              | caller の `branch_match_mode`(照合方式)を受ける action の入力が `loop_branch_match` で、caller の `branch_match`(パターン)は `loop_integration_branches` に渡る(`ci-loop-caller.yaml:359-360`)。層をまたいで、`branch_match` という語が別の意味になっている                                                                                                                                                                       | action の入力を `loop_branch_match_mode` に改名し、caller の `branch_match_mode` と1対1にする。環境変数 `LOOP_BRANCH_MATCH` も `LOOP_BRANCH_MATCH_MODE` にする                                                                                                                                                                                                |

**確認して、残すもの:**

- `no_changes_verdict`: 「maker が差分を作らなかったときに、`APPROVE` と `REJECT` のどちらにするか」は、loop ごとのドメイン判断である(L1 の triage は差分なしが正常で、L2 の loop の多くは差分なしを失敗とみなす)。`level` からは決まらないので、入力として残す。7-2 で必須にする。
- `write_target` は、`delivery` から導出しない。tech-debt は `delivery: pr` で `write_target: report` であり、`delivery` と1対1にならない。
- `additional_commit_paths` と `domain_persistence_script`: ledger の2つの caller が、同じファイルのパスを両方に書いている。冗長に見えるが、`additional_commit_paths` は commit の許可リストとして働く(第4節)。
- `state_file` / `run_log_file` / `budget_file` / `labels` / `branch_prefix` / `commit_message` / `priority`: dogfood の caller は、どれも上書きしていない。配布先が調整するための入力なので残す。

**互換性:** 7-1、7-2、7-3、7-6、7-7 は、reusable workflow または composite action の入力を、削除・改名・必須化する変更である。GitHub は、宣言のない入力を `with:` で渡すとエラーにし、必須の入力がないときもエラーにする。旧い書き方の caller は、新しいリリースを取り込んだ時点で失敗する。第1節の `open_pr` → `pr` の改名と同じ方針(非推奨期間なし、dogfood の caller は同じ PR で更新)を取る。7-3 の `allowlist: ""` の拒否は、L2/L3 で空を渡していた外部の caller を失敗させる。

### 8. outcome の値

| 現在の値     | 新しい値     | 変更の理由                                                                                          |
| ------------ | ------------ | --------------------------------------------------------------------------------------------------- |
| `pr-created` | `pr_created` | snake_case にそろえる。`finalize == pr` のときだけ返す                                              |
| (なし)       | `pushed`     | `push` / `push_head` で着地したとき。現在は `pr-created` を返している(`determine_outcome.sh:56-59`) |
| `no-changes` | `no_changes` | snake_case にそろえる                                                                               |

`rejected`、`reported`、`skipped`、`error` は変えない。

- outcome は、`.loop/loop-run-log.md`(JSONL)、state、ledger に永続化され、次のスクリプトが読む: `loop-finalize/lib/write_state.sh`、`loop-notify-pr/lib/notify.sh`、`lib/loop/{loop_meta,entity_meta}.sh`、`loop-run-log/action.yml`、`ci-loop-agent.yaml`、配布 skill の `ci-sweeper/scripts/{detect_ci_failures,update_run_ledger}.sh` と `test-gap/scripts/update_test_gap_ledger.sh`、`test-gap/references/category-input-schema.md`。
- 読む側は、移行期間のあいだ旧い値も受け付ける。`pushed` は、`pr-created` を「着地した」の意味で読んでいる箇所すべてで、同じ扱いにする。
- 移行期間は、旧い値を含むファイルがなくなるまでとする。run-log は30日より古いエントリを削除する(`docs/reference/specification.md:403`)。state と ledger の保持期間は、実装時に確認して、この節に追記する。

### 9. 調査中に見つかった既存の不具合(ci-sweeper の ledger)

- ci-sweeper の caller は、`CI_SWEEPER_LEDGER_FILE` を `.loop/state-ci-sweeper-run-ledger.json` に設定している(`on-loop-ci-sweeper.yaml:121`)。この値は `detect_domain_env_json` の一部で、detect ジョブにしか届かない(第4節)。
- finalize で動く `update_run_ledger.sh` は、既定値 `ci-sweeper-run-ledger.json`(リポジトリ直下)に書く(`update_run_ledger.sh:47`)。
- `additional_commit_paths` は `.loop/state-ci-sweeper-run-ledger.json` なので、書いたファイルは commit されない。detect は `.loop/` 側を読むので、ledger が更新されない。
- 静的に読んだ範囲での結論で、実行時には確認していない。状況証拠として、`.loop/state-ci-sweeper-run-ledger.json` はリポジトリに存在しない。
- 対応: `update_run_ledger.sh` の既定値を `.loop/state-ci-sweeper-run-ledger.json` にする(test-gap と同じ形)。source は `.apm/packages/repo-maintenance/.apm/skills/ci-sweeper/scripts/update_run_ledger.sh` である。本 spec の他の変更とは独立した不具合修正なので、Phase 0 として先に別 PR で直す。

## 移行

| Phase | 内容                                                                                                                                                                                                                                                                              | dogfood の挙動                                         | 外部の caller への影響                                                                                                       |
| ----- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------- |
| 0     | ci-sweeper の ledger の既定パスを直す(第9節)                                                                                                                                                                                                                                      | ledger が commit されるようになる(不具合修正)          | なし                                                                                                                         |
| 1     | `lib/loop/` に導出関数を追加し、`loop-detect` と `loop-entity-detect` が `target_json.finalize` と `target_json.auto_merge` を出す。旧い式と入力は残す                                                                                                                            | 変更なし                                               | なし                                                                                                                         |
| 2     | `loop-finalize` と `loop-notify-pr` が `target_json.auto_merge` を読む。`auto_merge` と `finalize_enabled` の入力と式を削除し、`finalize-l2` で `loop-finalize` を常に実行する。`loop-finalize` の `TARGET_JSON` のフォールバックを削除する(第2節、第3節)                         | 変更なし                                               | `ci-loop-agent.yaml` / `loop-finalize` / `loop-notify-pr` を直接呼ぶ利用者が失敗する                                         |
| 3     | `delivery` の enum を整理する。`log` / `notion` を削除し、未実装の値(`pr_review` / `issue` / `issue_comment`)を fail closed にする。`open_pr` を `pr` に改名する(`delivery`、`target_json.finalize`、`git_landing_*` の値、`loop-finalize` の分岐、bats、docs、配布 skill の記述) | 変更なし                                               | `open_pr` / `log` / `notion` を指定した caller が失敗する                                                                    |
| 4     | 入力の契約を整理する。第6節の検証の表と、第7節の 7-1〜7-7 を実施する                                                                                                                                                                                                              | 変更なし                                               | `may_edit` / `dispatch_hook_token` を渡す caller、必須の入力を省略する caller、L2/L3 で `allowlist: ""` の caller が失敗する |
| 5     | outcome の値を改名し、`pushed` を追加する(第8節)。読む側は、旧い値も受け付ける                                                                                                                                                                                                    | run-log・state・ledger に書かれる outcome の値が変わる | outcome の値を読む外部のスクリプトが、新しい値を知らないと誤動作する                                                         |
| 6     | `post_review.sh` を、投稿内容の生成(トークン不要)と投稿(プラットフォーム)に分割し、`delivery: pr_review` を実装する。別 spec                                                                                                                                                      | pr-review が `pr_review` に移る                        | なし                                                                                                                         |

- 各 Phase は、独立した PR にする。dogfood の caller は、各 Phase の PR で同時に更新する。
- 外部の caller への影響は、reusable workflow を SHA で pin しているため、新しいリリースを取り込んだ時点で初めて生じる。

## 検証

- 導出関数のゴールデンテスト: `delivery`(`pr` / `none`)× `level`(L1 / L2 / L3)× ターゲット種別(integration / pull_request / entity)× `git_landing_*` の全組み合わせで、`finalize` と `auto_merge` が、現在の `resolve_git_finalize_strategies`・`entity_target.sh:175`・caller の `auto_merge` の式の結果と一致することを bats で確認する(`open_pr` は `pr` と読み替える)。
- `finalize_enabled` の廃止: 検証を通る全組み合わせで、旧式が L2/L3 で true になることを、上記と同じテストで確認する。
- `loop-caller-parity.bats` の、旧い配線そのものを assert しているテスト(`:33-42` の `auto_merge` の式、`:44-` の `finalize_enabled` の式、`:127-128` の `loop-finalize` ステップの `if`)は、新しい不変条件に置き換える: caller が `auto_merge` / `finalize_enabled` を渡さないこと、`finalize-l2` が `loop-finalize` を条件なしで実行すること。仕様の変更に伴うテストの更新であり、検証を弱めるものではない。
- 第6節の検証の表: 表の全セルについて、許可と拒否の両方を `loop-write-contract.bats` で確認する。`loop-entity-detect.bats:117`(「L2/L3 require may_edit true」)は、`level` から導出する規則に合わせて更新する。
- outcome: 読む側のスクリプトが、旧い値と新しい値の両方を受け付けることを、各 bats で確認する。
- zizmor / actionlint / ghalint が通ること(Stop フックで検証)。

## 影響を受ける箇所

grep で確認した範囲である。実装時に、各 Phase の PR で、同じ grep を実行して漏れがないことを確かめる。

**Phase 1〜2(`finalize`・`auto_merge`・`finalize_enabled`):**

- `.github/actions/lib/loop/`(導出関数を新設)
- `.github/actions/loop-detect/{action.yml,lib/detect.sh,lib/matrix.sh}`
- `.github/actions/loop-entity-detect/{action.yml,lib/entity_target.sh}`
- `.github/actions/loop-finalize/action.yml`
- `.github/actions/loop-notify-pr/{action.yml,lib/notify.sh}`
- `.github/workflows/{ci-loop-caller,ci-loop-caller-entity,ci-loop-agent}.yaml`
- `.github/workflows/on-loop-github-pr-review.yaml:10`(`finalize_enabled` のコメント)
- `test/bats/github-actions/loop-caller-parity.bats`、`test/bats/.github/actions/loop-entity-detect/lib/entity_target.bats`、`test/bats/github-actions/loop-detect-matrix.bats`、`test/bats/.github/actions/loop-notify-pr/lib/notify.bats`
- docs: `loop-caller-workflows-design.md`(`:70`、`:88`、`:184`、`:194`)、`loop-caller-reusable-design.md:44`、`loop-engineering-design.md:251`、`workflows/loop-github-issue-triage-workflow-design.md:91`、`workflows/loop-github-pr-review-workflow-design.md`(`:42`、`:150`)、`docs/reference/loop-notify-pr-specification.md`

**Phase 3(`open_pr` → `pr`、enum の整理):** `open_pr` を含む次のファイルすべて。

- action: `lib/loop/validate_loop_write_contract.sh`、`loop-detect/{action.yml,lib/detect.sh,lib/prs.sh}`、`loop-entity-detect/lib/entity_target.sh`、`loop-finalize/{action.yml,lib/create_pr.sh,lib/determine_outcome.sh,lib/should_push_target.sh,lib/write_state.sh}`、`loop-notify-pr/action.yml`
- workflow: `ci-loop-caller.yaml`、`ci-loop-caller-entity.yaml`、`.github/workflows/CLAUDE.md`(「`open_pr` untouched」の規則)、`on-loop-{changelog,ci-sweeper,docs-updater,github-issue-autofix,github-pr-revise,refactor,tech-debt,test-gap}.yaml`(`on-loop-github-pr-revise.yaml:21-25` の workflow_dispatch の説明文を含む)
- 配布 skill: `.apm/packages/github/.apm/skills/github-pr-revise/{SKILL.md,references/common-checklist.md}`、`.apm/packages/github/.apm/skills/github-issue-autofix/{scripts/detect_autofix.sh,evals/tasks/skip-open-pr.yaml}`(後の2つは、`open_pr` が「開いている PR」の意味かを実装時に読み分ける)
- bats: `test/bats/github-actions/{loop-caller-parity,loop-detect-delivery,loop-detect-enrich,loop-write-contract,loop-write-state}.bats`、`test/bats/.github/actions/loop-detect/lib/{detect,pending,prs}.bats`、`test/bats/.github/actions/loop-entity-detect/lib/entity_target.bats`、`test/bats/.github/actions/loop-finalize/lib/{determine_outcome,should_delete_rejected_branch,should_push_target}.bats`
- docs: `docs/reference/{specification,loop-engineering-checklist,loop-notify-pr-specification}.md`、`docs/explanation/loop-engineering/` の `common-loop-triage-format.md`、`loop-caller-reusable-design.md`、`loop-caller-workflows-design.md`、`loop-engineering-design.md`、`multi-branch-loops-design.md`、`workflows/` の各 design と `loop-caller-inputs-reference.md`

**Phase 4(入力の契約):**

- `lib/loop/{validate_loop_write_contract,build_constraints}.sh`
- `loop-detect/{action.yml,lib/_init.sh,lib/branches.sh,lib/detect.sh,lib/matrix.sh}`(7-1、7-7)
- `loop-entity-detect/{action.yml,lib/detect.sh,lib/entity_target.sh}`(7-1、7-2、7-3、7-6)
- `ci-loop-caller.yaml`、`ci-loop-caller-entity.yaml`、全 `on-loop-*.yaml`(10本)
- bats: `test/bats/github-actions/{loop-write-contract,loop-build-constraints,loop-detect-matrix,loop-entity-detect,loop-caller-parity}.bats`、`test/bats/.github/actions/loop-detect/lib/{branches,detect,prs}.bats`、`test/bats/.github/actions/loop-entity-detect/lib/entity_target.bats`
- docs: `workflows/loop-caller-inputs-reference.md`(`dispatch_hook_token` の `:350` を含む)、`multi-branch-loops-design.md:44`、`may_edit` / `write_target` を記述する `docs/explanation/loop-engineering/` の各 design

**Phase 5(outcome):** 第8節に列挙したスクリプトと、`pr-created` / `no-changes` を含む bats(`test/bats/.apm/packages/repo-maintenance/{ci-sweeper,test-gap}/`、`test/bats/.github/actions/lib/loop/{entity_meta,loop_meta,trigger_thread}.bats`、`test/bats/.github/actions/loop-detect/lib/guards.bats`、`test/bats/.github/actions/loop-finalize/lib/{create_pr_body,determine_outcome}.bats`、`test/bats/.github/actions/loop-notify-pr/lib/notify.bats`、`test/bats/.github/actions/loop-run-log/lib/{append,run}.bats`、`test/bats/github-actions/{loop-prune-targets,loop-write-state}.bats`)、docs(`specification.md`、`loop-notify-pr-specification.md`、`loop-engineering-design.md`、`multi-branch-loops-design.md`、`workflows/` の各 design)

## この設計者(私)が決めたこと

次は、ユーザーとの対話で決めたことではなく、設計者の判断である。

- 外部の利用者に対する互換性: 非推奨期間は設けない。reusable workflow は SHA で pin されるため、変更は新しいリリースを取り込む時点で初めて効く。
- `ci-loop-agent.yaml` と composite action を直接呼ぶ利用者との互換性は、保証しない(非目標)。
- 導出した値は、すべて `target_json` に載せる。run 単位の出力は作らない(`auto_merge` がターゲット単位であるため)。以前の版にあった `finalize_plan` と `publish` は作らない。`publish` は `delivery` の部分集合に別の名前を付けただけで、`loop-finalize` は Phase 6 で `delivery` を直接読めばよい。
- L2/L3 で空の `allowlist` を拒否し、無制限は `**` で明示させる。
- `TARGET_JSON` が空のときの `open_pr` へのフォールバックを削除する。
- 判断を表す入力は、既定値と同じでも caller に書かせる(7-2、7-4)。
- ci-sweeper の ledger の不具合は、本 spec の Phase 0 として先に直す。

## ビルダーに任せること

- 導出関数の名前と、`lib/loop/` 内のファイル名。
- `target_json.auto_merge` を `loop-notify-pr` に渡す方法(`target_json` をそのまま読むか、`ci-loop-agent.yaml` で取り出して渡すか)。
- `validate_loop_write_contract.sh` の新しい表の、コード上の書き方。
- outcome の旧い値を受け付ける処理の実装方法。

## 未決(設計者の推測・要確認)

- **既存の入力名への命名規則の適用範囲(ユーザーの判断が必要)。** 以前の版の「検出側の入力を `detect_pr_*` に改名する」案は、規則を一貫して適用していなかったので取り下げた(`scoped_pr_number`、`priority`、`max_targets_per_schedule`、`branch_match`、`ack_trigger_comment` など、他の検出側の入力に `detect_` が付かない)。選択肢は次の2つである。
  - (A) 規則は、値と、本 spec が追加・改名する入力にだけ適用する。既存の入力名は変えない。`labels`(対象がない)だけ `pr_labels` にするかも、この判断に含める。
  - (B) 既存の入力名もすべて規則に合わせる。動詞が先頭の名前(`ack_trigger_comment`、`infer_files_pattern`、`write_target` など)や、対象がない名前(`labels`)を改名する。すべて破壊的変更で、caller の入力の過半に及ぶ。
- outcome の移行期間: state と ledger に outcome が何日残るかは、未確認である(第8節)。
- 第9節の ledger の不具合は、静的な読みによる結論で、実行時には確認していない。Phase 0 の PR で、finalize の実行後に `.loop/state-ci-sweeper-run-ledger.json` が commit されることを確かめる。
