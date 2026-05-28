<!-- omit in toc -->
# AWS Service Comparison Matrix (Batch)

バッチ処理・ジョブ実行サービスの選定判断材料。

## History

| 日付       | 内容     |
| ---------- | -------- |
| 2026-05-28 | 初版作成 |

<!-- omit in toc -->
## Table of Contents

- [History](#history)
- [Batch Processing: AWS Batch vs ECS Scheduled Task vs Step Functions vs Lambda](#batch-processing-aws-batch-vs-ecs-scheduled-task-vs-step-functions-vs-lambda)
  - [Guidelines](#guidelines)
- [Workflow Orchestration: Step Functions vs MWAA (Airflow) vs EventBridge Scheduler](#workflow-orchestration-step-functions-vs-mwaa-airflow-vs-eventbridge-scheduler)
  - [Guidelines](#guidelines-1)

## Batch Processing: AWS Batch vs ECS Scheduled Task vs Step Functions vs Lambda

| 比較項目             | AWS Batch                                            | ECS Scheduled Task                                   | Step Functions                                       | Lambda                                               |
| -------------------- | ---------------------------------------------------- | ---------------------------------------------------- | ---------------------------------------------------- | ---------------------------------------------------- |
| サービスカテゴリ     | Batch Computing                                      | Container Scheduling                                 | Workflow Orchestration                                | FaaS                                                 |
| ドキュメント         | [Batch](https://docs.aws.amazon.com/batch/)          | [ECS](https://docs.aws.amazon.com/ecs/)              | [Step Functions](https://docs.aws.amazon.com/step-functions/) | [Lambda](https://docs.aws.amazon.com/lambda/)        |
| 課金モデル           | 基盤リソース (Fargate/EC2) のみ                      | Fargate/EC2 課金                                     | 状態遷移課金 ($0.025/1000 遷移)                      | リクエスト + 実行時間                                |
| マネージド度         | 高い (ジョブキュー・スケジューリング自動)            | 中程度 (EventBridge ルール設定必要)                  | 非常に高い                                           | 非常に高い                                           |
| 主用途               | 大量並列バッチ、HPC                                  | 定期実行コンテナタスク                               | 複数ステップのワークフロー                           | 軽量イベント駆動処理                                 |
| 最大実行時間         | 無制限                                               | 無制限                                               | 1 年 (Standard) / 5 分 (Express)                     | 15 分                                                |
| 並列実行             | ✅ Array Job (数千並列)                               | ⚠️ (タスク数手動指定)                                 | ✅ Map State (最大 10,000)                             | ✅ (同時実行数制御)                                    |
| ジョブ依存関係       | ✅ (ジョブ間依存定義)                                 | ❌                                                    | ✅ (ステート間遷移)                                    | ❌ (単体実行)                                         |
| リトライ             | ✅ (自動リトライ + 戦略設定)                          | ⚠️ (EventBridge リトライ)                             | ✅ (Retry/Catch 定義)                                  | ⚠️ (非同期呼び出し時のみ)                             |
| スケジュール実行     | ❌ (EventBridge 連携で可能)                           | ✅ (EventBridge ルール)                               | ✅ (EventBridge 連携)                                  | ✅ (EventBridge 連携)                                  |
| GPU サポート         | ✅                                                    | ✅ (EC2 起動タイプ)                                   | ❌ (呼び出し先に依存)                                 | ❌                                                    |
| Spot 利用            | ✅ (Spot Fleet 自動管理)                              | ✅ (Fargate Spot)                                     | - (呼び出し先に依存)                                 | -                                                    |
| エラーハンドリング   | ジョブ単位リトライ                                   | タスク単位                                           | Catch/Retry で詳細制御                               | DLQ                                                  |
| 可観測性             | CloudWatch Logs + メトリクス                         | CloudWatch Logs + メトリクス                         | 実行履歴 + X-Ray                                     | CloudWatch Logs + X-Ray                              |
| Terraform 対応       | ✅                                                    | ✅                                                    | ✅                                                    | ✅                                                    |

### Guidelines

**→ ワークロード特性に応じて使い分ける。** 単一の推奨はなく、以下の判定基準で選定する。

- 定期実行の単一コンテナタスク → ECS Scheduled Task (ecschedule で管理)
- 複数ステップの依存関係があるワークフロー → Step Functions
- 大量並列 (数百〜数千) のバッチ処理、GPU/HPC → AWS Batch
- 15 分以内で完了する軽量イベント駆動処理 → Lambda
- Step Functions + Lambda/ECS の組み合わせで複雑なバッチパイプラインを構築するパターンが最も汎用的

## Workflow Orchestration: Step Functions vs MWAA (Airflow) vs EventBridge Scheduler

| 比較項目             | Step Functions                                       | MWAA (Airflow)                                       | EventBridge Scheduler                                |
| -------------------- | ---------------------------------------------------- | ---------------------------------------------------- | ---------------------------------------------------- |
| サービスカテゴリ     | Workflow Orchestration                                | Workflow Orchestration                                | Job Scheduler                                        |
| ドキュメント         | [Step Functions](https://docs.aws.amazon.com/step-functions/) | [MWAA](https://docs.aws.amazon.com/mwaa/)           | [Scheduler](https://docs.aws.amazon.com/scheduler/)  |
| 課金モデル           | 状態遷移課金                                         | 環境時間課金 (最小 $0.49/h)                          | 呼び出し課金 ($1/100万)                              |
| マネージド度         | 非常に高い                                           | 高い (Airflow 環境管理)                              | 非常に高い                                           |
| 主用途               | AWS サービス連携ワークフロー                         | データパイプライン、複雑な DAG                       | 単一ターゲットの定期呼び出し                         |
| ワークフロー定義     | ASL (JSON/YAML)                                      | Python DAG                                           | スケジュール式 (cron/rate)                           |
| 学習コスト           | 中程度                                               | 高い (Airflow 知識必要)                              | 低い                                                 |
| DAG 複雑度           | 中程度 (分岐・並列・Map)                             | 高い (任意の DAG 構造)                               | なし (単一ターゲット)                                |
| AWS サービス統合     | ✅ 200+ サービス直接呼び出し                          | ⚠️ (Operator/Hook 経由)                               | ✅ 270+ ターゲット                                    |
| 外部システム連携     | ⚠️ (Lambda/ECS 経由)                                  | ✅ (豊富な Provider)                                   | ⚠️ (API Destination 経由)                             |
| UI/可視化            | ✅ コンソール実行グラフ                               | ✅ Airflow Web UI                                     | ❌ (スケジュール一覧のみ)                             |
| バックフィル         | ❌                                                    | ✅                                                    | ❌                                                    |
| 最小コスト           | $0 (使った分だけ)                                    | ~$350/月 (最小環境)                                  | $0 (使った分だけ)                                    |
| Terraform 対応       | ✅                                                    | ✅                                                    | ✅                                                    |

### Guidelines

**→ Step Functions を標準採用する。** AWS サービスとの直接統合が豊富で、サーバーレスかつ従量課金のためコスト予測が容易。

- データパイプラインで複雑な DAG、バックフィル、外部システム連携が多い場合は MWAA を検討
- 単一ターゲットの定期呼び出し (cron ジョブ) は EventBridge Scheduler で十分
- MWAA は最小コストが高いため、小規模チームでは Step Functions + EventBridge Scheduler の組み合わせを推奨
