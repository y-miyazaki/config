# Loop Detect Hook Removal Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** loop のスクリプトの入力を `detect_script` と `finalize_script` の2つにする。基本線の外にある `detect_hook_script` と、triage の `on_detect_dispatch.sh`、detect の出力の `dispatch_*` を削除し、`triage:ready` での triage の起動をやめる。

**Architecture:** 削除だけで、新しい部品はない。`loop-entity-detect` から hook の入力と実行を消し、`ci-loop-caller-entity.yaml` と triage の caller から受け渡しを消す。triage の skill から `scripts/hooks/` と `should_request_dispatch` を消し、APM で同期する。autofix の `repository_dispatch` の起動は残す(外部や手動の入口)。

**Tech Stack:** GitHub Actions(reusable workflow、composite action)、bash、jq、bats、python3(topology の gate)。

**Spec:** `docs/superpowers/specs/2026-10-18-loop-detect-hook-removal-design.md`。spec の行番号は配信の実装(`feat/loop-delivery-message`、HEAD `776fee9f`)の後でずれている。この plan の行番号は HEAD で確かめた値である。

## Global Constraints

- 互換の処理は作らない(破壊的変更。`detect_hook_script` を渡す外部の caller は GitHub が起動時に拒否する)。
- `triage:ready` は triage の起動の許可リスト(job の `if`)から外す。`finalize_label_allowlist` には残す(エージェントが `message_labels.json` で付ける。parity の8つの一致のテストは変えない)。
- `detect_issue.sh` の `should_skip_issue` は変えない(`triage:ready` の Issue は今までどおりスキップ)。`result` から消えるのは `dispatch_requested`・`dispatch_event_type`・`dispatch_client_payload` の3つだけで、ほかのキーと順序は変えない。
- autofix の caller(`on-loop-github-issue-autofix.yaml`)と skill は変えない。
- grep の gate: 作業の後、`git grep -inE "detect_hook|on_detect_dispatch|dispatch_requested|dispatch_event_type|dispatch_client_payload|should_request_dispatch" -- . ':!.loop' ':!CHANGELOG.md' ':!docs/superpowers'` の出力は、`test/bats/github-actions/loop-caller-parity.bats` の `old_names` の1行だけ。**テストにもこの名前を書かない**(大文字小文字を区別しない。`DETECT_HOOK_SCRIPT` も当たる)。不在の検査は、入力の一覧の完全一致と `startswith("dispatch_")` で書く。
- 配布する skill は `.apm/packages/github/.apm/skills/github-issue-triage/` だけを編集し、`bash scripts/self/apm/sync_apm_artifacts.sh` で `.agents/skills/github-issue-triage/` と `.claude/skills/github-issue-triage/` に同期する(`apm_modules/` は追跡していない)。パッケージの文言は portable にする(Loop の platform の名前、caller や action の名前を書かない。`.apm/CLAUDE.md`)。SKILL.md の version は 0.1.5 のまま(このブランチで main の 0.1.4 から上げ済みで、未リリース)。
- シェルの変更には bats を対にする(`.claude/rules/bats.md`)。`shfmt` と `prettier` は PostToolUse フック、`shellcheck`・`actionlint`・`markdownlint` などは Stop フックが実行する。**実装者は直接実行しない**(結果はフックの出力で見る)。
- 作業ツリーに無関係の変更がある(`.claude/settings.json`、`.cursor/mcp.json`、`.mcp.json`、`apm.lock.yaml`、`.claude/worktrees/`)。コミットは**明示したパスだけ**を stage する。`git add -A` は対象のディレクトリを指定したときだけ使い、リポジトリ全体には使わない。`apm.lock.yaml` は Task 2 の手順の patch でだけ stage する。
- 一時ファイルは `tmp/` に置き、使い終えたら消す。
- `ci-*` から `./.github/...` を参照しない。pin は変えない。リリースと pin の更新、GitHub Actions のワークフローの実行(dogfood)は、この plan に含めない。push しない。

