<!-- omit in toc -->
# Tool Comparison Matrix (MCP Server)

MCP Server の選定・比較の判断材料。

## History

| 日付       | 内容                                                                 |
| ---------- | -------------------------------------------------------------------- |
| 2026-06-02 | Web Fetch & Markdown Compression MCP Servers カテゴリ追加 |
| 2026-05-27 | Local Filesystem & Git / Database & Data Stores / SaaS & Collaboration カテゴリ追加。Performance と Code Intelligence の重複解消。提供元表記を統一 |
| 2026-05-21 | History セクション追加                                               |
| 2026-05-17 | 初版作成。AWS / Terraform / Common / Performance / Code Intelligence / Knowledge MCP を比較 |

<!-- omit in toc -->
## Table of Contents

- [History](#history)
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
- [Local Filesystem & Git MCP Servers](#local-filesystem--git-mcp-servers)
  - [Guidelines](#guidelines-6)
- [Database MCP Servers](#database-mcp-servers)
  - [Guidelines](#guidelines-7)
- [SaaS & Collaboration MCP Servers](#saas--collaboration-mcp-servers)
  - [Guidelines](#guidelines-8)
- [Web Fetch & Markdown Compression MCP Servers](#web-fetch--markdown-compression-mcp-servers)
  - [Guidelines](#guidelines-9)

## AWS MCP Servers

| 比較項目           | AWS MCP (マネージド)                | AWS API MCP                      | AWS Knowledge MCP                 | AWS Documentation MCP                      | AWS Pricing MCP                      |
| ------------------ | ----------------------------------- | -------------------------------- | --------------------------------- | ------------------------------------------ | ------------------------------------ |
| 提供元             | AWS                                 | AWS Labs                         | AWS                               | AWS Labs                                   | AWS Labs                             |
| リポジトリ         | -                                   | [GitHub](https://github.com/awslabs/mcp) | -                                 | [GitHub](https://github.com/awslabs/mcp) | [GitHub](https://github.com/awslabs/mcp) |
| ドキュメント       | [Kiro Docs](https://kiro.dev/docs/mcp/) | [README](https://github.com/awslabs/mcp/tree/main/src/aws-api-mcp-server) | [Kiro Docs](https://kiro.dev/docs/mcp/) | [README](https://github.com/awslabs/mcp/tree/main/src/aws-documentation-mcp-server) | [README](https://github.com/awslabs/mcp/tree/main/src/aws-pricing-mcp-server) |
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
| リポジトリ         | [GitHub](https://github.com/hashicorp/terraform-mcp-server) | [GitHub](https://github.com/awslabs/mcp) |
| ドキュメント       | [README](https://github.com/hashicorp/terraform-mcp-server#readme) | [README](https://github.com/awslabs/mcp/tree/main/src/aws-iac-mcp-server) |
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
| 提供元             | GitHub (Microsoft)           | Upstash                     | Microsoft               | Anthropic              |
| リポジトリ         | [GitHub](https://github.com/github/github-mcp-server) | [GitHub](https://github.com/upstash/context7) | [GitHub](https://github.com/microsoft/playwright-mcp) | [GitHub](https://github.com/modelcontextprotocol/servers) |
| ドキュメント       | [README](https://github.com/github/github-mcp-server#readme) | [context7.com](https://context7.com) | [README](https://github.com/microsoft/playwright-mcp#readme) | [README](https://github.com/modelcontextprotocol/servers/tree/main/src/fetch#readme) |
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

トークン消費削減に特化した比較。コード構造理解の詳細は [Code Intelligence MCP Servers](#code-intelligence-mcp-servers) を参照。

| 比較項目             | lean-ctx                          | mcp-compressor                    | codebase-memory-mcp               | jCodeMunch                        |
| -------------------- | --------------------------------- | --------------------------------- | --------------------------------- | --------------------------------- |
| 提供元               | yvgude                            | Atlassian Labs                    | DeusData                          | jgravelle                         |
| リポジトリ           | [GitHub](https://github.com/yvgude/lean-ctx) | [GitHub](https://github.com/atlassian-labs/mcp-compressor) | [GitHub](https://github.com/deusdata/codebase-memory-mcp) | [GitHub](https://github.com/jgravelle/jcodemunch-mcp) |
| ドキュメント         | [README](https://github.com/yvgude/lean-ctx#readme) | [README](https://github.com/atlassian-labs/mcp-compressor#readme) | [README](https://github.com/deusdata/codebase-memory-mcp#readme) | [jCodeMunch](https://jcodemunch.com) |
| ライセンス           | Apache-2.0                        | Apache-2.0                        | MIT                               | 商用 (個人無料)                   |
| 言語                 | Rust                              | Python                            | C                                 | Python                            |
| インストール         | `lean-ctx mcp` / aqua             | `uvx mcp-compressor`              | バイナリ / aqua                   | `uvx --from git+https://github.com/jgravelle/jcodemunch-mcp.git jcodemunch-mcp` |
| 削減対象             | Shell出力 + ファイル読み込み      | ツール定義 (JSON Schema)          | grep/read → 構造クエリ代替        | ファイル読み込み → シンボル取得   |
| トークン削減率       | 60-99%                            | 70-97%                            | 99.2% (構造クエリ vs grep)        | 95%+ (コード読み込み)             |
| 削減方式             | 56パターンの正規表現圧縮 + キャッシュ (~13 tokens/file) | LLMによるJSON Schema要約          | ナレッジグラフ構造クエリ          | MUNCH圧縮フォーマット (45.5%バイト削減) |
| セッションメモリ     | ✅ (CCP)                           | ❌                                 | ❌                                 | ✅ (session-aware routing)         |
| 適用レイヤー         | Shell Hook + MCP Server           | プロキシ (他MCPをラップ)          | MCP Server (単体)                 | MCP Server (単体)                 |
| ツール数             | 51                                | 2-3 (プロキシ)                    | 14                                | 62 (full) / 16 (core)            |
| mcp-compressor推奨   | ✅                                 | N/A                               | ❌ (14ツール)                      | ⚠️ (core profileで自己圧縮可能)   |
| 依存関係             | なし (単一バイナリ)               | Python (uv)                       | なし (単一バイナリ)               | Python (uv)                       |
| 商用利用             | ✅ 無料                            | ✅ 無料                            | ✅ 無料                            | 有料 ($79〜)                      |

### Guidelines

**→ lean-ctx + mcp-compressor を採用する。** lean-ctx はシェル出力圧縮とキャッシュ読み込みで日常的なトークン消費を削減。mcp-compressor はツール数の多いサーバー（GitHub MCP 90+ツール、Playwright等）のプロキシとして適用。

- codebase-memory-mcp のトークン削減効果は構造クエリの副次的効果であり、主目的はコード理解。Code Intelligence カテゴリで採用。
- jCodeMunch は機能面で優れるが商用利用が有料（$79〜）のため、OSSで統一する方針では不採用。

## Code Intelligence MCP Servers

コード構造理解・リファクタリング能力に特化した比較。トークン削減の観点は [Performance / Token Optimization MCP Servers](#performance--token-optimization-mcp-servers) を参照。

| 比較項目                      | codebase-memory-mcp              | jCodeMunch                       | Serena                           |
| ----------------------------- | -------------------------------- | -------------------------------- | -------------------------------- |
| 提供元                        | DeusData                         | jgravelle                        | Oraios                           |
| リポジトリ                    | [GitHub](https://github.com/deusdata/codebase-memory-mcp) | [GitHub](https://github.com/jgravelle/jcodemunch-mcp) | [GitHub](https://github.com/oraios/serena) |
| ドキュメント                  | [README](https://github.com/deusdata/codebase-memory-mcp#readme) | [jcodemunch.com](https://jcodemunch.com) | [README](https://github.com/oraios/serena#readme) |
| ライセンス                    | MIT                              | 商用 (個人無料)                  | Apache-2.0                       |
| 言語                          | C                                | Python                           | Python                           |
| インストール                  | バイナリ / aqua                  | `uvx --from git+https://github.com/jgravelle/jcodemunch-mcp.git jcodemunch-mcp` | `uvx --from git+https://github.com/oraios/serena serena` |
| 主な用途                      | ナレッジグラフ構築・構造クエリ   | シンボルレベルのコード検索・取得 | IDE的セマンティック検索・編集    |
| コード構造理解                | ✅ (ナレッジグラフ)               | ✅ (シンボルインデックス)         | ✅ (LSP連携)                      |
| 呼び出しグラフ                | ✅                                | ✅ (AST-derived)                  | ✅ (LSP references)               |
| デッドコード検出              | ✅                                | ✅ (`find_dead_code`)             | ❌                                |
| 影響分析 (blast radius)       | ✅                                | ✅ (`get_blast_radius`)           | ⚠️ (references経由)               |
| シンボル検索                  | ✅ (regex + BM25)                 | ✅ (BM25 + fuzzy + semantic)      | ✅ (LSP symbols)                  |
| クラス階層                    | ❌                                | ✅ (`get_class_hierarchy`)        | ✅ (LSP type hierarchy)           |
| セマンティック編集            | ❌                                | ❌                                | ✅ (シンボル単位の編集)           |
| PR リスク分析                 | ❌                                | ✅ (`get_pr_risk_profile`)        | ❌                                |
| git diff → シンボルマッピング | ✅ (`detect_changes`)             | ✅ (`get_changed_symbols`)        | ❌                                |
| LSP連携                       | ❌                                | ❌                                | ✅ (Language Server必須)          |
| セマンティック検索            | ✅ (BM25 + embeddings)            | ✅ (BM25 + opt-in embeddings)     | ⚠️ (LSP依存)                      |
| 対応言語数                    | 155                              | 70+                              | LSP対応言語                      |
| インデックス速度              | 3分 (Linux kernel)               | 未公開 (tree-sitter)             | LSP起動時間に依存                |
| クエリ速度                    | <1ms                             | 未公開                           | LSP応答速度に依存                |
| 3D可視化UI                    | ✅ (オプション)                   | ❌                                | ❌                                |
| 依存関係                      | なし (単一バイナリ)              | Python (uv)                      | Python (uv) + Language Server    |
| 商用利用                      | ✅ 無料                           | 有料 ($79〜)                     | ✅ 無料                           |

### Guidelines

**→ codebase-memory-mcp を採用する。** 無料・単一バイナリ・155言語対応・ゼロ依存で導入が最も容易。ナレッジグラフによる構造クエリ（Cypher対応）と 3D 可視化UIも備える。

- Serena はLSP連携によるセマンティック編集（リネーム等）が可能な唯一のサーバー。リファクタリング主体のワークフローでは追加を検討。ただしLSPの起動・設定が必要で導入コストが高い。
- jCodeMunch は機能最多だが商用有料。OSSで統一する方針では不採用。

## Knowledge / Search MCP Servers

| 比較項目         | Context7                    | Brave Search MCP                  | Exa MCP                       | Fetch MCP              |
| ---------------- | --------------------------- | --------------------------------- | ----------------------------- | ---------------------- |
| 提供元           | Upstash                     | Brave                             | Exa                           | Anthropic              |
| リポジトリ       | [GitHub](https://github.com/upstash/context7) | [GitHub](https://github.com/brave/brave-search-mcp-server) | -                             | [GitHub](https://github.com/modelcontextprotocol/servers) |
| ドキュメント     | [context7.com](https://context7.com) | [README](https://github.com/brave/brave-search-mcp-server#readme) | [exa.ai](https://exa.ai/mcp) | [README](https://github.com/modelcontextprotocol/servers/tree/main/src/fetch#readme) |
| ライセンス       | OSS                         | MIT                               | 商用                          | MIT                    |
| Transport        | stdio                       | stdio                             | HTTP (リモート)               | stdio                  |
| インストール     | `npx @upstash/context7-mcp` | `npx -y @brave/brave-search-mcp-server` | URL: `https://mcp.exa.ai/mcp` | `uvx mcp-server-fetch` |
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

## Local Filesystem & Git MCP Servers

開発ワークフローのベースラインとなるローカルファイル操作・Git操作ツール。

| 比較項目           | Filesystem MCP                    | Git MCP (公式)                    | GitMCP (idosal)                   |
| ------------------ | --------------------------------- | --------------------------------- | --------------------------------- |
| 提供元             | Anthropic                         | Anthropic                         | idosal (コミュニティ)             |
| リポジトリ         | [GitHub](https://github.com/modelcontextprotocol/servers/tree/main/src/filesystem) | [GitHub](https://github.com/modelcontextprotocol/servers/tree/main/src/git) | [GitHub](https://github.com/idosal/git-mcp) |
| ドキュメント       | [README](https://github.com/modelcontextprotocol/servers/blob/main/src/filesystem/README.md) | [README](https://github.com/modelcontextprotocol/servers/blob/main/src/git/README.md) | [README](https://github.com/idosal/git-mcp#readme) |
| ライセンス         | MIT                               | MIT                               | MIT                               |
| Transport          | stdio                             | stdio                             | HTTP (リモート)                   |
| インストール       | `npx @modelcontextprotocol/server-filesystem` | `uvx mcp-server-git`             | URL直接                           |
| 主な用途           | ファイル読み書き・ディレクトリ操作 | Git操作 (diff, log, commit, branch) | リモートリポジトリのドキュメント参照 |
| ローカル操作       | ✅                                 | ✅                                 | ❌ (リモート専用)                  |
| ファイル読み書き   | ✅                                 | ❌                                 | ❌                                 |
| Git diff/log       | ❌                                 | ✅                                 | ❌                                 |
| Git commit/branch  | ❌                                 | ✅                                 | ❌                                 |
| サンドボックス     | ✅ (許可ディレクトリ制限)          | ⚠️ (リポジトリ単位)               | ✅ (読み取り専用)                  |
| 認証               | 不要                              | 不要                              | 不要                              |
| ツール数           | 少数                              | 少数                              | 少数                              |
| mcp-compressor推奨 | ❌                                 | ❌                                 | ❌                                 |

### Guidelines

**→ Filesystem MCP + Git MCP を採用する。** 両方とも Anthropic 公式で安定性が高く、ローカル開発の基本操作をカバーする。多くのAIエージェント（Claude Code, Kiro等）は同等機能を内蔵しているため、内蔵ツールがない環境でのみ追加が必要。

- GitMCP (idosal) はリモートリポジトリのドキュメント参照に特化。ローカルGit操作には使えないため、用途が異なる。
- Claude Code / Kiro 等はファイル操作・Git操作を内蔵しているため、これらの環境では明示的な追加は不要。

## Database MCP Servers

バックエンド開発・データ分析・デバッグ時にLLMが直接DBスキーマ確認やSQL発行を行うためのツール。DB種別ごとに選択肢を整理する。

### PostgreSQL MCP Servers

| 比較項目           | Postgres MCP (公式)               | Postgres MCP Pro                  |
| ------------------ | --------------------------------- | --------------------------------- |
| 提供元             | Anthropic                         | Crystal DBA                       |
| リポジトリ         | [GitHub](https://github.com/modelcontextprotocol/servers) | [GitHub](https://github.com/crystaldba/postgres-mcp) |
| ドキュメント       | [README](https://github.com/modelcontextprotocol/servers#readme) | [README](https://github.com/crystaldba/postgres-mcp#readme) |
| ライセンス         | MIT                               | AGPL-3.0                          |
| インストール       | `npx @modelcontextprotocol/server-postgres` | `uvx postgres-mcp`               |
| 主な用途           | スキーマ参照・読み取りクエリ      | 読み書き + パフォーマンス分析     |
| スキーマ参照       | ✅                                 | ✅                                 |
| SELECT実行         | ✅                                 | ✅                                 |
| INSERT/UPDATE/DELETE | ❌ (読み取り専用)                  | ✅ (設定可能)                      |
| EXPLAIN / 実行計画 | ❌                                 | ✅                                 |
| インデックス提案   | ❌                                 | ✅                                 |
| 接続プール         | ❌                                 | ✅                                 |
| ツール数           | 少数                              | 多数                              |
| 商用利用           | ✅ 無料                            | ⚠️ (AGPL-3.0)                     |

### SQLite MCP Servers

| 比較項目           | SQLite MCP (公式)                 |
| ------------------ | --------------------------------- |
| 提供元             | Anthropic                         |
| リポジトリ         | [GitHub](https://github.com/modelcontextprotocol/servers) |
| ドキュメント       | [README](https://github.com/modelcontextprotocol/servers#readme) |
| ライセンス         | MIT                               |
| インストール       | `uvx mcp-server-sqlite`           |
| 主な用途           | ローカルDB操作・テストデータ管理  |
| スキーマ参照       | ✅                                 |
| SELECT実行         | ✅                                 |
| INSERT/UPDATE/DELETE | ✅                                 |
| EXPLAIN / 実行計画 | ❌                                 |
| インデックス提案   | ❌                                 |
| 接続プール         | N/A                               |
| ツール数           | 少数                              |
| 商用利用           | ✅ 無料                            |

### Guidelines

**→ Postgres MCP (公式) を採用する。** MIT ライセンスで読み取り専用のため本番DBへの接続も安全。スキーマ確認とSELECTで開発・デバッグ用途を十分にカバーする。

- Postgres MCP Pro は EXPLAIN やインデックス提案が必要なパフォーマンスチューニング用途で検討。AGPL-3.0 ライセンスのため商用利用時は注意。
- SQLite MCP はローカルDB操作・テストデータ投入に追加。
- 本番DBへの接続は読み取り専用ユーザーで行い、書き込み操作は開発環境に限定することを推奨。

## SaaS & Collaboration MCP Servers

エラー解析・タスク管理・チーム通知を連携し、開発周辺タスクを自動化するためのツール。

| 比較項目           | Sentry MCP                        | Linear MCP (公式)                 | Slack MCP (公式)                  |
| ------------------ | --------------------------------- | --------------------------------- | --------------------------------- |
| 提供元             | Sentry (getsentry)                | Linear                            | Anthropic                         |
| リポジトリ         | [GitHub](https://github.com/getsentry/sentry-mcp) | -                                 | [GitHub](https://github.com/modelcontextprotocol/servers) |
| ドキュメント       | [Sentry Docs](https://docs.sentry.io/product/sentry-mcp/) | [Changelog](https://linear.app/changelog/2025-05-01-mcp) | [README](https://github.com/modelcontextprotocol/servers#readme) |
| ライセンス         | MIT                               | 商用 (Linear提供)                 | MIT                               |
| Transport          | HTTP (リモート)                   | HTTP (リモート)                   | stdio                             |
| インストール       | URL直接 (OAuth)                   | URL直接 (OAuth)                   | `npx @modelcontextprotocol/server-slack` |
| 主な用途           | エラー・Issue解析・デバッグ支援   | タスク管理 (Issue作成・更新・検索) | チャンネル・メッセージ操作        |
| 認証               | OAuth (Sentry)                    | OAuth (Linear)                    | Bot Token (Slack API)             |
| リアルタイム情報   | ✅ (エラーイベント)                | ✅ (タスク状態)                    | ✅ (メッセージ)                    |
| 読み取り           | ✅                                 | ✅                                 | ✅                                 |
| 書き込み           | ⚠️ (Issue操作)                     | ✅ (Issue作成・更新)               | ✅ (メッセージ送信)                |
| AI分析機能         | ✅ (Seer連携)                      | ❌                                 | ❌                                 |
| ツール数           | 多数                              | 多数                              | 少数                              |
| mcp-compressor推奨 | ⚠️                                | ⚠️                                | ❌                                 |
| 無料利用           | ✅ (Sentry無料枠内)               | ❌ (Linear有料プラン必要)          | ✅ (Slack無料枠内)                 |

### Guidelines

**→ Sentry MCP を採用する。** エラー解析とデバッグ支援に直結し、開発効率への貢献度が高い。OAuth認証でリモートホスト型のため導入も容易。Seer（AI分析）連携により根本原因の特定を支援。

- Linear MCP はLinearを利用しているチームでのみ有用。GitHub Issues で管理している場合は GitHub MCP で代替可能。
- Slack MCP はチーム通知の自動化に有用だが、誤送信リスクがあるため書き込み操作には注意が必要。必要に応じて追加。
- GitHub MCP と組み合わせることで「Sentryエラー解析 → GitHub Issue/PR作成」のワークフローが実現可能。

## Web Fetch & Markdown Compression MCP Servers

WebFetch / Fetch MCP の出力に対してMarkdown圧縮やレスポンスフィルタリングを行うプロキシ・サーバーの比較。トークン効率の高いWeb取得を実現するためのレイヤー選択肢を整理する。

| 比較項目                | Context Mode                      | mcp-rtk                           | Cloudflare MCP Portal             | Markdownify MCP                   | mcp-read-website-fast             |
| ----------------------- | --------------------------------- | --------------------------------- | --------------------------------- | --------------------------------- | --------------------------------- |
| 提供元                  | mksglu (コミュニティ)             | ThomasTartrau (コミュニティ)      | Cloudflare                        | zcaceres (コミュニティ)           | just-every (コミュニティ)         |
| リポジトリ              | [GitHub](https://github.com/mksglu/context-mode) | [GitHub](https://github.com/ThomasTartrau/mcp-rtk) | -                                 | [GitHub](https://github.com/zcaceres/markdownify-mcp) | [GitHub](https://github.com/just-every/mcp-read-website-fast) |
| ドキュメント            | [README](https://github.com/mksglu/context-mode#readme) | [README](https://github.com/ThomasTartrau/mcp-rtk#readme) | [Cloudflare Docs](https://developers.cloudflare.com/changelog/post/2026-03-26-mcp-portal-context-optimization/) | [README](https://github.com/zcaceres/markdownify-mcp#readme) | [README](https://github.com/just-every/mcp-read-website-fast#readme) |
| ライセンス              | ELv2 (source-available)           | MIT                               | 商用 (Cloudflare)                 | MIT                               | MIT                               |
| 言語                    | TypeScript (Node.js)              | Rust                              | N/A (SaaS)                        | TypeScript (Bun/Node.js)          | TypeScript (Node.js)              |
| インストール            | `npm install -g context-mode`     | `cargo install mcp-rtk`           | URL パラメータ追加                | `node dist/index.js`              | `npx @just-every/mcp-read-website-fast` |
| アーキテクチャ          | MCP Server + Hook (サンドボックス) | プロキシ (他MCPをラップ)          | リモートポータル (URL)            | MCP Server (単体)                 | MCP Server (単体)                 |
| 圧縮対象                | 全ツール出力 (Shell/Read/WebFetch) | MCP レスポンス JSON               | ツール定義 (スキーマ)             | HTML → Markdown 変換              | HTML → Markdown 変換              |
| トークン削減率          | 98% (56KB→299B)                   | 60-90% (JSONフィルタ)             | 5x (minimize_tools) / 定数 (search_and_execute) | 50-80% (HTML→MD)                  | 50-80% (HTML→MD + Readability)    |
| 圧縮方式               | サンドボックス実行 + 結果のみ返却 | 8段フィルターパイプライン (keep_fields/strip_nulls/condense_users等) | ツール定義をquery/execute 2ツールに集約 | markitdown による変換             | Mozilla Readability + Turndown    |
| WebFetch出力圧縮        | ✅ (ctx_fetch_and_index)           | ✅ (レスポンス全般)                | ❌ (ツール定義のみ)                | ✅ (webpage-to-markdown)           | ✅ (read_website)                  |
| セッション継続          | ✅ (SQLite FTS5 + PreCompact)      | ❌                                 | ❌                                 | ❌                                 | ❌                                 |
| キャッシュ              | ✅ (TTL付きFTS5)                   | ❌                                 | ❌                                 | ❌                                 | ✅ (インメモリ)                    |
| 対応プラットフォーム    | 15+ (Claude Code/Kiro/Cursor等)   | 全stdio MCP対応                   | Cloudflare Access経由のみ         | 全stdio MCP対応                   | 全stdio MCP対応                   |
| Hook連携                | ✅ (PreToolUse/PostToolUse等)      | ❌ (プロキシのみ)                  | ❌                                 | ❌                                 | ❌                                 |
| 他MCPラップ可能         | ⚠️ (ctx_executeで間接実行)         | ✅ (コマンドラップ)                | ✅ (ポータル経由)                  | ❌                                 | ❌                                 |
| PDF/画像/音声対応       | ❌                                 | ❌                                 | ❌                                 | ✅ (PDF/画像OCR/音声文字起こし)    | ❌                                 |
| プリセット/自動検出     | ✅ (プラットフォーム自動検出)      | ✅ (GitLab/Grafana等)             | N/A                               | ❌                                 | ❌                                 |
| ツール数               | 11                                | 0 (プロキシ)                      | 2 (query + execute)               | 10                                | 1 (read_website)                  |
| 依存関係               | Node.js >= 22.5 (or Bun) + Python/コンパイラ (サンドボックス言語実行時) | なし (単一バイナリ)               | なし (SaaS)                       | Node.js + Python (markitdown)     | Node.js                           |
| 商用利用               | ⚠️ (ELv2: SaaS提供不可)           | ✅ 無料                            | ✅ (Cloudflare契約内)              | ✅ 無料                            | ✅ 無料                            |
| GitHub Stars           | 16.2k                             | 1                                 | N/A                               | 2.4k                              | 150                               |

### Guidelines

**→ Context Mode + mcp-rtk を用途に応じて使い分ける。** Context Mode はWebFetch出力のサンドボックス化（`ctx_fetch_and_index`でURL取得→FTS5インデックス→検索）とセッション継続に最適。mcp-rtk は既存MCPサーバーのJSONレスポンスをフィルタリングするプロキシとして、特にGitLab/GitHub等のAPI応答が大きいサーバーに有効。

- Context Mode は ELv2 ライセンスのため SaaS としての再配布は不可だが、開発ツールとしての利用は無制限。15プラットフォーム対応・Hook連携・セッション継続の機能性が圧倒的。
- mcp-rtk は MIT ライセンス・Rust 単一バイナリでゼロ依存。コマンドを `mcp-rtk --` でラップするだけで導入可能。ただし新規プロジェクト（Star 1）のためプリセットの充実度に注意。
- Cloudflare MCP Portal はエンタープライズ向け。`optimize_context=search_and_execute` でツール定義コストを定数化できるが、Cloudflare Access 環境が前提。
- Markdownify MCP は PDF/画像/音声→Markdown 変換が必要な場合に追加。Web取得のみなら mcp-read-website-fast の方が軽量。
- mcp-read-website-fast は Readability による不要要素除去 + Turndown による Markdown 変換で、Fetch MCP の代替として単体利用可能。ツール数が1で軽量。
- mcp-compressor（既に Performance カテゴリで採用済み）はツール定義の圧縮であり、レスポンス圧縮とは補完関係にある。Context Mode / mcp-rtk と併用推奨。
- lean-ctx（同カテゴリで採用済み）は `ctx_read` の10モード + Shell Hook + Archive FTS で Web 取得結果の圧縮読み込みも副次的にカバーする。lean-ctx 導入済み環境では本カテゴリのツール追加の必要性は低い。
