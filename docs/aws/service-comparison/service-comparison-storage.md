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
- [File Storage: EFS vs S3 Files vs FSx for Lustre vs FSx for NetApp ONTAP](#file-storage-efs-vs-s3-files-vs-fsx-for-lustre-vs-fsx-for-netapp-ontap)
  - [Guidelines](#guidelines-1)
- [Object Storage Tier: S3 Standard vs S3 IA vs S3 Glacier](#object-storage-tier-s3-standard-vs-s3-ia-vs-s3-glacier)
  - [Guidelines](#guidelines-2)

## Block / File / Object: EBS vs EFS vs S3

| 比較項目             | EBS                                                  | EFS                                                  | S3                                                   |
| -------------------- | ---------------------------------------------------- | ---------------------------------------------------- | ---------------------------------------------------- |
| ドキュメント         | [EBS](https://docs.aws.amazon.com/ebs/)              | [EFS](https://docs.aws.amazon.com/efs/)              | [S3](https://docs.aws.amazon.com/s3/)                |
| 課金モデル           | GB/月 + IOPS/スループット ([料金](https://aws.amazon.com/ebs/pricing/)) | GB/月 使用量ベース ([料金](https://aws.amazon.com/efs/pricing/)) | GB/月 + リクエスト + 転送 ([料金](https://aws.amazon.com/s3/pricing/)) |
| 主用途               | 単一インスタンスの高性能ストレージ                   | 複数インスタンス間の共有ファイルシステム              | 大容量データ保存、静的配信、データレイク             |
| SLA                  | 99.999%                                              | 99.99%                                               | 99.99%                                               |
| 学習コスト           | 低い                                                 | 低い                                                 | 低い                                                 |
| スケーリング         | 手動 (ボリュームサイズ変更)                          | 自動 (使用量に応じて)                                | 自動 (実質無制限)                                    |
| コスト (常時高負荷)  | 安い (プロビジョン)                                  | 中程度                                               | 安い (大容量割引)                                    |
| コスト (バースト)    | 中程度 (プロビジョン固定)                            | 安い (使った分だけ)                                  | 安い (従量課金)                                      |
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

## File Storage: EFS vs S3 Files vs FSx for Lustre vs FSx for NetApp ONTAP

| 比較項目             | EFS                                                  | S3 Files                                             | FSx for Lustre                                       | FSx for NetApp ONTAP                                 |
| -------------------- | ---------------------------------------------------- | ---------------------------------------------------- | ---------------------------------------------------- | ---------------------------------------------------- |
| ドキュメント         | [EFS](https://docs.aws.amazon.com/efs/)              | [S3 Files](https://docs.aws.amazon.com/AmazonS3/latest/userguide/s3-files.html) | [FSx Lustre](https://docs.aws.amazon.com/fsx/latest/LustreGuide/) | [FSx ONTAP](https://docs.aws.amazon.com/fsx/latest/ONTAPGuide/) |
| 課金モデル           | GB/月 使用量ベース ([料金](https://aws.amazon.com/efs/pricing/)) | S3 ストレージ + キャッシュ + I/O ([料金](https://aws.amazon.com/s3/pricing/)) | GB/月 プロビジョン容量 ([料金](https://aws.amazon.com/fsx/lustre/pricing/)) | GB/月 プロビジョン + SSD/HDD ([料金](https://aws.amazon.com/fsx/netapp-ontap/pricing/)) |
| 主用途               | 汎用共有ファイルシステム                             | S3 データへの POSIX アクセス、大容量読み取り中心     | HPC、ML 学習データ、大規模並列 I/O                   | エンタープライズ NAS、マルチプロトコル               |
| SLA                  | 99.99%                                               | 99.99% (S3 SLA)                                      | 99.9%                                                | 99.99%                                               |
| 学習コスト           | 低い                                                 | 低い (NFS マウント)                                  | 中程度 (Lustre クライアント)                         | 中程度 (ONTAP 知識)                                  |
| スケーリング         | 自動 (使用量に応じて)                                | 自動 (S3 バックエンド、実質無制限)                   | 手動 (容量変更)                                      | 手動 (容量変更)                                      |
| コスト (常時高負荷)  | 中程度 ($0.30/GB)                                    | 安い (大容量ファイル: $0.023/GB)                     | 中程度 (プロビジョン)                                | 高い                                                 |
| コスト (バースト)    | 安い (使った分だけ)                                  | 安い (S3 従量課金)                                   | 高い (プロビジョン固定)                              | 高い (プロビジョン固定)                              |
| プロトコル           | NFSv4                                                | NFSv4.2                                              | POSIX (Lustre クライアント)                          | NFS, SMB, iSCSI                                      |
| スループット         | 最大 10 GB/s                                         | S3 スループット依存                                  | 最大数百 GB/s                                        | 最大数 GB/s                                          |
| レイテンシ           | 1桁 ms                                               | ~1 ms (キャッシュヒット)                             | サブ ms                                              | サブ ms                                              |
| 書き込み可視性       | 即時 (ms)                                            | ~60 秒 (write-back delay)                            | 即時                                                 | 即時                                                 |
| ファイルロック       | ✅                                                    | ❌ (クライアント間で非共有)                           | ✅                                                    | ✅                                                    |
| S3 連携              | ❌                                                    | ✅ (S3 バケットがバックエンド)                        | ✅ (S3 を透過的にマウント)                            | ❌                                                    |
| マルチ AZ            | ✅                                                    | ✅ (S3 の冗長性)                                      | ❌ (単一 AZ)                                          | ✅                                                    |
| Windows 対応         | ❌                                                    | ❌                                                    | ❌                                                    | ✅ (SMB)                                              |
| ECS Fargate 対応     | ✅                                                    | ✅                                                    | ❌                                                    | ❌                                                    |
| Lambda 対応          | ✅ (VPC 必要)                                         | ✅ (VPC 必要)                                         | ❌                                                    | ❌                                                    |
| Terraform 対応       | ✅                                                    | ✅                                                    | ✅                                                    | ✅                                                    |

### Guidelines

**→ ワークロード特性に応じて EFS と S3 Files を使い分ける。**

- 即時書き込み可視性、ファイルロック、concurrent writers が必要 → EFS
- S3 上の大容量データに POSIX アクセスしたい、読み取り中心のワークロード → S3 Files (ストレージコスト最大 13x 削減)
- 小ファイル中心 (< 1 MiB) のワークロードは S3 Files のキャッシュ層 ($0.30/GB) が加算されるため EFS と同等以上のコストになる
- HPC/ML で大規模並列 I/O + S3 データ連携が必要な場合は FSx for Lustre を検討
- NFS + SMB マルチプロトコル、エンタープライズ NAS 機能が必要な場合は FSx for NetApp ONTAP を検討
- S3 Files はファイルロック・atomic rename が非対応のため、DB (SQLite 等) やロックファイルによる排他制御には使用不可

## Object Storage Tier: S3 Standard vs S3 IA vs S3 Glacier

| 比較項目             | S3 Standard                                          | S3 Standard-IA                                       | S3 Glacier Instant Retrieval                         | S3 Glacier Deep Archive                              |
| -------------------- | ---------------------------------------------------- | ---------------------------------------------------- | ---------------------------------------------------- | ---------------------------------------------------- |
| ドキュメント         | [S3](https://docs.aws.amazon.com/s3/)                | [S3](https://docs.aws.amazon.com/s3/)                | [S3 Glacier](https://docs.aws.amazon.com/s3/)        | [S3 Glacier](https://docs.aws.amazon.com/s3/)        |
| 課金モデル           | $0.023/GB/月 ([料金](https://aws.amazon.com/s3/pricing/)) | $0.0125/GB/月 + 取出 $0.01/GB ([料金](https://aws.amazon.com/s3/pricing/)) | $0.004/GB/月 + 取出 $0.03/GB ([料金](https://aws.amazon.com/s3/pricing/)) | $0.00099/GB/月 + 取出 $0.02/GB ([料金](https://aws.amazon.com/s3/pricing/)) |
| 主用途               | 頻繁アクセスデータ                                   | 月1回程度のアクセス                                  | 四半期1回程度のアクセス                              | コンプライアンス保存、年1回未満                      |
| SLA                  | 99.99%                                               | 99.9%                                                | 99.9%                                                | 99.9%                                                |
| 学習コスト           | 低い                                                 | 低い                                                 | 低い                                                 | 低い                                                 |
| スケーリング         | 自動 (実質無制限)                                    | 自動 (実質無制限)                                    | 自動 (実質無制限)                                    | 自動 (実質無制限)                                    |
| コスト (常時高負荷)  | 中程度 (保存量依存)                                  | 安い (保存単価低)                                    | 非常に安い                                           | 最安                                                 |
| コスト (バースト)    | 安い (取出無料)                                      | 中程度 (取出課金)                                    | 高い (取出課金高)                                    | 高い (取出課金 + 時間)                               |
| 取り出しレイテンシ   | ms                                                   | ms                                                   | ms                                                   | 12-48 時間 (Standard/Bulk)                           |
| 最小保存期間         | なし                                                 | 30 日                                                | 90 日                                                | 180 日                                               |
| 最小オブジェクトサイズ | なし                                                | 128 KB                                               | 128 KB                                               | なし                                                 |
| 耐久性               | 99.999999999%                                        | 99.999999999%                                        | 99.999999999%                                        | 99.999999999%                                        |

### Guidelines

**→ S3 Intelligent-Tiering を標準採用する。** アクセスパターンが予測困難な場合、自動的に最適なティアに移行しコストを最小化する。

- アクセスパターンが明確な場合はライフサイクルルールで明示的にティア移行を設定
- 作成後 30 日以上アクセスされないことが確実なデータ → S3 Standard-IA
- 監査ログ等の長期保存 (年1回未満のアクセス) → S3 Glacier Deep Archive
- 即時取り出しが必要だがアクセス頻度が低いデータ → S3 Glacier Instant Retrieval