## Review Focus

1. **`triage:ready` を外す場所。** 起動の `if`(`on-loop-github-issue-triage.yaml:73`)からだけ外し、`finalize_label_allowlist`(`:147`)には残すこと。後者を消すと、エージェントの `mark_ready` が許可リストの外として黙って捨てられる。Task 1 に `triage caller intake admits needs-triage and triage:needs-info labels only` を置き、既存の `triage caller delivers issue_comment with the label allowlist` は変えずに通す。
2. **detect の結果の形。** `build_result_json` の if/else を1つにしたとき、`dispatch_*` 以外のキーの並びと値が変わらないこと。Task 2 の既存の facts のテスト(`emits facts for human opened issue` ほか)と、`triage:ready`+`autofix` の `labeled` で `skip == true` かつ `dispatch_` で始まるキーがないことのテストで見る。
3. **gate とテストの綴り。** テストで削除した名前を綴ると gate が落ちる。`loop-entity-detect.bats` の入力の一覧から行を消すだけにし、ヘッダーは「post-detect hook input」と書く。`detect_issue.bats` は `startswith("dispatch_")` で検査する。
4. **`apm.lock.yaml` の patch。** 無関係の既存の変更(`generated_at`、`mcp-server-fetch==`、`mcp-compressor==`)の hunk を含めないこと。Task 2 Step 6 の検査で、残った `+`/`-` の行が triage の skill のものだけであることを確かめる。
5. **`ISSUE_LABEL_NAME` の後始末。** 読むのは `should_request_dispatch` だけである(`detect_issue.sh:370`、`:375`)。代入(`:178`、`:588`)とヘッダー(`:33`)も消し、使われない変数を残さない。

---

## ファイル構成

| ファイル                                                                                                                                                                                                                       | 責務                                                  | Task |
| ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ----------------------------------------------------- | ---- |
| `.github/actions/loop-entity-detect/action.yml`、`lib/detect.sh`                                                                                                                                                               | 入力、env、hook の実行の削除                          | 1    |
| `.github/workflows/ci-loop-caller-entity.yaml`、`scripts/self/ci/loop_input_topology.py`                                                                                                                                       | 入力と受け渡し、decision table の削除                 | 1    |
| `.github/workflows/on-loop-github-issue-triage.yaml`                                                                                                                                                                           | hook の削除、起動の許可リスト、コメント、maker の指示 | 1    |
| `test/bats/github-actions/loop-entity-detect.bats`、`loop-caller-parity.bats`、`test/bats/.github/actions/loop-entity-detect/lib/detect_dispatch_hook.bats`(削除)                                                              | 入力の一覧、`old_names`、triage の起動                | 1    |
| `.apm/packages/github/.apm/skills/github-issue-triage/`(`scripts/hooks/` の削除、`detect_issue.sh`、`SKILL.md`、`references/category-fsm.md`)と同期先                                                                          | dispatch の出力と記述の削除                           | 2    |
| `test/bats/.apm/packages/github/github-issue-triage/detect_issue.bats`、`on_detect_dispatch.bats`(削除)                                                                                                                        | detect の出力                                         | 2    |
| `docs/explanation/loop-engineering/loop-engineering-design.md`、`workflows/loop-caller-inputs-reference.md`、`workflows/loop-github-issue-triage-workflow-design.md`、`workflows/loop-github-issue-autofix-workflow-design.md` | 設計と入力の記述                                      | 3    |

---

### Task 1: `detect_hook_script` を platform と caller から削除する

**Files:**

