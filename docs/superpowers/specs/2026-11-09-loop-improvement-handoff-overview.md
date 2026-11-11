# ループ間の引き継ぎ(code-review → triage → autofix)の全体構想と論点

**Status:** 構想(設計書ではない)。2026-11-09 にユーザー決定で設計書を段階ごとに分けた。最初の設計書は [code-review loop(L2、Issue の起票)](2026-11-09-loop-code-review-design.md)。この文書の第3版に対する独立レビューの未解決の論点(下の「後続の設計書へ引き継ぐ論点」)は、各段階の設計書で扱う。

**後続の設計書へ引き継ぐ論点(第3版の独立レビュー)**

- H1: triage を経由する構成では triage を L2(checker あり)にする(ユーザーの当初の決定: 案B)。L1 の triage のラベルだけで L2 の autofix を動かすのは Maker-Checker と Graduated Autonomy に反する。
- H2: 定期実行のジョブは `loop-state-main` で直列化する(Multi-loop Coordination の第1原則)。
- H3: 対象ごとのターゲットで `issue_comment` を配信するには、`validate_delivery_detect_config` と `validate_delivery_target` の規則を変える必要がある。
- M1: 対象ごとのキーの prune で、終端の outcome に `pr_merged` などを含める。
- M2: L1 の定期実行の triage に再試行の上限がない(Failure Mode の Retry limit of 3)。
- M3: 人間が PR を閉じた直後や、マージ後も Issue が開いたままのときに、同じ Issue を拾い直す。
- M4: Webhook の経路と定期実行の経路の分離は、作成者ではなくラベルで両方の層に実装する。
- M5: 対象ごとのターゲットの `result` と `verifier_context` を、その対象に絞る。
- M6: 並行するターゲットの作業ブランチの名前が衝突しうる(`loop-worktree-setup` の秒単位の名前)。
- M8: run-log に target のキーがなく、並行する対象の結果を区別できない。
- Low: Webhook の autofix を対象ごとのキーにすると、今の「同時に1つの PR」が外れる。予算が対象の数だけ超えうる。キーの区切りの `#` は ref で有効な文字。
  **Date:** 2026-11-09
  **Related:** [Loop Engineering Design — Design Principles](../../explanation/loop-engineering/loop-engineering-design.md#design-principles)、[Loop 配信設計](2026-10-17-loop-delivery-plan-design.md)、[Loop の投稿の配信](2026-10-18-loop-delivery-message-design.md)、[PR review loop](2026-10-17-loop-pr-review-design.md)(L2 でレポートを投稿に変える既存の形)

## 0. 準拠する設計原則

すべての決定は `loop-engineering-design.md` の Design Principles に従う。外れる決定はない。

| 原則                                         | この spec での決定                                                                                                                                                                                           |
| -------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| **Maker-Checker Separation**(最も重要)       | 報告を超える行動(Issue の起票、修正 PR)は、maker とは別セッションの checker が APPROVE した結果だけで行う。偽の APPROVE への備えとして、code-review の `finalize_script` が根拠を機械的に再検証する(第4.3節) |
| **Graduated Autonomy**                       | L1 は報告だけ。`issue_create` は `pr_create` と同じく L2/L3 だけ。新しい機能(code-review、定期実行での取り込み)は L1 で2週間以上観察してから L2 に上げる(第2節)。昇格と減速の条件を数値で決める(第2.2節)     |
| **Design Stop Conditions First**             | 止まり方を先に決める(第6節)                                                                                                                                                                                  |
| **Phase Contract**                           | 変えない。finalize は下流のワークフローを起動しない。引き継ぎは「Issue に残ったラベル」を、次のループの detect が定期実行で読む(Detect は外部の事実を読むだけ)                                               |
| **Intake Gating / 不変条件9**                | Webhook で Bot を拒否する既存の規則はどこも変えない。定期実行の取り込みは Webhook の intake と対象を分け、同じ Issue を両方が扱わないようにする(第5節)                                                       |
| **Multi-loop Coordination / Fan-out**        | 1回の定期実行で扱う件数を `detect_max_targets` で上限し、予算を detect で1回判定する。並行は上限の範囲に収まる                                                                                               |
| **不変条件1〜6、Agent Credential Isolation** | エージェントは worktree でだけ書き、書き込みの認証情報を持たない。起票は finalize が行う。state は finalize でだけ進む                                                                                       |
| **Component Design Principles**              | プラットフォームは汎用のまま(「detect が返した対象ごとのターゲット」は特定のドメインに依存しない)。どの Issue を拾うかの条件、checker の基準、レポートの変換は caller と、caller が指定するスクリプトに置く  |
| **Failure Mode Countermeasures(State Rot)**  | 対象ごとのキーも、既存の30日の prune の対象にする(第3.3節)                                                                                                                                                   |
| **State cursor の一般規則**                  | 新しい規則を作らない。`issue_create` は「API で配信する L2」として、checker の APPROVE で同じ finalize で進む。REJECT は進めず失敗回数を数える                                                               |

## 1. 目的(ユーザーの意図)

- Loop Engineering のワークフローが「開発 → テスト → デプロイ → 改善」を自動で回す。人間は機能のアイデアを出すことに集中する。
- code-review loop は「改善」の入口。マージ済みのコードから定期的にバグを見つけ、Issue にする。triage / autofix がそれを自動で拾う。
- 人間が判断するのは、autofix が作った PR のマージ承認だけ(autofix は L2 のまま)。
- triage を経由するか、autofix が直接拾うかは、caller の設定で選べる。
- 1件ずつの直列にしない。1回の定期実行で最大 N 件を並行に処理する(ユーザー決定。N の初期値は3)。

## 2. 段階的な導入

### 2.1 段階

| 段階                         | 内容                                                                                                  | 次へ進む条件                    |
| ---------------------------- | ----------------------------------------------------------------------------------------------------- | ------------------------------- |
| A. プラットフォーム          | 組み込みの範囲検出、対象ごとのターゲット、`issue_create`、`write_state` の再試行、prune の拡張(第3節) | bats と既存の loop の回帰がない |
| B. code-review L1            | `delivery: none`。指摘はログに出るだけ(第4.1節)                                                       | 2週間以上、第2.2節の条件        |
| C. code-review L2            | 承認された指摘だけを起票する。この段階では誰も拾わない(人間が見る)(第4.2節)                           | 2週間以上、第2.2節の条件        |
| D. autofix の定期取り込み L1 | 拾う対象の選び方だけを観察する(エージェントは修正方針を出すだけで PR は作らない)(第5.2節)             | 2週間以上                       |
| E. autofix の定期取り込み L2 | 拾った Issue の修正 PR を作る                                                                         | —                               |
| F. triage の定期取り込み     | code-review が作った Issue を triage する(L1。triage はもともと L1)(第5.1節)                          | —                               |

- 各段階は別の PR にする。L1 → L2 の移行チェックリスト(state のスキーマの文書化、maker と checker の分離、denylist、予算と sub-agent の上限)を C と E の PR で確かめる。
- 「triage を経由する」構成は F まで、「autofix が直接拾う」構成は E までで成立する。dogfood は triage を経由する。

### 2.2 昇格と減速の条件(Metrics、Stop Conditions)

| 条件           | 値                                                                                                                                |
| -------------- | --------------------------------------------------------------------------------------------------------------------------------- |
| L1 → L2 の昇格 | 2週間以上の観察で、人間が「妥当」と判断した指摘の率が70%以上(design の Metrics の Approval Rate に合わせる)                       |
| Slow Down      | 起票した Issue のうち「not planned」で閉じた率が30%を超えたら、`detect_max_targets` / `finalize_issue_limit` を下げるか L1 に戻す |
| Kill           | 2週続けて、修正 PR のマージ数がゼロで予算を使い切った                                                                             |

## 3. プラットフォームの変更(段階 A)

### 3.1 組み込みの範囲検出(`ci-loop-caller` の `detect_script` を省略可能に)

- `ci-loop-caller.yaml` と `loop-detect` の `detect_script` を `required: false`、既定 `""` にする。空の `DETECT_SCRIPT` を止めている2か所(`detect.sh` の `main` 先頭の `: "${DETECT_SCRIPT:?}"` と `resolve_detect_script_path`)を迂回する。`ci-loop-caller-entity` は必須のまま。
- 空のとき、ターゲットごとに `last_sha` から `HEAD` までの変更ファイルを `list_diff_paths`(`.github/actions/lib/loop/edit_paths.sh`)で取る。
  - プラットフォームが書くパス(`.loop/` 配下、解決済みの `state_file` と `run_log_file`)を除く。
  - 0件 → `{"skip": true}`。1件以上 → `{"skip": false, "result": {"since": <last_sha>, "changed_count": <n>}}`(不変条件8の追跡のため)。
  - rc 2(安全でないパス)→ 実行する。rc 1 → detect のステップを非0で終える。rc は `set -e` に頼らず明示的に確かめる。
- 到達できない `last_sha`: この経路でだけ、`target_last_sha` で到達を確かめ(`git cat-file -e`)、見つからなければ警告を標準エラーに出して `HEAD~10` を返す。プロンプトの `Last SHA` と範囲検出が同じ基点を使う。

### 3.2 対象ごとのターゲット(定期実行で最大 N 件を並行に処理する)

- detect スクリプトが、結果に `result.items` を返せるようにする。各要素は `{"key": "<対象を表す文字列>", "entity": {"kind": "issue", "handoff_key": "..."}, "context": {...}}`。
- `items` があるとき、`loop-detect` は要素ごとにターゲットを作る。
  - キーは `integration:<branch>#<key>`。`key` は `^[A-Za-z0-9._-]+(:[A-Za-z0-9._-]+)*$` に一致すること(注釈とキーに入るため)。一致しなければ detect を失敗させる。
  - **state の判定を要素ごとに行う。** circuit breaker、pending、却下内容の持ち越しを、要素のキーで読む(今は detect の前にブランチのキーで1回だけ読んでいる。`items` のときは detect の後に要素ごとに読む)。止められた要素はターゲットにしない(既存の `::warning` と run-log の skip の記録)。
  - プロンプトの「Change Detection Result」には、その要素の `context` を入れる。`target_json` に `entity` を入れる(Issue へのコメントの配信で、配信先の種別の検証と番号の取得に使う)。
  - 件数は既存の `detect_max_targets` で上限する。超えた分は次の実行で拾う(Issue のラベルが残っているので、失われない)。
- ターゲットは既存の matrix で並行に動き(`ci-loop-caller.yaml` の execute)、finalize がそれぞれのキーで state を書く。`loop-state-promote` は PR 番号で pending を探すので、そのまま動く。
- 予算は detect で1回判定する(既存)。1回の実行の並行数は `detect_max_targets` 以下。
- 対象を選ぶ条件(どのラベルの Issue を拾うか)は detect スクリプトと caller の `detect_env_json` に置く(ドメインの判断)。

### 3.3 prune の拡張(State Rot)

- `prune_targets.sh` は今、`pull_request:` のキーしか消さない。対象ごとのキー(`#` を含む integration のキー)も、pending がなく、終端の outcome で、30日を過ぎたら消す。

### 3.4 `delivery: issue_create`(L2/L3、integration のターゲット)

**位置づけ:** Issue を作るのは報告を超える行動なので、`pr_create` と同じく L2/L3 だけで許す。L1 では検証で拒否する。ターゲットは integration に限る(entity では state が読まれない)。

**流れ**(pr-review の L2 と同じ形):

1. maker が worktree にレポートを書く。指摘0件でも空の配列を書く。
2. checker がレポートを検証する。
3. APPROVE なら、finalize(Push Agent Branch)がエージェントのブランチを push し、caller が指定する `finalize_script` が `origin/<branch>` からレポートを読んで `LOOP_MESSAGE_DIR/issues.json` を書く(`issue_create` では `finalize_script` を必須にする)。
4. Deliver Message が Issue を作る。エージェントのブランチは削除する。

**`issues.json`:** `[{"title", "body", "fingerprint"}]`。0件は `[]`。ない、または検証に失敗 → 配信の失敗。

**Deliver Message の手順**(`if` は `issue_create` では `verdict == 'APPROVE'`):

1. 検証する。`[]` なら何も作らず成功。
2. 指紋を `sha256(loop_name + "\n" + fingerprint)` の先頭16桁にする。
3. **重複を先に除く。** 出所ラベル(`finalize_label_allowlist` の1つ目)の Issue を open と closed の両方から全件取り(`gh api --paginate`)、本文の marker `<!-- <loop_name>:fp:<hash> -->` を照合する。同じ実行の中の重複も除く。
4. 残りを `finalize_issue_limit`(既定5)で切る。切った指摘は捨て、題名と指紋を step summary と run-log に記録する(次回に回すと cursor が止まるため)。
5. 1件ずつ、本文中の既存の marker と `@` メンションを無害化し、先頭に marker、末尾に Meta を付けて `gh issue create --label <allowlist の全ラベル>` で作る。
6. 失敗したらその時点で止め、作成済みの番号を記録する。

- ラベルは `finalize_label_allowlist` の全ラベル(エージェントの出力からは取らない)。`issue_create` では必須。事前にリポジトリに作っておく(前提条件)。
- **不変条件10(新設):** `issue_create` が付けるラベルに、どの Webhook の intake のラベル(dogfood では `autofix`、`needs-triage`、`triage:needs-info`)も含めない。autofix の Webhook は送信者を見ずに `autofix` ラベルで起動するため。強制は caller の許可リストで行い、このリポジトリでは bats で検査する。
- outcome: 1件以上作れば `issue_created`(新設)、0件なら `unchanged`。

**state:** checker が APPROVE し配信が成功 → advance(`resolve_state_write_mode` に分岐を足し、判定を配信の後に置く)。REJECT → 既存どおり(`rejected`、失敗回数、circuit breaker)。配信の失敗 → 進めない(`error`)。次の実行で同じ範囲を再実行し、重複の判定で二重起票を防ぐ。

**入力:** `finalize_issue_limit`(既定 `5`)。`finalize_label_allowlist` を `issue_create` でも許し、必須にする。

### 3.5 `write_state` の再試行

- 並行するターゲットが同じ state ファイルへ push して競合する。push の stderr を捕まえ、`! [rejected] ... (fetch first|non-fast-forward)` のときだけ(`[remote rejected]` は除く)、`load_state_tmp` → prune → `resolve_consecutive_failures` → `write_target_state` → commit → push を最大3回やり直す(`loop-run-log` の再試行と同じ形)。
- `FINALIZE_COMMIT_PATHS` が空のときだけ再試行する(読み直しで台帳ファイルの変更が消えるため)。それ以外と、再試行を使い切ったときは、現在どおり state PR へのフォールバック。

## 4. code-review loop

### 4.1 段階 B: L1(観察)

| 設定                                      | 値                                                                                     |
| ----------------------------------------- | -------------------------------------------------------------------------------------- |
| トリガー / `concurrency`                  | `schedule`(週1回)、`workflow_dispatch` / `group: loop-state-main`、`queue: max`        |
| `level` / `delivery`                      | `L1` / `none`                                                                          |
| `detect_script`                           | 省略(組み込みの範囲検出)                                                               |
| `agent_engine` / `agent_maker_skill_name` | `claude` / `code-review`                                                               |
| `agent_maker_instructions`                | `code-review` を effort `medium`、基点 `Last SHA` で実行し、指摘を出力する。修正しない |

- 指摘はログに出るだけ。L1 は state を書かないので、範囲は毎回 `HEAD~10` になる(観察には足りる)。
- 確かめること: CI の CLI に組み込みの `code-review` があるか。`Agent` ツール(sub-agent)が許可されるか。sub-agent の数の上限を設定できなければ、`Agent` を許可せず effort を `medium` 以下にする(L1 → L2 のチェックリストの「maximum sub-agent count」)。

### 4.2 段階 C: L2(起票)

| 設定                                         | 値                                                                                                                                                                                    |
| -------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `level` / `delivery`                         | `L2` / `issue_create`                                                                                                                                                                 |
| `agent_edit_target` / `agent_edit_allowlist` | `report` / レポートのパスだけ(例: `.loop-code-review/findings.json`)                                                                                                                  |
| `agent_maker_instructions`                   | 検証済みの指摘を、題名・本文・指紋(`<path>:<関数名または行の要約>:<不具合の種類>`)・根拠(パスと行)の形で書く。0件でも空の配列                                                         |
| `agent_checker_instructions`                 | 既定で却下。指摘ごとに、根拠の行がこの範囲の差分に実在するか、不具合の筋道が成り立つか、指紋が位置と種類から決まっているか。1件でも根拠がなければ REJECT。レポート以外の変更は REJECT |
| `agent_checker_model`                        | maker より強いモデルか、別の系統(原則)                                                                                                                                                |
| `agent_unchanged_verdict`                    | `REJECT`                                                                                                                                                                              |
| `finalize_script`                            | 第4.3節。code-review はこのリポジトリの skill ではないので、リポジトリ専用の `scripts/` に置く                                                                                        |
| `finalize_label_allowlist`                   | `loop:code-review`(事前に作る)                                                                                                                                                        |
| `finalize_issue_limit`                       | `5`                                                                                                                                                                                   |

### 4.3 code-review の `finalize_script` の再検証(偽の APPROVE への備え)

- `verdict` はエージェントのジョブの自己申告で、偽の APPROVE が届きうる(design の Credential Isolation の残るリスク)。起票はその影響を Issue と後続のループへ広げるので、`finalize_script` が決定的に再検証する。
  - 根拠のパスと行が、`Last SHA` から HEAD までの差分(信頼できる checkout で取る)に実在しない指摘は落とす。
  - 題名と本文の長さの上限を超える指摘は落とす。
  - 落とした件数と理由を step summary に出す。

## 5. 定期実行での取り込み(段階 D〜F)

### 5.1 triage(段階 F、L1 のまま)

- **L1 のまま。** 以前の案Bは「triage から autofix へ dispatch するなら L2」だった。定期実行の方式では triage は dispatch せず、ラベルとコメント(L1 で許される書き込み)だけを行う。autofix を動かすかの判断は、autofix 自身(L2、checker あり)が行う。
- 既存の Webhook の経路(人間が作った Issue)は変えない。
- 定期実行の経路を足す。`on-loop-github-issue-triage.yaml` に、`schedule` で `ci-loop-caller`(対象ごとのターゲット)を使うジョブを足す。
  - 拾う対象: open で、出所ラベル `loop:code-review` が付き、`triage:*` のラベルがない Issue。最大 `detect_max_targets`(3)件。
  - Webhook の経路と対象を分ける: Webhook は Bot の操作を拒否するので、Bot が作った Issue(`loop:code-review`)は定期実行の経路だけが扱う。人間が作った Issue は Webhook の経路だけが扱う。同じ Issue を両方が扱うことはない。
  - `detect_issue.sh` に、拾う対象を一覧にするモード(`result.items`)を足す。
  - 配信は既存の `issue_comment`(L1)。ターゲットの `entity` で配信先を決める。
- triage の失敗(エージェントの失敗)では Issue にラベルが付かないので、次の実行でまた拾う。L1 は state を書かないので circuit breaker はない。歯止めは予算と `detect_max_targets`(残るリスク)。

### 5.2 autofix(段階 D〜E)

- 既存の Webhook の経路(`autofix` ラベル、`workflow_dispatch`)は変えない。ただし、state のキーを対象ごとにする(detect が `result.items` に1件だけ返す)。これで、定期実行の経路と同じキー(`integration:main#issue:<n>`)で pending と circuit breaker が働く。
- 定期実行の経路を足す。`schedule` で `ci-loop-caller`(対象ごとのターゲット)を使うジョブ。
  - 拾う対象(caller の `detect_env_json` で選ぶ):
    - triage を経由する構成(dogfood): open で `triage:ready` と `bug` が付き、`autofix` ラベルがない Issue。
    - 直接拾う構成: open で `loop:code-review` が付き、`autofix` ラベルがない Issue。
  - 共通の除外: `Fixes #N` の PR が開いている Issue(既存の `open_pr_fixes_issue`)。要素のキーの state で pending か circuit breaker に当たるもの(第3.2節)。
  - 最大 `detect_max_targets`(3)件を並行に処理する。
  - Webhook の経路と対象を分ける: `autofix` ラベルの付いた Issue は Webhook の経路だけが扱う。
- 段階 D(L1)では、エージェントは修正方針を出すだけで PR を作らない。選ばれた Issue と方針の妥当性を観察する。段階 E で L2 にする。
- 人間が作った Issue も、triage で `triage:ready` と `bug` になれば拾われる(ユーザー決定)。`feature` などは拾われない。
  - **取り下げ(2026-11-11):** autofix は triage の出力を入力にしない。人間が作った Issue は、今までどおり人間が `autofix` ラベルを付ける。詳細は [定期実行での取り込み(対象ごとのターゲット、triage / autofix の定期実行)](2026-11-11-loop-scheduled-intake-design.md) の第0節。
- triage skill の文書の「`triage:ready` のときは人間に `autofix` を付けるよう伝える」を、portable に「caller が定期実行の取り込みを設定していれば、`bug` で `triage:ready` の Issue は自動で拾われる。そうでなければ人間に `autofix` を付けるよう伝える」に改める(`SKILL.md`、`references/category-fsm.md`、`references/category-prompt-rules.md`、`evals/tasks/`)。

## 6. 止まり方(Design Stop Conditions First)

| 止める仕組み                                                                 | 対象                         |
| ---------------------------------------------------------------------------- | ---------------------------- |
| checker の REJECT と circuit breaker(対象ごと)                               | code-review、autofix         |
| 1回の件数の上限(`detect_max_targets`、`finalize_issue_limit`)                | 全ループ。並行数も上限される |
| 予算(detect で1回判定)                                                       | 全ループ                     |
| 指紋の重複判定(open と closed)                                               | 同じ指摘の再起票             |
| 経路の分離(Webhook / 定期実行で対象が重ならない)                             | 二重起動                     |
| 引き継ぎは一方向(code-review → triage → autofix)。どのループも他を起動しない | 循環                         |
| 人間のマージ(autofix は L2)                                                  | 修正の反映                   |
| 第2.2節の Slow Down / Kill                                                   | 品質とコスト                 |

## 7. 状態遷移とイベントの対応

**Issue 1件の状態遷移(triage を経由する構成)**

| 状態 | きっかけ                                                                                                | 次の状態                                                                                                |
| ---- | ------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------- |
| S0   | code-review(L2)の checker が APPROVE し、`finalize_script` の再検証を通り、起票(重複を除き上限の範囲で) | S1(`loop:code-review`)                                                                                  |
|      | REJECT                                                                                                  | 起票しない(cursor は進まない。失敗回数が増える)                                                         |
| S1   | triage の定期実行が拾う(上限を超えたら次の実行)                                                         | T                                                                                                       |
| T    | triage が `triage:ready` と `bug` を付けた                                                              | R                                                                                                       |
|      | `triage:needs-info` / `triage:failed` / `bug` 以外                                                      | 人間の操作を待つ(定期実行の対象から外れる)                                                              |
|      | triage のエージェントが失敗(ラベルが付かない)                                                           | S1 のまま(次の実行でまた拾う)                                                                           |
| R    | autofix の定期実行が拾う(上限を超えたら次の実行)                                                        | A                                                                                                       |
| A    | autofix(L2)が `Fixes #N` の PR を作成                                                                   | S3(この Issue のキーに pending。定期実行の対象から外れる)                                               |
|      | 却下                                                                                                    | R のまま(この Issue のキーの失敗回数が増え、circuit breaker が開けば対象から外れる)                     |
| S3   | 人間がマージ                                                                                            | Issue がクローズ                                                                                        |
|      | 人間が PR を閉じる                                                                                      | R に戻る(pending が解け、次の実行でまた拾われる)。拾わせたくなければ人間がラベルを外すか Issue を閉じる |

- どの「止まる」も、Issue のラベルか state に理由が残り、黙って消えない。引き継ぎは一方向で、どのループも他を起動しない。

**イベントと各 caller の起動判定**(★が変更)

| イベント(送信者)                              | code-review | triage                                         | autofix                                     | pr-review | pr-revise |
| --------------------------------------------- | ----------- | ---------------------------------------------- | ------------------------------------------- | --------- | --------- |
| schedule                                      | 実行        | ★実行(`loop:code-review` で未 triage の Issue) | ★実行(`triage:ready`+`bug`、`autofix` なし) | —         | —         |
| issues:opened / labeled、issue_comment(App)   | —           | 拒否(Bot)                                      | `autofix` 以外は拒否                        | —         | 拒否(Bot) |
| issues:labeled `autofix`(人間)                | —           | 拒否                                           | 実行(★対象ごとのキー)                       | —         | —         |
| issues:opened(人間)                           | —           | 実行                                           | —                                           | —         | —         |
| issue_comment(人間、`triage:needs-info`)      | —           | 実行                                           | —                                           | —         | —         |
| pull_request_target:opened(App の autofix PR) | —           | —                                              | —                                           | 拒否(Bot) | —         |

- Webhook の Bot 拒否はどこも変えていない。不変条件10を破って `autofix` を付けると、autofix の Webhook が起動し、定期実行との二重になる。第3.4節で防ぐ。
- 人間が `autofix` を付けた瞬間に、定期実行がすでにその Issue を拾っていると、両方が動きうる(短い窓)。同じ対象ごとのキーを使うので、先に PR を作った側の pending で後の側は止まる。PR を作る前の競合は残るリスク。

## 8. このリポジトリでの検査(bats)

- 不変条件10。`issue_create` と L1 の組み合わせの拒否。`issue_create` を entity / pull_request のターゲットで拒否し、`finalize_script` と `finalize_label_allowlist` を必須にすること。
- `issue_create` の state(APPROVE かつ配信成功で advance、REJECT で `rejected`、配信の失敗で進まない)。重複を上限より先に除くこと。marker の無害化。
- 組み込みの範囲検出(`.loop/` だけでスキップ、rc 2 で実行、rc 1 で非0終了、空の `detect_script`、到達できない `last_sha` でプロンプトの `Last SHA` がフォールバックの値)。
- 対象ごとのターゲット(キーの検証、要素ごとの circuit breaker と pending、`detect_max_targets` の上限、prune の拡張)。
- `write_state` の再試行(non-fast-forward で再試行、台帳ありと ruleset の拒否では再試行しない)。
- triage と autofix の定期実行の選び方(経路の分離: Webhook の対象を拾わない)。
- 新しい入力に合わせて `loop-caller-parity.bats`、`loop_input_topology.py` 等を更新する。

## 9. 残るリスク

- **反映の遅れ:** 定期実行の間隔ぶん遅れる。
- **指紋の不安定さ:** 同じ不具合が別の Issue になりうる。checker、上限、triage が吸収する。
- **再発の抑止:** closed も重複の判定に含めるので、同じ指紋の再発は起票されない。
- **上限を超えた指摘:** 捨てて記録する。
- **人間の選別なしの入力:** エージェントが書いた Issue が autofix の入力になる。ユーザーの意図どおり。marker とメンションを無害化し、根拠を再検証する。
- **triage の失敗の繰り返し:** L1 なので circuit breaker がない。予算と上限で止まる。
- **`autofix` ラベルと定期実行の短い競合**(第7節)。
- **範囲外:** 既存の `detect_script` の caller の、到達できない `last_sha` での縮退。`loop-state-promote` の push の競合(再試行なし)。

## 10. ドキュメントの更新

- `loop-engineering-design.md`: 不変条件10。Intake Gating(定期実行の経路と Webhook の経路の分離)。State cursor の表(`issue_create`)。Finalize の strategy matrix と、ブランチを削除する delivery の一覧(`issue_create`)。STATE Files(対象ごとのキー)。Failure Mode Countermeasures(prune の拡張)。Credential Isolation の残るリスク(`issue_create`)。
- `loop-caller-inputs-reference.md`、`docs/reference/specification.md`: `detect_script` の省略、`result.items`、`issue_create`、`finalize_issue_limit`。
- `common-loop-triage-format.md`、`loop-capable-skills.md`(detect JSON の `result.items`)。
- `2026-10-17-loop-delivery-plan-design.md`: `issue_create` の使えるターゲットと検証表。
- triage と autofix の workflow 設計書: 定期実行の経路、経路の分離、対象ごとのキー。autofix の非目標「`autofix` ラベルなしの自動 autofix」を改める。
- `github-issue-triage` skill の文書(第5.2節)。
- 新規: `loop-code-review-workflow-design.md`。

## 11. builder に任せること

- 組み込みの範囲検出と、要素ごとの state の判定の実装の分け方(`append_detect_candidate` の分割)。
- `issue_create` の state の判定を配信の後に置く実装。
- レポートと `issues.json` の検証、無害化の方式、code-review の `finalize_script`。
- 定期実行の間隔(triage と autofix)。
- **SHA pin は2段で更新する**(action のリリース → `ci-loop-agent.yaml` の pin → caller の pin)。
