<!-- omit in toc -->

# Tool Comparison Matrix (MCP Server)

MCP Server の選定・比較の判断材料。

<!-- omit in toc -->

## History

| 日付       | 内容                                                                                                                                                     |
| ---------- | -------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 2026-07-09 | rtk (rtk-ai/rtk) と lean-ctx の Hook 層比較・併用非推奨理由を追記。mcp-rtk は成熟度不足のため現時点では未採用と明記                                      |
| 2026-06-28 | Performance カテゴリに mcp-rtk 追加。導入形態（Proxy/Hook 型 vs MCP Server 型）による効果発動条件の違いを整理。Headroom の利用形態別評価を追記           |
| 2026-06-17 | Headroom を Performance / Token Optimization カテゴリに追加                                                                                              |
| 2026-06-17 | 全般最新化: Terraform MCP v1.0.0 GA 反映、GitHub MCP v1.1.0 機能追加、codebase-memory-mcp LSP エンジン追加、lean-ctx WebSocket 対応、Context7 OAuth 対応 |
| 2026-06-02 | Web Fetch & Markdown Compression MCP Servers カテゴリ追加                                                                                                |
| 2026-05-27 | Local Filesystem & Git / Database & Data Stores / SaaS & Collaboration カテゴリ追加。Performance と Code Intelligence の重複解消。提供元表記を統一       |
| 2026-05-21 | History セクション追加                                                                                                                                   |
| 2026-05-17 | 初版作成。AWS / Terraform / Common / Performance / Code Intelligence / Knowledge MCP を比較                                                              |

<!-- omit in toc -->

## Table of Contents

