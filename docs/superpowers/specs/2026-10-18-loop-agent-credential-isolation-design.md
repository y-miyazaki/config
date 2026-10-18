# Loop のエージェントのジョブから書き込みの認証情報をなくす

**Status:** Draft(第5回レビューで High・Medium なし。Low を反映)
**Date:** 2026-10-18
**Related:** [Loop の投稿の配信とラベル](2026-10-18-loop-delivery-message-design.md)(**この spec は、その後に実装する**)、[run-log の outcome を `loop-finalize` に寄せる](2026-10-18-loop-finalize-run-log-outcome-design.md)(同じく、その後に実装する。`always()` のステップと `github.action_status` に依存する)

## 方針(ユーザー承認済み)

基本線は、検出 → エージェント → finalize(run-log、ドメイン処理、配信、state)である。エージェントは中身を作るだけで、GitHub へ書き込まない。エージェントのブランチの push も配信の一部として、finalize で行う。エージェントのジョブには、GitHub への書き込みができる認証情報を置かない。

## 現状の問題

- `agent-l1` と `agent-l2` は `loop-resolve-push-token` を実行し、App の秘密鍵(`secrets.BOT_APP_PRIVATE_KEY`)と、それで発行した App のトークンを持つ(`ci-loop-agent.yaml:279-304`、`:388-394`)。App のトークンは、常に `contents`・`issues`・`pull-requests`・`workflows` の書き込み権限を持つ(`loop-resolve-push-token/action.yml:31-34`)。
- L2 では、そのトークンが `loop-execute` に入力として入り、エージェントを動かすステップ(`loop-execute/action.yml:196`)と push のステップ(`:236`)の両方で使われる。`loop-worktree-setup` は、それを `.git/config` の `extraheader` に書く(`loop-worktree-setup/action.yml:53`)。
- dogfood のエージェントは `Bash(bash:*)` を許されており(`.claude/settings.json:7`)、GitHub のランナーは sudo が使える。ジョブの中にある秘密情報は、ファイルとプロセスのメモリから読める。エージェントにトークンを渡さないだけでは足りず、ジョブに置かないことが要る。
- 同じ理由で、エージェントのジョブの出力(bundle、`has_changes`、`verdict`、`notify_context_json`)と、同じジョブで動く denylist・allowlist・checker の結果は、エージェントが書き換えられる。finalize は、それを信じて書き込んではいけない。
- `github.token` でも、`contents: write` があれば、`repository_dispatch` を送って loop(autofix、pr-revise)を起動できる。

## 変更

### 1. エージェントのジョブ

- `agent-l1` と `agent-l2` から、`loop-resolve-push-token` のステップと、`BOT_APP_*`・`GH_TOKEN` の秘密情報の参照をなくす。`loop-worktree-setup`、`loop-execute`、`loop-agent-once` には `github.token` を渡す。
- 権限は、`contents: read`、`issues: read`、`pull-requests: read`、`copilot-requests: write`(copilot エンジン用。現在のまま)。`agent-l2` は `actions: read` も残す(ci-sweeper の `gh run view`)。
- ワークツリーの準備と、エージェントの実行中の fetch(`verifier.sh:232`、`paths.sh:326`、`notify_context.sh:344`)は、同じリポジトリの読み取りだけで、`github.token` で足りる(fork の PR は、pr-review と pr-revise の detect で除外されている)。
- `loop-execute`・`loop-agent-once`・`loop-install-cli` の `setup-uv` を `enable-cache: false`、`setup-node` を `package-manager-cache: false` にする(`loop-execute/action.yml:178`・`:185`、`loop-agent-once/action.yml:71`・`:78`、`loop-install-cli/action.yml:33`・`:40`)。エージェントが中身を詰めたキャッシュを、post のステップが既定のブランチのスコープに保存し、ほかの workflow が復元するのを防ぐ。
- GitHub の MCP サーバ(`.mcp.json:25`)は `github.token` で動かす。受け付けられなければ、エージェントは MCP なしで、読み取りの `gh` を使う。

### 2. push を finalize へ移す

