---
applyTo: "**/instructions/*.instructions.md"
description: "AI Assistant Instructions for Writing Instruction Files"
---

# AI Assistant Instructions for Instruction Files

## Scope

- 対象は `**/instructions/*.instructions.md` の作成・修正に限定する

## Standards

### Naming Conventions

| Component | Rule                                     | Example                              |
| --------- | ---------------------------------------- | ------------------------------------ |
| File      | `<対象>.instructions.md`                 | `go.instructions.md`                 |
| Title     | `# AI Assistant Instructions for <対象>` | `# AI Assistant Instructions for Go` |

### Standards Content（MUST）

- **STD-01 (MUST)**: Naming Conventions テーブルが存在する — テーブルなしだとコンポーネント命名が不統一になる
- **STD-02 (SHOULD)**: ツール標準が文書化されている（該当する場合）
- **STD-03 (MUST)**: 他の instruction ファイルと記述レベルが一致している — ファイル間で粒度が異なると横断比較が困難

### Structure（MUST）

- **G-01 (MUST)**: Front Matter に `applyTo` + `description` を含める — 欠落すると自動適用が機能しない
- **G-02 (MUST)**: 本文は日本語、コード例/テーブルヘッダー/Front Matter/Rule ID は英語 — 混在ルールなしだと表記が不統一になる
- **G-03 (MUST)**: H1 タイトルは `# AI Assistant Instructions for <対象>` 形式 — 検索性と一貫性のため
- **STRUCT-01 (MUST)**: 5 章構成（Scope → Standards → Guidelines → Testing and Validation → Security Guidelines） — 章欠落は情報の抜け漏れを引き起こす
- **STRUCT-02 (MUST)**: 章順序を厳守する — 順序不統一だとファイル間の比較が困難になる
- **STRUCT-03 (MUST)**: H2 は章、H3 はサブセクション。H4 以降は最小限 — 階層が深いと AI の構造認識が劣化する
- **STRUCT-04 (MUST)**: Standards 章は `### Naming Conventions` を先頭に置く — 全ファイルで統一された起点
- **STRUCT-05 (MUST)**: Guidelines 章は「ドメイン固有ルール → Anti-Patterns → Code Modification Guidelines」の順 — 重要度順で配置
- **STRUCT-06 (MUST)**: H3 見出しフォーマットは `### Name（LEVEL）`（ルール）または `### Name`（宣言/プロセス） — ID 範囲を見出しに含めない
- **STRUCT-07 (MUST)**: `## Testing and Validation` / `## Security Guidelines` 章には運用手順・実務のみを記載し、レビュー観点（`TEST-*` / `SEC-*`）は Guidelines にのみ記載する — 重複定義は保守性と整合性を損なう

## Guidelines

### General (G)

- G-01 (MUST): Front Matter
  - Check: Front Matter contains applyTo and description fields
- G-02 (MUST): Language Policy
  - Check: Language policy is documented
- G-03 (MUST): Title
  - Check: Title clearly indicates purpose

### Structure (STRUCT)

- STRUCT-01 (MUST): Four Required Chapters Exist
  - Check: Standards, Guidelines, Testing and Validation, and Security Guidelines chapters exist
- STRUCT-02 (MUST): Chapter Order Unified
  - Check: Chapters follow Standards → Guidelines → Testing → Security order
- STRUCT-03 (MUST): Heading Levels Appropriate
  - Check: Heading hierarchy properly uses H2 (chapters) → H3 (subsections)
- STRUCT-04 (MUST): Standards Chapter Subsections
  - Check: Does the Standards chapter have Naming Conventions subsection first, followed by tool-specific standards?
- STRUCT-05 (MUST): Guidelines Chapter Subsections
  - Check: Does the Guidelines chapter have domain rules first, followed by Anti-Patterns, then Code Modification Guidelines?
- STRUCT-06 (MUST): H3 Heading Format
  - Check: Do H3 headings use `### Name（LEVEL）` format for rule sections, and `### Name` for process/declaration sections?

### Guidelines Chapter (GUIDE)

- GUIDE-01 (SHOULD): Documentation and Comments
  - Check: Comment and documentation conventions are documented
- GUIDE-02 (SHOULD): Code Modification Guidelines
  - Check: Modification procedures and validation methods are clearly documented
- GUIDE-03 (SHOULD): Tool Usage
  - Check: MCP Tool usage examples are documented
