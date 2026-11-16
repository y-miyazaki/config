# 定期実行での取り込み: PR 1(段階 A'、プラットフォーム) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** detect が `result.items` で対象ごとのターゲットを返せるようにし、それを支える基盤(prune、`write_state` の再試行、作業ブランチ名、artifact 名、run-log のキー)を足す。triage と autofix の挙動は変えない。

**Architecture:** 汎用の機能だけを platform に足す。items モードは caller の入力 `detect_items`(既定 `false`)で明示し、`false` のときは既存の順序と挙動のまま。純粋関数は新しい `loop-detect/lib/items.sh` と `lib/loop/target_slug.sh` に置き、`detect.sh` は呼ぶだけにする。

**Tech Stack:** bash、jq、gh、GitHub Actions(composite と reusable workflow)、bats。

**Spec:** `docs/superpowers/specs/2026-11-11-loop-scheduled-intake-design.md`(第4節、第14節の PR 1)。食い違ったら spec が正。triage と autofix の定期実行(PR 2〜4)はこの計画の範囲外。

## Global Constraints

- 変更した shell には、同じ commit で対の bats を足す(`.claude/rules/bats.md` BAT-01)。テストの置き場所は既存の `test/bats/<source と同じ相対パス>.bats`。header は `# Tests for <path>` と `# Use cases:`、`@test` は a-z 順、`setup()` と `teardown()` を持つ。
- bats は**触ったディレクトリだけ**を走らせる(全体のスイートは走らせない)。
- 新しい shell の関数は header の Globals / Arguments / Outputs / Returns を書き、a-z 順に置く(`.claude/rules/shell-script.md`)。sourced lib には `set -euo pipefail` と `main` を置かない。
- `.github/actions/**` と `.github/workflows/ci-*` は配布物。consumer のパスを埋め込まない。composite から composite を `uses:` しない。共有ロジックは `.github/actions/lib/loop/` に置く(`.github/workflows/CLAUDE.md`)。
- workflow / action の map のキーは a-z 順(ORD-01)。
- `.github/workflows/` の変更は、actionlint などを Stop hook が走らせる。手では再実行しない(AGENTS.md)。
- 既存の意味を変えない: `error` は `consecutive_failures` を増やさない。`detect_items: false` の挙動は一切変えない。
- キー: `integration:<branch>#<key>`。`key` は `^[A-Za-z0-9._-]+(:[A-Za-z0-9._-]+)*$`、64文字以下、`..` を含まず、先頭と末尾が `.` でない。
- ブランチ名: `<prefix>/<skill>/<YYYYMMDD-HHMMSS>-<slug>`。`slug` は最大32文字 + `-` + キー全体の sha256 先頭8桁(常に付ける)。`push_agent_branch.sh` の suffix の正規表現は `^[0-9]{8}-[0-9]{6}(-[A-Za-z0-9._-]{1,48})?$`。
- commit は Conventional Commits。末尾に `Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>`。
- 配布物の変更後の SHA pin 更新とタグの push は、人間の承認を取る(Task 9)。

## Review Focus

1. **`detect_items: false` の回帰。** 既存の候補の順序、breaker / pending の判定、出力が変わる → Task 6 に「`detect_items` 未指定で既存の `detect.bats` の全ケースが通る」ことと、「false のとき items を返す detect を無視する」テスト。
2. **古い `integration:main` の breaker が items モードの全件を止める。** → Task 6 に「`integration:main` の `consecutive_failures: 3` でも、`integration:main#issue:1` は拾われる」テスト。
3. **正規化後にキーが衝突してブランチ名が重なる(`issue:1-2` と `issue-1:2`)。** → Task 4 に、2つで名前が違うテスト。
4. **`push_agent_branch.sh` が新しいブランチ名を拒否して、L2 の push が全件失敗する。** → Task 4 に、新旧両方を受けるテスト。
5. **`write_state` の再試行が `[remote rejected]`(ruleset の拒否)でも走る、または台帳ファイルを消す。** → Task 2 に、再試行しないケースのテスト。

---

### Task 1: prune の拡張(`#` を含むキー)

**Files:**

- Modify: `.github/actions/loop-finalize/lib/prune_targets.sh`(`prune_targets_json` の jq)
- Test: `test/bats/.github/actions/loop-finalize/lib/prune_targets.bats`(存在しなければ新規。先に `ls` で確認する)

**Interfaces:**

- Produces: `prune_targets_json` の挙動の拡張(関数の署名は変えない)。

