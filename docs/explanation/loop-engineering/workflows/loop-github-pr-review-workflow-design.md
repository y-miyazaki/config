# PR Review Workflow Design

Workflow and domain design for the `github-pr-review` entity loop.

| Layer        | Document                                                                                                                           |
| ------------ | ---------------------------------------------------------------------------------------------------------------------------------- |
| Platform     | [Multi-Branch Loops Design](../multi-branch-loops-design.md)                                                                       |
| Caller shell | [Loop Caller Reusable Design](../loop-caller-reusable-design.md) (entity)                                                          |
| Spec         | [Loop `github-pr-review` 設計: PR 初回レビューの自動化](../../../superpowers/specs/2026-10-17-loop-pr-review-design.md)            |
| Boundaries   | [Entity Caller Responsibility Separation](../../../superpowers/specs/2026-08-11-entity-caller-responsibility-separation-design.md) |
| Invariants   | [Loop Engineering Design](../loop-engineering-design.md)                                                                           |

**Artifacts:** `on-loop-github-pr-review.yaml` · skill `github-pr-review` · `detect_pr_review.sh` · `post_review.sh` · `ci-loop-caller-entity.yaml`

Shared caller keys: [Loop Caller Inputs Reference](loop-caller-inputs-reference.md) (entity subset).

## Purpose

Review a pull request once when it is opened or marked ready, and post the result as a single `COMMENT` pull request review (L2). The agent only writes a JSON report; a trusted script posts it after the checker approves. The loop never approves, requests changes, or edits source files.

### Supported use cases

