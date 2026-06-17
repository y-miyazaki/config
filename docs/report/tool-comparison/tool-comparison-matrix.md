<!-- omit in toc -->
# Tool Comparison Matrix

ツール選定時の判断材料として、カテゴリ別に比較を行う。

<!-- omit in toc -->
## History

| 日付       | 内容                                                                 |
| ---------- | -------------------------------------------------------------------- |
| 2026-06-17 | 全般最新化: Biome v2.5.0 HTML/SVG対応反映、Semgrep Multimodal情報追加 |
| 2026-06-02 | Code Formatter セクション追加 (Prettier vs Biome vs deno fmt vs clang-format vs rustfmt) |
| 2026-05-26 | Version Management セクション mise Lazy Install 記述修正             |
| 2026-05-25 | Version Management セクションに mise 追加                            |
| 2026-05-25 | SAST / Code Pattern Analysis セクション追加 (Semgrep vs CodeQL vs SonarQube) |
| 2026-05-24 | tool-comparison 共通評価ルールドキュメントへのリンク更新             |
| 2026-05-23 | tool-comparison 共通評価基準ドキュメントへのリンク追加               |
| 2026-05-23 | AI Governance 比較ドキュメントへのリンク追加                         |
| 2026-05-21 | AI Workflow 比較ドキュメントへのリンク追加。History セクション追加    |
| 2026-05-12 | 初版作成。依存更新 / バージョン管理 / セキュリティ / CI/CD 等を比較 |

言語/技術スタック特化の比較は以下を参照:

- [共通評価ルール](tool-comparison-evaluation-rules.md)
- [Go](tool-comparison-matrix-go.md)
- [Terraform](tool-comparison-matrix-terraform.md)
- [Node.js](tool-comparison-matrix-nodejs.md)
- [Shell Script](tool-comparison-matrix-shell-script.md)
- [AWS](tool-comparison-matrix-aws.md)
- [AI Agent](tool-comparison-matrix-ai-agent.md)
- [AI Governance](tool-comparison-matrix-ai-governance.md)
- [AI Workflow](tool-comparison-matrix-ai-workflow.md)
- [AI Agent Hooks](tool-comparison-matrix-ai-agent-hooks.md)
- [AI Agent Guardrails](tool-comparison-matrix-ai-agent-guardrails.md)
- [AI MCP Server](tool-comparison-matrix-ai-mcp-server.md)

<!-- omit in toc -->
## Table of Contents