- [ ] **Step 1: 失敗するテストを書く**
      `prune_targets.bats` に、`prune_targets_json` へ渡す JSON のフィクスチャで次の `@test` を足す(`last_run` は31日前と1日前の UTC 日付で作る):
  - `prune removes hash key when no pending and older than 30 days regardless of outcome`(`integration:main#issue:1`、outcome `pr_created`、31日前 → 消える)
  - `prune keeps hash key with pending`
  - `prune keeps hash key within 30 days`
  - `prune keeps hash key with missing last_run`
  - `prune keeps plain integration key even when aged`(既存の挙動)
  - `prune still removes aged terminal pull_request key`(既存の挙動)
- [ ] **Step 2: 失敗を確かめる**
      Run: `bats test/bats/.github/actions/loop-finalize/lib/prune_targets.bats`
      Expected: 新しい `hash key` のテストが FAIL。
- [ ] **Step 3: 実装**
      `prune_targets_json` の `with_entries` で、`has_pending` の次、`startswith("pull_request:")` の**前**に、`(.key | contains("#"))` の分岐を置く(`aged` なら `empty`、そうでなければ `.`)。`aged` は既存の定義を使うので、`last_run` が欠けると残る。header の Design Rules も更新する。
- [ ] **Step 4: 通ることを確かめる**
      Run: `bats test/bats/.github/actions/loop-finalize/lib/prune_targets.bats`
      Expected: 全 PASS。
- [ ] **Step 5: Commit**

```bash
git add .github/actions/loop-finalize/lib/prune_targets.sh test/bats/.github/actions/loop-finalize/lib/prune_targets.bats
git commit -m "feat(loop): prune aged per-target integration keys"
```

---

### Task 2: `write_state` の再試行

**Files:**

- Modify: `.github/actions/loop-finalize/lib/write_state.sh`(`commit_and_push_state`、`load_state_tmp`、`main`)
- Test: `test/bats/.github/actions/loop-finalize/lib/write_state.bats`(既存を読んで、git のモックの作り方に合わせる)

**Interfaces:**

- Produces: `is_push_race_error <stderr_text>`(0: `! [rejected] ... (fetch first|non-fast-forward)` を含み、`[remote rejected]` を含まない)。`WRITE_STATE_MAX_RETRIES=3`(env で上書き可)。

- [ ] **Step 1: 失敗するテストを書く**
      次の `@test` を足す。git は `BATS_TEST_TMPDIR` 配下の本物の bare リポジトリで作り、競合は別の clone から先に push して起こす:
  - `is_push_race_error matches fetch first` / `matches non-fast-forward` / `rejects remote rejected`
  - `write_state retries after non-fast-forward and keeps both targets`(別の clone が別キーを先に push → 再試行で両方のキーが残る)
  - `write_state gives up after 3 retries and opens state PR fallback`(`gh` をモックし、競合を3回起こし続ける)
  - `write_state does not retry on remote rejected`(pre-receive hook で拒否 → 再試行せず PR フォールバック)
  - `write_state does not retry when FINALIZE_COMMIT_PATHS is set`
  - `write_state retry leaves no stale temp state file`(`STATE_TMP` の一時ファイルの数を比べる)
- [ ] **Step 2: 失敗を確かめる**
      Run: `bats test/bats/.github/actions/loop-finalize/lib/write_state.bats`
      Expected: 新しいテストが FAIL。
- [ ] **Step 3: 実装**
      `commit_and_push_state` の push の stderr を捕まえる。`is_push_race_error` が真、かつ `FINALIZE_COMMIT_PATHS` が空、かつ試行が `WRITE_STATE_MAX_RETRIES` 未満のときだけ、次を繰り返す: `git fetch origin <READ_BRANCH>` → `git reset --hard origin/<PUSH_BRANCH>` → 前の `STATE_TMP` を消して `load_state_tmp` → `prune_targets_by_retention` → `resolve_consecutive_failures` → `write_target_state` → `commit` → `push`。それ以外は既存の PR フォールバックに進む。再試行のループは `main` から呼べる別の関数(`retry_state_write`)に切る。
- [ ] **Step 4: 通ることを確かめる**
      Run: `bats test/bats/.github/actions/loop-finalize/lib/write_state.bats`
      Expected: 全 PASS(既存のテストも)。
- [ ] **Step 5: Commit**

