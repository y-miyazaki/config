# Tool Comparison Matrix (AI Governance)

AI Security / Runtime Guardrails / Agent Skills 品質管理 / 監査 / Agent 設定配布ツール選定の判断材料。

本ドキュメントのスコープは AI Governance レイヤ (Security / Runtime / Quality / Audit / Distribution) に限定する。

評価軸の共通ルールは [tool-comparison-evaluation-rules.md](tool-comparison-evaluation-rules.md) を参照する。

## History

| 日付       | 内容                                                                                                                                                                                                                                                                        |
| ---------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 2026-11-18 | 全般最新化: apm の提供元/リポジトリ/ライセンスを確定 (microsoft/apm, Apache-2.0)、NeMo Guardrails リポジトリ移管反映、Llama Guard ライセンス/最新世代注記、LlamaFirewall / Langfuse / Opik を追加、Trivy サプライチェーン侵害 (2026-03) 注記、Snyk / Observability 料金追記 |
| 2026-06-17 | 全般最新化: Waza/apm audit 現状反映、Langfuse pricing 更新                                                                                                                                                                                                                  |
| 2026-05-24 | 比較表の行順ルールを基本形 (提供元 → リポジトリ → ライセンス) に修正                                                                                                                                                                                                        |
| 2026-05-23 | 初版作成。                                                                                                                                                                                                                                                                  |

## AI Security Scanning: Snyk vs Trivy

