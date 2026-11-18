# Tool Comparison Matrix (Node.js)

Node.js / フロントエンド開発に特化したツール選定の判断材料。

## History

| 日付       | 内容                                                                                                                                                                                                 |
| ---------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 2026-11-18 | 全般最新化: Biome v2.6 の Markdown/YAML/SCSS 対応を反映。Oxlint (Linter) / Oxfmt (Formatter) / Bun (Package Manager) を追加。pnpm 11 の既定値変更を追記。yarn の提供元表記を公式サイトに合わせて修正 |
| 2026-08-23 | Biome HTML/SVG Formatter が実験的である点を公式 Language support に合わせて訂正 (Lint は ✅、Format は 🟡)                                                                                           |
| 2026-06-17 | 全般最新化: Biome v2.5.0 HTML/SVG 対応反映、Formatter 推奨を Biome に変更                                                                                                                            |
| 2026-05-21 | History セクション追加                                                                                                                                                                               |
| 2026-05-11 | 初版作成。Linter / Formatter / Package Manager を比較                                                                                                                                                |

## Linter: Biome vs deno lint vs ESLint vs Oxlint

| 比較項目           | Biome                                             | deno lint                                         | ESLint                                            | Oxlint                                                   |
| ------------------ | ------------------------------------------------- | ------------------------------------------------- | ------------------------------------------------- | -------------------------------------------------------- |
| 提供元             | Biome                                             | Deno                                              | ESLint                                            | Oxc                                                      |
| リポジトリ         | [biomejs/biome](https://github.com/biomejs/biome) | [denoland/deno](https://github.com/denoland/deno) | [eslint/eslint](https://github.com/eslint/eslint) | [oxc-project/oxc](https://github.com/oxc-project/oxc)    |
| ドキュメント       | [biomejs.dev](https://biomejs.dev)                | [docs.deno.com](https://docs.deno.com)            | [eslint.org](https://eslint.org)                  | [oxc.rs](https://oxc.rs/docs/guide/usage/linter.html)    |
| ライセンス         | MIT                                               | MIT                                               | MIT                                               | MIT                                                      |
| 実装言語           | Rust                                              | Rust                                              | JavaScript                                        | Rust                                                     |
| プラグインシステム | ⚠️ 限定的 (JS プラグインは Developer preview)     | ❌                                                | ✅ 豊富 (エコシステム最大)                        | ⚠️ 限定的 (JS プラグインは alpha、ESLint プラグイン互換) |
| TypeScript 対応    | ✅ 組み込み                                       | ✅ 組み込み                                       | ✅ (typescript-eslint)                            | ✅ 組み込み (型認識 Lint は tsgo ベース)                 |
| 実行速度           | 非常に高速                                        | 非常に高速                                        | 低速                                              | 非常に高速 (公式: ESLint 比 50〜100x)                    |
| フォーマッター統合 | ✅ 組み込み                                       | ✅ 組み込み                                       | ❌ (Prettier 併用)                                | ❌ (Oxfmt 併用)                                          |

### Guidelines

**→ 新規プロジェクトは Biome、既存プロジェクトは ESLint を採用する。**

- Biome: Lint + Format を一つのツールで高速に完結させたい新規プロジェクトに最適
- ESLint: プラグインエコシステム (React, Vue, a11y 等) が必要な場合 / 既存プロジェクトで移行コストが高い場合
- Oxlint: ESLint 互換ルール (公式記載 870+ ルール) を高速に実行したい場合。ESLint との併用 (高速チェックを Oxlint、プラグイン依存ルールを ESLint) も可能。Format は別ツール (Oxfmt / Prettier / Biome)
- deno lint: Deno ランタイムを採用している場合のみ

## Formatter: Biome vs dprint vs Oxfmt vs Prettier

| 比較項目   | Biome                                                               | dprint                                            | Oxfmt                                                                 | Prettier                                                  |
| ---------- | ------------------------------------------------------------------- | ------------------------------------------------- | --------------------------------------------------------------------- | --------------------------------------------------------- |
| 提供元     | Biome                                                               | dprint                                            | Oxc                                                                   | Prettier                                                  |
| リポジトリ | [biomejs/biome](https://github.com/biomejs/biome)                   | [dprint/dprint](https://github.com/dprint/dprint) | [oxc-project/oxc](https://github.com/oxc-project/oxc)                 | [prettier/prettier](https://github.com/prettier/prettier) |
| ライセンス | MIT                                                                 | MIT                                               | MIT                                                                   | MIT                                                       |
| 実装言語   | Rust                                                                | Rust                                              | Rust                                                                  | JavaScript                                                |
| 対応言語   | JS/TS/JSON/CSS/SCSS/GraphQL/Markdown/YAML。HTML/SVG Format は実験的 | JS/TS/JSON/MD/TOML 等                             | JS/TS/JSON/CSS/SCSS/YAML/TOML/HTML/Vue/Markdown/GraphQL 等 (公式記載) | JS/TS/CSS/HTML/JSON/YAML/MD 等                            |
| 実行速度   | 非常に高速                                                          | 非常に高速                                        | 非常に高速 (公式: Prettier 比 約 30x、Biome 比 約 2x)                 | 低速                                                      |
| Lint 統合  | ✅                                                                  | ❌                                                | ❌ (Oxlint 併用)                                                      | ❌                                                        |

### Guidelines

**→ Biome を採用する。** Lint + Format 統合により JS/TS/CSS/SCSS/JSON/GraphQL に加え Markdown/YAML (v2.6 で追加) を高速にカバー。Node.js 不要。HTML/SVG の Lint は対応済みだが Formatter は実験的 (公式 Language support、opt-in 要)。

- Biome: Lint と統合して一つのツールで完結させたい場合。安定 Format が必要な HTML は Prettier 併用を検討。Markdown の Prettier 互換は約 92%、YAML は 100% (v2.6 公式ブログ)
- Prettier: 安定した HTML フォーマットが必要な場合 / プラグイン言語対応が必要な場合
- Oxfmt: Prettier 出力との互換を重視しつつ高速化したい場合。import 整列・Tailwind クラス整列を内蔵。公式 docs に安定版/ベータの区分記載がないため、採用前に Release を確認する
- dprint: Prettier 互換の出力で高速化したい / プラグインで対応言語を拡張したい場合
- Vite+ (MIT) は Vite / Vitest / Oxlint / Oxfmt を `vp` コマンドで統合する開発ツールチェーン。Oxlint + Oxfmt を採用する場合は選択肢になる

## Package Manager: Bun vs npm vs pnpm vs yarn

| 比較項目         | Bun                                                      | npm                                      | pnpm                                      | yarn (v4+)                                        |
| ---------------- | -------------------------------------------------------- | ---------------------------------------- | ----------------------------------------- | ------------------------------------------------- |
| 提供元           | Bun (Anthropic 傘下)                                     | npm Inc (GitHub)                         | pnpm                                      | Yarn Contributors                                 |
| リポジトリ       | [oven-sh/bun](https://github.com/oven-sh/bun)            | [npm/cli](https://github.com/npm/cli)    | [pnpm/pnpm](https://github.com/pnpm/pnpm) | [yarnpkg/berry](https://github.com/yarnpkg/berry) |
| ドキュメント     | [bun.com/docs](https://bun.com/docs/pm/cli/install)      | [docs.npmjs.com](https://docs.npmjs.com) | [pnpm.io](https://pnpm.io)                | [yarnpkg.com](https://yarnpkg.com)                |
| ライセンス       | MIT (JavaScriptCore 等は LGPL-2)                         | Artistic-2.0                             | MIT                                       | BSD-2-Clause                                      |
| ディスク効率     | 高い (hardlink / clonefile、isolated linker)             | 低い (node_modules 肥大化)               | 高い (content-addressable store)          | 中程度 (PnP)                                      |
| インストール速度 | 高速 (公式: npm 比 最大 25x)                             | 中程度                                   | 高速                                      | 高速                                              |
| Monorepo 対応    | ✅ workspaces                                            | ✅ workspaces                            | ✅ workspaces (高機能)                    | ✅ workspaces                                     |
| 厳格な依存解決   | ⚠️ isolated linker (monorepo 新規は既定、単一は hoisted) | ❌ (hoisting)                            | ✅ (デフォルトで厳格)                     | ✅ (PnP)                                          |
| Node.js 同梱     | ❌ (独自ランタイム。`bun install` 単体でも利用可)        | ✅                                       | ❌                                        | ❌ (corepack)                                     |

### Guidelines

**→ pnpm を採用する。** ディスク効率・速度・厳格な依存解決 (幽霊依存の防止) で優位。Monorepo にも最適。

- pnpm 11 の変更点: Node.js 22 以上が必須。`minimumReleaseAge` 既定 1440 (1 日)、`blockExoticSubdeps` / `strictDepBuilds` 既定 true、依存のビルドスクリプトは `allowBuilds` による許可制 (pnpm 10 から `pnpm-v10-to-v11` codemod で移行可能)
- 追加セットアップ不要で始めたい小規模プロジェクトでは npm でも可
- PnP による Zero-Install を活用したい場合は yarn (v4+) を検討
- Bun: インストール高速化を優先する / Bun ランタイムを採用する場合。依存のライフサイクルスクリプトは既定で無効 (`trustedDependencies` で許可)、`minimumReleaseAge` に対応。単一オーナー (Anthropic) の依存となる点に留意