- `pull_request_target` `opened` / `ready_for_review` (see [Rollout](#rollout))
- `workflow_dispatch` with `pr_number` for a manual review; `force` reviews again even when a marker review already exists

### Out of scope

- Fixing the PR from review feedback (see [PR Revise Workflow Design](loop-github-pr-revise-workflow-design.md))
- Approving or requesting changes (the posted event is always `COMMENT`)
- Re-review on every push, fork PRs, draft PRs, and bot-authored PRs
- Issue triage and autofix (see [Issue Triage Workflow Design](loop-github-issue-triage-workflow-design.md) and [Issue Autofix Workflow Design](loop-github-issue-autofix-workflow-design.md))

## Rollout

The caller ships with the `pull_request_target` trigger enabled; the `ci-loop-*` pins already include the fixes below.

Do not dispatch or enable the workflow until a release that contains all of the following platform fixes is pinned in the `ci-loop-*` `uses:` lines of the caller chain (`ci-loop-caller-entity.yaml` → `ci-loop-agent.yaml` → `loop-*` actions):

| Fix        | Change                                                                                                                                             |
| ---------- | -------------------------------------------------------------------------------------------------------------------------------------------------- |
| P1, P2, P4 | `loop-finalize` never pushes for `delivery: none`, deletes the agent branch, and passes `GH_TOKEN` / `GITHUB_REPOSITORY` to `finalize_hook_script` |
| B2         | `loop-finalize` (and `post_review.sh`) always runs at L2/L3 for `delivery: none`; the `finalize_enabled` flag no longer exists                     |
| B3         | `loop-entity-detect` emits `target_json.from.branch`, which `ci-loop-agent` uses as the worktree base branch                                       |
| Meta guard | The `finalize-l2` PR review Meta step acts only on `entity:pr:<n>` handoff keys, before it sources any library, and cannot fail the job            |

With older pins, an APPROVE verdict can merge the agent branch, including `.loop-review/pr-<n>.json`, into the base branch, or the review is never posted (see [Finalize with `delivery: none`](#finalize-with-delivery-none)).

| Stage                 | Action                                                                                                                                                    |
| --------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Before the pin bump   | Do not run the workflow with older pins; the fixes above must be in the pinned release                                                                    |
| After the pin bump    | The trigger is enabled and `zizmor` covers it; do not downgrade the pins                                                                                  |
| Manual dispatch       | Run `workflow_dispatch` from the default branch only; the base checkout, the rules read at base, and `post_review.sh` come from the ref the run starts on |
| Intake gate on enable | `jobs.loop.if` already covers both events; enabling is only uncommenting the trigger                                                                      |

## Caller inputs

Keys are passed in `on-loop-github-pr-review.yaml` via `with:` on `ci-loop-caller-entity.yaml`. Entity subset of [Loop Caller Inputs Reference](loop-caller-inputs-reference.md).

| Input / JSON key             | Description                                                                    | Dogfood value                                                               |
| ---------------------------- | ------------------------------------------------------------------------------ | --------------------------------------------------------------------------- |
| `agent_checker_effort`       | Checker reasoning effort. Only engines with an effort flag (claude) consume it | `medium`                                                                    |
| `agent_checker_instructions` | APPROVE/REJECT rubric (evidence kinds, in-diff lines, base-read evidence)      | Inline in caller workflow                                                   |
| `agent_checker_max_turns`    | Max checker turns                                                              | `100`                                                                       |
| `agent_checker_model`        | Checker model ID                                                               | `claude-opus-5`                                                             |
| `agent_checker_skill_name`   | Checker skill                                                                  | `loop-verifier`                                                             |
| `agent_edit_allowlist`       | File edit allowlist (`**` = unrestricted)                                      | `**`                                                                        |
| `agent_edit_target`          | Agent artifact type (the report file is the only file written)                 | `report`                                                                    |
| `agent_engine`               | AI engine                                                                      | `claude`                                                                    |
| `agent_loop_max_attempts`    | Max Agent→Verify cycles                                                        | `3`                                                                         |
| `agent_maker_effort`         | Maker reasoning effort. Only engines with an effort flag (claude) consume it   | `medium`                                                                    |
| `agent_maker_instructions`   | Domain maker task (review skill, read-only engine review, repo exclusions)     | Inline in caller workflow                                                   |
| `agent_maker_max_turns`      | Max maker turns per attempt                                                    | `100`                                                                       |
| `agent_maker_model`          | Maker model ID                                                                 | `claude-sonnet-5`                                                           |
| `agent_maker_skill_name`     | Skill package                                                                  | `github-pr-review`                                                          |
| `agent_tool_allowlist`       | Read-only tool allowlist for the maker                                         | `gh api -X GET`, `gh issue view`, `gh pr diff`, `gh pr view`, `git show`    |
| `agent_unchanged_verdict`    | Verdict when no file diff (a missing report is a failed run)                   | `REJECT`                                                                    |
| `budget_max_runs_per_day`    | Daily run cap                                                                  | `20`                                                                        |
| `budget_max_tokens_per_day`  | Daily token cap                                                                | `1000000`                                                                   |
| `delivery`                   | Platform delivery (`none` — no push, no PR)                                    | `none`                                                                      |
| `detect_env_json`            | Detect env (`PR_EXCLUDE_LABELS`, and on dispatch `PR_FORCE`, `PR_NUMBER`)      | See [Domain detect environment](#domain-detect-environment-detect_env_json) |
| `detect_script`              | Domain detect script                                                           | `.agents/skills/github-pr-review/scripts/detect_pr_review.sh`               |
| `environment`                | GitHub Environment for env-scoped secrets                                      | `default`                                                                   |
| `finalize_hook_script`       | Trusted post step run once in finalize                                         | `.agents/skills/github-pr-review/scripts/post_review.sh`                    |
| `level`                      | Autonomy                                                                       | `L2`                                                                        |
| `loop_name`                  | Loop identifier                                                                | `github-pr-review`                                                          |
| `state_branch`               | `.loop/*` persistence branch                                                   | `main`                                                                      |

### Domain detect environment (`detect_env_json`)

`PR_EXCLUDE_LABELS` is `no-loop,loop-automation` on every path. `workflow_dispatch` also passes `PR_NUMBER` and `PR_FORCE`:

```yaml
detect_env_json: ${{ github.event_name == 'workflow_dispatch' && format('{{"PR_EXCLUDE_LABELS":"no-loop,loop-automation","PR_FORCE":"{0}","PR_NUMBER":"{1}"}}', inputs.force, inputs.pr_number) || '{"PR_EXCLUDE_LABELS":"no-loop,loop-automation"}' }}
```

Unset `PR_*` values are hydrated from `GITHUB_EVENT_PATH`; on `workflow_dispatch`, missing PR facts come from `gh pr view`.

## Caller shape

```text
on-loop-github-pr-review.yaml
  loop → uses ci-loop-caller-entity.yaml
           detect  → loop-entity-detect (detect_pr_review.sh)
           execute → ci-loop-agent (maker writes .loop-review/pr-<n>.json; checker verifies)
           finalize → delivery none: no push, agent branch always deleted;
                      post_review.sh posts one COMMENT review
           record-skip → budget | circuit_breaker
```

The head is never checked out or executed. The loop runs from the base checkout, and PR facts come from the event payload and read-only `gh` calls. Concurrency group `loop-github-pr-review-<pr>` with `cancel-in-progress: false` and `queue: max`.

## Detect contract

`detect_pr_review.sh` emits `skip: true` when any of these holds: the PR is a draft, a fork PR (head repository differs from base), bot-authored, labeled `no-loop` or `loop-automation`, or a Bot-authored review carrying the marker `<!-- github-pr-review:v1 -->` already exists (unless `PR_FORCE` is `true`). The job `if` in the caller refuses the same classes for `pull_request_target` so no run is queued for them (see [Intake Gating](../loop-engineering-design.md#intake-gating-self-retrigger-prevention)). Detect fails closed: when a required fact cannot be obtained, it emits an error envelope.

When `skip` is `false`, `result` carries `pr_number`, `base_sha`, `head_sha`, `changed_files`, `report_path` (`.loop-review/pr-<n>.json`), and `handoff_key` (`entity:pr:<n>`).

## Skill contract

See `.apm/packages/github/.apm/skills/github-pr-review/SKILL.md` and its `references/`. Summary:

- Findings need one of three evidence kinds: `rule` or `criteria` (verbatim quote from a file that exists at the base commit) or `bug` (diff line plus the concrete failing input or state).
- Severities are `Critical`, `Warning`, `Suggestion`. Pre-existing problems are not reported.
- Rules are read from the base commit with `git show <base_sha>:<path>`, never from the PR head.
- The agent never posts. `gh` is read-only in the maker.

## Posting contract (`post_review.sh`)

`post_review.sh` runs as `finalize_hook_script` in finalize and posts only when the verdict is `APPROVE`.

| Rule                  | Behavior                                                                                                                                                                         |
| --------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Trusted SHAs          | Report `base_sha` / `head_sha` are not trusted. The PR's SHAs come from `gh pr view` and drive evidence checks, all links, and `commit_id`                                       |
| Stale head            | A report `head_sha` that is missing or differs from the PR head posts nothing (the PR moved). A `base_sha` mismatch only warns                                                   |
| Evidence verification | `rule` / `criteria` findings are kept only when `evidence.quote` is an exact substring of `evidence.path` as committed at the trusted base SHA (via `git`, not the working tree) |
| Invalid findings      | Dropped; the review body reports the dropped count                                                                                                                               |
| Finding limit         | At most 20 findings are posted; the most severe are kept (report order breaks ties) and the review body reports the omitted count                                                |
| In-diff placement     | Findings whose lines are in the PR diff are posted inline; others move to the review body                                                                                        |
| Link labels           | A path containing a backtick, bracket, or backslash is rendered as escaped text instead of a code span                                                                           |
| Event                 | Always `COMMENT`; nothing in the report can change it                                                                                                                            |
| Inline failure        | When GitHub rejects the post with HTTP 422, the script retries once with all findings in the body; other failures are not retried                                                |
| Exit status           | Always `0`. Failures emit `::warning::` so finalize does not fail                                                                                                                |

The agent branch holding the report is read by the script from `EXECUTE_BRANCH`.

## Finalize with `delivery: none`

At L2, `loop-finalize` always runs and decides from `delivery: none`. It never pushes the agent branch to the target branch for `none`, deletes the agent branch whatever the verdict (previously only after an empty REJECT), and records the outcome `reported` instead of `pr_created` after APPROVE. The report is persisted only through `finalize_hook_script`, which receives `GH_TOKEN` and `GITHUB_REPOSITORY` from `loop-finalize` and reads the report from the agent branch before it is deleted.

After posting, finalize appends the standard loop Meta (run URL, usage) to the posted marker review via `entity_meta.sh`. Only a Bot-authored review counts as the marker review, here and in detect, so a human who pastes the marker can neither suppress the review nor receive the Meta. The append is a no-op when the marker review is absent and is idempotent when the Meta is already present.

## Related changes

The reply path of [PR Revise Workflow Design](loop-github-pr-revise-workflow-design.md#context-for-replies) reads the parent finding of an inline reply, so a human `@loop` reply on a review finding is understood in context.
