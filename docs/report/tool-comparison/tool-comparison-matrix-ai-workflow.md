<!-- omit in toc -->
# Tool Comparison Matrix (AI Workflow)

AI ワークフロー / LLM 基盤ツール選定の判断材料。

対象ツールはカテゴリが異なるため、用途別に分類して比較する。

## History

| 日付       | 内容                                                                                           |
| ---------- | ---------------------------------------------------------------------------------------------- |
| 2026-05-21 | 初版作成。ワークフロー自動化 / LLM Gateway / Agent Framework / Observability の4カテゴリで比較 |

<!-- omit in toc -->
## Table of Contents

- [History](#history)
- [Workflow Automation: n8n vs Make.com vs Zapier vs Dify vs Windmill](#workflow-automation-n8n-vs-makecom-vs-zapier-vs-dify-vs-windmill)
  - [Pricing](#pricing)
  - [Guidelines](#guidelines)
- [LLM Gateway: LiteLLM vs Portkey](#llm-gateway-litellm-vs-portkey)
  - [Guidelines](#guidelines-1)
- [AI Agent Framework: Mastra vs LangChain / LangGraph vs CrewAI vs Vercel AI SDK](#ai-agent-framework-mastra-vs-langchain--langgraph-vs-crewai-vs-vercel-ai-sdk)
  - [Pricing](#pricing-1)
  - [Guidelines](#guidelines-2)
- [LLM Observability: Langfuse vs LangSmith vs Arize Phoenix](#llm-observability-langfuse-vs-langsmith-vs-arize-phoenix)
  - [Pricing](#pricing-2)
  - [Guidelines](#guidelines-3)
- [組み合わせパターン](#組み合わせパターン)
  - [Guidelines](#guidelines-4)

## Workflow Automation: n8n vs Make.com vs Zapier vs Dify vs Windmill

| 比較項目             | n8n                                         | Make.com               | Zapier                 | Dify                                                  | Windmill                                                            |
| -------------------- | ------------------------------------------- | ---------------------- | ---------------------- | ----------------------------------------------------- | ------------------------------------------------------------------- |
| 提供元               | n8n GmbH                                    | Celonis (Make)         | Zapier, Inc.           | LangGenius                                            | Windmill Labs                                                       |
| リポジトリ           | [n8n-io/n8n](https://github.com/n8n-io/n8n) | - (商用 SaaS)          | - (商用 SaaS)          | [langgenius/dify](https://github.com/langgenius/dify) | [windmill-labs/windmill](https://github.com/windmill-labs/windmill) |
| ライセンス           | Sustainable Use License (fair-code)         | 商用                   | 商用                   | Source Available (Apache-2.0 ベース + 追加条項)       | AGPLv3                                                              |
| 実装言語             | TypeScript                                  | - (SaaS)               | - (SaaS)               | Python + TypeScript                                   | Rust + TypeScript                                                   |
| セルフホスト         | ✅ (Docker / K8s)                            | ❌                      | ❌                      | ✅ (Docker / K8s)                                      | ✅ (Docker / K8s)                                                    |
| クラウドホスト       | ✅ (n8n Cloud)                               | ✅ (SaaS のみ)          | ✅ (SaaS のみ)          | ✅ (Dify Cloud)                                        | ✅ (Windmill Cloud)                                                  |
| ビジュアルエディタ   | ✅                                           | ✅                      | ✅                      | ✅                                                     | ✅                                                                   |
| AI エージェント      | ✅ (AI Agent ノード)                         | ✅ (AI Agents)          | ✅ (Agents / Chatbots)  | ✅ (Agent + ReAct / Function Calling)                  | ⚠️ (スクリプトで実装)                                                |
| RAG / ナレッジベース | ⚠️ (外部連携)                                | ⚠️ (外部連携)           | ⚠️ (外部連携)           | ✅ (組み込み RAG パイプライン)                         | ⚠️ (外部連携)                                                        |
| インテグレーション数 | 500+                                        | 3,000+                 | 9,000+                 | 少数 (AI 特化)                                        | 少数 (スクリプト中心)                                               |
| コード実行           | ✅ (JavaScript / Python)                     | ⚠️ (限定的)             | ⚠️ (Code by Zapier)     | ✅ (コードブロック)                                    | ✅ (TypeScript / Python / Go / SQL / Bash)                           |
| MCP 対応             | ⚠️ (コミュニティ)                            | ❌                      | ✅ (Zapier MCP)         | ⚠️ (プラグイン)                                        | ❌                                                                   |
| 対象ユーザー         | 開発者 / テクニカルチーム                   | ビジネスユーザー       | ビジネスユーザー       | AI アプリ開発者                                       | 開発者 / インフラチーム                                             |
| 主な用途             | 汎用ワークフロー + AI パイプライン          | ビジネスプロセス自動化 | ビジネスプロセス自動化 | AI アプリ構築 (チャットボット / Agent)                | 内部ツール / データパイプライン / スクリプト実行                    |

### Pricing

| プラン         | n8n                                   | Make.com           | Zapier               | Dify                        | Windmill                          |
| -------------- | ------------------------------------- | ------------------ | -------------------- | --------------------------- | --------------------------------- |
| 無料枠         | ✅ (セルフホスト Community)            | ✅ (1,000 ops/月)   | ✅ (100 tasks/月)     | ✅ (Sandbox: 200 メッセージ) | ✅ (Cloud: 1,000 実行/月)          |
| Starter / Core | Cloud: €20/月 (2,500 実行)            | $9/月 (10,000 ops) | Professional: $20/月 | Professional: $59/月        | Team: $10/dev/月                  |
| Pro / Team     | Cloud: €50/月 (10,000 実行)           | $16/月             | Team: $69/月         | Team: $159/月               | Pro: $170/月 (1 dev)              |
| Enterprise     | カスタム                              | カスタム           | カスタム             | カスタム                    | カスタム                          |
| セルフホスト   | 無料 (Community) / €333/月 (Business) | N/A                | N/A                  | 無料 (機能制限なし)         | 無料 (AGPLv3) / 有料 (Enterprise) |

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

## AI Agent Framework: Mastra vs LangChain / LangGraph vs CrewAI vs Vercel AI SDK

| 比較項目           | Mastra                                                  | LangChain / LangGraph                                                                                                        | CrewAI                                                  | Vercel AI SDK                             |
| ------------------ | ------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------- | ----------------------------------------- |
| 提供元             | Mastra (元 Gatsby / YC W25)                             | LangChain, Inc.                                                                                                              | CrewAI, Inc.                                            | Vercel                                    |
| リポジトリ         | [mastra-ai/mastra](https://github.com/mastra-ai/mastra) | [langchain-ai/langchain](https://github.com/langchain-ai/langchain) / [langgraph](https://github.com/langchain-ai/langgraph) | [crewAIInc/crewAI](https://github.com/crewAIInc/crewAI) | [vercel/ai](https://github.com/vercel/ai) |
| ライセンス         | Apache-2.0                                              | MIT                                                                                                                          | MIT (Framework) / 商用 (AMP)                            | Apache-2.0                                |
| 言語               | TypeScript                                              | Python / JavaScript                                                                                                          | Python                                                  | TypeScript                                |
| Agent 定義         | ✅ (プロンプト + ツール + メモリ)                        | ✅ (LangGraph: グラフベース状態管理)                                                                                          | ✅ (ロール + ゴール + バックストーリー)                  | ✅ (generateText + tools)                  |
| マルチエージェント | ✅                                                       | ✅ (LangGraph: 明示的グラフ制御)                                                                                              | ✅ (役割分担型が得意)                                    | ⚠️ (自前実装)                              |
| ワークフロー       | ✅ (step / then / after)                                 | ✅ (LangGraph: ノード + エッジ)                                                                                               | ✅ (タスクベース)                                        | ⚠️ (自前実装)                              |
| RAG                | ✅ (組み込み)                                            | ✅ (豊富なインテグレーション)                                                                                                 | ⚠️ (外部連携)                                            | ❌                                         |
| Evals              | ✅ (組み込み)                                            | ✅ (LangSmith 連携)                                                                                                           | ⚠️ (AMP で提供)                                          | ❌                                         |
| メモリ             | ✅ (セッション + 長期)                                   | ✅ (チェックポイント / 永続化)                                                                                                | ✅ (短期 + 長期)                                         | ❌                                         |
| MCP 対応           | ✅                                                       | ✅                                                                                                                            | ✅                                                       | ✅                                         |
| モデルルーター     | ✅ (AI SDK 統合)                                         | ✅ (多数プロバイダー)                                                                                                         | ✅ (LiteLLM 統合)                                        | ✅ (コア機能)                              |
| Human-in-the-loop  | ✅ (suspend / resume)                                    | ✅ (LangGraph: interrupt)                                                                                                     | ✅                                                       | ⚠️                                         |
| ストリーミング     | ✅                                                       | ✅                                                                                                                            | ✅                                                       | ✅ (コア機能)                              |
| 構造化出力         | ✅                                                       | ✅                                                                                                                            | ✅                                                       | ✅ (コア機能)                              |
| エコシステム成熟度 | 成長中 (22K+ stars)                                     | 非常に高い (100K+ stars)                                                                                                     | 高い (25K+ stars)                                       | 高い (Vercel エコシステム)                |
| 学習コスト         | 中程度                                                  | 高い (抽象化が多い)                                                                                                          | 低い (直感的 API)                                       | 低い (シンプル API)                       |

### Pricing

| プラン    | Mastra                     | LangChain / LangGraph                               | CrewAI                               | Vercel AI SDK        |
| --------- | -------------------------- | --------------------------------------------------- | ------------------------------------ | -------------------- |
| Framework | 無料 (Apache-2.0)          | 無料 (MIT)                                          | 無料 (MIT)                           | 無料 (Apache-2.0)    |
| Platform  | 年額固定 (Mastra Platform) | LangSmith: 無料〜$39/seat/月 / Deployment: 従量課金 | AMP: $99/月〜 / Enterprise: カスタム | Vercel: $0〜$20/月〜 |

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

## LLM Observability: Langfuse vs LangSmith vs Arize Phoenix

| 比較項目           | Langfuse                                                  | LangSmith                      | Arize Phoenix                                           |
| ------------------ | --------------------------------------------------------- | ------------------------------ | ------------------------------------------------------- |
| 提供元             | Langfuse GmbH (ClickHouse 傘下)                           | LangChain, Inc.                | Arize AI                                                |
| リポジトリ         | [langfuse/langfuse](https://github.com/langfuse/langfuse) | - (商用 SaaS)                  | [Arize-ai/phoenix](https://github.com/Arize-ai/phoenix) |
| ライセンス         | MIT (コア)                                                | 商用                           | Elastic License 2.0                                     |
| セルフホスト       | ✅ (機能制限なし)                                          | ❌                              | ✅ (機能制限なし)                                        |
| クラウドホスト     | ✅ (Langfuse Cloud)                                        | ✅ (SaaS のみ)                  | ✅ (Arize Cloud / AX)                                    |
| トレーシング       | ✅ (ネスト対応)                                            | ✅ (ネスト対応)                 | ✅ (ネスト対応)                                          |
| OpenTelemetry      | ✅ (OTLP エンドポイント)                                   | ⚠️ (独自形式中心)               | ✅ (OTel ネイティブ)                                     |
| コスト分析         | ✅                                                         | ✅                              | ✅                                                       |
| 評価 (Evals)       | ✅ (自動 + 手動 + LLM-as-judge)                            | ✅ (自動 + 手動 + Online Evals) | ✅ (自動 + LLM-as-judge)                                 |
| プロンプト管理     | ✅ (バージョニング)                                        | ✅ (Hub + バージョニング)       | ❌                                                       |
| データセット管理   | ✅                                                         | ✅                              | ✅                                                       |
| フレームワーク統合 | 広い (OpenAI / LangChain / Mastra / n8n 等)               | LangChain / LangGraph に最適化 | 広い (OpenAI / LangChain / LlamaIndex 等)               |
| Agent デプロイ     | ❌                                                         | ✅ (LangSmith Deployment)       | ❌                                                       |
| SDK                | Python / TypeScript                                       | Python / TypeScript            | Python                                                  |
| 実験管理           | ⚠️ (基本的)                                                | ✅ (A/B テスト + Playground)    | ✅ (実験 + ベンチマーク)                                 |

### Pricing

| プラン       | Langfuse                    | LangSmith                | Arize Phoenix               |
| ------------ | --------------------------- | ------------------------ | --------------------------- |
| 無料枠       | Hobby: 50K observations/月  | Developer: 10K traces/月 | セルフホスト: 無料 (無制限) |
| 有料         | Pro: $59/月 / Team: $199/月 | Plus: $39/seat/月        | AX (Enterprise): カスタム   |
| Enterprise   | カスタム                    | カスタム                 | カスタム                    |
| セルフホスト | 無料 (機能制限なし)         | N/A                      | 無料 (機能制限なし)         |

### Guidelines

**→ セルフホスト + ベンダー非依存なら Langfuse、LangChain エコシステム統合なら LangSmith、ML 実験寄りなら Arize Phoenix。**

- Langfuse: セルフホスト無料・機能制限なし、OpenTelemetry 対応、フレームワーク非依存で最も汎用的
- LangSmith: LangChain / LangGraph を使う場合は最も統合が深い、Agent デプロイ機能あり
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
