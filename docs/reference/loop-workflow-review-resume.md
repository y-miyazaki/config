# Loop Workflow Review — Session Resume Guide

Use this file to continue the Loop Engineering review and implementation plan in a new agent session.

## Plan document

Full plan (all sections, todos, roadmap):

- [Loop Workflow Review Plan](loop-workflow-review-plan.md)

## Suggested prompt (copy into a new session)

```text
docs/reference/loop-workflow-review-plan.md と loop-workflow-review-resume.md を読み、
Loop Workflow レビュー計画の続きを実装する。

未完了 todo のうち Phase 0 / P0 を優先:
- loop-detect / loop-config-pack（caller 簡略化）
- loop-run-log（Phase 0b）
- skip_reason 統一（should_run + skip_reason）
- .loop/loop-budget.json

計画にない変更は行わない。各 Phase 完了後に plan の todo status を更新すること。
```

## Context files (read first)

| File | Purpose |
|------|---------|
| [loop-workflow-review-plan.md](loop-workflow-review-plan.md) | Master plan |
| [loop-engineering-design.md](../explanation/loop-engineering-design.md) | Design invariants, roadmap |
| [loop-engineering-checklist.md](loop-engineering-checklist.md) | Operational checklist |
| [.github/workflows/on-loop-docs-triage.yaml](../../.github/workflows/on-loop-docs-triage.yaml) | Current caller workflow |
| [.github/workflows/ci-loop-agent.yaml](../../.github/workflows/ci-loop-agent.yaml) | Reusable agent engine |
| [.github/actions/loop-detect/action.yml](../../.github/actions/loop-detect/action.yml) | Detect phase (domain-agnostic) |
| [.github/actions/loop-prompt-generate/action.yml](../../.github/actions/loop-prompt-generate/action.yml) | Prompt assembly (constraints + caller instructions) |
| [.github/actions/loop-finalize/action.yml](../../.github/actions/loop-finalize/action.yml) | Finalize / PR / state |

## Todo checklist (snapshot)

| ID | Task | Priority |
|----|------|----------|
| validate-docs-triage | L2 運用継続・メトリクス収集 | Phase 0 |
| loop-run-log | `.loop/loop-run-log.md` JSONL 追記 | Phase 0b / P0 |
| simplify-loop-caller | loop-config-pack, skip_reason, allowlist 単一化 | **done** |
| loop-budget-policy | `.loop/loop-budget.json` + detect 予算チェック | **done** |
| loop-usage-capture | CLI から model/tokens 実測 | Phase 1c |
| scaffold-on-loop | on-loop スキャフォールド（inline env、prompt_file 未採用） | **done** |
| implement-acting-on | acting_on 競合検知 | Phase 2 |
| simplify-loop-finalize | finalize の二重 state-write 統合 | P1 |
| hard-gate-pattern | ci-sweeper 向け Hard Gate | Phase 3b |
| loop-execute-contract-tests | loop-execute 契約テスト | Phase 4 |
| second-loop | changelog-loop または ci-sweeper-loop | Phase 3 |

## Key decisions (do not re-litigate)

1. **docs-triage L2** — production-ready; no blocker for current operation
2. **Hard Gate** — caller-side or optional input for code loops; not mandatory inside loop-execute for all loops
3. **Cost tracking** — run log only for usage; state JSON stays minimal
4. **Budget file** — `.loop/loop-budget.json` only (not MD)
5. **Skip semantics** — `should_run` + `skip_reason` enum（implemented in loop-detect）
6. **Inline-first caller config** — criteria/allowlist in workflow `env`, not external files (`.github/loop/*/criteria.md`, `prompt_file` deferred for this distribution repo)
7. **Domain isolation in actions** — `loop-detect` / `loop-prompt-generate` must not embed domain vocabulary; caller supplies `LOOP_PROMPT_INSTRUCTIONS`; generic constraints (level, allowlist, L2+ persistence) live in `loop-prompt-generate`. `loop-worktree-push` removed (superseded by `loop-execute` internal push/cleanup)

## External references

- [loop-budget.md](https://github.com/cobusgreyling/loop-engineering/blob/main/loop-budget.md)
- [loop-run-log.md](https://github.com/cobusgreyling/loop-engineering/blob/main/loop-run-log.md)

## Session history

- Initial review: external LLM review validated against implementation
- Added: cost/token tracking (Section 7), simplification analysis (Section 8)
- Saved to repo: 2026-07-10
