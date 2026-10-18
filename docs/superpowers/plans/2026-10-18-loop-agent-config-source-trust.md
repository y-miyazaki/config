# Loop Agent Config Source Trust Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `loop-execute` が `~/.claude.json` にワークスペースの信頼を書くのをやめ、導入先の `.claude/settings.json` の `permissions.allow` と `additionalDirectories` を `claude -p` に効かせない。claude の権限は、実行の種類ごとに明示する `--permission-mode`、プラットフォームが固定で持つ読み取りの git の基準(`--allowedTools`)、caller の `agent_tool_allowlist`、プラットフォームが固定で持つ拒否の一覧(`--disallowedTools`)だけで決める。

**Architecture:** `agent.sh` から `grant_claude_workspace_trust` と呼び出しを消す。`append_claude_permission_args` は、`--setting-sources project` を残したまま、maker に `acceptEdits`、checker に `dontAsk` を必ず渡し、`--allowedTools` に固定の読み取りの git 4件と caller の規則を、`--disallowedTools` に固定の拒否の一覧を渡す。固定の2つの一覧は `agent.sh` の配列にし、caller の新しい入力は作らない。信頼がなくなって失う許可(`git`、`bash` のスクリプト、`gh repo view` など)は、各 caller の `agent_tool_allowlist` に書き直す。

**Tech Stack:** bash、Claude Code CLI(`claude -p`、2.1.296 で `--permission-mode` の選択肢と `--disallowedTools` を確認)、GitHub Actions(reusable workflow、composite action)、bats。

**Spec:** `docs/superpowers/specs/2026-10-17-loop-agent-config-source-design.md` の「方向(2026-10-18 追記…)」。範囲はオーナーが決めた最小の変更(信頼の付与をやめること)だけ。行番号は HEAD(`cbe83740`、`91375a2b` の後)で確かめた値である(対応は末尾の「spec との差」)。

## Global Constraints

- 範囲外(この plan で触らない): 管理設定(`/etc/claude-code/managed-settings.json`、`allowManagedPermissionRulesOnly`)による強化、第10節の skill と MCP の読み元のデフォルトブランチへの切り替え、skill の文面(`loop-capable-skills.md` と各 `SKILL.md`)、claude 以外のエンジン(codex、copilot、cursor)の扱い、`--setting-sources` の変更、`.mcp.json` と `enableAllProjectMcpServers`(`mcp.sh:40`)。
- `--setting-sources project` は残す(spec「方向」第1項・第2項)。CLAUDE.md、rules、skill、hooks、`env`、`.mcp.json`、導入先の `deny` と `ask` は、これまでどおり効く。
- `--permission-mode` は毎回渡す: `allow_writes == true`(maker、L1 の `loop-agent-once` を含む)は `acceptEdits`、`false`(checker、`verifier.sh:393`)は `dontAsk`。caller の入力からは変えられない(spec「他のエージェント workflow」(3))。
- 新しい caller の入力、action の入力、reusable の入力は作らない(配信 spec のアンチゴール「新しいスクリプトの入力が増える」、配信設計のアンチゴール「新しい設定値が増える」)。固定の一覧は `agent.sh` の中の配列にする。
- 固定の一覧に導入先のパス(`.agents/`、`.claude/`、`scripts/` など)を書かない(`.github/workflows/CLAUDE.md` の Portability)。caller(`on-loop-*.yaml`)は dogfood なので、この repo のパスを書いてよい。
- 権限の4ファイル(`.claude/settings.json`、`.cursor/cli.json`、`.cursor/permissions.json`、`.lean-ctx.toml`)は変えない。CLAUDE.md の Permission parity は適用されない。
- シェルの変更には bats を対にする(`.claude/rules/bats.md`)。テストを先に書く。`shfmt`・`prettier` は PostToolUse フック、`shellcheck`・`actionlint`・`ghalint`・`zizmor`・`markdownlint-cli2`・`markdown-link-check`・`gitleaks` は Stop フックが実行する。**実装者は直接実行しない**(結果はフックの出力で見る)。
- 作業ツリーに無関係の変更がある(`.claude/settings.json`、`.cursor/mcp.json`、`.mcp.json`、`apm.lock.yaml`、`.claude/worktrees/`)。コミットは**明示したパスだけ**を stage する。`git add -A` は使わない。skill は変えないので APM の同期は要らない(Stop フックの同期で差分が出ても stage しない)。
- 一時ファイルは `tmp/` に置き、使い終えたら消す。
- `ci-*` から `./.github/...` を参照しない。pin は変えない。リリースと pin の更新、GitHub Actions のワークフローの実行(dogfood)は、この plan に含めない。push しない。

### 固定の一覧(Task 1 が `agent.sh` に置く値。順序もこのとおり)

`CLAUDE_PLATFORM_ALLOW_RULES`(4件。maker の合成のプロンプト `agent.sh:125` と checker が差分を読むために要る):

```text
Bash(git diff:*)
Bash(git log:*)
Bash(git show:*)
Bash(git status:*)
```

`CLAUDE_PLATFORM_DENY_RULES`(34件。GitHub への書き込み、push、外への通信、環境変数の表示、権限の昇格、`git diff --output` によるファイルの書き込み):

```text
Bash(curl:*)
Bash(gh api *--method*)
Bash(gh api *-X DELETE*)
Bash(gh api *-X PATCH*)
Bash(gh api *-X POST*)
Bash(gh api *-X PUT*)
Bash(gh issue close:*)
Bash(gh issue comment:*)
Bash(gh issue create:*)
Bash(gh issue delete:*)
Bash(gh issue edit:*)
Bash(gh label create:*)
Bash(gh label delete:*)
Bash(gh label edit:*)
Bash(gh pr close:*)
Bash(gh pr comment:*)
Bash(gh pr create:*)
Bash(gh pr edit:*)
Bash(gh pr merge:*)
Bash(gh pr review:*)
Bash(gh release create:*)
Bash(gh release delete:*)
Bash(gh release edit:*)
Bash(gh release upload:*)
Bash(gh run cancel:*)
Bash(gh run rerun:*)
Bash(gh secret:*)
Bash(gh variable:*)
Bash(gh workflow run:*)
Bash(git diff *--output*)
Bash(git push:*)
Bash(printenv:*)
Bash(sudo:*)
Bash(wget:*)
```

