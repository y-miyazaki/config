# ツール比較マトリクス

ツール選定時の判断材料として、カテゴリ別に比較を行う。

言語/技術スタック特化の比較は以下を参照:

- [Go 特化](tool-comparison-matrix-go.md)
- [Terraform 特化](tool-comparison-matrix-terraform.md)
- [Node.js 特化](tool-comparison-matrix-nodejs.md)
- [Shell Script 特化](tool-comparison-matrix-shell-script.md)

<!-- omit toc -->
## Table of Contents

- [依存関係更新: Renovate vs Dependabot](#依存関係更新-renovate-vs-dependabot)
- [バージョン管理: aqua vs asdf](#バージョン管理-aqua-vs-asdf)
- [セキュリティスキャン: Trivy vs Snyk vs Grype](#セキュリティスキャン-trivy-vs-snyk-vs-grype)
- [シークレット検出: gitleaks vs detect-secrets vs truffleHog](#シークレット検出-gitleaks-vs-detect-secrets-vs-trufflehog)
- [GitHub Actions Lint: actionlint vs ghalint vs zizmor](#github-actions-lint-actionlint-vs-ghalint-vs-zizmor)
- [GitHub Actions ピン留め: pinact vs pin-github-action vs Renovate](#github-actions-ピン留め-pinact-vs-pin-github-action-vs-renovate)
- [PR レビュー自動化: reviewdog vs GitHub Code Scanning vs SonarQube](#pr-レビュー自動化-reviewdog-vs-github-code-scanning-vs-sonarqube)
- [コードカバレッジ: Codecov vs Coveralls vs SonarQube](#コードカバレッジ-codecov-vs-coveralls-vs-sonarqube)
- [シークレット暗号化: sops vs Vault vs AWS Secrets Manager](#シークレット暗号化-sops-vs-vault-vs-aws-secrets-manager)
- [ECS デプロイ: ecspresso vs copilot vs CDK](#ecs-デプロイ-ecspresso-vs-copilot-vs-cdk)

## 依存関係更新: Renovate vs Dependabot

| 比較項目               | Renovate                                   | Dependabot                        |
| ---------------------- | ------------------------------------------ | --------------------------------- |
| 提供元                 | Mend (旧 WhiteSource)                      | GitHub                            |
| 対応プラットフォーム   | GitHub / GitLab / Bitbucket / Azure DevOps | GitHub のみ                       |
| 設定ファイル           | `renovate.json` (JSON5対応、extends可)     | `dependabot.yml`                  |
| 設定の柔軟性           | 非常に高い (正規表現、プリセット共有)      | 中程度 (YAML ベース)              |
| Shareable Config       | ✅ extends で組織共通設定を共有可能         | ❌ リポジトリ毎に設定が必要        |
| グルーピング           | ✅ `group` ルールで柔軟にまとめられる       | ⚠️ `groups` (2024年追加、制限あり) |
| 自動マージ             | ✅ 組み込みサポート                         | ⚠️ GitHub の auto-merge 機能に依存 |
| カスタム マネージャー  | ✅ regex manager で任意ファイル対応         | ❌ 対応エコシステムのみ            |
| 対応エコシステム数     | 90+                                        | 20+                               |
| スケジュール制御       | 詳細 (cron式、timezone対応)                | 基本 (daily/weekly/monthly)       |
| PR 同時オープン数制限  | ✅ 設定可能                                 | ✅ 設定可能                        |
| セルフホスト           | ✅ 可能                                     | ❌ GitHub 提供のみ                 |
| ダッシュボード         | ✅ Dependency Dashboard Issue               | ❌                                 |
| 料金                   | 無料 (GitHub App) / セルフホスト無料       | 無料 (GitHub 組み込み)            |
| 学習コスト             | やや高い (設定項目が多い)                  | 低い (シンプル)                   |
| このリポジトリでの用途 | aqua registry 等の更新                     | GitHub Actions の更新             |

### 選定ガイドライン

- **Renovate を選ぶ場合**: 複数リポジトリで設定を共有したい、対応エコシステムが多い方がよい、グルーピングや自動マージを細かく制御したい
- **Dependabot を選ぶ場合**: GitHub のみで完結させたい、設定をシンプルに保ちたい、GitHub Actions の更新のみで十分
- **併用パターン (このリポジトリ)**: Dependabot で GitHub Actions、Renovate でその他ツール (aqua等) を管理

## バージョン管理: aqua vs asdf

| 比較項目           | aqua                               | asdf                           |
| ------------------ | ---------------------------------- | ------------------------------ |
| 実装言語           | Go                                 | Shell Script (Bash)            |
| 設定ファイル       | `aqua.yaml`                        | `.tool-versions`               |
| プラグインシステム | Registry (GitHub 集中管理)         | Plugin (各リポジトリ分散)      |
| Checksum 検証      | ✅ 組み込みサポート                 | ❌ プラグイン依存               |
| Lazy Install       | ✅ コマンド実行時に自動インストール | ❌ 事前に `asdf install` が必要 |
| 実行速度           | 高速 (Go バイナリ)                 | 低速 (shim + shell script)     |
| Renovate 対応      | ✅ datasource 指定で自動更新可能    | ⚠️ 限定的                       |
| CI での利用        | ✅ `aqua-installer` Action          | ✅ `asdf-vm/actions`            |
| 対応ツール数       | 2,900+ (standard registry)         | 700+ (community plugins)       |
| Windows 対応       | ✅                                  | ❌ (WSL 経由のみ)               |
| 設定の宣言性       | 高い (YAML、バージョン固定)        | 中程度 (バージョン固定)        |
| ロックファイル     | ✅ `aqua-checksums.json`            | ❌                              |
| セキュリティ       | 高い (checksum必須化可能)          | 低い (プラグイン任意実行)      |
| 学習コスト         | 低い                               | 低い                           |
| コミュニティ規模   | 成長中                             | 大きい (歴史が長い)            |

### 選定ガイドライン

- **aqua を選ぶ場合**: セキュリティ (checksum) を重視、CI での高速セットアップ、Renovate との連携、Windows 対応が必要
- **asdf を選ぶ場合**: 既存チームが asdf に慣れている、Node.js/Ruby/Python 等のランタイム管理が主目的

## セキュリティスキャン: Trivy vs Snyk vs Grype

| 比較項目           | Trivy                   | Snyk                    | Grype                   |
| ------------------ | ----------------------- | ----------------------- | ----------------------- |
| 提供元             | Aqua Security           | Snyk Ltd                | Anchore                 |
| ライセンス         | OSS (Apache 2.0)        | フリーミアム            | OSS (Apache 2.0)        |
| コンテナスキャン   | ✅                       | ✅                       | ✅                       |
| IaC スキャン       | ✅ (Terraform, K8s等)    | ✅                       | ❌                       |
| ライセンススキャン | ✅                       | ✅                       | ❌                       |
| SBOM 生成          | ✅                       | ✅                       | ✅ (Syft連携)            |
| シークレット検出   | ✅                       | ❌ (別製品)              | ❌                       |
| CI 統合            | GitHub Actions / 各種CI | GitHub Actions / 各種CI | GitHub Actions / 各種CI |
| 脆弱性 DB          | 複数ソース統合          | Snyk独自DB              | Grype DB                |
| 修正提案           | ⚠️ 限定的                | ✅ 自動PR作成            | ❌                       |
| 実行速度           | 高速                    | 中程度                  | 高速                    |
| オフライン実行     | ✅ (DB事前DL)            | ❌                       | ✅ (DB事前DL)            |
| 料金               | 無料                    | 無料枠あり (制限付き)   | 無料                    |

### 選定ガイドライン

- **Trivy (このリポジトリ)**: OSS で無料、IaC + コンテナ + SBOM + シークレット検出を一つでカバー。オフライン実行可能で CI に組み込みやすい
- **Snyk**: 修正提案の自動 PR が欲しい場合、商用サポートが必要な場合
- **Grype**: コンテナイメージの脆弱性スキャンに特化したい場合。Syft と組み合わせて SBOM ベースのスキャンが可能

## シークレット検出: gitleaks vs detect-secrets vs truffleHog

| 比較項目         | gitleaks              | detect-secrets        | truffleHog          |
| ---------------- | --------------------- | --------------------- | ------------------- |
| 提供元           | Zach Rice             | Yelp                  | Truffle Security    |
| 実装言語         | Go                    | Python                | Go                  |
| Git 履歴スキャン | ✅                     | ❌ (ステージングのみ)  | ✅                   |
| pre-commit 対応  | ✅                     | ✅                     | ✅                   |
| ベースライン管理 | ✅ `.gitleaks.toml`    | ✅ `.secrets.baseline` | ❌                   |
| カスタムルール   | ✅ TOML で正規表現定義 | ✅ プラグインシステム  | ⚠️ 限定的            |
| 実行速度         | 高速                  | 中程度                | 高速                |
| 誤検知率         | 低い                  | 中程度                | 低い                |
| CI 統合          | GitHub Actions 公式   | 手動設定              | GitHub Actions 公式 |
| 料金             | 無料                  | 無料                  | 無料 (OSS版)        |

### 選定ガイドライン

- **gitleaks + detect-secrets 併用 (このリポジトリ)**: gitleaks で Git 履歴含む包括スキャン、detect-secrets で pre-commit 時のステージング検出。二重チェックで漏洩リスクを最小化
- **truffleHog**: Git 履歴の深いスキャンが必要で、検証済みシークレット (実際に有効か確認) の検出が欲しい場合

## GitHub Actions Lint: actionlint vs ghalint vs zizmor

| 比較項目             | actionlint                       | ghalint                        | zizmor                 |
| -------------------- | -------------------------------- | ------------------------------ | ---------------------- |
| 提供元               | rhysd                            | suzuki-shunsuke                | zizmorcore             |
| 主な検出対象         | 構文エラー、型チェック、式の検証 | セキュリティベストプラクティス | セキュリティ設定の不備 |
| シェルスクリプト検証 | ✅ (shellcheck連携)               | ❌                              | ❌                      |
| 式の型チェック       | ✅                                | ❌                              | ❌                      |
| persist-credentials  | ❌                                | ✅                              | ✅                      |
| timeout-minutes      | ❌                                | ✅                              | ❌                      |
| permissions 検証     | ⚠️ 限定的                         | ✅                              | ✅                      |
| Action ピン留め      | ❌                                | ✅                              | ✅                      |
| 補完的利用           | ✅ 構文・型中心                   | ✅ セキュリティ中心             | ✅ セキュリティ中心     |

### 選定ガイドライン

- **3つ併用を推奨 (このリポジトリ)**: それぞれ検出対象が異なるため、組み合わせることでカバレッジが最大化される

## GitHub Actions ピン留め: pinact vs pin-github-action vs Renovate

| 比較項目               | pinact                     | pin-github-action          | Renovate (pinDigests) |
| ---------------------- | -------------------------- | -------------------------- | --------------------- |
| 提供元                 | suzuki-shunsuke            | mheap                      | Mend                  |
| 用途                   | Action をフルSHAにピン留め | Action をフルSHAにピン留め | ピン留め + 自動更新   |
| バージョンコメント保持 | ✅                          | ✅                          | ✅                     |
| 一括変換               | ✅                          | ✅                          | ❌ (PR ベース)         |
| 自動更新               | ❌ (Renovate と併用)        | ❌                          | ✅                     |
| pre-commit 対応        | ❌                          | ❌                          | -                     |

### 選定ガイドライン

- **pinact + Renovate 併用 (このリポジトリ)**: pinact で初回ピン留め、Renovate で継続的な SHA 更新を自動化

## PR レビュー自動化: reviewdog vs GitHub Code Scanning vs SonarQube

| 比較項目       | reviewdog                   | GitHub Code Scanning           | SonarQube                |
| -------------- | --------------------------- | ------------------------------ | ------------------------ |
| 提供元         | haya14busa                  | GitHub                         | SonarSource              |
| コメント形式   | PR インラインコメント       | Security タブ + PR             | PR デコレーション        |
| 対応リンター   | 任意 (出力パース)           | SARIF 形式対応ツール           | 組み込みルール           |
| 設定の柔軟性   | 高い (任意ツール連携)       | 中程度 (SARIF 必須)            | 高い (独自ルール)        |
| セルフホスト   | 不要 (CI 内実行)            | 不要                           | 必要 (or Cloud版)        |
| 料金           | 無料                        | 無料 (Public) / 有料 (Private) | 有料 (Community版は無料) |
| フィルタリング | ✅ (diff のみ、ファイル指定) | ✅                              | ✅                        |

### 選定ガイドライン

- **reviewdog (このリポジトリ)**: golangci-lint 等の既存リンターの出力を PR インラインコメントとして表示。軽量で導入が容易

## コードカバレッジ: Codecov vs Coveralls vs SonarQube

| 比較項目                  | Codecov                        | Coveralls            | SonarQube   |
| ------------------------- | ------------------------------ | -------------------- | ----------- |
| 提供元                    | Sentry (Codecov)               | Coveralls            | SonarSource |
| 対応言語                  | 多数                           | 多数                 | 多数        |
| PR コメント               | ✅ (差分カバレッジ)             | ✅                    | ✅           |
| カバレッジゲート          | ✅                              | ✅                    | ✅           |
| フラグ/コンポーネント分割 | ✅                              | ⚠️ 限定的             | ✅           |
| OIDC 認証                 | ✅                              | ❌                    | ❌           |
| 料金                      | 無料 (Public) / 有料 (Private) | 無料 (Public) / 有料 | 有料        |
| バッジ                    | ✅                              | ✅                    | ✅           |

### 選定ガイドライン

- **Codecov (このリポジトリ)**: OIDC 対応でトークンレス運用可能。PR 差分カバレッジの可視化が優秀

## シークレット暗号化: sops vs Vault vs AWS Secrets Manager

| 比較項目       | sops                         | HashiCorp Vault     | AWS Secrets Manager |
| -------------- | ---------------------------- | ------------------- | ------------------- |
| 提供元         | Mozilla → CNCF               | HashiCorp           | AWS                 |
| 暗号化方式     | KMS / PGP / age              | 独自エンジン        | AWS KMS             |
| Git 管理       | ✅ (暗号化ファイルをコミット) | ❌ (API経由)         | ❌ (API経由)         |
| 運用コスト     | なし (CLIのみ)               | 高い (サーバー運用) | 低い (マネージド)   |
| ローテーション | 手動                         | ✅ 自動              | ✅ 自動              |
| アクセス制御   | KMS ポリシー                 | 詳細なポリシー      | IAM ポリシー        |
| Terraform 連携 | ✅ (sops provider)            | ✅ (vault provider)  | ✅ (data source)     |
| 適用規模       | 小〜中規模                   | 大規模              | 中〜大規模          |

### 選定ガイドライン

- **sops (このリポジトリ)**: Terraform の tfvars 等を Git 管理しつつ暗号化。小〜中規模チームで運用負荷が低い
- **Secrets Manager**: アプリケーション実行時のシークレット取得に最適。sops と併用可能

## ECS デプロイ: ecspresso vs copilot vs CDK

| 比較項目            | ecspresso                  | AWS Copilot          | AWS CDK              |
| ------------------- | -------------------------- | -------------------- | -------------------- |
| 提供元              | kayac (OSS)                | AWS                  | AWS                  |
| 設定形式            | JSON/Jsonnet (ECS API準拠) | YAML (独自形式)      | TypeScript/Python等  |
| 学習コスト          | 低い (ECS API知識があれば) | 中程度               | 高い                 |
| 柔軟性              | 高い (ECS API直接操作)     | 中程度 (抽象化)      | 非常に高い           |
| タスク定義管理      | ✅                          | ✅                    | ✅                    |
| スケジュールタスク  | ⚠️ ecschedule で対応        | ✅                    | ✅                    |
| ローリングデプロイ  | ✅                          | ✅                    | ✅                    |
| Blue/Green デプロイ | ✅ (CodeDeploy連携)         | ❌                    | ✅                    |
| Terraform 連携      | ✅ (tfstate参照可能)        | ❌                    | ⚠️ (別管理)           |
| CI/CD 統合          | シンプル (CLI実行のみ)     | 組み込みパイプライン | 組み込みパイプライン |

### 選定ガイドライン

- **ecspresso を選ぶ場合 (このリポジトリ)**: Terraform でインフラ管理しつつ、ECS デプロイのみ軽量に行いたい場合に最適
