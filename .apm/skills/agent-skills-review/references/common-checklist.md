# Complete Review Checklist & Validation Commands

## Automated Validation Commands

Run these BEFORE manual review to verify pre-conditions:

### 1. Run All Automated Checks
```bash
# Run the validate.sh script (includes YAML syntax, structure, field, word count, directories)
bash .github/skills/agent-skills-review/scripts/validate.sh SKILL.md

# Expected output: JSON with all validation checks
# If any FAIL (status != PASS), stop and request fixes before proceeding to manual review
```

### 2. Run Required Waza Checks
```bash
# Run readiness + eval + token checks in one step
bash .github/skills/agent-skills-review/scripts/validate_waza.sh <skill-name>

# The script runs these commands:
# waza check <skill-name>
# waza run <skill-name>/eval.yaml
# waza tokens count <skill-name>/SKILL.md

# If any command fails, stop and request fixes before manual review
```

### 3. Optional Deep-Dive Checks
```bash
# A/B baseline effect measurement (section 6)
waza run <eval.yaml> --baseline --trials 5 --output results-baseline.json

# Advisory quality scoring (optional)
waza quality <skill-name>

# Compare token delta against main (optional)
waza tokens compare main --skills --threshold 10

# Compare historical result files (optional)
waza compare <results-a.json> <results-b.json>

# Coverage planning (optional)
waza coverage --format markdown
```

---

## Manual Review Checklist

### Automated Checks Status
- [ ] YAML Syntax → validated by validate.sh
- [ ] S-01 Structural Completeness (6 required sections) → validated by validate.sh
- [ ] S-02 YAML Frontmatter Fields → validated by validate.sh
- [ ] Description Quality → validated by validate.sh
- [ ] Metadata Fields → validated by validate.sh
- [ ] Q-07 Progressive Disclosure (soft guard) → validated by validate.sh
- [ ] Q-08 Resource Separation → validated by validate.sh (references/ required; scripts/ optional)
- [ ] Reference Mandatory Files → validated by validate.sh
- [ ] Reference Trigger Conditions → validated by validate.sh

**Note:** All automated checks are executed by `validate.sh` script. If any check has status "FAIL", fix the issue and re-run before proceeding to manual review.

**Note:** Required Waza checks are executed by `validate_waza.sh`. Treat any failure in `check`, `run`, or `tokens count` as a blocking issue.

**Note:** For section 7 grader coverage in `eval.yaml`, keep `code`, `text`, and `behavior` enabled by default; use `prompt` (LLM-as-Judge) only in dedicated quality runs.

### Structure Checks (Reference: references/category-structure.md)

#### S-01: Section Order
- [ ] All 6 required sections present:
  1. Input
  2. Output Specification
  3. Execution Scope
  4. Reference Files Guide
  5. Workflow
  6. Best Practices
- **PASS** if all sections present, **FAIL** if any section missing

#### S-02: YAML Frontmatter Fields
- [ ] `name`, `description`, `license` fields present in frontmatter
- [ ] `metadata.author` and `metadata.version` present
- **PASS** if all required and recommended fields are present, **FAIL** if required fields are missing

#### S-03: Reference Files Header Level Consistency
- [ ] `common-checklist.md`: Starts with H1 (`#`)
- [ ] `common-output-format.md`: Starts with H1 (`#`)
- [ ] `common-troubleshooting.md`: Starts with H2 (`##`) if present
- [ ] `common-individual-commands.md`: Starts with H2 (`##`) if present
- [ ] All `category-*.md` files: Start with H2 (`##`)
- **PASS** if all present files follow header level standards, **FAIL** if any file violates standard

### Quality Checks (Reference: references/category-quality.md)

#### Q-01: Output is Truly Structured
- [ ] Output Specification defines structured format (JSON/Markdown/Table)
- [ ] Concrete example provided (not just description)
- [ ] Format is machine-parseable (not free text)
- **PASS** if all 3 ✅

#### Q-02: Scope Boundaries
- [ ] Execution Scope section defines what the skill does (checklist-driven review)
- [ ] Execution Scope section defines what the skill does NOT do (2-3 key exclusions)
- [ ] Tool delegation clearly mentioned (related validation skill, external tools)
- **PASS** if all 3 ✅

#### Q-03: Execution Determinism
- [ ] Review Flow has clear Step 1/2/3/4 or similar explicit sequence
- [ ] If multiple paths, decision criteria are explicit (IF/THEN conditions)
- [ ] No "depending on context" without specifying those contexts
- **PASS** if all 3 ✅

#### Q-04: Input/Output Specificity
- [ ] Input format examples are concrete (not "JSON file" but structured example)
- [ ] Output format examples are specific (field names, value types)
- [ ] No forbidden expressions: "etc.", "and so on", "as needed", "appropriately"
- **PASS** if all 3 ✅

#### Q-05: Constraints Clarity
- [ ] Project-specific constraints are documented (e.g., coverage thresholds, tool versions)
- [ ] Self-evident constraints are omitted (e.g., "tool must be installed", "files must exist")
- [ ] Non-obvious limitations are mentioned where relevant (in Execution Scope or Input)
- **PASS** if all 3 ✅

#### Q-06: No Implicit Inference
- [ ] All instructions use imperative form (Do X, Return Y, not "You should")
- [ ] Conditional logic explicit: "If X, then Y, else Z" (not "Handle appropriately")
- [ ] No forbidden expressions: "appropriately", "depending on", "case by case"
- **PASS** if all 3 ✅

#### Q-09: Token Hard Gate
- [ ] `waza check <skill-dir>` evidence is provided
- [ ] Reported Token Budget is 500 tokens or less
- [ ] If token reduction was performed, behavior-defining instructions remain intact
- **PASS** if all 3 ✅

