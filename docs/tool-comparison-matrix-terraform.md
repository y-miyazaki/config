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
- [ドキュメント生成: terraform-docs](#ドキュメント生成-terraform-docs)
  - [選定ガイドライン](#選定ガイドライン-3)
- [テスト: terraform test vs Terratest vs tftest](#テスト-terraform-test-vs-terratest-vs-tftest)
  - [選定ガイドライン](#選定ガイドライン-4)

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

## ドキュメント生成: terraform-docs

| 比較項目        | terraform-docs                                                                    |
| --------------- | --------------------------------------------------------------------------------- |
| 提供元          | terraform-docs                                                                    |
| リポジトリ      | [terraform-docs/terraform-docs](https://github.com/terraform-docs/terraform-docs) |
| ライセンス      | MIT                                                                               |
| 用途            | Terraform モジュールの入出力ドキュメント自動生成                                  |
| 出力形式        | Markdown / JSON / YAML / AsciiDoc 等                                              |
| pre-commit 対応 | ✅                                                                                 |
| README 自動更新 | ✅ (マーカーコメント間を自動置換)                                                  |

### 選定ガイドライン

**→ terraform-docs を採用する。** Terraform モジュールの variables / outputs / providers を自動でドキュメント化する唯一のデファクトツール。pre-commit と組み合わせて README を常に最新に保てる。

## テスト: terraform test vs Terratest vs tftest

| 比較項目 | terraform test | Terratest | tftest (pytest) |
|---|---|---|---|
| 提供元 | HashiCorp | Gruntwork | HashiCorp |
| リポジトリ | [hashicorp/terraform](https://github.com/hashicorp/terraform) | [gruntwork-io/terratest](https://github.com/gruntwork-io/terratest) | [hashicorp/terraform-plugin-testing](https://github.com/hashicorp/terraform-plugin-testing) |
| ライセンス | BSL 1.1 | Apache 2.0 | MPL-2.0 |
| テスト言語 | HCL (`.tftest.hcl`) | Go | Python (pytest) |
| 実リソース作成 | ✅ (plan のみも可) | ✅ | ✅ |
| plan のみテスト | ✅ (`command = plan`) | ⚠️ 自前実装 | ✅ |
| モック | ✅ (`mock_provider`) | ❌ | ⚠️ 限定的 |
| 追加依存 | なし (terraform 組み込み) | Go 環境必要 | Python 環境必要 |
| 学習コスト | 低い (HCL で記述) | 高い (Go テストコード) | 中程度 |
| 柔軟性 | 中程度 | 非常に高い (任意の Go コード) | 中程度 |
| マルチクラウド検証 | ✅ | ✅ (HTTP, SSH, K8s 等も可) | ✅ |

### 選定ガイドライン

**→ terraform test を採用する。** Terraform 組み込みで追加依存なし、HCL で記述でき学習コストが低い。plan のみのテストやモックにも対応しており、モジュールの単体テストに最適。

- 実リソースに対する複雑な統合テスト (HTTP リクエスト、SSH 接続、K8s 操作等) が必要な場合は Terratest を検討
- Python エコシステムで pytest ベースのテストを書きたい場合は tftest を検討