- GUIDE-04 (SHOULD): Error Handling
  - Check: Error handling policy is documented
- GUIDE-05 (SHOULD): Performance Considerations
  - Check: Performance guidelines are documented where applicable
- GUIDE-06 (SHOULD): Best Practices
  - Check: Best practices specific to the technology are documented
- GUIDE-07 (SHOULD): Common Patterns
  - Check: Common code patterns and idioms are documented
- GUIDE-08 (SHOULD): Anti-Patterns
  - Check: Common anti-patterns and pitfalls are documented
- GUIDE-09 (SHOULD): No ID-less Bullet Rules in Guidelines
  - Check: Are there no ID-less bullet rules in the Guidelines chapter?

### Content Quality (QUAL)

- QUAL-01 (SHOULD): Conciseness
  - Check: Content is concise without redundant expressions
- QUAL-02 (SHOULD): Practical Examples
  - Check: Practical code examples are included
- QUAL-03 (SHOULD): No Redundancy
  - Check: No duplicate content
- QUAL-04 (SHOULD): Token Efficiency
  - Check: Large code examples are avoided for high token efficiency

### Consistency (CONS)

- CONS-01 (SHOULD): Chapter Order
  - Check: Chapter order is consistent across all instructions files
- CONS-02 (SHOULD): Section Names
  - Check: Section names are consistent with other instructions files
- CONS-03 (SHOULD): Detail Level
  - Check: Documentation detail level matches other instructions files
- CONS-04 (SHOULD): Format
  - Check: Table and list formats are consistent with other instructions files

### Completeness (COMP)

- COMP-01 (SHOULD): All Required Sections
  - Check: All required sections exist
- COMP-02 (SHOULD): No Missing Commands
  - Check: Executable validation commands are comprehensive
- COMP-03 (SHOULD): Tool Coverage
  - Check: All tools in aqua.yaml are documented
- COMP-04 (SHOULD): Real Commands
  - Check: Examples are concrete and comprehensive

### Security Guidelines Chapter (SEC)

- SEC-01 (MUST): Security Items
  - Check: Security items are documented
- SEC-02 (MUST): Secrets Management
  - Check: Secrets management policy is documented
- SEC-03 (MUST): Best Practices
  - Check: Concrete security best practices are documented
- SEC-04 (SHOULD): Examples
  - Check: YAML/code examples are included (where applicable)

### Standards Chapter (STD)

- STD-01 (MUST): Naming Conventions
  - Check: Naming conventions are documented per component
- STD-02 (SHOULD): Tool Standards
  - Check: Tool conventions are documented
- STD-03 (MUST): Consistency
  - Check: Documentation level matches other instructions files

### Testing and Validation Chapter (TEST)

- TEST-01 (MUST): Validation Commands
  - Check: Executable validation commands are documented
- TEST-02 (MUST): Command Count
  - Check: At least 3 validation commands are documented
- TEST-03 (MUST): Code Block
  - Check: Examples are in \`\`\`bash code block format
- TEST-04 (SHOULD): Validation Items
  - Check: Validation items list is comprehensive
- TEST-05 (SHOULD): Tool Coverage
  - Check: All tools in aqua.yaml are covered in validation commands
- TEST-06 (SHOULD): Real Commands
  - Check: Examples are concrete and actually executable

### Code Modification Guidelines

- 変更後は [instructions-review Skill](../skills/instructions-review/SKILL.md) の validate.sh 実行を優先
- instructions ファイルを修正した場合は、必ず instructions の品質再評価を実施する
- 個別コマンドはデバッグ時のみ使用

## Testing and Validation

- 本章には実行手順（エントリポイント、個別実行、参照リンク）のみを記載し、レビュー観点（TEST-\*）は Guidelines に集約する

**エントリポイント（推奨）**:

```bash
bash skills/instructions-review/scripts/validate.sh
```

**個別実行（デバッグ時）**:

```bash
markdownlint .apm/instructions/
textlint .apm/instructions/
```

**詳細ガイド**: [instructions-review Skill](../skills/instructions-review/SKILL.md) を参照

## Security Guidelines

- 本章には運用上のセキュリティ実務のみを記載し、レビュー観点（SEC-\*）は Guidelines に集約する
- instruction ファイル内に実シークレット（トークン、鍵、認証情報）を記載しない
- コマンド例では破壊的操作を既定にせず、必要な場合は明示的な注意書きを添える
