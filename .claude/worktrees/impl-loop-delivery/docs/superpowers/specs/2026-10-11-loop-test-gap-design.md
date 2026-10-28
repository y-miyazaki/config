# Loop `test-gap` 設計: テスト不足を埋める改善ループ

**Status:** Draft(設計確定待ちの項目は「未決事項」に記載)
**Date:** 2026-10-11
**Primary consumers:** 新規 loop `test-gap`(`on-loop-test-gap.yaml`)、`repo-maintenance` package
**Related:** [Loop Engineering Design](../../explanation/loop-engineering/loop-engineering-design.md)、[Loop-Capable Skills](../../explanation/loop-engineering/loop-capable-skills.md)、[Report Tech Debt Workflow](../../explanation/loop-engineering/workflows/loop-tech-debt-workflow-design.md)、[Multi-Branch Loops Design](../../explanation/loop-engineering/multi-branch-loops-design.md)

> 注記: `docs/superpowers/specs/` の他の spec は英語だが、本 spec は依頼により日本語で記述する。

## 背景と課題

現行の loop は「CI 失敗を直す(`ci-sweeper`)」「ドキュメントのドリフトを直す(`docs-updater`)」「構造を整理する(`refactor`)」「負債をレポートする(`tech-debt`)」などで、コードを書く側と CI を直す側は揃っている。一方、**テストの不足は CI が失敗しないため、どの loop にも検知されない**。時間とともに劣化するが失敗として現れない資産であり、スケジュール実行の改善ループに向いている。

`tech-debt` は `test_gap` カテゴリを定義しているが、検知の裏づけが無い。`detect_tech_debt_sensors.sh` のセンサーは依存関係、ドキュメント(リンク切れ・陳腐化)、マーカー(TODO 等)、git churn のみで、テストに関するセンサーは存在しない。そのため `test_gap` はエージェントが文脈から推測するカテゴリになっている(Debt Taxonomy(`.apm/packages/repo-maintenance/.apm/skills/tech-debt/references/category-debt-taxonomy.md`) の Category decision order も、センサーに裏づけられたカテゴリを優先すると定めている)。さらに `tech-debt` はレポートのみで、テストを書かない。

テストを追加する PR を出す loop が無く、`tech-debt` の `test_gap` も機械的な裏づけを持たないため、別 loop として新設する。

