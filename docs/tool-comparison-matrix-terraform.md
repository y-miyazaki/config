# ツール比較マトリクス (Terraform)

Terraform / IaC に特化したツール選定の判断材料。

<!-- omit toc -->
## Table of Contents

- [ツール比較マトリクス (Terraform)](#ツール比較マトリクス-terraform)
  - [Table of Contents](#table-of-contents)
  - [Lint / セキュリティ: tflint vs checkov vs tfsec](#lint--セキュリティ-tflint-vs-checkov-vs-tfsec)
    - [選定ガイドライン](#選定ガイドライン)
  - [IaC: Terraform vs OpenTofu vs Pulumi](#iac-terraform-vs-opentofu-vs-pulumi)
    - [選定ガイドライン](#選定ガイドライン-1)
  - [Plan コメント: tfcmt vs tfnotify vs Atlantis](#plan-コメント-tfcmt-vs-tfnotify-vs-atlantis)
    - [選定ガイドライン](#選定ガイドライン-2)

## Lint / セキュリティ: tflint vs checkov vs tfsec

| 比較項目         | tflint                        | checkov                        | tfsec (非推奨→Trivy統合) |
| ---------------- | ----------------------------- | ------------------------------ | ------------------------ |
| 提供元           | terraform-linters             | Bridgecrew (Palo Alto)         | Aqua Security            |
| 主な用途         | Lint (構文・命名・非推奨検出) | セキュリティ・コンプライアンス | セキュリティスキャン     |
| カスタムルール   | ✅ プラグイン                  | ✅ Python/YAML                  | ✅ Rego/YAML              |
| プロバイダー対応 | AWS/Azure/GCP プラグイン      | マルチクラウド                 | マルチクラウド           |
| 自動修正         | ✅ `--fix`                     | ❌                              | ❌                        |
| 現在の状態       | アクティブ                    | アクティブ                     | Trivy に統合済み         |

### 選定ガイドライン

- **tflint + Trivy の併用 (このリポジトリ)**: tflint で構文・スタイル、Trivy でセキュリティをカバー

## IaC: Terraform vs OpenTofu vs Pulumi

| 比較項目              | Terraform              | OpenTofu                     | Pulumi                  |
| --------------------- | ---------------------- | ---------------------------- | ----------------------- |
| 提供元                | HashiCorp              | Linux Foundation             | Pulumi Corp             |
| ライセンス            | BSL 1.1 (v1.6+)        | MPL 2.0 (OSS)                | Apache 2.0              |
| 設定言語              | HCL                    | HCL (互換)                   | TypeScript/Python/Go等  |
| State 管理            | S3, Terraform Cloud 等 | S3, 互換バックエンド         | Pulumi Cloud, S3 等     |
| Provider エコシステム | 最大 (3,000+)          | Terraform 互換               | 独自 + Terraform Bridge |
| モジュール互換性      | -                      | ✅ Terraform モジュール利用可 | ❌                       |
| 移行コスト            | -                      | 低い (ほぼ互換)              | 高い (書き直し)         |
| 商用サポート          | HashiCorp              | コミュニティ中心             | Pulumi Corp             |
| CI ツール連携         | tfcmt, Atlantis 等豊富 | Terraform 互換ツール利用可   | 独自 CI 統合            |
| 将来性リスク          | ライセンス変更リスク   | フォーク維持の持続性         | ベンダーロックイン      |

### 選定ガイドライン

- **Terraform (このリポジトリ)**: エコシステムが最も成熟。BSL ライセンスが許容できるなら最も安定した選択
- **OpenTofu**: OSS ライセンスが必須要件の場合。Terraform からの移行は容易
- **Pulumi**: プログラミング言語で IaC を書きたい場合。テスト・型安全性に優れるが移行コスト大

## Plan コメント: tfcmt vs tfnotify vs Atlantis

| 比較項目         | tfcmt                             | tfnotify                | Atlantis                      |
| ---------------- | --------------------------------- | ----------------------- | ----------------------------- |
| 提供元           | suzuki-shunsuke                   | mercari                 | runatlantis                   |
| 位置づけ         | plan 結果の PR コメント           | plan 結果の PR コメント | plan + apply の自動化サーバー |
| 設定の簡易さ     | ✅ CLI 一つで完結                  | ✅ CLI 一つで完結        | ⚠️ サーバー運用が必要          |
| コメント品質     | 高い (差分ハイライト、折りたたみ) | 中程度                  | 高い                          |
| apply 実行       | ❌ (plan コメントのみ)             | ❌                       | ✅ (PR コメントから apply)     |
| GitHub App 不要  | ✅                                 | ✅                       | ❌ (Webhook 必要)              |
| メンテナンス状況 | アクティブ                        | メンテナンスモード      | アクティブ                    |
| 運用コスト       | なし (CI ジョブ内実行)            | なし                    | サーバー運用コスト            |

### 選定ガイドライン

- **tfcmt (このリポジトリ)**: CI ワークフロー内で軽量に plan 結果を PR コメントするだけなら最適。tfnotify の後継的位置づけ
- **Atlantis**: PR ベースで apply まで自動化したい大規模チーム向け
