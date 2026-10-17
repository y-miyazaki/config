# Loop 配信設計: `delivery` を唯一の入力にし、finalize の判断を1か所で導出する

**Status:** Draft(ユーザーの承認待ち)
**Date:** 2026-10-17
**Primary consumers:** `loop-detect`、`loop-entity-detect`、`ci-loop-caller.yaml`、`ci-loop-caller-entity.yaml`、`ci-loop-agent.yaml`、`loop-finalize`、`validate_loop_write_contract.sh`
**Related:** [Loop Write Target and Delivery Design](2026-07-23-loop-write-target-delivery-design.md)(四つの層。本 spec はその `delivery` 層を具体化する)、[Loop Agent Finalize Levels](2026-08-13-loop-agent-finalize-levels-design.md)、[Loop `github-pr-review` 設計](2026-10-17-loop-pr-review-design.md)
注記: 既存 spec に合わせて日本語で記述する。

## 背景と課題

loop の「結果をどう届けるか」は、本来1つの判断である。ところが現状は、同じ判断が複数の変数の組み合わせで、複数の場所に書かれている。

| #   | 箇所                                                                       | 現在の判断                                                                                               | 問題                                                                                 |
| --- | -------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------ |
| 1   | `ci-loop-caller.yaml` / `ci-loop-caller-entity.yaml` の `finalize_enabled` | `delivery == pr \|\| (delivery == none && level != L1)`                                                  | `delivery` と `level` の組み合わせ。同じ式が2つの caller に重複している              |
| 2   | 同 `auto_merge`                                                            | `delivery == pr && level == L3 && target.finalize == open_pr`                                            | 3項。`target.finalize == open_pr` は `delivery == pr` を含意するため冗長             |
| 3   | `entity_target.sh` の `finalize`                                           | `delivery == pr ? open_pr : none`                                                                        | `loop-detect` の `resolve_git_finalize_strategies` が同じ導出を別実装している(2か所) |
| 4   | `validate_loop_write_contract.sh`                                          | `may_edit × write_target × delivery × level`                                                             | 4変数の許可表                                                                        |
| 5   | `loop-finalize` の各ステップ                                               | push / ブランチ削除 / outcome が、それぞれ `verdict`・`has_changes`・`strategy` を個別に組み合わせて判断 | `strategy == none` の特別扱いが複数ステップに散在する                                |
| 6   | `delivery` の enum                                                         | `log \| issue \| notion` は検証を通るが実装がなく、`none` と同じ挙動になる                               | 宣言と挙動が食い違い、黙って何もしない                                               |

