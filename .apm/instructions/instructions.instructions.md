---
applyTo: ".apm/instructions/*.instructions.md"
description: "AI Assistant Instructions for Writing Instruction Files"
---

# AI Assistant Instructions for Instruction Files

## Scope

- 対象は `.apm/instructions/*.instructions.md` の作成・修正に限定する
- 本ファイルは instruction ファイル自体の設計規約を定義する

## Standards

### Front Matter（必須）

すべての instruction ファイルは YAML Front Matter を持つ:

```yaml
---
applyTo: "<glob pattern>"
description: "<AI Assistant Instructions for ...>"
---
```

| Field       | Rule                                               | Example                                     |
| ----------- | -------------------------------------------------- | ------------------------------------------- |
| applyTo     | 対象ファイルの glob パターン（カンマ区切り複数可） | `"**/*.tf,**/*.tfvars,**/*.hcl"`            |
| description | `AI Assistant Instructions for <対象>` 形式で記述  | `"AI Assistant Instructions for Terraform"` |

### Chapter Structure（必須・順序固定）

以下の 4 章を H2（`##`）で定義し、この順序を厳守する:

1. `## Standards` — 命名規則・フォーマット・ツール標準
2. `## Guidelines` — 実装指針・ベストプラクティス・Anti-Patterns
3. `## Testing and Validation` — 検証手順
4. `## Security Guidelines` — セキュリティ要件

追加で `## Scope` を Front Matter 直後・4 章の前に配置する。

### Scope Section（必須）

- H2 で `## Scope` を定義し、対象範囲を 1〜2 行で明示する
- 「〜に限定する」形式で境界を明確にする

### Naming Conventions

- Standards 章内に `### Naming Conventions` をテーブル形式で定義する
- テーブルヘッダー: `| Component | Rule | Example |`

### Title

- H1 タイトルは `# AI Assistant Instructions for <対象>` 形式で統一する

## Guidelines

### Language Policy

- 本文: 日本語
- コード例・テーブルヘッダー・Front Matter: 英語
- 技術用語: 英語のまま使用（例: snake_case, kebab-case, goroutine）

### Code Modification Guidelines

各 instruction ファイルの Guidelines 章内に `### Code Modification Guidelines` を配置し、以下のパターンで記述する:

```markdown
### Code Modification Guidelines

- 変更後は [<skill-name> Skill](../skills/<skill-name>/SKILL.md) の validate.sh 実行を優先
- 個別コマンドはデバッグ時または失敗分析時に実施
```

- 対応する validation skill が存在する場合、validate.sh への委譲を明記する
- 個別コマンドの直接実行はデバッグ時に限定する旨を記載する

### Performance Section

- Guidelines 章内に `### Performance` を配置する
- 箇条書き（3〜5 項目）で具体的な最適化指針を記述する
- 抽象的な表現（「パフォーマンスを意識する」等）を避け、具体的なアクションを記載する

### Anti-Patterns Section（推奨）

- Guidelines 章内に `### Anti-Patterns` を配置する
- `❌` / `✅` マーカーで Bad/Good パターンを対比する
- 各項目に理由を簡潔に付記する

例:

```markdown
### Anti-Patterns

- **`count` での条件分岐乱用**: リソースの有無トグル以外に `count` を使わない。コレクションには `for_each` を使用
```

### Testing and Validation Structure

2 段構成で記述する:

1. **エントリポイント（推奨）**: `validate.sh` の実行コマンド
2. **個別実行（デバッグ時）**: 各ツールの個別コマンド

````markdown
## Testing and Validation

**エントリポイント（推奨）**:

\```bash

# 全検証を実行

bash .github/skills/<skill-name>/scripts/validate.sh
\```

**個別実行（デバッグ時）**:

\```bash

# 個別コマンド

<tool> <args>
\```

**詳細ガイド**: [<skill-name> Skill](../skills/<skill-name>/SKILL.md) を参照
````

### Security Guidelines Structure

- 3〜6 項目の箇条書きで記述する
- 各項目は具体的な禁止事項または必須事項を 1 文で表現する
- 共通パターン:
  - シークレット/機密情報の取り扱い
  - 最小権限の原則
  - 安全なデフォルト設定

### Conciseness and Token Efficiency

- 冗長な説明を避け、箇条書き・テーブルを活用する
- 同一情報の重複記載を避ける（DRY）
- lint/formatter でカバーされる内容は instruction に記載しない
- AI がコードを読めば推論できる標準的な言語規約は書かない
- 各行に「これを削除したら AI がミスするか？」と問い、No なら削除する

### Multi-Target Compatibility

instruction ファイルは APM 経由で複数ターゲット（Copilot / Claude Code / Cursor）にデプロイされる。以下を遵守する:

- **内容はツール非依存で書く**: 特定ツールの機能（`@` メンション、`/command` 等）に依存しない
- **Front Matter は Copilot 形式を正本とする**: APM がターゲット別に変換する
- **1 ファイル 200 行以内を目安とする**: Claude Code の context 効率を考慮（厳密な上限ではない）
- **検証手段を必ず含める**: AI が自身の出力を検証できるコマンドを Testing and Validation に記載する

## Testing and Validation

**エントリポイント（推奨）**:

```bash
# 全検証を実行
bash .github/skills/instructions-review/scripts/validate.sh
```

**個別実行（デバッグ時）**:

```bash
# Markdown 構文チェック
markdownlint .apm/instructions/

# 日本語技術文書チェック
textlint .apm/instructions/
```

**詳細ガイド**: [instructions-review Skill](../skills/instructions-review/SKILL.md) を参照

## Security Guidelines

- instruction ファイルにシークレット・認証情報の実値を記載しない（ダミー値を使用）
- コード例に破壊的操作をデフォルトで含めない（必要時は注意書きを付与）
- 外部リンクは信頼できる一次情報源を優先する
