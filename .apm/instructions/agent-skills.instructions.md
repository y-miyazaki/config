---
applyTo: "**/skills/**/SKILL.md,**/skills/**/references/*.md"
description: "AI Assistant Instructions for Agent Skills Development"
---

# AI Assistant Instructions for Agent Skills

## Scope

- 対象は `skills/**/SKILL.md` および `references/*.md` の設計・修正に限定する
- 本ファイルは SKILL 設計規約を定義する。共通 4 章テンプレートの例外として扱う

## Standards

### Required Sections（MUST）

- **S-01 (MUST)**: 以下の 6 セクションを H2 で定義し、この順序で配置する — セクション欠落は実行決定性を破壊する:
  1. Input
  2. Output Specification
  3. Execution Scope
  4. Reference Files Guide
  5. Workflow
  6. Best Practices

### YAML Frontmatter（MUST）

- **S-02 (MUST)**: `name`, `description`, `license`, `metadata.author`, `metadata.version` を含む — 欠落するとプラグインシステムが skill を認識できない

### Reference Header Levels（MUST）

- **S-03 (MUST)**: ヘッダーレベルを統一する — 不統一だと AI のセクション認識が破綻する:
  - `common-checklist.md` / `common-output-format.md`: H1（`#`）
  - `common-troubleshooting.md` / `common-individual-commands.md`: H2（`##`）
  - `category-*.md`: H2（`##`）

### Naming Conventions

| Component      | Rule       | Example             |
| -------------- | ---------- | ------------------- |
| Skill name     | kebab-case | go-review           |
| Reference file | kebab-case | common-checklist.md |
| Script file    | snake_case | validate.sh         |

### Reference Files Matrix（MUST）

| File Name                       | Required | Purpose                                 | Load Trigger |
| ------------------------------- | -------- | --------------------------------------- | ------------ |
| `common-checklist.md`           | Yes      | Canonical checklist with fixed Item IDs | Always       |
| `common-output-format.md`       | Yes      | Canonical output contract               | Always       |
| `common-troubleshooting.md`     | No       | Failure diagnostics and rerun procedure | On failure   |
| `common-individual-commands.md` | No       | Debug-only command catalog              | On debugging |
| `category-*.md`                 | No       | Domain-specific review criteria         | Per category |

### Priority Principle（MUST）

- **S-04 (MUST)**: Clarity > DRY を優先する — 重複削減で曖昧化する場合は明確性を優先する

### Output Contract Source of Truth（MUST）

- **S-05 (MUST)**: `references/common-output-format.md` を出力契約の正本として扱う — `Output Specification` は要約に留め、重複定義を避ける

### Writing Style（MUST）

- **Q-06 (MUST)**: 命令形/不定詞形式を使用する — "You should" は AI の実行確度を下げる:
  - ❌ `You should do X` / `You need to check Y`
  - ✅ `Do X` / `Check Y` / `To accomplish X, do Y`

### Forbidden Expressions（MUST）

- **Q-04a (MUST)**: 以下の曖昧表現を禁止する — AI が具体的アクションに変換できない:
  - EN: appropriately, as needed, if possible, preferably, etc., and so on
  - JP: 適切に、必要に応じて、可能な限り、場合によっては、など、等

## Guidelines

### Pattern Checks

- P-01 (SHOULD): Design Pattern Compliance
  - Check: Does SKILL.md define a deterministic execution pattern with explicit flow, boundaries, and references?
- P-02 (SHOULD): Output Contract Compliance
  - Check: Does the skill define a structured output contract across Output Specification and common-output-format.md without contradiction?

### Quality Checks

- Q-01 (SHOULD): Output is Truly Structured
  - Check: Is the output format definition implementable and parseable (JSON schema / Markdown structure explicitly defined with example)?
- Q-02 (SHOULD): Scope Boundaries
  - Check: Is Execution Scope split into "What this skill does" (action list) + "Out of Scope" (explicit non-actions with tool delegation)?
- Q-03 (SHOULD): Execution Determinism
  - Check: Is execution path single/canonical OR are conditional branches explicitly defined (IF condition → path A, ELSE → path B)?
- Q-04 (SHOULD): Input/Output Specificity
  - Check: Are Input/Output formats explicitly defined with schema/structure + concrete examples (no vague "appropriately", "as needed", "etc." expressions)?
- Q-05 (SHOULD): Constraints Clarity
  - Check: Are project-specific, non-obvious constraints documented while self-evident constraints are omitted?
- Q-06 (MUST): No Implicit Inference
  - Check: Are all instructions imperative and explicit with concrete conditions (no vague "appropriately", "depending on context", "reasonable")?
- Q-09 (SHOULD): Token Hard Gate
  - Check: Does the review include `waza check` evidence and confirm Token Budget is 500 tokens or less?
- BP-03 (SHOULD): Token Efficiency
  - Check: Does SKILL.md avoid content that Claude already knows, minimizing redundancy with frontmatter and reference files?
- BP-04 (SHOULD): Anti-Overtrimming Guardrail
  - Check: If token reduction is applied, are behavior-defining instructions preserved?

### Structural Checks

- S-01 (MUST): Structural Completeness
  - Check: Does SKILL.md have all 6 required sections at ## heading level?
- S-02 (MUST): YAML Frontmatter Fields
  - Check: Does SKILL.md YAML frontmatter have all required fields (name, description, license) and recommended metadata (author, version)?
- BP-01 (SHOULD): Description Quality
  - Check: Does the description field follow best practices for skill discovery (third person, "Use when..." trigger, no implementation instructions)?
- BP-02 (SHOULD): Reference Trigger Conditions
  - Check: Does Reference Files Guide specify when to load each reference file (not just what it contains)?
- Q-07 (SHOULD): Progressive Disclosure (Soft Guard)
  - Check: Is SKILL.md concise and compatible with token budget, using word count as a supplemental signal?
- Q-08 (SHOULD): Resource Separation
  - Check: Does skill directory contain `references/` and the mandatory common reference files? `scripts/` is optional but required when executable logic is provided.
- S-03 (MUST): Reference Files Header Level Consistency
  - Check: Do references/ files follow consistent header level standards?

### Code Modification Guidelines

- 変更後は [agent-skills-review Skill](../skills/agent-skills-review/SKILL.md) の validate.sh 実行を優先
- 個別コマンドはデバッグ時のみ使用

## Testing and Validation

運用ルール:

- deterministic check（存在確認・定量計測・ファイル有無確認）は `scripts/` で自動化する
- judgment-based check（意味評価・設計判定・文脈判断）は review skill で評価する
- 総合評価は deterministic check + judgment-based check の両方で判断する

**エントリポイント（推奨）**:

```bash
bash skills/agent-skills-review/scripts/validate.sh SKILL.md
bash skills/agent-skills-review/scripts/validate_waza.sh <skill-name>
```

**個別実行（デバッグ時）**:

```bash
waza check <skill-name>
waza run <skill-name>/eval.yaml
waza tokens count <skill-name>/SKILL.md
```

**詳細ガイド**: [agent-skills-review Skill](../skills/agent-skills-review/SKILL.md) を参照

## Security Guidelines

- SKILL.md および references にシークレット・認証情報の実値を記載しない
- scripts/ 内のコードは入力検証を行い、任意パス操作を防止する
- 外部ツール実行時は引数をサニタイズし、コマンドインジェクションを防止する