```bash
git add .github/actions/loop-finalize/lib/write_state.sh test/bats/.github/actions/loop-finalize/lib/write_state.bats
git commit -m "feat(loop): retry state push on non-fast-forward races"
```

---

### Task 3: run-log に `target_key` を足す

**Files:**

- Modify: `.github/actions/loop-run-log/lib/append.sh`(`loop_run_log_build_entry` の13番目の引数)、`.github/actions/loop-run-log/lib/run.sh`、`.github/actions/loop-run-log/action.yml`(入力 `target_key`、既定 `""`)、`.github/workflows/ci-loop-agent.yaml`(L1 と L2 の run-log の `with:`)
- Test: `test/bats/.github/actions/loop-run-log/lib/append.bats`(既存。`ls` で名前を確認)、`test/bats/.github/actions/loop-run-log/action.bats`

**Interfaces:**

- Produces: `loop_run_log_build_entry ... <failure_message> <target_key>`(13番目、省略可)。run-log の JSON に、空でないとき `target_key` を**末尾**に足す。
- `ci-loop-agent.yaml` が渡す値: `fromJSON(inputs.target_json).key`(entity では handoff のキー `entity:issue:<N>`、items では `integration:<branch>#<key>`)。

- [ ] **Step 1: 失敗するテストを書く**
      `loop_run_log_build_entry ignores target_key when empty`(出力が従来と完全に同じ)、`loop_run_log_build_entry appends target_key last`(`keys_unsorted` の最後が `target_key`)、`budget_exceeded still counts entries that carry target_key`(`loop-detect/lib/guards.bats` に足す)。`action.bats` に、入力 `target_key` が定義され既定が空であること。
- [ ] **Step 2: 失敗を確かめる**
      Run: `bats test/bats/.github/actions/loop-run-log test/bats/.github/actions/loop-detect/lib/guards.bats`
      Expected: 新しいテストが FAIL。
- [ ] **Step 3: 実装**
      `append.sh` に13番目の引数 `target_key` と `--arg target_key`、最後の `+ (if ($target_key | length) > 0 then {target_key: $target_key} else {} end)`。`run.sh` が `TARGET_KEY` を渡す。`action.yml` に入力と `env` を足す(a-z 順)。`ci-loop-agent.yaml` の L1(387行付近)と L2(648行付近)の `with:` に `target_key: ${{ fromJSON(inputs.target_json).key }}` を足す。
- [ ] **Step 4: 通ることを確かめる**
      Run: `bats test/bats/.github/actions/loop-run-log test/bats/.github/actions/loop-detect/lib/guards.bats`
      Expected: 全 PASS。
- [ ] **Step 5: Commit**

```bash
git add .github/actions/loop-run-log .github/workflows/ci-loop-agent.yaml test/bats/.github/actions/loop-run-log test/bats/.github/actions/loop-detect/lib/guards.bats
git commit -m "feat(loop): record target_key in run log entries"
```

---

### Task 4: 作業ブランチ名と `push_agent_branch.sh` の検証

**Files:**

- Create: `.github/actions/lib/loop/target_slug.sh`
- Modify: `.github/actions/loop-worktree-setup/action.yml`(入力 `target_key`、ブランチ名)、`.github/actions/loop-finalize/lib/push_agent_branch.sh`(259行付近と326-328行付近)、`.github/workflows/ci-loop-agent.yaml`(L2 の worktree-setup の `with:`)
- Test: `test/bats/.github/actions/lib/loop/target_slug.bats`(新規)、`test/bats/.github/actions/loop-worktree-setup/action.bats`(81行付近の既存の期待を更新)、`test/bats/.github/actions/loop-finalize/lib/push_agent_branch.bats`(380-381行付近)

**Interfaces:**

- Produces: `target_slug <target_key>` → stdout に `<slug>-<hash8>`(`#` 以降を `[A-Za-z0-9._-]` に正規化。`:` は `-`。先頭と末尾の `.` を除く。`..` は `.` に、`.lock` で終わるなら `-lock`。32文字に切る。`hash8` はキー全体の `sha256` の先頭8桁)。キーが空なら何も出さず rc 0。
- Produces: `loop-worktree-setup` の入力 `target_key`(既定 `""`)。空なら従来の名前。