- [AWS MCP Servers](#aws-mcp-servers)
  - [Guidelines](#guidelines)
- [Terraform MCP Servers](#terraform-mcp-servers)
  - [Guidelines](#guidelines-1)
- [Common / General Purpose MCP Servers](#common--general-purpose-mcp-servers)
  - [Guidelines](#guidelines-2)
- [Performance / Token Optimization MCP Servers](#performance--token-optimization-mcp-servers)
  - [Guidelines](#guidelines-3)
- [Code Intelligence MCP Servers](#code-intelligence-mcp-servers)
  - [Guidelines](#guidelines-4)
- [Knowledge / Search MCP Servers](#knowledge--search-mcp-servers)
  - [Guidelines](#guidelines-5)
- [Local Filesystem \& Git MCP Servers](#local-filesystem--git-mcp-servers)
  - [Guidelines](#guidelines-6)
- [Database MCP Servers](#database-mcp-servers)
  - [PostgreSQL MCP Servers](#postgresql-mcp-servers)
  - [SQLite MCP Servers](#sqlite-mcp-servers)
  - [Guidelines](#guidelines-7)
- [SaaS \& Collaboration MCP Servers](#saas--collaboration-mcp-servers)
  - [Guidelines](#guidelines-8)
- [Web Fetch \& Markdown Compression MCP Servers](#web-fetch--markdown-compression-mcp-servers)
  - [Guidelines](#guidelines-9)

## AWS MCP Servers

| 比較項目            | AWS MCP (マネージド)                    | AWS API MCP                                                               | AWS Knowledge MCP                       | AWS Documentation MCP                                                               | AWS Pricing MCP                                                               |
| ------------------- | --------------------------------------- | ------------------------------------------------------------------------- | --------------------------------------- | ----------------------------------------------------------------------------------- | ----------------------------------------------------------------------------- |
| 提供元              | AWS                                     | AWS Labs                                                                  | AWS                                     | AWS Labs                                                                            | AWS Labs                                                                      |
| リポジトリ          | -                                       | [GitHub](https://github.com/awslabs/mcp)                                  | -                                       | [GitHub](https://github.com/awslabs/mcp)                                            | [GitHub](https://github.com/awslabs/mcp)                                      |
| ドキュメント        | [Kiro Docs](https://kiro.dev/docs/mcp/) | [README](https://github.com/awslabs/mcp/tree/main/src/aws-api-mcp-server) | [Kiro Docs](https://kiro.dev/docs/mcp/) | [README](https://github.com/awslabs/mcp/tree/main/src/aws-documentation-mcp-server) | [README](https://github.com/awslabs/mcp/tree/main/src/aws-pricing-mcp-server) |
| ライセンス          | 商用 (AWS)                              | Apache-2.0                                                                | 商用 (AWS)                              | Apache-2.0                                                                          | Apache-2.0                                                                    |
| ホスティング        | リモート (AWS 管理)                     | ローカル                                                                  | リモート                                | ローカル                                                                            | ローカル                                                                      |
| Transport           | stdio (proxy 経由)                      | stdio                                                                     | stdio (proxy 経由)                      | stdio                                                                               | stdio                                                                         |
| インストール        | `uvx mcp-proxy-for-aws`                 | `uvx awslabs.aws-api-mcp-server`                                          | `uvx mcp-proxy`                         | `uvx awslabs.aws-documentation-mcp-server`                                          | `uvx awslabs.aws-pricing-mcp-server`                                          |
| 認証                | IAM (自動)                              | AWS CLI credentials                                                       | 不要                                    | 不要                                                                                | 不要                                                                          |
| ツール数            | 多数                                    | 少数                                                                      | 少数                                    | 少数                                                                                | 少数                                                                          |
| mcp-compressor 推奨 | ✅                                      | ❌                                                                        | ❌                                      | ❌                                                                                  | ❌                                                                            |
| 主な用途            | 全 AWS サービス API 操作 + ドキュメント | AWS CLI 経由のリソース操作                                                | 最新 AWS コンテンツ・コードサンプル     | 最新 AWS ドキュメント参照                                                           | デプロイ前コスト見積もり                                                      |
| CloudTrail 監査     | ✅                                      | ❌                                                                        | ❌                                      | ❌                                                                                  | ❌                                                                            |
| オフライン利用      | ❌                                      | ✅ (credentials 必要)                                                     | ❌                                      | ✅ (キャッシュ後)                                                                   | ✅ (キャッシュ後)                                                             |

### Guidelines

**→ AWS MCP (マネージド) + AWS Knowledge MCP を採用する。** AWS MCP は GA 済みで全サービスをカバーし CloudTrail 監査付き。Knowledge MCP は最新ドキュメント・コードサンプルの参照に有用。`mcp-compressor` で AWS MCP をラップしてトークン消費を抑える。

- AWS API MCP は AWS MCP と機能が重複するため不要。AWS MCP が使えない環境（オフライン等）でのみ検討。
- Documentation MCP / Pricing MCP は必要に応じて追加。Pricing MCP はコスト見積もりが頻繁な場合に有用。

## Terraform MCP Servers

| 比較項目            | AWS Labs Terraform MCP                                                    | HashiCorp Terraform MCP                                            |
| ------------------- | ------------------------------------------------------------------------- | ------------------------------------------------------------------ |
| 提供元              | AWS Labs                                                                  | HashiCorp                                                          |
| リポジトリ          | [GitHub](https://github.com/awslabs/mcp)                                  | [GitHub](https://github.com/hashicorp/terraform-mcp-server)        |
| ドキュメント        | [README](https://github.com/awslabs/mcp/tree/main/src/aws-iac-mcp-server) | [README](https://github.com/hashicorp/terraform-mcp-server#readme) |
| ライセンス          | Apache-2.0                                                                | MPL-2.0                                                            |
| インストール        | `uvx awslabs.terraform-mcp-server`                                        | `npx terraform-mcp-server`                                         |
| ランタイム          | Python (uvx)                                                              | Node.js (npx)                                                      |
| 主な用途            | Terraform ベストプラクティス・コード生成                                  | Registry からプロバイダースキーマ・ドキュメント取得                |
| プロバイダー情報    | ⚠️ (内蔵知識ベース)                                                       | ✅ (Registry 直接参照)                                             |
| HCP Terraform 連携  | ❌                                                                        | ✅                                                                 |
| Stacks 対応         | ❌                                                                        | ✅ (list_stacks / get_stack_details)                               |
| Plan/Apply 操作     | ❌                                                                        | ✅ (get_plan_json_output, get_apply_logs 等)                       |
| Policy Sets         | ❌                                                                        | ✅ (list/attach)                                                   |
| ツールセット選択    | ❌                                                                        | ✅ (`--toolsets` / `--tools` フラグ)                               |
| OpenTelemetry       | ❌                                                                        | ✅                                                                 |
| バージョン          | -                                                                         | v1.0.0 (GA)                                                        |
| ツール数            | 少数                                                                      | 多数                                                               |
| mcp-compressor 推奨 | ❌                                                                        | ⚠️ (ツール数増加のため検討)                                        |

### Guidelines

**→ HashiCorp Terraform MCP + AWS Labs Terraform MCP を両方採用する。** HashiCorp 版はプロバイダースキーマの正確な参照、AWS Labs 版は AWS ベストプラクティスの提供と役割が異なり補完関係にある。

- HashiCorp 版は Registry から最新スキーマを直接取得するため、リソース定義の正確性が高い。
- AWS Labs 版は AWS に特化した Terraform パターンを提供。AWS 以外の環境では HashiCorp 版のみで十分。

## Common / General Purpose MCP Servers

| 比較項目            | GitHub MCP                                                   | Context7                                      | Playwright MCP                                               | Fetch MCP                                                                            |
| ------------------- | ------------------------------------------------------------ | --------------------------------------------- | ------------------------------------------------------------ | ------------------------------------------------------------------------------------ |
| 提供元              | GitHub (Microsoft)                                           | Upstash                                       | Microsoft                                                    | Anthropic                                                                            |
| リポジトリ          | [GitHub](https://github.com/github/github-mcp-server)        | [GitHub](https://github.com/upstash/context7) | [GitHub](https://github.com/microsoft/playwright-mcp)        | [GitHub](https://github.com/modelcontextprotocol/servers)                            |
| ドキュメント        | [README](https://github.com/github/github-mcp-server#readme) | [context7.com](https://context7.com)          | [README](https://github.com/microsoft/playwright-mcp#readme) | [README](https://github.com/modelcontextprotocol/servers/tree/main/src/fetch#readme) |
| ライセンス          | MIT                                                          | MIT                                           | Apache-2.0                                                   | MIT                                                                                  |
| Transport           | HTTP (リモート)                                              | stdio                                         | stdio                                                        | stdio                                                                                |
| インストール        | URL 直接                                                     | `npx @upstash/context7-mcp`                   | `npx @playwright/mcp`                                        | `uvx mcp-server-fetch`                                                               |
| 主な用途            | GitHub 操作 (PR, Issue, Repo, commit 検索)                   | ライブラリドキュメント参照                    | ブラウザ操作・E2E テスト                                     | Web ページ取得                                                                       |
| ツール数            | 90+ (v1.1.0)                                                 | 少数                                          | 多数                                                         | 少数                                                                                 |
| mcp-compressor 推奨 | ✅ 強く推奨                                                  | ❌                                            | ✅                                                           | ❌                                                                                   |
| 認証                | Copilot 認証 (自動)                                          | 不要                                          | 不要                                                         | 不要                                                                                 |
| オフライン利用      | ❌                                                           | ❌                                            | ✅                                                           | ❌                                                                                   |

### Guidelines

**→ GitHub MCP + Context7 + Fetch を採用する。** GitHub MCP は PR/Issue 操作に必須（`mcp-compressor` でラップ）。Context7 は API キー不要で最新ライブラリドキュメントを取得。Fetch は特定 URL の参照に有用。

- Playwright MCP は E2E テストやブラウザ操作が必要なプロジェクトでのみ追加。常時有効にするとツール数が多くトークンを消費する。mcp-compressor は同時に 1 サーバーしかラップできないため、GitHub MCP に適用済みの場合は Playwright を同時に圧縮できない点に注意。

## Performance / Token Optimization MCP Servers

トークン消費削減に特化した比較。コード構造理解の詳細は [Code Intelligence MCP Servers](#code-intelligence-mcp-servers) を参照。

| 比較項目            | lean-ctx                                                 | mcp-rtk                                                                | Headroom                                          | mcp-compressor                                                    | codebase-memory-mcp                                              | jCodeMunch                                                                      |
| ------------------- | -------------------------------------------------------- | ---------------------------------------------------------------------- | ------------------------------------------------- | ----------------------------------------------------------------- | ---------------------------------------------------------------- | ------------------------------------------------------------------------------- |
| 提供元              | yvgude                                                   | ThomasTartrau (コミュニティ)                                           | chopratejas                                       | Atlassian Labs                                                    | DeusData                                                         | jgravelle                                                                       |
| リポジトリ          | [GitHub](https://github.com/yvgude/lean-ctx)             | [GitHub](https://github.com/ThomasTartrau/mcp-rtk)                     | [GitHub](https://github.com/chopratejas/headroom) | [GitHub](https://github.com/atlassian-labs/mcp-compressor)        | [GitHub](https://github.com/deusdata/codebase-memory-mcp)        | [GitHub](https://github.com/jgravelle/jcodemunch-mcp)                           |
| ドキュメント        | [README](https://github.com/yvgude/lean-ctx#readme)      | [README](https://github.com/ThomasTartrau/mcp-rtk#readme)              | [Docs](https://headroom-docs.vercel.app/docs)     | [README](https://github.com/atlassian-labs/mcp-compressor#readme) | [README](https://github.com/deusdata/codebase-memory-mcp#readme) | [jCodeMunch](https://jcodemunch.com)                                            |
| ライセンス          | Apache-2.0                                               | MIT                                                                    | Apache-2.0                                        | Apache-2.0                                                        | MIT                                                              | 商用 (個人無料)                                                                 |
| 言語                | Rust                                                     | Rust                                                                   | Python                                            | Python                                                            | C                                                                | Python                                                                          |
| インストール        | `lean-ctx mcp` / aqua                                    | `cargo install mcp-rtk`                                                | `pip install headroom-ai` / npm                   | `uvx mcp-compressor`                                              | バイナリ / aqua                                                  | `uvx --from git+https://github.com/jgravelle/jcodemunch-mcp.git jcodemunch-mcp` |
| 削減対象            | Shell 出力 + ファイル読み込み                            | MCP レスポンス JSON                                                    | ツール出力 + ログ + ファイル + RAG チャンク       | ツール定義 (JSON Schema)                                          | grep/read → 構造クエリ代替                                       | ファイル読み込み → シンボル取得                                                 |
| トークン削減率      | 60-99%                                                   | 60-90%                                                                 | 60-95%                                            | 70-97%                                                            | 99.2% (構造クエリ vs grep)                                       | 95%+ (コード読み込み)                                                           |
| 削減方式            | 56 パターンの正規表現圧縮 + キャッシュ (~13 tokens/file) | 8 段フィルターパイプライン (keep_fields/strip_nulls/condense_users 等) | 6 アルゴリズム (可逆圧縮 + Kompress-v2 モデル)    | LLM による JSON Schema 要約                                       | ナレッジグラフ構造クエリ                                         | MUNCH 圧縮フォーマット (45.5%バイト削減)                                        |
| セッションメモリ    | ✅ (CCP)                                                 | ❌                                                                     | ❌                                                | ❌                                                                | ❌                                                               | ✅ (session-aware routing)                                                      |
| 適用レイヤー        | Shell Hook + MCP Server                                  | プロキシ (他 MCP をラップ)                                             | Library + Proxy + MCP Server                      | プロキシ (他 MCP をラップ)                                        | MCP Server (単体)                                                | MCP Server (単体)                                                               |
| 効果発動方式        | 透過的 (Hook)                                            | 透過的 (Proxy)                                                         | 形態依存 (※後述)                                  | 透過的 (Proxy)                                                    | Agent 呼び出し依存                                               | Agent 呼び出し依存                                                              |
| ツール数            | 51+                                                      | 0 (プロキシ)                                                           | MCP: 少数 (圧縮 API)                              | 2-3 (プロキシ)                                                    | 14                                                               | 62 (full) / 16 (core)                                                           |
| mcp-compressor 推奨 | ✅                                                       | N/A                                                                    | ❌ (自己圧縮機能あり)                             | N/A                                                               | ❌ (14 ツール)                                                   | ⚠️ (core profile で自己圧縮可能)                                                |
| 依存関係            | なし (単一バイナリ)                                      | なし (単一バイナリ)                                                    | Python (pip/uv) または Node.js                    | Python (uv)                                                       | なし (単一バイナリ)                                              | Python (uv)                                                                     |
| 商用利用            | ✅ 無料                                                  | ✅ 無料                                                                | ✅ 無料 (Enterprise 別途)                         | ✅ 無料                                                           | ✅ 無料                                                          | 有料 (\$79〜)                                                                   |

### Hook 型 CLI Proxy: lean-ctx vs rtk (rtk-ai/rtk)

> **用語整理:** **rtk** ([rtk-ai/rtk](https://github.com/rtk-ai/rtk)) は PreToolUse Hook で Bash コマンドを透過的に書き換え、シェル出力を圧縮する CLI プロキシ。**mcp-rtk** ([ThomasTartrau/mcp-rtk](https://github.com/ThomasTartrau/mcp-rtk)) は MCP レスポンス JSON を圧縮するプロキシで、製品・レイヤーともに別物。

本リポジトリは `common-hooks-*` で lean-ctx の `hook rewrite` / `hook redirect` / `hook observe` を既に配布している。rtk の `rtk init -g --agent cursor` も同じ Hook 型・同じ Bash 出力圧縮の思想だが、**同一 PreToolUse 層への併用は非推奨**（後述 Guidelines 参照）。

| 比較項目 | lean-ctx (採用) | rtk (rtk-ai/rtk) |
| 提供元 | yvgude | rtk-ai |
| リポジトリ | [GitHub](https://github.com/yvgude/lean-ctx) | [GitHub](https://github.com/rtk-ai/rtk) |
| 適用レイヤー | Shell Hook + MCP Server | Shell Hook のみ |
| Cursor 統合 | `lean-ctx hook rewrite` 等 (APM) | `rtk init -g --agent cursor` |
| 削減方針 | 情報保全優先 (passthrough rules) | 積極的圧縮 (60-90%) |
| `git diff` 巨大出力 | 素通し (設計意図) | 高削減 (実測 99% 級) |
| 再読込キャッシュ | ✅ (~13 tokens/再読み込み) | ❌ |
| Read/Grep 置換 | ✅ (`hook redirect` + MCP) | ❌ (Bash のみ) |
| lean-ctx との併用 | — | **非推奨** (同一 Hook 層) |
| 本リポジトリ採用 | ✅ | ❌ |

参考: [rtk vs lean-ctx 実測比較 (Elcamy Tech Blog)](https://blog.elcamy.com/articles/token-killer-bench)

### Guidelines

**→ lean-ctx + mcp-compressor を採用する。** Shell Hook と MCP によるコンテキスト最適化に加え、ツール数の多い MCP サーバーの JSON Schema 要約を mcp-compressor で行う。

| レイヤー                           | ツール         | 役割                                                                                                                          |
| ---------------------------------- | -------------- | ----------------------------------------------------------------------------------------------------------------------------- |
| Shell Hook (出力圧縮 + キャッシュ) | lean-ctx       | コマンド出力・ファイル読み込みの正規表現圧縮、セッションメモリ (CCP)。`common-hooks-*` で rewrite / redirect / observe を配布 |
| Proxy (ツール定義圧縮)             | mcp-compressor | ツール数の多い MCP サーバー (GitHub MCP 90+ ツール等) の JSON Schema 要約                                                     |
| Proxy (レスポンス JSON 圧縮)       | mcp-rtk        | **現時点では未採用。** MCP レスポンス JSON のフィールドフィルタ。成熟度 (GitHub Stars 等) が不足のため保留                    |

**導入形態による効果発動条件の違い:**

| 導入形態      | 効果発動条件                                                   | 例                      |
| ------------- | -------------------------------------------------------------- | ----------------------- |
| Proxy 型      | 経路上に存在するだけで透過的に効く（Agent は存在を意識しない） | mcp-rtk, mcp-compressor |
| Hook 型       | フック設定があれば透過的に効く（Agent は存在を意識しない）     | lean-ctx                |
| MCP Server 型 | Agent が明示的にツールを呼び出した場合にのみ効く               | Headroom MCP            |

Proxy/Hook 型は Agent の能力に依存せず確実に効果を発揮する。MCP Server 型は Agent がツールを呼ぶ保証がないため、導入効果の確実性が低い。

- **rtk (rtk-ai/rtk) Hook と lean-ctx Hook の併用は非推奨。** 両者とも PreToolUse で Bash コマンドを透過的に書き換える同一レイヤーのツール。本リポジトリは `lean-ctx hook rewrite` / `hook redirect` / `hook observe` で既に同思想を実装済み。rtk を追加すると (1) Hook 実行順により `rtk lean-ctx git diff` のような二重ラップが起きうる、(2) lean-ctx の passthrough（情報保全）と rtk の積極圧縮がコマンドごとに競合し、**何が削られ何が残ったか監査できない**、(3) 失敗時の原本保存 (tee) の責任境界が曖昧になる。圧縮方針を一本化するため lean-ctx に集約する。
- **rtk 単体採用は lean-ctx 未導入環境向け。** 手軽な導入 (`rtk init -g`) と広いシェルコマンドカバレッジが強み。MCP・キャッシュ・redirect が不要な個人環境では rtk から始めてもよい。本リポジトリは APM で lean-ctx (MCP + hooks) を配布するため rtk は不要。
- **mcp-rtk は理論上 lean-ctx と補完関係だが、現時点では未採用。** lean-ctx は Shell 出力・ファイル読み込み、mcp-rtk は MCP レスポンス JSON を圧縮する別レイヤー。ただし GitHub Stars が極めて少なく（2026-06 時点で Star 1）、プリセットの充実度・運用実績が不足。GitHub MCP は mcp-compressor でラップ済みのため、当面は mcp-rtk の導入優先度は低い。成熟度が上がった段階で再評価する。
- **制約: mcp-compressor は同時に複数の MCP サーバーをラップできない。** プロキシとして公開するツール名が同一（`call_tool` 等）になるため、1 セッションにつき 1 サーバーのみラップ可能。
- **Headroom の利用形態による違い:** Headroom は Library / Proxy / MCP Server の 3 形態がある。Library（アプリケーション組み込み）や Proxy（LLM API の前段に配置）では透過的に効果を発揮するが、MCP Server 形態では Agent が `compress_text` 等を明示的に呼び出す必要がある。Proxy をサポートしない環境では MCP 形態でしか利用できず、効果が限定的となる。アプリケーション組み込みや LLM Proxy 構成が可能な場合に追加を検討。headroom はシェル層に rtk または lean-ctx のどちらか一方を内部利用する設計であり、Hook 層での rtk + lean-ctx 併用とは別問題。

- codebase-memory-mcp のトークン削減効果は構造クエリの副次的効果であり、主目的はコード理解。Code Intelligence カテゴリで採用。
- jCodeMunch は機能面で優れるが商用利用が有料（\$79〜）のため、OSS で統一する方針では不採用。

## Code Intelligence MCP Servers

コード構造理解・リファクタリング能力に特化した比較。トークン削減の観点は [Performance / Token Optimization MCP Servers](#performance--token-optimization-mcp-servers) を参照。

| 比較項目                      | codebase-memory-mcp                                              | jCodeMunch                                                                      | Serena                                                   |
| ----------------------------- | ---------------------------------------------------------------- | ------------------------------------------------------------------------------- | -------------------------------------------------------- |
| 提供元                        | DeusData                                                         | jgravelle                                                                       | Oraios                                                   |
| リポジトリ                    | [GitHub](https://github.com/deusdata/codebase-memory-mcp)        | [GitHub](https://github.com/jgravelle/jcodemunch-mcp)                           | [GitHub](https://github.com/oraios/serena)               |
| ドキュメント                  | [README](https://github.com/deusdata/codebase-memory-mcp#readme) | [jcodemunch.com](https://jcodemunch.com)                                        | [README](https://github.com/oraios/serena#readme)        |
| ライセンス                    | MIT                                                              | 商用 (個人無料)                                                                 | Apache-2.0                                               |
| 言語                          | C                                                                | Python                                                                          | Python                                                   |
| インストール                  | バイナリ / aqua                                                  | `uvx --from git+https://github.com/jgravelle/jcodemunch-mcp.git jcodemunch-mcp` | `uvx --from git+https://github.com/oraios/serena serena` |
| 主な用途                      | ナレッジグラフ構築・構造クエリ                                   | シンボルレベルのコード検索・取得                                                | IDE 的セマンティック検索・編集                           |
| コード構造理解                | ✅ (ナレッジグラフ)                                              | ✅ (シンボルインデックス)                                                       | ✅ (LSP 連携)                                            |
| 呼び出しグラフ                | ✅                                                               | ✅ (AST-derived)                                                                | ✅ (LSP references)                                      |
| デッドコード検出              | ✅                                                               | ✅ (`find_dead_code`)                                                           | ❌                                                       |
| 影響分析 (blast radius)       | ✅                                                               | ✅ (`get_blast_radius`)                                                         | ⚠️ (references 経由)                                     |
| シンボル検索                  | ✅ (regex + BM25)                                                | ✅ (BM25 + fuzzy + semantic)                                                    | ✅ (LSP symbols)                                         |
| クラス階層                    | ❌                                                               | ✅ (`get_class_hierarchy`)                                                      | ✅ (LSP type hierarchy)                                  |
| セマンティック編集            | ❌                                                               | ❌                                                                              | ✅ (シンボル単位の編集)                                  |
| PR リスク分析                 | ❌                                                               | ✅ (`get_pr_risk_profile`)                                                      | ❌                                                       |
| git diff → シンボルマッピング | ✅ (`detect_changes`)                                            | ✅ (`get_changed_symbols`)                                                      | ❌                                                       |
| LSP 連携                      | ❌                                                               | ❌                                                                              | ✅ (Language Server 必須)                                |
| セマンティック検索            | ✅ (BM25 + embeddings)                                           | ✅ (BM25 + opt-in embeddings)                                                   | ⚠️ (LSP 依存)                                            |
| LSP エンジン (ハイブリッド)   | ✅ (Java/Kotlin/Rust/C/C++/Python/TS/Go/C#/PHP 9 言語)           | ❌                                                                              | ✅ (LSP 連携)                                            |
| 対応言語数                    | 155 (tree-sitter) + 9 (LSP hybrid)                               | 70+                                                                             | LSP 対応言語                                             |
| インデックス速度              | 3 分 (Linux kernel, 4.8M ノード)                                 | 未公開 (tree-sitter)                                                            | LSP 起動時間に依存                                       |
| クエリ速度                    | <1ms                                                             | 未公開                                                                          | LSP 応答速度に依存                                       |
| 3D 可視化 UI                  | ✅ (オプション)                                                  | ❌                                                                              | ❌                                                       |
| 依存関係                      | なし (単一バイナリ)                                              | Python (uv)                                                                     | Python (uv) + Language Server                            |
| 商用利用                      | ✅ 無料                                                          | 有料 (\$79〜)                                                                   | ✅ 無料                                                  |

### Guidelines

**→ codebase-memory-mcp を採用する。** 無料・単一バイナリ・155 言語対応・ゼロ依存で導入が最も容易。ナレッジグラフによる構造クエリ（Cypher 対応）と 3D 可視化 UI も備える。

- Serena は LSP 連携によるセマンティック編集（リネーム等）が可能な唯一のサーバー。リファクタリング主体のワークフローでは追加を検討。ただし LSP の起動・設定が必要で導入コストが高い。
- jCodeMunch は機能最多だが商用有料。OSS で統一する方針では不採用。

## Knowledge / Search MCP Servers

| 比較項目         | Context7                                      | Brave Search MCP                                                  | Exa MCP                       | Fetch MCP                                                                            |
| ---------------- | --------------------------------------------- | ----------------------------------------------------------------- | ----------------------------- | ------------------------------------------------------------------------------------ |
| 提供元           | Upstash                                       | Brave                                                             | Exa                           | Anthropic                                                                            |
| リポジトリ       | [GitHub](https://github.com/upstash/context7) | [GitHub](https://github.com/brave/brave-search-mcp-server)        | -                             | [GitHub](https://github.com/modelcontextprotocol/servers)                            |
| ドキュメント     | [context7.com](https://context7.com)          | [README](https://github.com/brave/brave-search-mcp-server#readme) | [exa.ai](https://exa.ai/mcp)  | [README](https://github.com/modelcontextprotocol/servers/tree/main/src/fetch#readme) |
| ライセンス       | OSS                                           | MIT                                                               | 商用                          | MIT                                                                                  |
| Transport        | stdio                                         | stdio                                                             | HTTP (リモート)               | stdio                                                                                |
| インストール     | `npx @upstash/context7-mcp`                   | `npx -y @brave/brave-search-mcp-server`                           | URL: `https://mcp.exa.ai/mcp` | `uvx mcp-server-fetch`                                                               |
| 主な用途         | ライブラリドキュメント参照                    | Web 検索                                                          | セマンティック Web 検索       | Web ページ取得                                                                       |
| API キー必要     | ❌                                            | ✅ (Brave API)                                                    | ✅ (Exa API)                  | ❌                                                                                   |
| リアルタイム情報 | ✅ (最新ドキュメント)                         | ✅ (Web 検索)                                                     | ✅ (Web 検索)                 | ✅ (URL 指定)                                                                        |
| ローカル検索     | ❌                                            | ✅                                                                | ❌                            | ❌                                                                                   |
| プライバシー     | ✅                                            | ✅ (Brave)                                                        | ⚠️                            | ✅                                                                                   |
| ツール数         | 少数                                          | 少数                                                              | 少数                          | 少数                                                                                 |

### Guidelines

**→ Context7 + Fetch を採用する。** 両方とも API キー不要で導入が容易。Context7 はライブラリの最新ドキュメント取得、Fetch は特定 URL の内容取得に特化し、開発用途を十分にカバーする。

- Brave Search / Exa は API キーが必要。Web 検索が頻繁に必要な場合のみ追加を検討。
- Brave Search はプライバシー重視で無料枠あり。Exa はセマンティック検索に強いが有料。

## Local Filesystem & Git MCP Servers

開発ワークフローのベースラインとなるローカルファイル操作・Git 操作ツール。

| 比較項目            | Filesystem MCP                                                                               | Git MCP (公式)                                                                        | GitMCP (idosal)                                    |
| ------------------- | -------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------- | -------------------------------------------------- |
| 提供元              | Anthropic                                                                                    | Anthropic                                                                             | idosal (コミュニティ)                              |
| リポジトリ          | [GitHub](https://github.com/modelcontextprotocol/servers/tree/main/src/filesystem)           | [GitHub](https://github.com/modelcontextprotocol/servers/tree/main/src/git)           | [GitHub](https://github.com/idosal/git-mcp)        |
| ドキュメント        | [README](https://github.com/modelcontextprotocol/servers/blob/main/src/filesystem/README.md) | [README](https://github.com/modelcontextprotocol/servers/blob/main/src/git/README.md) | [README](https://github.com/idosal/git-mcp#readme) |
| ライセンス          | MIT                                                                                          | MIT                                                                                   | MIT                                                |
| Transport           | stdio                                                                                        | stdio                                                                                 | HTTP (リモート)                                    |
| インストール        | `npx @modelcontextprotocol/server-filesystem`                                                | `uvx mcp-server-git`                                                                  | URL 直接                                           |
| 主な用途            | ファイル読み書き・ディレクトリ操作                                                           | Git 操作 (diff, log, commit, branch)                                                  | リモートリポジトリのドキュメント参照               |
| ローカル操作        | ✅                                                                                           | ✅                                                                                    | ❌ (リモート専用)                                  |
| ファイル読み書き    | ✅                                                                                           | ❌                                                                                    | ❌                                                 |
| Git diff/log        | ❌                                                                                           | ✅                                                                                    | ❌                                                 |
| Git commit/branch   | ❌                                                                                           | ✅                                                                                    | ❌                                                 |
| サンドボックス      | ✅ (許可ディレクトリ制限)                                                                    | ⚠️ (リポジトリ単位)                                                                   | ✅ (読み取り専用)                                  |
| 認証                | 不要                                                                                         | 不要                                                                                  | 不要                                               |
| ツール数            | 少数                                                                                         | 少数                                                                                  | 少数                                               |
| mcp-compressor 推奨 | ❌                                                                                           | ❌                                                                                    | ❌                                                 |

### Guidelines

**→ Filesystem MCP + Git MCP を採用する。** 両方とも Anthropic 公式で安定性が高く、ローカル開発の基本操作をカバーする。多くの AI エージェント（Claude Code, Kiro 等）は同等機能を内蔵しているため、内蔵ツールがない環境でのみ追加が必要。

- GitMCP (idosal) はリモートリポジトリのドキュメント参照に特化。ローカル Git 操作には使えないため、用途が異なる。
- Claude Code / Kiro 等はファイル操作・Git 操作を内蔵しているため、これらの環境では明示的な追加は不要。

## Database MCP Servers

バックエンド開発・データ分析・デバッグ時に LLM が直接 DB スキーマ確認や SQL 発行を行うためのツール。DB 種別ごとに選択肢を整理する。

### PostgreSQL MCP Servers

| 比較項目             | Postgres MCP (公式)                                              | Postgres MCP Pro                                            |
| -------------------- | ---------------------------------------------------------------- | ----------------------------------------------------------- |
| 提供元               | Anthropic                                                        | Crystal DBA                                                 |
| リポジトリ           | [GitHub](https://github.com/modelcontextprotocol/servers)        | [GitHub](https://github.com/crystaldba/postgres-mcp)        |
| ドキュメント         | [README](https://github.com/modelcontextprotocol/servers#readme) | [README](https://github.com/crystaldba/postgres-mcp#readme) |
| ライセンス           | MIT                                                              | AGPL-3.0                                                    |
| インストール         | `npx @modelcontextprotocol/server-postgres`                      | `uvx postgres-mcp`                                          |
| 主な用途             | スキーマ参照・読み取りクエリ                                     | 読み書き + パフォーマンス分析                               |
| スキーマ参照         | ✅                                                               | ✅                                                          |
| SELECT 実行          | ✅                                                               | ✅                                                          |
| INSERT/UPDATE/DELETE | ❌ (読み取り専用)                                                | ✅ (設定可能)                                               |
| EXPLAIN / 実行計画   | ❌                                                               | ✅                                                          |
| インデックス提案     | ❌                                                               | ✅                                                          |
| 接続プール           | ❌                                                               | ✅                                                          |
| ツール数             | 少数                                                             | 多数                                                        |
| 商用利用             | ✅ 無料                                                          | ⚠️ (AGPL-3.0)                                               |

### SQLite MCP Servers

| 比較項目             | SQLite MCP (公式)                                                |
| -------------------- | ---------------------------------------------------------------- |
| 提供元               | Anthropic                                                        |
| リポジトリ           | [GitHub](https://github.com/modelcontextprotocol/servers)        |
| ドキュメント         | [README](https://github.com/modelcontextprotocol/servers#readme) |
| ライセンス           | MIT                                                              |
| インストール         | `uvx mcp-server-sqlite`                                          |
| 主な用途             | ローカル DB 操作・テストデータ管理                               |
| スキーマ参照         | ✅                                                               |
| SELECT 実行          | ✅                                                               |
| INSERT/UPDATE/DELETE | ✅                                                               |
| EXPLAIN / 実行計画   | ❌                                                               |
| インデックス提案     | ❌                                                               |
| 接続プール           | N/A                                                              |
| ツール数             | 少数                                                             |
| 商用利用             | ✅ 無料                                                          |

### Guidelines

**→ Postgres MCP (公式) を採用する。** MIT ライセンスで読み取り専用のため本番 DB への接続も安全。スキーマ確認と SELECT で開発・デバッグ用途を十分にカバーする。

- Postgres MCP Pro は EXPLAIN やインデックス提案が必要なパフォーマンスチューニング用途で検討。AGPL-3.0 ライセンスのため商用利用時は注意。
- SQLite MCP はローカル DB 操作・テストデータ投入に追加。
- 本番 DB への接続は読み取り専用ユーザーで行い、書き込み操作は開発環境に限定することを推奨。

## SaaS & Collaboration MCP Servers

エラー解析・タスク管理・チーム通知を連携し、開発周辺タスクを自動化するためのツール。

| 比較項目            | Sentry MCP                                                | Linear MCP (公式)                                        | Slack MCP (公式)                                                 |
| ------------------- | --------------------------------------------------------- | -------------------------------------------------------- | ---------------------------------------------------------------- |
| 提供元              | Sentry (getsentry)                                        | Linear                                                   | Anthropic                                                        |
| リポジトリ          | [GitHub](https://github.com/getsentry/sentry-mcp)         | -                                                        | [GitHub](https://github.com/modelcontextprotocol/servers)        |
| ドキュメント        | [Sentry Docs](https://docs.sentry.io/product/sentry-mcp/) | [Changelog](https://linear.app/changelog/2025-05-01-mcp) | [README](https://github.com/modelcontextprotocol/servers#readme) |
| ライセンス          | MIT                                                       | 商用 (Linear 提供)                                       | MIT                                                              |
| Transport           | HTTP (リモート)                                           | HTTP (リモート)                                          | stdio                                                            |
| インストール        | URL 直接 (OAuth)                                          | URL 直接 (OAuth)                                         | `npx @modelcontextprotocol/server-slack`                         |
| 主な用途            | エラー・Issue 解析・デバッグ支援                          | タスク管理 (Issue 作成・更新・検索)                      | チャンネル・メッセージ操作                                       |
| 認証                | OAuth (Sentry)                                            | OAuth (Linear)                                           | Bot Token (Slack API)                                            |
| リアルタイム情報    | ✅ (エラーイベント)                                       | ✅ (タスク状態)                                          | ✅ (メッセージ)                                                  |
| 読み取り            | ✅                                                        | ✅                                                       | ✅                                                               |
| 書き込み            | ⚠️ (Issue 操作)                                           | ✅ (Issue 作成・更新)                                    | ✅ (メッセージ送信)                                              |
| AI 分析機能         | ✅ (Seer 連携)                                            | ❌                                                       | ❌                                                               |
| ツール数            | 多数                                                      | 多数                                                     | 少数                                                             |
| mcp-compressor 推奨 | ⚠️                                                        | ⚠️                                                       | ❌                                                               |
| 無料利用            | ✅ (Sentry 無料枠内)                                      | ❌ (Linear 有料プラン必要)                               | ✅ (Slack 無料枠内)                                              |

### Guidelines

**→ Sentry MCP を採用する。** エラー解析とデバッグ支援に直結し、開発効率への貢献度が高い。OAuth 認証でリモートホスト型のため導入も容易。Seer（AI 分析）連携により根本原因の特定を支援。

- Linear MCP は Linear を利用しているチームでのみ有用。GitHub Issues で管理している場合は GitHub MCP で代替可能。
- Slack MCP はチーム通知の自動化に有用だが、誤送信リスクがあるため書き込み操作には注意が必要。必要に応じて追加。
- GitHub MCP と組み合わせることで「Sentry エラー解析 → GitHub Issue/PR 作成」のワークフローが実現可能。

## Web Fetch & Markdown Compression MCP Servers

WebFetch / Fetch MCP の出力に対して Markdown 圧縮やレスポンスフィルタリングを行うプロキシ・サーバーの比較。トークン効率の高い Web 取得を実現するためのレイヤー選択肢を整理する。

| 比較項目             | lean-ctx                                                 | Context Mode                                                            | mcp-rtk                                                                | Cloudflare MCP Portal                                                                                           | Markdownify MCP                                              | mcp-read-website-fast                                                |
| -------------------- | -------------------------------------------------------- | ----------------------------------------------------------------------- | ---------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------ | -------------------------------------------------------------------- |
| 提供元               | yvgude                                                   | mksglu (コミュニティ)                                                   | ThomasTartrau (コミュニティ)                                           | Cloudflare                                                                                                      | zcaceres (コミュニティ)                                      | just-every (コミュニティ)                                            |
| リポジトリ           | [GitHub](https://github.com/yvgude/lean-ctx)             | [GitHub](https://github.com/mksglu/context-mode)                        | [GitHub](https://github.com/ThomasTartrau/mcp-rtk)                     | -                                                                                                               | [GitHub](https://github.com/zcaceres/markdownify-mcp)        | [GitHub](https://github.com/just-every/mcp-read-website-fast)        |
| ドキュメント         | [README](https://github.com/yvgude/lean-ctx#readme)      | [README](https://github.com/mksglu/context-mode#readme)                 | [README](https://github.com/ThomasTartrau/mcp-rtk#readme)              | [Cloudflare Docs](https://developers.cloudflare.com/changelog/post/2026-03-26-mcp-portal-context-optimization/) | [README](https://github.com/zcaceres/markdownify-mcp#readme) | [README](https://github.com/just-every/mcp-read-website-fast#readme) |
| ライセンス           | Apache-2.0                                               | ELv2 (source-available)                                                 | MIT                                                                    | 商用 (Cloudflare)                                                                                               | MIT                                                          | MIT                                                                  |
| 言語                 | Rust                                                     | TypeScript (Node.js)                                                    | Rust                                                                   | N/A (SaaS)                                                                                                      | TypeScript (Bun/Node.js)                                     | TypeScript (Node.js)                                                 |
| インストール         | `lean-ctx mcp` / aqua                                    | `npm install -g context-mode`                                           | `cargo install mcp-rtk`                                                | URL パラメータ追加                                                                                              | `node dist/index.js`                                         | `npx @just-every/mcp-read-website-fast`                              |
| アーキテクチャ       | MCP Server + Shell Hook                                  | MCP Server + Hook (サンドボックス)                                      | プロキシ (他 MCP をラップ)                                             | リモートポータル (URL)                                                                                          | MCP Server (単体)                                            | MCP Server (単体)                                                    |
| 圧縮対象             | 全ツール出力 (Shell/Read/Fetch)                          | 全ツール出力 (Shell/Read/WebFetch)                                      | MCP レスポンス JSON                                                    | ツール定義 (スキーマ)                                                                                           | HTML → Markdown 変換                                         | HTML → Markdown 変換                                                 |
| トークン削減率       | 60-99% (圧縮) / ~13 tokens (キャッシュ再読み込み)        | 98% (56KB→299B)                                                         | 60-90% (JSON フィルタ)                                                 | 5x (minimize_tools) / 定数 (search_and_execute)                                                                 | 50-80% (HTML→MD)                                             | 50-80% (HTML→MD + Readability)                                       |
| 圧縮方式             | 95+パターンの正規表現圧縮 + TTL キャッシュ + Archive FTS | サンドボックス実行 + 結果のみ返却                                       | 8 段フィルターパイプライン (keep_fields/strip_nulls/condense_users 等) | ツール定義を query/execute 2 ツールに集約                                                                       | markitdown による変換                                        | Mozilla Readability + Turndown                                       |
| WebFetch 出力圧縮    | ✅ (fetch ツール内蔵 + Shell 圧縮)                       | ✅ (ctx_fetch_and_index)                                                | ✅ (レスポンス全般)                                                    | ❌ (ツール定義のみ)                                                                                             | ✅ (webpage-to-markdown)                                     | ✅ (read_website)                                                    |
| セッション継続       | ✅ (CCP: クロスセッションメモリ)                         | ✅ (SQLite FTS5 + PreCompact)                                           | ❌                                                                     | ❌                                                                                                              | ❌                                                           | ❌                                                                   |
| キャッシュ           | ✅ (TTL 付き、再読み込み ~13 tokens)                     | ✅ (TTL 付き FTS5)                                                      | ❌                                                                     | ❌                                                                                                              | ❌                                                           | ✅ (インメモリ)                                                      |
| 対応プラットフォーム | 15+ (Claude Code/Kiro/Cursor 等)                         | 15+ (Claude Code/Kiro/Cursor 等)                                        | 全 stdio MCP 対応                                                      | Cloudflare Access 経由のみ                                                                                      | 全 stdio MCP 対応                                            | 全 stdio MCP 対応                                                    |
| Hook 連携            | ✅ (PreToolUse/PostToolUse 等)                           | ✅ (PreToolUse/PostToolUse 等)                                          | ❌ (プロキシのみ)                                                      | ❌                                                                                                              | ❌                                                           | ❌                                                                   |
| 他 MCP ラップ可能    | ❌                                                       | ⚠️ (ctx_execute で間接実行)                                             | ✅ (コマンドラップ)                                                    | ✅ (ポータル経由)                                                                                               | ❌                                                           | ❌                                                                   |
| PDF/画像/音声対応    | ❌                                                       | ❌                                                                      | ❌                                                                     | ❌                                                                                                              | ✅ (PDF/画像 OCR/音声文字起こし)                             | ❌                                                                   |
| プリセット/自動検出  | ✅ (プラットフォーム自動検出)                            | ✅ (プラットフォーム自動検出)                                           | ✅ (GitLab/Grafana 等)                                                 | N/A                                                                                                             | ❌                                                           | ❌                                                                   |
| ツール数             | 51+                                                      | 11                                                                      | 0 (プロキシ)                                                           | 2 (query + execute)                                                                                             | 10                                                           | 1 (read_website)                                                     |
| 依存関係             | なし (単一バイナリ)                                      | Node.js >= 22.5 (or Bun) + Python/コンパイラ (サンドボックス言語実行時) | なし (単一バイナリ)                                                    | なし (SaaS)                                                                                                     | Node.js + Python (markitdown)                                | Node.js                                                              |
| 商用利用             | ✅ 無料                                                  | ⚠️ (ELv2: SaaS 提供不可)                                                | ✅ 無料                                                                | ✅ (Cloudflare 契約内)                                                                                          | ✅ 無料                                                      | ✅ 無料                                                              |
| GitHub Stars         | -                                                        | 16.2k                                                                   | 1                                                                      | N/A                                                                                                             | 2.4k                                                         | 150                                                                  |

### Guidelines

**→ lean-ctx を採用する (Performance カテゴリと兼用)。** fetch ツール内蔵 + Shell 圧縮パイプライン + TTL キャッシュ (~13 tokens/再読み込み) + CCP セッションメモリにより、Web Fetch 結果の圧縮・蓄積・検索を単体でカバーする。単一バイナリ・Apache-2.0・ゼロ依存で導入コストが最小。

- lean-ctx 導入済み環境では本カテゴリの他ツール追加の優先度は低い。mcp-rtk は MCP レスポンス JSON 圧縮として理論上は補完関係にあるが、成熟度不足のため現時点では未採用（詳細は [Performance / Token Optimization MCP Servers](#performance--token-optimization-mcp-servers) 参照）。
- Context Mode は lean-ctx と機能が重複するが、サンドボックス実行 (`ctx_fetch_and_index`) による 98% 圧縮が独自。ELv2 ライセンスのため SaaS 再配布不可だが開発ツールとしては無制限。15 プラットフォーム対応。

- Cloudflare MCP Portal はエンタープライズ向け。`optimize_context=search_and_execute` でツール定義コストを定数化できるが、Cloudflare Access 環境が前提。
- Markdownify MCP は PDF/画像/音声 →Markdown 変換が必要な場合に追加。Web 取得のみなら mcp-read-website-fast の方が軽量。
- mcp-read-website-fast は Readability による不要要素除去 + Turndown による Markdown 変換で、Fetch MCP の代替として単体利用可能。ツール数が 1 で軽量。
- mcp-compressor（Performance カテゴリで採用済み）はツール定義の圧縮であり、レスポンス圧縮とは補完関係にある。lean-ctx と併用推奨。
