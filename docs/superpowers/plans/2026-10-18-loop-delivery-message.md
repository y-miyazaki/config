# Loop Delivery Message Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `delivery: issue_comment` と `delivery: pr_review` を実装し、triage(L1)と pr-review(L2)を移す。GitHub への書き込み(投稿とラベル)をエージェントと hook から外し、`loop-finalize` の1か所で、Meta とフッター付きで1回だけ行う。ラベルは caller の許可リストの範囲だけで付け外しする。

**Architecture:** エージェント(L1)か `finalize_script`(L2/L3)が、`LOOP_MESSAGE_DIR` に投稿ファイル(`message.md` / `review.json` / `message_labels.json`)を書く。L1 は `loop-agent-once` がファイルを JSON(`message_json`)にしてジョブの出力で finalize-l1 に渡し、`loop-finalize` が最初にファイルへ戻す。配信は新しい共有ライブラリ `.github/actions/lib/loop/deliver_message.sh` の `deliver_loop_message` が行い、`loop-finalize` の新しいステップ Deliver Message から呼ぶ。検証は `delivery.sh` と `validate_loop_write_contract.sh` を広げ、detect の時点で失敗させる。

**Tech Stack:** GitHub Actions(reusable workflow、composite action)、bash、jq、gh、bats。

**Spec:** `docs/superpowers/specs/2026-10-18-loop-delivery-message-design.md`。この plan の「§N」は spec の第N節を指す。

## Global Constraints

- `delivery` の値: `issue_comment`(Issue の entity、L1/L2/L3)、`pr_review`(PR の entity、L2/L3)、`none`・`pr_create`・`pr_push`(現在のまま)、`issue_create`(予約値。"not implemented" で拒否)。
- L1 の `delivery` は `none` か `issue_comment`。L1 では `finalize_script` を拒否する。
- L2/L3 の `issue_comment` と `pr_review` は `finalize_script` が必須。
- `finalize_label_allowlist` は `delivery` が `issue_comment` か `pr_review` のときだけ許す(それ以外で空でなければ拒否)。改行区切り。
- `loop-detect`(branch caller)は `issue_comment` と `pr_review` を `validate_delivery_detect_config` で拒否する。
- 入力 `finalize_hook_script` は `finalize_script`、env `FINALIZE_HOOK_SCRIPT` は `FINALIZE_SCRIPT` に改名する。互換の処理は作らない。
- 投稿ファイル: `${LOOP_MESSAGE_DIR}/message.md`、`${LOOP_MESSAGE_DIR}/review.json`(`{"body","commit_id","comments","fallback_body"}`)、`${LOOP_MESSAGE_DIR}/message_labels.json`(`{"add":[...],"remove":[...]}`、任意)。`LOOP_MESSAGE_DIR` は `${{ runner.temp }}/loop-message`。
- `message_json` は `{"body": <message.md の内容>, "labels": <message_labels.json の内容 | null>}` の1行の JSON。artifact は使わない。
- L1 のプロンプトの末尾に足す行: `Loop message directory: <絶対パス>`(この文字列を `loop-agent-once`、triage の maker の指示、`SKILL.md` で同じに使う)。
- marker は `<!-- <loop_name>:v1 -->`。本文の先頭になければ付ける。Meta とフッターは `build_loop_meta_block "<outcome>" "<verdict>" "" "<agent_engine>" "<usage_json>" "<run_url>"` で、本文の末尾に1回だけ付ける(`pr_review` は `body` と `fallback_body` の両方)。
- 投稿の番号は `target_json` の `.entity.handoff_key // .key`(`entity:issue:<n>` / `entity:pr:<n>`)から取る。種別が `delivery` と合わなければ失敗にする。
- `pr_review` の `event` は常に `COMMENT`。HTTP 422 で `comments` が空でないときだけ、`comments` なしで `fallback_body` を本文にして1回だけ再試行する。
- ラベル: 付けるのは `POST repos/{o}/{r}/issues/<n>/labels` に `{"labels":[...]}` を1回(許可リストで絞った後に空なら呼ばない)。外すのは `DELETE repos/{o}/{r}/issues/<n>/labels/<URL エンコードした名前>` で、404 は成功。ラベルは投稿の前に行う。
- Deliver Message の失敗は `loop_failure_record "deliver_message" "<msg>" "${LOOP_FAILURE_FILE}"` で記録し、ステップを失敗させる。
- 新しい outcome: `issue_commented`、`pr_reviewed`。Determine Outcome の判定の順: override → エージェントの失敗(`error`)→ `REJECT`(`rejected`)→ `issue_comment` は `issue_commented`、`pr_review` は `pr_reviewed` → 既存の `has_changes` の判定。
- 出力 `outcome` と Write State の `OUTCOME` は `${{ steps.deliver.outputs.outcome || steps.outcome.outputs.value }}`。Deliver は本文が空のときだけ `outcome=unchanged` を書く。
- Delete Agent Branch の `if`: `always() && inputs.branch != '' && (inputs.verdict == 'REJECT' || inputs.delivery == 'none' || inputs.delivery == 'issue_comment' || inputs.delivery == 'pr_review')`。
- 権限: `agent-l1` から `issues: write` を外す。`finalize-l1` は `contents: write` と `issues: write`(`pull-requests: write` を外す)。`finalize-l2` に `issues: write` を足す。権限の許可リスト(`.claude/settings.json` ほか4ファイル)は変えない。
- triage の `finalize_label_allowlist`: `needs-triage`、`bug`、`feature`、`question`、`documentation`、`triage:needs-info`、`triage:ready`、`triage:failed`(`autofix` は入れない)。
- 配布する skill は `.apm/packages/github/.apm/skills/<skill>/` だけを編集し、`bash scripts/self/apm/sync_apm_artifacts.sh` で同期して、同期先を同じコミットに入れる。
- シェルの変更には bats を対にする(`.claude/rules/bats.md`、TEST-00)。Edit で `.sh` を編集した後は `shfmt -w <file>` を実行する。
- `ci-*` から `./.github/...` を参照しない。pin は変えない。リリースと pin の更新(`scripts/self/ci/pin_config_actions.sh`)はこの plan に含めない。最後の手動の手順として、明示の承認を得てから行う(「リリース(手動)」)。それまで push しない。

## Review Focus

1. **URL エンコードが要るラベル名の DELETE。** `triage:needs-info`(`:`)や、空白と `/` を含む名前が、`labels/triage%3Aneeds-info` のように1つのパスの要素として送られること。生の名前を連結すると、別のエンドポイントに当たるか 404 になり、黙って成功扱いになる。Task 5 に `deliver_loop_message encodes label names in DELETE paths` を置く。
2. **要求したラベルがすべて許可リストの外。** `{"labels":[]}` の POST をしない(GitHub が 422 を返し、投稿まで止まる)。警告を出し、本文は投稿する。Task 5 に `deliver_loop_message skips the POST when no requested label is allowlisted` を置く。
3. **`message_json` の往復で本文が変わる。** 複数行の Markdown、バッククォート、`EOF` だけの行、末尾の改行を含む `message.md` が、`loop_message_to_json` → `GITHUB_OUTPUT`(ランダムな区切り)→ `loop_message_from_json` を通って、バイト単位で同じになること。Task 4 と Task 7 に置く。
4. **`handoff_key` の種別と `delivery` の食い違い。** `issue_comment` に `entity:pr:7`、`pr_review` に `entity:issue:7` が来たら、gh を呼ばずに失敗する。`.entity.handoff_key` がなく `.key` だけのときも番号を取れる。Task 5 に置く。
5. **`always()` を足した Delete Agent Branch の波及。** `pr_create` で APPROVE、Create PR が失敗したとき、ブランチを消さない(`should_delete_rejected_branch` が 1 を返す)。`pr_review` で Deliver が失敗したときは消す。Task 3 に `keeps APPROVE branches for pr_create and pr_push`(既存)と `deletes for issue_comment and pr_review regardless of verdict and changes`、Task 6 に `if` の文字列の一致を置く。

---

## ファイル構成