根拠(公式ドキュメント permissions、2026-10-18 取得): deny はどの階層の allow にも勝ち、`--disallowedTools` もその一つ。`*` はどの位置でも任意の文字列に一致し、`:*` は末尾のスペースと `*` と同じ。deny は複合コマンドのどの部分にも当たる。`Bash(gh api *-X POST*)` は `gh api -X GET … -X POST` に当たる(spec「方向」第4項の前方一致の穴)。ただし `/usr/bin/curl` や `sh -c '…'` のような別の形は当たらない。止める本体は agent ジョブの読み取りのトークン(credential-isolation、実装済み)で、この一覧は補助の層である。

## Review Focus

1. **caller の許可の取りこぼし。** 信頼があった間は `Bash(bash:*)`、`Bash(jq:*)`、`Bash(gh repo view:*)`、`mcp__github`、`WebFetch` などが黙って効いていた。取りこぼしは CI の stderr の `::warning::Agent permission_denials:`(`usage.sh` の `render_claude_stream_log_summary`)にだけ出る。Task 2 の表は skill と maker の指示から作ったが、エージェントが実際に打つコマンドの形(絶対パス、`cd … &&`)は実機でしか確かめられない。「リリース後の実機の確認」の 2・3 で見る。
2. **checker の `dontAsk`。** 今の checker は `--permission-mode` なし(既定のモード)で、信頼で有効になった導入先の `Edit(**/*.md)` などの allow で編集もできた。`dontAsk` にすると、許可のないものは全て拒否される。checker が差分を読めることは、固定の読み取りの git 4件に頼る。Task 1 の `run_agent claude checker session runs in dontAsk mode with the read baseline` で引数を見て、実機の確認の 4 で APPROVE が出ることを見る。
3. **`--disallowedTools` が caller の必要なコマンドを奪うこと。** 固定の拒否は全ての caller に効く。pr-review の `gh api -X GET …` や `gh pr view`、ci-sweeper の `gh run view` が拒否の一覧のどの規則にも当たらないことを、Task 1 の `platform deny rules do not cover the read-only gh rules callers declare` で見る(dogfood の caller の読み取りの規則を固定値として並べ、各規則の先頭の語が拒否の一覧の先頭の語と一致しないことを見る)。
4. **可変長のフラグの並び。** `--allowedTools <tools...>` と `--disallowedTools <tools...>` は後ろの値を全部取る。後ろに続くのが `--add-dir` などのフラグであること、`-p <prompt>` が前にあることを、Task 1 の引数の完全一致のテスト(`run.bats` の `CLAUDE_BASE_ARGS`)で見る。
5. **導入先の `deny` と `ask` と hooks は効いたまま。** この repo の `ask: Edit(.github/workflows/**)`、`Edit(go.mod)`、`Edit(package.json)` は、`claude -p` では拒否になる(ci-sweeper の `.github/**`、tech-debt の `go.mod`・`package.json` を編集できない)。Stop の hook(`sync_apm_artifacts.sh`)は CI の maker でも動く。どちらも今と同じ挙動で、この plan は変えない(「spec との差」に記録し、実機の確認の 5 で見る)。

---

## ファイル構成

| ファイル                                                                                                                                                                                                                                                                       | 責務                                                        | Task |
| ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ----------------------------------------------------------- | ---- |
| `.github/actions/loop-execute/lib/agent.sh`、`test/bats/.github/actions/loop-execute/lib/agent.bats`、`test/bats/.github/actions/loop-agent-once/lib/run.bats`                                                                                                                 | 信頼の付与の削除、`--permission-mode`、固定の allow と deny | 1    |
| `.github/workflows/on-loop-{changelog,docs-updater,refactor,tech-debt,test-gap,ci-sweeper,github-issue-autofix,github-pr-revise,github-pr-review,github-issue-triage}.yaml`、`test/bats/github-actions/loop-caller-parity.bats`                                                | caller の許可リストの組み直しと triage のコメント           | 2    |
| `.github/workflows/{ci-loop-caller,ci-loop-caller-entity,ci-loop-agent}.yaml`、`.github/actions/{loop-execute,loop-agent-once}/action.yml`(入力の説明)、`docs/explanation/loop-engineering/workflows/loop-caller-inputs-reference.md`、各 workflow の設計の文書、対応する bats | 契約の文言                                                  | 3    |
| なし                                                                                                                                                                                                                                                                           | 全体の確認                                                  | 4    |

---

### Task 1: `agent.sh` の信頼の付与をやめ、claude の権限の引数を固定する

**Files:**

- Modify: `.github/actions/loop-execute/lib/agent.sh`
  - `:14-17`(Design Rules): 「The action grants no tool permissions of its own …」「grant_claude_workspace_trust only unlocks …」の4行を、次の趣旨に置き換える: workspace trust は付与しないので、導入先の `.claude/settings.json` の `permissions.allow` と `additionalDirectories` は CI で使われない(`deny`・`ask`・hooks・`env` は効く)。claude の権限は、実行の種類で決まる `--permission-mode`、固定の読み取りの git の基準、caller の規則、固定の拒否の一覧だけで決まる。
  - `:22-36`(`append_claude_permission_args` の Description): `:26-34` を、上の4要素と、`acceptEdits`(maker)・`dontAsk`(checker)の意味(`dontAsk` は許可のない呼び出しを全て拒否する)に書き換える。`:30-31` の「loads the host repository's .claude/settings.json」は「loads the host repository's project settings (deny/ask rules, hooks, env, .mcp.json); its allow rules stay inactive without workspace trust」にする。Globals に `CLAUDE_PLATFORM_ALLOW_RULES`、`CLAUDE_PLATFORM_DENY_RULES` を足す。
  - ファイルの冒頭(ヘッダーの後、最初の関数の前)に `CLAUDE_PLATFORM_ALLOW_RULES=(…)` と `CLAUDE_PLATFORM_DENY_RULES=(…)` を、Global Constraints の値と順序で定義する(`readonly` にしない。`_init.sh` 経由で同じプロセスに2回 source されても失敗しないため)。それぞれに1行のコメント(用途)を付ける。
  - `:51-65`(`append_claude_permission_args`): Interfaces のとおり。
  - `:163-239`(`grant_claude_workspace_trust` の doc と本体)を削除。`:434`(呼び出し)を削除。