- Modify: `.github/actions/loop-entity-detect/action.yml:44-47`(入力 `detect_hook_script`)、`:60`(`github_token` の説明の「the detect hook」)、`:127`(env `DETECT_HOOK_SCRIPT`)
- Modify: `.github/actions/loop-entity-detect/lib/detect.sh:17`(Design Rules の hook の行)、`:26`(Optional environment)、`:56`(グローバル)、`:60-110`(`resolve_detect_hook_script` とその doc ブロック)、`:184`(`main` の Globals)、`:237`(コメント)、`:254-264`(hook の実行)
- Modify: `.github/workflows/ci-loop-caller-entity.yaml:133-137`(入力)、`:310`(`loop-entity-detect` への受け渡し)
- Modify: `.github/workflows/on-loop-github-issue-triage.yaml:40-44`(コメント)、`:73`(起動の許可リスト)、`:121`(maker の指示)、`:137-138`(空行と `detect_hook_script`)
- Modify: `scripts/self/ci/loop_input_topology.py:94`(`DECISIONS` の `detect_hook_script`。`DETECT_REQUIRED` には入っていない)
- Delete: `test/bats/.github/actions/loop-entity-detect/lib/detect_dispatch_hook.bats`
- Test: `test/bats/github-actions/loop-entity-detect.bats:9`、`:82-105`、`:128-140`;`test/bats/github-actions/loop-caller-parity.bats:923-935`、`:975-1005`

**Interfaces:** Produces: `loop-entity-detect` の入力は18個(`detect_hook_script` がない)、Detect Entity Target の env は `DETECT_HOOK_SCRIPT` がない。`ci-loop-caller-entity.yaml` の `workflow_call` の入力は `ci-loop-caller.yaml` の部分集合になる(topology の行は51から50)。

- [ ] **Step 1: 失敗するテストを書く。**
  - `loop-entity-detect.bats`:
    - `@test "action.yml declares exactly the renamed inputs"`(`:82`)の期待値から `detect_hook_script` の行(`:94`)を消す。
    - `@test "action.yml maps every renamed input to its uppercase environment variable"`(`:128`)の一覧(`:131`)から `detect_hook_script` を消し、`[ "${checked}" -eq 9 ]`(`:136`)を `8` にする。
    - ヘッダーの `:9` を `# - action.yml declares the renamed inputs and no removed inputs (may_edit, write_target, dispatch_hook_*, the post-detect hook input)` にする(gate のため、削除した名前を綴らない)。
  - `loop-caller-parity.bats`:
    - `old_names` の最後の行(`:934`)を `DETECT_DOMAIN_ENV_JSON ENGINE finalize_hook_script FINALIZE_HOOK_SCRIPT detect_hook_script DETECT_HOOK_SCRIPT` にする(2つの名前は必ずこの1行に置く。gate が許すのはこの行だけ)。
    - `@test "triage maker instructions point at the message directory"`(`:999`)の最後の行の前に `[[ ${block} != *'platform hook'* ]]` を足す。
    - `triage caller grants no write gh commands to the agent` の後に足す:

      ```bash
      @test "triage caller intake admits needs-triage and triage:needs-info labels only" {
          local wf="${ROOT}/.github/workflows/on-loop-github-issue-triage.yaml" gate
          gate="$(awk '/^    if: >-$/ {f=1; next} f && /^    uses:/ {exit} f {print}' "${wf}")"
          [ -n "${gate}" ]
          grep -qF "fromJSON('[\"needs-triage\",\"triage:needs-info\"]')" <<<"${gate}"
          [[ ${gate} != *'triage:ready'* ]]
      }
      ```

  - `git rm test/bats/.github/actions/loop-entity-detect/lib/detect_dispatch_hook.bats`。