| ファイル                                                                                                                              | 責務                                                                     | Task  |
| ------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------ | ----- |
| `.github/actions/loop-finalize/action.yml`                                                                                            | 改名、`message_json` の復元、Deliver Message、outcome の配線、削除の条件 | 1, 6  |
| `.github/actions/lib/loop/delivery.sh`                                                                                                | 値と種別と branch caller の検証                                          | 2     |
| `.github/actions/lib/loop/validate_loop_write_contract.sh`                                                                            | L1 の `issue_comment`、`finalize_script`、`finalize_label_allowlist`     | 2     |
| `.github/actions/loop-detect/`、`.github/actions/loop-entity-detect/`                                                                 | 新しい入力と検証の呼び出し                                               | 2     |
| `.github/actions/loop-finalize/lib/determine_outcome.sh`、`should_delete_rejected_branch.sh`                                          | 新しい outcome と削除の判定                                              | 3     |
| `.github/actions/lib/loop/loop_message.sh`(新規)                                                                                      | 投稿ファイルと `message_json` の往復                                     | 4     |
| `.github/actions/lib/loop/deliver_message.sh`(新規)                                                                                   | Deliver Message の本体                                                   | 5     |
| `.github/actions/loop-agent-once/`、`.github/actions/loop-execute/lib/agent.sh`、`.github/actions/lib/loop/entity_meta.sh`(削除)      | L1 の投稿ファイルと `--add-dir`、stdout の投稿の削除                     | 7     |
| `.github/workflows/ci-loop-agent.yaml`、`ci-loop-caller.yaml`、`ci-loop-caller-entity.yaml`、`scripts/self/ci/loop_input_topology.py` | ジョブの配線と権限、入力の受け渡し                                       | 8     |
| `.apm/packages/github/.apm/skills/github-pr-review/`、`on-loop-github-pr-review.yaml`                                                 | `render_review.sh` と caller の移行                                      | 9     |
| `.apm/packages/github/.apm/skills/github-issue-triage/`、`on-loop-github-issue-triage.yaml`                                           | 投稿ファイルを書く手順と caller の移行                                   | 10    |
| `docs/`                                                                                                                               | 契約と設計の記述                                                         | 1, 11 |

---

### Task 1: `finalize_hook_script` を `finalize_script` に改名する

**Files:**

- Modify: `.github/actions/loop-finalize/action.yml:25`(説明)、`:31-34`(入力)、`:40`(説明)、`:188`、`:193`、`:214`
- Modify: `.github/workflows/ci-loop-agent.yaml:126-130`、`:541`
- Modify: `.github/workflows/ci-loop-caller.yaml:185-189`、`:494`;`.github/workflows/ci-loop-caller-entity.yaml:152-156`、`:351`
- Modify: `.github/workflows/on-loop-ci-sweeper.yaml:132`、`on-loop-test-gap.yaml:81`、`on-loop-github-pr-review.yaml:9`、`:117`、`:130`(キー名だけ。値は Task 9)
- Modify: `scripts/self/ci/loop_input_topology.py:101`
- Modify(docs、語の置換だけ): `docs/reference/specification.md:391`、`:400`、`:498`;`docs/reference/loop-engineering-checklist.md:64`;`docs/explanation/loop-engineering/` の `loop-caller-reusable-design.md:272`、`loop-caller-workflows-design.md:94`、`:218`、`loop-engineering-design.md:22`、`:172`、`:211`、`:369`、`:780`、`multi-branch-loops-design.md:272`;`workflows/` の `loop-caller-inputs-reference.md:136`、`:225`、`:254`、`:255`、`:335`、`:420`、`loop-changelog-workflow-design.md:171`、`loop-ci-sweeper-workflow-design.md:137`、`:181`、`:238`、`:291`、`:307`、`loop-docs-updater-workflow-design.md:177`、`loop-github-pr-review-workflow-design.md:41`、`:83`、`:129`、`:148`、`:150`、`loop-refactor-workflow-design.md:152`、`loop-tech-debt-workflow-design.md:175`、`loop-test-gap-workflow-design.md:75`、`:103`、`:150`、`:236`、`:259`
- Test: `test/bats/github-actions/loop-caller-parity.bats:850-859`、`test/bats/.github/actions/loop-finalize/action_delivery.bats:62-74`、`test/bats/.github/actions/loop-finalize/action_finalize_hook_env.bats`

**Interfaces:** Produces: `loop-finalize` の入力 `finalize_script`、Run Finalize Hook の env `FINALIZE_SCRIPT`、reusable の入力 `finalize_script`。topology の `DECISIONS["finalize_script"] = ("finalize_hook_script", "L2+", "改名(投稿の配信 第1節)")`。

- [ ] **Step 1: 失敗するテストを書く。**
  - `loop-caller-parity.bats` の `old_names`(`:850-859`)に `finalize_hook_script` と `FINALIZE_HOOK_SCRIPT` を足す。
  - `action_delivery.bats` の `action inputs are the delivery contract in alphabetical order` の期待値で、`finalize_hook_script` を `finalize_script` にする(`finalize_commit_paths finalize_outcome_override finalize_script` の順)。
  - `action_finalize_hook_env.bats`: `FINALIZE_SCRIPT: ${{ inputs.finalize_script }}` を期待し、`if` は `inputs.finalize_script != ''` にする。
  - `test/bats/github-actions/loop-caller-parity.bats` に `@test "no tracked file outside docs/superpowers names finalize_hook_script"` を足す: `git -C "${ROOT}" grep -l -e finalize_hook_script -e FINALIZE_HOOK_SCRIPT -- . ':!docs/superpowers' ':!.agents' ':!.claude/skills' ':!apm_modules' ':!apm.lock.yaml' ':!.apm/packages/github/.apm/skills/github-pr-review/scripts/post_review.sh' ':!test/bats/github-actions/loop-caller-parity.bats'` の出力が空。`post_review.sh` の除外は Task 9 で外す。
- [ ] **Step 2: 失敗を確認する。** `bats test/bats/github-actions/loop-caller-parity.bats test/bats/.github/actions/loop-finalize/action_delivery.bats test/bats/.github/actions/loop-finalize/action_finalize_hook_env.bats`。Expected: FAIL(旧い名前が残っている)。
- [ ] **Step 3: 改名する。** Files の全箇所で語を置き換える。入力の並びはアルファベット順を保つ(ORD-01。`finalize_outcome_override` の後ろへ移す)。`loop_input_topology.py` の `DECISIONS` のキーも改める。docs は語だけを置き換え、文は変えない。
- [ ] **Step 4: 通ることを確認する。** Step 2 のコマンドと `bats test/bats/scripts/self/ci/loop_input_topology.bats`。Expected: PASS。
- [ ] **Step 5: コミットする。** `git add .github/actions/loop-finalize/action.yml .github/workflows/ci-loop-agent.yaml .github/workflows/ci-loop-caller.yaml .github/workflows/ci-loop-caller-entity.yaml .github/workflows/on-loop-ci-sweeper.yaml .github/workflows/on-loop-test-gap.yaml .github/workflows/on-loop-github-pr-review.yaml scripts/self/ci/loop_input_topology.py docs/reference docs/explanation test/bats/github-actions/loop-caller-parity.bats test/bats/.github/actions/loop-finalize`、`refactor(loop): rename finalize_hook_script to finalize_script`。

---

### Task 2: `delivery` と書き込みの契約の検証を広げる

**Files:**

- Modify: `.github/actions/lib/loop/delivery.sh:12-17`(Design Rules)、`:95-116`、`:135-164`、`:182-196`
- Modify: `.github/actions/lib/loop/validate_loop_write_contract.sh:9-21`、`:37-127`
- Modify: `.github/actions/loop-entity-detect/action.yml`(入力 `:41-48` 付近、env `:107-124`)、`.github/actions/loop-entity-detect/lib/detect.sh:211-217`
- Modify: `.github/actions/loop-detect/action.yml`(入力 `:40-77` 付近、env `:150-177`)、`.github/actions/loop-detect/lib/detect.sh:974-995`
- Test: `test/bats/github-actions/loop-delivery.bats`、`test/bats/github-actions/loop-write-contract.bats`、`test/bats/github-actions/loop-entity-detect.bats:82-103`、`:140-163`、`test/bats/github-actions/loop-detect-delivery.bats:52-81`、`:148-196`、`test/bats/.github/actions/loop-finalize/lib/parse_target.bats`

**Interfaces:**