- Test: `test/bats/.github/actions/loop-execute/lib/agent.bats`、`test/bats/.github/actions/loop-agent-once/lib/run.bats`

**Interfaces:**

- Produces `append_claude_permission_args <args_nameref> <allow_writes>`(引数は今と同じ)。`args_ref` に次の順で足す:
  1. `--setting-sources project`
  2. `--permission-mode acceptEdits`(`allow_writes == true`)/`--permission-mode dontAsk`(それ以外)
  3. `--allowedTools` と、`CLAUDE_PLATFORM_ALLOW_RULES` の全件、続けて `AGENT_TOOL_ALLOWLIST` の空でない行(重複は除かない)
  4. `--disallowedTools` と、`CLAUDE_PLATFORM_DENY_RULES` の全件
- `run_agent_engine` の claude の枝の引数の順は `-p … --output-format stream-json --verbose`、`append_agent_mcp_args`、`append_claude_permission_args`、`--add-dir …`、`--effort`、`--max-turns`、`--model`(今と同じ。信頼の付与だけが消える)。
- copilot・codex・cursor の枝と `warn_unsupported_allowed_tools` は変えない。
- Task 2 と Task 3 は、固定の allow 4件と deny 34件の値(Global Constraints)を前提にする。

- [ ] **Step 1: `agent.bats` の失敗するテストを書く。**
  - 削除: `:8-12` の Use cases 5行と、`:91-153` の `grant_claude_workspace_trust …` の5件。
  - Use cases を直す: `run_agent loads the host repository's project settings for maker and checker` → `run_agent loads project settings but never grants workspace trust`。`run_agent forwards only caller-declared permission rules, never its own` → `run_agent passes the fixed read baseline plus caller rules, and the fixed deny list`。`run_agent grants edit permission to claude maker sessions only …` → `run_agent runs claude makers in acceptEdits and checkers in dontAsk, and forwards model/max-turns`。
  - 足す・直す(a-z の位置に置く):
    - `@test "run_agent claude never writes workspace trust"`: `HOME` と `GITHUB_WORKSPACE` を `BATS_TEST_TMPDIR` の下にし、`run_agent "true"` と `run_agent "false"` の後で `${HOME}/.claude.json` が存在しない。`declare -F grant_claude_workspace_trust` が失敗する。
    - `run_agent claude checker session stays read-only`(`:312`)を `@test "run_agent claude checker session runs in dontAsk mode with the read baseline"` に: `grep -q -- "--permission-mode dontAsk"`、`run ! grep -q -- "acceptEdits"`、`grep -qF -- "--allowedTools Bash(git diff:*) Bash(git log:*) Bash(git show:*) Bash(git status:*)"`。
    - `run_agent claude passes caller-declared rules and grants nothing on its own`(`:335`)を `@test "run_agent claude appends caller rules after the read baseline"` に: `AGENT_TOOL_ALLOWLIST` に `Bash(gh issue view:*)`、空行、`Bash(gh label list:*)` を入れ、`--allowedTools Bash(git diff:*) Bash(git log:*) Bash(git show:*) Bash(git status:*) Bash(gh issue view:*) Bash(gh label list:*) --disallowedTools`(末尾にスペース)を含む。
    - `run_agent claude omits allowedTools when the caller declared no rules`(`:364`)を `@test "run_agent claude passes only the read baseline when the caller declared no rules"` に: `--allowedTools` の直後から `--disallowedTools` の直前までが固定の4件だけ。
    - `run_agent ignores the legacy ENGINE and AGENT_ALLOWED_TOOLS names`(`:346`): `run ! grep -q -- "--allowedTools"` を `run ! grep -qF -- "Bash(gh issue edit:*) --disallowedTools" "${args_file}"`(legacy の値が allow 側に入らない)に直す。後半の `ENGINE` の部分は変えない。
    - `@test "run_agent claude passes the fixed deny list for maker and checker"`: 両方の役で `--disallowedTools` の後ろが Global Constraints の34件をその順で空白区切りにしたもの(テストの中に34件を固定値として書く。`CLAUDE_PLATFORM_DENY_RULES` から作らない)。`--disallowedTools` の後に `--add-dir` が続くケース(`DETECT_JSON_FILE` あり)も1つ見る。
    - `@test "platform deny rules do not cover the read-only gh rules callers declare"`(Review Focus 3): 固定値 `Bash(gh api -X GET:*)`、`Bash(gh issue view:*)`、`Bash(gh label list:*)`、`Bash(gh pr diff:*)`、`Bash(gh pr list:*)`、`Bash(gh pr view:*)`、`Bash(gh repo view:*)`、`Bash(gh run list:*)`、`Bash(gh run view:*)` のそれぞれについて、`Bash(` と `:*)` を外した文字列(例 `gh api -X GET`)が、`CLAUDE_PLATFORM_DENY_RULES` のどの規則を `Bash(…)` を外して `*` をワイルドカードにした bash の `[[ … == pattern ]]` にも一致しない(`:*` はスペースと `*` と同じ扱い。末尾にスペースと `x` を足した文字列でも見る)。
    - `@test "platform rules name no consumer path"`: 両配列のどの要素も `.agents/`、`.claude/`、`.apm/`、`scripts/`、`skills/` を含まない。
    - `run_agent claude maker session grants edit permission and passes model`(`:260`)は変えない(`acceptEdits` のまま通る)。`run_agent claude loads host project settings for both roles`(`:323`)は名前を `run_agent claude keeps project setting sources for both roles` に変えるだけ。