- [ ] **Step 2: 失敗を確認する。** `bats test/bats/github-actions/loop-entity-detect.bats test/bats/github-actions/loop-caller-parity.bats`。Expected: FAIL(`declares exactly the renamed inputs`、`maps every renamed input`、`reusable workflows use no pre-rename input or env names`(`old_names`)、`triage caller intake ...`、`triage maker instructions ...`)。
- [ ] **Step 3: platform から削除する。**
  - `action.yml`: `:44-47` と `:127` を消す。`:60` を `description: Resolved GitHub token for detect scripts and API calls` にする。
  - `detect.sh`: `:17` を消す。`:26` を `#   GITHUB_TOKEN (detect token)` にする。`:56`、`:60-110`(`resolve_detect_hook_script` の doc ブロックの `#######` から関数の後の空行まで)、`:254-264`(コメントの行から `fi` の後の空行まで)を消す。`:184` を `#   GITHUB_TOKEN` にする。`:237` を `# Validate the entity kind and target before writing outputs.` にする。
  - `ci-loop-caller-entity.yaml`: `:133-137`(`detect_hook_script:` のブロック5行)と `:310` を消す。
  - `loop_input_topology.py`: `:94` を消す(入力を消すのと同じコミットにする。片方だけだと gate が「entry names no input」で落ちる)。
- [ ] **Step 4: triage の caller を直す。**
  - `:137-138`(`detect_env_json` の後の空行と `detect_hook_script:`)を消す。
  - `:73` を `fromJSON('["needs-triage","triage:needs-info"]'),` にする。
  - `:40-44` のコメントを次にする:

    ```yaml
    # Label allowlist is intake-only — classification labels the agent itself
    # applies (bug/feature/question/documentation) must stay out, and so must
    # triage:ready (detect skips it, so admitting it only queues skipped runs).
    # autofix is owned by on-loop-github-issue-autofix.yaml and must not
    # double-intake here.
    ```

  - `:121` を `no leading "---". Do not open PRs or call repository_dispatch.` にする。
  - checker の指示(`:101`、`:109`)の `repository_dispatch` の項目は残す(エージェントへの禁止で、hook とは関係がない)。
- [ ] **Step 5: 通ることを確認する。**
  - `bats test/bats/github-actions/loop-entity-detect.bats test/bats/github-actions/loop-caller-parity.bats test/bats/.github/actions/loop-entity-detect/lib/entity_target.bats test/bats/scripts/self/ci/loop_input_topology.bats`。Expected: PASS。
  - `python3 -I scripts/self/ci/loop_input_topology.py . > /dev/null; echo $?`。Expected: `0`。
  - `git grep -in -e detect_hook -e on_detect_dispatch -- .github scripts test/bats/github-actions test/bats/.github`。Expected: `test/bats/github-actions/loop-caller-parity.bats:934` の1行だけ。
  - triage の caller が消した入力を渡していないことは Stop フックの actionlint(ローカルの reusable を参照するので未定義の入力を検出する)の結果で見る。
- [ ] **Step 6: コミットする。** `git add .github/actions/loop-entity-detect/action.yml .github/actions/loop-entity-detect/lib/detect.sh .github/workflows/ci-loop-caller-entity.yaml .github/workflows/on-loop-github-issue-triage.yaml scripts/self/ci/loop_input_topology.py test/bats/github-actions/loop-entity-detect.bats test/bats/github-actions/loop-caller-parity.bats`(`detect_dispatch_hook.bats` の削除は Step 1 の `git rm` で stage 済み)。`git diff --cached --name-status` に上の7ファイルと `D test/bats/.github/actions/loop-entity-detect/lib/detect_dispatch_hook.bats` だけがあることを確かめる。`refactor(loop): remove detect_hook_script from loop-entity-detect and the entity caller`。

---

### Task 2: triage の skill から dispatch の hook と出力を削除する

**Files:**