- Produces `validate_delivery_value <delivery>`: `issue_comment`・`none`・`pr_create`・`pr_push`・`pr_review` で 0。`issue_create` は `::error::delivery issue_create is not implemented` で 1。そのほか(空を含む)は `::error::delivery must be issue_comment|none|pr_create|pr_push|pr_review (got: <v|empty>)` で 1。
- Produces `validate_delivery_target <delivery> <target_json>`: `issue_comment` は種別 `issue` だけ、`pr_review` は種別 `pr` だけを通す(`::error::delivery issue_comment allows only issue targets (got: <kind>)`、`pr_review` も同じ形)。
- Produces `validate_delivery_detect_config <delivery> <detect_pr_enabled> <detect_branch_match>`: `issue_comment`・`pr_review` は `::error::delivery <d> requires an entity caller (loop-entity-detect)` で 1(候補の有無に関係なく)。
- Produces `validate_loop_write_contract <level> <delivery> <agent_edit_target> <agent_edit_allowlist> <agent_edit_denylist> <agent_unchanged_verdict> <finalize_script> <finalize_label_allowlist>`(8引数)。
- Produces `loop-detect` / `loop-entity-detect` の入力 `finalize_label_allowlist`・`finalize_script`(既定 `""`)と env `FINALIZE_LABEL_ALLOWLIST`・`FINALIZE_SCRIPT`。両 `detect.sh` は第7・8引数にそれを渡す。

- [ ] **Step 1: 失敗するテストを書く。** `loop-write-contract.bats` を §1 の表の全セルで書き直す(1セルにつき通る1件と落ちる1件):
  - `validate accepts L1 delivery none and issue_comment with empty edit fields`
  - `validate rejects L1 delivery pr_create pr_push pr_review issue_create`。stderr は `::error::delivery must be none or issue_comment at L1 (got: <v>)`(空は `got: empty`)
  - `validate rejects L1 finalize_script`(`::error::finalize_script is not allowed at L1`)
  - `validate accepts L2 and L3 issue_comment and pr_review with finalize_script`
  - `validate rejects L2 and L3 issue_comment and pr_review without finalize_script`(`::error::finalize_script is required for delivery <d>`)
  - `validate accepts finalize_label_allowlist only with issue_comment or pr_review`(L1 `issue_comment` と L2 `pr_review` は通る。L1 `none`、L2 `pr_create`・`pr_push`・`none` は `::error::finalize_label_allowlist requires delivery issue_comment or pr_review (got: <d>)` で落ちる)
  - 既存の L1 の4項目の拒否と L2/L3 の各項目は残す。

  `loop-delivery.bats`:
  - `validate_delivery_value: implemented values pass` に `issue_comment`、`pr_review` を足し、`unimplemented values fail with not implemented` は `issue_create` だけにする。
  - `validate_delivery_target: issue_comment accepts entity issue only`(`{"entity":{"kind":"issue"}}` は通る。`kind: pr`、`{"mode":"integration"}`、`{"mode":"pull_request"}` は落ちる)。
  - `validate_delivery_target: pr_review accepts entity pr only`(上と対称)。
  - `validate_delivery_detect_config: issue_comment and pr_review are rejected for branch callers`(`true ""` と `false main` の両方で落ちる)。

  `loop-entity-detect.bats` と `loop-detect-delivery.bats`:
  - 入力の一覧の期待値に `finalize_label_allowlist` と `finalize_script` を足す。
  - `maps every renamed input` に `FINALIZE_LABEL_ALLOWLIST: ${{ inputs.finalize_label_allowlist }}` と `FINALIZE_SCRIPT: ${{ inputs.finalize_script }}` を足す。
  - `main fails on each invalid configuration without outputs` の L1 空 `DELIVERY` の期待値を新しい文言にし、`'LEVEL=L1 DELIVERY=issue_comment FINALIZE_SCRIPT=x.sh|::error::finalize_script is not allowed at L1'` を足す(件数を7にする)。
  - `@test "main publishes target matrix for L1 issue_comment on an issue entity"` を足す。
  - `loop-detect-delivery.bats` に `@test "validate_detect_inputs rejects issue_comment and pr_review"` を足す。

  `parse_target.bats`:
  - `@test "parse_target accepts issue_comment with an issue entity and pr_review with a pr entity"`(`{"key":"entity:issue:3","entity":{"handoff_key":"entity:issue:3","kind":"issue"},"to":{"branch":"main"}}`)を足す。
  - `parse_target fails for an empty or unimplemented delivery` は `issue_create` で落ちることにする。

- [ ] **Step 2: 失敗を確認する。** `bats test/bats/github-actions/loop-delivery.bats test/bats/github-actions/loop-write-contract.bats test/bats/github-actions/loop-entity-detect.bats test/bats/github-actions/loop-detect-delivery.bats test/bats/.github/actions/loop-finalize/lib/parse_target.bats`。Expected: FAIL。
- [ ] **Step 3: 実装する。**
  - `delivery.sh` の3関数を Interfaces のとおりに直し、ヘッダーの Design Rules と各関数の `Arguments` の値の一覧を改める。
  - `validate_loop_write_contract.sh`:
    - L1 では、`delivery` が `none|issue_comment` 以外なら落とし、`finalize_script` が空でなければ落とす。
    - 全 level で `finalize_label_allowlist` を検査する。L2/L3 では `validate_delivery_value` の後に `finalize_script` の必須を検査する。
    - ヘッダーの Design Rules を §1 の表に合わせる。
  - 両 action に入力と env を足す(アルファベット順)。`delivery` の説明を `issue_comment | none | pr_create | pr_push | pr_review` にする。
  - 両 `detect.sh` の呼び出しに `"${FINALIZE_SCRIPT:-}" "${FINALIZE_LABEL_ALLOWLIST:-}"` を足す。
  - `parse_target.sh` はコードを変えない(`delivery.sh` の変更で通る)。
- [ ] **Step 4: 通ることを確認する。** Step 2 のコマンド。Expected: PASS。
- [ ] **Step 5: コミットする。** `shfmt -w` を変更した `.sh` に実行する。`git add .github/actions/lib/loop/delivery.sh .github/actions/lib/loop/validate_loop_write_contract.sh .github/actions/loop-detect .github/actions/loop-entity-detect test/bats/github-actions/loop-delivery.bats test/bats/github-actions/loop-write-contract.bats test/bats/github-actions/loop-entity-detect.bats test/bats/github-actions/loop-detect-delivery.bats test/bats/.github/actions/loop-finalize/lib/parse_target.bats`、`feat(loop): validate issue_comment and pr_review deliveries at detect`。

---

### Task 3: outcome の判定の順と、ブランチの削除の判定

**Files:**

- Modify: `.github/actions/loop-finalize/lib/determine_outcome.sh:10-69`
- Modify: `.github/actions/loop-finalize/lib/should_delete_rejected_branch.sh:10-46`
- Modify: `.github/actions/loop-run-log/action.yml:40`(説明に `issue_commented | pr_reviewed` を足す)
- Test: `test/bats/.github/actions/loop-finalize/lib/determine_outcome.bats`、`test/bats/.github/actions/loop-finalize/lib/should_delete_rejected_branch.bats`、`test/bats/github-actions/loop-write-state.bats`

**Interfaces:** Produces `determine_outcome <override> <agent_result> <has_changes> <verdict> <delivery>`(引数は変えない)の判定の順(Global Constraints)。Produces `should_delete_rejected_branch <verdict> <has_changes> <delivery>`: `delivery` が `none|issue_comment|pr_review` なら 0。

- [ ] **Step 1: 失敗するテストを書く。**
  - `determine_outcome.bats`:
    - `@test "issue_comment and pr_review are issue_commented and pr_reviewed with or without changes"`: `success` × `has_changes` {true,false} × verdict {APPROVE, ""} の8通り。
    - `@test "REJECT is rejected for pr_review and issue_comment"`。
    - `@test "override wins over issue_comment and pr_review"`(`watch`)。
    - `@test "failed agent is error for issue_comment and pr_review"`。
    - 既存の `none:reported` などの行は変えない(REJECT を先に判定しても既存の結果は同じであることを、既存のテストで確かめる)。
  - `should_delete_rejected_branch.bats`: `@test "deletes for issue_comment and pr_review regardless of verdict and changes"`(APPROVE/REJECT × true/false)。既存の `keeps APPROVE branches for pr_create and pr_push` を残す。
  - `loop-write-state.bats`: `@test "run.sh resets consecutive_failures on issue_commented and pr_reviewed"`(既存の `:442` と同じ形)。
- [ ] **Step 2: 失敗を確認する。** `bats test/bats/.github/actions/loop-finalize/lib/determine_outcome.bats test/bats/.github/actions/loop-finalize/lib/should_delete_rejected_branch.bats test/bats/github-actions/loop-write-state.bats`。Expected: 前2つが FAIL(`write_state` は `*` で既に 0 にするので通ってよい。通ったら回帰テストとして残す)。
- [ ] **Step 3: 実装する。**
  - `determine_outcome` の `if` の連鎖を判定の順に並べ替え、ヘッダーの Design Rules に新しい値と順を書く。
  - `should_delete_rejected_branch` の最初の検査を `case "${delivery}" in none | issue_comment | pr_review) return 0 ;; esac` にする。
  - `outcome.sh`・`resolve_state_write_mode.sh`・`write_state.sh` は変えない(新しい値は passthrough、`metadata`、`consecutive_failures` の 0 になる)。
