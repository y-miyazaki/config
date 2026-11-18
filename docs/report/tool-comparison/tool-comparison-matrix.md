# Tool Comparison Matrix

ツール選定時の判断材料として、カテゴリ別に比較を行う。

## History

| 日付       | 内容                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   |
| ---------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 2026-11-18 | Markdown Link Check セクション追加 (lychee vs markdown-link-check)、Supply Chain / Provenance セクション追加 (cosign vs OSV-Scanner vs Scorecard vs syft)                                                                                                                                                                                                                                                                                                                                                                                                                                                              |
| 2026-11-18 | 全般最新化: Biome v2.6 の Markdown/YAML/SCSS 対応、mise Lazy Install (v2026.9.0+)、Dependabot/Renovate 対応数、CodeQL 対応言語数、料金 (Snyk / SonarQube / Codecov / CircleCI / GitHub Actions) を公式情報に更新。gitleaks の保守状況 (feature complete・セキュリティ修正のみ、メンテナは Betterleaks へ移行) と Betterleaks、Trivy の 2026-03 サプライチェーン侵害、prek、Opengrep を追記。追記: 公式で確認し Coveralls 料金を更新 (coveralls.io/pricing)。SonarQube Community Build の LGPL-3.0・Renovate の AGPL-3.0・Snyk CLI の Apache-2.0 を確認。mise / aqua の登録ツール数は公式に総数の記載がなく未確認のまま |
| 2026-08-23 | Biome HTML/SVG Formatter は実験的である点を公式 Language support に合わせて訂正。aqua Standard Registry パッケージ数を 2,200+ に更新                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   |
| 2026-06-17 | 全般最新化: Biome v2.5.0 HTML/SVG 対応反映、Semgrep Multimodal 情報追加                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                |
| 2026-06-02 | Code Formatter セクション追加 (Prettier vs Biome vs deno fmt vs clang-format vs rustfmt)                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               |
| 2026-05-26 | Version Management セクション mise Lazy Install 記述修正                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               |
| 2026-05-25 | Version Management セクションに mise 追加                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              |
| 2026-05-25 | SAST / Code Pattern Analysis セクション追加 (Semgrep vs CodeQL vs SonarQube)                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           |
| 2026-05-24 | tool-comparison 共通評価ルールドキュメントへのリンク更新                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               |
| 2026-05-23 | tool-comparison 共通評価基準ドキュメントへのリンク追加                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 |
| 2026-05-23 | AI Governance 比較ドキュメントへのリンク追加                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           |
| 2026-05-21 | AI Workflow 比較ドキュメントへのリンク追加。History セクション追加                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     |
| 2026-05-12 | 初版作成。依存更新 / バージョン管理 / セキュリティ / CI/CD 等を比較                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    |

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
- [AI Spec-Driven Development](tool-comparison-matrix-ai-spec-driven.md)
- [Docs Site Generator](tool-comparison-matrix-docs.md)

## Dependency Updates: Dependabot vs Renovate