- Delete: `.apm/packages/github/.apm/skills/github-issue-triage/scripts/hooks/on_detect_dispatch.sh`、`scripts/hooks/README.md`
- Modify: `.apm/packages/github/.apm/skills/github-issue-triage/scripts/detect_issue.sh:33`(`ISSUE_LABEL_NAME` の説明)、`:178`(代入)、`:328-381`(`should_request_dispatch` とその doc ブロック)、`:460-496`(`build_result_json` の if/else)、`:588`(代入)
- Modify: `.apm/packages/github/.apm/skills/github-issue-triage/SKILL.md:33`、`:38`
- Modify: `.apm/packages/github/.apm/skills/github-issue-triage/references/category-fsm.md:20`
- 変えない: `evals/tasks/*.yaml`、`references/common-checklist.md:38`(「エージェントは dispatch しない」の記述。spec のとおり)
- Delete: `test/bats/.apm/packages/github/github-issue-triage/on_detect_dispatch.bats`
- Test: `test/bats/.apm/packages/github/github-issue-triage/detect_issue.bats:10`、`:62-71`、`:132-156`、`:168-194`、`:218-241`
- Sync: `bash scripts/self/apm/sync_apm_artifacts.sh`(`.agents/skills/github-issue-triage/`、`.claude/skills/github-issue-triage/`、`apm.lock.yaml`)

**Interfaces:** Produces: `detect_issue.sh` の `result` は `handoff_key`・`entity`・`issue_number`・`title`・`body`・`labels`・`event_name`・`event_action`・`comment_id`・`actor`・`actor_type` だけ(すべての event で同じ形)。skill に `scripts/hooks/` がない。

- [ ] **Step 1: 失敗するテストを書く(`detect_issue.bats`)。**
  - `DETECT_SCRIPT=` の行の後に `NO_DISPATCH_FIELDS='([.result | keys[] | select(startswith("dispatch_"))] == [])'` を置く。
  - ヘッダーの `:10` を `# - emits no dispatch_* fields for any event (autofix starts from its own intake)` にする。
  - `:62` のテストを `@test "emits result.entity.kind issue and no dispatch fields when triage:ready is labeled with autofix present"` にし、jq を `".result.entity.kind == \"issue\" and ${NO_DISPATCH_FIELDS}"` にする。
  - `:143` のテストを `@test "skips triage:ready labeled with autofix present and emits no dispatch fields"` にし、jq を `".skip == true and ${NO_DISPATCH_FIELDS}"` にする。
  - `:132`、`:168`、`:182`、`:218`、`:229` の `omits dispatch flags ...` の5件は、`(.result.dispatch_requested // false) != true` を `${NO_DISPATCH_FIELDS}` に置き換える(`.skip == true` の条件はそのまま。jq の引数は二重引用符にする)。
  - 足す: `@test "skill ships no scripts/hooks directory"` — `[ ! -e "$(apm_skill_dir github-issue-triage)/scripts/hooks" ]`。
  - `git rm test/bats/.apm/packages/github/github-issue-triage/on_detect_dispatch.bats`。
  - `grep -inE 'dispatch_requested|dispatch_event_type|dispatch_client_payload' test/bats/.apm/packages/github/github-issue-triage/detect_issue.bats`。Expected: 出力がない。
- [ ] **Step 2: 失敗を確認する。** `bats test/bats/.apm/packages/github/github-issue-triage/detect_issue.bats`。Expected: FAIL(`:62` と `:143` の2件と `ships no scripts/hooks directory`)。
- [ ] **Step 3: skill のスクリプトを直す。**
  - `git rm -r .apm/packages/github/.apm/skills/github-issue-triage/scripts/hooks`。
  - `detect_issue.sh`:
    - `:328-381`(`should_request_dispatch` の doc ブロックの `#######` から関数の後の空行まで)を消す。
    - `build_result_json` の `local comment_id payload` を `local comment_id` にし、if/else を else の側の `json_object ...`(`handoff_key` から `actor_type` まで)1つにする。
    - `:33`、`:178`、`:588` の `ISSUE_LABEL_NAME` を消す(Review Focus 5)。