この構造は、実際に配線の不具合を生んだ。github-pr-review の導入(#989)では、(a) `delivery: none` の L2 で finalize が動かない(`finalize_enabled` の式)、(b) `target_json.from.branch` が出ない、(c) `strategy none` で agent ブランチが main にマージされ得る、という問題を、個別の条件追加で直した。同種の問題は、loop が増えるたびに再発する。

もう1つの課題は `domain_persistence_script` である。これは finalize 内で任意のスクリプトを実行し、`GH_TOKEN` を渡す。スクリプトの中身によって必要な権限が変わるが、権限は caller の `permissions:` で固定されるため、スクリプトが何をできるかが暗黙の取り決めになっている。現状の2つの利用例(ci-sweeper、test-gap の ledger)は、リポジトリ内の JSON を jq で更新するだけで、`gh` も `curl` も呼ばない(確認済み)。一方 pr-review の `post_review.sh` は、GitHub にレビューを投稿する。

## 目標

- caller が宣言する配信は **`delivery` の1つだけ**にする。
- `delivery` と `level` から、finalize に必要な判断(finalize 戦略、auto-merge、公開の種類)を **`loop-detect` の1か所**で導出し、下流は導出結果を参照するだけにする。caller と action に、`delivery` や `level` を組み合わせる式を残さない。
- `delivery` の値は、すべて実装がある値にする。未実装の値は検証で失敗させる(fail closed)。
- 必要な権限が `delivery` から一意に分かるようにする。
- 既存 loop(`delivery: pr` と `none`)の挙動を変えない(振る舞い保存)。

## 非目標

- Linear / JIRA / Notion など外部システムへの配信。秘密情報の受け渡しを設計しない限り権限が曖昧になるため、将来の追加枠として記すだけにする。
- 1回の実行での複合配信(`pr` と `issue` の同時実行)。既存 spec の方針を踏襲し、loop を分ける。
- `post_review.sh` の分割(Phase 5 として別 spec)。
- `level` の意味(L1/L2/L3 のエージェント権限)の変更。

## アンチゴール(これが起きたら失敗)

- 導出の場所が増える(別の action や caller に、新しい `delivery` の判断式が入る)。
- 既存 loop の挙動が変わる(PR が開かない、開きすぎる、auto-merge の条件が変わる)。
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
| `pr_review`     | 検証済みのレポートを、既存 PR へのレビュー(COMMENT 形式、インラインコメント付き)として投稿する                                     | **Phase 5 まで未実装**。実装されるまで検証で拒否 |

**命名規則(MUST):** loop の設定値(`delivery`、`finalize`、`publish` の値、関連する入力名)は、snake_case で、**対象(domain)を先、動作を後**に統一する(`pr_review`、`issue_comment`)。動詞を先頭にした値(`open_pr`)は作らない。名前でソートしたとき、同じ対象のものが隣に並ぶようにするためである。`delivery` と `finalize` は同じ語彙を使い、同じ意味の値に別の名前を付けない(`pr` は両方で「PR を作る」)。新しい用語は作らず、`finalize`(`target_json.finalize`)と `git_landing_integration` / `git_landing_pull_request` は既存の名前を使う。

- `log` と `notion` は enum から削除する。実装がなく、必要になったときに、複数の loop が使うと分かった時点で追加する。
- `issue` は「作る」、`issue_comment` は「既存に書く」で、1つの値に分岐を隠さない(既存 spec の「Issue 番号があればコメント、なければ作成」は、この2値に分ける)。
- `none` は「何もしない」の意味に限定する。pr-review が `none` で動いている現状は、Phase 5 で `pr_review` に移るまでの暫定である。

### 2. 導出は `loop-detect` で1回だけ行う(finalize plan)

`loop-detect` と `loop-entity-detect` は、`delivery` と `level` から次を導出し、`finalize_plan` として出力する。

| フィールド   | 値                                            | 導出                                                                                                                                                                                                                                                      |
| ------------ | --------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `finalize`   | `pr \| push \| push_head \| none`             | 現在の `resolve_git_finalize_strategies` と同じ。`delivery` と、任意の `git_landing_integration` / `git_landing_pull_request`、ターゲット種別(integration / pull_request / entity)から決まる。`entity_target.sh` の導出は、この結果を使うように置き換える |
| `auto_merge` | bool                                          | `delivery == pr` かつ `level == L3`                                                                                                                                                                                                                       |
| `publish`    | `none \| pr_review \| issue \| issue_comment` | `delivery` が `pr_review` / `issue` / `issue_comment` のときだけその値。Phase 1〜4 では常に `none`                                                                                                                                                        |

`finalize` の値は、どのブランチへ、どう着地させるかを表す。`pr` は新規ブランチを作って PR を作る。`push_head` は既存 PR の head ブランチへ、最新の `to.branch` を merge して push する(pr-revise)。`push` は integration ブランチへ直接 push する。`none` は着地させない。`pr` と `push_head` は安全条件(merge、fail closed、`fetch-depth: 0`)が異なるため、区別を残す。

粒度: `auto_merge` と `publish` は**実行単位**(run 単位)の値で、`loop-detect` の job 出力として出す。`finalize` は**ターゲット単位**の値で、現状どおり matrix の各要素の `target_json.finalize` に載せる(新しい経路は作らない)。

- caller は `auto_merge` を、そのまま `ci-loop-agent` に渡す。`delivery` や `level` を使う式は caller から消える。
- **`finalize_enabled`(finalize ジョブを走らせるかどうかのフラグ)は廃止する。** finalize ジョブは `level != L1` のときだけ起動する。L1 は書き込み禁止なので、もともと finalize で行うことがない。`finalize == none` でスクリプトもない場合、ジョブは何もせずに終了する。これにより、`delivery` と `domain_persistence_script` の組み合わせで起動を判断する必要がなくなり、起動の判断は `level` だけになる(ユーザー承認済み)。

dogfood の全 caller の実際の組み合わせ(`on-loop-*.yaml` で確認済み)での、旧 `finalize_enabled` と新しい起動条件(`level != L1`)の結果は、すべて一致する。

| loop                                               | `delivery` | `level`          | `domain_persistence_script` | 旧 `finalize_enabled` | 新: finalize ジョブ |
| -------------------------------------------------- | ---------- | ---------------- | --------------------------- | --------------------- | ------------------- |
| changelog、autofix、pr-revise、tech-debt、refactor | `pr`       | L2               | なし                        | true                  | 起動                |
| docs-updater                                       | `pr`       | 指定なし(既定値) | なし                        | true                  | 起動                |
| ci-sweeper                                         | `pr`       | 指定なし(既定値) | あり                        | true                  | 起動                |
| test-gap                                           | `pr`       | L2               | あり                        | true                  | 起動                |
| github-pr-review                                   | `none`     | L2               | あり                        | true                  | 起動                |
| github-issue-triage                                | `none`     | L1               | なし                        | false                 | 起動しない          |

- `level` の既定値の扱い(docs-updater、ci-sweeper)は、実装時に起動条件が既定値を使うことを確認する。
- 旧式と新式が異なるのは、(a) L2/L3 で `delivery: none` かつスクリプトなし(旧: 起動しない、新: 起動して何もしない)、(b) L1 で `pr`、の2つである。(a) に該当する caller は存在しない。(b) は `validate_loop_write_contract.sh` が拒否する組み合わせ(`pr` は `may_edit: true` を要し、L1 は `may_edit: true` を許さない)で、到達しない。
- (a) の挙動の変更は、意図的な変更である: 何もしないジョブが走るだけで、副作用はない。

### 3. `loop-finalize` は `finalize` と `publish` だけを見る

- push・ブランチ削除・outcome の判断は、`finalize`(と `publish`)を入力にする。「`strategy == none` なら…」という特別扱いを、`finalize == none` の1つの規則にまとめる。
- `determine_outcome` は、`finalize == none` で APPROVE のとき `reported` を返す現在の挙動を保つ。

### 4. `domain_persistence_script` の契約

- 位置づけ: 配信ではなく、finalize に差し込む**副次的な独自処理**(ledger、ログなど)。
- 許される範囲: リポジトリルート配下の相対パスのファイル更新のみ(現在の ledger スクリプトが、すでにこれを検証している)。外部システムへの書き込みはしない。
- 権限: 書き込みトークンを必要としない。ただし、Phase 5 までは `post_review.sh` が `GH_TOKEN` を使うため、`GH_TOKEN` の受け渡しは残す(過渡的な例外として明記する)。
- 実行条件: `finalize` に関係なく、finalize ジョブが起動したとき(`level != L1`)に1回実行する。失敗の扱いは現在の挙動を変えない。

### 5. 権限は `delivery` から導く

`delivery` ごとに、caller の `permissions:` に必要な権限を表にする(例: `pr` は `contents: write` と `pull-requests: write`)。表は docs に置き、各 `on-loop-*.yaml` の `permissions:` が、その loop の `delivery` に必要な権限を**含む(上位集合である)**ことを、静的なテスト(bats)で検証する。完全一致は要求しない(既存 loop が、現在は広めの権限を持つため)。pr-review のように、`delivery: none` でもスクリプトが追加の権限を要する loop は、Phase 5 で `pr_review` に移るまでの既知の例外として、テストに明記する(**設計者の判断**)。GitHub の reusable workflow は、caller の権限を超えられないため、プラットフォーム側での強制はしない。

### 6. `validate_loop_write_contract.sh`

4変数の許可表は、`delivery` を主キーにした表に書き直す(振る舞い保存)。`delivery` の値が決まれば `may_edit` の許容値が決まる、という形にする。具体的な表は、現在の検証の挙動を網羅するテストから起こす。

## 移行

| Phase | 内容                                                                                                                                                                                                                                      | 挙動                                                                                                                    |
| ----- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------- |
| 0     | 本 spec                                                                                                                                                                                                                                   | —                                                                                                                       |
| 1     | `loop-detect` / `loop-entity-detect` に `finalize_plan` を追加。既存の出力と式は残す                                                                                                                                                      | 変更なし                                                                                                                |
| 2     | 2つの caller が `finalize_plan` を使う。`finalize_enabled` を廃止し、finalize ジョブは `level != L1` で起動する。重複する式を削除                                                                                                         | 変更なし                                                                                                                |
| 3     | `loop-finalize` が `finalize` を使う(`publish` は読まない)。`log` / `notion` を削除し、未実装の値(`pr_review` / `issue` / `issue_comment`)を、既存の検証点(`validate_loop_write_contract.sh` と `detect.sh` の enum)で fail closed にする | `log` / `notion` / `pr_review` / `issue` / `issue_comment` を指定した caller は検証で失敗する(現在は黙って `none` 扱い) |
| 4     | 権限表と、`permissions:` の静的テストを追加。`validate_loop_write_contract.sh` を `delivery` 主キーの表に書き直す(Phase 3 の拒否は、書き直し前の表に追加する)                                                                             | 変更なし                                                                                                                |
| 5     | `post_review.sh` を、投稿内容の生成(トークン不要)と投稿(プラットフォーム)に分割し、`delivery: pr_review` を実装する。別 spec                                                                                                              | pr-review が `pr_review` に移る                                                                                         |

各 Phase は、独立した PR にする。Phase 1〜4 は振る舞い保存で、Phase 3 の fail closed だけが、既存の誤設定を失敗にする(dogfood の caller は、すべて `pr` または `none` なので影響しない見込み)。

## 検証

- 導出表のゴールデンテスト: dogfood の全 caller について、`(delivery, level)` から導出される finalize ジョブの起動 / `finalize` / `auto_merge` が、現在の式の結果と一致することを bats で確認する。
- 既存の `loop-finalize` の bats(`determine_outcome` など)が、変更なしで通ること。
- zizmor / actionlint / ghalint が通ること(Stop フックで検証)。

## 影響を受ける箇所(grep で確認済み)

実装時に、次をすべて確認する: `.github/actions/lib/loop/build_constraints.sh`、`.github/actions/lib/loop/validate_loop_write_contract.sh`、`.github/actions/loop-detect/{action.yml,lib/detect.sh,lib/matrix.sh}`、`.github/actions/loop-entity-detect/{action.yml,lib/entity_target.sh,lib/outputs.sh}`、`.github/actions/loop-execute/lib/agent_output_format_criteria.md`、`.github/workflows/{ci-loop-agent,ci-loop-caller,ci-loop-caller-entity}.yaml`、`docs/explanation/loop-engineering/` 配下の `delivery` / `finalize_enabled` の記述、関連する bats の fixture。

## この設計者(私)が決めたこと

次は、ユーザーとの対話で決めたことではなく、設計者の判断である。

- 外部の利用者に対する互換性: reusable workflow は、リリースタグで pin されて参照されるため、`log` / `notion` の削除と fail closed は、新しいリリースを取り込む時点で初めて効く。非推奨期間は設けない。
- `publish` は Phase 1 から出力するが、`loop-finalize` が読むのは Phase 5 から。
- 権限テストは、完全一致ではなく上位集合の検査にする。

## ビルダーに任せること

- `finalize_plan` の出力形式(個別出力か JSON か)と、フィールド名。ただし、粒度は上記のとおり(run 単位と、ターゲット単位の `target_json.finalize`)。
- 権限表の具体的な内容と、静的テストの実装方法。
- `validate_loop_write_contract.sh` の新しい表の書き方。

## 未決(設計者の推測・要確認)

- 配信の値を `pr` / `pr_review` / `issue` / `issue_comment` / `none` とする(ユーザー承認済み)。`open_pr` から `pr` への改名は、全 caller・検証・docs に及ぶ破壊的変更で、Phase 3 以降に含める。`finalize` の値の `open_pr` も、同じ理由で `pr` に改名する(`push` / `push_head` は、git の操作そのものを指すので残す)。`git_landing_pull_request` の値 `open_pr` も `pr` になる。`target_json.finalize`、`finalize_strategy`、`loop-finalize` の分岐、bats の fixture、docs の `open_pr` も同時に置き換える。なお、outcome の値(`pr-created`、`no-changes`)はハイフン区切りで、規則と食い違う。本 spec では扱わず、別途の整理候補として挙げる。
- `push`(`git_landing_integration`)は、dogfood の caller に使用がないが、配布される公開入力で、`.github/workflows/CLAUDE.md` にも規則がある。削除は外部の利用者を壊すため、本 spec では扱わず、別途の整理候補とする。