`test_gap` を含む `tech-debt` の推測ベースのカテゴリ(`architecture`、`security`、`operational` も同様)の扱いは、本 spec の範囲外とする。[別課題](#別課題-tech-debt-のカテゴリ設計)として記録する。

## ゴール

- スケジュール実行で、テストが不足している箇所に**テストを追加する PR**(L2)を出す。
- 言語ごとの検出アダプタを持たず、複数言語(Go、shell/Bats、将来の Terraform など)を 1 つの loop で扱う。
- 「通るだけで何も検証しないテスト」(Checker Theater)を Checker の機械的な基準で防ぐ。
- 既存の共通基盤(`loop-detect`、`loop-execute`、`loop-finalize`、state、予算、run-log)を変更せずに載せる。

## 非ゴール

- 言語別の検出アダプタ(カバレッジ形式のパース等)を detect に実装すること。
- ミューテーションテストツールの導入(Go の `go-mutesting` 等は将来の検討事項)。
- GitHub Issue の起票(`tech-debt` と同様、本 loop は Issue を作らない)。
- 既存テストの修正・削除・アサーション変更(追加のみ)。
- 本番コード(テスト対象)の修正。バグを見つけた場合は PR 本文に所見として記載するにとどめる。
- カバレッジ閾値を CI の失敗条件にすること(その失敗は `ci-sweeper` の担当)。
- Terraform のテスト(初期スコープ外)。

## 調査: 外部事例

| #   | パターン           | 代表例                                                   | 要点                                                                                                                                           |
| --- | ------------------ | -------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------- |
| A   | 自由探索型         | gh-aw Daily Test Improver、Claude Code Action の cron 例 | エージェントが build/test/coverage コマンドとギャップを自分で発見する。導入が簡単で、スタック非依存                                            |
| B   | フィルタ連鎖型     | Meta TestGen-LLM、Qodo Cover-Agent                       | build、pass、安定性、カバレッジ増加の順に候補を機械的に絞る                                                                                    |
| C   | ミュータント誘導型 | Meta ACH、TestForge、AdverTest                           | 実装を壊すとテストが落ちることを証明できたテストだけ採用する。ACH では生成テスト 571 件のうち 277 件が行カバレッジのみの基準では捨てられていた |
| D   | 分業・Issue 経由型 | gh-aw Testify Expert と下流エージェント                  | 分析と実装を別のエージェントに分ける                                                                                                           |

本 loop は **A の探索方式(エージェントに任せる)** と **B/C の検証方式(Checker が機械的に確認する)** を組み合わせる。

出典(検索結果の要約経由。数値の原典照合は未実施):

- [githubnext/agentics](https://github.com/githubnext/agentics)
- [Meet the Workflows: Testing & Validation](https://github.github.com/gh-aw/blog/2026-01-13-meet-the-workflows-testing-validation/)
- [Automated Unit Test Improvement using LLMs at Meta](https://arxiv.org/pdf/2402.09171)
- [Mutation-Guided LLM-based Test Generation at Meta](https://arxiv.org/pdf/2501.12862)
- [TestForge](https://github.com/Luz7818/testforge)
- [Claude Code GitHub Actions](https://code.claude.com/docs/en/github-actions)

## 決定事項

| 項目               | 決定                                                                                                                                                                                  | 理由                                                                                                                                                                                                                                                      |
| ------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Loop の形          | **別 loop `test-gap`**(`tech-debt` への統合は不採用)                                                                                                                                  | `tech-debt` はレポートのみを出す(write_target: report)。テストを追加する PR は性質が異なり、allowlist、Checker の基準、書き込み対象が別になる                                                                                                             |
| Loop 名 / skill 名 | `test-gap`(`loop-` プレフィックスなし)                                                                                                                                                | 既存の命名規約(`loop-engineering-design.md` の命名表)                                                                                                                                                                                                     |
| Package            | `repo-maintenance`                                                                                                                                                                    | 同じフォージ非依存のリポジトリ保守 loop 群                                                                                                                                                                                                                |
| Caller             | `.github/workflows/on-loop-test-gap.yaml`                                                                                                                                             | `on-loop-<loop_name>.yaml` 規約                                                                                                                                                                                                                           |
| レベル             | **L2 から開始**(L1 は経由しない)。`open_pr`、`may_edit: true`、`write_target` はテストファイル([Allowlist / Denylist](#allowlist--denylist) を参照)                                   | 既存 dogfood loop と同様。`tech-debt` も「L2 from start」                                                                                                                                                                                                 |
| スケジュール       | `schedule` は **週 1 回、月曜 10:00 UTC**(`0 10 * * 1`)。`workflow_dispatch` による手動実行も可能にする                                                                               | 既存は月曜 08:00(tech-debt)、09:00(docs-updater)、金曜 10:00、日曜 10:00 で、月曜 10:00 は空いている。同じ `loop-state-main` の concurrency グループで直列化される                                                                                        |
| モデル・上限       | `tech-debt` と同じ構成(maker `claude-sonnet-5`、checker `claude-opus-5`、`agent_loop_max_attempts: 3`、turns 100、`budget_max_runs_per_day: 2`、`budget_max_tokens_per_day: 1000000`) | 既存 loop と揃える。数値は運用で調整する                                                                                                                                                                                                                  |
| 対象数             | `max_targets_per_schedule: 1`、1 PR は 1 つのテスト対象に限定                                                                                                                         | レビュー負荷と予算の抑制                                                                                                                                                                                                                                  |
| 探索・選定         | **エージェントに任せる**(detect はテスト不足を判定しない)                                                                                                                             | 言語別アダプタの保守を避ける。ギャップの判断はコードを読めるエージェントの方が適する                                                                                                                                                                      |
| Detect             | **skill 同梱の薄い detect script**(言語非依存。[Detect](#detect) を参照)。`detect_script` の省略可能化(基盤の既定レスポンス)は採用しない                                              | 共通コードを変更しない。2 本目の空 detect が必要になった時点で、基盤の既定への昇格を再検討する                                                                                                                                                            |
| 台帳               | 別ファイル `.loop/state-test-gap-ledger.json`(ci-sweeper と同じ型)                                                                                                                    | 既存の `domain_persistence_script` と `additional_commit_paths` で追加でき、共通コードの改修が不要                                                                                                                                                        |
| 検証               | **テストの実行(緑、安定性、カバレッジ)は CI に任せる**。Checker は実行を伴わない静的な基準で確認する([Checker の基準](#checker-の基準agent_checker_instructions) を参照)              | loop 実行環境にはテストの実行環境が無く、push 前のため Checker は CI を確認できない([検証経路](#検証経路) を参照)                                                                                                                                         |
| CI 失敗時          | **人間が対応する**(`ci-sweeper` には拾わせない。`pr_include_bots` は変更しない)。失敗率を測定してから、拾わせる方法を再検討する                                                       | loop の PR はすべて同じ App の bot が作成するため、`pr_include_bots` に入れると全 loop の PR が `ci-sweeper` の対象になり、再帰のリスクがある([CI での検証と `ci-sweeper` の接続](#ci-での検証と-ci-sweeper-の接続) を参照)。本 loop は CI を再実行しない |

### 観測トリガーの扱い(Selection Criteria 5 への対応)

設計書の Selection Criteria 5 は「新しい loop package には独自の観測トリガーが必要」としている。本 loop は検出器を持たないため、トリガーを次のとおり**明示的に定義**する。

> 観測トリガー = スケジュール起動 + **台帳に無い対象**(未処理のテスト不足)+ git の変更頻度(churn)

台帳(処理済みの対象)を観測の一部とすることで、「前回までに処理していない箇所を選ぶ」という状態に基づく観測になる。この判断は本 spec で記録する。実装時に `loop-engineering-design.md` の Selection Criteria 近辺にも同旨を追記する。

## アーキテクチャ

### 層ごとの責務

| 層                  | 担当                                 | 内容                                                                                                                              |
| ------------------- | ------------------------------------ | --------------------------------------------------------------------------------------------------------------------------------- |
| detect              | 機械的、言語非依存                   | `skip: false` と参考事実(churn ホットスポット、台帳の要約)を出す。「テストが足りない」とは判定しない                              |
| Maker(エージェント) | 任せる                               | スタックの特定、テスト/カバレッジコマンドの発見、台帳に無い対象の選定、テスト作成                                                 |
| Maker の出力        | 必須                                 | 選んだ対象と理由、想定される検証コマンドと期待結果。台帳に追記する。テストを実行できない環境では、実行していない結果を記載しない  |
| Checker             | 静的、言語非依存                     | allowlist 順守、既存アサーション不変、テストが実装の挙動を検証しているか、台帳との整合、PR 本文の記載                             |
| CI                  | PR 後に実行                          | 緑、安定性、カバレッジ。落ちた場合は人間が対応する                                                                                |
| 言語固有の知識      | caller の `agent_maker_instructions` | Go は `go-validation`、shell は `shell-script-validation`(Bats、TEST-00)を参照させる。ci-sweeper の Stack routing (A') と同じ方式 |

### Detect

- `detect_script` は skill 同梱の薄いスクリプト(`.agents/skills/test-gap/scripts/detect_test_gap.sh`)とする。
- 契約は既存どおり: `--scope range --since <ref>` を受け付け、JSON を出力する。`loop-detect` が必須とするのは `skip` が boolean であること(`detect.sh:726`)のみ。
- 出力: `skip: false`、`since`、`commit_range`、`hotspots[]`(`TECH_DEBT_CHURN_*` と同様の git churn)、`ledger`(処理済み対象の要約)、`warnings[]`。
- 言語やテストの有無は判定しない。
- 重複 PR の抑制、予算、サーキットブレーカーは基盤が担当する(`target_pending_blocks_detect`、`budget_exceeded`、`target_circuit_breaker_open`)。

#### 最小レスポンスの検証結果

`{"skip":false}` と、`since`、`commit_range`、`hotspots[]`、`warnings[]` を足した形の 2 通りで、`loop-detect` の次の関数を実際に呼んで確認した(2026-10-11)。

| 関数                                              | 結果                                                                  |
| ------------------------------------------------- | --------------------------------------------------------------------- |
| `detect_result_skip`                              | `skip: false` と判定される                                            |
| `enrich_target_json_with_ci_context`              | `.failures[0]` が無いため、`target_json` を変更せずに返す             |
| `enrich_target_json_with_detect_fields`           | `report_file` が空のため、`target_json` を変更せずに返す              |
| `build_verifier_context_from_result`              | `failures` と `commits` が無いため、空文字を返す                      |
| `since` / `commit_range` の取得(`detect.sh:1142`) | `{"skip":false}` のみだと空になる。`since` を出力した場合は取得される |

欠落フィールドで失敗する経路は見つからなかった。ただし、確認したのは上記の関数単体で、`loop-detect` 全体の実行(checkout、state、matrix 組み立て)は行っていない。実装時に、`test/bats/.github/actions/loop-detect/` 配下の既存の Bats に、`detect_test_gap.sh` の出力を使うケースを追加して担保する。

### 台帳(ledger)

- ファイル: `.loop/state-test-gap-ledger.json`
- 書き込み: caller の `domain_persistence_script`(`update_test_gap_ledger.sh`)と `additional_commit_paths`。`ci-sweeper` の `update_run_ledger.sh`(`.loop/state-ci-sweeper-run-ledger.json`)と同じ構造。
- 内容(案): 対象ごとの `path`、`stack`、`processed_at`、`outcome`、`pr`。30 日などの保持期間で prune する(ci-sweeper の台帳に倣う)。
- `write_state.sh` が扱うのは `targets[key]` の `last_sha`、`pending`、メタデータのみで、独自キーの書き込み口は無い。そのため台帳は state 本体と別ファイルにする。

### Allowlist / Denylist

本リポジトリ(config)のテストは `test/` 配下に集約されている(確認結果: `test/bats/`(Bats、対象のパスを鏡写しにした構成)、`test/go/`(Go の `*_test.go`)、`test/fixtures/`)。

- allowlist(本リポジトリの caller): `test/**`
- denylist: caller では省略し、プラットフォーム既定(`lib/paths.sh` の `DEFAULT_EXECUTE_DENYLIST`)を使う。`ci-sweeper` の caller も同じ方式。
- consumer リポジトリは、自身のテストレイアウトに合わせて `allowlist` を指定する(例: Go の `**/*_test.go`)。reusable に consumer 固有のパスを入れない(`.github/workflows/CLAUDE.md` の Portability 規則)。

### Checker の基準(`agent_checker_instructions`)

Checker は CI を確認できず、テストも実行できないため、**差分と PR 本文だけで判定できる静的な基準**に限る。`loop-verifier` の「CI や linter を再実行しない」方針(loop-verifier SKILL.md(`.apm/packages/loop/.apm/skills/loop-verifier/SKILL.md`))と整合する。

APPROVE には次の**すべて**が必要:

1. 変更が allowlist 内に限られ、denylist に触れていない。
2. 既存のテストの削除、スキップ、コメントアウト、アサーションの弱体化が無い。
3. 追加したテストが、テスト対象の実装の挙動(戻り値、副作用、エラー経路)を検証している。
4. 欠落していた対象(テストの無い関数やスクリプト、Bats ペアリング(TEST-00))に対応するテストである。
5. 台帳に既出の対象でない、または再選択の新しい理由が記載されている。
6. PR に対象、理由、想定される検証コマンド、期待される結果が記載されている(実測値ではなく、CI が検証する前提の記載)。

次のいずれかで REJECT:

- 追加したテストが実装の挙動を検証していない(戻り値を使わない、常に真になる、モックだけを検証するなど)。
- 本番コードの変更、または denylist パスの変更。
- 台帳に既出の対象を、新しい理由なしに再度選んでいる。
- 実行していないテスト結果を「実行した」と主張している。

**限界:** 「実装を壊すとテストが落ちる」(ミュータント確認)と「カバレッジが増える」は、実行環境が無いため Checker では確認できない。Checker Theater の抑止力は、実行ベースの検証より弱い。緑かどうかは CI が、品質の深い確認は人間のレビューが担う。

### Caller `on-loop-test-gap.yaml`(骨子)

`on-loop-tech-debt.yaml` を雛形にする(キーはアルファベット順、ORD-01 に準拠)。

- `loop_name: test-gap`、`agent_maker_skill_name: test-gap`、`agent_checker_skill_name: loop-verifier`
- トリガー: `schedule`(`cron: "0 10 * * 1"`、`timezone: Etc/UTC`)と `workflow_dispatch: {}`
- `level: L2`、`may_edit: true`、`delivery: open_pr`、`pr_enabled: false`、`branch_match: main`、`branch_state: main`
- `allowlist: test/**`(denylist はプラットフォーム既定)
- `max_targets_per_schedule: 1`、`budget_max_runs_per_day` と `budget_max_tokens_per_day` を設定
- `no_changes_verdict: REJECT`
- `domain_persistence_script` と `additional_commit_paths` で台帳を更新
- `concurrency` は他の loop と同じ `loop-state-main` グループ(`queue: max`)

## 影響範囲と変更チェックリスト

`loop-capable-skills.md` の「Cross-cutting edit checklist」に従い、同じ変更セットで更新する。

- skill: `.apm/packages/repo-maintenance/.apm/skills/test-gap/`(`SKILL.md`、`scripts/detect_test_gap.sh`、`scripts/update_test_gap_ledger.sh`、`references/`、`assets/pr-body-template*.md`)。編集は `.apm/packages/` 配下のみ。`.agents/` などは `apm install` で同期する(CLAUDE.md の Edit routing)。
- caller: `.github/workflows/on-loop-test-gap.yaml`
- インストールドリフト一覧: `scripts/self/apm/check_apm_skill_install_drift.sh` の `LOOP_SKILLS`
- PR 本文契約: `scripts/self/apm/check_loop_pr_body_contract.sh`、`references/category-pr-body-links.md`
- ドキュメント: `loop-capable-skills.md`(Loop entry skills 表)、`loop-engineering-design.md`(ステータス表、ロードマップ、Selection Criteria 5 への記述)、`architecture.md`、`specification.md`、新規 `workflows/loop-test-gap-workflow-design.md`、`loop-caller-inputs-reference.md`、ミューテーション確認の方針
- テスト: Bats(`test/bats/`)に detect と台帳更新スクリプトのテストを追加する(AGENTS.md の Test-first と TEST-00)。
- 権限パリティ: 新しいコマンドを許可する場合のみ、CLAUDE.md の「Permission parity」の 4 ファイルを同じコミットで更新する。
- 共通コード(`loop-detect`、`loop-execute`、`loop-finalize`)は**変更しない**。

## リスクと緩和

| リスク                                | 緩和                                                                                                                                                                                                                                                |
| ------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Checker Theater(無意味なテストの通過) | 静的基準(挙動の検証、既存アサーション不変、REJECT 条件)と CI。実行ベースの確認は無いため抑止力は弱く、人間のレビューが最終防衛線                                                                                                                    |
| CI で落ちる PR が出る                 | 人間が修正または close する。失敗率を測定し、`ci-sweeper` に拾わせる方法は運用データを見てから再検討する。連続して失敗する場合はサーキットブレーカーで停止する。落ちた PR が残る間は、基盤の `pending` ブロックにより同じ target の次回実行は止まる |
| 毎回同じ対象を選ぶ                    | 台帳 + Checker による再選択の REJECT                                                                                                                                                                                                                |
| 重複 PR                               | 基盤の `pending` ブロック                                                                                                                                                                                                                           |
| トークンの浪費(探索が非決定的)        | `max_targets_per_schedule: 1`、日次予算、`agent_maker_max_turns` の上限                                                                                                                                                                             |
| 言語ごとの品質差                      | caller の `agent_maker_instructions` で言語別の参照 skill を指定。最初は shell(Bats)に絞って導入する                                                                                                                                                |
| スケジュールが空振りする              | `no_changes_verdict: REJECT` と台帳の outcome 記録。連続失敗はサーキットブレーカーが止める                                                                                                                                                          |

## 検証経路

loop の実行ジョブ(`loop-execute`)が導入するのは Node(`setup-node`)、uv(`setup-uv`)、エンジンの CLI のみで、Go、shellcheck、bats などの導入は確認できなかった。Bash の実行権限も、caller が `agent_allowed_tools` で渡した場合に限られる(`ci-sweeper` と issue 系は定義し、`tech-debt` と `refactor` は定義していない)。ランナーのプリインストールの有無は未確認。push 前のため CI の結果も参照できない。

| 案  | 内容                                                                             | 判断                                                             |
| --- | -------------------------------------------------------------------------------- | ---------------------------------------------------------------- |
| 1   | loop ジョブに言語ツールを導入し、Maker と Checker が実際にテストを実行する       | **拡張**。[ツール導入 action](#ツール導入-action拡張) で実現する |
| 2   | PR を出し、検証は CI に任せる。Checker は静的な基準のみ。CI 失敗は人間が対応する | **採用(初期)**                                                   |
| 3   | Maker にのみツールを用意して自己検証させ、Checker は実行ログを証拠にする         | 不採用。ログの真正性が弱い                                       |

### CI での検証と `ci-sweeper` の接続

案 2 は、test-gap の PR で CI が走ることが前提になる。失敗への対応は、`ci-sweeper` に拾わせず人間が行う(方針 B、2026-10-11 決定)。判断の根拠として、次を調査した。

| 確認項目                 | 結果                                                                                                                                                                                                                                |
| ------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| テストを実行する CI      | `on-ci-push-shell-script`(Bats を含む。`push` と `pull_request` の両方で起動)。Go のテストを実行する `on-ci-push-*` caller は、このリポジトリには無い(`ci-go.yaml` は reusable のみ)                                                |
| PR の CI が起動する条件  | PR の作成に使うトークン次第。`loop-resolve-push-token` は GitHub App のトークンを優先し、無ければ `GITHUB_TOKEN` にフォールバックする。`GITHUB_TOKEN` で作った PR は CI を起動しない(GitHub の仕様)。App が設定されていれば起動する |
| `ci-sweeper` の起動      | `workflow_run`(`on-ci-push-*` など 7 本、`completed`)。head リポジトリが同一かつ `failure` / `startup_failure` のとき                                                                                                               |
| bot の PR を対象にするか | **既定では対象外**。`pr_excluded`(`prs.sh`)は、作者の login が `bot` で終わる PR を、`pr_include_bots` に含まれない限り除外する。`on-loop-ci-sweeper.yaml` は `pr_include_bots: ""` で、全 bot を除外している                       |

「`ci-sweeper` が test-gap の PR の CI 失敗を拾う」には、`on-loop-ci-sweeper.yaml` の `pr_include_bots` に、PR 作成者の login を追加する必要がある。しかし次の理由で、**初期は追加しない(方針 B)**。

**作者 login の実値(確認済み、2026-10-11):** `gh pr list --json author` は、loop の PR(例: #936 `loop/github-issue-autofix/...`、#910 `loop/tech-debt/...`)の作者を `app/y-miyazaki-repo-maintenance-bot`(`is_bot: true`)と返す。`pr_include_bots` はこの文字列との完全一致で判定する(`prs.sh` の `[[ ${author_login} == "${bot}" ]]`)。

**bot 除外の理由(調査結果):**

- `prs.sh` のコメントは、bot 除外を「スケジュール起動の loop が、Renovate、Dependabot、**loop 自身の PR** を勝手に拾わないための走査上のヒューリスティック」としている。
- `loop-ci-sweeper-workflow-design.md` は、依存更新(bot の PR)の修復を domain skill ができるまで先送り(defer B)とし、dogfood では `pr_include_bots: ""` としている。
- 再帰の抑止は、`workflow_run.workflows` の allowlist、run ledger(`workflow_run_id`)、日次予算で行うと記載がある。bot 除外が再帰防止のためとは明記されていない。

**追加しない理由:** loop の PR はすべて同じ App の bot が作成する(`tech-debt`、`github-issue-autofix`、run-log の PR など)。`app/y-miyazaki-repo-maintenance-bot` を `pr_include_bots` に入れると、test-gap だけでなく、`ci-sweeper` 自身の修正 PR を含む全 loop の PR が `ci-sweeper` の対象になり、再帰(修正 PR の CI 失敗 → さらに修正 PR)のリスクが増える。ledger、予算、サーキットブレーカー、`pending` ブロックで抑止できるかは未検証。

**検討した選択肢:**

| 案  | 内容                                                                             | 判断                                                                  |
| --- | -------------------------------------------------------------------------------- | --------------------------------------------------------------------- |
| A   | `app/y-miyazaki-repo-maintenance-bot` を `pr_include_bots` に追加                | 不採用(再帰のリスクが未検証)                                          |
| B   | `pr_include_bots` は変えず、CI 失敗は人間が対応する                              | **採用(初期)**                                                        |
| C   | PR にラベル(例: `test-gap`)を付け、`ci-sweeper` がラベルで絞り込めるよう拡張する | 共通コード(`prs.sh` など)の変更が必要。運用データを見てから再検討する |

運用中は、test-gap の PR のうち CI が失敗した割合を記録し、A または C に進む判断材料にする。

また、`on-ci-push-*` の対象が `paths`(例: `**/*.sh`、`**/*.bats`)で絞られているため、Go のテスト変更を検証する CI が無い。フェーズ 2(Go の追加)の前に、Go のテストを実行する caller が必要になる。

### ツール導入 action(拡張)

案 1 を実現する手段として、リポジトリに mise または aqua の設定がある場合に、そのツールを導入する action を用意する。

- **形:** 新しい leaf composite(仮称 `loop-setup-tools`)を追加し、`ci-loop-agent.yaml` の execute ジョブから `uses:` で呼ぶ。`.github/workflows/CLAUDE.md` の Composition 規則(composite から composite を呼ばない、workflow から leaf composite を `uses:` で呼ぶ)に従う。
- **入力:** `tools_setup`(`none` / `auto` / `mise` / `aqua`)、`mise_version`、`aqua_version`。`tools_setup` の既定は `none` にして、既存 loop の挙動を変えない。
- **`auto` の判定:** リポジトリに `mise.toml`、`.mise.toml`、`.tool-versions` のいずれかがあれば mise、`aqua.yaml` があれば aqua。これらはツールの規約上のファイル名で、consumer 固有のディレクトリではない。ただし `.github/workflows/CLAUDE.md` の「Consumer layout を reusable に埋め込まない」規則に抵触しないか、実装時にレビューする。
- **mise:** `jdx/mise-action` を使う(第三者 action のため SHA で固定)。`install_args` で、必要なツールだけを指定できる。`add_shims_to_path`(既定 true)で shim が PATH に入り、lazy のツールは初回の呼び出しで導入される。lazy の shim 作成に `reshim` 入力が必要かは**未確認**。
- **aqua:** `aquaproj/aqua-installer` を想定するが、入力仕様は**未確認**。リポジトリ内で利用実績が無い。
- **バージョンの指定と Renovate:** `mise_version`、`aqua_version` は inputs の `default:` に置く。`renovate/github-actions-tool-version.json` の既存の正規表現(`mise_version:\s*\n\s*default:\s*...`)が mise に一致する。aqua には対応する正規表現が無く、追加が必要。caller の `with:` に値を直書きしない(`with:` の直書きは正規表現に一致せず、更新が止まる。`mise_version` で実際に起きた)。
- **Bash の権限:** 導入しても、エージェントがテストを実行するには `agent_allowed_tools` で Bash の実行権限を caller が渡す必要がある。
- **mise の要件:** lazy は mise 2026.9.0 以降。reusable の `mise_version` の default を満たす版に保つ。
- **位置づけ:** 初期(案 2)では `none` のまま運用し、CI 失敗率を測定してから、caller で `auto` に切り替えるかを判断する。

### mise.toml の lazy 化(実施済み)

- 本リポジトリの `mise.toml` は、ランタイム(`aqua`、`node`、`pnpm`、`python`)、`uv`、`npm:awsp` を除く 56 ツールに `lazy = true` と `lazy_bins` を指定した。`mise install` は lazy のツールを導入せず、コマンドの初回実行時に導入される。`init.sh` と `mise-install` タスクは `mise install` のままで、`--include-lazy` は使わない。
- 隔離環境で、`mise install` が lazy を導入しないこと、`mise reshim` で shim が作られること、初回実行で aqua(`shellcheck`)、npm(`markdownlint-cli2`)、pipx(`yamllint`)、github(`apm`)のツールが導入されて動くことを確認した。go バックエンド(`dlv`、`gopls` など)と、`postinstall`(`mkdocs`)、`allow_builds`(`lean-ctx-bin`)付きのツールの lazy 動作は未確認。
- `lazy_bins` は、registry の短縮名以外のツールでは必須(未指定だと shim が作られず、警告が出る)。
- `mise_version` は `ci-mise-update-lock.yaml` の inputs の default で指定し、Renovate が更新する。caller の `with:` では指定しない。

## 別課題: tech-debt のカテゴリ設計

`tech-debt` のカテゴリのうち、センサーに裏づけられているのは `dependency_version`、`documentation`、`code_quality`(マーカーと churn)のみで、`test_gap`、`architecture`、`security`、`operational` はエージェントの推測に依存している。レポートが各カテゴリを網羅的に、機械的な事実に基づいて見ているとは言えない。センサーの追加(例: テストの無いパッケージ、Bats ペアリング欠落の機械的検出)、または推測カテゴリの扱いの見直しを、本 spec とは別の課題として扱う。

## 段階導入

1. **フェーズ 1:** shell/Bats のみ(TEST-00 の欠落は二値で明確。Checker Theater のリスクが低い)。
2. **フェーズ 2:** Go を追加する。caller の instructions と Checker の言語別追記のみで、loop は増やさない。
3. **フェーズ 3:** CI 失敗率を測定したうえで、[検証経路](#検証経路)の案 1(実行環境の導入、mise の lazy install など)を検討する。

## 未決事項(確認が必要)

1. **PR の CI が起動するか。** `loop-resolve-push-token` が App のトークンで PR を作成する構成(`MAINTENANCE_BOT_APP_*`)かを、実際の PR で確認する。`GITHUB_TOKEN` へのフォールバックでは CI が起動しない。
2. **Go のテストを実行する CI。** フェーズ 2 の前に、Go のテストを実行する `on-ci-push-*` caller が必要。
3. **ツール導入 action の未確認事項。** lazy の shim 作成に `reshim` 入力が必要か、`aquaproj/aqua-installer` の入力仕様、`auto` の判定が Portability 規則に抵触しないか。
4. **mise の lazy の未確認範囲。** go バックエンド、`postinstall`、`allow_builds` 付きのツール、`init.sh` の `mise prune` との相互作用。

### 確定済み(2026-10-11)

| 項目                 | 決定                                                                      |
| -------------------- | ------------------------------------------------------------------------- |
| detect の置き場所    | skill 同梱の薄い detect                                                   |
| 最小レスポンスの耐性 | 関連関数で確認済み([最小レスポンスの検証結果](#最小レスポンスの検証結果)) |
| L1 の経由            | 経由しない(L2 から)                                                       |
| allowlist            | `test/**`(本リポジトリ)                                                   |
| スケジュール         | 月曜 10:00 UTC + `workflow_dispatch`                                      |
| モデル構成           | `tech-debt` と同じ                                                        |
| CI 失敗時の対応      | 人間が対応する(方針 B)。`pr_include_bots` は変更しない                    |
| PR 作成者の login    | `app/y-miyazaki-repo-maintenance-bot`(確認済み)                           |
