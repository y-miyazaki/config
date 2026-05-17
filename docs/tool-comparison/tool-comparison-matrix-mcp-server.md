<!-- omit in toc -->
# Tool Comparison Matrix (MCP Server)

MCP Server の選定・比較の判断材料。

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

## AWS MCP Servers

| 比較項目           | AWS MCP (マネージド)                | AWS API MCP                      | AWS Knowledge MCP                 | AWS Documentation MCP                      | AWS Pricing MCP                      |
| ------------------ | ----------------------------------- | -------------------------------- | --------------------------------- | ------------------------------------------ | ------------------------------------ |
| 提供元             | AWS                                 | AWS Labs                         | AWS                               | AWS Labs                                   | AWS Labs                             |
| ライセンス         | 商用 (AWS)                          | Apache-2.0                       | 商用 (AWS)                        | Apache-2.0                                 | Apache-2.0                           |
| ホスティング       | リモート (AWS管理)                  | ローカル                         | リモート                          | ローカル                                   | ローカル                             |
| Transport          | stdio (proxy経由)                   | stdio                            | stdio (proxy経由)                 | stdio                                      | stdio                                |
| インストール       | `uvx mcp-proxy-for-aws`             | `uvx awslabs.aws-api-mcp-server` | `uvx mcp-proxy`                   | `uvx awslabs.aws-documentation-mcp-server` | `uvx awslabs.aws-pricing-mcp-server` |
| 認証               | IAM (自動)                          | AWS CLI credentials              | 不要                              | 不要                                       | 不要                                 |
| ツール数           | 多数                                | 少数                             | 少数                              | 少数                                       | 少数                                 |
| mcp-compressor推奨 | ✅                                   | ❌                                | ❌                                 | ❌                                          | ❌                                    |
| 主な用途           | 全AWSサービスAPI操作 + ドキュメント | AWS CLI経由のリソース操作        | 最新AWSコンテンツ・コードサンプル | 最新AWSドキュメント参照                    | デプロイ前コスト見積もり             |
| CloudTrail監査     | ✅                                   | ❌                                | ❌                                 | ❌                                          | ❌                                    |
| オフライン利用     | ❌                                   | ✅ (credentials必要)              | ❌                                 | ✅ (キャッシュ後)                           | ✅ (キャッシュ後)                     |

### Guidelines

**→ AWS MCP (マネージド) + AWS Knowledge MCP を採用する。** AWS MCP はGA済みで全サービスをカバーし CloudTrail 監査付き。Knowledge MCP は最新ドキュメント・コードサンプルの参照に有用。`mcp-compressor` で AWS MCP をラップしてトークン消費を抑える。

- AWS API MCP は AWS MCP と機能が重複するため不要。AWS MCP が使えない環境（オフライン等）でのみ検討。
- Documentation MCP / Pricing MCP は必要に応じて追加。Pricing MCP はコスト見積もりが頻繁な場合に有用。

## Terraform MCP Servers

| 比較項目           | HashiCorp Terraform MCP                             | AWS Labs Terraform MCP                   |
| ------------------ | --------------------------------------------------- | ---------------------------------------- |
| 提供元             | HashiCorp                                           | AWS Labs                                 |
| ライセンス         | MPL-2.0                                             | Apache-2.0                               |
| インストール       | `npx terraform-mcp-server`                          | `uvx awslabs.terraform-mcp-server`       |
| ランタイム         | Node.js (npx)                                       | Python (uvx)                             |
| 主な用途           | Registry からプロバイダースキーマ・ドキュメント取得 | Terraform ベストプラクティス・コード生成 |
| プロバイダー情報   | ✅ (Registry直接参照)                                | ⚠️ (内蔵知識ベース)                       |
| HCP Terraform連携  | ✅                                                   | ❌                                        |
| Stacks対応         | ✅                                                   | ❌                                        |
| ツール数           | 少数                                                | 少数                                     |
| mcp-compressor推奨 | ❌                                                   | ❌                                        |

### Guidelines

**→ HashiCorp Terraform MCP + AWS Labs Terraform MCP を両方採用する。** HashiCorp版はプロバイダースキーマの正確な参照、AWS Labs版はAWSベストプラクティスの提供と役割が異なり補完関係にある。

- HashiCorp版は Registry から最新スキーマを直接取得するため、リソース定義の正確性が高い。
- AWS Labs版は AWS に特化した Terraform パターンを提供。AWS以外の環境では HashiCorp版のみで十分。

## Common / General Purpose MCP Servers

