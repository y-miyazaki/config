# ツール比較マトリクス (Node.js)

Node.js / フロントエンド開発に特化したツール選定の判断材料。

<!-- omit toc -->
## Table of Contents

- [Linter: ESLint vs Biome vs deno lint](#linter-eslint-vs-biome-vs-deno-lint)
- [フォーマッター: Prettier vs Biome vs dprint](#フォーマッター-prettier-vs-biome-vs-dprint)
- [パッケージマネージャー: npm vs pnpm vs yarn](#パッケージマネージャー-npm-vs-pnpm-vs-yarn)

## Linter: ESLint vs Biome vs deno lint

| 比較項目 | ESLint | Biome | deno lint |
|---|---|---|---|
| 実装言語 | JavaScript | Rust | Rust |
| プラグインシステム | ✅ 豊富 (エコシステム最大) | ⚠️ 限定的 | ❌ |
| TypeScript 対応 | ✅ (typescript-eslint) | ✅ 組み込み | ✅ 組み込み |
| 実行速度 | 低速 | 非常に高速 | 非常に高速 |
| 自動修正 | ✅ | ✅ | ✅ |
| フォーマッター統合 | ❌ (Prettier 併用) | ✅ 組み込み | ✅ 組み込み |
| 設定ファイル | `.eslintrc` / `eslint.config.js` | `biome.json` | `deno.json` |
| コミュニティ規模 | 最大 | 成長中 | Deno エコシステム |
| 移行コスト | - | 中程度 (ESLint ルール互換あり) | 高い (Deno 前提) |

### 選定ガイドライン

- **ESLint**: プラグインエコシステムが必要、既存プロジェクトで利用中の場合
- **Biome**: 高速な Lint + Format を一つのツールで完結させたい新規プロジェクト向け
- **deno lint**: Deno ランタイムを採用している場合

## フォーマッター: Prettier vs Biome vs dprint

| 比較項目 | Prettier | Biome | dprint |
|---|---|---|---|
| 実装言語 | JavaScript | Rust | Rust |
| 対応言語 | JS/TS/CSS/HTML/JSON/YAML/MD 等 | JS/TS/JSON/CSS | JS/TS/JSON/MD/TOML 等 |
| 実行速度 | 低速 | 非常に高速 | 非常に高速 |
| 設定の柔軟性 | 低い (Opinionated) | 中程度 | 高い (プラグイン) |
| Lint 統合 | ❌ | ✅ | ❌ |
| エディタ統合 | ✅ 全エディタ対応 | ✅ 主要エディタ対応 | ✅ 主要エディタ対応 |
| コミュニティ規模 | 最大 | 成長中 | 中程度 |

### 選定ガイドライン

- **Prettier**: 対応言語が最も多い。Markdown/YAML/HTML 等も含めて統一フォーマットしたい場合
- **Biome**: JS/TS プロジェクトで Lint + Format を高速に一括実行したい場合
- **dprint**: Prettier 互換の出力で高速化したい場合。プラグインで拡張可能

## パッケージマネージャー: npm vs pnpm vs yarn

| 比較項目 | npm | pnpm | yarn (v4+) |
|---|---|---|---|
| 提供元 | npm Inc (GitHub) | pnpm | Meta (Yarn Berry) |
| ディスク効率 | 低い (node_modules 肥大化) | 高い (content-addressable store) | 中程度 (PnP) |
| インストール速度 | 中程度 | 高速 | 高速 |
| ロックファイル | `package-lock.json` | `pnpm-lock.yaml` | `yarn.lock` |
| Monorepo 対応 | ✅ workspaces | ✅ workspaces (高機能) | ✅ workspaces |
| 厳格な依存解決 | ❌ (hoisting) | ✅ (デフォルトで厳格) | ✅ (PnP) |
| Node.js 同梱 | ✅ | ❌ | ❌ (corepack) |
| 学習コスト | 低い | 低い | 中程度 (PnP) |

### 選定ガイドライン

- **npm**: 追加セットアップ不要で始めたい場合。小規模プロジェクト向け
- **pnpm**: ディスク効率・速度・厳格な依存解決を重視。Monorepo に最適
- **yarn (v4+)**: PnP による Zero-Install を活用したい場合
