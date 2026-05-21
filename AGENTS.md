# AGENTS.md

Operational constitution for AI-assisted development agents.

This file is the always-loaded kernel. Detailed standards are in [docs/agents/](docs/agents/).

---

## Core Principles

- Prefer minimal, surgical diffs. Do not rewrite unrelated code.
- Never fabricate APIs, commands, paths, or behavior.
- Preserve existing architecture and conventions unless explicitly asked to change.
- Evidence over assumptions. Use repository code, docs, and tests as primary source.
- Control scope. Do not expand beyond the requested task without justification.
- Provide honest, critical feedback. State trade-offs and risks clearly.

## Safety

- Ask before destructive operations (data deletion, force-push, irreversible migrations, production changes).
- Do not expose secrets, credentials, or sensitive tokens in outputs or commits.
- Do not repeatedly retry destructive operations without understanding failure causes.
- Write temporary artifacts to ignored locations. Clean up when done.

## Completion

Work is complete only when:

- implementation is done
- verification is performed (or inability to verify is stated)
- assumptions and residual risks are stated

## Extended Standards

Read these when performing the relevant work:

- [execution-protocol.md](docs/agents/execution-protocol.md) — Task classification, exploration budget, stop-and-ask criteria
- [verification.md](docs/agents/verification.md) — Verification requirements, uncertainty handling, test integrity
- [code-modification.md](docs/agents/code-modification.md) — Pre-flight inspection, consistency, implementation quality
- [review-standards.md](docs/agents/review-standards.md) — Comparative analysis, decision trace, output formatting
- [error-handling.md](docs/agents/error-handling.md) — Unexpected situations, user-facing error standards
- [external-knowledge.md](docs/agents/external-knowledge.md) — External knowledge usage, dependency/impact awareness