| 比較項目           | GitHub MCP                   | Context7                    | Playwright MCP          | Fetch MCP              |
| ------------------ | ---------------------------- | --------------------------- | ----------------------- | ---------------------- |
| 提供元             | GitHub (Microsoft)           | Upstash                     | Microsoft               | MCP公式 (Anthropic)    |
| ライセンス         | MIT                          | MIT                         | Apache-2.0              | MIT                    |
| Transport          | HTTP (リモート)              | stdio                       | stdio                   | stdio                  |
| インストール       | URL直接                      | `npx @upstash/context7-mcp` | `npx @playwright/mcp`   | `uvx mcp-server-fetch` |
| 主な用途           | GitHub操作 (PR, Issue, Repo) | ライブラリドキュメント参照  | ブラウザ操作・E2Eテスト | Webページ取得          |
| ツール数           | 90+                          | 少数                        | 多数                    | 少数                   |
| mcp-compressor推奨 | ✅ 強く推奨                   | ❌                           | ✅                       | ❌                      |
| 認証               | Copilot認証 (自動)           | 不要                        | 不要                    | 不要                   |
| オフライン利用     | ❌                            | ❌                           | ✅                       | ❌                      |

### Guidelines

**→ GitHub MCP + Context7 + Fetch を採用する。** GitHub MCP はPR/Issue操作に必須（`mcp-compressor` でラップ）。Context7 はAPIキー不要で最新ライブラリドキュメントを取得。Fetch は特定URLの参照に有用。

- Playwright MCP はE2Eテストやブラウザ操作が必要なプロジェクトでのみ追加。常時有効にするとツール数が多くトークンを消費する。

## Performance / Token Optimization MCP Servers

| 比較項目           | lean-ctx                                                          |                          codebase-memory-mcp | jCodeMunch                             | mcp-compressor           |
| ------------------ | ----------------------------------------------------------------- | -------------------------------------------: | -------------------------------------- | ------------------------ |
| 提供元             | yvgude                                                            |                                     DeusData | jgravelle                              | Atlassian Labs           |
| ライセンス         | Apache-2.0                                                        |                                          MIT | 商用 (個人無料)                        | Apache-2.0               |
| 言語               | Rust                                                              |                                            C | Python                                 | Python                   |
| インストール       | `lean-ctx mcp` / aqua                                             |                              バイナリ / aqua | `uvx jcodemunch-mcp`                   | `uvx mcp-compressor`     |
| 主な用途           | Shell出力圧縮 + キャッシュ付きファイル読み込み + セッションメモリ | コードベースのナレッジグラフ構築・構造クエリ | シンボルレベルのコード検索・取得       | ツール定義の圧縮プロキシ |
| トークン削減率     | 60-99%                                                            |                   99.2% (構造クエリ vs grep) | 95%+ (コード読み込み)                  | 70-97% (ツール定義)      |
| ツール数           | 51                                                                |                                           14 | 62 (full) / 16 (core)                  | 2-3 (プロキシ)           |
| mcp-compressor推奨 | ✅                                                                 |                                 ❌ (14ツール) | ⚠️ (core profileで自己圧縮可能)         | N/A                      |
| 動作方式           | Shell Hook + MCP Server                                           |                      ナレッジグラフ (SQLite) | tree-sitter AST + シンボルインデックス | プロキシ (ラップ)        |
| セッションメモリ   | ✅ (CCP)                                                           |                                            ❌ | ✅ (session-aware routing)              | ❌                        |
| AST解析            | ✅ (21言語)                                                        |                                  ✅ (155言語) | ✅ (70+言語)                            | ❌                        |
| 呼び出しグラフ     | ❌                                                                 |                                            ✅ | ✅                                      | ❌                        |
| セマンティック検索 | ❌                                                                 |                        ✅ (BM25 + embeddings) | ✅ (BM25 + opt-in embeddings)           | ❌                        |
| 依存関係           | なし (単一バイナリ)                                               |                          なし (単一バイナリ) | Python (uv)                            | Python (uv)              |
| 商用利用           | ✅ 無料                                                            |                                       ✅ 無料 | 有料 ($79〜)                           | ✅ 無料                   |

### Guidelines

**→ lean-ctx + codebase-memory-mcp + mcp-compressor を採用する。** lean-ctx はシェル出力圧縮とキャッシュ読み込みで日常的なトークン消費を削減。codebase-memory-mcp は構造クエリで grep/read を代替。mcp-compressor はツール数の多いサーバー（GitHub, Playwright等）のプロキシとして適用。

- jCodeMunch は機能面で優れるが商用利用が有料（$79〜）のため、OSSで統一する方針では codebase-memory-mcp を優先。
- jCodeMunch の `tool_profile: core` (16ツール) は小規模モデルとの相性が良く、予算が許せば併用も有効。

## Code Intelligence MCP Servers