- [ ] **Step 4: 通ることを確認する。** Step 2 のコマンド。Expected: PASS。
- [ ] **Step 5: コミットする。** `git add .github/actions/loop-finalize/lib/determine_outcome.sh .github/actions/loop-finalize/lib/should_delete_rejected_branch.sh .github/actions/loop-run-log/action.yml test/bats/.github/actions/loop-finalize/lib test/bats/github-actions/loop-write-state.bats`、`feat(loop): add issue_commented and pr_reviewed outcomes`。

---

### Task 4: 投稿ファイルと `message_json` の往復

**Files:**

- Create: `.github/actions/lib/loop/loop_message.sh`
- Test: `test/bats/.github/actions/lib/loop/loop_message.bats`

**Interfaces:** Produces(どちらも純関数。エラーは stderr の `::warning::`):

- `loop_message_to_json <dir>`
  - `message.md` がない、または空白だけなら、何も出さずに 0 を返す。
  - あれば、`{"body": <rawfile>, "labels": <message_labels.json | null>}` を `jq -c` の1行で出す。
  - `message_labels.json` が、壊れた JSON か、`add`/`remove` が文字列の配列でない object なら、`::warning::message_labels.json is invalid; nothing is delivered` を出し、何も出さずに 0 を返す。本文だけを配信すると、ラベルと合わない文面が残るためである(§3-3 と同じ考え方。この plan の判断)。
- `loop_message_from_json <message_json> <dir>`
  - `dir` を作る。
  - 空の入力なら何も書かない。
  - `.body` を `jq -j` で `message.md` に、`.labels` が null でなければ `message_labels.json` に書く。
  - JSON でなければ `::error::` で 1。

- [ ] **Step 1: 失敗するテストを書く。**
  - `loop_message_to_json prints nothing without message.md or with a blank one`
  - `loop_message_to_json ignores message_labels.json when message.md is absent`
  - `loop_message_to_json emits body and null labels`
  - `loop_message_to_json emits labels when valid`
  - `loop_message_to_json prints nothing and warns on malformed or mis-shaped labels`(`{`、`{"add":"bug"}`、`[1]`)
  - `loop_message_from_json writes message.md and message_labels.json`
  - `loop_message_from_json writes nothing for empty input`
  - `loop_message_from_json fails on invalid JSON`
  - `round trip keeps the body byte-identical`: 本文 `printf '## A\n\n`code` and ```fence```\nEOF\n\n'` で `cmp`(Review Focus 3)。
- [ ] **Step 2: 失敗を確認する。** `bats test/bats/.github/actions/lib/loop/loop_message.bats`。Expected: FAIL(ファイルがない)。
- [ ] **Step 3: 実装する。** ヘッダーと関数のドキュメントは `delivery.sh` の形に合わせ、関数は a-z の順に置く。
- [ ] **Step 4: 通ることを確認する。** Step 2 のコマンド。Expected: PASS。
- [ ] **Step 5: コミットする。** `git add .github/actions/lib/loop/loop_message.sh test/bats/.github/actions/lib/loop/loop_message.bats`、`feat(loop): add loop message file and JSON round trip`。

---

### Task 5: Deliver Message の関数

**Files:**

- Create: `.github/actions/lib/loop/deliver_message.sh`
- Test: `test/bats/.github/actions/lib/loop/deliver_message.bats`(gh のモックは `test/bats/.github/actions/lib/loop/entity_meta.bats:30-47` の `mock_gh` の形にし、`-X POST`/`-X DELETE`/`--input` の中身と終了コードを、環境変数で切り替えられるようにする)

**Interfaces:**

- Consumes `build_loop_meta_block`・`loop_meta_reset`(`loop_meta.sh`。`created_by.sh` が先)、`loop_failure_record`(`failure_record.sh`)。
- Produces `deliver_loop_message`(引数なし)。
  - 読む Globals: `DELIVERY`、`LOOP_MESSAGE_DIR`、`LOOP_NAME`、`TARGET_JSON`、`FINALIZE_LABEL_ALLOWLIST`、`OUTCOME`(予定の値)、`VERDICT`、`AGENT_ENGINE`、`USAGE_JSON`、`RUN_URL`、`GITHUB_REPOSITORY`、`GH_TOKEN`、`LOOP_FAILURE_FILE`、`GITHUB_OUTPUT`。
  - 戻り値: 成功か何もしないときは 0、失敗は 1(記録してから)。
- Produces(内部、a-z の順):
  - `apply_loop_message_labels <number> <labels_file> <allowlist>`
  - `build_loop_message_body <text> <marker> <meta_block>`: 先頭に marker がなければ付ける。`<text>\n\n<meta_block>` を出す。
  - `loop_message_target_number <delivery> <target_json>`
  - `post_loop_issue_comment <number> <body_file>`(`gh issue comment <n> --repo <repo> --body-file <f>`)
  - `post_loop_pr_review <number> <review_file>`(`gh api -X POST repos/<repo>/pulls/<n>/reviews --input <payload>`。payload は `{body, commit_id, comments, event: "COMMENT"}`)

- [ ] **Step 1: 失敗するテストを書く。** すべて `deliver_loop_message` を呼ぶ:
  - `does nothing and writes outcome unchanged when message.md is absent or blank`: gh を呼ばない。`message_labels.json` があってもラベルを付けない。`GITHUB_OUTPUT` に `outcome=unchanged` がある。`OUTCOME=watch` でも同じ。
  - `does nothing when review.json is absent or has an empty body`(`pr_review`)
  - `posts one issue comment with the marker first and Meta and footer once`: 本文の1行目が `<!-- github-issue-triage:v1 -->`。`| outcome | issue_commented |` を含み、`Written by Loop Engineering (LE)` がちょうど1回。gh の呼び出しは `issue comment 12 --repo o/r --body-file` の1回。`GITHUB_OUTPUT` に `outcome=` がない。
  - `does not duplicate a marker the text already has`
  - `posts a COMMENT review with marker and Meta in body`: payload の `.event == "COMMENT"`、`.commit_id`、`.comments` は review.json のまま。
  - `ignores an event in review.json`(`"event":"APPROVE"` を入れても `COMMENT`)
  - `retries once with fallback_body and no comments on HTTP 422`: POST が2回。2回目は `.comments` がなく、`.body` が fallback_body で、marker と Meta がそれぞれ1回。
  - `does not retry on 422 without comments, or on other HTTP errors`(422 で `comments: []`、502 で `comments` あり)。どちらも1回で、戻り値 1。
  - `takes the number from entity.handoff_key and falls back to key`
  - `fails without calling gh when the handoff key kind does not match delivery`(Review Focus 4)
  - `applies labels before posting`: gh.log で labels の POST が comment より前。
  - `posts allowlisted labels in one POST and warns on the rest`: allowlist `bug\ntriage:ready`、add `["bug","autofix"]`。POST は1回で `{"labels":["bug"]}`、`::warning::` に `autofix`。
  - `skips the POST when no requested label is allowlisted`(Review Focus 2)
  - `encodes label names in DELETE paths`: remove `["triage:needs-info","a b/c"]` で `issues/12/labels/triage%3Aneeds-info` と `issues/12/labels/a%20b%2Fc`(Review Focus 1)。
  - `treats 404 on label DELETE as success`
  - `ignores labels and warns when the allowlist is empty`
  - `fails the step and records deliver_message when a label call or the post fails`: 戻り値 1。`LOOP_FAILURE_FILE` の `.failure_stage == "deliver_message"`。ラベルの失敗のときは投稿しない。
  - `redacts tokens in the recorded failure message`(gh の stderr に `ghp_` で始まる値)
- [ ] **Step 2: 失敗を確認する。** `bats test/bats/.github/actions/lib/loop/deliver_message.bats`。Expected: FAIL。
- [ ] **Step 3: 実装する。**
  - `loop_message_target_number`: `(.entity.handoff_key // .key)` を `^entity:(issue|pr):([1-9][0-9]*)$` で読み、`issue_comment`→`issue`、`pr_review`→`pr` と照合する。
  - 本文の空の判定は、前後の空白を除いてから行う(`entity_meta.sh:91-94` と同じ)。
  - Meta は `loop_meta_reset` の後に1回だけ組み立てる。marker は `<!-- ${LOOP_NAME}:v1 -->`。
  - 422 の判定は gh の stderr に `HTTP 422` があるか(`post_review.sh:816` と同じ)。
  - ラベルの DELETE のパスは `jq -rn --arg n "$name" '$n|@uri'`。404 の判定も stderr の `HTTP 404`。
  - gh の stderr は変数に取り、`loop_failure_record` にだけ渡す(生のまま出さない)。
