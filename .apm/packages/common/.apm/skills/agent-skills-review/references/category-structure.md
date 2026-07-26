## Structural Checks (S)

**S-01 (MUST): Structural Completeness**

Check: Does SKILL.md have all 5 required sections at ## heading level?
Why: Complete structure ensures all required information exists for quality evaluation. Missing sections make skill incomplete and non-reviewable.

Required sections:

1. Input
2. Output Specification
3. Execution Scope
4. Reference Files Guide
5. Workflow

Sections removed by design (redundant with frontmatter description or self-evident to Claude):

- Purpose (duplicates description field)
- When to Use This Skill (duplicates description activation trigger)
- Constraints (self-evident prerequisites)
- Failure Behavior (standard tool behavior) — use `### Error Handling` under Workflow instead (Q-10 SHOULD)
- Best Practices (merge into Workflow or Execution Scope)

`### Error Handling` is not a sixth H2 section. It lives under `## Workflow` when the skill has recoverable or fatal branches (Q-10 SHOULD). Automation and utility siblings should include the same table pattern.

Examples:

- ✅ All 5 required sections present
- ❌ Missing "Workflow" → only 4/5 sections → FAIL

---

**S-02 (MUST): YAML Frontmatter Fields**

Check: Does SKILL.md YAML frontmatter have all required fields (name, description, license) and recommended metadata (author, version)?
Why: Machine-readable frontmatter enables skill discovery, cataloging, and CI/CD integration. Missing fields cause parsing errors and skill registration failures. Metadata enables version tracking and ownership.
Examples:

- ✅ `name: go-review`, `description: "Reviews..."`, `license: Apache-2.0`, `metadata: {author: y-miyazaki, version: "1.0.0"}`
- ❌ Missing `license` field → parsing fails
- ⚠️ Missing `metadata.version` → version tracking unavailable

---

**BP-01 (SHOULD): Description Quality**

Check: Does the description field follow best practices for skill discovery (third person, includes when-to-activate trigger content, no implementation instructions)?
Why: The description is the primary signal for skill activation. Poor descriptions cause incorrect skill selection or missed activation. Official guidance: write in third person and include specific keywords that help agents identify relevant tasks. A clear activation trigger is required; the exact phrase `Use when...` is recommended but not mandatory.
Examples:

- ✅ "Reviews Go source code for correctness and security. Use when reviewing Go pull requests or assessing security." (third person + recommended trigger phrasing)
- ✅ "Reviews Go source code for correctness and security during pull-request review and security assessment." (third person + trigger content without `Use when`)
- ❌ "Use for manual review of Go code" (imperative, not third person)
- ❌ "Always use validate.sh script. For troubleshooting, see references/." (implementation instructions in description)
- ❌ "Helps with Go code" (too vague, no activation trigger)

---

**BP-02 (SHOULD): Reference Trigger Conditions**

Check: Does every Reference Files Guide line use exactly one parenthetical load trigger from the allowlist — `(always read)`, `(read on failure)`, `(read on debugging)`, `(read on automation path)`, `(read on interactive path)`, `(read when <condition>)`? Flag any other trigger wording.
Allowlist detail: `<condition>` in `(read when <condition>)` must be a single concrete predicate.
Why: One allowlisted trigger keeps load timing unambiguous. Triggers outside the list are easy to misread.
Examples:

- ✅ `[common-checklist.md](references/common-checklist.md) (always read)`
- ✅ `[category-automation-envelope.md](references/category-automation-envelope.md) (read on automation path)`
- ✅ `[common-troubleshooting.md](references/common-troubleshooting.md) (read on failure)`
- ✅ `[common-impact-map.md](references/common-impact-map.md) (read on interactive path)`
- ❌ Parenthetical trigger not on the allowlist
- ❌ No parenthetical trigger on a Reference Files Guide line

---

**Q-07 (SHOULD): Progressive Disclosure (Soft Guard)**

Check: Is SKILL.md depth aligned with sibling skills in the same package? Is word count aligned with sibling depth for that family?
Why: Token/word limits are advisory. Isolated compression below sibling depth causes execution drift; prefer package-wide alignment over a single-skill token gate.
Examples:

- ✅ Automation sibling (for example ci-sweeper/changelog) matches package section depth and reference phrasing
- ✅ `waza check` token evidence recorded; over 500 noted as Q-09 advisory when siblings are similar depth
- ❌ One skill uses arrow-only workflow while siblings use numbered `###` path sections

---

**Q-08 (SHOULD): Resource Separation**

Check: Does skill directory contain `references/` and the mandatory common reference files? `scripts/` is optional but required when executable logic is provided.
Why: Reference files define reusable evaluation contracts. Scripts should hold deterministic executable logic when present, but not every skill requires scripts.
Examples:

- ✅ references/ exists and includes common-checklist.md + common-output-format.md
- ✅ scripts/ exists when deterministic commands are provided
- ❌ Missing references/ or missing common-checklist.md/common-output-format.md

---

**S-07 (MUST): Portable Reference Paths**

Check: Do SKILL.md and `references/` link only to files inside the same skill directory (`references/`, `assets/`, `scripts/`) or to absolute `https://` URLs?
Why: Skills are often installed or copied per skill directory. Paths to repository `docs/`, `../other-skill/`, or `repository \`docs/...\`` prose break consumers that use the skill in a different repository layout.
Examples:

- ✅ `[category-automation-envelope.md](references/category-automation-envelope.md)`
- ✅ `https://example.com/spec` for stable external specs
- ❌ `repository \`docs/explanation/...\``
- ❌ `[format](../../../../docs/...)` or any `../` escape from the skill tree
- ❌ `[shared.md](../other-skill/references/shared.md)`

---

**S-03 (MUST): Reference Files Header Level Consistency**

Check: Do references/ files follow consistent header level standards?
Why: Consistent header levels ensure predictable structure, proper document hierarchy, and correct rendering when files are referenced from SKILL.md via @-mention.

Header level requirements:

**Common-prefix files**:

- `common-checklist.md`: Starts with H1 (`#`)
- `common-output-format.md`: Starts with H1 (`#`)
- `common-troubleshooting.md`: Starts with H2 (`##`)
- `common-individual-commands.md`: Starts with H2 (`##`)

**Category-prefix files**:

- All category-\*.md: Starts with H2 (`##`)
- Internal content: H3 (`###`) and below for hierarchy

Examples:

- ✅ `common-checklist.md` first line: `# Checklist Title` → PASS
- ✅ `common-troubleshooting.md` first line: `## Troubleshooting Guide` → PASS
- ✅ `category-security.md` first line: `## Security Checks` → PASS
- ❌ `common-checklist.md` first line: `## Checklist` → FAIL (should be H1)
- ❌ `category-security.md` first line: `# Security Checks` → FAIL (should be H2)