- [Dependency Updates: Dependabot vs Renovate](#dependency-updates-dependabot-vs-renovate)
  - [Guidelines](#guidelines)
- [Version Management: aqua vs asdf vs mise](#version-management-aqua-vs-asdf-vs-mise)
  - [Guidelines](#guidelines-1)
- [Security Scanning: Trivy vs Snyk vs Grype](#security-scanning-trivy-vs-snyk-vs-grype)
  - [Guidelines](#guidelines-2)
- [SAST / Code Pattern Analysis: Semgrep vs CodeQL vs SonarQube](#sast--code-pattern-analysis-semgrep-vs-codeql-vs-sonarqube)
  - [Guidelines](#guidelines-3)
- [Secret Detection: gitleaks vs detect-secrets vs truffleHog](#secret-detection-gitleaks-vs-detect-secrets-vs-trufflehog)
  - [Guidelines](#guidelines-4)
- [GitHub Actions Lint: actionlint vs ghalint vs zizmor](#github-actions-lint-actionlint-vs-ghalint-vs-zizmor)
  - [Guidelines](#guidelines-5)
- [GitHub Actions Pinning: pinact vs pin-github-action vs Renovate](#github-actions-pinning-pinact-vs-pin-github-action-vs-renovate)
  - [Guidelines](#guidelines-6)
- [PR Review Automation: reviewdog vs GitHub Code Scanning vs SonarQube](#pr-review-automation-reviewdog-vs-github-code-scanning-vs-sonarqube)
  - [Guidelines](#guidelines-7)
- [Code Coverage: Codecov vs Coveralls vs SonarQube](#code-coverage-codecov-vs-coveralls-vs-sonarqube)
  - [Guidelines](#guidelines-8)
- [Git Hooks Framework: pre-commit](#git-hooks-framework-pre-commit)
  - [Guidelines](#guidelines-9)
- [CI/CD: GitHub Actions vs GitLab CI vs CircleCI vs Jenkins](#cicd-github-actions-vs-gitlab-ci-vs-circleci-vs-jenkins)
  - [Guidelines](#guidelines-10)
- [Code Formatter: Prettier vs Biome vs deno fmt vs clang-format vs rustfmt](#code-formatter-prettier-vs-biome-vs-deno-fmt-vs-clang-format-vs-rustfmt)
  - [Guidelines](#guidelines-11)

## Dependency Updates: Dependabot vs Renovate

| 比較項目              | Dependabot                        | Renovate                                                        |
| --------------------- | --------------------------------- | --------------------------------------------------------------- |
| 提供元                | GitHub                            | Mend (旧 WhiteSource)                                           |
| リポジトリ            | - (GitHub 組み込み)               | [renovatebot/renovate](https://github.com/renovatebot/renovate) |
| ライセンス            | MIT                               | AGPL-3.0                                                        |
| 対応プラットフォーム  | GitHub のみ                       | GitHub / GitLab / Bitbucket / Azure DevOps                      |
| 設定ファイル          | `dependabot.yml`                  | `renovate.json` (JSON5対応、extends可)                          |
| 設定の柔軟性          | 中程度 (YAML ベース)              | 非常に高い (正規表現、プリセット共有)                           |
| Shareable Config      | ❌ リポジトリ毎に設定が必要        | ✅ extends で組織共通設定を共有可能                              |
| グルーピング          | ⚠️ `groups` (2024年追加、制限あり) | ✅ `group` ルールで柔軟にまとめられる                            |
| 自動マージ            | ⚠️ GitHub の auto-merge 機能に依存 | ✅ 組み込みサポート                                              |
| カスタム マネージャー | ❌ 対応エコシステムのみ            | ✅ regex manager で任意ファイル対応                              |
| 対応エコシステム数    | 20+                               | 90+                                                             |
| スケジュール制御      | 基本 (daily/weekly/monthly)       | 詳細 (cron式、timezone対応)                                     |
| セルフホスト          | ❌ GitHub 提供のみ                 | ✅ 可能                                                          |
| 料金                  | 無料 (GitHub 組み込み)            | 無料 (GitHub App) / セルフホスト無料                            |

### Guidelines

**→ Renovate を採用する。** 対応エコシステムの広さ、Shareable Config による組織横断の設定共有、グルーピング・自動マージの柔軟性で優位。

- GitHub 以外のプラットフォーム (GitLab 等) を使う場合は Renovate 一択
- GitHub Actions の更新のみなど限定的な用途であれば Dependabot 単体でも可
- 併用も有効: Dependabot (GitHub Actions) + Renovate (その他エコシステム)

## Version Management: aqua vs asdf vs mise

| 比較項目           | aqua                                              | asdf                                             | mise                                          |
| ------------------ | ------------------------------------------------- | ------------------------------------------------ | --------------------------------------------- |
| 提供元             | aquaproj                                          | asdf-vm                                          | jdx                                           |
| リポジトリ         | [aquaproj/aqua](https://github.com/aquaproj/aqua) | [asdf-vm/asdf](https://github.com/asdf-vm/asdf) | [jdx/mise](https://github.com/jdx/mise)       |
| ライセンス         | MIT                                               | MIT                                              | MIT                                           |
| 実装言語           | Go                                                | Shell Script (Bash)                              | Rust                                          |
| 設定ファイル       | `aqua.yaml`                                       | `.tool-versions`                                 | `mise.toml` / `.tool-versions`                |
| プラグインシステム | Registry (GitHub 集中管理)                        | Plugin (各リポジトリ分散)                        | 複数バックエンド (aqua, asdf, cargo, npm 等)  |
| Checksum 検証      | ✅ 組み込みサポート                                | ❌ プラグイン依存                                 | ✅ aqua バックエンド経由で対応                  |
| Lazy Install       | ✅ コマンド実行時に自動インストール                | ❌ 事前に `asdf install` が必要                   | ⚠️ `mise exec`/`mise run` 経由か、`mise activate` + shims 設定が必要。`not_found_auto_install` は既に別バージョンがインストール済みのツールのみ対応 |
| 実行速度           | 高速 (Go バイナリ)                                | 低速 (shim + shell script)                       | 高速 (Rust バイナリ、shim 不要)               |
| Renovate 対応      | ✅ datasource 指定で自動更新可能                   | ⚠️ 限定的                                         | ✅ mise manager で自動更新可能 (lockfile対応)       |
| 対応ツール数       | 2,900+ (standard registry)                        | 700+ (community plugins)                         | 900+ (registry) + asdf/aqua バックエンド経由  |
| Windows 対応       | ✅                                                 | ❌ (WSL 経由のみ)                                 | ✅ (非 asdf バックエンドのみ)                   |
| セキュリティ       | 高い (checksum必須化可能)                         | 低い (プラグイン任意実行)                        | 高い (aqua バックエンド経由で署名検証対応)    |
| タスクランナー     | ❌                                                 | ❌                                                | ✅ 組み込みサポート                             |
| 環境変数管理       | ❌                                                 | ❌                                                | ✅ 組み込みサポート                             |
| asdf 互換性        | ❌                                                 | -                                                | ✅ `.tool-versions` 読み込み・asdf プラグイン対応 |

### Guidelines

**→ aqua または mise を採用する。** どちらも高速・セキュアで Renovate による自動更新に対応しており、用途に応じて選択する。

- **aqua を選ぶ場合**: `aqua-policy.yaml` によるインストール許可ツールのポリシー制御が可能。CI でのバージョン管理に特化したシンプルな設計で、組織全体のツール制限を強制できる
- **mise を選ぶ場合**: aqua を backend として取り込めるため aqua registry の checksum/署名検証をそのまま利用可能。加えてタスクランナー・環境変数管理・lockfile (`mise.lock`) を統合し、単一ツールで開発環境全体をカバーできる。Rust 実装で高速、Renovate の mise manager で lockfile 含む自動更新に対応。ただし Lazy Install は aqua と異なり、初回は `mise install` が必要 (`not_found_auto_install` は既に別バージョンがインストール済みのツールのみ対応)。新規ツールの自動インストールには `mise exec`/`mise run` を使うか、事前に `mise install` を実行する必要がある
- Node.js/Ruby/Python 等のランタイム管理が主目的で、チームが既に asdf に慣れている場合は asdf でも可

## Security Scanning: Trivy vs Snyk vs Grype

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

### Guidelines

**→ Trivy を採用する。** OSS・無料で IaC + コンテナ + SBOM + シークレット検出を一つでカバーでき、スキャン範囲が最も広い。

- 脆弱性の修正 PR を自動生成したい / 商用サポートが必要な場合は Snyk を検討
- コンテナイメージ特化で Syft と組み合わせた SBOM ベーススキャンが必要な場合は Grype を検討

## SAST / Code Pattern Analysis: Semgrep vs CodeQL vs SonarQube

| 比較項目             | Semgrep                                                   | CodeQL                                                    | SonarQube                                                         |
| -------------------- | --------------------------------------------------------- | --------------------------------------------------------- | ----------------------------------------------------------------- |
| 提供元               | Semgrep, Inc.                                             | GitHub (Microsoft)                                        | SonarSource                                                       |
| リポジトリ           | [semgrep/semgrep](https://github.com/semgrep/semgrep)     | [github/codeql](https://github.com/github/codeql)        | [SonarSource/sonarqube](https://github.com/SonarSource/sonarqube) |
| ドキュメント         | [semgrep.dev/docs](https://semgrep.dev/docs)              | [codeql.github.com](https://codeql.github.com)           | [docs.sonarsource.com](https://docs.sonarsource.com/sonarqube)    |
| ライセンス           | LGPL-2.1 (OSS Engine) / 商用 (Platform)                   | MIT (クエリ) / 商用 (GitHub Advanced Security)            | LGPL-3.0 (CE) / 商用 (DE/EE)                                     |
| 対応言語数           | 35+                                                       | 20+                                                       | 35+                                                               |
| ルール記述           | YAML (パターンベース)                                     | QL (データフロー言語)                                     | Java (プラグイン)                                                 |
| カスタムルール容易性 | ✅ 高い (YAML、数分で記述可能)                             | ⚠️ 中程度 (QL学習コストあり)                               | ⚠️ 低い (Java実装が必要)                                          |
| クロスファイル解析   | ✅ (Pro Engine)                                            | ✅                                                         | ✅                                                                 |
| テイント解析         | ✅ (クロスファンクション)                                  | ✅ (深いデータフロー)                                      | ✅                                                                 |
| 解析深度             | パターンマッチ + テイント                                 | セマンティック (最も深い)                                  | データフロー + 品質メトリクス                                     |
| スキャン速度         | ✅ 高速 (~10秒)                                            | ⚠️ 低速 (数分〜30分+)                                      | ⚠️ 中程度                                                         |
| CI/CD 統合           | ✅ (GitHub/GitLab/任意CI)                                  | ✅ (GitHub Actions ネイティブ)                              | ✅ (任意CI)                                                        |
| IDE 統合             | ✅ (VS Code, JetBrains)                                    | ⚠️ (VS Code のみ)                                          | ✅ (SonarLint: VS Code, JetBrains等)                               |
| 品質ゲート           | ❌                                                         | ❌                                                         | ✅ (カバレッジ、重複、信頼性)                                      |
| 自動修正 (Autofix)   | ✅ (AI-powered)                                            | ✅ (Copilot Autofix)                                       | ⚠️ 限定的                                                         |
| AI トリアージ        | ✅ (Semgrep Assistant)                                     | ⚠️ (Copilot連携)                                           | ⚠️ (AI CodeFix)                                                    |
| 誤検知率             | 低い                                                      | 低い                                                      | 中程度                                                            |
| 料金 (無料枠)        | Free: 10リポジトリ/10人まで (60 AI credits含む)            | 無料 (公開リポジトリ)                                     | Community Edition: 無料                                           |
| 料金 (有料)          | Teams: $30/contributor/月 (20 AI credits/dev)              | Code Security: $30/committer/月 (GHAS)                    | Developer Edition: $150/年〜                                      |
| 料金ページ           | [semgrep.dev/pricing](https://semgrep.dev/pricing)        | [github.com/pricing](https://github.com/pricing)         | [sonarsource.com/plans](https://www.sonarsource.com/plans-and-pricing/) |
| オフライン実行       | ✅ (CLI)                                                   | ✅ (CLI)                                                   | ✅ (セルフホスト)                                                  |
| SaaS / セルフホスト  | 両方                                                      | SaaS (GitHub) / CLI                                       | セルフホスト / SonarCloud (SaaS)                                  |

### Guidelines

**→ Semgrep を採用する。** カスタムルールの記述容易性 (YAML)、スキャン速度、CI統合の柔軟性のバランスが最も良い。OSS Engine (CLI) は無料で利用可能。Semgrep Multimodal (AI + ルール解析の併用) が新たに追加され、従来のパターンマッチだけでは検出困難な問題もカバー可能。

- GitHub をメインで使い GHAS を契約済みの場合は CodeQL が追加コストなしで利用可能。解析深度は最も高いがスキャン時間が長い
- コード品質ゲート (カバレッジ閾値、重複検出等) も統合したい場合は SonarQube を検討。SAST単体としては Semgrep/CodeQL に劣る
- Semgrep + CodeQL の併用も有効。Semgrep で高速フィードバック (PR時)、CodeQL で深い解析 (定期スキャン) と使い分ける

## Secret Detection: gitleaks vs detect-secrets vs truffleHog

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

### Guidelines

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

### Guidelines

**→ 3つ全て併用する。** 検出対象が異なるため、組み合わせることでカバレッジが最大化される。actionlint (構文・型) + ghalint (セキュリティプラクティス) + zizmor (セキュリティ設定)。

## GitHub Actions Pinning: pinact vs pin-github-action vs Renovate

| 比較項目   | pinact                                                              | pin-github-action                                                     | Renovate (pinDigests)                                           |
| ---------- | ------------------------------------------------------------------- | --------------------------------------------------------------------- | --------------------------------------------------------------- |
| 提供元     | suzuki-shunsuke                                                     | mheap                                                                 | Mend                                                            |
| リポジトリ | [suzuki-shunsuke/pinact](https://github.com/suzuki-shunsuke/pinact) | [mheap/pin-github-action](https://github.com/mheap/pin-github-action) | [renovatebot/renovate](https://github.com/renovatebot/renovate) |
| ライセンス | MIT                                                                 | MIT                                                                   | AGPL-3.0                                                        |
| 用途       | Action をフルSHAにピン留め                                          | Action をフルSHAにピン留め                                            | ピン留め + 自動更新                                             |
| 一括変換   | ✅                                                                   | ✅                                                                     | ❌ (PR ベース)                                                   |
| 自動更新   | ❌ (Renovate と併用)                                                 | ❌                                                                     | ✅                                                               |

### Guidelines

**→ pinact + Renovate を併用する。** pinact で既存ワークフローを一括ピン留めし、Renovate (pinDigests) で継続的に SHA を自動更新する。

## PR Review Automation: reviewdog vs GitHub Code Scanning vs SonarQube

| 比較項目     | reviewdog                                                     | GitHub Code Scanning           | SonarQube                                                         |
| ------------ | ------------------------------------------------------------- | ------------------------------ | ----------------------------------------------------------------- |
| 提供元       | haya14busa                                                    | GitHub                         | SonarSource                                                       |
| リポジトリ   | [reviewdog/reviewdog](https://github.com/reviewdog/reviewdog) | - (GitHub 組み込み)            | [SonarSource/sonarqube](https://github.com/SonarSource/sonarqube) |
| ライセンス   | MIT                                                           | 商用 (GitHub に含む)           | LGPL-3.0 (Community) / 商用                                       |
| コメント形式 | PR インラインコメント                                         | Security タブ + PR             | PR デコレーション                                                 |
| 対応リンター | 任意 (出力パース)                                             | SARIF 形式対応ツール           | 組み込みルール                                                    |
| セルフホスト | 不要 (CI 内実行)                                              | 不要                           | 必要 (or Cloud版)                                                 |
| 料金         | 無料                                                          | 無料 (Public) / 有料 (Private) | 有料 (Community版は無料)                                          |

### Guidelines

**→ reviewdog を採用する。** 任意のリンターと組み合わせて PR インラインコメントを生成でき、無料・軽量・導入が容易。

- コード品質メトリクス (技術的負債、重複率等) を組織全体で追跡したい場合は SonarQube を検討
- SARIF 形式で Security タブに一元集約したい場合は GitHub Code Scanning を検討

## Code Coverage: Codecov vs Coveralls vs SonarQube

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

### Guidelines

**→ Codecov を採用する。** OIDC 対応でトークンレス運用が可能、PR 差分カバレッジの可視化が優秀、コンポーネント別分割管理に対応。

- カバレッジだけでなくコード品質全体を一元管理したい場合は SonarQube を検討

## Git Hooks Framework: pre-commit

| 比較項目       | pre-commit                                                        |
| -------------- | ----------------------------------------------------------------- |
| 提供元         | pre-commit                                                        |
| リポジトリ     | [pre-commit/pre-commit](https://github.com/pre-commit/pre-commit) |
| ライセンス     | MIT                                                               |
| 実装言語       | Python                                                            |
| 対応フック     | 任意言語 (YAML で定義)                                            |
| マルチ言語対応 | ✅ (Go, Python, Node.js, Shell 等)                                 |
| キャッシュ     | ✅ (フック環境を自動キャッシュ)                                    |
| CI 統合        | ✅ (`pre-commit run --all-files`)                                  |

### Guidelines

**→ pre-commit を採用する。** Git hooks のデファクトスタンダード。言語を問わず任意のリンター・フォーマッターを pre-commit/pre-push フックとして統一管理できる。代替ツール (husky + lint-staged 等) は Node.js 特化のため、多言語プロジェクトでは pre-commit が最適。

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

### Guidelines

**→ GitHub Actions を採用する。** GitHub をソースコード管理に使っている場合、最も統合がシームレスで学習コストが低い。Reusable Workflows による共通化、OIDC によるセキュアな認証、Marketplace の豊富な Actions が利用可能。

- GitLab をソースコード管理に使っている場合は GitLab CI 一択
- 高度な並列実行・リソースクラスの細かい制御が必要な場合は CircleCI を検討
- 完全なカスタマイズ性・オンプレミス要件がある場合は Jenkins を検討 (運用コスト高)

## Code Formatter: Prettier vs Biome vs deno fmt vs clang-format vs rustfmt

コードフォーマッターの比較。言語固有フォーマッター (gofumpt, shfmt 等) は各言語別ドキュメントを参照。ここでは多言語対応フォーマッターおよび代表的な言語固有フォーマッターのアーキテクチャを比較する。

| 比較項目             | Prettier                                                    | Biome                                               | deno fmt                                            | clang-format                                        | rustfmt                                               |
| -------------------- | ----------------------------------------------------------- | --------------------------------------------------- | --------------------------------------------------- | --------------------------------------------------- | ----------------------------------------------------- |
| 提供元               | Prettier                                                    | Biome                                               | Deno Land                                           | LLVM Project                                        | Rust Project                                          |
| リポジトリ           | [prettier/prettier](https://github.com/prettier/prettier)   | [biomejs/biome](https://github.com/biomejs/biome)   | [denoland/deno](https://github.com/denoland/deno)   | [llvm/llvm-project](https://github.com/llvm/llvm-project) | [rust-lang/rustfmt](https://github.com/rust-lang/rustfmt) |
| ドキュメント         | [prettier.io](https://prettier.io/docs/en/)                 | [biomejs.dev](https://biomejs.dev)                  | [docs.deno.com](https://docs.deno.com/runtime/reference/cli/fmt/) | [clang.llvm.org](https://clang.llvm.org/docs/ClangFormat.html) | [rust-lang.github.io](https://rust-lang.github.io/rustfmt/) |
| ライセンス           | MIT                                                         | MIT                                                 | MIT                                                 | Apache-2.0 with LLVM Exception                      | Apache-2.0 / MIT                                      |
| 実装言語             | JavaScript                                                  | Rust                                                | Rust                                                | C++                                                 | Rust                                                  |
| 対応言語             | JS/TS/JSX/TSX/CSS/HTML/JSON/YAML/Markdown/GraphQL等         | JS/TS/JSX/TSX/CSS/JSON/GraphQL/HTML/SVG (Vue/Svelte/Astroは実験的) | JS/TS/JSX/TSX/JSON/Markdown/YAML/CSS/HTML           | C/C++/Objective-C/Java/C#/Proto                     | Rust                                                  |
| 設定ファイル         | `.prettierrc` (JSON/YAML/TOML/JS)                           | `biome.json` / `biome.jsonc`                        | `deno.json` (`fmt` セクション)                      | `.clang-format` (YAML)                              | `rustfmt.toml` / `.rustfmt.toml`                      |
| 設定オプション数     | 少ない (Opinionated)                                        | 少ない (Opinionated)                                | 極少 (Opinionated)                                  | 多い (100+)                                         | 多い (60+、nightly のみのオプション含む)               |
| Linter 統合          | ❌ (別途 ESLint)                                             | ✅ 組み込み (ESLint互換ルール)                       | ✅ 組み込み (`deno lint`)                            | ❌ (別途 clang-tidy)                                 | ❌ (別途 clippy)                                       |
| 実行速度             | 低速 (Node.js)                                              | ✅ 高速 (Rust、Prettier比 25-35x)                    | ✅ 高速 (Rust)                                       | ✅ 高速 (C++)                                        | ✅ 高速 (Rust)                                         |
| プラグインシステム   | ✅ (言語追加プラグイン)                                      | ❌ (組み込みのみ)                                    | ❌ (組み込みのみ)                                    | ❌                                                   | ❌                                                     |
| エディタ統合         | ✅ (VS Code/JetBrains/Vim等、広範)                           | ✅ (VS Code/JetBrains/Vim等)                         | ✅ (VS Code/JetBrains)                               | ✅ (VS Code/JetBrains/Vim等)                         | ✅ (VS Code/JetBrains/Vim等)                           |
| Ignore ファイル      | `.prettierignore`                                           | 設定内 `ignore` / CLI `--ignore`                    | 設定内 `exclude`                                    | ❌ (CLI で指定)                                      | `rustfmt.toml` 内 `ignore`                            |
| CI 統合 (check mode) | ✅ (`--check`)                                               | ✅ (`check --formatter-enabled=true`)                | ✅ (`fmt --check`)                                   | ✅ (`--dry-run --Werror`)                            | ✅ (`--check`)                                         |
| pre-commit 対応      | ✅ (mirrors-prettier)                                        | ✅ (biomejs/pre-commit)                              | ⚠️ (カスタム定義)                                    | ✅ (pre-commit/mirrors-clang-format)                 | ✅ (doublify/pre-commit-rust)                          |
| Node.js 依存         | ✅ 必須                                                      | ❌ 不要 (単一バイナリ)                               | ❌ 不要 (Deno ランタイム)                            | ❌ 不要                                              | ❌ 不要 (rustup 経由)                                  |
| Prettier 互換性      | -                                                           | ✅ 97%互換 (移行容易)                                | ⚠️ 類似だが非互換                                    | ❌                                                   | ❌                                                     |
| Markdown フォーマット | ✅                                                           | ❌                                                   | ✅                                                   | ❌                                                   | ❌                                                     |
| YAML フォーマット    | ✅                                                           | ❌                                                   | ✅                                                   | ❌                                                   | ❌                                                     |
| 料金                 | 無料                                                        | 無料                                                | 無料                                                | 無料                                                | 無料                                                  |

### Guidelines

**→ 言語スタックに応じて使い分ける。** 単一の万能フォーマッターは存在しないため、プロジェクトの言語構成に合わせて選択する。

- **Web フロントエンド (JS/TS/CSS/HTML)**: Biome を第一候補とする。Prettier比 25-35x の高速性、Linter統合による単一ツール化、Node.js不要で CI が軽量化。Prettier 97% 互換のため移行コストが低い。v2.5.0 で HTML/SVG のフォーマット+Lintが本番対応 (Vue/Svelte/Astro は実験的)
- **Prettier を選ぶ場合**: プラグインによる追加言語対応が必要な場合 (PHP, Ruby, Svelte等)、または Biome 未対応のフォーマット (Markdown, YAML) が重要な場合。エコシステムの成熟度・プラグイン数では依然最大
- **Deno プロジェクト**: deno fmt 一択。設定不要で Deno ランタイムに統合されており、追加の依存が不要
- **C/C++ プロジェクト**: clang-format 一択。LLVM エコシステムのデファクトスタンダード。設定項目が多いためチームで `.clang-format` を共有し BasedOnStyle を固定する
- **Rust プロジェクト**: rustfmt 一択。`cargo fmt` として標準ツールチェーンに含まれ、追加インストール不要
- **Go プロジェクト**: gofumpt を使用 (Go 別ドキュメント参照)。本比較の対象外
- **多言語リポジトリ**: Biome (JS/TS/CSS/JSON) + 言語固有ツール (gofumpt, rustfmt, shfmt 等) の組み合わせ。pre-commit で統一的に実行する