- [ ] **Step 4: 通ることを確認する。** Step 2 のコマンド。Expected: PASS。
- [ ] **Step 5: コミットする。** `shfmt -w .github/actions/lib/loop/deliver_message.sh`。`git add .github/actions/lib/loop/deliver_message.sh test/bats/.github/actions/lib/loop/deliver_message.bats`、`feat(loop): deliver loop messages as issue comments and PR reviews`。

---

### Task 6: `loop-finalize` に配信をつなぐ

**Files:**

- Modify: `.github/actions/loop-finalize/action.yml:2`、`:20-22`、入力(`finalize_label_allowlist`・`message_json` を足す)、`:125-127`、`:137` の前(Materialize Message)、`:187-214`、`:214` と `:216` の間(Deliver Message)、`:278`、`:290-291`
- Test: `test/bats/.github/actions/loop-finalize/action_delivery.bats`、`test/bats/.github/actions/loop-finalize/action_finalize_hook_env.bats`

**Interfaces:**

- Consumes `loop_message_from_json`(Task 4)、`deliver_loop_message`(Task 5)、`determine_outcome`(Task 3)。
- Produces 入力 `finalize_label_allowlist`(既定 `""`)と `message_json`(既定 `""`)。
- Produces ステップ:
  - `Materialize Message`(最初のステップ)。env は `LOOP_MESSAGE_DIR`、`MESSAGE_JSON`。
  - `Deliver Message`(`id: deliver`)。`if` は `(inputs.delivery == 'issue_comment' || inputs.delivery == 'pr_review') && inputs.agent_result == 'success' && inputs.verdict != 'REJECT'`。env はアルファベット順に `AGENT_ENGINE`、`DELIVERY`、`FINALIZE_LABEL_ALLOWLIST`、`GH_TOKEN`、`GITHUB_REPOSITORY`、`LOOP_FAILURE_FILE: ${{ runner.temp }}/loop-finalize-failure.json`、`LOOP_MESSAGE_DIR`、`LOOP_NAME`、`OUTCOME: ${{ steps.outcome.outputs.value }}`、`RUN_URL`、`TARGET_JSON`、`USAGE_JSON`、`VERDICT`。
- Produces hook の env `LOOP_MESSAGE_DIR`。hook の step からは `LOOP_META_BLOCK` の組み立て(`:204-213`)を消す。

- [ ] **Step 1: 失敗するテストを書く。**
  - `action_delivery.bats`:
    - 入力の一覧に `finalize_label_allowlist`、`message_json` を足す。
    - `@test "steps run in spec order"`: ステップ名の並びが `Materialize Message, Parse Target, Resolve State File, Determine Outcome, Resolve State Write Mode, Run Finalize Hook, Deliver Message, Push to Target Branch, Create PR, Enable Auto-Merge, Write State, Delete Agent Branch, Export Failure Diagnostics`。
    - `@test "deliver message runs for issue_comment and pr_review after a successful, non-REJECT agent"`: `if` の文字列が Interfaces と一致する。
    - `@test "deliver message env is alphabetical and uses the planned outcome"`
    - `@test "outcome output and write state use the delivered outcome"`: `value: ${{ steps.deliver.outputs.outcome || steps.outcome.outputs.value }}` と `OUTCOME: ${{ steps.deliver.outputs.outcome || steps.outcome.outputs.value }}`。
    - `delete agent branch keys on REJECT or delivery none` を `... on REJECT or a delivery that never lands the branch` にし、Global Constraints の `if` と一致させる(Review Focus 5)。
    - `@test "materialize message writes message_json into LOOP_MESSAGE_DIR"`: そのステップの `run:` だけを取り出して `MESSAGE_JSON='{"body":"x","labels":null}'` で実行し、`message.md` ができる。
  - `action_finalize_hook_env.bats`:
    - `finalize hook receives the data for, and builds, LOOP_META_BLOCK` を消す。
    - `@test "finalize hook gets LOOP_MESSAGE_DIR and no LOOP_META_BLOCK"` を足す。
    - env のキーがアルファベット順のテストは残す。
  - `test/bats/github-actions/loop-caller-parity.bats`: `@test "no loop-finalize step or lib/loop script edits a posted comment or review"`。`.github/actions/loop-finalize/action.yml` と `.github/actions/lib/loop/*.sh` に、`-X PATCH`、`--method PATCH`、`issues/comments/`、`gh issue comment .*--edit-last`、`pulls/[^ ]*/reviews/[0-9]` がない。
- [ ] **Step 2: 失敗を確認する。** `bats test/bats/.github/actions/loop-finalize/action_delivery.bats test/bats/.github/actions/loop-finalize/action_finalize_hook_env.bats test/bats/github-actions/loop-caller-parity.bats`。Expected: FAIL。
- [ ] **Step 3: 実装する。**
  - Materialize Message の `run`: `source "${GITHUB_ACTION_PATH}/../lib/loop/loop_message.sh"` の後に `loop_message_from_json "${MESSAGE_JSON}" "${LOOP_MESSAGE_DIR}"` を呼ぶ。`LOOP_MESSAGE_DIR` は常に作る(hook が書くため)。
  - Deliver Message の `run`: `created_by.sh`、`loop_meta.sh`、`failure_record.sh`、`deliver_message.sh` を source して `deliver_loop_message` を呼ぶ。
  - `description`(`:2`)と `delivery` の説明に新しい値を書く。`level` の説明(`:55`)は変えない。
- [ ] **Step 4: 通ることを確認する。** Step 2 のコマンド。Expected: PASS。
- [ ] **Step 5: コミットする。** `git add .github/actions/loop-finalize/action.yml test/bats/.github/actions/loop-finalize test/bats/github-actions/loop-caller-parity.bats`、`feat(loop-finalize): deliver loop messages after the finalize script`。

---

### Task 7: `loop-agent-once` が投稿ファイルを集める(stdout の投稿をなくす)

**Files:**

- Modify: `.github/actions/loop-agent-once/action.yml:31-38`(`comment_handoff_key`・`comment_marker` を削除)、`:62-65`(出力 `message_json`)、`:93-106`(env の `COMMENT_*`・`REPOSITORY`・`RUN_URL` を削除し、`LOOP_MESSAGE_DIR: ${{ runner.temp }}/loop-message` を足す)
- Modify: `.github/actions/loop-agent-once/lib/run.sh:8-31`(ヘッダー)、`:91-144`(`post_loop_comment` を削除)、`:170-187`
- Modify: `.github/actions/loop-execute/lib/agent.sh:370`(Globals のコメント)、`:436-438`
- Delete: `.github/actions/lib/loop/entity_meta.sh`、`test/bats/.github/actions/lib/loop/entity_meta.bats`
- Test: `test/bats/.github/actions/loop-agent-once/lib/run.bats`、`test/bats/.github/actions/loop-agent-once/action.bats:25-60`、`test/bats/.github/actions/loop-execute/lib/agent.bats:270-290`

**Interfaces:**

- Consumes `loop_message_to_json`(Task 4)。
- Produces(`run.sh`):
  - `prepare_loop_message_dir`: `LOOP_MESSAGE_DIR` が空でなければ作り、`PROMPT` の末尾に `\n\nLoop message directory: ${LOOP_MESSAGE_DIR}` を足す。
  - `emit_message_json_output`: `loop_message_to_json` の結果を、`MESSAGE_JSON_<openssl rand -hex 8>` を区切りにして `message_json` として `GITHUB_OUTPUT` に書く。空なら `message_json=`。
- Produces 出力 `message_json`。
- Produces `run_agent_engine` の claude 分岐: `LOOP_MESSAGE_DIR` が空でなければ `--add-dir "${LOOP_MESSAGE_DIR}"` を足す。

