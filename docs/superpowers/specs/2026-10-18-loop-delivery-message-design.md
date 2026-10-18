# Loop の投稿の配信(`issue_comment` / `pr_review`)とラベル

**Status:** Draft(第4回レビューで High・Medium なし。Low を反映)
**Date:** 2026-10-18
**Related:** [Loop 配信設計](2026-10-17-loop-delivery-plan-design.md)(移行の節の「Phase P」を扱う)、[`detect_hook_script` の削除](2026-10-18-loop-detect-hook-removal-design.md)、[run-log の outcome を `loop-finalize` に寄せる](2026-10-18-loop-finalize-run-log-outcome-design.md)(この spec の後に実装する)、[エージェントのジョブから書き込みの認証情報をなくす](2026-10-18-loop-agent-credential-isolation-design.md)(この spec の後に実装する)

## 方針(ユーザー承認済み)

- 基本線は **検出(`detect_script`)→ エージェント → finalize(run-log、ドメイン処理の `finalize_script`、配信、state)**。新しいスクリプトの入力は作らない。
- エージェントは中身(差分、または投稿の文面)を作り、usage を測るところまで。GitHub へは書き込まない。
- finalize が、エージェントから返ったものを処理する最終地点である。GitHub への書き込みは、finalize が `delivery` に従って1回だけ行い、Meta とフッターをその投稿に含める。自分の投稿を後から編集しない。
- ラベルは投稿と一緒に運び、finalize が caller の許可リストの範囲で付け外しする。
- `delivery: none` は残す(他のリポジトリで「何も配信しない」loop を書く手段。移行後、dogfood では使わない)。
- 対話で skill を使うときは、これまでどおり skill が自分で投稿してよい。

## 背景

- triage(L1)は `delivery: none` のまま、`loop-agent-once` がエージェントの stdout を Issue コメントにし(`loop-agent-once/lib/run.sh:114-144`)、ラベルはエージェントが `gh issue edit` で付ける。pr-review(L2)は `delivery: none` のまま、hook の `post_review.sh` が投稿する(配信設計の第4節の例外)。
- エージェントのジョブには、今も App のトークンと秘密鍵がある。この spec は、エージェントが自分で書き込む手順(投稿とラベル)をなくす。書き込みの手段そのものを断つのは、[認証情報の分離の spec](2026-10-18-loop-agent-credential-isolation-design.md) で扱う。

## 目標と非目標

**目標:** `issue_comment` と `pr_review` を実装して triage と pr-review を移す。エージェントの手順から GitHub への書き込みをなくす。Meta を付けるのを finalize の1か所にする。ラベルを許可リストで制限する。hook から書き込みをなくす。

**非目標:** `issue_create`(予約値のまま)。エージェントの文面を PR の会話欄へ投稿する配信(`loop-notify-pr` の状態コメントと `@loop` への返信は、finalize が組み立てる通知で、すでに方針に沿う)。`pr_create`・`pr_push` でのエージェントによるラベル(`pr_labels` は現在のまま)。エージェントのジョブのトークンと権限(認証情報の分離の spec)。skill と設定の読み元([別 spec](2026-10-17-loop-agent-config-source-design.md))。

**アンチゴール:** エージェントの手順(skill と maker の指示)に、GitHub への書き込みが残る。同じ実行で、自分の投稿を後から編集する。新しいスクリプトの入力が増える。許可リストにないラベルが付け外しされる。

## 設計

### 1. `delivery` の値と検証

| 値                             | 配信                                                                    | ターゲット                       | level      |
| ------------------------------ | ----------------------------------------------------------------------- | -------------------------------- | ---------- |
| `issue_comment`                | 既存の Issue に1つのコメントを投稿                                      | Issue の entity(`kind == issue`) | L1、L2、L3 |
| `pr_review`                    | 既存 PR に1つのレビュー(event は常に `COMMENT`、インラインコメント付き) | PR の entity(`kind == pr`)       | L2、L3     |
| `none`、`pr_create`、`pr_push` | 現在のまま                                                              | 現在のまま                       | 現在のまま |
| `issue_create`                 | 予約値(拒否)                                                            | —                                | —          |

配信設計の第6節の表(level を主キーにする検証)を、次のように直す。detect の段階で、`loop-detect` と `loop-entity-detect` が検証する。そのため、両 action と `validate_loop_write_contract` に、入力 `finalize_script` と `finalize_label_allowlist` を足す。