| 比較項目            | Snyk                                                                  | Trivy                                                            |
| ------------------- | --------------------------------------------------------------------- | ---------------------------------------------------------------- |
| 提供元              | Snyk                                                                  | Aqua Security                                                    |
| リポジトリ          | [snyk/cli](https://github.com/snyk/cli)                               | [aquasecurity/trivy](https://github.com/aquasecurity/trivy)      |
| ライセンス          | Apache-2.0 (CLI) / 商用 (Platform)                                    | Apache-2.0                                                       |
| 提供形態            | CLI + SaaS プラットフォーム                                           | OSS (CLI)                                                        |
| 主なスキャン対象    | OSS 依存関係 / コード / コンテナ / IaC                                | Filesystem / Container / Repo / SBOM                             |
| 主な検出タイプ      | 脆弱性 (SCA) / コード分析 / IaC misconfig                             | 脆弱性 / misconfig / secrets / license                           |
| AI 文脈での検出観点 | AI 生成コードの脆弱性検知 / LLM アプリ設定不備の検出                  | AI 関連 IaC 設定不備 / コンテナ・SBOM 起点のサプライチェーン検査 |
| 主な CLI 例         | `snyk test`, `snyk code test`, `snyk container test`, `snyk iac test` | `trivy fs`, `trivy image`, `trivy config`, `trivy sbom`          |
| マネージド統合      | ✅ (Snyk プラットフォーム)                                            | ⚠️ OSS 中心 (必要に応じて周辺サービスを組み合わせ)               |
| セルフホスト適性    | ⚠️ CLI はローカル実行可、運用統合は SaaS 寄り                         | ✅ OSS 単体で導入しやすい                                        |
| 導入の主な前提条件  | SaaS 利用可否 / 予算 / 開発者向け修正支援の必要性                     | OSS 運用体制 / 誤検知調整の運用余力                              |

### Pricing

| プラン     | Snyk                                                                      | Trivy                                  |
| ---------- | ------------------------------------------------------------------------- | -------------------------------------- |
| OSS/無料枠 | Free: \$0/月 (SCA / SAST / IaC / Container、最大 5 projects)              | OSS は無料                             |
| 有料       | Team: \$25/月〜 (最大 10 developers / 100 projects)、Enterprise: カスタム | Enterprise/周辺製品は別途 (価格非公開) |

> ※ 2026-11-18 時点 ([snyk.io/plans](https://snyk.io/plans/) 確認)。

### Guidelines

**→ 優劣ではなく要件適合で選択する。コスト最小化なら Trivy、修正ワークフロー統合を重視するなら Snyk、厳格運用なら併用。**

- OSS 中心・セルフホスト前提なら Trivy
- 開発者向け修正導線や組織横断ガバナンスを重視するなら Snyk
- 規制対応や多層防御が必要なら Trivy + Snyk の併用を検討
- Trivy は 2026-03-19 にサプライチェーン侵害 (CVE-2026-33634 / GHSA-69fq-xp46-6x23: 悪意ある v0.69.4 バイナリ/イメージ、trivy-action / setup-trivy タグの改ざん) を受けた。Trivy 本体・GitHub Action ともにバージョン/コミット SHA で固定し、公式アドバイザリで安全版を確認して利用する ([Aqua 公式ブログ](https://www.aquasec.com/blog/trivy-supply-chain-attack-what-you-need-to-know/))
- 最終判断は [tool-comparison-evaluation-rules.md](tool-comparison-evaluation-rules.md) の加重スコアで行う

## Runtime Guardrails: Guardrails AI vs Llama Guard vs NeMo Guardrails

| 比較項目                       | Guardrails AI                                                           | Llama Guard                                                                                      | LlamaFirewall                                                                       | NeMo Guardrails                                                     |
| ------------------------------ | ----------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------ | ----------------------------------------------------------------------------------- | ------------------------------------------------------------------- |
| 提供元                         | Guardrails AI                                                           | Meta                                                                                             | Meta                                                                                | NVIDIA                                                              |
| リポジトリ                     | [guardrails-ai/guardrails](https://github.com/guardrails-ai/guardrails) | [meta-llama/PurpleLlama](https://github.com/meta-llama/PurpleLlama)                              | [meta-llama/PurpleLlama (LlamaFirewall)](https://github.com/meta-llama/PurpleLlama) | [NVIDIA-NeMo/Guardrails](https://github.com/NVIDIA-NeMo/Guardrails) |
| ライセンス                     | Apache-2.0                                                              | Llama Community License (モデル世代ごとに版が異なる。Llama Guard 4 は Llama 4 Community License) | MIT                                                                                 | Apache-2.0                                                          |
| 提供形態                       | OSS ライブラリ/フレームワーク                                           | OSS セーフティモデル                                                                             | OSS ガードレールフレームワーク                                                      | OSS フレームワーク                                                  |
| 主用途                         | 入出力バリデーション / ルール適用                                       | 有害・不適切コンテンツ判定                                                                       | エージェント向け prompt injection / 目的逸脱 / 生成コード検査                       | 対話フロー制御 / 実行時ガードレール                                 |
| プロンプトインジェクション対策 | ⚠️ (ルール設計依存)                                                     | ⚠️ (分類モデル補助として利用)                                                                    | ✅ (PromptGuard 2)                                                                  | ✅ (フロー制御で抑制)                                               |
| PII / 機密情報フィルタ         | ✅ (バリデータ拡張)                                                     | ⚠️ (用途に応じた別実装が必要)                                                                    | -                                                                                   | ⚠️ (実装次第)                                                       |
| エージェント統合               | ✅ (アプリ層に組込み)                                                   | ⚠️ (推論パイプラインへの組込みが必要)                                                            | ✅ (AlignmentCheck / CodeShield をエージェントに組込み)                             | ✅ (ワークフロー組込み)                                             |
| 監査向けログ親和性             | 中                                                                      | 中                                                                                               | -                                                                                   | 中                                                                  |

> ※ 2026-11-18 時点。Llama Guard の最新世代は Llama Guard 4 (12B、Hugging Face で gated)。Guardrails AI は 2026-07 に hosted remote inferencing の終了 (README 記載の期限: 2026-08-25) を告知し、validator は個別の PyPI パッケージとして提供される。NeMo Guardrails のリポジトリは `NVIDIA/NeMo-Guardrails` から `NVIDIA-NeMo/Guardrails` へ移管された。

### Guidelines

**→ Runtime Guardrails は静的スキャンの代替ではなく補完レイヤとして導入する。**

- 対話フロー全体の制御が必要なら NeMo Guardrails
- 入出力バリデーションを柔軟に拡張したいなら Guardrails AI
- 軽量に安全性分類器を入れたいなら Llama Guard
- エージェントの prompt injection / 目的逸脱 / 生成コード検査を入れたいなら LlamaFirewall
- 本番では Security Scanning + Runtime Guardrails の二層で運用する

## Agent Skills Lint / Evaluation: apm audit vs markdownlint-cli2 vs Waza

| 比較項目         | apm audit                                                          | markdownlint-cli2                                                               | Waza                                                |
| ---------------- | ------------------------------------------------------------------ | ------------------------------------------------------------------------------- | --------------------------------------------------- |
| 提供元           | Microsoft                                                          | David Anson                                                                     | Microsoft                                           |
| リポジトリ       | [microsoft/apm](https://github.com/microsoft/apm)                  | [DavidAnson/markdownlint-cli2](https://github.com/DavidAnson/markdownlint-cli2) | [microsoft/waza](https://github.com/microsoft/waza) |
| ライセンス       | Apache-2.0                                                         | MIT                                                                             | MIT                                                 |
| 主用途           | APM パッケージの隠し Unicode / drift 検出と lockfile・ポリシー監査 | Markdown の静的 lint                                                            | Agent Skills の readiness/eval                      |
| 実行例           | `apm audit --ci`                                                   | `markdownlint-cli2 "docs/**"`                                                   | `waza check <skill>` / `waza run eval.yaml`         |
| 対象             | `apm.yml`, `apm.lock.yaml`, パッケージ依存                         | `README.md`, `docs/**/*.md`                                                     | `SKILL.md`, `eval.yaml`, `evals/tasks/*.yaml`       |
| 判定タイプ       | 依存整合性 / 監査ポリシー                                          | Markdown 文法/フォーマット                                                      | スキーマ妥当性 / 評価スコア / トークン分析          |
| 失敗時の主な示唆 | 依存問題・監査違反                                                 | 形式崩れ・リンク不整合                                                          | 仕様逸脱・評価不足・タスク不足                      |
| 導入効果         | 構成と依存の監査一貫性を担保                                       | 文書品質を安定化                                                                | Agent Skills の品質保証を直接評価                   |
| 代替可能性       | 低 (APM 運用時は事実上必須)                                        | 中 (他 lint へ置換可能)                                                         | 低 (Skill eval を代替しにくい)                      |

### Guidelines

**→ 目的が異なるため代替ではなく組み合わせ判断を行う。Agent Skills を運用するなら Waza は必要、ドキュメント品質には markdownlint、APM 利用時は apm audit が必要。**

- `waza check` で readiness のハードエラーを先に潰す
- `waza run eval.yaml` で振る舞い品質を評価
- docs 変更を含む場合は markdownlint を追加
- APM パッケージ配布を行う場合は `apm audit --ci` を必須化

## Agent Observability & Audit: Arize Phoenix vs LangSmith vs OpenLLMetry

| 比較項目                 | Arize Phoenix                                           | Langfuse                                                  | LangSmith                            | OpenLLMetry (Traceloop)                                           | Opik (Comet)                                      |
| ------------------------ | ------------------------------------------------------- | --------------------------------------------------------- | ------------------------------------ | ----------------------------------------------------------------- | ------------------------------------------------- |
| 提供元                   | Arize                                                   | Langfuse (ClickHouse)                                     | LangChain                            | Traceloop (ServiceNow 傘下)                                       | Comet                                             |
| リポジトリ               | [Arize-ai/phoenix](https://github.com/Arize-ai/phoenix) | [langfuse/langfuse](https://github.com/langfuse/langfuse) | - (商用 SaaS)                        | [traceloop/openllmetry](https://github.com/traceloop/openllmetry) | [comet-ml/opik](https://github.com/comet-ml/opik) |
| ライセンス               | Elastic License 2.0                                     | MIT (`ee/` ディレクトリを除く)                            | 商用                                 | Apache-2.0                                                        | Apache-2.0                                        |
| 提供形態                 | OSS + Cloud                                             | OSS (セルフホスト) + Cloud                                | SaaS 中心                            | OSS (OpenTelemetry ベース)                                        | OSS (セルフホスト) + Cloud                        |
| 主用途                   | LLM/Agent 観測・評価                                    | LLM/Agent トレース / 評価 / プロンプト管理                | Agent 実行トレース / 評価 / デバッグ | LLM 呼び出しとツール実行の標準トレース収集                        | LLM/Agent トレース / 評価 / ガードレール          |
| ツール呼び出し監査       | ✅                                                      | ✅ (tool / agent observation)                             | ✅                                   | ✅                                                                | ✅                                                |
| 評価ワークフロー連携     | ✅                                                      | ✅                                                        | ✅ (LangChain/LangGraph 親和性高)    | ⚠️ (別評価基盤との組み合わせ前提)                                 | ✅ (datasets / experiments / LLM-as-a-judge)      |
| OpenTelemetry 親和性     | ✅                                                      | ✅ (OTLP/HTTP 受信、gRPC 未対応)                          | ⚠️                                   | ✅ (中核)                                                         | ✅ (first-party OTel 対応)                        |
| エンタープライズ監査適性 | 中〜高                                                  | 中〜高                                                    | 中〜高                               | 中〜高                                                            | 中〜高                                            |

### Pricing

| プラン     | Arize Phoenix / AX                                           | Langfuse Cloud                                                    | LangSmith                                                                           | OpenLLMetry | Opik       |
| ---------- | ------------------------------------------------------------ | ----------------------------------------------------------------- | ----------------------------------------------------------------------------------- | ----------- | ---------- |
| OSS/無料枠 | Phoenix OSS 無料 / AX Free: \$0 (25k spans/月、15 日保持)    | Hobby: \$0 (50k units/月、30 日保持)、OSS セルフホスト無料        | Developer: \$0 (1 seat、5k base traces/月、14 日保持)                               | OSS は無料  | OSS は無料 |
| 有料       | AX Pro: \$50/月 (50k spans、30 日保持)、Enterprise: カスタム | Core: \$29/月 (100k units)、Pro: \$199/月、Enterprise: \$2,499/月 | Plus: \$39/seat/月 (10k base traces/月、180 日 extended 保持)、Enterprise: カスタム | -           | -          |

> ※ 2026-11-18 時点 ([arize.com/pricing](https://arize.com/pricing/) / [langfuse.com/pricing](https://langfuse.com/pricing) / [langchain.com/pricing](https://www.langchain.com/pricing) 確認)。Traceloop は 2026-03-02 に ServiceNow 参画を発表したが、OpenLLMetry は Apache-2.0 の OSS として継続している。

### Guidelines

**→ 事前評価 (Lint/Eval) に加えて、事後監査 (Observability/Audit) を本番運用に組み込む。**

- LangChain 系中心で一体運用したいなら LangSmith
- OSS 中心で可視化と評価を行いたいなら Arize Phoenix / Langfuse / Opik
- ベンダー中立な監査ログ標準化を重視するなら OpenLLMetry
- 高リスク運用では Runtime Guardrails と Observability を同時導入する

## Agent Capability Distribution: Agent-native Plugin vs APM vs Git Sync

| 比較項目       | Agent-native Plugin モデル                        | APM                                               | Git Sync モデル                                     |
| -------------- | ------------------------------------------------- | ------------------------------------------------- | --------------------------------------------------- |
| 提供元         | ベンダー各社                                      | Microsoft                                         | GitHub/Git                                          |
| リポジトリ     | - (vendor provided)                               | [microsoft/apm](https://github.com/microsoft/apm) | - (Git 管理)                                        |
| ライセンス     | ベンダー/プラットフォーム規約に依存               | Apache-2.0                                        | リポジトリ定義に依存                                |
| ツール種別     | ベンダー提供の拡張配布                            | Agent 設定配布マネージャー                        | Git ベース配布                                      |
| 主用途         | Agent 機能の即時導入                              | Agent 設定配布 (MCP/Instructions/Skills/Hooks)    | Skill/Rules の Git 共有                             |
| 代表例         | Claude の plugin 的拡張、拡張マーケット導入モデル | APM package                                       | gh skill / Claude Skills / Cursor rules の Git 管理 |
| 配布単位       | Plugin/拡張機能                                   | 設定パッケージ                                    | リポジトリ/ファイル                                 |
| 再現配布       | ⚠️ (提供元依存)                                   | ✅                                                | ⚠️ (Git 運用次第)                                   |
| バージョン固定 | ⚠️ (提供元更新に依存)                             | ✅ (`apm.lock.yaml`)                              | ⚠️ (Git 運用次第)                                   |
| 監査/統制      | ⚠️ (Marketplace/提供元ポリシー依存)               | ✅ (`apm audit`)                                  | ⚠️ (レビュー運用依存)                               |

### Guidelines

**→ APM は再現性と統制、Git Sync モデルは運用単純性、Agent-native Plugin は導入速度を優先するときに選ぶ。**

- Agent 設定資産を複数環境で再現配布する要件がある場合は APM を採用
- Git Sync モデルは gh skill / Claude Skills / Cursor rules のような Git 管理型配布を含む
- 単一ツールへ統一せず、責務境界 (設定配布/実行依存) で管理
- 本番運用では、Plugin モデルを使う場合でもレビュー済み設定を Git 管理で補完する

## 推奨構成パターン

| パターン                    | 構成                                                                 | 用途                                               |
| --------------------------- | -------------------------------------------------------------------- | -------------------------------------------------- |
| 最小構成                    | Trivy + Waza + markdownlint-cli2 + APM                               | セキュリティ/Skill 品質/設定配布をバランスよく担保 |
| Runtime 重視                | Trivy + (NeMo Guardrails or Guardrails AI) + Waza + APM              | 実行時の不正入力/不適切出力リスクを抑制            |
| 監査重視                    | Trivy + Waza + LangSmith(or Phoenix/OpenLLMetry) + APM               | 本番での推論・ツール実行履歴を継続監査             |
| 厳格運用 (CI+Runtime+Audit) | Trivy + Snyk + Guardrails + Waza + LangSmith(or Phoenix) + apm audit | 事前・実行時・事後監査を多層化して統制             |

### Guidelines

**→ 先に要件を定義し、次に必要ツールだけ採用する。不要ツールは導入しない。**

- 静的セキュリティが必要: Trivy (必要に応じて Snyk を追加)
- 実行時安全制御が必要: Runtime Guardrails を追加
- Agent 品質保証が必要: Waza を追加
- 本番監査が必要: Observability/Audit を追加
- Agent 設定を複数環境で再現配布する必要がある: APM を追加