- [ ] **Step 1: 失敗するテストを書く。**
  - `run.bats`:
    - `post_loop_comment` の3件(`:171-214`)を消す。
    - `@test "run_loop_agent_once appends the message directory to the prompt and creates it"`: モックの claude の引数の `-p` の末尾が `Loop message directory: <dir>`。
    - `@test "run_loop_agent_once emits message_json from message.md and message_labels.json"`: モックの claude がファイルを書く。
    - `@test "run_loop_agent_once emits an empty message_json when message.md is missing or labels are malformed"`
    - `@test "run_loop_agent_once never calls gh"`: gh のスタブが呼ばれない。
    - `@test "run_loop_agent_once keeps a multi-line body intact through GITHUB_OUTPUT"`(Review Focus 3)
  - `action.bats`: 入力の一覧から `comment_handoff_key comment_marker` を消す。Run CLI Agent の env の期待値から `COMMENT_*`・`REPOSITORY`・`RUN_URL` を消し、`LOOP_MESSAGE_DIR: ${{ runner.temp }}/loop-message` を足す。`@test "action exposes message_json from the run step"` を足す。
  - `agent.bats`: `@test "run_agent claude adds LOOP_MESSAGE_DIR with --add-dir"` と `@test "run_agent claude omits the message add-dir when LOOP_MESSAGE_DIR is empty"`(`:274-290` の形)。
- [ ] **Step 2: 失敗を確認する。** `bats test/bats/.github/actions/loop-agent-once/lib/run.bats test/bats/.github/actions/loop-agent-once/action.bats test/bats/.github/actions/loop-execute/lib/agent.bats`。Expected: FAIL。
- [ ] **Step 3: 実装する。**
  - `run_loop_agent_once` で、`reset_usage_totals` の前に `prepare_loop_message_dir`、`emit_usage_json_output` の後に `emit_message_json_output` を呼ぶ。`post_loop_comment` の呼び出しを消す。
  - `entity_meta.sh` とその bats を `git rm` する。
  - claude 以外のエンジンには何も足さない(spec の未決3。この plan の判断。Task 11 で docs に制限として書く)。
- [ ] **Step 4: 通ることを確認する。** Step 2 のコマンド。Expected: PASS。`git grep -n entity_meta -- .github test` が空であることを確かめる。
- [ ] **Step 5: コミットする。** `shfmt -w .github/actions/loop-agent-once/lib/run.sh .github/actions/loop-execute/lib/agent.sh`。`git add -A .github/actions/loop-agent-once .github/actions/loop-execute/lib/agent.sh .github/actions/lib/loop/entity_meta.sh test/bats/.github/actions/loop-agent-once test/bats/.github/actions/loop-execute/lib/agent.bats test/bats/.github/actions/lib/loop/entity_meta.bats`、`feat(loop-agent-once): collect message files instead of posting agent stdout`。

---

### Task 8: `ci-loop-agent` と reusable の caller の配線

**Files:**

- Modify: `.github/workflows/ci-loop-agent.yaml:1-5`(ヘッダー)、入力(`finalize_label_allowlist` を足す。`delivery` の説明 `:112-115`)、`:203-207`(`target_json` の説明)、`:261-306`(agent-l1)、`:308-350`(finalize-l1)、`:472-475`(finalize-l2 の権限)、`:531-563`(finalize-l2 の Finalize)
- Modify: `.github/workflows/ci-loop-caller.yaml`(入力 `finalize_label_allowlist`、`delivery` の説明 `:123`、detect の `with:` `:334-357`、ci-loop-agent の `with:` `:491-494`)
- Modify: `.github/workflows/ci-loop-caller-entity.yaml`(入力 `finalize_label_allowlist`、`delivery` の説明 `:124`、detect の `with:` `:296-311`、ci-loop-agent の `with:` `:348-351`)
- Modify: `scripts/self/ci/loop_input_topology.py:47-56`(`DETECT_REQUIRED`)、`:62-114`(`DECISIONS`)
- Test: `test/bats/github-actions/loop-caller-parity.bats`、`test/bats/scripts/self/ci/loop_input_topology.bats:123-131`

**Interfaces:**

- Consumes `loop-agent-once` の出力 `message_json`(Task 7)、`loop-finalize` の入力 `message_json`・`finalize_label_allowlist`(Task 6)、detect の入力 `finalize_script`・`finalize_label_allowlist`(Task 2)。
- Produces ジョブ `agent-l1`:
  - `outputs.message_json: ${{ steps.agent.outputs.message_json }}`
  - 権限は `contents: read` と `copilot-requests: write`。
  - Run Agent Once に `comment_handoff_key`・`comment_marker`・`output_file` を渡さない。
- Produces ジョブ `finalize-l1`:
  - 権限は `contents: write` と `issues: write`。
  - ステップ `Warn Missing Message`: `if: needs.agent-l1.result == 'success' && needs.agent-l1.outputs.message_json == '' && inputs.delivery == 'issue_comment'` で `::warning::` を出す(spec §2 の警告。どこで出すかは spec にないので、出力が捨てられたことが見える finalize-l1 に置く)。
  - ステップ `Finalize`: `id: finalize`、`continue-on-error: true`、`loop-finalize` を実行する。`with` は `agent_engine`、`agent_result: ${{ needs.agent-l1.result }}`、`branch: ""`、`current_sha: ""`、`delivery`、`finalize_label_allowlist`、`github_token`、`level`、`loop_name`、`message_json: ${{ needs.agent-l1.outputs.message_json || '' }}`、`state_branch`、`target_json`、`usage_json`。
  - Append Run Log: `if: always()`。outcome は `${{ steps.finalize.outcome == 'failure' && 'error' || steps.finalize.outputs.outcome || (needs.agent-l1.result != 'success' && needs.agent-l1.result != 'skipped' && 'error') || 'unchanged' }}`(L1 には verdict がないので、`:612` の REJECT の項だけを除く)。
- Produces ジョブ `finalize-l2`: `issues: write` を足し、Finalize に `finalize_label_allowlist` を渡す。
- Produces reusable の入力 `finalize_label_allowlist`(`type: string`、既定 `""`)。両 detect と ci-loop-agent に `finalize_script` と `finalize_label_allowlist` を渡す。
- Produces `DECISIONS["finalize_label_allowlist"] = ("—", "全", "新設(投稿の配信 第5節)")`。`DETECT_REQUIRED` に `finalize_label_allowlist`、`finalize_script` を足す。

- [ ] **Step 1: 失敗するテストを書く(`loop-caller-parity.bats`)。**
  - `agent-l1 gives Run Agent Once the entity handoff key and output file`(`:201-207`)を、`@test "agent-l1 has no issues write and exposes message_json without comment inputs"` に置き換える。`job_block "${AGENT}" agent-l1` に `issues: write`・`comment_handoff_key`・`output_file` がなく、`message_json: ${{ steps.agent.outputs.message_json }}` がある。
  - `@test "finalize-l1 runs loop-finalize with an empty current_sha and branch"`: `loop-finalize@` を使い、`current_sha: ""` と `branch: ""` と `message_json: ${{ needs.agent-l1.outputs.message_json || '' }}` と `continue-on-error: true` がある。
  - `@test "finalize-l1 has issues write and no pull-requests write"`。`@test "finalize-l2 has issues write"`。
  - `@test "finalize-l1 run log uses the finalize outcome"`: 式が Interfaces と一致する。
  - `@test "finalize-l1 warns when a successful agent left no message"`。
  - `@test "both reusables pass finalize_script and finalize_label_allowlist to detect and to ci-loop-agent"`。
  - `@test "target_json is described as required at every level"`: `ci-loop-agent.yaml` の `target_json` の説明に `required at every level` がある。
  - 既存の `finalize-l1 persists run-log after agent-l1`(`:657-661`)と `agent-l1 exposes usage_json and finalize-l1 passes it to run-log`(`:215-218`)は残す(`grep -A` の行数が足りなければ増やす)。
  - `loop_input_topology.bats:126` の一覧に `finalize_label_allowlist finalize_script` を足す。
- [ ] **Step 2: 失敗を確認する。** `bats test/bats/github-actions/loop-caller-parity.bats test/bats/scripts/self/ci/loop_input_topology.bats`。Expected: FAIL。
- [ ] **Step 3: 実装する。**
  - Interfaces のとおりに YAML を直す。キーはアルファベット順にする(ORD-01)。
  - ヘッダーの `:2` を `L1: agent-l1 (loop-agent-once) → finalize-l1 (loop-finalize and run-log)` にし、`:4` の delivery の一覧を改める。
  - `target_json` の説明は「required at every level; empty fails」にする。外部の caller への契約の変更であることを、Task 11 で docs に書く。
  - `python3 -I scripts/self/ci/loop_input_topology.py .` が 0 で終わることを確かめる。