- **Bundle Branch:** `loop-execute` の Push Branch(`lib/push.sh`)を置き換える。条件は現在の push と同じ(変更があり、denylist に当たっていない)。`git bundle create <file> "^origin/<base_branch>" "refs/heads/<branch>"` で、base にないコミットだけを入れる(base は `verifier.sh:232` で取得済み)。pr_push のターゲットでも、PR の head の SHA を前提にしないので、実行中に head が force-push されても検証に通る。
- artifact の名前は `loop-agent-bundle-<run_attempt>-<target_json.key の sha256 の先頭16文字>`(ブランチ名は秒単位の時刻で、並ぶ matrix のセルで重なり得る。`loop-worktree-setup/action.yml:85-86`)。両方のジョブの Parse Target で計算する。`retention-days: 1`(handoff の artifact と同じ。`loop-detect/action.yml:190-192`)。finalize-l2 だけを再実行すると前の attempt の bundle が見つからず `error` になるが、許容する。
- 出力 `has_changes` は「bundle を作った」を意味するようになる(現在は「リモートにブランチがある」。`push.sh:85`)。run-log と Notify Context の `HAS_CHANGES` はこの意味で読む。`specification.md` に書く。
- **finalize-l2 の取得:** 上げるのは agent-l2 の Execute の後の workflow のステップ、取得は finalize-l2 の workflow のステップとする。`if: needs.agent-l2.result == 'success' && needs.agent-l2.outputs.has_changes == 'true'`、`continue-on-error: true`。Build Notify Context が bundle の後に失敗した場合(`loop-execute/action.yml:248`)は、取得も push もしない。`loop-finalize` には新しい入力 `agent_bundle_dir` で渡す。
- **ブランチ名の検証:** finalize は、入力 `branch`(`needs.agent-l2.outputs.branch`、`ci-loop-agent.yaml:536`、`:539`)が空でなければ、`<agent_branch_prefix>/<agent_maker_skill_name>/` で始まり(文字列として比べ、正規表現に埋め込まない)、残りが `^[0-9]{8}-[0-9]{6}$` に合い(`loop-worktree-setup/action.yml:85-86` の形)、`to_branch` とも `state_branch` とも違うときだけ受け付ける。push、hook の `EXECUTE_BRANCH`、Push to Target Branch、Delete Agent Branch のすべてがこの検証を通った名前を使う。合わなければ失敗として扱う。空なら検証せず、1 の何もしない場合になる(finalize-l1 と、ワークツリーの準備より前のエージェントの失敗)。push は force しない。新しい入力 `agent_branch_prefix` と `agent_maker_skill_name` を finalize-l2 から渡す(現在は `loop-worktree-setup` にだけ渡す。`ci-loop-agent.yaml:425-426`)。
- **Push Agent Branch**(`loop-finalize` の新しいステップ。Parse Target の後、Determine Outcome の前)。新しい入力は `agent_bundle_dir`、`agent_edit_allowlist`、`agent_edit_denylist`(空ならプラットフォームの既定。`paths.sh:20`)。`parse_target.sh` は `base_branch` も出す(`ci-loop-agent.yaml:412` と同じ式)。
  1. `agent_result != success` か `has_changes != 'true'` なら、何もしない。workflow は取得の成否にかかわらず決まったパスを `agent_bundle_dir` に渡し、そこに bundle がなければ失敗として扱う。
  2. `git fetch origin <base_branch>`、`git bundle verify`、`git fetch <file> "refs/heads/<branch>:refs/heads/<branch>"` で、そのブランチだけを取り込む。
  3. `target_json.from.ref` が空でなければ、先端がその子孫であることを確かめる(`from.ref` は detect が決めた値。base の子孫は求めない。PR の head や実行中の main は base より遅れ得るため)。
  4. `git diff --name-only --no-renames` の差分のファイル(`from.ref` があれば `<from.ref>..<branch>`、なければ `origin/<base_branch>...<branch>`)に、caller の denylist と allowlist をかけ直す。`.loop/` は除かない(`paths.sh:331` と違う)。`--no-renames` で、denylist のファイルを許されたパスへ移す変更も捕まえる(`paths.sh:331` と `verifier.sh:232` の同じ形は、関数を移すときに一緒に直す)。判定の関数は `loop-execute/lib/paths.sh` から `lib/loop/` に移し、両方から使う。
  5. 変わった `.github/workflows/` のファイルは、`.github/` で始まる allowlist のパターンに当たるときだけ許す(`**` だけでは許さない)。push したブランチの workflow は、`on: push` で秘密情報を持って動くため。ci-sweeper(`.github/**`、`on-loop-ci-sweeper.yaml:81`)は許され、pr-revise・pr-review・autofix(`**`)は拒まれる。
  6. `git ls-remote origin refs/heads/<branch>` で、ブランチがすでにあれば失敗とする(エージェントが時刻を選んで、同じ skill の別の実行のブランチを指すのを防ぐ。finalize-l2 だけの再実行は bundle が見つからないので、正当な再 push はない)。解決したトークン(App → `GH_TOKEN` → `github.token`、`loop-resolve-push-token/action.yml:37-45`)で `origin/<branch>` に push する。
