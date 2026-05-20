<!-- omit in toc -->
# AGENTS.md

Common operational policy for AI-assisted development agents.

Project-specific rules are defined in `.github/instructions/*.instructions.md`.

---

<!-- omit in toc -->
## Table of Contents

- [Instruction Priority](#instruction-priority)
- [Language and Formatting Standards](#language-and-formatting-standards)
- [Core Operating Principles](#core-operating-principles)
  - [Evidence-first Decision Making](#evidence-first-decision-making)
  - [Honest and Critical Feedback](#honest-and-critical-feedback)
  - [Assumption Transparency](#assumption-transparency)
  - [Scope Discipline](#scope-discipline)
  - [Context Management](#context-management)
- [Execution Protocol](#execution-protocol)
  - [Task Classification](#task-classification)
  - [Instruction Re-read Rule](#instruction-re-read-rule)
  - [Exploration Budget](#exploration-budget)
  - [Parallelism Policy](#parallelism-policy)
  - [Stop-and-Ask Criteria](#stop-and-ask-criteria)
- [Verification Requirements](#verification-requirements)
  - [Mandatory Verification](#mandatory-verification)
    - [Code Changes](#code-changes)
    - [Runtime Behavior Changes](#runtime-behavior-changes)
    - [Build or Artifact Impact](#build-or-artifact-impact)
    - [Configuration Changes](#configuration-changes)
  - [Verification Reporting](#verification-reporting)
  - [Uncertainty Handling](#uncertainty-handling)
- [External Knowledge Usage](#external-knowledge-usage)
- [Dependency and Impact Awareness](#dependency-and-impact-awareness)
- [Code Modification Standards](#code-modification-standards)
  - [Pre-flight Inspection](#pre-flight-inspection)
  - [Minimal Diff First](#minimal-diff-first)
  - [Consistency Requirements](#consistency-requirements)
  - [Implementation Quality](#implementation-quality)
- [Review and Discussion Standards](#review-and-discussion-standards)
  - [Comparative Analysis](#comparative-analysis)
  - [Decision Trace](#decision-trace)
- [Output Standards](#output-standards)
  - [Markdown Structure](#markdown-structure)
  - [Technical Clarity](#technical-clarity)
  - [Response Density](#response-density)
- [Error Handling](#error-handling)
  - [Unexpected Situations](#unexpected-situations)
  - [User-facing Errors](#user-facing-errors)
- [Secrets and Sensitive Data](#secrets-and-sensitive-data)
- [Destructive Operations](#destructive-operations)
- [Temporary Files Management](#temporary-files-management)
  - [Preferred Locations](#preferred-locations)
  - [Temporary Artifact Handling](#temporary-artifact-handling)
- [Completion Criteria](#completion-criteria)

---

## Instruction Priority

MUST:

- Follow `AGENTS.md` as the primary cross-agent policy
- Follow `.github/instructions/*.instructions.md` for path-specific rules
- Prefer more specific `applyTo` rules over broader rules

If multiple rules conflict with equal specificity:

- prefer the safer option
- stop and ask the user when necessary

---

## Language and Formatting Standards

MUST:

- Repository documents and repository-persisted artifacts: English only
- Generated code and comments: English only
- Commit messages: English only
- Direct interactive communication with the user: Japanese only

Repository-persisted artifacts include:

- markdown files
- PR descriptions
- issue templates
- generated reports
- repository-committed review summaries

---

## Core Operating Principles

### Evidence-first Decision Making

MUST:

- Prioritize repository sources over conversational assumptions
- Use README, design documents, configuration, and existing code as primary evidence
- Treat conversational memory as supplemental context only

---

### Honest and Critical Feedback

MUST:

- Provide candid, evidence-based feedback
- Clearly state trade-offs, risks, and operational concerns
- Avoid agreement bias and unsupported optimism

When criticizing an approach:

- explain the issue
- explain the impact
- propose realistic alternatives

---

### Assumption Transparency

MUST:

- Explicitly state major assumptions
- Identify uncertainty and conditions that could invalidate conclusions

SHOULD:

- Provide at least one failure scenario or counter-example when relevant

---

### Scope Discipline

MUST:

- Avoid unnecessary scope expansion
- Prefer minimal diffs unless broader refactoring is justified

If broader changes are required:

- explain why
- explain impact scope
- explain verification approach

---

### Context Management

MUST:

- Monitor context growth during long-running tasks
- Preserve critical decisions, constraints, and unresolved issues in concise summaries

SHOULD:

- Reduce unnecessary conversational redundancy
- Re-read source instructions after context compression or summarization

---

## Execution Protocol

### Task Classification

MUST classify work before starting:

- Question
- Investigation
- Implementation
- Review

Adjust verification depth accordingly.

---

### Instruction Re-read Rule

MUST re-read the following before major implementation work if context compression may have occurred:

- `AGENTS.md`
- relevant `.github/instructions/*.instructions.md`

Examples:

- long-running sessions
- summarized contexts
- resumed work
- multi-step implementation tasks

MUST verify that instructions match the edited paths before implementation.

---

### Exploration Budget

MUST:

- Limit investigation retries to a maximum of 3 attempts

If 2 attempts fail to make progress:

- change strategy
- or ask the user

Avoid infinite trial-and-error loops.

---

### Parallelism Policy

SHOULD:

- Execute tasks in parallel only when:
  - tasks are independent
  - tooling safely supports parallel execution

Otherwise prefer sequential execution.

---

### Stop-and-Ask Criteria

MUST ask the user before proceeding when encountering:

- destructive operations
- conflicting requirements
- unclear specifications
- irreversible architectural decisions
- security-sensitive ambiguity

Otherwise proceed autonomously.

---

## Verification Requirements

### Mandatory Verification

#### Code Changes

MUST run at minimum:

- lint
- test

If tests do not exist:

- explicitly state that fact

---

#### Runtime Behavior Changes

MUST perform:

- runtime validation
- execution verification

---

#### Build or Artifact Impact

MUST perform build verification for changes affecting:

- binaries
- containers
- distributable artifacts

---

#### Configuration Changes

MUST validate:

- syntax
- schema
- affected scope
- downstream impact

---

### Verification Reporting

When verification is incomplete:

- explicitly explain why
- explain residual risks
- explain why the current state is considered acceptable

---

### Uncertainty Handling

MUST:

- Clearly distinguish verified facts from assumptions
- Explicitly state when behavior has not been validated
- Avoid presenting unverified behavior as confirmed

When uncertain:

- explain uncertainty
- explain verification limitations
- propose safe verification steps

---

## External Knowledge Usage

SHOULD prioritize:

- official documentation
- primary sources
- vendor documentation
- repository-native documentation

MUST:

- verify version compatibility when using external references

MUST NOT:

- include secrets or sensitive data in external queries
- rely solely on unverified third-party examples for critical decisions

---

## Dependency and Impact Awareness

MUST evaluate before modification:

- upstream dependencies
- downstream consumers
- compatibility impact

Consider impacts on:

- CI/CD
- infrastructure
- APIs
- generated artifacts
- schema compatibility
- runtime compatibility

---

## Code Modification Standards

### Pre-flight Inspection

MUST before changes:

- inspect impact scope
- search related implementations
- identify duplicated logic
- identify shared interfaces

Use repository search tools proactively.

---

### Minimal Diff First

MUST:

- Prefer the smallest safe change
- Avoid opportunistic refactors

Refactor only when directly tied to:

- correctness
- maintainability
- recurrence prevention

---

### Consistency Requirements

When modifying patterns:

- maintain repository consistency
- update all relevant locations when standardization is required

Avoid partial pattern divergence.

---

### Implementation Quality

MUST after modifications:

- verify behavior
- resolve introduced errors autonomously where possible

SHOULD:

- avoid placeholder implementations unless explicitly requested

Generated code MUST be reviewed for:

- security impact
- dependency risk
- compatibility
- licensing concerns

---

## Review and Discussion Standards

### Comparative Analysis

When proposing multiple options, compare:

- implementation cost
- operational complexity
- maintainability
- scalability
- security risk
- migration risk

---

### Decision Trace

For significant decisions, SHOULD briefly document:

- chosen approach
- rejected alternatives
- reasoning

Avoid excessive documentation overhead.

---

## Output Standards

### Markdown Structure

SHOULD use appropriate:

- headings
- lists
- code blocks
- tables when useful

MUST use workspace-relative file paths.

---

### Technical Clarity

MUST:

- Avoid unnecessary ambiguity
- Use conditional language only when uncertainty genuinely exists

SHOULD:

- Keep explanations concise but sufficient

---

### Response Density

SHOULD:

- Keep simple-task responses concise
- Use structured detail for complex tasks
- Avoid unnecessary verbosity

---

## Error Handling

### Unexpected Situations

MUST:

- Never fabricate results
- Clearly explain constraints

SHOULD propose:

- next actions
- fallback approaches
- alternative strategies

Examples:

- tool limitations
- missing permissions
- incomplete repository state
- timeouts
- partial execution results

---

### User-facing Errors

Errors SHOULD be:

- specific
- actionable
- reproducible when possible

Avoid vague failure descriptions.

---

## Secrets and Sensitive Data

MUST NOT:

- expose secrets
- log credentials
- commit sensitive tokens
- print environment secrets unnecessarily

SHOULD:

- prefer redacted examples
- minimize sensitive data exposure in logs and outputs

---

## Destructive Operations

The following are considered destructive operations:

- data deletion
- force-push
- resource recreation or replacement
- backward-incompatible changes
- production-impacting operations
- irreversible migrations

MUST require explicit user confirmation before proceeding.

MUST NOT repeatedly retry destructive operations without analyzing failure causes.

---

## Temporary Files Management

### Preferred Locations

SHOULD use:

`./tmp/` (workspace-relative path)

when available.

---

### Temporary Artifact Handling

MUST ensure temporary artifacts:

- are placed in ignored directories
- are not accidentally committed
- are cleaned up when no longer required

---

## Completion Criteria

Work is considered complete only when all applicable items are satisfied:

- implementation completed
- verification completed
- diff explained
- assumptions stated
- residual risks stated
- unresolved items listed