- L1 の `delivery`: `none` か `issue_comment`(配信設計の第1節の「`none` 以外は L2 以上」を改める)。L1 では `finalize_script` を拒否する。
- L2/L3 の `issue_comment` と `pr_review`: `finalize_script` を必須にする(投稿ファイルを書くのが hook のため)。
- `finalize_label_allowlist`: `delivery` が `issue_comment` か `pr_review` のときだけ許す。
- 両 detect は、契約の検証の後に `validate_delivery_value` を呼ぶ(`loop-entity-detect/lib/detect.sh:215`、`loop-detect/lib/detect.sh:992`)。L1 を止めているのは、`validate_loop_write_contract` の `delivery != none` の検査と、`validate_delivery_value` が `issue_comment` を未実装として拒否することである。この2つを第1節の表に合わせて直す。`validate_delivery_target`(`delivery.sh:150-163`)と `parse_target.sh:69`・`:95` にも新しい値を足す(足さないと finalize の Parse Target で失敗する)。`loop-detect`(entity でない loop)は `integration` と `pull_request` しか出さないので、`issue_comment` と `pr_review` を設定の段階で拒否する(`validate_delivery_detect_config`。現在は候補があるときだけ失敗する。`loop-detect/lib/detect.sh:960-965`)。
- **改名:** 入力 `finalize_hook_script` を `finalize_script` にする(`detect_script` と対にする)。caller、`ci-loop-caller*.yaml`、`ci-loop-agent.yaml`、`loop-finalize`(`FINALIZE_HOOK_SCRIPT` を含む)、`loop_input_topology.py`、docs、bats を改める。`loop-caller-parity.bats` の旧い名前の一覧に `finalize_hook_script` を足す。
- `pr_review` のターゲットは、PR の entity に狭める(配信設計は pull_request も挙げていたが、使う loop がない)。配信設計の `none` の説明(「L1 triage が自分で完結」)を「何も配信しない」に直す。

### 2. 投稿ファイル

`LOOP_MESSAGE_DIR`(`runner.temp` の下。プラットフォームが作る)に置く。

| ファイル              | 内容                                                                                                                                                                                                                                   |
| --------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `message.md`          | `issue_comment` の本文(Markdown)                                                                                                                                                                                                       |
| `review.json`         | `pr_review` の `{"body", "commit_id", "comments", "fallback_body"}`。`comments` は Create a review API の形。`fallback_body` は全指摘を本文に移した版で、HTTP 422 の再試行に使う(現在の `post_review.sh:814-824` の挙動を配信側へ移す) |
| `message_labels.json` | 任意。`{"add": [...], "remove": [...]}`                                                                                                                                                                                                |

- 配信先の番号は書かない。finalize が `target_json` の `handoff_key` から取る。
- **L1:** エージェントが書く。`loop-agent-once` がディレクトリを作り、絶対パスをプロンプトの末尾に足し、claude には `--add-dir` で書き込みを許す(`agent.sh:436-438` の detect JSON と同じ形)。実行後、ファイルを `{"body", "labels"}` の JSON にして、ジョブの出力 `message_json` で finalize-l1 に渡す(artifact は使わない。出力は 1MB まで)。エージェントが成功したのに `message_json` が空なら、警告を出す(秘密の値を含む出力を GitHub が捨てた場合や、書き込みの失敗を見えるようにするため)。stdout からの本文の取り出しと、プラットフォームの行の除去はなくす。
- **L2/L3:** `finalize_script` が finalize の中で書く(第4節)。
- `loop-finalize` は、最初に `message_json` を `LOOP_MESSAGE_DIR` のファイルに戻す。配信は、どの level でもファイルだけを読む。

### 3. finalize の配信

`loop-finalize` の順番は、Determine Outcome → Run Finalize Hook → **Deliver Message**(新設)→ 既存の Push、Create PR、Write State、Delete Agent Branch。

**Deliver Message**(`lib/loop/` の1つの関数)は、`delivery` が `issue_comment` か `pr_review` で、`agent_result == success` かつ `verdict != REJECT` のときに動く。level では分岐しない(`loop-finalize/action.yml:55` の「level は表示のみ」を保つ)。

1. ファイルがない、または本文が空なら、何もしない(ラベルも付けない)。outcome を `unchanged` に下げる。
2. 本文(`pr_review` は `body` と `fallback_body` の両方)の先頭に marker(`<!-- <loop_name>:v1 -->`)がなければ付け(422 の再試行の後も `detect_pr_review.sh:363` が見つけられるように)、末尾に `build_loop_meta_block` で Meta とフッターを付ける。usage は入力 `usage_json`。
3. ラベルを付け外しする(第5節)。投稿の前に行う(ラベルに失敗したとき、状態と合わない文面だけが残らないようにするため)。
4. 投稿する。`issue_comment` は `gh issue comment <n> --body-file`。`pr_review` は `gh api -X POST repos/{o}/{r}/pulls/<n>/reviews`(`event: COMMENT` 固定)。HTTP 422 で `comments` があれば、`comments` なしで `fallback_body` を本文にして1回だけ再試行する。
5. 失敗はステップを失敗させ、`loop_failure_record` で記録する(`.github/workflows/CLAUDE.md` の Failure diagnostics)。出力 `outcome` は、1 で下げたときの `unchanged` だけを書く。投稿に成功したときは書かない(予定の値と `finalize_outcome_override` をそのまま使う)。本文が空なら、override があっても `unchanged` にする(投稿していないため)。

