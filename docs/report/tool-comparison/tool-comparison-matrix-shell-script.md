<!-- omit in toc -->

# Tool Comparison Matrix (Shell Script)

Shell Script に特化したツール選定の判断材料。

<!-- omit in toc -->

## History

| 日付       | 内容                                           |
| ---------- | ---------------------------------------------- |
| 2026-05-21 | History セクション追加                         |
| 2026-05-11 | 初版作成。shfmt / shellcheck / beautysh を比較 |

<!-- omit in toc -->

## Table of Contents

- [Format / Lint: beautysh vs shellcheck vs shfmt](#format--lint-beautysh-vs-shellcheck-vs-shfmt)
  - [Guidelines](#guidelines)

## Format / Lint: beautysh vs shellcheck vs shfmt

| 比較項目           | beautysh                                                          | shellcheck                                                    | shfmt                                   |
| ------------------ | ----------------------------------------------------------------- | ------------------------------------------------------------- | --------------------------------------- |
| 提供元             | -                                                                 | Vidar Holen                                                   | mvdan                                   |
| リポジトリ         | [lovesegfault/beautysh](https://github.com/lovesegfault/beautysh) | [koalaman/shellcheck](https://github.com/koalaman/shellcheck) | [mvdan/sh](https://github.com/mvdan/sh) |
| ライセンス         | MIT                                                               | GPL-3.0                                                       | BSD-3-Clause                            |
| 用途               | フォーマッター                                                    | 静的解析 (Lint)                                               | フォーマッター                          |
| 実装言語           | Python                                                            | Haskell                                                       | Go                                      |
| 自動修正           | ✅                                                                | ⚠️ (一部提案のみ)                                             | ✅                                      |
| バグ検出           | ❌                                                                | ✅ (未定義変数、引用漏れ等)                                   | ❌                                      |
| POSIX 準拠チェック | ❌                                                                | ✅                                                            | ✅                                      |

### Guidelines

**→ shfmt + shellcheck を併用する。** shfmt でフォーマット統一、shellcheck でバグ検出。役割が異なるため両方導入してコード品質を担保する。

- beautysh は shfmt の代替だが、POSIX 準拠チェック非対応・Python 依存のため通常は shfmt を推奨