- [ ] **Step 2: `run.bats` を直す。** `:57` の `CLAUDE_BASE_ARGS` を、`--permission-mode acceptEdits` の後に `--allowedTools Bash(git diff:*) Bash(git log:*) Bash(git show:*) Bash(git status:*) --disallowedTools <34件を空白区切り>` を足した値にする(34件はテストの中の固定値。`agent.bats` と同じ並び)。`:51` の `unset … GITHUB_WORKSPACE CLAUDE_CONFIG_DIR …` は残す。Use cases に `run_loop_agent_once passes the fixed claude permission surface (acceptEdits, read baseline, deny list)` を足す。
- [ ] **Step 3: 失敗を確認する。** `bats test/bats/.github/actions/loop-execute/lib/agent.bats test/bats/.github/actions/loop-agent-once/lib/run.bats`。Expected: FAIL(`dontAsk`、`--disallowedTools`、`declare -F` が残る、`CLAUDE_BASE_ARGS` の不一致)。
- [ ] **Step 4: 実装する。** Files と Interfaces のとおり。関数は a-z の順を保つ(`grant_claude_workspace_trust` が消えるだけ)。
- [ ] **Step 5: 通ることを確認する。** `bats test/bats/.github/actions/loop-execute/ test/bats/.github/actions/loop-agent-once/`。Expected: PASS。兄弟の箇所: `git grep -n -e grant_claude_workspace_trust -e hasTrustDialogAccepted -e "workspace trust" -- .github test docs ':!docs/superpowers'` が、Task 3 で直す `loop-caller-inputs-reference.md:228` だけを出す。`CHANGELOG.md` の過去の記載は変えない。
- [ ] **Step 6: コミットする。** `git add .github/actions/loop-execute/lib/agent.sh test/bats/.github/actions/loop-execute/lib/agent.bats test/bats/.github/actions/loop-agent-once/lib/run.bats`、`feat(loop-execute): stop granting workspace trust and pass a fixed claude permission surface`。

---

### Task 2: caller の許可リストを組み直す

信頼がなくなると、caller の規則と固定の基準にないコマンドは拒否される。組み立ての前提(公式ドキュメント permissions「Read-only commands」): `ls`、`cat`、`echo`、`pwd`、`head`、`tail`、`grep`、`find`、`wc`、`which`、`diff`、`stat`、`du`、作業ディレクトリ内への `cd`、git の読み取りの形は、どのモードでも規則なしで動く。Read・Grep・Glob も作業ディレクトリと `--add-dir` の中では承認が要らない。`acceptEdits` は Edit・Write と `mkdir`・`touch`・`mv`・`cp` を許す。`jq`、`yq`、`rg`、`bash <script>`、`bats`、`go test`、`gh …`、`WebFetch`、MCP のツールは規則が要る。

検証のスクリプトは、Claude Code が skill を `.claude/skills/` から読むので、`.claude/skills/<skill>/scripts/validate.sh` の相対パスに固定する。エージェントが絶対パスや `cd <skill dir> && bash scripts/validate.sh` で打つと規則に当たらないので、該当する4つの caller の maker の指示に1文を足して形をそろえる(Files)。下の表で `V(a, b, …)` は、`Bash(bash .claude/skills/<x>-validation/scripts/validate.sh:*)` を、`x` = `a`、`b`、… の順に並べたもの。

**caller ごとの許可(固定の基準 `git diff`・`git log`・`git show`・`git status` は全ての caller に付くので表に書かない)。checker(`verifier.sh:393`)は同じ規則を `dontAsk` で受ける。**

| caller(`on-loop-*.yaml`)                     | skill / maker の指示が使うもの(根拠)                                                                                                                                                                                                   | 今の `agent_tool_allowlist`                                                                                      | 新しい `agent_tool_allowlist`(この順)                                                |
| -------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------ |
| `changelog`                                  | `git diff --name-only` で照合(`changelog/references/category-automation-envelope.md`)、リンクは detect の `repository_url`                                                                                                             | なし                                                                                                             | なし(変えない。基準で足りる)                                                         |
| `docs-updater`                               | `git diff`(automation envelope)、`git remote get-url origin` と現在のブランチ(`docs-updater/references/category-pr-body-links.md:8-9`)                                                                                                 | なし                                                                                                             | `Bash(git remote get-url:*)`                                                         |
| `refactor`                                   | 4つの検証の skill を「Re-run stack validation」(caller の maker の指示 `:66-75`)、`git remote get-url`(`refactor/references/category-pr-body-links.md:9`)                                                                              | なし                                                                                                             | `Bash(git remote get-url:*)`、`V(github-actions, go, markdown, shell-script)`        |
| `tech-debt`                                  | `git diff`、`git remote get-url`(`tech-debt/references/category-pr-body-links.md:9`)。GitHub の Issue は作らない(maker の指示)                                                                                                         | なし                                                                                                             | `Bash(git remote get-url:*)`                                                         |
| `test-gap`                                   | 「You cannot run the tests here」(maker の指示、`test-gap/SKILL.md:67`)、`git remote get-url`(`test-gap/references/category-pr-body-links.md:9`)                                                                                       | なし                                                                                                             | `Bash(git remote get-url:*)`                                                         |
| `ci-sweeper`                                 | 失敗の取得(既存)、ルーティングの表の検証の skill(github-actions、shell-script、markdown。maker の指示 `:91-102`)、checker が「Missing validation」を REJECT、`git remote get-url`(`ci-sweeper/references/category-pr-body-links.md:9`) | `Bash(gh api -X GET:*)`、`Bash(gh run list:*)`、`Bash(gh run view:*)`                                            | 既存の3行、`Bash(git remote get-url:*)`、`V(github-actions, markdown, shell-script)` |
| `github-issue-autofix`                       | Issue と既存の PR の確認(既存)、編集は `**`、検証は「Validation tooling missing → defer」(`github-issue-autofix/SKILL.md:78`)                                                                                                          | `Bash(gh api -X GET:*)`、`Bash(gh issue view:*)`、`Bash(gh pr list:*)`、`Bash(gh pr view:*)`                     | 既存の4行、`V(github-actions, go, markdown, shell-script)`                           |
| `github-pr-revise`                           | PR とレビューの取得(既存。`gh pr view <n> --json body,comments,reviews`)、編集は `**`、検証は defer 可(`github-pr-revise/SKILL.md:81`)                                                                                                 | `Bash(gh api -X GET:*)`、`Bash(gh pr view:*)`、`Bash(gh pr diff:*)`                                              | 既存の3行、`V(github-actions, go, markdown, shell-script)`                           |
| `github-pr-review`                           | `gh api -X GET`、`gh pr view`、`gh pr diff`、`gh issue view`、`git show <base_sha>:<path>`(maker の指示 `:102-117`、`github-pr-review/references/category-review-rules.md`)。`/code-review` は `--comment` なし                        | `Bash(gh api -X GET:*)`、`Bash(gh issue view:*)`、`Bash(gh pr diff:*)`、`Bash(gh pr view:*)`、`Bash(git show:*)` | 変えない(`git show` は基準と重複するが残す)                                          |
| `github-issue-triage`(L1、`loop-agent-once`) | Issue の取得、ラベルの一覧(既存)、`gh repo view --json nameWithOwner`(`github-issue-triage/references/category-pr-body-links.md:14`)。`message.md`・`message_labels.json` は `--add-dir` の `LOOP_MESSAGE_DIR` に `acceptEdits` で書く | `Bash(gh api -X GET:*)`、`Bash(gh issue view:*)`、`Bash(gh label list:*)`                                        | 既存の3行、`Bash(gh repo view:*)`                                                    |

