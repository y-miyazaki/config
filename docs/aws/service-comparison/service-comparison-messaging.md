<!-- omit in toc -->
# AWS Service Comparison Matrix (Messaging)

メッセージング・キューサービスの選定判断材料。

## History

| 日付       | 内容     |
| ---------- | -------- |
| 2026-05-28 | 初版作成 |

<!-- omit in toc -->
## Table of Contents

- [History](#history)
- [Queue: SQS vs Kinesis Data Streams vs MSK (Kafka)](#queue-sqs-vs-kinesis-data-streams-vs-msk-kafka)
  - [Guidelines](#guidelines)
- [Event Bus: EventBridge vs SNS vs SQS](#event-bus-eventbridge-vs-sns-vs-sqs)
  - [Guidelines](#guidelines-1)

## Queue: SQS vs Kinesis Data Streams vs MSK (Kafka)

| 比較項目             | SQS                                                  | Kinesis Data Streams                                 | MSK (Kafka)                                          |
| -------------------- | ---------------------------------------------------- | ---------------------------------------------------- | ---------------------------------------------------- |
| サービスカテゴリ     | Message Queue                                        | Data Streaming                                       | Data Streaming (Kafka)                               |
| ドキュメント         | [SQS](https://docs.aws.amazon.com/sqs/)              | [Kinesis](https://docs.aws.amazon.com/streams/latest/dev/) | [MSK](https://docs.aws.amazon.com/msk/)             |
| 課金モデル           | リクエスト課金 ($0.40/100万)                         | シャード時間 + PUT 課金                              | ブローカー時間 + ストレージ                          |
| マネージド度         | 非常に高い                                           | 高い                                                 | 中程度 (Kafka 運用知識必要)                          |
| 主用途               | 非同期タスクキュー、デカップリング                   | リアルタイムデータストリーミング                     | 大規模イベントストリーミング                         |
| 配信モデル           | Pull (ポーリング)                                    | Pull (シャードイテレータ)                            | Pull (Consumer Group)                                |
| 順序保証             | ⚠️ (FIFO キューで保証、Standard は Best Effort)       | ✅ (シャード内で保証)                                 | ✅ (パーティション内で保証)                           |
| 重複排除             | ✅ (FIFO キュー)                                      | ❌ (アプリ側で対応)                                   | ❌ (アプリ側で対応)                                   |
| メッセージ保持       | 最大 14 日                                           | 最大 365 日                                          | 無制限 (Tiered Storage)                              |
| メッセージサイズ     | 256 KB (拡張で 2 GB via S3)                          | 1 MB                                                 | 1 MB (設定変更可)                                    |
| スループット         | 実質無制限 (Standard)、3,000 msg/s (FIFO)            | シャードあたり 1 MB/s 書込、2 MB/s 読取             | ブローカースペック依存                               |
| 複数コンシューマー   | ❌ (1メッセージ1コンシューマー)                       | ✅ (Enhanced Fan-Out)                                 | ✅ (Consumer Group)                                   |
| リプレイ             | ❌ (消費後削除)                                       | ✅ (任意時点から再読み取り)                           | ✅ (オフセット指定)                                   |
| Lambda 統合          | ✅ (Event Source Mapping)                             | ✅ (Event Source Mapping)                             | ✅ (Event Source Mapping)                             |
| DLQ                  | ✅                                                    | ❌ (アプリ側で対応)                                   | ❌ (アプリ側で対応)                                   |
| 最小コスト           | $0 (使った分だけ)                                    | ~$11/月 (1 シャード On-Demand)                       | ~$200/月 (最小構成)                                  |
| Terraform 対応       | ✅                                                    | ✅                                                    | ✅                                                    |

### Guidelines

**→ SQS を標準のメッセージキューとして採用する。** サーバーレス、従量課金、DLQ 内蔵で運用負荷が最も低い。

- リアルタイムストリーミング (ログ集約、クリックストリーム) でリプレイ・複数コンシューマーが必要 → Kinesis Data Streams
- 大規模イベントストリーミングで Kafka エコシステム (Connect、Streams) を活用したい → MSK
- 順序保証 + 重複排除が必要な場合は SQS FIFO を採用 (スループット制限に注意)
- MSK は最小コストが高いため、小〜中規模では Kinesis を推奨

## Event Bus: EventBridge vs SNS vs SQS

| 比較項目             | EventBridge                                          | SNS                                                  | SQS                                                  |
| -------------------- | ---------------------------------------------------- | ---------------------------------------------------- | ---------------------------------------------------- |
| サービスカテゴリ     | Event Bus                                            | Pub/Sub                                              | Message Queue                                        |
| ドキュメント         | [EventBridge](https://docs.aws.amazon.com/eventbridge/) | [SNS](https://docs.aws.amazon.com/sns/)              | [SQS](https://docs.aws.amazon.com/sqs/)             |
| 課金モデル           | イベント課金 ($1.00/100万)                           | リクエスト + 配信課金                                | リクエスト課金                                       |
| 主用途               | イベント駆動アーキテクチャ、AWS サービス連携         | Fan-Out (1:N 配信)                                   | Point-to-Point キュー (1:1)                          |
| 配信モデル           | Push (ルールベース)                                  | Push (サブスクリプション)                            | Pull (ポーリング)                                    |
| ターゲット数         | 最大 5/ルール (複数ルール可)                         | 最大 12,500,000 サブスクリプション/トピック          | 1 (キュー)                                           |
| フィルタリング       | ✅ (イベントパターン、詳細)                           | ✅ (サブスクリプションフィルター)                     | ❌                                                    |
| スキーマ管理         | ✅ (Schema Registry)                                  | ❌                                                    | ❌                                                    |
| AWS サービスイベント | ✅ (90+ サービスからの自動イベント)                   | ⚠️ (一部サービスのみ)                                 | ❌                                                    |
| SaaS 統合            | ✅ (Partner Event Sources)                            | ❌                                                    | ❌                                                    |
| アーカイブ/リプレイ  | ✅                                                    | ❌                                                    | ❌                                                    |
| DLQ                  | ✅                                                    | ✅ (配信失敗時)                                       | ✅                                                    |
| 順序保証             | ❌                                                    | ❌ (FIFO トピックで保証)                              | ⚠️ (FIFO キューで保証)                                |
| Terraform 対応       | ✅                                                    | ✅                                                    | ✅                                                    |

### Guidelines

**→ イベント駆動アーキテクチャには EventBridge を標準採用する。**

- AWS サービス間のイベント連携、スケジュール実行 → EventBridge
- シンプルな Fan-Out (1つのイベントを複数 SQS キューに配信) → SNS + SQS
- 非同期タスクキュー (ワーカーパターン) → SQS
- EventBridge → SQS の組み合わせ: イベントフィルタリング + 確実な処理を両立するパターンとして推奨
- SNS → SQS (Fan-Out) パターンは引き続き有効。EventBridge で代替可能だが、既存構成の移行は不要
