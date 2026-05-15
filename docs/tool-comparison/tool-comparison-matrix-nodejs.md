<!-- omit in toc -->
# Tool Comparison Matrix (Node.js)

Node.js / フロントエンド開発に特化したツール選定の判断材料。

<!-- omit in toc -->
## Table of Contents

- [Linter: ESLint vs Biome vs deno lint](#linter-eslint-vs-biome-vs-deno-lint)
  - [Guidelines](#Guidelines)
- [Formatter: Prettier vs Biome vs dprint](#formatter-prettier-vs-biome-vs-dprint)
  - [Guidelines](#Guidelines-1)
- [Package Manager: npm vs pnpm vs yarn](#package-manager-npm-vs-pnpm-vs-yarn)
  - [Guidelines](#Guidelines-2)

## Linter: ESLint vs Biome vs deno lint

| 比較項目           | ESLint                                            | Biome                                             | deno lint                                         |
| ------------------ | ------------------------------------------------- | ------------------------------------------------- | ------------------------------------------------- |
| 提供元             | ESLint                                            | Biome                                             | Deno                                              |
| リポジトリ         | [eslint/eslint](https://github.com/eslint/eslint) | [biomejs/biome](https://github.com/biomejs/biome) | [denoland/deno](https://github.com/denoland/deno) |
| ライセンス         | MIT                                               | MIT                                               | MIT                                               |
| 実装言語           | JavaScript                                        | Rust                                              | Rust                                              |
| プラグインシステム | ✅ 豊富 (エコシステム最大)                         | ⚠️ 限定的                                          | ❌                                                 |
| TypeScript 対応    | ✅ (typescript-eslint)                             | ✅ 組み込み                                        | ✅ 組み込み                                        |
| 実行速度           | 低速                                              | 非常に高速                                        | 非常に高速                                        |
| フォーマッター統合 | ❌ (Prettier 併用)                                 | ✅ 組み込み                                        | ✅ 組み込み                                        |

### Guidelines

**→ 新規プロジェクトは Biome、既存プロジェクトは ESLint を採用する。**

- Biome: Lint + Format を一つのツールで高速に完結させたい新規プロジェクトに最適
- ESLint: プラグインエコシステム (React, Vue, a11y 等) が必要な場合 / 既存プロジェクトで移行コストが高い場合
- deno lint: Deno ランタイムを採用している場合のみ

## Formatter: Prettier vs Biome vs dprint

| 比較項目   | Prettier                                                  | Biome                                             | dprint                                            |
| ---------- | --------------------------------------------------------- | ------------------------------------------------- | ------------------------------------------------- |
| 提供元     | Prettier                                                  | Biome                                             | dprint                                            |
| リポジトリ | [prettier/prettier](https://github.com/prettier/prettier) | [biomejs/biome](https://github.com/biomejs/biome) | [dprint/dprint](https://github.com/dprint/dprint) |
| ライセンス | MIT                                                       | MIT                                               | MIT                                               |
| 実装言語   | JavaScript                                                | Rust                                              | Rust                                              |
| 対応言語   | JS/TS/CSS/HTML/JSON/YAML/MD 等                            | JS/TS/JSON/CSS                                    | JS/TS/JSON/MD/TOML 等                             |
| 実行速度   | 低速                                                      | 非常に高速                                        | 非常に高速                                        |
| Lint 統合  | ❌                                                         | ✅                                                 | ❌                                                 |

### Guidelines

**→ Biome を Linter と併用する場合は Biome のフォーマッターを使用する。単体フォーマッターとしては Prettier を採用する。**

- Biome: Lint と統合して一つのツールで完結させたい場合
- Prettier: 対応言語が最も多い / Markdown・YAML・HTML 等も含めて統一フォーマットしたい場合
- dprint: Prettier 互換の出力で高速化したい / プラグインで対応言語を拡張したい場合

## Package Manager: npm vs pnpm vs yarn

| 比較項目         | npm                                   | pnpm                                      | yarn (v4+)                                        |
| ---------------- | ------------------------------------- | ----------------------------------------- | ------------------------------------------------- |
| 提供元           | npm Inc (GitHub)                      | pnpm                                      | Meta (Yarn Berry)                                 |
| リポジトリ       | [npm/cli](https://github.com/npm/cli) | [pnpm/pnpm](https://github.com/pnpm/pnpm) | [yarnpkg/berry](https://github.com/yarnpkg/berry) |
| ライセンス       | Artistic-2.0                          | MIT                                       | BSD-2-Clause                                      |
| ディスク効率     | 低い (node_modules 肥大化)            | 高い (content-addressable store)          | 中程度 (PnP)                                      |
| インストール速度 | 中程度                                | 高速                                      | 高速                                              |
| Monorepo 対応    | ✅ workspaces                          | ✅ workspaces (高機能)                     | ✅ workspaces                                      |
| 厳格な依存解決   | ❌ (hoisting)                          | ✅ (デフォルトで厳格)                      | ✅ (PnP)                                           |
| Node.js 同梱     | ✅                                     | ❌                                         | ❌ (corepack)                                      |

### Guidelines

**→ pnpm を採用する。** ディスク効率・速度・厳格な依存解決 (幽霊依存の防止) で優位。Monorepo にも最適。

- 追加セットアップ不要で始めたい小規模プロジェクトでは npm でも可
- PnP による Zero-Install を活用したい場合は yarn (v4+) を検討