- [ ] **Step 1: 失敗するテストを書く**
      `target_slug.bats`: `target_slug normalizes colon to dash`、`target_slug differs for issue:1-2 and issue-1:2`、`target_slug truncates long keys to 32 chars plus hash`、`target_slug output passes git check-ref-format as branch suffix`、`target_slug strips leading and trailing dots`、`target_slug empty key prints nothing`。`push_agent_branch.bats`: `validate_agent_branch accepts suffix with slug`、`validate_agent_branch still accepts plain timestamp suffix`、`validate_agent_branch rejects suffix over 48 slug chars`。`action.bats`: 入力 `target_key` が定義されていること。
- [ ] **Step 2: 失敗を確かめる**
      Run: `bats test/bats/.github/actions/lib/loop/target_slug.bats test/bats/.github/actions/loop-finalize/lib/push_agent_branch.bats test/bats/.github/actions/loop-worktree-setup/action.bats`
      Expected: 新しいテストが FAIL。
- [ ] **Step 3: 実装**
      `target_slug.sh` を書く(sourced lib。`.github/actions/lib/loop/_resolve.sh` の `LOOP_ACTION_LIB_DIR` で `loop-worktree-setup` から読む)。`action.yml` の `DATE=...` の次に、`target_key` があれば `BRANCH="${BRANCH}-$(target_slug "${TARGET_KEY}")"` を足す(既存の正規表現の検証はそのまま通る)。`push_agent_branch.sh` の suffix の正規表現を Global Constraints のものに広げ、エラーメッセージを `YYYYMMDD-HHMMSS[-slug]` に直す。`ci-loop-agent.yaml` の L2 の `with:` に `target_key: ${{ fromJSON(inputs.target_json).key }}` を足す。実装時に `rg "loop/"` で、ブランチ名から対象を引く処理がないことを確認する。
- [ ] **Step 4: 通ることを確かめる**
      Run: Step 2 と同じ。Expected: 全 PASS。
- [ ] **Step 5: Commit**

```bash
git add .github/actions/lib/loop/target_slug.sh .github/actions/loop-worktree-setup .github/actions/loop-finalize/lib/push_agent_branch.sh .github/workflows/ci-loop-agent.yaml test/bats/.github/actions
git commit -m "feat(loop): per-target agent branch names"
```

---

### Task 5: items の純粋関数(`loop-detect/lib/items.sh`)

**Files:**

- Create: `.github/actions/loop-detect/lib/items.sh`
- Test: `test/bats/.github/actions/loop-detect/lib/items.bats`(新規)

**Interfaces:**

- Produces(すべて sourced lib。失敗は rc 1 と stderr の `::error::`):
  - `validate_item_key <key>` → rc 0/1(Global Constraints のキーの規則)。
  - `item_target_key <branch> <key>` → stdout `integration:<branch>#<key>`。
  - `extract_items <detect_result_json>` → stdout に `items` の compact な JSON 配列。`items` がなければ空(rc 0)。キーの不正と重複は rc 1。
  - `item_result_json <item_json>` → stdout `{"status":"ok","skip":false,"result":{<context>,"key":"<key>"}}`。
  - `order_items_by_last_run <state_file> <branch> <items_json>` → 要素を、キーの state の `last_run` が古い順(state なしが先)に並べ、同順位は入力順を保つ。
- Consumes: `read_target_state`(`state.sh`)。

- [ ] **Step 1: 失敗するテストを書く**
      `validate_item_key accepts issue:123`、`... rejects empty / double dot / leading dot / trailing dot / space / hash / over 64 chars`、`extract_items fails on duplicate keys`、`extract_items fails on invalid key`、`extract_items returns nothing when items absent`、`extract_items returns empty array for empty items`、`item_result_json keeps only that item's context and adds key`、`item_result_json does not leak other items`、`order_items_by_last_run puts missing state first`、`order_items_by_last_run orders oldest first and is stable`。
- [ ] **Step 2: 失敗を確かめる**
      Run: `bats test/bats/.github/actions/loop-detect/lib/items.bats`
      Expected: FAIL(`items.sh` がない)。
- [ ] **Step 3: 実装**
      上の署名どおりに実装する。jq は `--arg`/`--argjson` で値を渡す。`order_items_by_last_run` は、各要素の `last_run`(なければ空文字)を `jq` で付けて `sort_by` する(`sort_by` は安定)。
- [ ] **Step 4: 通ることを確かめる**
      Run: `bats test/bats/.github/actions/loop-detect/lib/items.bats`
      Expected: 全 PASS。
- [ ] **Step 5: Commit**

```bash
git add .github/actions/loop-detect/lib/items.sh test/bats/.github/actions/loop-detect/lib/items.bats
git commit -m "feat(loop): add per-target items helpers for detect"
```