| 比較項目              | Dependabot                          | Renovate                                                        |
| --------------------- | ----------------------------------- | --------------------------------------------------------------- |
| 提供元                | GitHub                              | Mend (旧 WhiteSource)                                           |
| リポジトリ            | - (GitHub 組み込み)                 | [renovatebot/renovate](https://github.com/renovatebot/renovate) |
| ライセンス            | MIT                                 | AGPL-3.0                                                        |
| 対応プラットフォーム  | GitHub のみ                         | GitHub / GitLab / Bitbucket / Azure DevOps                      |
| 設定ファイル          | `dependabot.yml`                    | `renovate.json` (JSON5 対応、extends 可)                        |
| 設定の柔軟性          | 中程度 (YAML ベース)                | 非常に高い (正規表現、プリセット共有)                           |
| Shareable Config      | ❌ リポジトリ毎に設定が必要         | ✅ extends で組織共通設定を共有可能                             |
| グルーピング          | ⚠️ `groups` (2024 年追加、制限あり) | ✅ `group` ルールで柔軟にまとめられる                           |
| 自動マージ            | ⚠️ GitHub の auto-merge 機能に依存  | ✅ 組み込みサポート                                             |
| カスタム マネージャー | ❌ 対応エコシステムのみ             | ✅ regex manager で任意ファイル対応                             |
| 対応エコシステム数    | 30+ (公式対応表の行数)              | 120+ (公式 Managers 一覧)                                       |
| スケジュール制御      | 基本 (daily/weekly/monthly)         | 詳細 (cron 式、timezone 対応)                                   |
| セルフホスト          | ❌ GitHub 提供のみ                  | ✅ 可能                                                         |
| 料金                  | 無料 (GitHub 組み込み)              | 無料 (GitHub App) / セルフホスト無料                            |

### Guidelines

**→ Renovate を採用する。** 対応エコシステムの広さ、Shareable Config による組織横断の設定共有、グルーピング・自動マージの柔軟性で優位。

- GitHub 以外のプラットフォーム (GitLab 等) を使う場合は Renovate 一択
- GitHub Actions の更新のみなど限定的な用途であれば Dependabot 単体でも可
- 併用も有効: Dependabot (GitHub Actions) + Renovate (その他エコシステム)

## Version Management: aqua vs asdf vs mise

| 比較項目           | aqua                                                                           | asdf                                            | mise                                                                                                                                                                                             |
| ------------------ | ------------------------------------------------------------------------------ | ----------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| 提供元             | aquaproj                                                                       | asdf-vm                                         | jdx                                                                                                                                                                                              |
| リポジトリ         | [aquaproj/aqua](https://github.com/aquaproj/aqua)                              | [asdf-vm/asdf](https://github.com/asdf-vm/asdf) | [jdx/mise](https://github.com/jdx/mise)                                                                                                                                                          |
| ライセンス         | MIT                                                                            | MIT                                             | MIT                                                                                                                                                                                              |
| 実装言語           | Go                                                                             | Shell Script (Bash)                             | Rust                                                                                                                                                                                             |
| 設定ファイル       | `aqua.yaml`                                                                    | `.tool-versions`                                | `mise.toml` / `.tool-versions`                                                                                                                                                                   |
| プラグインシステム | Registry (GitHub 集中管理)                                                     | Plugin (各リポジトリ分散)                       | 複数バックエンド (aqua, asdf, cargo, npm 等)                                                                                                                                                     |
| Checksum 検証      | ✅ 組み込みサポート                                                            | ❌ プラグイン依存                               | ✅ aqua バックエンド経由で対応                                                                                                                                                                   |
| Lazy Install       | ✅ コマンド実行時に自動インストール                                            | ❌ 事前に `asdf install` が必要                 | ⚠️ ツールに `lazy = true` (+ `lazy_bins`) を指定すると初回コマンド実行時にインストール (mise v2026.9.0 以降。素の `mise install` は lazy ツールをスキップ)。未指定ツールは `mise install` が必要 |
| 実行速度           | 高速 (Go バイナリ)                                                             | 低速 (shim + shell script)                      | 高速 (Rust バイナリ、shim 不要)                                                                                                                                                                  |
| Renovate 対応      | ✅ datasource 指定で自動更新可能                                               | ⚠️ 限定的                                       | ✅ mise manager で自動更新可能 (lockfile 対応)                                                                                                                                                   |
| 対応ツール数       | 2,200+ (standard registry、2026-08 時点の値。公式に総数の記載がなく再確認不可) | 800+ (community plugins)                        | 900+ (registry、公式に総数の記載がなく未確認) + asdf/aqua バックエンド経由                                                                                                                       |
| Windows 対応       | ✅                                                                             | ❌ (WSL 経由のみ)                               | ✅ (非 asdf バックエンドのみ)                                                                                                                                                                    |
| セキュリティ       | 高い (checksum 必須化可能)                                                     | 低い (プラグイン任意実行)                       | 高い (aqua バックエンド経由で署名検証対応)                                                                                                                                                       |
| タスクランナー     | ❌                                                                             | ❌                                              | ✅ 組み込みサポート                                                                                                                                                                              |
| 環境変数管理       | ❌                                                                             | ❌                                              | ✅ 組み込みサポート                                                                                                                                                                              |
| asdf 互換性        | ❌                                                                             | -                                               | ✅ `.tool-versions` 読み込み・asdf プラグイン対応                                                                                                                                                |

### Guidelines

**→ aqua または mise を採用する。** どちらも高速・セキュアで Renovate による自動更新に対応しており、用途に応じて選択する。

- **aqua を選ぶ場合**: `aqua-policy.yaml` によるインストール許可ツールのポリシー制御が可能。CI でのバージョン管理に特化したシンプルな設計で、組織全体のツール制限を強制できる
- **mise を選ぶ場合**: aqua を backend として取り込めるため aqua registry の checksum/署名検証をそのまま利用可能。加えてタスクランナー・環境変数管理・lockfile (`mise.lock`) を統合し、単一ツールで開発環境全体をカバーできる。Rust 実装で高速、Renovate の mise manager で lockfile 含む自動更新に対応。Lazy Install は v2026.9.0 以降 `lazy = true` (レジストリ外のバックエンドは `lazy_bins` も必要) を指定したツールで利用可能。素の `mise install` は lazy ツールをスキップし、初回のコマンド実行 (shim) でインストールされる。未指定のツールは従来どおり `mise install` が必要。`minimum_release_age` / `locked` / provenance 検証 (SLSA・Cosign・Minisign・GitHub attestations) でサプライチェーン対策も可能
- Node.js/Ruby/Python 等のランタイム管理が主目的で、チームが既に asdf に慣れている場合は asdf でも可

## Security Scanning: Trivy vs Snyk vs Grype

| 比較項目         | Trivy                                                       | Snyk                                                                                                    | Grype                                             |
| ---------------- | ----------------------------------------------------------- | ------------------------------------------------------------------------------------------------------- | ------------------------------------------------- |
| 提供元           | Aqua Security                                               | Snyk Ltd                                                                                                | Anchore                                           |
| リポジトリ       | [aquasecurity/trivy](https://github.com/aquasecurity/trivy) | [snyk/cli](https://github.com/snyk/cli)                                                                 | [anchore/grype](https://github.com/anchore/grype) |
| ライセンス       | Apache 2.0                                                  | Apache 2.0 (CLI) / 商用 (サービス)                                                                      | Apache 2.0                                        |
| コンテナスキャン | ✅                                                          | ✅                                                                                                      | ✅                                                |
| IaC スキャン     | ✅ (Terraform, K8s 等)                                      | ✅                                                                                                      | ❌                                                |
| SBOM 生成        | ✅                                                          | ✅                                                                                                      | ✅ (Syft 連携)                                    |
| シークレット検出 | ✅                                                          | ❌ (別製品)                                                                                             | ❌                                                |
| 脆弱性 DB        | 複数ソース統合                                              | Snyk 独自 DB                                                                                            | Grype DB                                          |
| 修正提案         | ⚠️ 限定的                                                   | ✅ 自動 PR 作成                                                                                         | ❌                                                |
| オフライン実行   | ✅ (DB 事前 DL)                                             | ❌                                                                                                      | ✅ (DB 事前 DL)                                   |
| 料金             | 無料                                                        | Free (5 プロジェクト、Snyk Code 100 tests/月) / Team \$25/月〜 (100 プロジェクト) / Enterprise 要問合せ | 無料                                              |

### Guidelines

**→ Trivy を採用する。** OSS・無料で IaC + コンテナ + SBOM + シークレット検出を一つでカバーでき、スキャン範囲が最も広い。

- 脆弱性の修正 PR を自動生成したい / 商用サポートが必要な場合は Snyk を検討
- コンテナイメージ特化で Syft と組み合わせた SBOM ベーススキャンが必要な場合は Grype を検討
- 2026-03-19 に Trivy のサプライチェーン侵害 (GHSA-69fq-xp46-6x23、CVE-2026-33634) が発生し、悪意ある v0.69.4 と trivy-action タグの上書きが確認された。バージョンは advisory 記載の安全な版 (v0.69.2 / v0.69.3) を確認のうえ固定し、GitHub Actions はフル SHA で参照する (本リポジトリは `mise.toml` で 0.76.2 を pin)

## Supply Chain / Provenance: cosign vs OSV-Scanner vs Scorecard vs syft

4 ツールは責務が異なる (cosign = 署名・検証 / OSV-Scanner = 依存の脆弱性照合 / Scorecard = リポジトリのセキュリティ姿勢評価 / syft = SBOM 生成)。代替ではなく補完関係にあるため、同一課題の代替比較ではなく「どの責務を担うか」で選ぶ。

| 比較項目                 | cosign                                                                         | OSV-Scanner                                                                          | Scorecard                                                                                      | syft                                                                          |
| ------------------------ | ------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------ | ---------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------- |
| 提供元                   | Sigstore (OpenSSF)                                                             | Google                                                                               | OpenSSF                                                                                        | Anchore                                                                       |
| リポジトリ               | [sigstore/cosign](https://github.com/sigstore/cosign)                          | [google/osv-scanner](https://github.com/google/osv-scanner)                          | [ossf/scorecard](https://github.com/ossf/scorecard)                                            | [anchore/syft](https://github.com/anchore/syft)                               |
| ドキュメント             | [docs.sigstore.dev/cosign](https://docs.sigstore.dev/cosign/signing/overview/) | [google.github.io/osv-scanner](https://google.github.io/osv-scanner/)                | [scorecard.dev](https://scorecard.dev)                                                         | [oss.anchore.com/docs](https://oss.anchore.com/docs/)                         |
| ライセンス               | Apache-2.0                                                                     | Apache-2.0                                                                           | Apache-2.0                                                                                     | Apache-2.0                                                                    |
| 提供形態                 | CLI / コンテナイメージ                                                         | CLI / Go ライブラリ / コンテナイメージ                                               | CLI / コンテナイメージ / REST API                                                              | CLI / Go ライブラリ                                                           |
| 主用途                   | 署名・検証・in-toto attestation                                                | 依存関係と OSV 脆弱性 DB の照合                                                      | リポジトリの運用・設定を 0–10 点で採点                                                         | コンテナイメージ・ファイルシステムの SBOM 生成                                |
| 実行例                   | `cosign sign <image>` / `cosign verify`                                        | `osv-scanner scan source -r ./`                                                      | `scorecard --repo=github.com/<owner>/<repo>`                                                   | `syft <image> -o spdx-json=./spdx.json`                                       |
| aqua / mise 提供         | ✅ aqua registry 掲載 (`aqua:sigstore/cosign`)                                 | ✅ aqua registry 掲載 (`aqua:google/osv-scanner`)                                    | ✅ aqua registry 掲載 (`aqua:ossf/scorecard`)                                                  | ✅ aqua registry 掲載 (`aqua:anchore/syft`)                                   |
| 他のインストール         | Homebrew / Arch / Nix / `go install` / `ghcr.io/sigstore/cosign/cosign`        | `ghcr.io/google/osv-scanner` (Docker) / pre-commit hook                              | Docker (`ghcr.io/ossf/scorecard`) / Homebrew / Nix / AUR / リリースバイナリ (SLSA3 provenance) | インストールスクリプト / Homebrew / Docker / Scoop / Chocolatey / Nix         |
| GitHub Action            | [sigstore/cosign-installer](https://github.com/sigstore/cosign-installer)      | `google/osv-scanner-action` (reusable workflow: PR 差分スキャン / フルスキャン)      | [ossf/scorecard-action](https://github.com/ossf/scorecard-action)                              | [anchore/sbom-action](https://github.com/anchore/sbom-action) (syft をラップ) |
| 出力形式                 | - (署名・attestation を OCI レジストリまたは bundle に保存)                    | table / json / sarif ほか (`--format`)。GitHub Action は SARIF を Code Scanning へ   | default (text) / json (README 記載)                                                            | SPDX / CycloneDX / syft-json ほか。形式間変換も可                             |
| SBOM 対応                | ⚠️ SBOM を署名対象 (attestation) として扱える                                  | ⚠️ `--all-packages` で SPDX / CycloneDX 出力可。SBOM 入力は公式ドキュメントで 未確認 | ❌                                                                                             | ✅ 生成が主機能                                                               |
| キーレス署名             | ✅ (Fulcio + Rekor + OIDC がデフォルト)                                        | ❌                                                                                   | ❌                                                                                             | ❌ (in-toto attestation 作成は可、署名は cosign と併用する運用)               |
| 脆弱性照合               | ❌                                                                             | ✅ (OSV.dev)                                                                         | ⚠️ Vulnerabilities チェックのみ (OSV 利用)                                                     | ❌ (Grype 等と併用)                                                           |
| オフライン実行           | ⚠️ bundle による検証が可能 (README は一部古い旨を記載)                         | ✅ `--offline-vulnerabilities` + `--download-offline-databases`                      | ❌ (GitHub / GitLab API が前提)                                                                | ✅ (ローカルのイメージ・ディレクトリを対象)                                   |
| 本リポジトリでの位置づけ | `mise.toml` の `settings.aqua.cosign` でツール取得時の署名検証に利用           | 未採用                                                                               | 未採用                                                                                         | 未採用                                                                        |
| 料金                     | 無料                                                                           | 無料                                                                                 | 無料                                                                                           | 無料                                                                          |

### Guidelines

**→ 責務ごとに必要なものを併用する。** 4 ツールは代替関係ではなく補完関係にある。単体で全責務をカバーするツールはない。

- 選定方針: まず必要な責務 (署名 / 脆弱性照合 / 姿勢評価 / SBOM) を特定し、責務ごとに 1 ツールを選ぶ
- 採用条件:
  - 成果物 (コンテナイメージ・バイナリ) の改ざん防止と出所証明が必要 → cosign (キーレス署名なら OIDC 対応の CI が前提)
  - lockfile ベースで依存の既知脆弱性を継続検知したい → OSV-Scanner
  - リポジトリのブランチ保護・ピン留め・権限設定等を定量把握したい → Scorecard
  - 成果物の構成を SPDX / CycloneDX で提出・保管する要件がある → syft
- 不採用条件:
  - cosign: 署名を検証する消費者がいない、または OIDC / 鍵管理を運用できない場合
  - OSV-Scanner: Trivy / Grype 等で既に同等の依存脆弱性スキャンを運用している場合 (本リポジトリは `govulncheck` と Trivy を利用)
  - Scorecard: リポジトリが GitHub / GitLab 以外、または API 接続が許されない環境
  - syft: SBOM の提出・保管要件がなく、Trivy の SBOM 生成で足りる場合
- 併用条件: syft で SBOM を生成し cosign で署名・attestation を付与 → OSV-Scanner / Grype で脆弱性を照合する。Scorecard はこれらとは独立してリポジトリ姿勢を継続評価する。OSV-Scanner と Trivy / Grype は脆弱性照合で重複するため、片方で足りる場合は併用しない
- 更新条件: cosign の次期メジャーリリース (README は sigstore-go ベースへの移行を予告)、OSV-Scanner / Scorecard の出力仕様変更、SBOM 提出要件の発生時に再評価する
- 本リポジトリの `mise.toml` は `slsa` / `cosign` / `minisign` による取得時の provenance・署名検証と `minimum_release_age = "7d"` を有効化している。これは取得側の検証であり、成果物を署名する cosign の利用そのものではない。Trivy との役割分担は [Security Scanning: Trivy vs Snyk vs Grype](#security-scanning-trivy-vs-snyk-vs-grype) を参照
- 各ツールの aqua registry エントリが cosign / SLSA 検証を定義しているかは未確認

## SAST / Code Pattern Analysis: Semgrep vs CodeQL vs SonarQube

| 比較項目             | Semgrep                                               | CodeQL                                            | SonarQube                                                               |
| -------------------- | ----------------------------------------------------- | ------------------------------------------------- | ----------------------------------------------------------------------- |
| 提供元               | Semgrep, Inc.                                         | GitHub (Microsoft)                                | SonarSource                                                             |
| リポジトリ           | [semgrep/semgrep](https://github.com/semgrep/semgrep) | [github/codeql](https://github.com/github/codeql) | [SonarSource/sonarqube](https://github.com/SonarSource/sonarqube)       |
| ドキュメント         | [semgrep.dev/docs](https://semgrep.dev/docs)          | [codeql.github.com](https://codeql.github.com)    | [docs.sonarsource.com](https://docs.sonarsource.com/sonarqube)          |
| ライセンス           | LGPL-2.1 (OSS Engine) / 商用 (Platform)               | MIT (クエリ) / 商用 (GitHub Advanced Security)    | LGPL-3.0 (CE) / 商用 (DE/EE)                                            |
| 対応言語数           | 35+                                                   | 12 (公式 supported languages 表の項目数)          | 35+                                                                     |
| ルール記述           | YAML (パターンベース)                                 | QL (データフロー言語)                             | Java (プラグイン)                                                       |
| カスタムルール容易性 | ✅ 高い (YAML、数分で記述可能)                        | ⚠️ 中程度 (QL 学習コストあり)                     | ⚠️ 低い (Java 実装が必要)                                               |
| クロスファイル解析   | ✅ (Pro Engine)                                       | ✅                                                | ✅                                                                      |
| テイント解析         | ✅ (クロスファンクション)                             | ✅ (深いデータフロー)                             | ✅                                                                      |
| 解析深度             | パターンマッチ + テイント                             | セマンティック (最も深い)                         | データフロー + 品質メトリクス                                           |
| スキャン速度         | ✅ 高速 (~10 秒)                                      | ⚠️ 低速 (数分〜30 分+)                            | ⚠️ 中程度                                                               |
| CI/CD 統合           | ✅ (GitHub/GitLab/任意 CI)                            | ✅ (GitHub Actions ネイティブ)                    | ✅ (任意 CI)                                                            |
| IDE 統合             | ✅ (VS Code, JetBrains)                               | ⚠️ (VS Code のみ)                                 | ✅ (SonarLint: VS Code, JetBrains 等)                                   |
| 品質ゲート           | ❌                                                    | ❌                                                | ✅ (カバレッジ、重複、信頼性)                                           |
| 自動修正 (Autofix)   | ✅ (AI-powered)                                       | ✅ (Copilot Autofix)                              | ⚠️ 限定的                                                               |
| AI トリアージ        | ✅ (Semgrep Assistant)                                | ⚠️ (Copilot 連携)                                 | ⚠️ (AI CodeFix)                                                         |
| 誤検知率             | 低い                                                  | 低い                                              | 中程度                                                                  |
| 料金 (無料枠)        | Free: 10 リポジトリ/10 人まで (60 AI credits 含む)    | 無料 (公開リポジトリ)                             | Community Build: 無料                                                   |
| 料金 (有料)          | Teams: \$30/contributor/月 (20 AI credits/dev)        | Code Security: \$30/committer/月 (GHAS)           | Developer: LOC 従量の年額ライセンス (公式は金額非公開、要見積)          |
| 料金ページ           | [semgrep.dev/pricing](https://semgrep.dev/pricing)    | [github.com/pricing](https://github.com/pricing)  | [sonarsource.com/plans](https://www.sonarsource.com/plans-and-pricing/) |
| オフライン実行       | ✅ (CLI)                                              | ✅ (CLI)                                          | ✅ (セルフホスト)                                                       |
| SaaS / セルフホスト  | 両方                                                  | SaaS (GitHub) / CLI                               | セルフホスト / SonarCloud (SaaS)                                        |

### Guidelines

**→ Semgrep を採用する。** カスタムルールの記述容易性 (YAML)、スキャン速度、CI 統合の柔軟性のバランスが最も良い。OSS Engine (CLI) は無料で利用可能。Semgrep Multimodal (AI + ルール解析の併用) が新たに追加され、従来のパターンマッチだけでは検出困難な問題もカバー可能。

- GitHub をメインで使い GHAS を契約済みの場合は CodeQL が追加コストなしで利用可能。解析深度は最も高いがスキャン時間が長い
- コード品質ゲート (カバレッジ閾値、重複検出等) も統合したい場合は SonarQube を検討。SAST 単体としては Semgrep/CodeQL に劣る
- Semgrep + CodeQL の併用も有効。Semgrep で高速フィードバック (PR 時)、CodeQL で深い解析 (定期スキャン) と使い分ける
- Semgrep OSS からフォークした Opengrep (LGPL-2.1、Aikido / Endor Labs / Orca Security 等の AppSec 企業コンソーシアムが支援) は Semgrep ルール互換。Semgrep Inc. とは無関係で、ライセンス方針の差を重視する場合に検討する

## Secret Detection: gitleaks vs detect-secrets vs truffleHog vs Betterleaks

| 比較項目         | gitleaks                                                  | detect-secrets                                                | truffleHog                                                                  | Betterleaks                                                           |
| ---------------- | --------------------------------------------------------- | ------------------------------------------------------------- | --------------------------------------------------------------------------- | --------------------------------------------------------------------- |
| 提供元           | Zach Rice                                                 | Yelp                                                          | Truffle Security                                                            | Betterleaks (旧 Gitleaks 開発者、Aikido が支援)                       |
| リポジトリ       | [gitleaks/gitleaks](https://github.com/gitleaks/gitleaks) | [Yelp/detect-secrets](https://github.com/Yelp/detect-secrets) | [trufflesecurity/trufflehog](https://github.com/trufflesecurity/trufflehog) | [betterleaks/betterleaks](https://github.com/betterleaks/betterleaks) |
| ライセンス       | MIT                                                       | Apache 2.0                                                    | AGPL-3.0                                                                    | MIT                                                                   |
| 実装言語         | Go                                                        | Python                                                        | Go                                                                          | Go                                                                    |
| Git 履歴スキャン | ✅                                                        | ❌ (ステージングのみ)                                         | ✅                                                                          | ✅                                                                    |
| ベースライン管理 | ✅ `.gitleaks.toml`                                       | ✅ `.secrets.baseline`                                        | ❌                                                                          | -                                                                     |
| カスタムルール   | ✅ TOML で正規表現定義                                    | ✅ プラグインシステム                                         | ⚠️ 限定的                                                                   | ✅ TOML (Expr で式記述)                                               |
| 実行速度         | 高速                                                      | 中程度                                                        | 高速                                                                        | 高速 (公式: fast)                                                     |
| 誤検知率         | 低い                                                      | 中程度                                                        | 低い                                                                        | -                                                                     |

### Guidelines

**→ gitleaks + detect-secrets を併用する。** gitleaks で Git 履歴を含む包括スキャン、detect-secrets で pre-commit 時のステージング検出を行い、多層防御を実現する。

- 検出したシークレットが実際に有効かどうかの検証 (verified secrets) が必要な場合は truffleHog を検討
- gitleaks は README で「feature complete」とされ、新機能は取り込まず今後はセキュリティパッチのみ。開発者の関心は後継の Betterleaks (同開発チーム、MIT、Git 履歴スキャン・任意の検証に対応) に移っている。Betterleaks は v2 開発中で安定版は未リリース (README 時点) のため、新規採用は v2 の安定化を待って再評価する
- verified secrets の検証機能を持つ OSS として MongoDB 製の Kingfisher (Apache-2.0) もあるが、採用実績が限定的なため本比較には含めない

## GitHub Actions Lint: actionlint vs ghalint vs zizmor

| 比較項目             | actionlint                                              | ghalint                                                               | zizmor                                                    |
| -------------------- | ------------------------------------------------------- | --------------------------------------------------------------------- | --------------------------------------------------------- |
| 提供元               | rhysd                                                   | suzuki-shunsuke                                                       | zizmorcore                                                |
| リポジトリ           | [rhysd/actionlint](https://github.com/rhysd/actionlint) | [suzuki-shunsuke/ghalint](https://github.com/suzuki-shunsuke/ghalint) | [zizmorcore/zizmor](https://github.com/zizmorcore/zizmor) |
| ライセンス           | MIT                                                     | MIT                                                                   | MIT                                                       |
| 主な検出対象         | 構文エラー、型チェック、式の検証                        | セキュリティベストプラクティス                                        | セキュリティ設定の不備                                    |
| シェルスクリプト検証 | ✅ (shellcheck 連携)                                    | ❌                                                                    | ❌                                                        |
| 式の型チェック       | ✅                                                      | ❌                                                                    | ❌                                                        |
| persist-credentials  | ❌                                                      | ✅                                                                    | ✅                                                        |
| timeout-minutes      | ❌                                                      | ✅                                                                    | ❌                                                        |
| permissions 検証     | ⚠️ 限定的                                               | ✅                                                                    | ✅                                                        |
| Action ピン留め      | ❌                                                      | ✅                                                                    | ✅                                                        |

### Guidelines

**→ 3 つ全て併用する。** 検出対象が異なるため、組み合わせることでカバレッジが最大化される。actionlint (構文・型) + ghalint (セキュリティプラクティス) + zizmor (セキュリティ設定)。

## GitHub Actions Pinning: pinact vs pin-github-action vs Renovate

| 比較項目   | pinact                                                              | pin-github-action                                                     | Renovate (pinDigests)                                           |
| ---------- | ------------------------------------------------------------------- | --------------------------------------------------------------------- | --------------------------------------------------------------- |
| 提供元     | suzuki-shunsuke                                                     | mheap                                                                 | Mend                                                            |
| リポジトリ | [suzuki-shunsuke/pinact](https://github.com/suzuki-shunsuke/pinact) | [mheap/pin-github-action](https://github.com/mheap/pin-github-action) | [renovatebot/renovate](https://github.com/renovatebot/renovate) |
| ライセンス | MIT                                                                 | MIT                                                                   | AGPL-3.0                                                        |
| 用途       | Action をフル SHA にピン留め                                        | Action をフル SHA にピン留め                                          | ピン留め + 自動更新                                             |
| 一括変換   | ✅                                                                  | ✅                                                                    | ❌ (PR ベース)                                                  |
| 自動更新   | ❌ (Renovate と併用)                                                | ❌                                                                    | ✅                                                              |

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
| セルフホスト | 不要 (CI 内実行)                                              | 不要                           | 必要 (or Cloud 版)                                                |
| 料金         | 無料                                                          | 無料 (Public) / 有料 (Private) | 有料 (Community 版は無料)                                         |

### Guidelines

**→ reviewdog を採用する。** 任意のリンターと組み合わせて PR インラインコメントを生成でき、無料・軽量・導入が容易。

- コード品質メトリクス (技術的負債、重複率等) を組織全体で追跡したい場合は SonarQube を検討
- SARIF 形式で Security タブに一元集約したい場合は GitHub Code Scanning を検討

## Code Coverage: Codecov vs Coveralls vs SonarQube

| 比較項目                  | Codecov                                                                                                                   | Coveralls                                                                                                                                                   | SonarQube                                                         |
| ------------------------- | ------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------- |
| 提供元                    | Sentry (Codecov)                                                                                                          | Coveralls                                                                                                                                                   | SonarSource                                                       |
| リポジトリ                | [codecov/codecov-action](https://github.com/codecov/codecov-action)                                                       | [coverallsapp/github-action](https://github.com/coverallsapp/github-action)                                                                                 | [SonarSource/sonarqube](https://github.com/SonarSource/sonarqube) |
| ライセンス                | 商用 (SaaS)                                                                                                               | 商用 (SaaS)                                                                                                                                                 | LGPL-3.0 (Community) / 商用                                       |
| PR コメント               | ✅ (差分カバレッジ)                                                                                                       | ✅                                                                                                                                                          | ✅                                                                |
| カバレッジゲート          | ✅                                                                                                                        | ✅                                                                                                                                                          | ✅                                                                |
| フラグ/コンポーネント分割 | ✅                                                                                                                        | ⚠️ 限定的                                                                                                                                                   | ✅                                                                |
| OIDC 認証                 | ✅                                                                                                                        | ❌                                                                                                                                                          | ❌                                                                |
| 料金                      | Developer: 無料 (Public 無制限、Private は 1 ユーザー・月 250 アップロード) / Team \$5/ユーザー/月 / Pro \$12/ユーザー/月 | 無料 (Public は常に無料) / Starter \$10 (Private 1 リポジトリ) / Org \$50 (10) / Org+ \$100 (20) / Pro \$200 (40) / Unlimited \$400 (月額、年払い 10% 割引) | 有料 (Community 版は無料)                                         |

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
| マルチ言語対応 | ✅ (Go, Python, Node.js, Shell 等)                                |
| キャッシュ     | ✅ (フック環境を自動キャッシュ)                                   |
| CI 統合        | ✅ (`pre-commit run --all-files`)                                 |

### Guidelines

**→ pre-commit を採用する。** Git hooks のデファクトスタンダード。言語を問わず任意のリンター・フォーマッターを pre-commit/pre-push フックとして統一管理できる。代替ツール (husky + lint-staged 等) は Node.js 特化のため、多言語プロジェクトでは pre-commit が最適。

- 高速な代替として prek (MIT、Rust 製単一バイナリ) がある。既存の pre-commit 設定とフックに完全互換で、独自の `prek.toml` も使える。CPython / Apache Airflow / FastAPI 等が採用

## CI/CD: GitHub Actions vs GitLab CI vs CircleCI vs Jenkins

| 比較項目             | GitHub Actions                                         | GitLab CI                                                 | CircleCI                                                   | Jenkins                                                   |
| -------------------- | ------------------------------------------------------ | --------------------------------------------------------- | ---------------------------------------------------------- | --------------------------------------------------------- |
| 提供元               | GitHub                                                 | GitLab                                                    | CircleCI                                                   | OSS (CloudBees)                                           |
| リポジトリ           | - (GitHub 組み込み)                                    | [gitlabhq/gitlabhq](https://github.com/gitlabhq/gitlabhq) | - (SaaS)                                                   | [jenkinsci/jenkins](https://github.com/jenkinsci/jenkins) |
| ライセンス           | 商用 (GitHub に含む)                                   | MIT (CE) / 商用 (EE)                                      | 商用                                                       | MIT                                                       |
| ホスティング         | SaaS                                                   | SaaS / セルフホスト                                       | SaaS / セルフホスト                                        | セルフホスト                                              |
| 設定ファイル         | `.github/workflows/*.yml`                              | `.gitlab-ci.yml`                                          | `.circleci/config.yml`                                     | `Jenkinsfile`                                             |
| Reusable Workflow    | ✅ (reusable workflows, composite actions)             | ✅ (include, extends)                                     | ✅ (orbs)                                                  | ✅ (shared libraries)                                     |
| セルフホストランナー | ✅                                                     | ✅                                                        | ✅ (runner)                                                | ✅ (agent)                                                |
| コンテナ実行         | ✅                                                     | ✅ (デフォルト)                                           | ✅ (デフォルト)                                            | ✅ (プラグイン)                                           |
| キャッシュ           | ✅ (actions/cache)                                     | ✅ 組み込み                                               | ✅ 組み込み                                                | ⚠️ プラグイン依存                                         |
| シークレット管理     | ✅ (Encrypted secrets, OIDC)                           | ✅ (Variables, Vault 連携)                                | ✅ (Contexts)                                              | ⚠️ プラグイン依存                                         |
| 料金 (Public)        | 無料                                                   | 無料 (400 分/月)                                          | 無料 (OSS は 400,000 credits/月 ≈ 80,000 分)               | 無料 (セルフホスト)                                       |
| 料金 (Private)       | \$12 分の利用枠 (Linux 標準ランナーで約 2,000 分/月)〜 | 400 分/月〜                                               | 30,000 credits/月 (最大 6,000 分)〜、Performance \$15/月〜 | 無料 (セルフホスト)                                       |

### Guidelines

**→ GitHub Actions を採用する。** GitHub をソースコード管理に使っている場合、最も統合がシームレスで学習コストが低い。Reusable Workflows による共通化、OIDC によるセキュアな認証、Marketplace の豊富な Actions が利用可能。

- GitLab をソースコード管理に使っている場合は GitLab CI 一択
- 高度な並列実行・リソースクラスの細かい制御が必要な場合は CircleCI を検討
- 完全なカスタマイズ性・オンプレミス要件がある場合は Jenkins を検討 (運用コスト高)

## Code Formatter: Prettier vs Biome vs deno fmt vs clang-format vs rustfmt

コードフォーマッターの比較。言語固有フォーマッター (gofumpt, shfmt 等) は各言語別ドキュメントを参照。ここでは多言語対応フォーマッターおよび代表的な言語固有フォーマッターのアーキテクチャを比較する。

| 比較項目              | Prettier                                                  | Biome                                                                                                        | deno fmt                                                          | clang-format                                                   | rustfmt                                                     |
| --------------------- | --------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------ | ----------------------------------------------------------------- | -------------------------------------------------------------- | ----------------------------------------------------------- |
| 提供元                | Prettier                                                  | Biome                                                                                                        | Deno Land                                                         | LLVM Project                                                   | Rust Project                                                |
| リポジトリ            | [prettier/prettier](https://github.com/prettier/prettier) | [biomejs/biome](https://github.com/biomejs/biome)                                                            | [denoland/deno](https://github.com/denoland/deno)                 | [llvm/llvm-project](https://github.com/llvm/llvm-project)      | [rust-lang/rustfmt](https://github.com/rust-lang/rustfmt)   |
| ドキュメント          | [prettier.io](https://prettier.io/docs/en/)               | [biomejs.dev](https://biomejs.dev)                                                                           | [docs.deno.com](https://docs.deno.com/runtime/reference/cli/fmt/) | [clang.llvm.org](https://clang.llvm.org/docs/ClangFormat.html) | [rust-lang.github.io](https://rust-lang.github.io/rustfmt/) |
| ライセンス            | MIT                                                       | MIT                                                                                                          | MIT                                                               | Apache-2.0 with LLVM Exception                                 | Apache-2.0 / MIT                                            |
| 実装言語              | JavaScript                                                | Rust                                                                                                         | Rust                                                              | C++                                                            | Rust                                                        |
| 対応言語              | JS/TS/JSX/TSX/CSS/HTML/JSON/YAML/Markdown/GraphQL 等      | JS/TS/JSX/TSX/CSS/SCSS/JSON/GraphQL/Markdown/YAML。HTML/SVG は Lint ✅・Format 🟡。Vue/Svelte/Astro は実験的 | JS/TS/JSX/TSX/JSON/Markdown/YAML/CSS/HTML                         | C/C++/Objective-C/Java/C#/Proto                                | Rust                                                        |
| 設定ファイル          | `.prettierrc` (JSON/YAML/TOML/JS)                         | `biome.json` / `biome.jsonc`                                                                                 | `deno.json` (`fmt` セクション)                                    | `.clang-format` (YAML)                                         | `rustfmt.toml` / `.rustfmt.toml`                            |
| 設定オプション数      | 少ない (Opinionated)                                      | 少ない (Opinionated)                                                                                         | 極少 (Opinionated)                                                | 多い (100+)                                                    | 多い (60+、nightly のみのオプション含む)                    |
| Linter 統合           | ❌ (別途 ESLint)                                          | ✅ 組み込み (ESLint 互換ルール)                                                                              | ✅ 組み込み (`deno lint`)                                         | ❌ (別途 clang-tidy)                                           | ❌ (別途 clippy)                                            |
| 実行速度              | 低速 (Node.js)                                            | ✅ 高速 (Rust、Prettier 比 25-35x)                                                                           | ✅ 高速 (Rust)                                                    | ✅ 高速 (C++)                                                  | ✅ 高速 (Rust)                                              |
| プラグインシステム    | ✅ (言語追加プラグイン)                                   | ❌ (組み込みのみ)                                                                                            | ❌ (組み込みのみ)                                                 | ❌                                                             | ❌                                                          |
| エディタ統合          | ✅ (VS Code/JetBrains/Vim 等、広範)                       | ✅ (VS Code/JetBrains/Vim 等)                                                                                | ✅ (VS Code/JetBrains)                                            | ✅ (VS Code/JetBrains/Vim 等)                                  | ✅ (VS Code/JetBrains/Vim 等)                               |
| Ignore ファイル       | `.prettierignore`                                         | 設定内 `ignore` / CLI `--ignore`                                                                             | 設定内 `exclude`                                                  | ❌ (CLI で指定)                                                | `rustfmt.toml` 内 `ignore`                                  |
| CI 統合 (check mode)  | ✅ (`--check`)                                            | ✅ (`check --formatter-enabled=true`)                                                                        | ✅ (`fmt --check`)                                                | ✅ (`--dry-run --Werror`)                                      | ✅ (`--check`)                                              |
| pre-commit 対応       | ✅ (mirrors-prettier)                                     | ✅ (biomejs/pre-commit)                                                                                      | ⚠️ (カスタム定義)                                                 | ✅ (pre-commit/mirrors-clang-format)                           | ✅ (doublify/pre-commit-rust)                               |
| Node.js 依存          | ✅ 必須                                                   | ❌ 不要 (単一バイナリ)                                                                                       | ❌ 不要 (Deno ランタイム)                                         | ❌ 不要                                                        | ❌ 不要 (rustup 経由)                                       |
| Prettier 互換性       | -                                                         | ✅ 97%互換 (移行容易)                                                                                        | ⚠️ 類似だが非互換                                                 | ❌                                                             | ❌                                                          |
| Markdown フォーマット | ✅                                                        | ✅ (v2.6、Prettier 互換 約 92%)                                                                              | ✅                                                                | ❌                                                             | ❌                                                          |
| YAML フォーマット     | ✅                                                        | ✅ (v2.6、Prettier 互換 100%)                                                                                | ✅                                                                | ❌                                                             | ❌                                                          |
| 料金                  | 無料                                                      | 無料                                                                                                         | 無料                                                              | 無料                                                           | 無料                                                        |

### Guidelines

**→ 言語スタックに応じて使い分ける。** 単一の万能フォーマッターは存在しないため、プロジェクトの言語構成に合わせて選択する。

- **Web フロントエンド (JS/TS/CSS)**: Biome を第一候補とする。Prettier 比 25-35x の高速性、Linter 統合による単一ツール化、Node.js 不要で CI が軽量化。Prettier 97% 互換のため移行コストが低い。HTML/SVG は Lint が本番対応、Formatter は実験的 (opt-in 要。Vue/Svelte/Astro も実験的)。Markdown/YAML の Format は v2.6 (2026-10) で対応 (Markdown は Prettier 互換 約 92%、YAML は 100%)
- **Prettier を選ぶ場合**: プラグインによる追加言語対応が必要な場合 (PHP, Ruby, Svelte 等)、または安定した HTML フォーマットが重要な場合。エコシステムの成熟度・プラグイン数では依然最大
- **Deno プロジェクト**: deno fmt 一択。設定不要で Deno ランタイムに統合されており、追加の依存が不要
- **C/C++ プロジェクト**: clang-format 一択。LLVM エコシステムのデファクトスタンダード。設定項目が多いためチームで `.clang-format` を共有し BasedOnStyle を固定する
- **Rust プロジェクト**: rustfmt 一択。`cargo fmt` として標準ツールチェーンに含まれ、追加インストール不要
- **Go プロジェクト**: gofumpt を使用 (Go 別ドキュメント参照)。本比較の対象外
- **多言語リポジトリ**: Biome (JS/TS/CSS/JSON) + 言語固有ツール (gofumpt, rustfmt, shfmt 等) の組み合わせ。pre-commit で統一的に実行する

## Markdown Link Check: lychee vs markdown-link-check

Markdown 内のリンク切れ検出ツールの比較。両者は同一課題の代替関係にあり、通常はどちらか一方を選ぶ。

| 比較項目                    | lychee                                                                                          | markdown-link-check                                                                                   |
| --------------------------- | ----------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------- |
| 提供元                      | lycheeverse                                                                                     | tcort                                                                                                 |
| リポジトリ                  | [lycheeverse/lychee](https://github.com/lycheeverse/lychee)                                     | [tcort/markdown-link-check](https://github.com/tcort/markdown-link-check)                             |
| ドキュメント                | [lychee.cli.rs](https://lychee.cli.rs)                                                          | [README (GitHub)](https://github.com/tcort/markdown-link-check#readme)                                |
| ライセンス                  | Apache-2.0 / MIT (選択可)                                                                       | ISC                                                                                                   |
| 実装言語                    | Rust                                                                                            | JavaScript (Node.js、npm 配布)                                                                        |
| 提供形態                    | 単一バイナリ / Docker                                                                           | npm パッケージ / Docker (`ghcr.io/tcort/markdown-link-check`)                                         |
| 主用途                      | Markdown / HTML / CSS / XML 等からのリンク検査                                                  | Markdown ファイルのリンク検査                                                                         |
| 実行例                      | `lychee './**/*.md'`                                                                            | `markdown-link-check ./README.md`                                                                     |
| インストール                | `cargo install` / `cargo binstall` / Homebrew / Docker / バイナリ / Nix / scoop / WinGet ほか   | `npm install` (dev / global) / Docker / pre-commit                                                    |
| aqua / mise 提供            | ✅ aqua registry 掲載 (`aqua:lycheeverse/lychee`、registry 側に cosign / SLSA 定義は確認できず) | ❌ aqua 対象外 (本リポジトリは `npm:markdown-link-check` 3.15.0 を mise で導入)                       |
| Node.js 依存                | ❌ 不要                                                                                         | ✅ 必須                                                                                               |
| GitHub Action               | [lycheeverse/lychee-action](https://github.com/lycheeverse/lychee-action)                       | [tcort/github-action-markdown-link-check](https://github.com/tcort/github-action-markdown-link-check) |
| キャッシュ                  | ✅ `--cache` (`.lycheecache`、有効期間設定可)                                                   | 未確認 (README に記載なし)                                                                            |
| オフライン (ローカルのみ)   | ✅ `--offline`                                                                                  | 未確認 (README に明記なし)                                                                            |
| アンカー / フラグメント検査 | ✅ `--include-fragments` (`anchor-only` / `text-only` / `full`)                                 | 未確認 (README に記載なし)                                                                            |
| 除外設定                    | ✅ `--exclude` / `--exclude-path` / `.lycheeignore`                                             | ✅ `ignorePatterns` / 無効化コメント                                                                  |
| URL 置換                    | ⚠️ 未確認                                                                                       | ✅ `replacementPatterns` (`{{BASEURL}}` 対応)                                                         |
| リトライ / レート制限       | ✅ バックオフ付きリトライ / ホスト単位のスロットリング                                          | ✅ `retryOn429` (`retry-after` 尊重) / `retryCount` / `fallbackRetryDelay`                            |
| 出力形式                    | compact / detailed / json / junit / markdown                                                    | default (コンソール) / JUnit XML                                                                      |
| 設定ファイル                | ✅ 設定ファイルあり (形式は 未確認)                                                             | ✅ JSON (`--config`)                                                                                  |
| 並列実行                    | ✅ 非同期・並列                                                                                 | 未確認                                                                                                |
| 料金                        | 無料                                                                                            | 無料                                                                                                  |

### Guidelines

**→ 現状は markdown-link-check を継続し、速度・キャッシュ・アンカー検査が必要になった時点で lychee を再評価する (条件付き推奨)。** 両者は代替関係であり、併用はしない。

- 選定方針: Node.js 環境が既にあり設定が小さく済むか (markdown-link-check)、速度・キャッシュ・フラグメント検査・Node.js 非依存を優先するか (lychee) で決める
- 採用条件:
  - markdown-link-check: Node.js / npm が前提の環境で、`replacementPatterns` による URL 置換や JUnit 出力が要件に合う場合。本リポジトリは mise の `npm:markdown-link-check` 3.15.0 を Stop hook で実行している
  - lychee: 大規模ドキュメントで速度とキャッシュ (`.lycheecache`) が必要、アンカー検査が要件、または Node.js を入れたくない CI の場合
- 不採用条件:
  - markdown-link-check: キャッシュ・アンカー検査が必須要件で、公式ドキュメント上の対応が確認できない場合
  - lychee: 既存の markdown-link-check 設定 (`replacementPatterns` 等) の移行コストが利益を上回る場合。URL 置換機能は公式ドキュメントで 未確認
- 併用条件: なし (同一責務のため)。移行検証中のみ一時的に並走して検出結果を比較する
- 更新条件: lychee-action / markdown-link-check の保守状況の変化、mise.toml のツール構成変更、リンク検査の実行時間や外部サイトの 429 によるフレーキーさが問題化した場合
