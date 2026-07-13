# Tool Comparison Matrix (Node.js)

Node.js / フロントエンド開発に特化したツール選定の判断材料。

## History

| 日付       | 内容                                                                      |
| ---------- | ------------------------------------------------------------------------- |
| 2026-06-17 | 全般最新化: Biome v2.5.0 HTML/SVG 対応反映、Formatter 推奨を Biome に変更 |
| 2026-05-21 | History セクション追加                                                    |
| 2026-05-11 | 初版作成。Linter / Formatter / Package Manager を比較                     |

## Linter: Biome vs deno lint vs ESLint

| 比較項目           | Biome                                             | deno lint                                         | ESLint                                            |
| ------------------ | ------------------------------------------------- | ------------------------------------------------- | ------------------------------------------------- |
| 提供元             | Biome                                             | Deno                                              | ESLint                                            |
| リポジトリ         | [biomejs/biome](https://github.com/biomejs/biome) | [denoland/deno](https://github.com/denoland/deno) | [eslint/eslint](https://github.com/eslint/eslint) |
| ライセンス         | MIT                                               | MIT                                               | MIT                                               |
| 実装言語           | Rust                                              | Rust                                              | JavaScript                                        |
| プラグインシステム | ⚠️ 限定的                                         | ❌                                                | ✅ 豊富 (エコシステム最大)                        |
| TypeScript 対応    | ✅ 組み込み                                       | ✅ 組み込み                                       | ✅ (typescript-eslint)                            |
| 実行速度           | 非常に高速                                        | 非常に高速                                        | 低速                                              |
| フォーマッター統合 | ✅ 組み込み                                       | ✅ 組み込み                                       | ❌ (Prettier 併用)                                |

### Guidelines

**→ 新規プロジェクトは Biome、既存プロジェクトは ESLint を採用する。**

- Biome: Lint + Format を一つのツールで高速に完結させたい新規プロジェクトに最適
- ESLint: プラグインエコシステム (React, Vue, a11y 等) が必要な場合 / 既存プロジェクトで移行コストが高い場合
- deno lint: Deno ランタイムを採用している場合のみ

## Formatter: Biome vs dprint vs Prettier

| 比較項目   | Biome                                             | dprint                                            | Prettier                                                  |
| ---------- | ------------------------------------------------- | ------------------------------------------------- | --------------------------------------------------------- |
| 提供元     | Biome                                             | dprint                                            | Prettier                                                  |
| リポジトリ | [biomejs/biome](https://github.com/biomejs/biome) | [dprint/dprint](https://github.com/dprint/dprint) | [prettier/prettier](https://github.com/prettier/prettier) |
| ライセンス | MIT                                               | MIT                                               | MIT                                                       |
| 実装言語   | Rust                                              | Rust                                              | JavaScript                                                |
| 対応言語   | JS/TS/JSON/CSS/HTML/SVG/GraphQL                   | JS/TS/JSON/MD/TOML 等                             | JS/TS/CSS/HTML/JSON/YAML/MD 等                            |
| 実行速度   | 非常に高速                                        | 非常に高速                                        | 低速                                                      |
| Lint 統合  | ✅                                                | ❌                                                | ❌                                                        |

### Guidelines

**→ Biome を採用する。** Lint + Format 統合、HTML/SVG 対応の追加 (v2.5.0) により、Prettier の大部分のユースケースをカバー。Node.js 不要で高速。

- Biome: Lint と統合して一つのツールで完結させたい場合。HTML/CSS/GraphQL もカバー
- Prettier: Markdown・YAML フォーマットが必要な場合 / プラグイン言語対応が必要な場合
- dprint: Prettier 互換の出力で高速化したい / プラグインで対応言語を拡張したい場合

## Package Manager: npm vs pnpm vs yarn

| 比較項目         | npm                                   | pnpm                                      | yarn (v4+)                                        |
| ---------------- | ------------------------------------- | ----------------------------------------- | ------------------------------------------------- |
| 提供元           | npm Inc (GitHub)                      | pnpm                                      | Meta (Yarn Berry)                                 |
| リポジトリ       | [npm/cli](https://github.com/npm/cli) | [pnpm/pnpm](https://github.com/pnpm/pnpm) | [yarnpkg/berry](https://github.com/yarnpkg/berry) |
| ライセンス       | Artistic-2.0                          | MIT                                       | BSD-2-Clause                                      |
| ディスク効率     | 低い (node_modules 肥大化)            | 高い (content-addressable store)          | 中程度 (PnP)                                      |
| インストール速度 | 中程度                                | 高速                                      | 高速                                              |
| Monorepo 対応    | ✅ workspaces                         | ✅ workspaces (高機能)                    | ✅ workspaces                                     |
| 厳格な依存解決   | ❌ (hoisting)                         | ✅ (デフォルトで厳格)                     | ✅ (PnP)                                          |
| Node.js 同梱     | ✅                                    | ❌                                        | ❌ (corepack)                                     |

### Guidelines

**→ pnpm を採用する。** ディスク効率・速度・厳格な依存解決 (幽霊依存の防止) で優位。Monorepo にも最適。

- 追加セットアップ不要で始めたい小規模プロジェクトでは npm でも可
- PnP による Zero-Install を活用したい場合は yarn (v4+) を検討