- [ ] **Step 4: skill の記述を直す(portable な文言)。**
  - `SKILL.md:33`(USE FOR の dispatch の行)を消す。dispatch はこの skill の用途ではなく、禁止は `:38` にある。
  - `SKILL.md:38` を `- Firing \`repository_dispatch\` or starting github-issue-autofix (autofix starts only from a human action, such as adding the \`autofix\` label)` にする。
  - `category-fsm.md:20` の最後の文を `The Agent must **not** fire \`repository_dispatch\` or start github-issue-autofix intake; autofix remains a human-triggered follow-up via the \`autofix\` label.` にする(「or trusted platform hooks」を消す)。
- [ ] **Step 5: 同期して、通ることを確認する。**
  - `bash scripts/self/apm/sync_apm_artifacts.sh`。Expected: exit 0。
  - `test ! -e .agents/skills/github-issue-triage/scripts/hooks && test ! -e .claude/skills/github-issue-triage/scripts/hooks && echo pruned`。Expected: `pruned`。残っていれば同期先を手で消さず、BLOCKED として報告する。
  - `bats test/bats/.apm/packages/github/github-issue-triage/`。Expected: PASS(`detect_issue.bats`、`issue_comment.bats`、`label_fsm.bats`)。
  - `bash scripts/self/apm/check_loop_pr_body_contract.sh`。Expected: exit 0。
  - `git grep -inE "detect_hook|on_detect_dispatch|dispatch_requested|dispatch_event_type|dispatch_client_payload|should_request_dispatch" -- .apm .agents .claude test/bats/.apm`。Expected: 出力がない。
- [ ] **Step 6: コミットする(2回)。**
  1. skill と同期先: `git add -A .apm/packages/github/.apm/skills/github-issue-triage .agents/skills/github-issue-triage .claude/skills/github-issue-triage test/bats/.apm/packages/github/github-issue-triage`。`git diff --cached --name-status` に `apm.lock.yaml` と無関係のファイルがないことを確かめる。`refactor(github-issue-triage): drop the detect dispatch hook and dispatch fields`。
  2. `apm.lock.yaml` の skill の hunk だけ:

     ```bash
     mkdir -p tmp
     git diff -U0 apm.lock.yaml > tmp/apm-lock-full.diff
     awk '
     function flush() { if (hunk != "" && keep) out = out hunk; hunk = "" }
     /^@@/ { flush(); hunk = $0 "\n"; keep = 0; next }
     hunk != "" { hunk = hunk $0 "\n"; if ($0 ~ /^[-+]/ && $0 !~ /^[-+]generated_at:/ && $0 !~ /mcp-server-fetch==/ && $0 !~ /mcp-compressor==/) keep = 1; next }
     { header = header $0 "\n" }
     END { flush(); printf "%s%s", header, out }
     ' tmp/apm-lock-full.diff > tmp/apm-lock-skill.patch
     grep '^[-+]' tmp/apm-lock-skill.patch | grep -v '^\(---\|+++\) ' \
       | grep -v -e 'github-issue-triage' \
         -e '^[-+]  \(target\|runtime\|scope\|owners\|active_owner\|content_hash\):' \
         -e '^[-+]  - \./\.apm/packages/github$' -e '^[-+]- kind: project-relative$'
     ```

     Expected: 最後の `grep` の出力がない(残った行は triage の skill の配置とハッシュだけ)。出力があれば stage せずに報告する。続けて `git apply --cached --unidiff-zero tmp/apm-lock-skill.patch`、`git diff --cached --name-only` が `apm.lock.yaml` だけであること、`git diff --cached apm.lock.yaml | grep -c -e generated_at -e mcp-server-fetch -e mcp-compressor` が `0` であることを確かめる。`chore(apm): sync lock for github-issue-triage detect hook removal`。最後に `rm -f tmp/apm-lock-full.diff tmp/apm-lock-skill.patch`。

---

### Task 3: docs から hook を消す

**Files:**

