<!-- omit in toc -->
# AWS Service Comparison Matrix (Database)

データベースサービスの選定判断材料。RDS、DynamoDB、ElastiCache 等を比較する。

## History

| 日付       | 内容     |
| ---------- | -------- |
| 2026-05-28 | 初版作成 |

<!-- omit in toc -->
## Table of Contents

- [History](#history)
- [RDB: RDS vs Aurora vs Aurora Serverless v2](#rdb-rds-vs-aurora-vs-aurora-serverless-v2)
  - [Guidelines](#guidelines)
- [NoSQL: DynamoDB vs DocumentDB vs ElastiCache](#nosql-dynamodb-vs-documentdb-vs-elasticache)
  - [Guidelines](#guidelines-1)
- [Cache: ElastiCache Redis vs ElastiCache Memcached vs DAX](#cache-elasticache-redis-vs-elasticache-memcached-vs-dax)
  - [Guidelines](#guidelines-2)

## RDB: RDS vs Aurora vs Aurora Serverless v2

| 比較項目             | RDS                                                  | Aurora                                               | Aurora Serverless v2                                 |
| -------------------- | ---------------------------------------------------- | ---------------------------------------------------- | ---------------------------------------------------- |
| サービスカテゴリ     | Managed RDB                                          | Cloud-Native RDB                                     | Serverless RDB                                       |
| ドキュメント         | [RDS](https://docs.aws.amazon.com/rds/)              | [Aurora](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/) | [Aurora Serverless v2](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/aurora-serverless-v2.html) |
| 課金モデル           | インスタンス時間 + ストレージ                        | インスタンス時間 + I/O + ストレージ                  | ACU 秒課金 + I/O + ストレージ                        |
| マネージド度         | 高い                                                 | 高い                                                 | 非常に高い                                           |
| 主用途               | 標準的な RDB ワークロード                            | 高性能・高可用性が必要な RDB                         | 可変負荷の RDB ワークロード                          |
| 対応エンジン         | MySQL, PostgreSQL, MariaDB, Oracle, SQL Server        | MySQL 互換, PostgreSQL 互換                          | MySQL 互換, PostgreSQL 互換                          |
| ストレージ上限       | 64 TB (gp3)                                          | 128 TB (自動拡張)                                    | 128 TB (自動拡張)                                    |
| レプリカ             | 最大 15 (リードレプリカ)                             | 最大 15 (同一ストレージ共有)                         | 最大 15 (同一ストレージ共有)                         |
| フェイルオーバー時間 | 60-120 秒                                            | 30 秒以下                                            | 30 秒以下                                            |
| マルチ AZ            | ✅ (スタンバイレプリカ)                               | ✅ (3 AZ に 6 コピー自動)                             | ✅ (3 AZ に 6 コピー自動)                             |
| 自動スケーリング     | ❌ (手動インスタンス変更)                             | ⚠️ (リードレプリカ Auto Scaling)                      | ✅ (ACU 自動スケール)                                 |
| ゼロスケール         | ❌                                                    | ❌                                                    | ✅ (最小 0.5 ACU)                                     |
| Global Database      | ❌                                                    | ✅                                                    | ✅                                                    |
| コスト (常時高負荷)  | 安い (RI 適用)                                       | 中程度 (RI 適用)                                     | 高い                                                 |
| コスト (可変負荷)    | 高い (ピークに合わせたサイジング)                    | 高い                                                 | 安い (使った分だけ)                                  |
| Terraform 対応       | ✅                                                    | ✅                                                    | ✅                                                    |

### Guidelines

**→ Aurora を標準採用する。** ストレージの自動拡張、高速フェイルオーバー、リードレプリカの容易な追加で運用負荷が低い。

- 開発環境や負荷が不定期なワークロードは Aurora Serverless v2 を検討 (コスト最適化)
- Oracle / SQL Server が必須の場合は RDS を採用
- 小規模で Aurora のコストが過剰な場合は RDS (db.t4g クラス) を検討
- I/O 課金が高額になるワークロード (大量書き込み) は Aurora I/O-Optimized を検討

## NoSQL: DynamoDB vs DocumentDB vs ElastiCache

| 比較項目             | DynamoDB                                             | DocumentDB                                           | ElastiCache (Redis)                                  |
| -------------------- | ---------------------------------------------------- | ---------------------------------------------------- | ---------------------------------------------------- |
| サービスカテゴリ     | Key-Value / Document DB                              | Document DB (MongoDB 互換)                           | In-Memory DB                                         |
| ドキュメント         | [DynamoDB](https://docs.aws.amazon.com/dynamodb/)    | [DocumentDB](https://docs.aws.amazon.com/documentdb/) | [ElastiCache](https://docs.aws.amazon.com/elasticache/) |
| 課金モデル           | RCU/WCU (プロビジョン) or リクエスト従量             | インスタンス時間 + I/O + ストレージ                  | ノード時間課金                                       |
| マネージド度         | 非常に高い                                           | 高い                                                 | 高い                                                 |
| 主用途               | 高スループット KV アクセス、シンプルなクエリ         | MongoDB 互換が必要なドキュメント DB                  | キャッシュ、セッション、リアルタイム処理             |
| データモデル         | Key-Value + ドキュメント                             | JSON ドキュメント                                    | Key-Value + データ構造                               |
| クエリ柔軟性         | 低い (PK/SK + GSI/LSI)                               | 高い (MongoDB クエリ構文)                            | 低い (キーベース)                                    |
| レイテンシ           | 1桁 ms                                               | 1桁 ms                                               | サブ ms                                              |
| スケーリング         | 自動 (オンデマンド) / 手動 (プロビジョン)            | インスタンス追加                                     | ノード追加 / シャーディング                          |
| ストレージ上限       | 実質無制限                                           | 128 TB                                               | ノードメモリ依存                                     |
| トランザクション     | ✅ (25 アイテムまで)                                  | ✅                                                    | ✅ (Redis 7.0+)                                       |
| TTL                  | ✅                                                    | ✅                                                    | ✅                                                    |
| Global 展開          | ✅ Global Tables                                      | ✅ Global Clusters                                    | ✅ Global Datastore                                   |
| VPC 内配置           | ⚠️ (VPC Endpoint 経由)                                | ✅ (VPC 内のみ)                                       | ✅ (VPC 内のみ)                                       |
| Terraform 対応       | ✅                                                    | ✅                                                    | ✅                                                    |

### Guidelines

**→ DynamoDB をデフォルト NoSQL として採用する。** サーバーレス運用でスケーリング管理が不要、オンデマンドモードで小規模から大規模まで対応できる。

- MongoDB 互換 API が必須 (既存アプリ移行) の場合は DocumentDB を検討
- サブ ms レイテンシが必要なキャッシュ・セッション管理は ElastiCache を採用
- DynamoDB のクエリ制約 (複雑な検索、集計) が問題になる場合は Aurora を検討
- DynamoDB + ElastiCache の併用パターン: 読み取り頻度が極めて高いホットキーがある場合

## Cache: ElastiCache Redis vs ElastiCache Memcached vs DAX

| 比較項目             | ElastiCache Redis                                    | ElastiCache Memcached                                | DAX                                                  |
| -------------------- | ---------------------------------------------------- | ---------------------------------------------------- | ---------------------------------------------------- |
| サービスカテゴリ     | In-Memory Cache/DB                                   | In-Memory Cache                                      | DynamoDB Accelerator                                 |
| ドキュメント         | [Redis](https://docs.aws.amazon.com/elasticache/latest/red-ug/) | [Memcached](https://docs.aws.amazon.com/elasticache/latest/mem-ug/) | [DAX](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/DAX.html) |
| 課金モデル           | ノード時間課金                                       | ノード時間課金                                       | ノード時間課金                                       |
| 主用途               | 汎用キャッシュ、セッション、Pub/Sub、ランキング      | シンプルなキャッシュ                                 | DynamoDB 読み取りキャッシュ                          |
| データ構造           | String, Hash, List, Set, Sorted Set, Stream          | String のみ                                          | DynamoDB 互換                                        |
| 永続化               | ✅ (RDB/AOF)                                          | ❌                                                    | ❌ (キャッシュのみ)                                   |
| レプリケーション     | ✅ (最大 5 レプリカ/シャード)                          | ❌                                                    | ✅ (最大 10 レプリカ)                                  |
| クラスターモード     | ✅ (シャーディング)                                   | ✅ (ノード追加)                                       | ✅ (ノード追加)                                       |
| フェイルオーバー     | ✅ 自動                                               | ❌ (クライアント側で対応)                             | ✅ 自動                                               |
| マルチ AZ            | ✅                                                    | ⚠️ (AZ 分散配置のみ)                                  | ✅                                                    |
| Pub/Sub              | ✅                                                    | ❌                                                    | ❌                                                    |
| Lua スクリプト       | ✅                                                    | ❌                                                    | ❌                                                    |
| API 互換性           | Redis API                                            | Memcached API                                        | DynamoDB API (透過的)                                |
| 導入コスト           | 中程度 (Redis クライアント設定)                      | 低い                                                 | 低い (SDK 差し替えのみ)                              |

### Guidelines

**→ ElastiCache Redis を汎用キャッシュとして採用する。** データ構造の豊富さ、永続化、レプリケーション、Pub/Sub を備え、キャッシュ以外の用途にも対応できる。

- DynamoDB の読み取りレイテンシ改善が目的で、アプリケーション変更を最小化したい場合は DAX を検討
- 単純な KV キャッシュのみで永続化・レプリケーション不要な場合は Memcached を検討 (コスト面で有利な場合がある)
- Redis のメモリコストが問題になる場合は ElastiCache Serverless (Redis) を検討
