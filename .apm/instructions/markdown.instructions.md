---
applyTo: "README.md,CONTRIBUTING.md,docs/**/*.md"
description: "AI Assistant Instructions for Markdown Documentation"
---

# AI Assistant Instructions for Markdown

## Scope

- 対象は `README.md`、`CONTRIBUTING.md`、`docs/**/*.md` のドキュメント整備に限定する
- Markdown 記法の一般論ではなく、リポジトリ内ドキュメント運用ルールを定義する

## Standards

### Naming Conventions

| Component    | Rule       | Example                   |
| ------------ | ---------- | ------------------------- |
| File (docs/) | kebab-case | getting-started.md        |
| Image file   | kebab-case | architecture-overview.png |
| Directory    | kebab-case | docs/user-guide/          |

## Guidelines

### README.md Structure（MUST）

- **DOC-01 (MUST)**: 以下の順序で構成 — 順序不統一だと初見ユーザーが必要情報を見つけられない:
  1. Project Title + Badge
  2. Description
  3. Features（簡潔リスト）
  4. Installation/Setup
  5. Usage/Examples
  6. Configuration（必要時）
  7. License/Contributing（必要時）

### Documentation Rules（SHOULD）

- **DOC-02 (SHOULD)**: 目次（TOC）は 3 セクション以上の場合に付与
- **DOC-03 (SHOULD)**: 大きなドキュメントは論理的なセクションに分割
- **DOC-04 (SHOULD)**: 画像は適切なフォーマット・サイズで配置。不要な高解像度を避ける

### Revision Process（SHOULD）

1. 対象セクション特定
2. 既存内容確認
3. 他ファイルとの統一性確認
4. 修正実施
5. フォーマット確認

### Code Modification Guidelines

- 変更後は [markdown-validation Skill](../skills/markdown-validation/SKILL.md) の検証手順を優先
- リンク切れ・表整形の個別確認はデバッグ時に実施

## Testing and Validation

**エントリポイント（推奨）**:

```bash
bash skills/markdown-validation/scripts/validate.sh
```

**個別実行（デバッグ時）**:

```bash
markdownlint docs/
markdown-link-check README.md
```

**詳細ガイド**: [markdown-validation Skill](../skills/markdown-validation/SKILL.md) を参照

## Security Guidelines

- ドキュメントに機密情報（トークン・鍵・内部URL・個人情報）を記載しない
- コマンド例は破壊的操作を既定にしない（必要時は注意書きを付与）
- 外部リンクは信頼できる一次情報を優先し、不明な短縮URLを避ける
- コード例にダミーの認証情報を使用する場合、明示的にダミーであることを示す