- Modify: `docs/explanation/loop-engineering/loop-engineering-design.md:579`(Intake の表の triage の行)、`:585`(`triage:ready` を例外とする段落)
- Modify: `docs/explanation/loop-engineering/workflows/loop-caller-inputs-reference.md:37`(流れの図)、`:372-377`(「Inputs only it accepts」の節)
- Modify: `docs/explanation/loop-engineering/workflows/loop-github-issue-triage-workflow-design.md:34`(`labeled` の起動)、`:74`(入力の表の行)
- Modify: `docs/explanation/loop-engineering/workflows/loop-github-issue-autofix-workflow-design.md:22`、`:31`、`:94`
- 変えない: `CHANGELOG.md`(リリースの手順で書く)、`docs/superpowers/`(履歴。配信設計の付録 A も作り直さない)、autofix の design の `:15`・`:30`(`repository_dispatch` の起動は残るので正しい)

**Interfaces:** なし(記述だけ)。

- [ ] **Step 1: docs を直す。** DOC-00 に従い、該当する行だけを変える。表の桁揃えは prettier のフックに任せる。
  - `loop-engineering-design.md:579` の `if` gate の列: `labels limited to \`needs-triage\` / \`triage:needs-info\``(`/ \`triage:ready\`` を消す)。
  - `loop-engineering-design.md:585`: `Classification labels a triage agent applies itself (\`bug\`, \`feature\`, \`question\`, \`documentation\`) must stay out of its own intake allowlist, and so must \`triage:ready\`: detect skips an Issue that carries it, so admitting the event only queues runs that end in a skip.`
  - `loop-caller-inputs-reference.md:37`: `detect      → loop-entity-detect`(先頭の空白は除く。`(+ detect_hook_script)` を消す)。
  - `loop-caller-inputs-reference.md:372-377`: 見出し `### Inputs only it accepts` と表と前後の空行を消す(入力が `ci-loop-caller` の部分集合になり、節が空になる。この見出しへのリンクはない)。
  - `loop-github-issue-triage-workflow-design.md:34`: ``- `labeled` intake is limited to `needs-triage` and `triage:needs-info`. Classification labels the agent applies itself and `triage:ready` (detect skips it) stay out, and `autofix` belongs to [Autofix Design](loop-github-issue-autofix-workflow-design.md)``(リンクの文字は今のまま)。
  - `loop-github-issue-triage-workflow-design.md:74`: `detect_hook_script` の行を消す。
  - `loop-github-issue-autofix-workflow-design.md:22`: ``- `repository_dispatch` (`loop-github-issue-autofix`) with `client_payload.issue_number` — an external or manual entry; nothing in this repository sends it``
  - `loop-github-issue-autofix-workflow-design.md:31`: `` - Agent-initiated `repository_dispatch` ``
  - `loop-github-issue-autofix-workflow-design.md:94`(Triage handoff の本文)を次にする:

    ```markdown
    Triage marks `triage:ready` and tells the human that adding `autofix` requests a fix PR. Autofix starts only from the `autofix` label, `workflow_dispatch`, or `repository_dispatch` with `client_payload.issue_number`; neither triage nor the Agent dispatches. To retry after a run that opened no PR (REJECT, budget, closed PR), remove and re-add `autofix`, or run `workflow_dispatch` with `issue_number`.
    ```

- [ ] **Step 2: 残っていないことを確かめる。** `git grep -n -i -e 'detect_hook' -e 'dispatch hook' -e 'trusted hook' -e 'post-detect' -- docs ':!docs/superpowers'`。Expected: 出力がない。
- [ ] **Step 3: コミットする。** `git add docs/explanation/loop-engineering/loop-engineering-design.md docs/explanation/loop-engineering/workflows/loop-caller-inputs-reference.md docs/explanation/loop-engineering/workflows/loop-github-issue-triage-workflow-design.md docs/explanation/loop-engineering/workflows/loop-github-issue-autofix-workflow-design.md`、`docs(loop): drop the detect hook from the triage and autofix designs`。

---

### Task 4: 全体の確認

**Files:** なし(確認だけ。直しが要れば、原因の Task のファイルを直して別のコミットにする)。