### Pattern Checks (Reference: references/category-patterns.md)

#### P-01: Design Pattern Compliance
- [ ] Workflow has explicit numbered steps and deterministic execution order
- [ ] Branching logic is explicit when multiple paths exist (IF/THEN)
- [ ] Execution Scope states what is in scope and out of scope
- [ ] Reference Files Guide includes required common files and relevant category files
- **PASS** if all 4 ✅

#### P-02: Output Contract Compliance
- [ ] Output Specification clearly states what the skill returns and how `common-output-format.md` refines it
- [ ] `references/common-output-format.md` defines a concrete structured output contract
- [ ] Output structure is concrete and parseable (section names, fields, or schema are explicit)
- [ ] Recommendations or example fields are concrete, not generic
- **PASS** if all required items are satisfied

### Best Practice Checks (Reference: references/category-structure.md, references/category-quality.md)

#### BP-01: Description Quality
- [ ] Description uses third person ("Reviews...", "Validates...", not "Use for...")
- [ ] Description includes "Use when..." trigger keywords
- [ ] Description does not contain implementation instructions ("Always use...", "For troubleshooting...")
- [ ] Description is ≤ 1024 characters
- **PASS** if all 4 ✅

#### BP-02: Reference Trigger Conditions
- [ ] Standard Components have "(always read)" annotation
- [ ] Category Details have "Read when..." trigger conditions
- [ ] No generic "see references/ for details" without specific triggers
- **PASS** if all 3 ✅

#### BP-03: Token Efficiency
- [ ] No Purpose section duplicating description
- [ ] No When to Use section duplicating description triggers
- [ ] No self-evident Constraints section (tool installation, file existence)
- [ ] No general Failure Behavior section (standard tool exit codes)
- [ ] No Available Review Categories section duplicating Reference Files Guide
- **PASS** if no redundant sections found

#### BP-04: Anti-Overtrimming Guardrail
- [ ] Trigger quality preserved (`description` trigger + `USE FOR` / `DO NOT USE FOR`)
- [ ] Structured output contract preserved (`Output Specification` + `common-output-format.md`)
- [ ] Workflow remains deterministic (numbered steps or explicit IF/THEN branch)
- [ ] At least one concrete example remains in SKILL.md
- **PASS** if all 4 ✅

---

## Summary Scoring

| Category          | Checks                                                                   | Pass Threshold | Your Score |
| ----------------- | ------------------------------------------------------------------------ | -------------- | ---------- |
| **Automated**     | 9 (YAML, Structure, Fields, Desc, Meta, WordCount, Dirs, Refs, Triggers) | 9/9            | ___ / 9    |
| **Quality**       | 7 (Q-01~Q-06, Q-09)                                                      | 6+/7           | ___ / 7    |
| **Pattern**       | 2 (P-01, P-02)                                                           | 2/2            | ___ / 2    |
| **Best Practice** | 4 (BP-01~BP-04)                                                          | 3+/4           | ___ / 4    |
| **TOTAL**         | 22                                                                       | 20/22          | ___ / 22   |

### Overall Status
- **✅ PASS**: 20+ / 22 pass (2 ENHANCEMENT allowed)
- **⚠️ REVIEW**: 17-19 / 22 pass (IMPORTANT issues)
- **❌ REJECT**: < 17 / 22 pass (CRITICAL issues)

---

## Reference Files Quick Link

For detailed evaluation criteria, refer to:

| Check ID                        | Reference File                     |
| ------------------------------- | ---------------------------------- |
| S-01, S-02, Q-07, Q-08          | references/category-structure.md   |
| BP-01, BP-02                    | references/category-structure.md   |
| Q-01 ~ Q-06, Q-09, BP-03, BP-04 | references/category-quality.md     |
| P-01, P-02                      | references/category-patterns.md    |
| Output examples                 | references/common-output-format.md |

---

## Common Failure Patterns & Fixes

| Pattern                  | Detection              | Fix                                                                                          |
| ------------------------ | ---------------------- | -------------------------------------------------------------------------------------------- |
| Invalid YAML syntax      | validate.sh YAML check | Fix indentation and YAML structure in frontmatter                                            |
| Missing sections         | validate.sh S-01 check | Add all 7 required ## sections                                                               |
| Vague output definition  | Q-01 (manual check)    | Add explicit JSON schema or markdown structure                                               |
| No explicit Out of Scope | Q-02 (manual check)    | Add "## Out of Scope" list with "does NOT" statements                                        |
| Free-text instructions   | Q-06 (manual check)    | Replace "Handle X appropriately" with "If X, do Y"                                           |
| Missing review flow      | P-01 (manual check)    | Add "## Review Flow" with Step 1/2/3/4                                                       |
| Non-structured output    | P-02 (manual check)    | Define structured output in common-output-format.md and summarize it in Output Specification |

---

## Validation Command Reference

```bash
# Full validation pipeline

# Execute all automated checks in one step
bash .github/skills/agent-skills-review/scripts/validate.sh SKILL.md

# Verify output JSON shows all checks as PASS or SKIP (not FAIL)
# Example success output:
# {
#   "validation_results": [
#     {"check": "YAML Syntax", "status": "PASS", "detail": ""},
#     {"check": "Structural Completeness", "status": "PASS", "detail": ""},
#     ...
#   ],
#   "overall_status": "PASS"
# }

# If any check status is FAIL, example failure extraction:
# cat /tmp/validation.json | jq '.validation_results[] | select(.status=="FAIL")'

# Then proceed to manual review checklist
```