- **失敗:** 名前の検証と 1〜6 の失敗は、`loop_failure_record` で `LOOP_FAILURE_FILE`(`loop-finalize/action.yml:244`、`:318`)に段階 `push` で記録し、出力 `pushed=false`、`failed=true` を書いて、ステップは 0 で終える。Determine Outcome は、`failed` を `finalize_outcome_override` より先に見て `error` にする。Resolve State Write Mode は、`failed` のとき `metadata` にする(`advance` でカーソルが進んだり、`pending` が PR 番号なしで失敗したりしないように)。Run Finalize Hook と Deliver Message は `failed` でないときだけ動く(ledger の hook は変更がなくても動く)。Push to Target Branch、Create PR、Delete Agent Branch は、`pushed == 'true'` のときだけ動く(push していなければ、消すべき自分のブランチはない。変更のない REJECT は現在も push されない。`push.sh:69-71`)。配信の spec と合わせた Delete Agent Branch の `if` は、`always() && steps.<push>.outputs.pushed == 'true' && (REJECT か、delivery が none・issue_comment・pr_review)` になる(`should_delete_rejected_branch.sh` が `issue_comment` と `pr_review` でも削除を返す変更は、配信の spec が持つ)。`agent_result` が success でないときは、bundle があっても push も PR の作成もしない(現在の Create PR は `agent_result` を見ない。`action.yml:232-236`)。Write State は `error` を記録する(detect が同じターゲットを次の回に選び続けないように)。`failed` のときにステップを失敗させるステップを、Delete Agent Branch の後、run-log の spec の `always()` のステップより前に置く(`github.action_status` に反映させるため)。
- 後の Run Finalize Hook(pr-review の `render_review.sh` は `origin/<branch>` を読む)、Push to Target Branch(`push_target.sh:100`)、Create PR は、現在のまま `origin/<branch>` を使う。

### 3. caller の許可リストと skill

- caller の `agent_tool_allowlist` から、書き込みのコマンドを外す。pr-revise の `gh pr comment`、`gh api`、autofix と ci-sweeper の `gh api`。読み取りは `gh api -X GET` にする。制限の本体はトークンで、許可リストは整理である。
- loop のときに skill が自分で GitHub に書き込む手順がないことは、レビューで確かめた(pr-review の `post_review.sh` だけで、配信の spec が扱う)。

## 残るもの(この spec では変えない)

