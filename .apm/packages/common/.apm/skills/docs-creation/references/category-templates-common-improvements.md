## improvements

Templates are guidance and review rubrics, not rigid prose generators.
Adapt structure and depth to the repository and context.
Remove sections that cannot be populated with concrete information.

**Depth guidance:** Document all planned, in-progress, and completed improvements with concrete impact assessment. Include specific metrics or indicators of success. For projects with active tech debt, list every known item with its operational consequence.

```markdown
# Improvements

<!-- Answer: What improvements are planned or completed? Source: read issues, project boards, recent PRs, tech debt comments. -->

Focus on:
- operational impact and risk reduction
- architectural improvements
- technical debt with concrete consequences

Avoid:
- vague wishlist items without measurable justification
- items that belong solely in an issue tracker with no architectural context

## Improvement Priorities

<!-- Answer: What are the current pain points? Source: read recent incidents, performance issues, developer friction points. -->

## Planned Improvements

<!-- Answer: What is being worked on or planned? Source: read open issues, project roadmap. -->

| Title | Priority | Impact | Status |
| ----- | -------- | ------ | ------ |

## Completed Improvements

<!-- Answer: What was recently improved? What was the outcome? Source: read recent merged PRs, changelog. -->

| Date | Improvement | Outcome |
| ---- | ----------- | ------- |

## Deferred or Rejected (Optional)

<!-- Answer: What was considered but not pursued? Why? -->

| Proposal | Reason |
| -------- | ------ |

## Decision Prompts

Consider:
- Which improvements reduce operational risk most?
- Which technical debt blocks future changes?
- Which improvements increase long-term maintainability?
```
