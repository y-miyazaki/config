# Tool Comparison Matrix (AI Workflow)

AI ワークフロー / LLM 基盤ツール選定の判断材料。

対象ツールはカテゴリが異なるため、用途別に分類して比較する。

## History

| 日付       | 内容                                                                                                                                                                                                                                                                                                                                                                                                          |
| ---------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 2026-11-18 | 全般最新化: Activepieces / Bifrost / OpenRouter / Google ADK / OpenAI Agents SDK / Pydantic AI / Opik を追加。Portkey の Palo Alto Networks 買収、Make.com / n8n / Windmill / Dify の MCP 対応、n8n・Zapier・Make.com の連携数、Dify・n8n・Windmill・Zapier・CrewAI・Mastra・Arize AX の料金、LangSmith のセルフホスト (Enterprise アドオン)、Phoenix の TypeScript SDK、Mastra のライセンス、各 stars を更新 |
| 2026-06-17 | 全般最新化: LangSmith Fleet/Engine プラットフォーム化反映、Langfuse pricing 更新 ($29〜$2,499)、n8n AI Workflow Builder 追加、Mastra managed DB 追加                                                                                                                                                                                                                                                          |
| 2026-05-21 | 初版作成。ワークフロー自動化 / LLM Gateway / Agent Framework / Observability の 4 カテゴリで比較                                                                                                                                                                                                                                                                                                              |

## Workflow Automation: Activepieces vs Dify vs Make.com vs n8n vs Windmill vs Zapier