---

### Task 6: `detect_items` を detect に配線する

**Files:**

- Modify: `.github/actions/loop-detect/lib/detect.sh`(`append_detect_candidate` を分割、`main`、`validate_detect_inputs`)、`.github/actions/loop-detect/action.yml`(入力 `detect_items`、`env` に `DETECT_ITEMS`)、`.github/workflows/ci-loop-caller.yaml`(入力 `detect_items`、detect への `with:`)、`.github/actions/loop-detect/lib/_init.sh`(`items.sh` を source)
- Test: `test/bats/.github/actions/loop-detect/lib/detect.bats`(既存のスタイルに合わせる)、`test/bats/.github/workflows/`(caller の入力の parity。`loop-caller-parity.bats` を `ls` で確認して更新)

**Interfaces:**

- Consumes: Task 5 の関数。
- Produces: 入力 `detect_items`(boolean、既定 `false`)。`DETECT_ITEMS=true` のとき: `validate_detect_inputs` が「`DETECT_BRANCH_MATCH` がちょうど1つのブランチで `DETECT_PR_ENABLED` が `false`」を要求する(満たさなければ rc 1)。処理順は checkout → detect の実行 → `extract_items` → 要素ごとに `read_target_state`(キー `integration:<branch>#<key>`)で breaker と pending を判定。止めた要素は `::warning` を出し `CIRCUIT_BREAKER_BLOCKED` / `PENDING_PR_BLOCKED` を増やす。残りを `order_items_by_last_run` で並べ、要素ごとに候補を作る(`target_json` は `mode: integration`、`key` は item のキー、`entity` は `{kind, number}` のみで `handoff_key` なし、`from.since` はその要素の `last_sha`、なければ `HEAD~10`)。`items` が空配列または要素が全部止まれば、既存の `write_empty_candidates_outputs` を使う。`DETECT_ITEMS` が `false` または未設定のときは**今までのコードを通る**。

- [ ] **Step 1: 失敗するテストを書く**
      `detect.bats` に: `items mode creates one candidate per item with per-item key`、`items mode ignores branch-level circuit breaker`(Review Focus 2)、`items mode skips item with open breaker and reports circuit_breaker skip_reason when all blocked`、`items mode skips item with pending pr`、`items mode orders by last_run oldest first before cap`、`items mode caps at detect_max_targets`、`items mode candidate result contains only that item's context`、`items mode since falls back to HEAD~10 without state`、`items mode requires single branch and detect_pr_enabled false`、`items mode fails on invalid or duplicate item key`、`items empty array behaves like skip`、`items ignored when detect_items false`(Review Focus 1)。caller の parity: 入力 `detect_items` が `ci-loop-caller.yaml` と `loop-detect/action.yml` の両方にあり、既定が `false`。
- [ ] **Step 2: 失敗を確かめる**
      Run: `bats test/bats/.github/actions/loop-detect/lib/detect.bats`
      Expected: 新しいテストが FAIL、既存のテストは PASS。
- [ ] **Step 3: 実装**
      `append_detect_candidate` を、(a) checkout と detect の実行、(b) 候補の組み立て(`target_json_builder` 以降)に分ける。items でないときは今までと同じ順で (a)→既存の state 判定→(b)。items のときは (a)→`extract_items`→要素ごとの state 判定→(b) を要素ごとに呼ぶ。分割は動作を変えない(既存のテストが全部通ることで確かめる)。
- [ ] **Step 4: 通ることを確かめる**
      Run: `bats test/bats/.github/actions/loop-detect test/bats/.github/workflows`(`loop-caller-parity.bats` のあるディレクトリ。パスは `ls` で確認)
      Expected: 全 PASS。
- [ ] **Step 5: Commit**

```bash
git add .github/actions/loop-detect .github/workflows/ci-loop-caller.yaml test/bats
git commit -m "feat(loop): detect_items mode returns per-target candidates"
```

---

### Task 7: `handoff_artifact_suffix`(entity の matrix 用)

**Files:**

- Modify: `.github/actions/loop-entity-detect/action.yml`(入力 `handoff_artifact_suffix`、artifact 名は136行と142行付近の2か所)、`.github/workflows/ci-loop-caller-entity.yaml`(入力と、detect への `with:`)
- Test: `test/bats/.github/actions/loop-entity-detect/`(既存の action の bats。`ls` で確認)、parity の bats

**Interfaces:**