| 比較項目                      |  codebase-memory-mcp | jCodeMunch                  | Serena                        | lean-ctx           |
| ----------------------------- | -------------------: | --------------------------- | ----------------------------- | ------------------ |
| 提供元                        |             DeusData | jgravelle                   | Oraios                        | yvgude             |
| ライセンス                    |                  MIT | 商用 (個人無料)             | Apache-2.0                    | Apache-2.0         |
| 言語                          |                    C | Python                      | Python                        | Rust               |
| インストール                  |   バイナリ / aqua    | `uvx jcodemunch-mcp`        | `uvx --from git+https://github.com/oraios/serena serena` | `lean-ctx mcp` / aqua |
| 主な用途                      | ナレッジグラフ構築・構造クエリ | シンボルレベルのコード検索・取得 | IDE的セマンティック検索・編集 | Shell圧縮 + キャッシュ読み込み |
| コード構造理解                |   ✅ (ナレッジグラフ) | ✅ (シンボルインデックス)    | ✅ (LSP連携)                   | ⚠️ (ファイルレベル) |
| 呼び出しグラフ                |                    ✅ | ✅ (AST-derived)             | ✅ (LSP references)            | ❌                  |
| デッドコード検出              |                    ✅ | ✅ (`find_dead_code`)        | ❌                             | ❌                  |
| 影響分析 (blast radius)       |                    ✅ | ✅ (`get_blast_radius`)      | ⚠️ (references経由)            | ❌                  |
| シンボル検索                  |     ✅ (regex + BM25) | ✅ (BM25 + fuzzy + semantic) | ✅ (LSP symbols)               | ❌                  |
| クラス階層                    |                    ❌ | ✅ (`get_class_hierarchy`)   | ✅ (LSP type hierarchy)        | ❌                  |
| セマンティック編集            |                    ❌ | ❌                           | ✅ (シンボル単位の編集)        | ❌                  |
| PR リスク分析                 |                    ❌ | ✅ (`get_pr_risk_profile`)   | ❌                             | ❌                  |
| git diff → シンボルマッピング | ✅ (`detect_changes`) | ✅ (`get_changed_symbols`)   | ❌                             | ❌                  |
| ファイルキャッシュ読み込み    |                    ❌ | ❌                           | ❌                             | ✅ (~13 tokens)     |
| Shell出力圧縮                 |                    ❌ | ❌                           | ❌                             | ✅ (56パターン)     |
| MUNCH圧縮フォーマット         |                    ❌ | ✅ (45.5%バイト削減)         | ❌                             | ❌                  |
| LSP連携                       |                    ❌ | ❌                           | ✅ (Language Server必須)       | ⚠️ (opt-in)        |
| インデックス速度              |   3分 (Linux kernel) | 未公開 (tree-sitter)        | LSP起動時間に依存             | N/A                |
| クエリ速度                    |                 <1ms | 未公開                      | LSP応答速度に依存             | N/A                |
| 3D可視化UI                    |       ✅ (オプション) | ❌                           | ❌                             | ❌                  |
| Groq連携                      |                    ❌ | ✅ (リモートMCP)             | ❌                             | ❌                  |

### Guidelines

**→ codebase-memory-mcp を採用する。** 無料・単一バイナリ・155言語対応・ゼロ依存で導入が最も容易。ナレッジグラフによる構造クエリ（Cypher対応）と 3D 可視化UIも備える。

- Serena はLSP連携によるセマンティック編集（リネーム等）が可能な唯一のサーバー。リファクタリング主体のワークフローでは追加を検討。ただしLSPの起動・設定が必要で導入コストが高い。
- jCodeMunch は機能最多だが商用有料。OSSで統一する方針では不採用。
- lean-ctx はコード理解ではなくトークン最適化レイヤーのため、codebase-memory-mcp と併用する。

## Knowledge / Search MCP Servers

| 比較項目         | Context7                    | Brave Search MCP                  | Exa MCP                       | Fetch MCP              |
| ---------------- | --------------------------- | --------------------------------- | ----------------------------- | ---------------------- |
| 提供元           | Upstash                     | Brave                             | Exa                           | MCP公式                |
| ライセンス       | OSS                         | MIT                               | 商用                          | MIT                    |
| Transport        | stdio                       | stdio                             | HTTP (リモート)               | stdio                  |
| インストール     | `npx @upstash/context7-mcp` | `npx @anthropic/brave-search-mcp` | URL: `https://mcp.exa.ai/mcp` | `uvx mcp-server-fetch` |
| 主な用途         | ライブラリドキュメント参照  | Web検索                           | セマンティックWeb検索         | Webページ取得          |
| APIキー必要      | ❌                           | ✅ (Brave API)                     | ✅ (Exa API)                   | ❌                      |
| リアルタイム情報 | ✅ (最新ドキュメント)        | ✅ (Web検索)                       | ✅ (Web検索)                   | ✅ (URL指定)            |
| ローカル検索     | ❌                           | ✅                                 | ❌                             | ❌                      |
| プライバシー     | ✅                           | ✅ (Brave)                         | ⚠️                             | ✅                      |
| ツール数         | 少数                        | 少数                              | 少数                          | 少数                   |

### Guidelines

**→ Context7 + Fetch を採用する。** 両方ともAPIキー不要で導入が容易。Context7 はライブラリの最新ドキュメント取得、Fetch は特定URLの内容取得に特化し、開発用途を十分にカバーする。

- Brave Search / Exa はAPIキーが必要。Web検索が頻繁に必要な場合のみ追加を検討。
- Brave Search はプライバシー重視で無料枠あり。Exa はセマンティック検索に強いが有料。