| 比較項目             | Activepieces                                                              | Dify                                                      | Make.com               | n8n                                                            | Windmill                                                            | Zapier                 |
| -------------------- | ------------------------------------------------------------------------- | --------------------------------------------------------- | ---------------------- | -------------------------------------------------------------- | ------------------------------------------------------------------- | ---------------------- |
| 提供元               | Activepieces                                                              | LangGenius                                                | Celonis (Make)         | n8n GmbH                                                       | Windmill Labs                                                       | Zapier, Inc.           |
| リポジトリ           | [activepieces/activepieces](https://github.com/activepieces/activepieces) | [langgenius/dify](https://github.com/langgenius/dify)     | - (商用 SaaS)          | [n8n-io/n8n](https://github.com/n8n-io/n8n)                    | [windmill-labs/windmill](https://github.com/windmill-labs/windmill) | - (商用 SaaS)          |
| ライセンス           | MIT (Community Edition) / 商用 (Enterprise 機能)                          | Source Available (Apache-2.0 ベース + 追加条項)           | 商用                   | Sustainable Use License (fair-code)                            | AGPLv3                                                              | 商用                   |
| 実装言語             | TypeScript                                                                | Python + TypeScript                                       | - (SaaS)               | TypeScript                                                     | Rust + TypeScript                                                   | - (SaaS)               |
| セルフホスト         | ✅ (Docker Compose)                                                       | ✅ (Docker / K8s)                                         | ❌                     | ✅ (Docker / K8s)                                              | ✅ (Docker / K8s)                                                   | ❌                     |
| クラウドホスト       | ✅ (Activepieces Cloud)                                                   | ✅ (Dify Cloud)                                           | ✅ (SaaS のみ)         | ✅ (n8n Cloud)                                                 | ✅ (Windmill Cloud)                                                 | ✅ (SaaS のみ)         |
| ビジュアルエディタ   | ✅                                                                        | ✅                                                        | ✅                     | ✅                                                             | ✅                                                                  | ✅                     |
| AI エージェント      | ✅ (Agents)                                                               | ✅ (Agent + ReAct / Function Calling)                     | ✅ (AI Agents)         | ✅ (AI Agent ノード)                                           | ⚠️ (スクリプトで実装)                                               | ✅ (Agents / Chatbots) |
| RAG / ナレッジベース | ⚠️ (Agent Knowledge)                                                      | ✅ (組み込み RAG パイプライン)                            | ⚠️ (外部連携)          | ⚠️ (外部連携)                                                  | ⚠️ (外部連携)                                                       | ⚠️ (外部連携)          |
| インテグレーション数 | 760+ apps                                                                 | 少数 (AI 特化)                                            | 3,500+                 | 1,500+ (README)                                                | 少数 (スクリプト中心)                                               | 10,000+                |
| コード実行           | -                                                                         | ✅ (コードブロック)                                       | ⚠️ (限定的)            | ✅ (JavaScript / Python)                                       | ✅ (TypeScript / Python / Go / SQL / Bash 等 20+ 言語)              | ⚠️ (Code by Zapier)    |
| MCP 対応             | ✅ (MCP Server)                                                           | ✅ (アプリを MCP Server として公開 / Agent から MCP 接続) | ✅ (Make MCP Server)   | ✅ (MCP Server Trigger / MCP Client Tool / Instance-level MCP) | ✅ (MCP Server + AI セッションの MCP Client)                        | ✅ (Zapier MCP)        |
| 対象ユーザー         | -                                                                         | AI アプリ開発者                                           | ビジネスユーザー       | 開発者 / テクニカルチーム                                      | 開発者 / インフラチーム                                             | ビジネスユーザー       |
| 主な用途             | ワークフロー自動化 + AI Agent / MCP                                       | AI アプリ構築 (チャットボット / Agent)                    | ビジネスプロセス自動化 | 汎用ワークフロー + AI パイプライン                             | 内部ツール / データパイプライン / スクリプト実行                    | ビジネスプロセス自動化 |

### Pricing

| プラン         | Activepieces                    | Dify                                         | Make.com                | n8n                                                     | Windmill                                              | Zapier                                       |
| -------------- | ------------------------------- | -------------------------------------------- | ----------------------- | ------------------------------------------------------- | ----------------------------------------------------- | -------------------------------------------- |
| 無料枠         | ✅ (Free: 1,000 credits/月)     | ✅ (Sandbox: 200 credits (一回限り))         | ✅ (1,000 credits/月)   | ✅ (セルフホスト Community)                             | ✅ (Community: 実行無制限)                            | ✅ (100 tasks/月)                            |
| Starter / Core | Plus: \$20/月 (10,000 credits)  | Professional: \$590/年 (5,000 credits/月)    | \$9/月 (10,000 credits) | Cloud: €20/月 (2,500 実行、年払い)                      | Builder seat: \$20/月 (Non-builder: \$10/月)          | Professional: \$19.99/月 (750 tasks、年払い) |
| Pro / Team     | Team: \$200/月 (50,000 credits) | Team: \$1,590/年 (10,000 credits/月)         | \$16/月                 | Cloud: €50/月 (10,000 実行、年払い)                     | Pro: 個人・10 名未満の小規模事業者向け (価格は要確認) | Team: \$69/月 (2,000 tasks、年払い)          |
| Enterprise     | Ultimate: カスタム              | カスタム                                     | カスタム                | カスタム                                                | Enterprise: \$120/月〜                                | カスタム                                     |
| セルフホスト   | 無料 (Community Edition)        | 無料 (Community: 単一 workspace、非商用向け) | N/A                     | 無料 (Community) / €667/月 (Business、年払い、40K 実行) | 無料 (AGPLv3) / 有料 (Enterprise)                     | N/A                                          |

### Guidelines

**→ 用途と対象ユーザーで選択する。**

- 汎用ワークフロー自動化 + AI 統合 + セルフホスト → **n8n**
- MIT ライセンスの OSS で自動化 + MCP を使いたい → **Activepieces**
- ビジネスユーザー主体 / SaaS 連携が多い / 非エンジニア → **Zapier** (連携数最大) または **Make.com** (コスパ重視)
- AI アプリ (チャットボット / RAG / Agent) を素早く構築 → **Dify**
- スクリプト実行基盤 / 内部ツール / データパイプライン → **Windmill**
- データプライバシー / VPC 内運用が必須 → **n8n** / **Dify** / **Windmill** / **Activepieces** (セルフホスト)
- Zapier vs Make.com: Zapier は連携数 (10,000+) で圧倒、Make.com は同等機能を低コストで提供
- n8n と Dify は併用可能: n8n でオーケストレーション、Dify で AI アプリ部分を担当
- Activepieces の連携数 (760+) は公式 docs 記載値。Make.com の \$9 / \$16 は公式ページから取得できず、旧記載のまま (第三者情報では一致)。

## LLM Gateway: Bifrost vs LiteLLM vs OpenRouter vs Portkey

| 比較項目           | Bifrost                                               | LiteLLM                                               | OpenRouter                                                                                 | Portkey                                                                                                       |
| ------------------ | ----------------------------------------------------- | ----------------------------------------------------- | ------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------- |
| 提供元             | Maxim AI                                              | BerriAI                                               | OpenRouter                                                                                 | Portkey AI (Palo Alto Networks 傘下)                                                                          |
| リポジトリ         | [maximhq/bifrost](https://github.com/maximhq/bifrost) | [BerriAI/litellm](https://github.com/BerriAI/litellm) | - (商用 SaaS)                                                                              | [portkey-ai/gateway](https://github.com/portkey-ai/gateway)                                                   |
| ライセンス         | Apache-2.0 (OSS) / Enterprise (商用)                  | MIT (OSS) / Enterprise (商用)                         | 商用                                                                                       | MIT (Gateway OSS) / Managed (商用)                                                                            |
| 実装言語           | Go                                                    | Python                                                | - (SaaS)                                                                                   | TypeScript (Gateway) / Platform (SaaS)                                                                        |
| セルフホスト       | ✅                                                    | ✅ (Docker / K8s)                                     | ❌                                                                                         | ✅ (Gateway OSS のみ)                                                                                         |
| マネージドサービス | -                                                     | ❌ (セルフホストのみ)                                 | ✅ (SaaS)                                                                                  | ✅ (Portkey Cloud)                                                                                            |
| 統一 API           | ✅ (OpenAI 互換)                                      | ✅ (OpenAI 互換)                                      | ✅ (OpenAI 互換)                                                                           | ✅ (OpenAI 互換)                                                                                              |
| 対応プロバイダー   | 23+ (README)                                          | 100+                                                  | 80+ providers / 600+ models (有料プラン)                                                   | 250+ LLMs (README)                                                                                            |
| ロードバランシング | ✅ (複数キー / プロバイダー)                          | ✅                                                    | -                                                                                          | ✅                                                                                                            |
| フォールバック     | ✅                                                    | ✅                                                    | ✅ (`models` 配列で優先順位指定)                                                           | ✅ (条件付きルーティング)                                                                                     |
| コストトラッキング | -                                                     | ✅                                                    | -                                                                                          | ✅                                                                                                            |
| 予算管理           | ✅ (Virtual Keys / チーム / 顧客)                     | ✅ (チーム / プロジェクト / ユーザー)                 | -                                                                                          | ✅ (Virtual Keys)                                                                                             |
| ガードレール       | ⚠️ (Enterprise)                                       | ✅ (Enterprise)                                       | -                                                                                          | ✅ (組み込み)                                                                                                 |
| キャッシュ         | ✅ (Semantic Cache)                                   | ✅                                                    | -                                                                                          | ✅ (Semantic Cache)                                                                                           |
| Observability 統合 | ✅ (Prometheus / 分散トレース / リクエストログ)       | ⚠️ (外部連携: Langfuse 等)                            | -                                                                                          | ✅ (組み込みトレーシング + ログ)                                                                              |
| プロンプト管理     | -                                                     | ❌                                                    | -                                                                                          | ✅ (Prompt Templates)                                                                                         |
| Pricing            | OSS: 無料 / Enterprise: カスタム                      | OSS: 無料 / Enterprise: カスタム                      | Free: 手数料なし / Standard: 5.5% / Business: 8% (クレジット購入時) / Enterprise: カスタム | OSS Gateway: 無料 / Developer: 無料 (10K logs/月) / Production: \$49/月 (100K logs/月) / Enterprise: カスタム |

### Guidelines

**→ セルフホスト + コスト重視なら LiteLLM (または軽量さ重視の Bifrost)、マネージド + 統合機能重視なら Portkey、モデル調達の一本化なら OpenRouter。**

- LiteLLM: セルフホスト前提、MIT ライセンスで自由度が高い、Python エコシステムとの親和性
- Bifrost: Apache-2.0 の OSS ゲートウェイ (Go)。Virtual Keys / 予算 / Semantic Cache を OSS で提供し、Guardrails / MCP gateway / adaptive load balancing は Enterprise 機能
- OpenRouter: 単一 API で多数のモデルを利用できるホスト型。手数料はクレジット購入時 (Standard 5.5% / Business 8%)、推論は各プロバイダーの list price。セルフホスト不可
- Portkey: マネージドで運用負荷が低い、Observability + ガードレール + プロンプト管理が組み込み。2026-05-29 に Palo Alto Networks が買収完了し Prisma AIRS の AI Gateway に位置づけられた (既存顧客のサポートは継続と発表)。Gateway 2.0 で enterprise gateway の OSS 統合が予告されている (pre-release)
- 全ツールとも OpenAI 互換 API を提供するため、アプリケーション側の変更は最小
- AWS Bedrock を Gateway 的に使う場合は直接 Bedrock API でも可 (ただしマルチプロバイダーには非対応)
- 小規模 / 単一プロバイダーの場合は Gateway 不要 (直接 SDK を使用)
- Bifrost / OpenRouter の `-` は公式 README・docs で確認できなかった項目 (非対応を意味しない)

## AI Agent Framework: CrewAI vs Google ADK vs LangChain / LangGraph vs Mastra vs OpenAI Agents SDK vs Pydantic AI vs Vercel AI SDK

| 比較項目           | CrewAI                                                  | Google ADK                                                     | LangChain / LangGraph                                                                                                        | Mastra                                                  | OpenAI Agents SDK                                                             | Pydantic AI                                                     | Vercel AI SDK                             |
| ------------------ | ------------------------------------------------------- | -------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------- | ----------------------------------------------------------------------------- | --------------------------------------------------------------- | ----------------------------------------- |
| 提供元             | CrewAI, Inc.                                            | Google                                                         | LangChain, Inc.                                                                                                              | Mastra (元 Gatsby / YC W25)                             | OpenAI                                                                        | Pydantic                                                        | Vercel                                    |
| リポジトリ         | [crewAIInc/crewAI](https://github.com/crewAIInc/crewAI) | [google/adk-python](https://github.com/google/adk-python)      | [langchain-ai/langchain](https://github.com/langchain-ai/langchain) / [langgraph](https://github.com/langchain-ai/langgraph) | [mastra-ai/mastra](https://github.com/mastra-ai/mastra) | [openai/openai-agents-python](https://github.com/openai/openai-agents-python) | [pydantic/pydantic-ai](https://github.com/pydantic/pydantic-ai) | [vercel/ai](https://github.com/vercel/ai) |
| ライセンス         | MIT (Framework) / 商用 (AMP)                            | Apache-2.0                                                     | MIT                                                                                                                          | Apache-2.0 (`ee/` は Mastra Enterprise License)         | MIT                                                                           | MIT                                                             | Apache-2.0                                |
| 言語               | Python                                                  | Python (他に Java / Kotlin / Go / TypeScript 版が別リポジトリ) | Python / JavaScript                                                                                                          | TypeScript                                              | Python / TypeScript                                                           | Python                                                          | TypeScript                                |
| Agent 定義         | ✅ (ロール + ゴール + バックストーリー)                 | ✅                                                             | ✅ (LangGraph: グラフベース状態管理)                                                                                         | ✅ (プロンプト + ツール + メモリ)                       | ✅                                                                            | ✅ (型付き依存性注入 + ツール)                                  | ✅ (generateText + tools)                 |
| マルチエージェント | ✅ (役割分担型が得意)                                   | ✅ (階層構成 / Task API)                                       | ✅ (LangGraph: 明示的グラフ制御)                                                                                             | ✅                                                      | ✅ (handoffs / Agents as tools)                                               | ✅ (sub-agents)                                                 | ⚠️ (自前実装)                             |
| ワークフロー       | ✅ (タスクベース)                                       | ✅ (グラフベース Workflow)                                     | ✅ (LangGraph: ノード + エッジ)                                                                                              | ✅ (step / then / after)                                | -                                                                             | ✅ (Pydantic Graph / Durable Execution)                         | ⚠️ (自前実装)                             |
| RAG                | ⚠️ (外部連携)                                           | -                                                              | ✅ (豊富なインテグレーション)                                                                                                | ✅ (組み込み)                                           | -                                                                             | -                                                               | ❌                                        |
| Evals              | ⚠️ (AMP で提供)                                         | ✅ (`adk eval`)                                                | ✅ (LangSmith 連携)                                                                                                          | ✅ (組み込み)                                           | -                                                                             | ✅ (Pydantic Evals)                                             | ❌                                        |
| メモリ             | ✅ (短期 + 長期)                                        | -                                                              | ✅ (チェックポイント / 永続化)                                                                                               | ✅ (セッション + 長期)                                  | ✅ (Sessions)                                                                 | -                                                               | ❌                                        |
| MCP 対応           | ✅                                                      | ✅                                                             | ✅                                                                                                                           | ✅                                                      | ✅                                                                            | ✅                                                              | ✅                                        |
| モデルルーター     | ✅ (LiteLLM 統合)                                       | ⚠️ (Gemini 最適化、モデル非依存を明記)                         | ✅ (多数プロバイダー)                                                                                                        | ✅ (AI SDK 統合)                                        | ✅ (OpenAI API + 100+ LLMs)                                                   | ✅ (主要プロバイダー + モデルフォールバック)                    | ✅ (コア機能)                             |
| Human-in-the-loop  | ✅                                                      | ✅                                                             | ✅ (LangGraph: interrupt)                                                                                                    | ✅ (suspend / resume)                                   | ✅                                                                            | ✅ (ツール承認)                                                 | ⚠️                                        |
| ストリーミング     | ✅                                                      | -                                                              | ✅                                                                                                                           | ✅                                                      | -                                                                             | -                                                               | ✅ (コア機能)                             |
| 構造化出力         | ✅                                                      | -                                                              | ✅                                                                                                                           | ✅                                                      | -                                                                             | ✅ (`output_type`)                                              | ✅ (コア機能)                             |
| エコシステム成熟度 | 高い (60K+ stars)                                       | 高い (22K+ stars)                                              | 非常に高い (LangChain 150K+ / LangGraph 45K+ stars)                                                                          | 成長中 (29K+ stars)                                     | 高い (30K+ stars)                                                             | 高い (21K+ stars)                                               | 高い (Vercel エコシステム、28K+ stars)    |
| 学習コスト         | 低い (直感的 API)                                       | -                                                              | 高い (抽象化が多い)                                                                                                          | 中程度                                                  | -                                                                             | -                                                               | 低い (シンプル API)                       |

### Pricing

| プラン    | CrewAI                                                    | Google ADK        | LangChain / LangGraph                                | Mastra                                                                                             | OpenAI Agents SDK | Pydantic AI                                                                                     | Vercel AI SDK        |
| --------- | --------------------------------------------------------- | ----------------- | ---------------------------------------------------- | -------------------------------------------------------------------------------------------------- | ----------------- | ----------------------------------------------------------------------------------------------- | -------------------- |
| Framework | 無料 (MIT)                                                | 無料 (Apache-2.0) | 無料 (MIT)                                           | 無料 (Apache-2.0)                                                                                  | 無料 (MIT)        | 無料 (MIT)                                                                                      | 無料 (Apache-2.0)    |
| Platform  | AMP Suite: Basic 無料 (50 実行/月) / Enterprise: カスタム | -                 | LangSmith: 無料〜\$39/seat/月 / Deployment: 従量課金 | Mastra Platform: Free \$0 / Starter \$25 / Team \$250 (/月、workspace 単位) / Enterprise: カスタム | -                 | Logfire: Personal 無料 (10M records/月) / Team \$49/月 / Growth \$249/月 / Enterprise: カスタム | Vercel: $0〜$20/月〜 |

### Guidelines

**→ 言語スタックと要件で選択する。**

- TypeScript + フルスタック (Agent + Workflow + RAG + Evals) → **Mastra**
- TypeScript + 軽量 (モデルルーティング + ツール呼び出し + ストリーミング) → **Vercel AI SDK**
- Python + 複雑なグラフ制御 + 状態管理 → **LangGraph**
- Python + 素早いマルチエージェント構築 + 直感的 API → **CrewAI**
- Python + 豊富なインテグレーション + エコシステム → **LangChain**
- Python + 型安全な構造化出力 + Evals / Durable Execution → **Pydantic AI**
- OpenAI モデル中心 + handoffs / ガードレール / トレーシング → **OpenAI Agents SDK**
- Google Cloud (Gemini / Cloud Run) 中心 + グラフ Workflow → **Google ADK**
- Mastra は内部で Vercel AI SDK を使用しており、AI SDK の上位レイヤーとして位置づけられる
- LangGraph は LangChain の上位レイヤーで、複雑なエージェントワークフローに特化
- CrewAI は「役割分担型マルチエージェント」に特化しており、プロトタイピングが最速
- Google ADK / OpenAI Agents SDK / Pydantic AI の `-` は公式 README で確認できなかった項目 (非対応を意味しない)

## LLM Observability: Arize Phoenix vs Langfuse vs LangSmith vs Opik

| 比較項目           | Arize Phoenix                                           | Langfuse                                                  | LangSmith                       | Opik                                                                        |
| ------------------ | ------------------------------------------------------- | --------------------------------------------------------- | ------------------------------- | --------------------------------------------------------------------------- |
| 提供元             | Arize AI                                                | Langfuse GmbH (ClickHouse 傘下)                           | LangChain, Inc.                 | Comet                                                                       |
| リポジトリ         | [Arize-ai/phoenix](https://github.com/Arize-ai/phoenix) | [langfuse/langfuse](https://github.com/langfuse/langfuse) | - (商用 SaaS)                   | [comet-ml/opik](https://github.com/comet-ml/opik)                           |
| ライセンス         | Elastic License 2.0                                     | MIT (コア、`ee` フォルダ除く)                             | 商用                            | Apache-2.0                                                                  |
| セルフホスト       | ✅ (機能制限なし)                                       | ✅ (機能制限なし)                                         | ⚠️ (Enterprise アドオン / K8s)  | ✅ (機能制限なし)                                                           |
| クラウドホスト     | ✅ (Arize Cloud / AX)                                   | ✅ (Langfuse Cloud)                                       | ✅                              | ✅ (Comet Cloud)                                                            |
| トレーシング       | ✅ (ネスト対応)                                         | ✅ (ネスト対応)                                           | ✅ (ネスト対応)                 | ✅ (ネスト対応)                                                             |
| OpenTelemetry      | ✅ (OTel ネイティブ)                                    | ✅ (OTLP エンドポイント)                                  | ⚠️ (独自形式中心)               | ✅ (OpenTelemetry 対応)                                                     |
| コスト分析         | ✅                                                      | ✅                                                        | ✅                              | -                                                                           |
| 評価 (Evals)       | ✅ (自動 + LLM-as-judge)                                | ✅ (自動 + 手動 + LLM-as-judge)                           | ✅ (自動 + 手動 + Online Evals) | ✅ (自動 + LLM-as-judge + PyTest 連携 + Online 評価)                        |
| プロンプト管理     | ❌                                                      | ✅ (バージョニング)                                       | ✅ (Hub + バージョニング)       | ✅                                                                          |
| データセット管理   | ✅                                                      | ✅                                                        | ✅                              | ✅                                                                          |
| フレームワーク統合 | 広い (OpenAI / LangChain / LlamaIndex 等)               | 広い (OpenAI / LangChain / Mastra / n8n 等)               | LangChain / LangGraph に最適化  | 広い (OpenAI / Anthropic / LangChain / LlamaIndex / CrewAI / Google ADK 等) |
| Agent デプロイ     | ❌                                                      | ❌                                                        | ✅ (LangSmith Deployment)       | -                                                                           |
| SDK                | Python / TypeScript                                     | Python / TypeScript                                       | Python / TypeScript             | Python / TypeScript                                                         |
| 実験管理           | ✅ (実験 + ベンチマーク)                                | ⚠️ (基本的)                                               | ✅ (A/B テスト + Playground)    | ✅ (datasets + experiments)                                                 |

### Pricing

| プラン       | Arize Phoenix                                             | Langfuse                       | LangSmith                                                     | Opik                                          |
| ------------ | --------------------------------------------------------- | ------------------------------ | ------------------------------------------------------------- | --------------------------------------------- |
| 無料枠       | セルフホスト: 無料 (無制限) / AX Free: \$0 (25K spans/月) | Hobby: 50K units/月, 2 users   | Developer: 5K traces/月, 1 seat                               | OSS: 無料 (無制限) / Free Cloud: 25K spans/月 |
| 有料         | AX Pro: \$50/月 (50K spans/月)                            | Core: $29/月 / Pro: $199/月    | Plus: \$39/seat/月 (10K traces/月、Fleet/Engine 従量課金あり) | Pro Cloud: \$19/月 (100K spans/月)            |
| Enterprise   | AX Enterprise: カスタム                                   | \$2,499/月 (SCIM/監査ログ/SLA) | カスタム                                                      | カスタム                                      |
| セルフホスト | 無料 (機能制限なし)                                       | 無料 (機能制限なし)            | Enterprise アドオン (要契約)                                  | 無料 (機能制限なし)                           |

### Guidelines

**→ セルフホスト + ベンダー非依存なら Langfuse、LangChain エコシステム統合なら LangSmith、ML 実験寄りなら Arize Phoenix、Apache-2.0 の OSS で完結したいなら Opik。**

- Langfuse: セルフホスト無料・機能制限なし、OpenTelemetry 対応、フレームワーク非依存で最も汎用的
- LangSmith: LangChain / LangGraph を使う場合は最も統合が深い、Fleet によるマネージド Agent デプロイ + Engine + Sandboxes で完全プラットフォーム化
- Arize Phoenix: OpenTelemetry ネイティブ、ML バックグラウンドのチームに馴染みやすい、実験管理が強い
- Opik: Apache-2.0 でバックエンド含む全機能をセルフホスト可能。Evals / プロンプト管理 / OpenTelemetry を備える。コスト分析 / Agent デプロイは公式 README で確認できず `-`
- LangSmith のセルフホストは Enterprise アドオン (Kubernetes、ライセンスキー要) のみのため、データプライバシー要件が厳しい場合は Langfuse / Phoenix / Opik が導入しやすい
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
