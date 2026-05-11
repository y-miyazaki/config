# ツール比較マトリクス (Shell Script)

Shell Script に特化したツール選定の判断材料。

<!-- omit toc -->
## Table of Contents

- [フォーマット / Lint: shfmt + shellcheck vs beautysh](#フォーマット--lint-shfmt--shellcheck-vs-beautysh)

## フォーマット / Lint: shfmt + shellcheck vs beautysh

| 比較項目 | shfmt | shellcheck | beautysh |
|---|---|---|---|
| 用途 | フォーマッター | 静的解析 (Lint) | フォーマッター |
| 実装言語 | Go | Haskell | Python |
| 自動修正 | ✅ | ⚠️ (一部提案のみ) | ✅ |
| バグ検出 | ❌ | ✅ (未定義変数、引用漏れ等) | ❌ |
| POSIX 準拠チェック | ✅ | ✅ | ❌ |
| pre-commit 対応 | ✅ | ✅ | ✅ |
| 補完関係 | フォーマット担当 | Lint 担当 | フォーマット担当 |

### 選定ガイドライン

- **shfmt + shellcheck 併用 (このリポジトリ)**: shfmt でフォーマット統一、shellcheck でバグ検出。役割が異なるため併用が最適