- Produces: 入力 `handoff_artifact_suffix`(既定 `""`)。artifact 名は `loop-handoff-${run_id}${suffix}`。detect の出力 `handoff_artifact_name` に同じ値が入る(`ci-loop-agent.yaml` の download はこの出力を使うので変更しない)。

- [ ] **Step 1: 失敗するテストを書く**
      `handoff artifact name equals loop-handoff-run_id when suffix empty`、`handoff artifact name appends suffix`、入力 `handoff_artifact_suffix` が `ci-loop-caller-entity.yaml` と action の両方にあり既定が空であること。
- [ ] **Step 2: 失敗を確かめる**
      Run: `bats test/bats/.github/actions/loop-entity-detect`(と parity)
      Expected: 新しいテストが FAIL。
- [ ] **Step 3: 実装**
      名前を作るステップ(136行付近)と upload の `name:`(142行付近)で同じ式 `loop-handoff-${GITHUB_RUN_ID}${SUFFIX}` を使う。suffix は `^[A-Za-z0-9._-]*$` に限り、違えばエラーにする。
- [ ] **Step 4: 通ることを確かめる**
      Run: Step 2 と同じ。Expected: 全 PASS。
- [ ] **Step 5: Commit**

```bash
git add .github/actions/loop-entity-detect .github/workflows/ci-loop-caller-entity.yaml test/bats
git commit -m "feat(loop): optional suffix for entity handoff artifact name"
```

---

### Task 8: permissions、入力の参照ドキュメント、整合の検査

**Files:**

- Modify: `.github/workflows/ci-loop-caller.yaml`(detect ジョブの `permissions` に `issues: read`。a-z 順)、`docs/explanation/loop-engineering/workflows/loop-caller-inputs-reference.md`(`detect_items`、`handoff_artifact_suffix`)、`docs/reference/specification.md`(`result.items`、run-log の `target_key`、`loop-worktree-setup` の `target_key`)、`docs/explanation/loop-engineering/loop-engineering-design.md`(STATE Files の `#` のキー、prune)、`common-loop-triage-format.md` と `loop-capable-skills.md`(detect JSON の `result.items`。場所は `rg -l "detect JSON"` で確認)
- Test: 既存の `loop_input_topology.py` とその bats、`loop-caller-parity.bats` を、新しい入力に合わせて更新

- [ ] **Step 1: 失敗するテストを書く(または既存の検査が失敗するのを確かめる)**
      Run: `bats test/bats/.github/workflows`(parity の bats のあるディレクトリ)
      Expected: Task 6・7 の入力の追加後、ドキュメントと topology が古いために FAIL するものがあれば、それを確認する。
- [ ] **Step 2: 実装**
      上のファイルを更新する。docs は DOC-05(`docs/` の相対リンクは文書の題名で)、TERM-10(「上記」を使わない)に従う。`mkdocs.yml` の nav は、ファイルを足さないので変更しない。
- [ ] **Step 3: 通ることを確かめる**
      Run: Step 1 と同じ。Expected: 全 PASS。
- [ ] **Step 4: Commit**

```bash
git add .github/workflows/ci-loop-caller.yaml docs test/bats
git commit -m "docs(loop): document detect_items, result.items and target_key"
```

---

### Task 9: SHA pin の更新とリリース(人間の確認が必要)

Task 1〜8 が main に入った後。`.github/workflows/CLAUDE.md` の Pins に従い、2段で更新する。

- [ ] **Step 1: 人間に確認する**
      タグの作成と push は外部に出る操作。対象の SHA とバージョンを示して承認を取る(承認なしに実行しない)。
- [ ] **Step 2: 承認の後、既存のリリース手順で更新する**
      action のリリース → `ci-loop-agent.yaml` の `loop-execute` / `loop-finalize` / `loop-run-log` / `loop-worktree-setup` の pin → `ci-loop-caller.yaml` の `loop-detect` / `loop-run-log` / `ci-loop-agent` の pin → `ci-loop-caller-entity.yaml` の `loop-entity-detect` の pin。`test/bats/.github/pin_config_actions.bats` を走らせる。
- [ ] **Step 3: 回帰の確認(`AGENT_TOKEN` が有効になってから)**
      既存の `on-loop-*` が1回ずつ動くこと(`detect_items` は使われないので挙動が変わらない)を `gh workflow run` で確かめる。`AGENT_TOKEN` が未更新の間は、この Step は保留し、保留したことを PR に書く。