- [ ] **Step 4: 通ることを確認する。** Step 2 のコマンドと `bats test/bats/github-actions/loop-entity-detect.bats test/bats/github-actions/loop-detect-delivery.bats`。Expected: PASS。
- [ ] **Step 5: コミットする。** `git add .github/workflows/ci-loop-agent.yaml .github/workflows/ci-loop-caller.yaml .github/workflows/ci-loop-caller-entity.yaml scripts/self/ci/loop_input_topology.py test/bats/github-actions/loop-caller-parity.bats test/bats/scripts/self/ci/loop_input_topology.bats`、`feat(loop): run loop-finalize at L1 and wire finalize_label_allowlist`。

---

### Task 9: pr-review の `render_review.sh` と caller の移行

**Files:**

- Rename: `.apm/packages/github/.apm/skills/github-pr-review/scripts/post_review.sh` → `render_review.sh`(`git mv`)
- Modify: `render_review.sh` の `:1-46`(ヘッダー)、`:263-278`(`build_payload`)、`:391-428`(`post_payload` を削除)、`:743-826`(`main`)、`:828-844`(入口の警告文)
- Modify: `.apm/packages/github/.apm/skills/github-pr-review/assets/review-body-template.md:2`、`assets/inline-comment-template.md:2`、`SKILL.md:13`(version を 0.1.1 に)
- Modify: `.github/workflows/on-loop-github-pr-review.yaml:5-16`、`:116-117`、`:127`(`delivery: pr_review`)、`:130`(`finalize_script: .agents/skills/github-pr-review/scripts/render_review.sh`)
- Rename/Test: `test/bats/.apm/packages/github/github-pr-review/post_review.bats` → `render_review.bats`(`git mv`)
- Modify: `test/bats/github-actions/loop-caller-parity.bats`(Task 1 の除外から `post_review.sh` を外す)
- Sync: `bash scripts/self/apm/sync_apm_artifacts.sh`(`.agents/skills/github-pr-review/`、`.claude/skills/github-pr-review/`、`apm_modules/_local/github/`、`apm.lock.yaml`)

**Interfaces:**

- Produces `render_review.sh`(finalize の `finalize_script`)。
  - 読む env: `VERDICT`、`EXECUTE_BRANCH`、`TARGET_JSON`、`GITHUB_REPOSITORY`、`GH_TOKEN`(読み取りだけ)、`LOOP_MESSAGE_DIR`(必須)。テスト用の `REPORT_FILE`・`PR_DIFF_FILE`・`PR_BASE_SHA`・`PR_HEAD_SHA` は変えない。
  - 書くもの: `${LOOP_MESSAGE_DIR}/review.json` = `{"body", "commit_id", "comments", "fallback_body"}`。`fallback_body` は `.findings |= map(.inline = false)` で組み立てた本文。`event` は書かない。
  - 常に exit 0。組み立てられないときは `::warning::render_review: ...` を出し、ファイルを書かない。
- Produces `build_payload` → `build_review_json <annotated>`。`event` を出さず、`fallback_body` を足す。

- [ ] **Step 1: テストを移して、失敗させる。**
  - `git mv` の後、`POST_SCRIPT` を `RENDER_SCRIPT="$(apm_skill_script_path github-pr-review render_review.sh)"` にする。`run_in_repo` に `LOOP_MESSAGE_DIR="${BATS_TEST_TMPDIR}/msg"` を渡す。`posted()` を `rendered() { cat "${BATS_TEST_TMPDIR}/msg/review.json"; }` にする。
  - 検証と組み立ての全ケース(`:174-458`、`:462-490`、`:509-547`、`:567-628`)は、期待値を `rendered` に向けて残す。「posting なし」の検査は「`review.json` がない」にする。
  - 次のテストを置き換える:
    - `appends LOOP_META_BLOCK ...`(`:491`)と `posts the review body unchanged when LOOP_META_BLOCK is absent`(`:501`)→ `@test "review.json body carries no Meta block even when LOOP_META_BLOCK is set"`
    - `retries without inline comments ...`(`:549`)→ `@test "fallback_body holds every finding and the same marker"`
    - `never sends REQUEST_CHANGES or APPROVE`(`:423`)→ `@test "review.json has no event key"`
  - 次のテストは消す(Task 5 の `deliver_message.bats` が持つ):
    - `retries only on HTTP 422 ...`(`:559`)
    - `warns and exits 0 when posting fails`(`:630`)
  - 足すテスト:
    - `@test "writes nothing and warns when LOOP_MESSAGE_DIR is unset"`
    - `@test "never calls gh api with POST"`: gh.log に `--method POST`・`-X POST` がない。
  - Run: `bats test/bats/.apm/packages/github/github-pr-review/render_review.bats`。Expected: FAIL。
- [ ] **Step 2: 実装する。**
  - `post_payload` と 422 の再試行(`:808-825`)を消す。`main` の最後で `jq` により `review.json` を書く。
  - ヘッダーの Description・Usage・Output・Design Rules・Environment を、「組み立てて書く、投稿しない、`LOOP_META_BLOCK` を読まない」に合わせる。
  - ログの接頭辞を `render_review:` にする。
  - テンプレート2つの2行目を `rendered by render_review.sh` に、`the poster` を `the platform` にする。
- [ ] **Step 3: caller を移す。**
  - `delivery: pr_review`。`finalize_script` を `render_review.sh` にする。
  - `:5-16` のコメントを「`render_review.sh`(`finalize_script`)が `review.json` を書き、`loop-finalize` の Deliver Message が1回だけ COMMENT のレビューを投稿する」に書き換える。`:116-117` も同じ趣旨にする。
- [ ] **Step 4: 同期して、通ることを確認する。** `bash scripts/self/apm/sync_apm_artifacts.sh` の後、`bats test/bats/.apm/packages/github/github-pr-review/render_review.bats test/bats/.apm/packages/github/github-pr-review/detect_pr_review.bats test/bats/github-actions/loop-caller-parity.bats`。Expected: PASS。
- [ ] **Step 5: コミットする。** `shfmt -w .apm/packages/github/.apm/skills/github-pr-review/scripts/render_review.sh`。`git add -A .apm/packages/github/.apm/skills/github-pr-review .agents/skills/github-pr-review .claude/skills/github-pr-review apm_modules/_local/github apm.lock.yaml test/bats/.apm/packages/github/github-pr-review .github/workflows/on-loop-github-pr-review.yaml test/bats/github-actions/loop-caller-parity.bats`、`feat(github-pr-review): render review.json for pr_review delivery instead of posting`。

---

### Task 10: triage の skill と caller の移行

**Files:**

- Modify: `.apm/packages/github/.apm/skills/github-issue-triage/SKILL.md:12`(version を 0.1.5 に)、`:19-24`(Input、Output)、`:53-59`(Workflow の3・5・6)、Error Handling の表
- Modify: `.apm/packages/github/.apm/skills/github-issue-triage/references/category-fsm.md:16-20`(Failed stop)、`references/category-prompt-rules.md:17-26`、`references/common-checklist.md:27-28`、`references/category-pr-body-links.md:3`
- Modify: `.github/workflows/on-loop-github-issue-triage.yaml:35-44`(コメント)、`:116-121`(maker の指示)、`:125-133`(`agent_tool_allowlist`)、`:136`(`delivery`)、`finalize_label_allowlist` を足す
- Test: `test/bats/github-actions/loop-caller-parity.bats`
- Sync: `bash scripts/self/apm/sync_apm_artifacts.sh`

**Interfaces:**

- Consumes プロンプトの行 `Loop message directory: <path>`(Task 7)。
- Produces skill の自動化の契約(portable な文言):
  - プロンプトに `Loop message directory:` があるときは、`gh` でラベルを付けず、コメントを投稿しない。
  - コメントの Markdown をそのディレクトリの `message.md` に書く。
  - FSM の遷移(`label_fsm_next_state` の `{"add","remove"}`)を `message_labels.json` に書く。
  - 対話のとき(その行がないとき)は、これまでどおり `scripts/issue_comment.sh` と `gh issue edit` を使う。
- Produces caller の値:
  - `delivery: issue_comment`
  - `finalize_label_allowlist`(Global Constraints の8つ)
  - `agent_tool_allowlist` は `Bash(gh api -X GET:*)`、`Bash(gh issue view:*)`、`Bash(gh label list:*)`

