<!-- omit in toc -->
# Tool Comparison Matrix (AI Workflow)

AI ワークフロー / LLM 基盤ツール選定の判断材料。

対象ツールはカテゴリが異なるため、用途別に分類して比較する。

<!-- omit in toc -->
## History

| 日付       | 内容                                                                                           |
| ---------- | ---------------------------------------------------------------------------------------------- |
| 2026-06-17 | 全般最新化: LangSmith Fleet/Engine プラットフォーム化反映、Langfuse pricing更新 ($29〜$2,499)、n8n AI Workflow Builder追加、Mastra managed DB追加 |
| 2026-05-21 | 初版作成。ワークフロー自動化 / LLM Gateway / Agent Framework / Observability の4カテゴリで比較 |

<!-- omit in toc -->
## Table of Contents

- [Workflow Automation: Dify vs Make.com vs n8n vs Windmill vs Zapier](#workflow-automation-dify-vs-makecom-vs-n8n-vs-windmill-vs-zapier)
  - [Pricing](#pricing)
  - [Guidelines](#guidelines)
- [LLM Gateway: LiteLLM vs Portkey](#llm-gateway-litellm-vs-portkey)
  - [Guidelines](#guidelines-1)
- [AI Agent Framework: CrewAI vs LangChain / LangGraph vs Mastra vs Vercel AI SDK](#ai-agent-framework-crewai-vs-langchain--langgraph-vs-mastra-vs-vercel-ai-sdk)
  - [Pricing](#pricing-1)
  - [Guidelines](#guidelines-2)
- [LLM Observability: Arize Phoenix vs Langfuse vs LangSmith](#llm-observability-arize-phoenix-vs-langfuse-vs-langsmith)
  - [Pricing](#pricing-2)
  - [Guidelines](#guidelines-3)
- [組み合わせパターン](#組み合わせパターン)
  - [Guidelines](#guidelines-4)

## Workflow Automation: Dify vs Make.com vs n8n vs Windmill vs Zapier

| 比較項目             | Dify                                                  | Make.com               | n8n                                         | Windmill                                                            | Zapier                 |
| -------------------- | ----------------------------------------------------- | ---------------------- | ------------------------------------------- | ------------------------------------------------------------------- | ---------------------- |
| 提供元               | LangGenius                                            | Celonis (Make)         | n8n GmbH                                    | Windmill Labs                                                       | Zapier, Inc.           |
| リポジトリ           | [langgenius/dify](https://github.com/langgenius/dify) | - (商用 SaaS)          | [n8n-io/n8n](https://github.com/n8n-io/n8n) | [windmill-labs/windmill](https://github.com/windmill-labs/windmill) | - (商用 SaaS)          |
| ライセンス           | Source Available (Apache-2.0 ベース + 追加条項)       | 商用                   | Sustainable Use License (fair-code)         | AGPLv3                                                              | 商用                   |
| 実装言語             | Python + TypeScript                                   | - (SaaS)               | TypeScript                                  | Rust + TypeScript                                                   | - (SaaS)               |
| セルフホスト         | ✅ (Docker / K8s)                                      | ❌                      | ✅ (Docker / K8s)                            | ✅ (Docker / K8s)                                                    | ❌                      |
| クラウドホスト       | ✅ (Dify Cloud)                                        | ✅ (SaaS のみ)          | ✅ (n8n Cloud)                               | ✅ (Windmill Cloud)                                                  | ✅ (SaaS のみ)          |
| ビジュアルエディタ   | ✅                                                     | ✅                      | ✅                                           | ✅                                                                   | ✅                      |
| AI エージェント      | ✅ (Agent + ReAct / Function Calling)                  | ✅ (AI Agents)          | ✅ (AI Agent ノード)                         | ⚠️ (スクリプトで実装)                                                | ✅ (Agents / Chatbots)  |
| RAG / ナレッジベース | ✅ (組み込み RAG パイプライン)                         | ⚠️ (外部連携)           | ⚠️ (外部連携)                                | ⚠️ (外部連携)                                                        | ⚠️ (外部連携)           |
| インテグレーション数 | 少数 (AI 特化)                                        | 3,000+                 | 500+                                        | 少数 (スクリプト中心)                                               | 9,000+                 |
| コード実行           | ✅ (コードブロック)                                    | ⚠️ (限定的)             | ✅ (JavaScript / Python)                     | ✅ (TypeScript / Python / Go / SQL / Bash)                           | ⚠️ (Code by Zapier)     |
| MCP 対応             | ⚠️ (プラグイン)                                        | ❌                      | ⚠️ (コミュニティ)                            | ❌                                                                   | ✅ (Zapier MCP)         |
| 対象ユーザー         | AI アプリ開発者                                       | ビジネスユーザー       | 開発者 / テクニカルチーム                   | 開発者 / インフラチーム                                             | ビジネスユーザー       |
| 主な用途             | AI アプリ構築 (チャットボット / Agent)                | ビジネスプロセス自動化 | 汎用ワークフロー + AI パイプライン          | 内部ツール / データパイプライン / スクリプト実行                    | ビジネスプロセス自動化 |

### Pricing

| プラン         | Dify                        | Make.com           | n8n                                   | Windmill                          | Zapier               |
| -------------- | --------------------------- | ------------------ | ------------------------------------- | --------------------------------- | -------------------- |
| 無料枠         | ✅ (Sandbox: 200 メッセージ) | ✅ (1,000 ops/月)   | ✅ (セルフホスト Community)            | ✅ (Cloud: 1,000 実行/月)          | ✅ (100 tasks/月)     |
| Starter / Core | Professional: $59/月        | $9/月 (10,000 ops) | Cloud: €20/月 (2,500 実行)            | Team: $10/dev/月                  | Professional: $20/月 |
| Pro / Team     | Team: $159/月               | $16/月             | Cloud: €50/月 (10,000 実行)           | Pro: $170/月 (1 dev)              | Team: $69/月         |
| Enterprise     | カスタム                    | カスタム           | カスタム                              | カスタム                          | カスタム             |
| セルフホスト   | 無料 (機能制限なし)         | N/A                | 無料 (Community) / €333/月 (Business) | 無料 (AGPLv3) / 有料 (Enterprise) | N/A                  |

### Guidelines

**→ 用途と対象ユーザーで選択する。**

- 汎用ワークフロー自動化 + AI 統合 + セルフホスト → **n8n**
- ビジネスユーザー主体 / SaaS 連携が多い / 非エンジニア → **Zapier** (連携数最大) または **Make.com** (コスパ重視)
- AI アプリ (チャットボット / RAG / Agent) を素早く構築 → **Dify**
- スクリプト実行基盤 / 内部ツール / データパイプライン → **Windmill**
- データプライバシー / VPC 内運用が必須 → **n8n** / **Dify** / **Windmill** (セルフホスト)
- Zapier vs Make.com: Zapier は連携数 (9,000+) で圧倒、Make.com は同等機能を低コストで提供
- n8n と Dify は併用可能: n8n でオーケストレーション、Dify で AI アプリ部分を担当

## LLM Gateway: LiteLLM vs Portkey

| 比較項目           | LiteLLM                                               | Portkey                                                      |
| ------------------ | ----------------------------------------------------- | ------------------------------------------------------------ |
| 提供元             | BerriAI                                               | Portkey AI                                                   |
| リポジトリ         | [BerriAI/litellm](https://github.com/BerriAI/litellm) | [portkey-ai/gateway](https://github.com/portkey-ai/gateway)  |
| ライセンス         | MIT (OSS) / Enterprise (商用)                         | MIT (Gateway OSS) / Managed (商用)                           |
| 実装言語           | Python                                                | TypeScript (Gateway) / Platform (SaaS)                       |
| セルフホスト       | ✅ (Docker / K8s)                                      | ✅ (Gateway OSS のみ)                                         |
| マネージドサービス | ❌ (セルフホストのみ)                                  | ✅ (Portkey Cloud)                                            |
| 統一 API           | ✅ (OpenAI 互換)                                       | ✅ (OpenAI 互換)                                              |
| 対応プロバイダー   | 100+                                                  | 200+                                                         |
| ロードバランシング | ✅                                                     | ✅                                                            |
| フォールバック     | ✅                                                     | ✅ (条件付きルーティング)                                     |
| コストトラッキング | ✅                                                     | ✅                                                            |
| 予算管理           | ✅ (チーム / プロジェクト / ユーザー)                  | ✅ (Virtual Keys)                                             |
| ガードレール       | ✅ (Enterprise)                                        | ✅ (組み込み)                                                 |
| キャッシュ         | ✅                                                     | ✅ (Semantic Cache)                                           |
| Observability 統合 | ⚠️ (外部連携: Langfuse 等)                             | ✅ (組み込みトレーシング + ログ)                              |
| プロンプト管理     | ❌                                                     | ✅ (Prompt Templates)                                         |
| Pricing            | OSS: 無料 / Enterprise: カスタム                      | OSS Gateway: 無料 / Managed: $49/月〜 / Enterprise: カスタム |

### Guidelines

**→ セルフホスト + コスト重視なら LiteLLM、マネージド + 統合機能重視なら Portkey。**

- LiteLLM: セルフホスト前提、MIT ライセンスで自由度が高い、Python エコシステムとの親和性
- Portkey: マネージドで運用負荷が低い、Observability + ガードレール + プロンプト管理が組み込み
- 両者とも OpenAI 互換 API を提供するため、アプリケーション側の変更は最小
- AWS Bedrock を Gateway 的に使う場合は直接 Bedrock API でも可 (ただしマルチプロバイダーには非対応)
- 小規模 / 単一プロバイダーの場合は Gateway 不要 (直接 SDK を使用)

## AI Agent Framework: CrewAI vs LangChain / LangGraph vs Mastra vs Vercel AI SDK

| 比較項目           | CrewAI                                                  | LangChain / LangGraph                                                                                                        | Mastra                                                  | Vercel AI SDK                             |
| ------------------ | ------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------- | ----------------------------------------- |
| 提供元             | CrewAI, Inc.                                            | LangChain, Inc.                                                                                                              | Mastra (元 Gatsby / YC W25)                             | Vercel                                    |
| リポジトリ         | [crewAIInc/crewAI](https://github.com/crewAIInc/crewAI) | [langchain-ai/langchain](https://github.com/langchain-ai/langchain) / [langgraph](https://github.com/langchain-ai/langgraph) | [mastra-ai/mastra](https://github.com/mastra-ai/mastra) | [vercel/ai](https://github.com/vercel/ai) |
| ライセンス         | MIT (Framework) / 商用 (AMP)                            | MIT                                                                                                                          | Apache-2.0                                              | Apache-2.0                                |
| 言語               | Python                                                  | Python / JavaScript                                                                                                          | TypeScript                                              | TypeScript                                |
| Agent 定義         | ✅ (ロール + ゴール + バックストーリー)                  | ✅ (LangGraph: グラフベース状態管理)                                                                                          | ✅ (プロンプト + ツール + メモリ)                        | ✅ (generateText + tools)                  |
| マルチエージェント | ✅ (役割分担型が得意)                                    | ✅ (LangGraph: 明示的グラフ制御)                                                                                              | ✅                                                       | ⚠️ (自前実装)                              |
| ワークフロー       | ✅ (タスクベース)                                        | ✅ (LangGraph: ノード + エッジ)                                                                                               | ✅ (step / then / after)                                 | ⚠️ (自前実装)                              |
| RAG                | ⚠️ (外部連携)                                            | ✅ (豊富なインテグレーション)                                                                                                 | ✅ (組み込み)                                            | ❌                                         |
| Evals              | ⚠️ (AMP で提供)                                          | ✅ (LangSmith 連携)                                                                                                           | ✅ (組み込み)                                            | ❌                                         |
| メモリ             | ✅ (短期 + 長期)                                         | ✅ (チェックポイント / 永続化)                                                                                                | ✅ (セッション + 長期)                                   | ❌                                         |
| MCP 対応           | ✅                                                       | ✅                                                                                                                            | ✅                                                       | ✅                                         |
| モデルルーター     | ✅ (LiteLLM 統合)                                        | ✅ (多数プロバイダー)                                                                                                         | ✅ (AI SDK 統合)                                         | ✅ (コア機能)                              |
| Human-in-the-loop  | ✅                                                       | ✅ (LangGraph: interrupt)                                                                                                     | ✅ (suspend / resume)                                    | ⚠️                                         |
| ストリーミング     | ✅                                                       | ✅                                                                                                                            | ✅                                                       | ✅ (コア機能)                              |
| 構造化出力         | ✅                                                       | ✅                                                                                                                            | ✅                                                       | ✅ (コア機能)                              |
| エコシステム成熟度 | 高い (25K+ stars)                                       | 非常に高い (100K+ stars)                                                                                                     | 成長中 (22K+ stars)                                     | 高い (Vercel エコシステム)                |
| 学習コスト         | 低い (直感的 API)                                       | 高い (抽象化が多い)                                                                                                          | 中程度                                                  | 低い (シンプル API)                       |

### Pricing

| プラン    | CrewAI                               | LangChain / LangGraph                               | Mastra                     | Vercel AI SDK        |
| --------- | ------------------------------------ | --------------------------------------------------- | -------------------------- | -------------------- |
| Framework | 無料 (MIT)                           | 無料 (MIT)                                          | 無料 (Apache-2.0)          | 無料 (Apache-2.0)    |
| Platform  | AMP: $99/月〜 / Enterprise: カスタム | LangSmith: 無料〜$39/seat/月 / Deployment: 従量課金 | 年額固定 (Mastra Platform) | Vercel: $0〜$20/月〜 |

### Guidelines

**→ 言語スタックと要件で選択する。**

- TypeScript + フルスタック (Agent + Workflow + RAG + Evals) → **Mastra**
- TypeScript + 軽量 (モデルルーティング + ツール呼び出し + ストリーミング) → **Vercel AI SDK**
- Python + 複雑なグラフ制御 + 状態管理 → **LangGraph**
- Python + 素早いマルチエージェント構築 + 直感的 API → **CrewAI**
- Python + 豊富なインテグレーション + エコシステム → **LangChain**
- Mastra は内部で Vercel AI SDK を使用しており、AI SDK の上位レイヤーとして位置づけられる
- LangGraph は LangChain の上位レイヤーで、複雑なエージェントワークフローに特化
- CrewAI は「役割分担型マルチエージェント」に特化しており、プロトタイピングが最速

## LLM Observability: Arize Phoenix vs Langfuse vs LangSmith

| 比較項目           | Arize Phoenix                                           | Langfuse                                                  | LangSmith                      |
| ------------------ | ------------------------------------------------------- | --------------------------------------------------------- | ------------------------------ |
| 提供元             | Arize AI                                                | Langfuse GmbH (ClickHouse 傘下)                           | LangChain, Inc.                |
| リポジトリ         | [Arize-ai/phoenix](https://github.com/Arize-ai/phoenix) | [langfuse/langfuse](https://github.com/langfuse/langfuse) | - (商用 SaaS)                  |
| ライセンス         | Elastic License 2.0                                     | MIT (コア)                                                | 商用                           |
| セルフホスト       | ✅ (機能制限なし)                                        | ✅ (機能制限なし)                                          | ❌                              |
| クラウドホスト     | ✅ (Arize Cloud / AX)                                    | ✅ (Langfuse Cloud)                                        | ✅ (SaaS のみ)                  |
| トレーシング       | ✅ (ネスト対応)                                          | ✅ (ネスト対応)                                            | ✅ (ネスト対応)                 |
| OpenTelemetry      | ✅ (OTel ネイティブ)                                     | ✅ (OTLP エンドポイント)                                   | ⚠️ (独自形式中心)               |
| コスト分析         | ✅                                                       | ✅                                                         | ✅                              |
| 評価 (Evals)       | ✅ (自動 + LLM-as-judge)                                 | ✅ (自動 + 手動 + LLM-as-judge)                            | ✅ (自動 + 手動 + Online Evals) |
| プロンプト管理     | ❌                                                       | ✅ (バージョニング)                                        | ✅ (Hub + バージョニング)       |
| データセット管理   | ✅                                                       | ✅                                                         | ✅                              |
| フレームワーク統合 | 広い (OpenAI / LangChain / LlamaIndex 等)               | 広い (OpenAI / LangChain / Mastra / n8n 等)               | LangChain / LangGraph に最適化 |
| Agent デプロイ     | ❌                                                       | ❌                                                         | ✅ (LangSmith Deployment)       |
| SDK                | Python                                                  | Python / TypeScript                                       | Python / TypeScript            |
| 実験管理           | ✅ (実験 + ベンチマーク)                                 | ⚠️ (基本的)                                                | ✅ (A/B テスト + Playground)    |

### Pricing

| プラン       | Arize Phoenix               | Langfuse                    | LangSmith                |
| ------------ | --------------------------- | --------------------------- | ------------------------ |
| 無料枠       | セルフホスト: 無料 (無制限) | Hobby: 50K units/月, 2 users | Developer: 5K traces/月, 1 seat |
| 有料         | AX (Enterprise): カスタム   | Core: $29/月 / Pro: $199/月  | Plus: $39/seat/月 (Fleet/Engine従量課金あり) |
| Enterprise   | カスタム                    | $2,499/月 (SCIM/監査ログ/SLA) | カスタム                 |
| セルフホスト | 無料 (機能制限なし)         | 無料 (機能制限なし)         | N/A                      |

### Guidelines

**→ セルフホスト + ベンダー非依存なら Langfuse、LangChain エコシステム統合なら LangSmith、ML 実験寄りなら Arize Phoenix。**

- Langfuse: セルフホスト無料・機能制限なし、OpenTelemetry 対応、フレームワーク非依存で最も汎用的
- LangSmith: LangChain / LangGraph を使う場合は最も統合が深い、Fleet によるマネージド Agent デプロイ + Engine + Sandboxes で完全プラットフォーム化
- Arize Phoenix: OpenTelemetry ネイティブ、ML バックグラウンドのチームに馴染みやすい、実験管理が強い
- LangSmith はセルフホスト不可のため、データプライバシー要件が厳しい場合は Langfuse / Phoenix
- Langfuse + LiteLLM の組み合わせが最もコスト効率が高い (両方セルフホスト無料)

## 組み合わせパターン

| パターン                    | 構成                                   | 用途                                         |
| --------------------------- | -------------------------------------- | -------------------------------------------- |
| AI アプリ基盤 (TypeScript)  | LiteLLM + Langfuse + Mastra            | TypeScript Agent 開発 + LLM 管理 + 可観測性  |
| AI アプリ基盤 (Python)      | LiteLLM + Langfuse + LangGraph         | Python Agent 開発 + LLM 管理 + 可観測性      |
| AI アプリ基盤 (ノーコード)  | LiteLLM + Langfuse + Dify              | ノーコード AI アプリ + LLM 管理 + 可観測性   |
| マルチエージェント (Python) | LiteLLM + LangSmith + CrewAI           | 役割分担型 Agent + LLM 管理 + 評価           |
| ワークフロー自動化 + AI     | n8n + LiteLLM + Langfuse               | 汎用自動化 + LLM ルーティング + トレーシング |
| ビジネス自動化              | Zapier or Make.com                     | ノーコード自動化 (LLM Gateway は不要)        |
| 最小構成 (PoC)              | Dify (単体)                            | AI アプリの素早いプロトタイピング            |
| セルフホスト完全構成        | Windmill + LiteLLM + Langfuse + Mastra | 全レイヤーセルフホスト + データ主権確保      |

### Guidelines

**→ 本番運用では LiteLLM (LLM 管理) + Langfuse (可観測性) を基盤レイヤーとして導入し、その上にアプリケーションレイヤーを構築する。**

- LiteLLM / Portkey と Langfuse / LangSmith はレイヤーが異なるため競合しない
- Dify は単体で RAG + Agent + ワークフローを提供するため、小〜中規模では単体利用も有効
- n8n は AI 以外の汎用自動化 (Slack 通知、データ同期等) も含む場合に選択
- Zapier / Make.com は非エンジニアチームが主体の場合に選択
- セルフホスト要件がある場合: LiteLLM + Langfuse + (n8n or Dify or Windmill) + (Mastra or LangGraph)
- LangChain エコシステムに統一する場合: LangChain + LangGraph + LangSmith が最も統合が深い
