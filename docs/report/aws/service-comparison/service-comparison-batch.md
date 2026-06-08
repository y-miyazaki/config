<!-- omit in toc -->
# AWS Service Comparison Matrix (Batch)

バッチ処理・ジョブ実行サービスの選定判断材料。

<!-- omit in toc -->
## History

| 日付       | 内容     |
| ---------- | -------- |
| 2026-05-28 | 初版作成 |

<!-- omit in toc -->
## Table of Contents

- [Batch Processing: AWS Batch vs ECS Scheduled Task vs Step Functions vs Lambda](#batch-processing-aws-batch-vs-ecs-scheduled-task-vs-step-functions-vs-lambda)
  - [Guidelines](#guidelines)
- [Workflow Orchestration: Step Functions vs MWAA (Airflow) vs EventBridge Scheduler](#workflow-orchestration-step-functions-vs-mwaa-airflow-vs-eventbridge-scheduler)
  - [Guidelines](#guidelines-1)

## Batch Processing: AWS Batch vs ECS Scheduled Task vs Step Functions vs Lambda

| 比較項目             | AWS Batch                                            | ECS Scheduled Task                                   | Step Functions                                       | Lambda                                               |
| -------------------- | ---------------------------------------------------- | ---------------------------------------------------- | ---------------------------------------------------- | ---------------------------------------------------- |
| ドキュメント         | [Batch](https://docs.aws.amazon.com/batch/)          | [ECS](https://docs.aws.amazon.com/ecs/)              | [Step Functions](https://docs.aws.amazon.com/step-functions/) | [Lambda](https://docs.aws.amazon.com/lambda/)        |
| 課金モデル           | 基盤リソース (Fargate/EC2) のみ ([料金](https://aws.amazon.com/batch/pricing/)) | Fargate/EC2 課金 ([料金](https://aws.amazon.com/fargate/pricing/)) | 状態遷移 $0.025/1000 ([料金](https://aws.amazon.com/step-functions/pricing/)) | リクエスト + 実行時間 ([料金](https://aws.amazon.com/lambda/pricing/)) |
| 主用途               | 大量並列バッチ、HPC                                  | 定期実行コンテナタスク                               | 複数ステップのワークフロー                           | 軽量イベント駆動処理                                 |
| SLA                  | 99.99%                                               | 99.99% (ECS SLA)                                     | 99.99%                                               | 99.95%                                               |
| 学習コスト           | 中程度                                               | 低い (ECS + EventBridge)                             | 中程度 (ASL 定義)                                    | 低い                                                 |
| スケーリング         | 自動 (ジョブキュー + Compute Environment)            | タスク数手動指定                                     | Map State (最大 10,000 並列)                          | 自動 (同時実行数制御)                                |
| 主要サービス制限     | ジョブキュー 50/アカウント ([Quotas](https://docs.aws.amazon.com/batch/latest/userguide/service_limits.html)) | ECS サービス制限に準拠 ([Quotas](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/service-quotas.html)) | ペイロード 256KB、実行履歴 25,000 イベント、Standard 1年/Express 5分 ([Quotas](https://docs.aws.amazon.com/step-functions/latest/dg/limits-overview.html)) | 実行時間 15分、ペイロード 6MB、同時実行 1000 ([Quotas](https://docs.aws.amazon.com/lambda/latest/dg/gettingstarted-limits.html)) |
| コスト (常時高負荷)  | 安い (Spot 活用)                                     | 中程度                                               | 遷移数依存                                           | 高い                                                 |
| コスト (バースト)    | 安い (使った分だけ + Spot)                           | 中程度                                               | 安い (従量課金)                                      | 安い (従量課金)                                      |
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
| ドキュメント         | [Step Functions](https://docs.aws.amazon.com/step-functions/) | [MWAA](https://docs.aws.amazon.com/mwaa/)           | [Scheduler](https://docs.aws.amazon.com/scheduler/latest/UserGuide/what-is-scheduler.html)  |
| 課金モデル           | 状態遷移課金 ([料金](https://aws.amazon.com/step-functions/pricing/)) | 環境時間 最小 $0.49/h ([料金](https://aws.amazon.com/managed-workflows-for-apache-airflow/pricing/)) | 呼び出し $1/100万 ([料金](https://aws.amazon.com/eventbridge/pricing/)) |
| 主用途               | AWS サービス連携ワークフロー                         | データパイプライン、複雑な DAG                       | 単一ターゲットの定期呼び出し                         |
| SLA                  | 99.99%                                               | 99.9%                                                | 99.99%                                               |
| 学習コスト           | 中程度 (ASL 定義)                                    | 高い (Airflow 知識必要)                              | 低い                                                 |
| スケーリング         | 自動 (状態遷移数に応じて)                            | Worker Auto Scaling                                  | 自動 (スケジュール数に応じて)                        |
| 主要サービス制限     | ペイロード 256KB、Standard 1年/Express 5分、状態遷移 25,000/実行 ([Quotas](https://docs.aws.amazon.com/step-functions/latest/dg/limits-overview.html)) | DAG 数/Worker 数は環境クラスに依存 ([Quotas](https://docs.aws.amazon.com/mwaa/latest/userguide/mwaa-quotas.html)) | スケジュール数 1,000,000/アカウント/リージョン ([Quotas](https://docs.aws.amazon.com/scheduler/latest/UserGuide/scheduler-quotas.html)) |
| コスト (常時高負荷)  | 遷移数依存 (Express で安い)                          | 高い (~$350/月〜)                                    | 安い                                                 |
| コスト (バースト)    | 安い (従量課金)                                      | 高い (環境常時課金)                                  | 安い (従量課金)                                      |
| ワークフロー定義     | ASL (JSON/YAML)                                      | Python DAG                                           | スケジュール式 (cron/rate)                           |
| DAG 複雑度           | 中程度 (分岐・並列・Map)                             | 高い (任意の DAG 構造)                               | なし (単一ターゲット)                                |
| AWS サービス統合     | ✅ 200+ サービス直接呼び出し                          | ⚠️ (Operator/Hook 経由)                               | ✅ 270+ ターゲット                                    |
| 外部システム連携     | ⚠️ (Lambda/ECS 経由)                                  | ✅ (豊富な Provider)                                   | ⚠️ (API Destination 経由)                             |
| UI/可視化            | ✅ コンソール実行グラフ                               | ✅ Airflow Web UI                                     | ❌ (スケジュール一覧のみ)                             |
| バックフィル         | ❌                                                    | ✅                                                    | ❌                                                    |
| Terraform 対応       | ✅                                                    | ✅                                                    | ✅                                                    |

### Guidelines

**→ Step Functions を標準採用する。** AWS サービスとの直接統合が豊富で、サーバーレスかつ従量課金のためコスト予測が容易。

- データパイプラインで複雑な DAG、バックフィル、外部システム連携が多い場合は MWAA を検討
- 単一ターゲットの定期呼び出し (cron ジョブ) は EventBridge Scheduler で十分
- MWAA は最小コストが高いため、小規模チームでは Step Functions + EventBridge Scheduler の組み合わせを推奨
