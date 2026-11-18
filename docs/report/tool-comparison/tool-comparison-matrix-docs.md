# Tool Comparison Matrix (Docs Site Generator)

Markdown ドキュメントサイトの生成ツール選定の判断材料。本リポジトリは MkDocs Material (`mkdocs.yml`) で運用しており、Material for MkDocs の保守終了予定を受けて移行先を評価する。

## History

| 日付       | 内容                                                                                                                                                                                                                                                                                                                                         |
| ---------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 2026-11-18 | 初版作成。Docusaurus / Hugo / MkDocs (Material) / Starlight / Zensical を比較。Material の EOL (2027-05-05) 対応が契機。追記: MkDocs 本体は BSD-2-Clause (1.6.1 は 2024-08-30 公開、2.0.dev6 が 2026-09-15)。Zensical は公式に stable/beta の表明なし (PyPI 分類子は Beta)。Docusaurus の正規 URL は github.com/meta/docusaurus で確認 (MIT) |

## Docs Site Generator: Docusaurus vs Hugo vs MkDocs (Material) vs Starlight vs Zensical

| 比較項目          | Docusaurus                                            | Hugo                                              | MkDocs (Material)                                                                   | Starlight                                                     | Zensical                                                               |
| ----------------- | ----------------------------------------------------- | ------------------------------------------------- | ----------------------------------------------------------------------------------- | ------------------------------------------------------------- | ---------------------------------------------------------------------- |
| 提供元            | Meta                                                  | gohugoio                                          | squidfunk (Material for MkDocs)                                                     | withastro (Astro)                                             | Material for MkDocs チーム                                             |
| リポジトリ        | [meta/docusaurus](https://github.com/meta/docusaurus) | [gohugoio/hugo](https://github.com/gohugoio/hugo) | [squidfunk/mkdocs-material](https://github.com/squidfunk/mkdocs-material)           | [withastro/starlight](https://github.com/withastro/starlight) | [zensical/zensical](https://github.com/zensical/zensical)              |
| ドキュメント      | [docusaurus.io](https://docusaurus.io)                | [gohugo.io](https://gohugo.io)                    | [squidfunk.github.io/mkdocs-material](https://squidfunk.github.io/mkdocs-material/) | [starlight.astro.build](https://starlight.astro.build)        | [zensical.org/docs](https://zensical.org/docs/)                        |
| ライセンス        | MIT                                                   | Apache-2.0                                        | MIT (MkDocs 本体は BSD-2-Clause)                                                    | MIT                                                           | MIT                                                                    |
| 提供形態          | npm                                                   | 単一バイナリ                                      | PyPI (`mkdocs` + `mkdocs-material`)                                                 | npm                                                           | PyPI (`zensical`) / Docker                                             |
| 保守状況          | 活発 (最終 push 2026-11-15)                           | 活発 (最終 push 2026-11-17)                       | ⚠️ maintenance mode。重大修正とセキュリティ更新のみ。EOL 2027-05-05                 | 活発 (最終 push 2026-11-17)                                   | 活発 (最終 push 2026-11-17)                                            |
| `mkdocs.yml` 移行 | ❌ 設定・nav の再構築が必要                           | ❌ 設定・テーマの再構築が必要                     | - (現行)                                                                            | ❌ 設定・nav の再構築が必要                                   | ✅ `mkdocs.yml` を読み込み。`classic` テーマで Material の見た目を維持 |
| プラグイン互換    | ❌                                                    | ❌                                                | - (現行)                                                                            | ❌                                                            | ⚠️ 主要プラグインの代替を順次提供。非対応のものがある                  |
| 主用途            | React ベースのドキュメント / ブログ                   | 汎用の静的サイト                                  | Markdown ドキュメント                                                               | Astro ベースのドキュメント                                    | Markdown ドキュメント (Material 後継)                                  |

出典 (2026-11-18 時点): 各リポジトリの GitHub API、[Material for MkDocs README](https://github.com/squidfunk/mkdocs-material)、[Zensical README](https://github.com/zensical/zensical)、[Zensical MkDocs 互換性](https://zensical.org/docs/compatibility/mkdocs/)。

### Guidelines

**→ 現行の MkDocs Material 構成を維持しつつ、EOL (2027-05-05) 前に Zensical で試験ビルドして移行可否を判断する (条件付き推奨)。**

- 選定方針: 移行コストを最小にする。`mkdocs.yml` の nav・theme・plugins をそのまま読める Zensical が最小変更の移行先
- 採用条件 (Zensical): 試験ビルドで `mkdocs.yml` の全プラグイン (本リポジトリは `mdx-truly-sane-lists` を使用) が動作または代替される場合
- 不採用条件 (Zensical): 必須プラグインが非対応、または安定版かどうか確認できない場合。公式サイト・ロードマップに stable / beta の明示はない。PyPI の分類子は `Development Status :: 4 - Beta` (zensical 0.1.2)
- 他の候補: Docusaurus / Starlight / Hugo は設定の再構築が必要で、Markdown 中心の本リポジトリでは移行コストに見合う利点が現時点で確認できない
- 併用条件: なし (単一ジェネレータで運用する)
- 更新条件: Zensical の安定版表明、2027-05-05 までの EOL 変更、必須プラグインの互換状況が変わった場合に再評価する