- **自己申告の値:** `verdict`、`has_changes`、`finalize_outcome_override`(`loop.sh:190`)は、エージェントのジョブが出す値のままである。偽の `APPROVE` は、`pr_push` の人の PR への反映(`push_target.sh:100-117`)と L3 の auto-merge(`loop-finalize/action.yml:258-268`)に届く。push される中身は第2節の 3〜5 で制限される。checker を別の読み取り専用のジョブに移すのは、別に扱う。
- **push で動く workflow:** allowlist に `.github/` を入れた caller(ci-sweeper)は、push したブランチの workflow が秘密情報を持って動くことを受け入れる(判断は自己申告の `verdict` だけ)。Create PR や `pr_push` の後に動く `pull_request` の workflow(例: `on-ci-security.yaml`)も、同じリポジトリのブランチのコードを秘密情報と一緒に動かす(この spec の前からある)。また、秘密情報を持つ push の workflow は、push された木のコードを動かしてはいけない。`on-ci-push-mise-update-lock.yaml:10-13` は全ブランチの `mise.toml` の変更で App の秘密鍵を持って `mise lock` を動かすので、`branches: [main]` に絞る(この spec の範囲外の別の修正)。
- **ランタイムのトークン:** すべてのジョブにあり、Actions のキャッシュと artifact に書ける。キャッシュは第1節で止める。artifact は同じ run の中だけで使われ、finalize が検証する。bundle の名前は予測できるので、エージェントが先に同じ名前で上げ得る。上げるステップは `overwrite: true` にせず、既にあればエージェントのジョブを失敗させる。先に上げられても、finalize の検証の範囲を超えるものは push されない。
- エンジンの認証情報 `AGENT_TOKEN` は、エージェントのジョブに残る。copilot エンジンでは、これが GitHub の PAT(`COPILOT_GITHUB_TOKEN`、`agent.sh:445`)で、ジョブの権限では制限されない。Copilot Requests だけに絞った fine-grained PAT にすることを、docs に書く。
- `.claude/settings.json` の `Bash(bash:*)` などは、CI のエージェントにも読み込まれる。この spec の後は、ジョブに書き込みの認証情報がないので、GitHub への書き込みの抜け道にはならない。権限の4ファイル(CLAUDE.md の Permission parity)の見直しは別に扱う。
- REJECT のブランチを「人が調べるため」に push する挙動(`push.sh:21-23`)は変えない(push は finalize に移る)。

## 検証

- `loop-caller-parity.bats`: `agent-l1` と `agent-l2` が、`loop-resolve-push-token` を実行せず、`BOT_APP_*` と `GH_TOKEN` の秘密情報を参照せず、`contents`・`issues`・`pull-requests` の書き込み権限を持たないこと。3つの `action.yml`(`loop-execute`、`loop-agent-once`、`loop-install-cli`)の bats で、`enable-cache: false` と `package-manager-cache: false` を確かめる。
- Bundle Branch の bats: 変更あり、変更なし、denylist、bundle が `^origin/<base>` の範囲であること。
- Push Agent Branch の bats: bundle あり・なし、`has_changes` なのに bundle がない、形の合わないブランチ名(`main`、`state_branch` を含む)、空のブランチ名で何もしないこと、ほかの ref を含む bundle、`from.ref` の子孫でない先端、`from.ref` が空のとき、`.loop/` の変更、denylist のファイルの改名、既存のブランチ、`failed` のとき Run Finalize Hook と Deliver Message が動かず、変更なしのとき ledger の hook が動くこと、push していないときに Delete Agent Branch が動かないこと、取得に失敗して bundle がないとき、denylist・allowlist のかけ直し、`.github/workflows/` の変更(`.github/**` で許可、`**` で拒否)、PR の head が force-push された後の bundle、push の失敗で override より `error` が優先され、state のモードが `metadata` になり、ステップが失敗すること。
- dogfood(使い捨てのブランチ): `pr_create`(例: changelog)、`pr_push`(pr-revise)、`pr_review`(pr-review)が、現在と同じブランチと PR を作ること。GitHub の MCP サーバが `github.token` で認証できるか。agent のジョブで、参照しない秘密情報がランナーに渡らないこと(プロセスの環境と `_temp` を、App の秘密鍵のハッシュで grep する。見つかれば別に扱う)。

## 影響を受ける箇所

`ci-loop-agent.yaml`(エージェントのジョブの権限と秘密情報、artifact の上げ下ろし)、`loop-execute`(`action.yml`、`lib/push.sh` を bundle に置き換え、`setup-uv`)、`loop-finalize`(Push Agent Branch、入力 `agent_bundle_dir`・`agent_edit_allowlist`・`agent_edit_denylist`・`agent_branch_prefix`・`agent_maker_skill_name`、`parse_target.sh` の `base_branch`、`determine_outcome.sh`、`resolve_state_write_mode.sh`、ステップの `if`)、`loop-install-cli`、`lib/loop/`(パスの判定を `paths.sh` から移す)、`loop-worktree-setup`、`loop-agent-once`(`setup-uv`)、pr-revise・autofix・ci-sweeper の caller、docs(`docs/reference/specification.md`、loop-engineering の index と各 workflow design)、対応する bats。
