<!-- omit in toc -->
# ツール比較マトリクス (Terraform)

Terraform / IaC に特化したツール選定の判断材料。

<!-- omit in toc -->
## Table of Contents

- [Lint / セキュリティ: tflint vs checkov vs tfsec](#lint--セキュリティ-tflint-vs-checkov-vs-tfsec)
  - [選定ガイドライン](#選定ガイドライン)
- [IaC: Terraform vs OpenTofu vs Pulumi](#iac-terraform-vs-opentofu-vs-pulumi)
  - [選定ガイドライン](#選定ガイドライン-1)
- [Plan コメント: tfcmt vs tfnotify vs Atlantis](#plan-コメント-tfcmt-vs-tfnotify-vs-atlantis)
  - [選定ガイドライン](#選定ガイドライン-2)

## Lint / セキュリティ: tflint vs checkov vs tfsec

| 比較項目         | tflint                                                                  | checkov                                                         | tfsec (非推奨→Trivy統合)                                    |
| ---------------- | ----------------------------------------------------------------------- | --------------------------------------------------------------- | ----------------------------------------------------------- |
| 提供元           | terraform-linters                                                       | Bridgecrew (Palo Alto)                                          | Aqua Security                                               |
| リポジトリ       | [terraform-linters/tflint](https://github.com/terraform-linters/tflint) | [bridgecrewio/checkov](https://github.com/bridgecrewio/checkov) | [aquasecurity/tfsec](https://github.com/aquasecurity/tfsec) |
| ライセンス       | MPL-2.0                                                                 | Apache 2.0                                                      | MIT                                                         |
| 主な用途         | Lint (構文・命名・非推奨検出)                                           | セキュリティ・コンプライアンス                                  | セキュリティスキャン                                        |
| カスタムルール   | ✅ プラグイン                                                            | ✅ Python/YAML                                                   | ✅ Rego/YAML                                                 |
| プロバイダー対応 | AWS/Azure/GCP プラグイン                                                | マルチクラウド                                                  | マルチクラウド                                              |
| 自動修正         | ✅ `--fix`                                                               | ❌                                                               | ❌                                                           |
| 現在の状態       | アクティブ                                                              | アクティブ                                                      | Trivy に統合済み                                            |

### 選定ガイドライン

**→ tflint + Trivy を併用する。** tflint で構文・スタイル・非推奨リソースを検出し、Trivy でセキュリティスキャンをカバーする。tfsec は Trivy に統合済みのため新規採用は不要。

- コンプライアンスポリシーを Python/YAML で独自定義したい場合は checkov を検討

## IaC: Terraform vs OpenTofu vs Pulumi

| 比較項目              | Terraform                                                     | OpenTofu                                                  | Pulumi                                            |
| --------------------- | ------------------------------------------------------------- | --------------------------------------------------------- | ------------------------------------------------- |
| 提供元                | HashiCorp                                                     | Linux Foundation                                          | Pulumi Corp                                       |
| リポジトリ            | [hashicorp/terraform](https://github.com/hashicorp/terraform) | [opentofu/opentofu](https://github.com/opentofu/opentofu) | [pulumi/pulumi](https://github.com/pulumi/pulumi) |
| ライセンス            | BSL 1.1 (v1.6+)                                               | MPL 2.0                                                   | Apache 2.0                                        |
| 設定言語              | HCL                                                           | HCL (互換)                                                | TypeScript/Python/Go等                            |
| State 管理            | S3, Terraform Cloud 等                                        | S3, 互換バックエンド                                      | Pulumi Cloud, S3 等                               |
| Provider エコシステム | 最大 (3,000+)                                                 | Terraform 互換                                            | 独自 + Terraform Bridge                           |
| モジュール互換性      | -                                                             | ✅ Terraform モジュール利用可                              | ❌                                                 |
| 移行コスト            | -                                                             | 低い (ほぼ互換)                                           | 高い (書き直し)                                   |
| CI ツール連携         | tfcmt, Atlantis 等豊富                                        | Terraform 互換ツール利用可                                | 独自 CI 統合                                      |

### 選定ガイドライン

**→ Terraform を採用する。** エコシステムが最も成熟しており、Provider 数・周辺ツール (tfcmt, tflint 等) の充実度で優位。

- OSS ライセンスが必須要件の場合は OpenTofu を採用 (Terraform からの移行は容易)
- プログラミング言語で IaC を書きたい / ユニットテスト・型安全性を重視する場合は Pulumi を検討

## Plan コメント: tfcmt vs tfnotify vs Atlantis

| 比較項目         | tfcmt                                                             | tfnotify                                                | Atlantis                                                        |
| ---------------- | ----------------------------------------------------------------- | ------------------------------------------------------- | --------------------------------------------------------------- |
| 提供元           | suzuki-shunsuke                                                   | mercari                                                 | runatlantis                                                     |
| リポジトリ       | [suzuki-shunsuke/tfcmt](https://github.com/suzuki-shunsuke/tfcmt) | [mercari/tfnotify](https://github.com/mercari/tfnotify) | [runatlantis/atlantis](https://github.com/runatlantis/atlantis) |
| ライセンス       | MIT                                                               | MIT                                                     | Apache 2.0                                                      |
| 位置づけ         | plan 結果の PR コメント                                           | plan 結果の PR コメント                                 | plan + apply の自動化サーバー                                   |
| 設定の簡易さ     | ✅ CLI 一つで完結                                                  | ✅ CLI 一つで完結                                        | ⚠️ サーバー運用が必要                                            |
| コメント品質     | 高い (差分ハイライト、折りたたみ)                                 | 中程度                                                  | 高い                                                            |
| apply 実行       | ❌ (plan コメントのみ)                                             | ❌                                                       | ✅ (PR コメントから apply)                                       |
| メンテナンス状況 | アクティブ                                                        | メンテナンスモード                                      | アクティブ                                                      |
| 運用コスト       | なし (CI ジョブ内実行)                                            | なし                                                    | サーバー運用コスト                                              |

### 選定ガイドライン

**→ tfcmt を採用する。** CI ワークフロー内で軽量に plan 結果を PR コメントでき、サーバー運用不要。tfnotify の後継的位置づけでアクティブにメンテナンスされている。

- PR コメントから apply まで自動化したい / 複数環境の plan/apply をチームで統制したい場合は Atlantis を検討
