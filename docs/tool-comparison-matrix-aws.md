<!-- omit in toc -->
# ツール比較マトリクス (AWS)

AWS に特化したツール選定の判断材料。

<!-- omit in toc -->
## Table of Contents

- [ECS デプロイ: ecspresso vs Copilot vs CDK](#ecs-デプロイ-ecspresso-vs-copilot-vs-cdk)
  - [選定ガイドライン](#選定ガイドライン)
- [サーバーレス: SAM vs Serverless Framework vs CloudFormation](#サーバーレス-sam-vs-serverless-framework-vs-cloudformation)
  - [選定ガイドライン](#選定ガイドライン-1)
- [シークレット暗号化: sops vs Vault vs AWS Secrets Manager](#シークレット暗号化-sops-vs-vault-vs-aws-secrets-manager)
  - [選定ガイドライン](#選定ガイドライン-2)
- [ECS スケジュールタスク: ecschedule](#ecs-スケジュールタスク-ecschedule)
  - [選定ガイドライン](#選定ガイドライン-3)

## ECS デプロイ: ecspresso vs Copilot vs CDK

| 比較項目            | ecspresso                                             | AWS Copilot                                           | AWS CDK                                       |
| ------------------- | ----------------------------------------------------- | ----------------------------------------------------- | --------------------------------------------- |
| 提供元              | kayac                                                 | AWS                                                   | AWS                                           |
| リポジトリ          | [kayac/ecspresso](https://github.com/kayac/ecspresso) | [aws/copilot-cli](https://github.com/aws/copilot-cli) | [aws/aws-cdk](https://github.com/aws/aws-cdk) |
| ライセンス          | MIT                                                   | Apache 2.0                                            | Apache 2.0                                    |
| 設定形式            | JSON/Jsonnet (ECS API準拠)                            | YAML (独自形式)                                       | TypeScript/Python等                           |
| 学習コスト          | 低い (ECS API知識があれば)                            | 中程度                                                | 高い                                          |
| 柔軟性              | 高い (ECS API直接操作)                                | 中程度 (抽象化)                                       | 非常に高い                                    |
| スケジュールタスク  | ⚠️ ecschedule で対応                                   | ✅                                                     | ✅                                             |
| Blue/Green デプロイ | ✅ (CodeDeploy連携)                                    | ❌                                                     | ✅                                             |
| Terraform 連携      | ✅ (tfstate参照可能)                                   | ❌                                                     | ⚠️ (別管理)                                    |
| CI/CD 統合          | シンプル (CLI実行のみ)                                | 組み込みパイプライン                                  | 組み込みパイプライン                          |

### 選定ガイドライン

**→ ecspresso を採用する。** Terraform でインフラ管理しつつ ECS デプロイのみ軽量に行える。CI パイプラインに CLI を組み込むだけで完結し、学習コストが低い。

- Terraform を使わず ECS の構築からデプロイまで一気通貫で管理したい場合は AWS Copilot を検討
- 複雑なデプロイパターン (Blue/Green等) をプログラミング言語で制御したい場合は CDK を検討

## サーバーレス: SAM vs Serverless Framework vs CloudFormation

| 比較項目            | AWS SAM                                               | Serverless Framework                                              | CloudFormation (直接) |
| ------------------- | ----------------------------------------------------- | ----------------------------------------------------------------- | --------------------- |
| 提供元              | AWS                                                   | Serverless Inc                                                    | AWS                   |
| リポジトリ          | [aws/aws-sam-cli](https://github.com/aws/aws-sam-cli) | [serverless/serverless](https://github.com/serverless/serverless) | - (AWS 組み込み)      |
| ライセンス          | Apache 2.0                                            | MIT                                                               | 商用 (AWS に含む)     |
| 設定形式            | YAML (CloudFormation拡張)                             | YAML (独自形式)                                                   | YAML/JSON             |
| 抽象化レベル        | 中程度 (Lambda中心の簡略記法)                         | 高い (プラグインで拡張)                                           | なし (低レベル)       |
| ローカル実行        | ✅ `sam local invoke/start-api`                        | ✅ `serverless invoke local`                                       | ❌                     |
| ホットリロード      | ✅ `sam sync --watch`                                  | ⚠️ プラグイン依存                                                  | ❌                     |
| マルチクラウド      | ❌ AWS のみ                                            | ✅ (AWS/Azure/GCP)                                                 | ❌ AWS のみ            |
| CloudFormation 互換 | ✅ (上位互換)                                          | ❌ (独自変換)                                                      | ✅ (そのもの)          |
| 料金                | 無料                                                  | 無料 (v4 は有料プランあり)                                        | 無料                  |

### 選定ガイドライン

**→ AWS SAM を採用する。** AWS 公式でローカル実行・ホットリロードに対応し、CloudFormation の上位互換として既存知識を活用できる。Lambda 中心のサーバーレス開発に最適。

- マルチクラウド対応が必要 / プラグインエコシステムを活用したい場合は Serverless Framework を検討
- SAM/Serverless を使わず Terraform で Lambda を管理する構成も有効 (インフラ全体を Terraform に統一したい場合)

## シークレット暗号化: sops vs Vault vs AWS Secrets Manager

| 比較項目       | sops                                            | HashiCorp Vault                                       | AWS Secrets Manager |
| -------------- | ----------------------------------------------- | ----------------------------------------------------- | ------------------- |
| 提供元         | CNCF (旧 Mozilla)                               | HashiCorp                                             | AWS                 |
| リポジトリ     | [getsops/sops](https://github.com/getsops/sops) | [hashicorp/vault](https://github.com/hashicorp/vault) | - (AWS 組み込み)    |
| ライセンス     | MPL-2.0                                         | BSL 1.1                                               | 商用 (AWS に含む)   |
| 暗号化方式     | KMS / PGP / age                                 | 独自エンジン                                          | AWS KMS             |
| Git 管理       | ✅ (暗号化ファイルをコミット)                    | ❌ (API経由)                                           | ❌ (API経由)         |
| 運用コスト     | なし (CLIのみ)                                  | 高い (サーバー運用)                                   | 低い (マネージド)   |
| ローテーション | 手動                                            | ✅ 自動                                                | ✅ 自動              |
| アクセス制御   | KMS ポリシー                                    | 詳細なポリシー                                        | IAM ポリシー        |
| Terraform 連携 | ✅ (sops provider)                               | ✅ (vault provider)                                    | ✅ (data source)     |

### 選定ガイドライン

**→ sops + AWS Secrets Manager を併用する。** sops で IaC の変数ファイル (tfvars 等) を Git 管理しつつ暗号化、Secrets Manager でアプリケーション実行時のシークレット取得を行う。

- 動的シークレット生成・詳細な監査ログが必要な大規模組織では Vault を検討

## ECS スケジュールタスク: ecschedule

| 比較項目 | ecschedule |
|---|---|
| 提供元 | Songmu |
| リポジトリ | [Songmu/ecschedule](https://github.com/Songmu/ecschedule) |
| ライセンス | MIT |
| 用途 | ECS Scheduled Tasks (EventBridge + ECS) のデプロイ管理 |
| 設定形式 | YAML |
| ecspresso 連携 | ✅ (タスク定義を共有可能) |
| Terraform 連携 | ✅ (tfstate 参照) |
| CI/CD 統合 | シンプル (CLI実行のみ) |

### 選定ガイドライン

**→ ecschedule を採用する。** ecspresso と同じ思想で ECS スケジュールタスクを管理する軽量ツール。ecspresso と組み合わせることで ECS サービス + スケジュールタスクを統一的に管理できる。
