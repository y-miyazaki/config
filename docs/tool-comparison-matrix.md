<!-- omit in toc -->
# ツール比較マトリクス

ツール選定時の判断材料として、カテゴリ別に比較を行う。

言語/技術スタック特化の比較は以下を参照:

- [Go 特化](tool-comparison-matrix-go.md)
- [Terraform 特化](tool-comparison-matrix-terraform.md)
- [Node.js 特化](tool-comparison-matrix-nodejs.md)
- [Shell Script 特化](tool-comparison-matrix-shell-script.md)
- [AWS 特化](tool-comparison-matrix-aws.md)

<!-- omit in toc -->
## Table of Contents

- [依存関係更新: Renovate vs Dependabot](#依存関係更新-renovate-vs-dependabot)
  - [選定ガイドライン](#選定ガイドライン)
- [バージョン管理: aqua vs asdf](#バージョン管理-aqua-vs-asdf)
  - [選定ガイドライン](#選定ガイドライン-1)
- [セキュリティスキャン: Trivy vs Snyk vs Grype](#セキュリティスキャン-trivy-vs-snyk-vs-grype)
  - [選定ガイドライン](#選定ガイドライン-2)
- [シークレット検出: gitleaks vs detect-secrets vs truffleHog](#シークレット検出-gitleaks-vs-detect-secrets-vs-trufflehog)
  - [選定ガイドライン](#選定ガイドライン-3)
- [GitHub Actions Lint: actionlint vs ghalint vs zizmor](#github-actions-lint-actionlint-vs-ghalint-vs-zizmor)
  - [選定ガイドライン](#選定ガイドライン-4)
- [GitHub Actions ピン留め: pinact vs pin-github-action vs Renovate](#github-actions-ピン留め-pinact-vs-pin-github-action-vs-renovate)
  - [選定ガイドライン](#選定ガイドライン-5)
- [PR レビュー自動化: reviewdog vs GitHub Code Scanning vs SonarQube](#pr-レビュー自動化-reviewdog-vs-github-code-scanning-vs-sonarqube)
  - [選定ガイドライン](#選定ガイドライン-6)
- [コードカバレッジ: Codecov vs Coveralls vs SonarQube](#コードカバレッジ-codecov-vs-coveralls-vs-sonarqube)
  - [選定ガイドライン](#選定ガイドライン-7)
- [CI/CD: GitHub Actions vs GitLab CI vs CircleCI vs Jenkins](#cicd-github-actions-vs-gitlab-ci-vs-circleci-vs-jenkins)
  - [選定ガイドライン](#選定ガイドライン-8)

## 依存関係更新: Renovate vs Dependabot

| 比較項目              | Renovate                                                        | Dependabot                        |
| --------------------- | --------------------------------------------------------------- | --------------------------------- |
| 提供元                | Mend (旧 WhiteSource)                                           | GitHub                            |
| リポジトリ            | [renovatebot/renovate](https://github.com/renovatebot/renovate) | - (GitHub 組み込み)               |
| ライセンス            | AGPL-3.0                                                        | MIT                               |
| 対応プラットフォーム  | GitHub / GitLab / Bitbucket / Azure DevOps                      | GitHub のみ                       |
| 設定ファイル          | `renovate.json` (JSON5対応、extends可)                          | `dependabot.yml`                  |
| 設定の柔軟性          | 非常に高い (正規表現、プリセット共有)                           | 中程度 (YAML ベース)              |
| Shareable Config      | ✅ extends で組織共通設定を共有可能                              | ❌ リポジトリ毎に設定が必要        |
| グルーピング          | ✅ `group` ルールで柔軟にまとめられる                            | ⚠️ `groups` (2024年追加、制限あり) |
| 自動マージ            | ✅ 組み込みサポート                                              | ⚠️ GitHub の auto-merge 機能に依存 |
| カスタム マネージャー | ✅ regex manager で任意ファイル対応                              | ❌ 対応エコシステムのみ            |
| 対応エコシステム数    | 90+                                                             | 20+                               |
| スケジュール制御      | 詳細 (cron式、timezone対応)                                     | 基本 (daily/weekly/monthly)       |
| セルフホスト          | ✅ 可能                                                          | ❌ GitHub 提供のみ                 |
| 料金                  | 無料 (GitHub App) / セルフホスト無料                            | 無料 (GitHub 組み込み)            |

### 選定ガイドライン

**→ Renovate を採用する。** 対応エコシステムの広さ、Shareable Config による組織横断の設定共有、グルーピング・自動マージの柔軟性で優位。

- GitHub 以外のプラットフォーム (GitLab 等) を使う場合は Renovate 一択
- GitHub Actions の更新のみなど限定的な用途であれば Dependabot 単体でも可
- 併用も有効: Dependabot (GitHub Actions) + Renovate (その他エコシステム)

## バージョン管理: aqua vs asdf

| 比較項目           | aqua                                              | asdf                                            |
| ------------------ | ------------------------------------------------- | ----------------------------------------------- |
| 提供元             | aquaproj                                          | asdf-vm                                         |
| リポジトリ         | [aquaproj/aqua](https://github.com/aquaproj/aqua) | [asdf-vm/asdf](https://github.com/asdf-vm/asdf) |
| ライセンス         | MIT                                               | MIT                                             |
| 実装言語           | Go                                                | Shell Script (Bash)                             |
| 設定ファイル       | `aqua.yaml`                                       | `.tool-versions`                                |
| プラグインシステム | Registry (GitHub 集中管理)                        | Plugin (各リポジトリ分散)                       |
| Checksum 検証      | ✅ 組み込みサポート                                | ❌ プラグイン依存                                |
| Lazy Install       | ✅ コマンド実行時に自動インストール                | ❌ 事前に `asdf install` が必要                  |
| 実行速度           | 高速 (Go バイナリ)                                | 低速 (shim + shell script)                      |
| Renovate 対応      | ✅ datasource 指定で自動更新可能                   | ⚠️ 限定的                                        |
| 対応ツール数       | 2,900+ (standard registry)                        | 700+ (community plugins)                        |
| Windows 対応       | ✅                                                 | ❌ (WSL 経由のみ)                                |
| セキュリティ       | 高い (checksum必須化可能)                         | 低い (プラグイン任意実行)                       |

### 選定ガイドライン

**→ aqua を採用する。** Checksum 検証によるセキュリティ、Renovate 連携による自動更新、CI での高速セットアップで優位。

- Node.js/Ruby/Python 等のランタイム管理が主目的で、チームが既に asdf に慣れている場合は asdf でも可

## セキュリティスキャン: Trivy vs Snyk vs Grype

| 比較項目         | Trivy                                                       | Snyk                                    | Grype                                             |
| ---------------- | ----------------------------------------------------------- | --------------------------------------- | ------------------------------------------------- |
| 提供元           | Aqua Security                                               | Snyk Ltd                                | Anchore                                           |
| リポジトリ       | [aquasecurity/trivy](https://github.com/aquasecurity/trivy) | [snyk/cli](https://github.com/snyk/cli) | [anchore/grype](https://github.com/anchore/grype) |
| ライセンス       | Apache 2.0                                                  | Apache 2.0 (CLI) / 商用 (サービス)      | Apache 2.0                                        |
| コンテナスキャン | ✅                                                           | ✅                                       | ✅                                                 |
| IaC スキャン     | ✅ (Terraform, K8s等)                                        | ✅                                       | ❌                                                 |
| SBOM 生成        | ✅                                                           | ✅                                       | ✅ (Syft連携)                                      |
| シークレット検出 | ✅                                                           | ❌ (別製品)                              | ❌                                                 |
| 脆弱性 DB        | 複数ソース統合                                              | Snyk独自DB                              | Grype DB                                          |
| 修正提案         | ⚠️ 限定的                                                    | ✅ 自動PR作成                            | ❌                                                 |
| オフライン実行   | ✅ (DB事前DL)                                                | ❌                                       | ✅ (DB事前DL)                                      |
| 料金             | 無料                                                        | フリーミアム                            | 無料                                              |

### 選定ガイドライン

**→ Trivy を採用する。** OSS・無料で IaC + コンテナ + SBOM + シークレット検出を一つでカバーでき、スキャン範囲が最も広い。

- 脆弱性の修正 PR を自動生成したい / 商用サポートが必要な場合は Snyk を検討
- コンテナイメージ特化で Syft と組み合わせた SBOM ベーススキャンが必要な場合は Grype を検討

## シークレット検出: gitleaks vs detect-secrets vs truffleHog

| 比較項目         | gitleaks                                                  | detect-secrets                                                | truffleHog                                                                  |
| ---------------- | --------------------------------------------------------- | ------------------------------------------------------------- | --------------------------------------------------------------------------- |
| 提供元           | Zach Rice                                                 | Yelp                                                          | Truffle Security                                                            |
| リポジトリ       | [gitleaks/gitleaks](https://github.com/gitleaks/gitleaks) | [Yelp/detect-secrets](https://github.com/Yelp/detect-secrets) | [trufflesecurity/trufflehog](https://github.com/trufflesecurity/trufflehog) |
| ライセンス       | MIT                                                       | Apache 2.0                                                    | AGPL-3.0                                                                    |
| 実装言語         | Go                                                        | Python                                                        | Go                                                                          |
| Git 履歴スキャン | ✅                                                         | ❌ (ステージングのみ)                                          | ✅                                                                           |
| ベースライン管理 | ✅ `.gitleaks.toml`                                        | ✅ `.secrets.baseline`                                         | ❌                                                                           |
| カスタムルール   | ✅ TOML で正規表現定義                                     | ✅ プラグインシステム                                          | ⚠️ 限定的                                                                    |
| 実行速度         | 高速                                                      | 中程度                                                        | 高速                                                                        |
| 誤検知率         | 低い                                                      | 中程度                                                        | 低い                                                                        |

### 選定ガイドライン

**→ gitleaks + detect-secrets を併用する。** gitleaks で Git 履歴を含む包括スキャン、detect-secrets で pre-commit 時のステージング検出を行い、多層防御を実現する。

- 検出したシークレットが実際に有効かどうかの検証 (verified secrets) が必要な場合は truffleHog を検討

## GitHub Actions Lint: actionlint vs ghalint vs zizmor

| 比較項目             | actionlint                                              | ghalint                                                               | zizmor                                                    |
| -------------------- | ------------------------------------------------------- | --------------------------------------------------------------------- | --------------------------------------------------------- |
| 提供元               | rhysd                                                   | suzuki-shunsuke                                                       | zizmorcore                                                |
| リポジトリ           | [rhysd/actionlint](https://github.com/rhysd/actionlint) | [suzuki-shunsuke/ghalint](https://github.com/suzuki-shunsuke/ghalint) | [zizmorcore/zizmor](https://github.com/zizmorcore/zizmor) |
| ライセンス           | MIT                                                     | MIT                                                                   | MIT                                                       |
| 主な検出対象         | 構文エラー、型チェック、式の検証                        | セキュリティベストプラクティス                                        | セキュリティ設定の不備                                    |
| シェルスクリプト検証 | ✅ (shellcheck連携)                                      | ❌                                                                     | ❌                                                         |
| 式の型チェック       | ✅                                                       | ❌                                                                     | ❌                                                         |
| persist-credentials  | ❌                                                       | ✅                                                                     | ✅                                                         |
| timeout-minutes      | ❌                                                       | ✅                                                                     | ❌                                                         |
| permissions 検証     | ⚠️ 限定的                                                | ✅                                                                     | ✅                                                         |
| Action ピン留め      | ❌                                                       | ✅                                                                     | ✅                                                         |

### 選定ガイドライン

**→ 3つ全て併用する。** 検出対象が異なるため、組み合わせることでカバレッジが最大化される。actionlint (構文・型) + ghalint (セキュリティプラクティス) + zizmor (セキュリティ設定)。

## GitHub Actions ピン留め: pinact vs pin-github-action vs Renovate

| 比較項目   | pinact                                                              | pin-github-action                                                     | Renovate (pinDigests)                                           |
| ---------- | ------------------------------------------------------------------- | --------------------------------------------------------------------- | --------------------------------------------------------------- |
| 提供元     | suzuki-shunsuke                                                     | mheap                                                                 | Mend                                                            |
| リポジトリ | [suzuki-shunsuke/pinact](https://github.com/suzuki-shunsuke/pinact) | [mheap/pin-github-action](https://github.com/mheap/pin-github-action) | [renovatebot/renovate](https://github.com/renovatebot/renovate) |
| ライセンス | MIT                                                                 | MIT                                                                   | AGPL-3.0                                                        |
| 用途       | Action をフルSHAにピン留め                                          | Action をフルSHAにピン留め                                            | ピン留め + 自動更新                                             |
| 一括変換   | ✅                                                                   | ✅                                                                     | ❌ (PR ベース)                                                   |
| 自動更新   | ❌ (Renovate と併用)                                                 | ❌                                                                     | ✅                                                               |

### 選定ガイドライン

**→ pinact + Renovate を併用する。** pinact で既存ワークフローを一括ピン留めし、Renovate (pinDigests) で継続的に SHA を自動更新する。

## PR レビュー自動化: reviewdog vs GitHub Code Scanning vs SonarQube

| 比較項目     | reviewdog                                                     | GitHub Code Scanning           | SonarQube                                                         |
| ------------ | ------------------------------------------------------------- | ------------------------------ | ----------------------------------------------------------------- |
| 提供元       | haya14busa                                                    | GitHub                         | SonarSource                                                       |
| リポジトリ   | [reviewdog/reviewdog](https://github.com/reviewdog/reviewdog) | - (GitHub 組み込み)            | [SonarSource/sonarqube](https://github.com/SonarSource/sonarqube) |
| ライセンス   | MIT                                                           | 商用 (GitHub に含む)           | LGPL-3.0 (Community) / 商用                                       |
| コメント形式 | PR インラインコメント                                         | Security タブ + PR             | PR デコレーション                                                 |
| 対応リンター | 任意 (出力パース)                                             | SARIF 形式対応ツール           | 組み込みルール                                                    |
| セルフホスト | 不要 (CI 内実行)                                              | 不要                           | 必要 (or Cloud版)                                                 |
| 料金         | 無料                                                          | 無料 (Public) / 有料 (Private) | 有料 (Community版は無料)                                          |

### 選定ガイドライン

**→ reviewdog を採用する。** 任意のリンターと組み合わせて PR インラインコメントを生成でき、無料・軽量・導入が容易。

- コード品質メトリクス (技術的負債、重複率等) を組織全体で追跡したい場合は SonarQube を検討
- SARIF 形式で Security タブに一元集約したい場合は GitHub Code Scanning を検討

## コードカバレッジ: Codecov vs Coveralls vs SonarQube

| 比較項目                  | Codecov                                                             | Coveralls                                                                   | SonarQube                                                         |
| ------------------------- | ------------------------------------------------------------------- | --------------------------------------------------------------------------- | ----------------------------------------------------------------- |
| 提供元                    | Sentry (Codecov)                                                    | Coveralls                                                                   | SonarSource                                                       |
| リポジトリ                | [codecov/codecov-action](https://github.com/codecov/codecov-action) | [coverallsapp/github-action](https://github.com/coverallsapp/github-action) | [SonarSource/sonarqube](https://github.com/SonarSource/sonarqube) |
| ライセンス                | 商用 (SaaS)                                                         | 商用 (SaaS)                                                                 | LGPL-3.0 (Community) / 商用                                       |
| PR コメント               | ✅ (差分カバレッジ)                                                  | ✅                                                                           | ✅                                                                 |
| カバレッジゲート          | ✅                                                                   | ✅                                                                           | ✅                                                                 |
| フラグ/コンポーネント分割 | ✅                                                                   | ⚠️ 限定的                                                                    | ✅                                                                 |
| OIDC 認証                 | ✅                                                                   | ❌                                                                           | ❌                                                                 |
| 料金                      | 無料 (Public) / 有料 (Private)                                      | 無料 (Public) / 有料                                                        | 有料 (Community版は無料)                                          |

### 選定ガイドライン

**→ Codecov を採用する。** OIDC 対応でトークンレス運用が可能、PR 差分カバレッジの可視化が優秀、コンポーネント別分割管理に対応。

- カバレッジだけでなくコード品質全体を一元管理したい場合は SonarQube を検討

## CI/CD: GitHub Actions vs GitLab CI vs CircleCI vs Jenkins

| 比較項目             | GitHub Actions                            | GitLab CI                                                 | CircleCI               | Jenkins                                                   |
| -------------------- | ----------------------------------------- | --------------------------------------------------------- | ---------------------- | --------------------------------------------------------- |
| 提供元               | GitHub                                    | GitLab                                                    | CircleCI               | OSS (CloudBees)                                           |
| リポジトリ           | - (GitHub 組み込み)                       | [gitlabhq/gitlabhq](https://github.com/gitlabhq/gitlabhq) | - (SaaS)               | [jenkinsci/jenkins](https://github.com/jenkinsci/jenkins) |
| ライセンス           | 商用 (GitHub に含む)                      | MIT (CE) / 商用 (EE)                                      | 商用                   | MIT                                                       |
| ホスティング         | SaaS                                      | SaaS / セルフホスト                                       | SaaS / セルフホスト    | セルフホスト                                              |
| 設定ファイル         | `.github/workflows/*.yml`                 | `.gitlab-ci.yml`                                          | `.circleci/config.yml` | `Jenkinsfile`                                             |
| Reusable Workflow    | ✅ (reusable workflows, composite actions) | ✅ (include, extends)                                      | ✅ (orbs)               | ✅ (shared libraries)                                      |
| セルフホストランナー | ✅                                         | ✅                                                         | ✅ (runner)             | ✅ (agent)                                                 |
| コンテナ実行         | ✅                                         | ✅ (デフォルト)                                            | ✅ (デフォルト)         | ✅ (プラグイン)                                            |
| キャッシュ           | ✅ (actions/cache)                         | ✅ 組み込み                                                | ✅ 組み込み             | ⚠️ プラグイン依存                                          |
| シークレット管理     | ✅ (Encrypted secrets, OIDC)               | ✅ (Variables, Vault連携)                                  | ✅ (Contexts)           | ⚠️ プラグイン依存                                          |
| 料金 (Public)        | 無料                                      | 無料 (400分/月)                                           | 無料 (制限あり)        | 無料 (セルフホスト)                                       |
| 料金 (Private)       | 2,000分/月〜                              | 400分/月〜                                                | 6,000分/月〜           | 無料 (セルフホスト)                                       |

### 選定ガイドライン

**→ GitHub Actions を採用する。** GitHub をソースコード管理に使っている場合、最も統合がシームレスで学習コストが低い。Reusable Workflows による共通化、OIDC によるセキュアな認証、Marketplace の豊富な Actions が利用可能。

- GitLab をソースコード管理に使っている場合は GitLab CI 一択
- 高度な並列実行・リソースクラスの細かい制御が必要な場合は CircleCI を検討
- 完全なカスタマイズ性・オンプレミス要件がある場合は Jenkins を検討 (運用コスト高)
