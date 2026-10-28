# Tool Comparison Matrix (AWS)

AWS に特化したツール選定の判断材料。

## History

| 日付       | 内容                                                                          |
| ---------- | ----------------------------------------------------------------------------- |
| 2026-05-21 | History セクション追加                                                        |
| 2026-05-12 | 初版作成。ECS デプロイ / Serverless / Secret 管理を比較。Copilot EOS 警告追加 |

## ECS Deploy: AWS CDK vs AWS Copilot vs ecspresso

> ⚠️ **AWS Copilot CLI は 2026/6/12 に End of Support。** 新規採用は非推奨。移行先として ECS Express Mode または AWS CDK を推奨。

| 比較項目            | AWS CDK                                       | AWS Copilot ⚠️ EOS                                    | ecspresso                                             |
| ------------------- | --------------------------------------------- | ----------------------------------------------------- | ----------------------------------------------------- |
| 提供元              | AWS                                           | AWS                                                   | kayac                                                 |
| リポジトリ          | [aws/aws-cdk](https://github.com/aws/aws-cdk) | [aws/copilot-cli](https://github.com/aws/copilot-cli) | [kayac/ecspresso](https://github.com/kayac/ecspresso) |
| ライセンス          | Apache 2.0                                    | Apache 2.0                                            | MIT                                                   |
| 設定形式            | TypeScript/Python 等                          | YAML (独自形式)                                       | JSON/Jsonnet (ECS API 準拠)                           |
| 学習コスト          | 高い                                          | 中程度                                                | 低い (ECS API 知識があれば)                           |
| 柔軟性              | 非常に高い                                    | 中程度 (抽象化)                                       | 高い (ECS API 直接操作)                               |
| スケジュールタスク  | ✅                                            | ✅                                                    | ⚠️ ecschedule で対応                                  |
| Blue/Green デプロイ | ✅                                            | ❌                                                    | ✅ (CodeDeploy 連携)                                  |
| Terraform 連携      | ⚠️ (別管理)                                   | ❌                                                    | ✅ (tfstate 参照可能)                                 |
| CI/CD 統合          | 組み込みパイプライン                          | 組み込みパイプライン                                  | シンプル (CLI 実行のみ)                               |

### Guidelines

**→ ecspresso を採用する。** Terraform でインフラ管理しつつ ECS デプロイのみ軽量に行える。CI パイプラインに CLI を組み込むだけで完結し、学習コストが低い。

- ~~Terraform を使わず ECS の構築からデプロイまで一気通貫で管理したい場合は AWS Copilot を検討~~ → EOS のため非推奨。CDK または ECS Express Mode を検討
- 複雑なデプロイパターン (Blue/Green 等) をプログラミング言語で制御したい場合は CDK を検討

## Serverless: AWS SAM vs CloudFormation vs Serverless Framework

| 比較項目            | AWS SAM                                               | CloudFormation (直接) | Serverless Framework                                              |
| ------------------- | ----------------------------------------------------- | --------------------- | ----------------------------------------------------------------- |
| 提供元              | AWS                                                   | AWS                   | Serverless Inc                                                    |
| リポジトリ          | [aws/aws-sam-cli](https://github.com/aws/aws-sam-cli) | - (AWS 組み込み)      | [serverless/serverless](https://github.com/serverless/serverless) |
| ライセンス          | Apache 2.0                                            | 商用 (AWS に含む)     | 独自 (個人・小規模は無料、\$2M+ 収益は有料)                       |
| 設定形式            | YAML (CloudFormation 拡張)                            | YAML/JSON             | YAML (独自形式)                                                   |
| 抽象化レベル        | 中程度 (Lambda 中心の簡略記法)                        | なし (低レベル)       | 高い (プラグインで拡張)                                           |
| ローカル実行        | ✅ `sam local invoke/start-api`                       | ❌                    | ✅ `serverless invoke local`                                      |
| ホットリロード      | ✅ `sam sync --watch`                                 | ❌                    | ⚠️ プラグイン依存                                                 |
| マルチクラウド      | ❌ AWS のみ                                           | ❌ AWS のみ           | ❌ AWS のみ (v3 まで対応、v4 で廃止)                              |
| CloudFormation 互換 | ✅ (上位互換)                                         | ✅ (そのもの)         | ❌ (独自変換)                                                     |
| 料金                | 無料                                                  | 無料                  | 有料 (個人・小規模は無料枠あり)                                   |

### Guidelines

**→ AWS SAM を採用する。** AWS 公式でローカル実行・ホットリロードに対応し、CloudFormation の上位互換として既存知識を活用できる。Lambda 中心のサーバーレス開発に最適。

- プラグインエコシステムを活用したい場合は Serverless Framework を検討 (v4 以降は有料化・AWS 専用のため注意)
- SAM/Serverless を使わず Terraform で Lambda を管理する構成も有効 (インフラ全体を Terraform に統一したい場合)

## Secret Encryption: AWS Secrets Manager vs HashiCorp Vault vs sops

| 比較項目       | AWS Secrets Manager | HashiCorp Vault                                       | sops                                            |
| -------------- | ------------------- | ----------------------------------------------------- | ----------------------------------------------- |
| 提供元         | AWS                 | HashiCorp                                             | CNCF (旧 Mozilla)                               |
| リポジトリ     | - (AWS 組み込み)    | [hashicorp/vault](https://github.com/hashicorp/vault) | [getsops/sops](https://github.com/getsops/sops) |
| ライセンス     | 商用 (AWS に含む)   | BSL 1.1                                               | MPL-2.0                                         |
| 暗号化方式     | AWS KMS             | 独自エンジン                                          | KMS / PGP / age                                 |
| Git 管理       | ❌ (API 経由)       | ❌ (API 経由)                                         | ✅ (暗号化ファイルをコミット)                   |
| 運用コスト     | 低い (マネージド)   | 高い (サーバー運用)                                   | なし (CLI のみ)                                 |
| ローテーション | ✅ 自動             | ✅ 自動                                               | 手動                                            |
| アクセス制御   | IAM ポリシー        | 詳細なポリシー                                        | KMS ポリシー                                    |
| Terraform 連携 | ✅ (data source)    | ✅ (vault provider)                                   | ✅ (sops provider)                              |

### Guidelines

**→ sops + AWS Secrets Manager を併用する。** sops で IaC の変数ファイル (tfvars 等) を Git 管理しつつ暗号化、Secrets Manager でアプリケーション実行時のシークレット取得を行う。

- 動的シークレット生成・詳細な監査ログが必要な大規模組織では Vault を検討

## ECS Scheduled Tasks: ecschedule

| 比較項目       | ecschedule                                                |
| -------------- | --------------------------------------------------------- |
| 提供元         | Songmu                                                    |
| リポジトリ     | [Songmu/ecschedule](https://github.com/Songmu/ecschedule) |
| ライセンス     | MIT                                                       |
| 用途           | ECS Scheduled Tasks (EventBridge + ECS) のデプロイ管理    |
| 設定形式       | YAML                                                      |
| ecspresso 連携 | ✅ (タスク定義を共有可能)                                 |
| Terraform 連携 | ✅ (tfstate 参照)                                         |
| CI/CD 統合     | シンプル (CLI 実行のみ)                                   |

### Guidelines

**→ ecschedule を採用する。** ecspresso と同じ思想で ECS スケジュールタスクを管理する軽量ツール。ecspresso と組み合わせることで ECS サービス + スケジュールタスクを統一的に管理できる。
