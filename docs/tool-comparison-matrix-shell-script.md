<!-- omit in toc -->
# ツール比較マトリクス (Shell Script)

Shell Script に特化したツール選定の判断材料。

<!-- omit in toc -->
## Table of Contents

- [フォーマット / Lint: shfmt + shellcheck vs beautysh](#フォーマット--lint-shfmt--shellcheck-vs-beautysh)
  - [選定ガイドライン](#選定ガイドライン)

## フォーマット / Lint: shfmt + shellcheck vs beautysh

| 比較項目           | shfmt                                   | shellcheck                                                    | beautysh                                                          |
| ------------------ | --------------------------------------- | ------------------------------------------------------------- | ----------------------------------------------------------------- |
| 提供元             | mvdan                                   | Vidar Holen                                                   | -                                                                 |
| リポジトリ         | [mvdan/sh](https://github.com/mvdan/sh) | [koalaman/shellcheck](https://github.com/koalaman/shellcheck) | [lovesegfault/beautysh](https://github.com/lovesegfault/beautysh) |
| ライセンス         | BSD-3-Clause                            | GPL-3.0                                                       | MIT                                                               |
| 用途               | フォーマッター                          | 静的解析 (Lint)                                               | フォーマッター                                                    |
| 実装言語           | Go                                      | Haskell                                                       | Python                                                            |
| 自動修正           | ✅                                       | ⚠️ (一部提案のみ)                                              | ✅                                                                 |
| バグ検出           | ❌                                       | ✅ (未定義変数、引用漏れ等)                                    | ❌                                                                 |
| POSIX 準拠チェック | ✅                                       | ✅                                                             | ❌                                                                 |

### 選定ガイドライン

**→ shfmt + shellcheck を併用する。** shfmt でフォーマット統一、shellcheck でバグ検出。役割が異なるため両方導入してコード品質を担保する。

- beautysh は shfmt の代替だが、POSIX 準拠チェック非対応・Python 依存のため通常は shfmt を推奨