- [ ] **Step 1: gate。** `git grep -inE "detect_hook|on_detect_dispatch|dispatch_requested|dispatch_event_type|dispatch_client_payload|should_request_dispatch" -- . ':!.loop' ':!CHANGELOG.md' ':!docs/superpowers'`。Expected: `test/bats/github-actions/loop-caller-parity.bats:934:        DETECT_DOMAIN_ENV_JSON ENGINE finalize_hook_script FINALIZE_HOOK_SCRIPT detect_hook_script DETECT_HOOK_SCRIPT` の1行だけ。
- [ ] **Step 2: spec の bats と topology。** `bats test/bats/.apm/packages/github/github-issue-triage/detect_issue.bats test/bats/github-actions/loop-entity-detect.bats test/bats/.github/actions/loop-entity-detect/lib/entity_target.bats test/bats/scripts/self/ci/loop_input_topology.bats test/bats/github-actions/loop-caller-parity.bats`。Expected: PASS。`python3 -I scripts/self/ci/loop_input_topology.py . > /dev/null; echo $?`。Expected: `0`。
- [ ] **Step 3: 全部の bats。** `bats -r test/bats > tmp/bats-detect-hook-removal.txt 2>&1; echo $?`。Expected: `0`。確認の後 `rm -f tmp/bats-detect-hook-removal.txt`。
- [ ] **Step 4: 同期の残り。** `bash scripts/self/apm/sync_apm_artifacts.sh` の後、`git status --porcelain`。Expected: 作業の前からある `.claude/settings.json`、`.cursor/mcp.json`、`.mcp.json`、`apm.lock.yaml`、`.claude/worktrees/` だけ。`git diff apm.lock.yaml` は `generated_at` と `mcp_configs` の hunk だけ。
- [ ] **Step 5: lint。** actionlint、ghalint、zizmor、shellcheck、markdownlint は Stop フックの結果を見る。直接は実行しない。

---

## 範囲外(手動)

- リリースと pin の更新(`scripts/self/ci/pin_config_actions.sh`)。CHANGELOG に破壊的変更(`detect_hook_script` の削除)を書くのもこのとき。
- dogfood(spec「検証」): 使い捨てのブランチで triage を `workflow_dispatch` で動かし、detect が成功すること。リリースの後、`autofix` の付いたテスト用の Issue に所有者が `triage:ready` を付け、triage が起動しないこと、`gh run list --workflow on-loop-github-issue-autofix.yaml --event repository_dispatch` に新しい実行がないこと。
- 未検証として残る: autofix の `repository_dispatch` の経路(リポジトリ内に送る側もテストもない)。

## Self-review(writing-plans のチェックリスト)

- **spec の網羅:**
  - 変更の表の `ci-loop-caller-entity.yaml`・`loop-entity-detect`・`on-loop-github-issue-triage.yaml`・`loop_input_topology.py`・bats(`detect_dispatch_hook.bats` の削除、`loop-entity-detect.bats`、`old_names`)→ Task 1
  - triage の skill・bats(`on_detect_dispatch.bats` の削除、`detect_issue.bats`)・同期先 → Task 2
  - docs → Task 3。spec にない `loop-engineering-design.md:579`(Intake の表の `triage:ready`)も同じ理由で直す
  - autofix は変えない → Global Constraints
  - 検証の節: grep の gate、5つの bats、topology → Task 4。dogfood とリリースの後の確認 → 範囲外
- **プレースホルダー:** なし。
- **名前の一貫性:** `detect_hook_script` / `DETECT_HOOK_SCRIPT` / `resolve_detect_hook_script` / `should_request_dispatch` / `NO_DISPATCH_FIELDS` / `finalize_label_allowlist` は Task 1〜4 で同じ綴り。
- **分量:** 削除だけなので、置き換える文と、gate を通すテストの書き方、lock の patch の手順だけを書いた。