**outcome:** Determine Outcome の判定の順は、`finalize_outcome_override` → エージェントの失敗(`error`)→ `REJECT`(`rejected`)→ `issue_comment` で `issue_commented`、`pr_review` で `pr_reviewed` → 既存の `has_changes` の判定、とする(`pr_review` の `REJECT` は `rejected` のまま。bats で確かめる)。Write State の `OUTCOME`(`action.yml:278`)と action の出力 `outcome`(`:127`)は、`steps.deliver.outputs.outcome || steps.outcome.outputs.value` にする。失敗は、finalize のステップの失敗として `error` になる。hook の `OUTCOME`(`:197`)は予定の値で、後で `unchanged` や `error` に変わり得る(第4節の契約に書く)。state の書き方は `metadata` のまま(`resolve_state_write_mode.sh` は知らない値に `metadata` を返す)。agent ブランチは `none` と同じく削除する。`should_delete_rejected_branch.sh:39` と、Delete Agent Branch の `if`(`action.yml:291`)の両方を、`always() && inputs.branch != '' && (REJECT か、delivery が none・issue_comment・pr_review)` に直す。Deliver Message が失敗したときも pr-review の報告のブランチは消える(調べる材料は run のログに残るので許容する)。新しい値を `outcome.sh`、`loop-run-log/action.yml:40`、`docs/reference/specification.md:400`・`:509-517`、ledger、state-promote が受け付けるかを確かめる。

**finalize-l1:** `loop-finalize` を実行する。`current_sha` と `branch` に空文字を渡し(`current_sha` は `required: true`、`action.yml:17-19`)、Write State などは動かさない。ほかに必須の `github_token`(`:39-41`)と `state_branch`(`:97-99`)、marker に使う `loop_name`、表示用の `level`、`delivery`、`finalize_label_allowlist`、`message_json`、`target_json`(Parse Target が必須にするので、`ci-loop-agent.yaml:203-206` の説明を「L1 でも必須」に直す。外部の caller への契約の変更)、`usage_json`、`agent_engine`、`agent_result` を渡す。Finalize のステップに `continue-on-error: true` を付け、Append Run Log の outcome を finalize-l2 と同じ式(`ci-loop-agent.yaml:612`)にする。L1 の `failure_stage` の記録は、[run-log の spec](2026-10-18-loop-finalize-run-log-outcome-design.md) で扱う。

### 4. pr-review の hook

- `post_review.sh` を `render_review.sh` に改名し、投稿(`post_payload` と 422 の再試行)を外す。検証と組み立て(`validate_report`、`resolve_trusted_shas`、head SHA の照合、`annotate_report`、`build_payload`)は残し、`review.json` を書く。報告の読み方(`git show origin/<branch>:`)は変えない。組み立てられないときは、警告を出してファイルを書かない(現在の fail closed と同じ)。
- **hook の契約**(配信設計の第4節を改める): 書いてよいのは、リポジトリ内のファイルと `LOOP_MESSAGE_DIR` の投稿ファイル。`GH_TOKEN` は読み取りに使う。L2/L3 だけで動く。`LOOP_META_BLOCK` は渡さない。`OUTCOME` は予定の値である。

### 5. ラベル

- 許可リストは、caller の入力 `finalize_label_allowlist`(改行区切り)。空なら `labels` は無視して警告する。許可リストにないラベルは、付け外しせずに警告し、残りは続ける。
- REST の Issue の API で扱う(PR も同じ API)。付けるのは `POST repos/{o}/{r}/issues/<n>/labels` に `{"labels": [...]}` を1回。外すのは `DELETE .../labels/<URL エンコードした名前>` で、404 は成功とみなす。失敗はステップを失敗させる(triage は `triage:needs-info` が付かないと、作者の返信で再び動かない。`on-loop-github-issue-triage.yaml:84`)。
- 存在しないラベルを POST したときに GitHub が作るかは、ビルダーが確かめる。作るとしても、許可リストの範囲なので許容する。

### 6. 権限と許可リスト

