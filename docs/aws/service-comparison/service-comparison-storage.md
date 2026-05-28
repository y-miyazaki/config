<!-- omit in toc -->
# AWS Service Comparison Matrix (Storage)

ストレージ・マウントサービスの選定判断材料。S3、EFS、EBS 等を比較する。

## History

| 日付       | 内容     |
| ---------- | -------- |
| 2026-05-28 | 初版作成 |

<!-- omit in toc -->
## Table of Contents

- [History](#history)
- [Block / File / Object: EBS vs EFS vs S3](#block--file--object-ebs-vs-efs-vs-s3)
  - [Guidelines](#guidelines)
- [File Storage: EFS vs FSx for Lustre vs FSx for NetApp ONTAP](#file-storage-efs-vs-fsx-for-lustre-vs-fsx-for-netapp-ontap)
  - [Guidelines](#guidelines-1)
- [Object Storage Tier: S3 Standard vs S3 IA vs S3 Glacier](#object-storage-tier-s3-standard-vs-s3-ia-vs-s3-glacier)
  - [Guidelines](#guidelines-2)

## Block / File / Object: EBS vs EFS vs S3

| 比較項目             | EBS                                                  | EFS                                                  | S3                                                   |
| -------------------- | ---------------------------------------------------- | ---------------------------------------------------- | ---------------------------------------------------- |
| サービスカテゴリ     | Block Storage                                        | File Storage (NFS)                                   | Object Storage                                       |
| ドキュメント         | [EBS](https://docs.aws.amazon.com/ebs/)              | [EFS](https://docs.aws.amazon.com/efs/)              | [S3](https://docs.aws.amazon.com/s3/)                |
| 課金モデル           | GB/月 + IOPS/スループット (gp3)                      | GB/月 (使用量ベース) + スループット                  | GB/月 + リクエスト + データ転送                      |
| マネージド度         | 高い                                                 | 非常に高い                                           | 非常に高い                                           |
| 主用途               | EC2/ECS 単一インスタンスの高性能ストレージ           | 複数インスタンス/コンテナ間の共有ファイルシステム    | 大容量データ保存、静的配信、データレイク             |
| アクセスパターン     | 単一 EC2/ECS タスクからマウント                      | 複数 EC2/ECS タスクから同時マウント                  | API (HTTP) 経由                                      |
| プロトコル           | ブロックデバイス                                     | NFSv4                                                | REST API                                             |
| 最大容量             | 64 TB/ボリューム                                     | 実質無制限 (ペタバイト級)                            | 実質無制限                                           |
| レイテンシ           | サブ ms (io2) / 1桁 ms (gp3)                         | 1桁 ms                                               | 10-100 ms (First Byte)                               |
| IOPS                 | 最大 256,000 (io2 Block Express)                     | 最大 55,000 (読み取り)                               | - (リクエストベース)                                 |
| スループット         | 最大 4,000 MB/s (io2 BE)                             | 最大 10 GB/s (Elastic)                               | マルチパートで高スループット                         |
| マルチ AZ            | ❌ (単一 AZ、スナップショットで復元)                  | ✅ (自動マルチ AZ レプリケーション)                   | ✅ (3 AZ 以上に自動レプリケーション)                  |
| マルチアタッチ       | ⚠️ (io2 のみ、同一 AZ 最大 16)                        | ✅ (数千クライアント同時)                             | ✅ (無制限同時アクセス)                               |
| ECS Fargate マウント | ✅ (単一タスク)                                       | ✅ (複数タスク共有)                                   | ❌ (SDK/CLI 経由でアクセス)                           |
| 暗号化               | ✅ (KMS)                                              | ✅ (KMS)                                              | ✅ (SSE-S3/SSE-KMS/SSE-C)                             |
| バックアップ         | スナップショット                                     | AWS Backup                                           | バージョニング + レプリケーション                    |
| ライフサイクル管理   | ❌                                                    | ✅ (IA クラス自動移行)                                | ✅ (Intelligent-Tiering / ライフサイクルルール)       |
| Terraform 対応       | ✅                                                    | ✅                                                    | ✅                                                    |

### Guidelines

**→ ユースケースに応じて使い分ける。**

- 単一コンテナ/インスタンスの高性能ブロックストレージ → EBS (gp3 を標準、高 IOPS 要件は io2)
- 複数コンテナ/インスタンス間のファイル共有 → EFS
- 大容量データ保存、静的ファイル配信、データレイク → S3
- ECS Fargate で共有ストレージが必要な場合は EFS を採用
- ECS Fargate で単一タスクの永続ストレージが必要な場合は EBS を採用
- アプリケーションデータの一時保存は S3 を推奨 (耐久性 99.999999999%)

## File Storage: EFS vs FSx for Lustre vs FSx for NetApp ONTAP

| 比較項目             | EFS                                                  | FSx for Lustre                                       | FSx for NetApp ONTAP                                 |
| -------------------- | ---------------------------------------------------- | ---------------------------------------------------- | ---------------------------------------------------- |
| サービスカテゴリ     | Managed NFS                                          | High-Performance File System                         | Multi-Protocol File System                           |
| ドキュメント         | [EFS](https://docs.aws.amazon.com/efs/)              | [FSx Lustre](https://docs.aws.amazon.com/fsx/latest/LustreGuide/) | [FSx ONTAP](https://docs.aws.amazon.com/fsx/latest/ONTAPGuide/) |
| 課金モデル           | GB/月 (使用量ベース)                                 | GB/月 (プロビジョン容量)                             | GB/月 (プロビジョン容量) + SSD/HDD                   |
| 主用途               | 汎用共有ファイルシステム                             | HPC、ML 学習データ、大規模並列 I/O                   | エンタープライズ NAS、マルチプロトコル               |
| プロトコル           | NFSv4                                                | POSIX (Lustre クライアント)                          | NFS, SMB, iSCSI                                      |
| スループット         | 最大 10 GB/s                                         | 最大数百 GB/s                                        | 最大数 GB/s                                          |
| レイテンシ           | 1桁 ms                                               | サブ ms                                              | サブ ms                                              |
| S3 連携              | ❌                                                    | ✅ (S3 を透過的にマウント)                            | ❌                                                    |
| マルチ AZ            | ✅                                                    | ❌ (単一 AZ)                                          | ✅                                                    |
| Windows 対応         | ❌                                                    | ❌                                                    | ✅ (SMB)                                              |
| データ圧縮           | ❌                                                    | ✅                                                    | ✅                                                    |
| スナップショット     | ❌ (AWS Backup)                                       | ❌ (S3 バックアップ)                                  | ✅ (NetApp Snapshot)                                  |
| ECS Fargate 対応     | ✅                                                    | ❌                                                    | ❌                                                    |
| Terraform 対応       | ✅                                                    | ✅                                                    | ✅                                                    |

### Guidelines

**→ EFS を標準採用する。** マルチ AZ 対応、使用量ベース課金、ECS Fargate 対応で汎用性が高い。

- HPC/ML で大規模並列 I/O + S3 データ連携が必要な場合は FSx for Lustre を検討
- NFS + SMB マルチプロトコル、エンタープライズ NAS 機能が必要な場合は FSx for NetApp ONTAP を検討
- ECS Fargate からマウントする場合は EFS 一択

## Object Storage Tier: S3 Standard vs S3 IA vs S3 Glacier

| 比較項目             | S3 Standard                                          | S3 Standard-IA                                       | S3 Glacier Instant Retrieval                         | S3 Glacier Deep Archive                              |
| -------------------- | ---------------------------------------------------- | ---------------------------------------------------- | ---------------------------------------------------- | ---------------------------------------------------- |
| サービスカテゴリ     | Object Storage (Hot)                                 | Object Storage (Warm)                                | Object Storage (Cold)                                | Object Storage (Archive)                             |
| 課金 (GB/月)         | $0.023                                               | $0.0125                                              | $0.004                                               | $0.00099                                             |
| 取り出し料金         | なし                                                 | $0.01/GB                                             | $0.03/GB                                             | $0.02/GB (Bulk)                                      |
| 最小保存期間         | なし                                                 | 30 日                                                | 90 日                                                | 180 日                                               |
| 最小オブジェクトサイズ | なし                                                | 128 KB                                               | 128 KB                                               | なし                                                 |
| 取り出しレイテンシ   | ms                                                   | ms                                                   | ms                                                   | 12-48 時間 (Standard/Bulk)                           |
| 可用性 SLA           | 99.99%                                               | 99.9%                                                | 99.9%                                                | 99.9%                                                |
| 耐久性               | 99.999999999%                                        | 99.999999999%                                        | 99.999999999%                                        | 99.999999999%                                        |
| ユースケース         | 頻繁アクセスデータ                                   | 月1回程度のアクセス                                  | 四半期1回程度のアクセス                              | コンプライアンス保存、年1回未満                      |

### Guidelines

**→ S3 Intelligent-Tiering を標準採用する。** アクセスパターンが予測困難な場合、自動的に最適なティアに移行しコストを最小化する。

- アクセスパターンが明確な場合はライフサイクルルールで明示的にティア移行を設定
- 作成後 30 日以上アクセスされないことが確実なデータ → S3 Standard-IA
- 監査ログ等の長期保存 (年1回未満のアクセス) → S3 Glacier Deep Archive
- 即時取り出しが必要だがアクセス頻度が低いデータ → S3 Glacier Instant Retrieval