- [ ] **Step 1: 失敗するテストを書く(`loop-caller-parity.bats`)。**
  - `@test "triage caller delivers issue_comment with the label allowlist"`: `delivery: issue_comment` があり、`finalize_label_allowlist` の8行が一致し、`autofix` がない。
  - `@test "triage caller grants no write gh commands to the agent"`: `agent_tool_allowlist` のブロックに `gh issue edit`、`gh label create`、`gh issue comment`、`Bash(gh api:*)` がない。
  - `@test "triage maker instructions point at the message directory"`: `message.md` と `message_labels.json` を含み、`Your final message IS the comment` を含まない。
- [ ] **Step 2: 失敗を確認する。** `bats test/bats/github-actions/loop-caller-parity.bats`。Expected: FAIL。
- [ ] **Step 3: skill を直す。**
  - `SKILL.md` の Workflow 5・6 を、自動化(投稿ファイルを書く)と対話(`gh issue edit`・`issue_comment.sh`)に分ける。
  - 手順3の `gh label create` は対話のときだけにする。
  - `:58` の「When the caller says it posts the comment itself」の文を、投稿ファイルの手順に置き換える。
  - `category-fsm.md` の Failed stop で、`triage:failed` は自動化では `message_labels.json` の `add` に書くこと、エージェントが失敗した実行ではプラットフォームが付けないことを書く。
  - prompt-rules と checklist の `issue_comment.sh create` の行には「対話のとき。自動化では `message.md` が同じ役」を足す。
  - YAML `description` は会話での利用を先に書いたままにする(`.apm/CLAUDE.md` の Package placement)。
- [ ] **Step 4: caller を直す。**
  - maker の指示: `Triage the Issue per the github-issue-triage skill. Do NOT post comments or change labels. Write the comment markdown to message.md, and the label changes as {"add":[...],"remove":[...]} to message_labels.json, in the loop message directory named at the end of this prompt. Do not open PRs or call repository_dispatch.`
  - `:35-40` のコメントを「finalize が App のトークンで投稿とラベルを行う」に直す。
- [ ] **Step 5: 同期して、通ることを確認する。** `bash scripts/self/apm/sync_apm_artifacts.sh` の後、`bats test/bats/github-actions/loop-caller-parity.bats test/bats/.apm/packages/github/github-issue-triage/issue_comment.bats test/bats/.apm/packages/github/github-issue-triage/label_fsm.bats`。Expected: PASS。`scripts/self/apm/check_loop_pr_body_contract.sh` が通ることも確かめる。
- [ ] **Step 6: コミットする。** `git add -A .apm/packages/github/.apm/skills/github-issue-triage .agents/skills/github-issue-triage .claude/skills/github-issue-triage apm_modules/_local/github apm.lock.yaml .github/workflows/on-loop-github-issue-triage.yaml test/bats/github-actions/loop-caller-parity.bats`、`feat(github-issue-triage): write message files for issue_comment delivery`。

---

### Task 11: docs と全体の確認

**Files:**

- Modify: `docs/reference/specification.md:400`(`loop-finalize` の行に `issue_comment`・`pr_review` と Deliver Message)、`:493-501`(`loop-finalize` の入力に `finalize_label_allowlist`・`message_json`、`finalize_script` の env に `LOOP_MESSAGE_DIR` を足し、`LOOP_META_BLOCK` を書かない)、`:509-517`(Outcome enum に `issue_commented`・`pr_reviewed`。`consecutive_failures` は Reset to 0)
- Modify: `docs/explanation/loop-engineering/index.md`、`loop-engineering-design.md:257` 付近(finalize の流れの図に Deliver Message)、`:764`・`:774-780`(Finalize の責務と表)
- Modify: `docs/explanation/loop-engineering/workflows/loop-github-issue-triage-workflow-design.md:19-21`、`:60`、`:63`(エージェントは投稿ファイルを書き、finalize が投稿とラベルを行う。claude 以外のエンジンでは `LOOP_MESSAGE_DIR` に書けない制限)
- Modify: `docs/explanation/loop-engineering/workflows/loop-github-pr-review-workflow-design.md:13`、`:41-52`、`:83`、`:106`、`:127-150`(`render_review.sh` と Deliver Message。`LOOP_META_BLOCK` の段落を置き換える)
- Modify: `docs/explanation/loop-engineering/workflows/loop-caller-inputs-reference.md:255`(`render_review.sh`)と、入力の表に `finalize_label_allowlist`。`target_json` が L1 でも必須になったことを書く
- Modify: `docs/explanation/loop-engineering/loop-pr-body-skill-contract.md:142`(コメントとレビューの文面は finalize が投稿する)
- Modify: `docs/superpowers/specs/2026-10-17-loop-delivery-plan-design.md` の第1節 `:99-110`(`issue_comment`・`pr_review` を実装済みにし、`pr_review` のターゲットを PR の entity に狭め、`none` を「何も配信しない」にし、「`none` 以外は L2 以上」を改める)、第4節 `:179-188`(hook の契約: `LOOP_MESSAGE_DIR` に書いてよい、`GH_TOKEN` は読み取り、`LOOP_META_BLOCK` なし、`OUTCOME` は予定の値)、第6節 `:198-203`(表の L1 と L2/L3 の `delivery`)
- Test: 全 bats

**Interfaces:** なし(記述だけ)。

- [ ] **Step 1: docs を直す。** DOC-00 に従い、該当する節だけを変える。DOC-05 に従い、リンクの文字はリンク先の文書の題名にする。spec の未決の3点は次のように書く。
  - ラベルの自動作成: dogfood の結果を triage の design に書く。
  - 古い `commit_id`: 422 で `fallback_body` になることを pr-review の design に書く。
  - claude 以外のエンジン: 制限として triage の design に書く。
- [ ] **Step 2: 残っている旧い記述がないことを確かめる。** `git grep -n -e post_review -e finalize_hook_script -e LOOP_META_BLOCK -e comment_handoff_key -e post_loop_comment -e entity_meta -- . ':!docs/superpowers' ':!test/bats/github-actions/loop-caller-parity.bats'`。Expected: 出力がない(履歴の plan と spec、旧い名前を列挙する parity テストは除く。配信設計の spec は Task 11 で第1・4・6節だけを直すので、ほかの節の旧い名前は履歴として残る)。
- [ ] **Step 3: 全体を確認する。**
  - `bats -r test/bats`。Expected: すべて PASS。
  - `python3 -I scripts/self/ci/loop_input_topology.py .`。Expected: exit 0。
  - `bash scripts/self/apm/sync_apm_artifacts.sh` の後、`git status --porcelain` に同期先の差分が残らない。
  - lint(actionlint、ghalint、zizmor、shellcheck、markdownlint)は Stop フックの結果を見る。直接は実行しない。
- [ ] **Step 4: コミットする。** `git add docs/reference/specification.md docs/explanation/loop-engineering docs/superpowers/specs/2026-10-17-loop-delivery-plan-design.md`、`docs(loop): document issue_comment and pr_review delivery`。

---

## リリース(手動。この plan の範囲外)

明示の承認を得てから、`scripts/self/ci/pin_config_actions.sh` で、変更と `ci-loop-agent.yaml`・`ci-loop-caller*.yaml`・`example/` の pin を1回で push する(spec「移行」)。その後、使い捨てのブランチで次を確かめ、結果を Task 11 の docs に反映する。

- triage と pr-review を `workflow_dispatch` で動かす。
- 投稿が Meta とフッター付きで1回だけであること。
- triage のラベルが許可リストの範囲で付くこと。
- 存在しないラベルの POST で GitHub がラベルを作るか。

## Self-review(writing-plans のチェックリスト)

- **spec の網羅:**
  - §1 → Task 1, 2
  - §2 → Task 4, 6, 7, 8
  - §3 → Task 3, 5, 6, 8
  - §4 → Task 6, 9
  - §5 → Task 5, 10
  - §6 → Task 8, 10
  - §7 → Task 9, 10
  - 検証の節の各項目 → 各 Task の Step 1
  - 影響を受ける箇所 → ファイル構成の表。`loop_input_topology.py` は Task 1 と 8 で扱う(入力を足す Task で `DECISIONS` を足さないと gate が落ちるため、Task 11 には置かない)。
- **プレースホルダー:** なし。spec の未決の3点は、Task 7、Task 11、「リリース」で扱いを決めた。
- **名前の一貫性:** `loop_message_to_json` / `loop_message_from_json` / `deliver_loop_message` / `LOOP_MESSAGE_DIR` / `message_json` / `finalize_label_allowlist` / `FINALIZE_SCRIPT` は、Task 4〜10 で同じ綴りを使う。
- **分量:** 関数の本体は書かず、アルゴリズムが自明でない箇所(番号の取り方、422 の判定、URL エンコード)だけを書いた。