- `agent-l1`: `issues: write` を外す(エージェントも `loop-agent-once` も投稿しない)。
- `finalize-l1`: `issues: write` を足し、`pull-requests: write` を外す(run-log は直接 push する。`loop-run-log/lib/append.sh:281`)。`finalize-l2`: `issues: write` を足す。
- caller の `agent_tool_allowlist` から、投稿とラベルのコマンドを外す(triage の `gh issue edit`、`gh label create`、`gh api`。読み取りは `gh api -X GET`)。ほかの loop の書き込みのコマンド(pr-revise の `gh pr comment` など)とトークンは、認証情報の分離の spec で扱う。
- triage の失敗の止め(エージェントが `triage:failed` を付ける)は、エージェントが失敗したときには働かなくなる(Deliver Message は `agent_result == success` のときだけ動く。現在の `post_loop_comment` は失敗でも投稿する。`run.sh:122`)。意図した変更として受け入れる。失敗した triage は run-log の `error` で見える。

### 7. caller の移り先

- **triage:** `delivery: issue_comment`。`finalize_label_allowlist` は `needs-triage`、`bug`、`feature`、`question`、`documentation`、`triage:needs-info`、`triage:ready`、`triage:failed`(skill の FSM でエージェントが付ける失敗の止め。`category-fsm.md:18-20`。止める方向にしか働かない)。`autofix` は入れない(人が付ける)。maker の指示と `SKILL.md` を「loop のときは付けず、投稿せず、`message.md` と `message_labels.json` を書く」に変える。対話の手順(`issue_comment.sh`)は残す。
- **pr-review:** `delivery: pr_review`、`finalize_script: .agents/skills/github-pr-review/scripts/render_review.sh`。

## 移行

配信設計と同じく、`pin_config_actions.sh` で変更と pin を1回で push する。互換の処理は作らない。dogfood は、使い捨てのブランチで triage と pr-review を `workflow_dispatch` で動かす。

## 検証

- 検証の表: 第1節の全セル(値 × ターゲット × level、`finalize_script` の必須と拒否、`finalize_label_allowlist` の許可と拒否)。
- Deliver Message: marker、Meta とフッターが `body` と `fallback_body` に1回だけ付くこと、空の本文で何もしない(`unchanged`)こと、`event` が常に `COMMENT`、422 だけで再試行、番号が `handoff_key` から取られること、失敗でステップが失敗すること、`REJECT` とエージェントの失敗で動かないこと。
- ラベル: 許可リストの内外、空の許可リスト、1回の POST、404 の DELETE、失敗でステップが失敗、投稿より先に行うこと。
- `loop-agent-once`: ファイルから `message_json` を作ること、`--add-dir` を付けること、ファイルがないとき・壊れた JSON のとき。
- `render_review.sh`: 現在の `post_review.bats` の検証と組み立ての全ケースを `review.json` に対して移す。
- outcome: Determine Outcome の判定の順(`pr_review` の `REJECT` を含む)と予定の値、成功した投稿で override が残ること、Deliver による `unchanged` への引き下げ、Write State と出力 `outcome` が最終の値を使うこと。
- `loop-caller-parity.bats`: `agent-l1` に `issues: write` がないこと。finalize-l1 が `loop-finalize` を `current_sha: ""` で実行すること。同じジョブの中で、自分が作ったコメントやレビューを更新するステップがないこと。
- dogfood: triage と pr-review が Meta とフッター付きで1回だけ投稿し、triage のラベルが許可リストの範囲で付くこと。

## 影響を受ける箇所

`lib/loop/`(`delivery.sh`、`validate_loop_write_contract.sh`、`entity_meta.sh` は Deliver Message に置き換え、`outcome.sh`)、`loop-agent-once`、`loop-execute`(`agent.sh` の `--add-dir`)、`loop-finalize`(`action.yml`、`determine_outcome.sh`、`should_delete_rejected_branch.sh`)、`loop-detect`、`loop-entity-detect`、`ci-loop-agent.yaml`、`ci-loop-caller.yaml`、`ci-loop-caller-entity.yaml`、triage と pr-review の caller、skill の `github-pr-review` と `github-issue-triage`、docs(loop-engineering の index、pr-review と triage の workflow design、PR 本文の skill の契約、`specification.md`、配信設計の第1・4・6節)、`loop_input_topology.py`、`post_review.sh` を名指しする箇所(`github-pr-review/assets/review-body-template.md:2`、`inline-comment-template.md:2`、`loop-caller-inputs-reference.md:255`)、hook の投稿を説明する `on-loop-github-pr-review.yaml:5-16`・`:116-117` のコメント、対応する bats(`post_review.bats` は `render_review.bats` に。`action_finalize_hook_env.bats` の `LOOP_META_BLOCK` の検査を外す)。

## 未決

- 存在しないラベルを REST で付けたとき、GitHub が作るか。
- GitHub が、古い `commit_id` のレビューをインラインコメント付きで受け付けるか(受け付けなければ 422 で `fallback_body` になる)。
- claude 以外のエンジンで、`LOOP_MESSAGE_DIR` への書き込みを許す方法(エンジンごとの引数)。