表に入れなかったもの(意図して許さない): `Bash(bash:*)`・`Bash(bash -c:*)`(任意のコマンド)、`Bash(bats:*)`・`Bash(go test:*)`(検証の skill のスクリプトが呼ぶ。直接は不要)、`Bash(jq:*)`・`Bash(yq:*)`(detect JSON は Read で読める)、`WebFetch`・`WebSearch`・`mcp__*`(skill の文面に使う指示がない。`git grep` で0件)、triage の `scripts/label_fsm.sh`(`category-fsm.md:24` の補助の関数。表で計算できる)。どれも実機の確認の 2 で拒否が出たら別の変更で足す。

**Files:**

- Modify: 表の新しい値が今と違う8つの caller の `agent_tool_allowlist`(`docs-updater`・`refactor`・`tech-debt`・`test-gap` は `agent_maker_skill_name` の次の a-z の位置にキーを足す。`ci-sweeper` `:108-111`、`github-issue-autofix` `:73-77`、`github-pr-revise` `:120-123`、`github-issue-triage` `:129-132` は行を足す)。キーの上のコメントは、新しく足すキーには付けない。
- Modify: `on-loop-refactor.yaml`(maker の指示 `:66-75`)、`on-loop-ci-sweeper.yaml`(`:86-103`。`:102` の「Read each skill's SKILL.md under `.agents/skills/` or `.claude/skills/` before invoking.」の次の行)、`on-loop-github-issue-autofix.yaml`(`:65-67`)、`on-loop-github-pr-revise.yaml`(`:106-114`)の maker の指示の末尾に、次の1文をそのまま足す:

  ```text
  Run a validation skill's script from the repository root by this exact form: `bash .claude/skills/<skill>/scripts/validate.sh [path]` (other forms such as cd into the skill directory or an absolute path are denied in CI).
  ```

- Modify: `on-loop-github-issue-triage.yaml:125-128` のコメントを次に置き換える:

  ```yaml
  # Triage reads Issue facts only; finalize posts the comment and applies the
  # labels. CI never activates the host .claude/settings.json allow rules (no
  # workspace trust), so these rules plus the platform read-only git baseline
  # are the agent's whole command surface; the platform deny list blocks gh writes.
  ```

- Test: `test/bats/github-actions/loop-caller-parity.bats`(`:1125-1171` の triage のテスト群の後)

**Interfaces:** Consumes Task 1 の固定の一覧(基準4件を caller に書かないこと、拒否の34件と衝突しないこと)。

- [ ] **Step 1: 失敗するテストを書く。**
  - `@test "callers declare the tool rules their skill needs without host allow rules"`: 10個の caller について、`triage_block "${wf}" agent_tool_allowlist` の出力が表の「新しい `agent_tool_allowlist`」と行の並びまで完全一致する(`changelog` は空。期待値はテストの中に caller ごとの here-doc で書く。`V(...)` は展開した行で書く)。
  - `@test "callers that run validation scripts pin the script form in maker instructions"`: refactor・ci-sweeper・github-issue-autofix・github-pr-revise の `triage_block "${wf}" agent_maker_instructions` が上の1文を `grep -qF` で含み、その caller の `agent_tool_allowlist` の `validate.sh` の行がすべて `Bash(bash .claude/skills/` で始まる。
  - `@test "no caller allowlist repeats the platform read baseline or a platform deny rule"`: github-pr-review の `Bash(git show:*)` を除き、10個の caller の規則が `Bash(git diff:*)`・`Bash(git log:*)`・`Bash(git status:*)` を含まず、`Bash(gh pr comment`・`Bash(gh issue comment`・`Bash(gh issue edit`・`Bash(gh label create`・`Bash(git push`・`Bash(curl`・`Bash(bash:*)`・`Bash(bash -c` を含まない。
  - 既存の `triage caller grants no write gh commands to the agent`(`:1142`)に `grep -qxF 'Bash(gh repo view:*)'` を足す。`L2 callers grant no write gh commands to the agent`(`:1157`)は変えない。
  - `@test "triage caller comment no longer says host project settings apply"`: `on-loop-github-issue-triage.yaml` が `still apply via --setting-sources project` を含まず、`no` と `workspace trust` を同じコメントの中に含む。
  - Use cases に「Dogfood callers declare every command rule their skill needs; host .claude/settings.json allow rules are never active in CI」を足す。
- [ ] **Step 2: 失敗を確認する。** `bats test/bats/github-actions/loop-caller-parity.bats`。Expected: FAIL(新しい4件)。
- [ ] **Step 3: 実装する。** Files のとおり。`with:` のキーは a-z の順(ORD-01)。規則の行は表の並び。
- [ ] **Step 4: 通ることを確認する。** `bats test/bats/github-actions/loop-caller-parity.bats test/bats/scripts/self/ci/loop_input_topology.bats` と `python3 -I scripts/self/ci/loop_input_topology.py . > /dev/null; echo $?`。Expected: PASS、`0`。兄弟の箇所: `git grep -n "agent_tool_allowlist" -- example` の出力を見て、`example/` の caller も同じ前提(信頼なし)で足りないものがあれば、完了の報告に範囲外として列挙する(この plan では直さない)。
- [ ] **Step 5: コミットする。** `git add` で変えた `on-loop-*.yaml`(最大9つ。`changelog` と `github-pr-review` は変えない)と `test/bats/github-actions/loop-caller-parity.bats`、`chore(loop): declare caller tool rules now that host allow rules are inactive in CI`。

---

### Task 3: 入力の説明と docs を新しい契約に合わせる

**Files:**

- Modify(入力 `agent_tool_allowlist` の `description`。例の `Bash(gh issue edit:*)` は固定の拒否に入ったので `Bash(gh issue view:*)` に変える):
  - `.github/workflows/ci-loop-caller.yaml:102`、`.github/workflows/ci-loop-caller-entity.yaml:103`:

    ```yaml
    description: 'Newline-separated permission rules the skill needs, in the engine''s own syntax (claude: "Bash(gh issue view:*)"). Caller-declared only — never derived from detect output. The repository''s .claude/settings.json allow rules are not applied in CI; claude adds only a fixed read-only git baseline and always applies a fixed deny list for GitHub writes, push, network, and env commands'
    ```

  - `.github/workflows/ci-loop-agent.yaml:106`: 同じ文から「Caller-declared only — never derived from detect output. 」を除いたもの。
  - `.github/actions/loop-execute/action.yml:72`、`.github/actions/loop-agent-once/action.yml:29`:

    ```yaml
    description: 'Newline-separated permission rules the running skill needs, in the engine''s own syntax (claude: "Bash(gh issue view:*)"). The host repository''s .claude/settings.json allow rules are not applied (no workspace trust); claude adds a fixed read-only git baseline (git diff/log/show/status), runs makers in acceptEdits and checkers in dontAsk, and always denies a fixed list of GitHub-write, push, network, and env commands. Engines without a per-tool allowlist warn and ignore it.'
    ```

- Modify: `docs/explanation/loop-engineering/workflows/loop-caller-inputs-reference.md`
  - `:215`(`agent_tool_allowlist` の行): 「Added on top of the host repository's `.claude/settings.json`; empty grants nothing beyond it.」を「Added after a fixed read-only git baseline (`git diff`, `git log`, `git show`, `git status`); the host repository's `.claude/settings.json` allow rules are not applied in CI.」に、例を `Bash(gh issue view:*)` に。
  - `:221-226` の表の `claude` の行: 1列目を「`.claude/settings.json` `deny` / `ask` only (its `allow` stays inactive without workspace trust), plus the fixed baseline, the fixed deny list, and `agent_tool_allowlist`」、2列目を「`--permission-mode acceptEdits` (maker) / `dontAsk` (checker)」。
  - `:228` の段落を置き換える: claude は信頼を付与しないので `permissions.allow` と `additionalDirectories` は使われず、stderr に「this workspace has not been trusted」の警告が出ること。`deny`・`ask`・hooks・`env`・`.mcp.json` は効くこと。固定の拒否の一覧の要旨(GitHub への書き込み、`git push`、`curl`・`wget`、`printenv`、`sudo`、`git diff --output`)と、それが強制の境界ではなく、境界は agent ジョブの読み取りのトークンであること。skill の `allowed-tools` は信頼に関係なく効くこと(公式ドキュメント)。
- Modify(各 workflow の設計の文書の `agent_tool_allowlist` の行。DOC-00 に従い、その行だけ):
  - `loop-ci-sweeper-workflow-design.md:130`、`loop-github-issue-autofix-workflow-design.md:57`、`loop-github-pr-revise-workflow-design.md:61`、`loop-github-issue-triage-workflow-design.md:70`: Task 2 の表の新しい規則を反映する(検証のスクリプト、`gh repo view`)。
  - `loop-docs-updater-workflow-design.md`、`loop-refactor-workflow-design.md`、`loop-tech-debt-workflow-design.md`、`loop-test-gap-workflow-design.md`: 入力の表に `agent_tool_allowlist` の行を足す(`agent_maker_skill_name` の行の次)。値は Task 2 の表。
  - `loop-changelog-workflow-design.md`、`loop-github-pr-review-workflow-design.md:76`: 変えない(規則が変わらない)。
- Modify(テスト): `test/bats/.github/actions/loop-execute/action.bats`、`test/bats/.github/actions/loop-agent-once/action.bats`、`test/bats/github-actions/loop-caller-parity.bats`
- 変えない: `CHANGELOG.md`(リリースのとき)、`docs/superpowers/`

**Interfaces:** なし。

- [ ] **Step 1: 失敗するテストを書く。**
  - `loop-execute/action.bats` と `loop-agent-once/action.bats` に `@test "agent_tool_allowlist description states host allow rules are not applied"`: `agent_tool_allowlist` の `description` の行が `is also loaded when present` を含まず、`are not applied (no workspace trust)`、`acceptEdits`、`dontAsk`、`Bash(gh issue view:*)` を含み、`Bash(gh issue edit:*)` を含まない。Use cases に1行足す。
  - `loop-caller-parity.bats` に `@test "reusable agent_tool_allowlist descriptions state host allow rules are not applied"`: 3つの reusable の該当の `description` が `grants nothing beyond the repository` を含まず、`allow rules are not applied in CI` と `Bash(gh issue view:*)` を含む。
- [ ] **Step 2: 失敗を確認する。** `bats test/bats/.github/actions/loop-execute/action.bats test/bats/.github/actions/loop-agent-once/action.bats test/bats/github-actions/loop-caller-parity.bats`。Expected: FAIL(新しい3件)。
- [ ] **Step 3: 実装する。** Files のとおり。表の桁揃えは prettier のフックに任せる。
- [ ] **Step 4: 通ることを確認する。** Step 2 のコマンド。Expected: PASS。残りの確認: `git grep -n -e "beyond the repository" -e "is also loaded when present" -e "workspace trust, which" -e "Bash(gh issue edit:\*)\")" -- .github docs ':!docs/superpowers'` の出力がない。
- [ ] **Step 5: コミットする。** 変えた5つの YAML、`loop-caller-inputs-reference.md`、変えた workflow の設計の文書(最大8つ)、3つの bats を列挙して `git add`、`docs(loop): describe the claude permission surface without host allow rules`。

---

### Task 4: 全体の確認

**Files:** なし(直しが要れば原因の Task のファイルを直して別のコミットにする)。

- [ ] **Step 1: 全部の bats。** `mkdir -p tmp && bats -r test/bats > tmp/bats-config-source-trust.txt 2>&1; echo $?`。Expected: `0`。確認の後 `rm -f tmp/bats-config-source-trust.txt`。
- [ ] **Step 2: 引数の目視。** `bats test/bats/.github/actions/loop-agent-once/lib/run.bats` が通っていれば、L1 の引数の完全一致(`CLAUDE_BASE_ARGS`)が Task 1 の Interfaces の並びと同じであることが確かめられている。追加の実行は不要。
- [ ] **Step 3: 作業ツリー。** `git status --porcelain`。Expected: 作業の前からある5つだけ。
- [ ] **Step 4: lint。** shellcheck、actionlint、ghalint、zizmor、markdownlint は Stop フックの結果を見る。直接は実行しない。

---

## リリース後の実機の確認(手動。この plan の範囲外)

リリースと pin の更新(`loop-execute`・`loop-agent-once` と `ci-loop-agent.yaml`、`ci-loop-caller*.yaml`、`example/`)は明示の承認を得てから行う。CHANGELOG に、信頼の付与の削除(導入先の `allow` が CI で効かなくなる破壊的な変更)、checker の `dontAsk`、固定の基準と拒否の一覧、入力の説明の例の変更を書く。その後、dogfood で次を見る(spec「方向」の実機の確認 (1)(2)(4) に対応。(3) は管理設定なので範囲外)。

1. **信頼がないこと。** changelog(または任意の L2)と triage(L1)の CI のログの claude の stderr に `Ignoring N permissions.allow entries`(公式ドキュメントでは「this workspace has not been trusted」の警告)が出る。ランナーの `~/.claude.json` に `hasTrustDialogAccepted` がない。
2. **maker のコマンドが通ること。** 各 caller の1回の実行で、`::warning::Agent permission_denials:` の行(`usage.sh` の要約)が出ないか、出ても Task 2 の表で「意図して許さない」としたものだけであること。特に: maker の合成の `git diff --name-only origin/<base>...HEAD -- . ':!.loop/'`(全 L2)、`bash .claude/skills/<x>-validation/scripts/validate.sh`(refactor、ci-sweeper、autofix、pr-revise)、`git remote get-url origin`、`gh repo view`(triage)、pr-review の `/code-review` が使うコマンド(`git` の読み取り、`gh pr diff`)。拒否が出たら、その caller の規則を別の変更で足す。
3. **固定の拒否が効くこと。** pr-review か triage の実行の後、`permission_denials` に `gh pr review` や `gh issue comment` が出たときに、ジョブが止まらずに続き、GitHub に書き込みがないこと(ログで見る。意図して打たせるテストは行わない)。
4. **checker が判定できること。** `dontAsk` の checker が、差分を読んで APPROVE か REJECT の JSON を出す(changelog と pr-revise で1回ずつ)。
5. **skill の `allowed-tools` と導入先の `deny`・`ask`・hooks。** この repo の skill には `allowed-tools` がない(`git grep -n "allowed-tools" -- .claude/skills .agents/skills` で確かめる)。導入先の `allowed-tools` は信頼に関係なく効く(公式ドキュメント「Workspace trust never gates a skill's allowed-tools」)ので、別のリポジトリでは CI の許可が広がり得る(spec「方向」第6項 (1)。管理設定でだけ止められる)。この repo の `ask: Edit(.github/workflows/**)` で ci-sweeper の workflow の編集が拒否されること、Stop の hook が CI の maker で動くことは、今と同じであることだけを見る。
6. **MCP のツール。** `.mcp.json` のサーバは接続されるが、`mcp__github` などのツールの呼び出しは規則がないので拒否される。`permission_denials` に `mcp__` が出るかを見る(出たら、spec「方向」第1項の「`.mcp.json` は使う」との関係を owner が決める)。

## Self-review(writing-plans のチェックリスト)

- **spec の網羅:** 「方向」第2項(信頼の付与をやめる、`--setting-sources project` を残す)→ Task 1。第3項(許可リストの組み直しを同じ変更で)→ Task 2。第4項(`--permission-mode` を毎回明示、`--disallowedTools`、前方一致の穴)→ Task 1 と Global Constraints の固定の一覧。第5項(管理設定)→ 範囲外(Global Constraints)。第6項(残る穴)→ 実機の確認 5・6 と「spec との差」。第8項(実機の確認)→ 「リリース後の実機の確認」。「ビルダーに任せること」の更新の一覧(`loop-caller-inputs-reference.md`、bats、`run.bats:57`、入力の説明5か所、triage のコメント、`agent.sh` の冒頭、`grant_claude_workspace_trust` の削除)→ Task 1・2・3。`:98`(信頼が他に何も制御しないことの確認)→「spec との差」で確認結果を書いた。`:99`(書き込みの系統を外す)→ 固定の拒否と Task 2 の `no caller allowlist repeats …`。
- **プレースホルダー:** なし。workflow の設計の文書の行は Task 3 で行番号か「行を足す位置」で決めた。
- **名前の一貫性:** `CLAUDE_PLATFORM_ALLOW_RULES` / `CLAUDE_PLATFORM_DENY_RULES` / `append_claude_permission_args` / `acceptEdits` / `dontAsk` / `V(...)` / `triage_block` は全 Task で同じ綴り。
- **分量:** スクリプトの本体は書かず、引数の順、固定の値、テストの名前と期待値、caller ごとの表だけにした。

## spec との差(HEAD `cbe83740` で確かめた値)

- 行番号: `grant_claude_workspace_trust` は spec の `:164-197` → doc が `:163-196`、本体が `:197-239`(削除は `:163-239`)。checker の呼び出し `verifier.sh:376` → `:393`(`run_agent_capture "${output_file}" "false"`)。`agent.bats:91-114` → trust のテストは `:91-153` の5件。`loop-caller-inputs-reference.md:222-226` → 表は `:221-226`、信頼の段落は `:228`。`ci-loop-agent.yaml:104` → キーが `:104`、説明が `:106`。triage のコメントは spec の `:124-127`(`:102`)と `:125-128`(`:100`)が食い違う。HEAD は `:125-128`。maker の合成のプロンプト `agent.sh:125`、`append_claude_permission_args` `:51-65`、呼び出し `:434`、冒頭 `:14-17`・`:30-31`、`run.bats:57`、入力の説明 `ci-loop-caller.yaml:102`・`ci-loop-caller-entity.yaml:103`・`loop-execute/action.yml:72`・`loop-agent-once/action.yml:29` は spec のとおり。
- **信頼が他に何を制御するか(spec `:98` の未決)。** 公式ドキュメントの「What runs before you trust a folder」では、信頼がないと、`permissions.allow`・`additionalDirectories` に加えて、project の subagent の frontmatter の hooks と inline の `mcpServers`、`@skills-dir` の plugin、`extraKnownMarketplaces`、`.mcp.json` の `headersHelper` も使われない。この repo には該当がない(HEAD の `.claude/settings.json` に `additionalDirectories`・`extraKnownMarketplaces` がない。`.claude/agents/test-engineer.md` の frontmatter に hooks・`mcpServers` がない。`.mcp.json` に `headersHelper` がない)。導入先では、これらが CI で止まる(意図した変更)。
- **「CI の結果が導入先の設定に左右されない」(spec `:52` の理由 (2))は、この手段では一部しか満たさない。** `--setting-sources project` を残すので、導入先の `deny`・`ask`(`claude -p` では拒否)、hooks、`env`、`apiKeyHelper`、skill の `allowed-tools` は効く。spec `:50` の「`.claude/settings.json` はデフォルトブランチからも読まない」と、`:62-63` の「deny と hooks は効いたまま」は食い違う。この plan は `:62-63`(後の追記)に従った。この repo では `ask: Edit(.github/workflows/**)` が ci-sweeper の `.github/**`、`ask: Edit(go.mod)`・`Edit(package.json)` が tech-debt の allowlist と衝突している(今も同じ。Review Focus 5)。
- **MCP。** spec `:61` は「`.mcp.json` は使う」とするが、ツールの呼び出しは allow が要る。今は導入先の `mcp__github` などの allow で動いていた。この plan は MCP の規則を足さない(skill の文面に MCP の指示がない)ので、CI では MCP のツールが実質使えなくなる。必要なら owner が caller の規則に `mcp__<server>` を足すかを決める(実機の確認 6)。`WebFetch`・`WebSearch` も同様(事前承認のドキュメントのドメインを除く)。
- **固定の基準(spec `:55` の (a)/(b))。** この plan は (b) を選んだ: プラットフォームが読み取りの git 4件を持つ。根拠は、プラットフォーム自身のプロンプト(`agent.sh:125`)と checker の判定が `git diff` を要すること、git の読み取りの形が CLI の組み込みの読み取りの一覧に入るかの細目がドキュメントに無いこと。`agent.sh:14` の「The action grants no tool permissions of its own」は書き換える。`git remote get-url` などその他は caller ごと(a)にした。
- **拒否の一覧の入力。** spec `:56` は「deny の入力を足すか」を未決とした。配信の spec のアンチゴールにより、caller の入力は作らず、固定の一覧にした。caller が拒否を足す手段は無い(導入先の `.claude/settings.json` の `deny` は効くので、導入先はそこで足せる)。
- **checker のモード。** spec `:64` は「`dontAsk`、または maker に `acceptEdits`」。この plan は checker を `dontAsk` にした。今の checker は既定のモードで、信頼で有効になった導入先の `Edit(**/*.md)` などで編集もできた。その能力がなくなる(意図した変更)。
- **検証のスクリプトの形。** skill は「run from this skill directory」(`go-validation`・`markdown-validation` の `SKILL.md`)と書くが、`cd` と `bash scripts/validate.sh` の組み合わせを許すと、任意のディレクトリの `scripts/validate.sh` を許すことになる。この plan は caller の maker の指示で `bash .claude/skills/<skill>/scripts/validate.sh` の形に固定した(4つの `validate.sh` は `SCRIPT_DIR` で自分の場所を解くので、リポジトリのルートから動く)。skill の文面は範囲外なので変えない。
- **残る危険(spec `:57`、`:66` と同じ)。** 作業ツリーのスクリプトを `bash` で動かす規則(検証のスクリプト)は、maker がそのスクリプトを編集できるので、実質は任意のコマンドの実行と同じである(今の `Bash(bash:*)` よりは狭いが、境界ではない)。境界は agent ジョブの読み取りのトークンと、finalize の push の検証(credential-isolation)である。
