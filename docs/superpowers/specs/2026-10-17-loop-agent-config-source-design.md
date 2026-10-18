# Loop エージェントの skill と設定の読み元

**Status:** Draft(CI の権限の設定を読まない決定と、skill の書き方を追記。レビュー前)
**Date:** 2026-10-17
**Related:** [Loop 配信設計](2026-10-17-loop-delivery-plan-design.md)(この spec は、配信設計の第10節として書いたものを切り出した)
注記: 既存 spec に合わせて日本語で記述する。

## 経緯

配信設計の第8回レビューで、この節に重大な指摘が3件出た。配信の整理とは別の話題(信頼できない PR に対して、loop がどこまで守れるか)なので、ユーザーの判断で別の spec に分けた。配信設計は、移行の手順で、リリース前から開いている PR に main を取り込ませて回避する。

## 方針(ユーザー承認済み)

maker と checker が使う skill と MCP の設定は、PR head の作業ツリーからではなく、リポジトリのデフォルトブランチから読む。

**GitHub Actions との対応:** GitHub は、workflow ファイルを、イベントごとに次の ref から読む(GitHub Docs の Events that trigger workflows)。

| イベント                                                                                            | workflow ファイルの読み元 | この repo の loop                                                          |
| --------------------------------------------------------------------------------------------------- | ------------------------- | -------------------------------------------------------------------------- |
| `issue_comment`、`issues`、`schedule`、`workflow_run`、`repository_dispatch`、`pull_request_target` | デフォルトブランチ        | pr-revise(`@loop`)、triage、autofix、ci-sweeper、pr-review、changelog など |
| `workflow_dispatch`                                                                                 | 起動時に選んだ ref        | 全 loop の手動起動                                                         |
| `pull_request_review_comment`                                                                       | PR の merge commit        | pr-revise(レビューコメント)                                                |

`pull_request_target` がデフォルトブランチで動くのは、信頼できない PR のコードに書き込み権限を渡さないためである。loop も、同じ考え方にそろえる。

**現在の読み元:**

| 読むもの                            | 現在の読み元                                                      | 根拠                                           |
| ----------------------------------- | ----------------------------------------------------------------- | ---------------------------------------------- |
| detect スクリプト                   | 作業ツリーより前に固定(信頼できる側)                              | `loop-detect/lib/detect.sh:1200`               |
| checker の skill                    | ジョブの checkout(`GITHUB_WORKSPACE`)を優先し、なければ作業ツリー | `loop-execute/lib/verifier_skill.sh:36`        |
| maker の skill                      | エージェントの CLI が作業ディレクトリ(作業ツリー)から読み込む     | `loop-execute/lib/loop.sh:256`、`agent.sh:391` |
| 権限の設定(`.claude/settings.json`) | 作業ツリー(`--setting-sources project`)。新方針: 読まない         | `agent.sh:57`                                  |
| MCP の設定(`.mcp.json` など)        | 作業ツリー                                                        | `loop-execute/lib/mcp.sh:120-130`              |

PR を対象にするターゲット(pr-revise、ci-sweeper の PR ターゲット)では、作業ツリーは PR head である(`loop-detect/lib/detect.sh:356-359`、`ci-loop-agent.yaml:454-455`、`:474-475`)。そのため次の2つが起きる。

- PR が skill や権限の設定を書き換えると、その PR に対して書き込み権限付きで動くエージェントの指示と権限を、PR の作者が差し替えられる。
- [Loop 配信設計](2026-10-17-loop-delivery-plan-design.md)のリリース前から開いている PR では、PR head の旧い skill が、旧いプロンプトのキー(`may_edit`)を探す。新しいキー(`agent_edit_allowed`)を見つけられず、編集せずに REJECT で終わり得る(配信設計の第7-1節のプロンプトのキーの改名。配信設計は、移行の手順で、該当する PR に main を取り込ませて回避する)。

**新しい読み元:**

- maker の skill、checker の skill、MCP の設定は、デフォルトブランチから読む。イベントに関係なく同じにする。`pull_request_review_comment` では、ジョブの checkout が PR の merge commit になるので、デフォルトブランチを別に取得する。
- 例外は `workflow_dispatch` で、起動時に選んだ ref から読む。起動できるのは書き込み権限を持つ人だけで、作業ブランチの skill を dogfood で確かめる手段(配信設計の移行の節のリリース前の確認)になるためである。
- 作業ツリーの skill と設定は、エージェントに使わせない。エージェントが編集する対象のファイルとしては、これまでどおり作業ツリーにある。
- 読み元を変えても、エージェントの差分(commit)に、読み元から持ち込んだファイルが入ってはならない。

**CI は、導入先の権限の設定を読まない(2026-10-18 追記。ユーザー承認済み):**

- 目的は「導入先のリポジトリの設定ファイルを、CI の権限に使わない」ことである。権限の設定(claude の `.claude/settings.json`)は、デフォルトブランチからも読まない。claude では、CI のエージェントの権限は、caller の `agent_tool_allowlist` と実行のモード(`--permission-mode`)だけで決める(他のエンジンは次の項)。手段は、`--setting-sources project` をやめるだけでは足りない(フラグを外すと、省略時の既定が全ての読み元になる可能性が高い)。`--setting-sources user`、`--restricted`、`--bare` などを、実装の最初に確かめて選ぶ(未決)。
- 公式ドキュメントで確認した範囲(2026-10-18、調査): `--setting-sources` は `user,project,local` をコンマ区切りで指定する。`user` だけにすると、導入先の `.claude/settings.json` と `.mcp.json` は読まれない。ただし `project` を外すと、同じ `project` の読み元に属する CLAUDE.md、`.claude/rules/`、skill、subagent、command、hooks も読まれなくなる。このため、`--setting-sources` を `user` に切り替えるだけでは足りず、skill と指示ファイルをどう与えるかを、この spec の読み元の切り替えと一緒に決める必要がある。
- 理由は2つある。(1) 対話で使うための設定は、CI には広すぎる(例: このリポジトリの設定は `Bash(bash:*)`、`gh api:*`、`gh issue comment:*` を許す。配信の spec の後も、triage の書き込みを止めているのはプロンプトだけである)。(2) LE workflow を導入する別のリポジトリの設定(許可・拒否)で、CI が動かなくなったり広がったりする。CI の結果が、導入先の設定に左右されてはならない。
- 書き込みを止める本体は、エージェントのジョブのトークンの権限になる(未実装。[認証情報の分離](2026-10-18-loop-agent-credential-isolation-design.md))。この変更は、その実装の後に行い、その上に重ねる層とする。それまでは、`gh api:*` を許す caller は POST もできる。
- 上の「caller の許可リストと `--permission-mode` だけ」は claude の話である。copilot は `--allow-all-tools`(`mcp.sh:43`)、cursor は `.cursor/cli.json` を読み、codex などは許可リストを使わない(`agent.sh:517-525`)。他のエンジン(codex、copilot、cursor)は、設定の読み込みを止める手段がエンジンごとに違う。対応は各エンジンで確かめて決める(未決)。
- **これは、ほとんどの caller を壊す変更である。** 今の `append_claude_permission_args`(`agent.sh:51-65`)は、caller の許可リストだけを渡す。`grant_claude_workspace_trust`(`agent.sh:164-197`)は、導入先の `allow` を有効にするためだけにある。次の caller には許可リストが無い: changelog、docs-updater、refactor、tech-debt、test-gap。ほかの caller の許可リストは `gh` 系(と pr-review の `git show`)だけである。今は `settings.json` の `allow` が、`git diff`(maker のプロンプト自身が使う: `agent.sh:125`)、`Bash(bash:*)`(skill のスクリプト)、`go test`、`bats`、`jq`、`yq`、`grep`、`rg`、`find`、`WebFetch`、MCP のツール(`mcp__github` など。`mcp.sh:40` はサーバを有効にするだけ)を許している。checker(`verifier.sh:376`)も同じ許可リストを受ける。同じ変更で、各 caller の許可リストを組み直す。方法は、(a) 各 caller が、skill の必要とするコマンドを全て書く、(b) action が、読み取りだけの最小の基準(`git diff`、`log`、`show`、`status`)を持ち、文書にする(今の action は何も許さない: `agent.sh:14`)、のどちらかで、実装の最初に決める。
- **deny の規則と hooks も失われる。** 今の `settings.json` の deny(`Read(./.env)`、`Read(**/*.pem)`、`Bash(printenv:*)`、`Bash(env:*)`、`Bash(curl:*)`、`Bash(wget:*)`、`Bash(rm -rf:*)` など)は、CI で効かなくなる。caller の入力に deny を渡す経路は今は無い。失う deny は、トークンの権限と、チェックアウトに秘密のファイルが無いことで受け止める、とするか、deny の入力を足すかを、配信設計の「新しい設定値を増やさない」と合わせて決める(未決)。`Stop` と `PostToolUse` の hooks(lint、shfmt、prettier、`sync_apm_artifacts.sh`)も、CI の maker では動かなくなる。整形や同期は、skill の手順か finalize に移すか、失うことを受け入れるかを決める(未決)。
- 許可リストだけでは、書き込みを止められない。公式ドキュメントによると、`Bash(gh api -X GET:*)` は `gh api -X GET` で始まるコマンド全体に一致し、後ろに `-X POST` を足した形も許す。deny の規則も、`sh -c` や `git -C . push` のような別の形は一致しない。許可リストは「手順の指示」を強める層であり、止める本体は、トークンの権限である。

**スキルは、対話と自動実行の動きを分けて書く(同日追記。ユーザー承認済み):**

- スキルは、対話でも使うので、自動実行(loop)のときの動きを、スキルの本文に書く。CI の権限にないツールを、エージェントが試して失敗を繰り返さないようにするためである。
- 見分け方は、既にある対話と自動実行の区別(detect JSON と `## Constraints`、`agent_edit_allowed`。`docs/explanation/loop-engineering/loop-capable-skills.md`)を使う。`Loop message directory:` の行は、メッセージを配信する実行の印で、今は L1(`loop-agent-once/lib/run.sh:152`)だけが出す。L2 で `delivery` が `issue_comment` と `pr_review` の実行にも出すのは、配信の spec の実装(これから)である。ここで決めるのは、GitHub の API への書き込み(コメント、ラベル、レビューの投稿)だけで、ファイルを編集して commit する maker には当てはまらない。GitHub への書き込みは対話のときだけにし、メッセージを配信する実行では、決まったファイルを書く。変更は `loop-capable-skills.md` に行い、この節は方針だけを書く。
- スキルの文面は、特定のエンジンのツール名に依存させない(配布物であり、エンジンごとにツール名と指定の仕組みが違うため)。ツールの許可と拒否は、スキルではなく caller の許可リストが決める。スキルの文面は、強制力のない、手順の指示である。
- skill の `allowed-tools` のような、エンジン固有のフロントマターは、権限の制限には使わない(公式ドキュメントで確認済み: `allowed-tools` は確認なしで使えるツールを足すだけで、制限しない。他のツールは、権限の設定が引き続き決める。ツールを外すには `disallowed-tools` が別にあるが、エンジン固有なので使わない)。

**対象にしないもの:** リポジトリの指示ファイル(`CLAUDE.md`、`AGENTS.md`、`.claude/rules/`)は、編集する対象のコードの規約であり、PR がその規約を変えることもある。この spec の初版では読み元を変える対象にしない。ただし、claude の `project` の読み元を外す手段を選ぶと、これらも読まれなくなる。手段を選ぶときに、指示ファイルの与え方(デフォルトブランチからの取得、作業ツリーから `--add-dir`、与えない)を一緒に決める(未決に記す)。

**挙動の変化(意図した変更):** skill や設定を書き換える PR に対して pr-revise や ci-sweeper が動くとき、PR の版ではなく、デフォルトブランチの版の skill と MCP の設定を使う。PR を対象にしない loop(作業ツリーがデフォルトブランチから作られる loop)では、skill と MCP の読み元の内容は現在と同じである。ただし、claude の権限の設定を読まない変更は、PR を対象にするかどうかに関わらず、全ての loop に効く(権限、deny、hooks が変わる)。

## ビルダーに任せること(切り出し時点の案)

- 第10節の読み元の切り替え方。条件は、エージェントの差分に持ち込んだファイルが入らないこと、4つのエンジン(claude、codex、copilot、cursor)のどれでも、作業ツリーの skill と MCP の設定が使われないことである。候補は次のとおり。
  - 作業ツリーの該当ディレクトリを、デフォルトブランチの内容で上書きし、commit の前に元に戻す(`git update-index --skip-worktree` か、commit の前の `git checkout -- <paths>`)。
  - エンジンが対応していれば、設定と skill の場所を CLI の引数か環境変数で指定し、作業ツリーの設定を読ませない(claude の `--setting-sources` と `--add-dir` など)。

- MCP の与え方: `project` の読み元を外すと `.mcp.json` が読まれず、`enableAllProjectMcpServers`(`mcp.sh:40`)は、読まれない `.mcp.json` に対しては意味を持たない。デフォルトブランチの MCP の設定を、`--mcp-config <ファイル> --strict-mcp-config` で渡すことを第一候補にする。`run.bats:57` は、L1 で `--settings … --setting-sources project` を固定しているので、変える。
- skill と指示ファイルの与え方: maker の skill は、CLI が作業ディレクトリ(作業ツリー)から見つける(`build_agent_prompt`(`agent.sh:84`)は、skill のパスを渡さない)。`project` を外すと全ての maker が skill を失うので、skill の場所を別に渡す手段(`--add-dir` で default ブランチの内容を渡す、`--bare` と組み合わせるなど。どちらが `--setting-sources` と両立するかは未確認)を、実装の最初に確かめて決める。
- 手段の候補に `--bare`(hooks、CLAUDE.md、自動メモリを省き、`--mcp-config` を明示で受ける)も加える。`--safe-mode` は skill を無効にするので合わない。
- 目的の範囲: `user` だけにしても、ランナーの `~/.claude/settings.json`(セルフホストのランナーでは、ホストの管理下)、`--settings`、管理設定は効く。目的は「導入先のリポジトリの設定ファイルを、CI の権限に使わない」である。
- `grant_claude_workspace_trust` を消すには、信頼の確認が、選んだ読み元の組み合わせで他に何も制御しないことの確認が要る(未決)。
- 許可リストを組み直すときに、書き込みの系統(`Bash(gh pr comment:*)`、`gh api:*` など)を外す。
- 権限の設定を読まない変更に合わせて、次も更新する: `loop-caller-inputs-reference.md:215`、`:222-226`(claude の行と workspace trust の段落)、`test/bats/.github/actions/loop-execute/lib/agent.bats:8-12,91-114`、`test/bats/.github/actions/loop-agent-once/lib/run.bats:57`。triage caller のコメントは `:125-128`。
- 権限の設定(`.claude/settings.json`、`.cursor/cli.json`)と hooks は、「差し替える」のではなく「読まない」(エンジンごとに手段は未決)。
- 次を書き換える(実装の対象): reusable の入力の説明(`ci-loop-caller.yaml:102`、`ci-loop-caller-entity.yaml:103`、`ci-loop-agent.yaml:104`、`loop-execute/action.yml:72`、`loop-agent-once/action.yml:29`、`loop-caller-inputs-reference.md:223`)の「beyond the repository's `.claude/settings.json`」、triage caller のコメント(`on-loop-github-issue-triage.yaml:124-127`)、`agent.sh` の冒頭(`:14-17`、`:30-31`)。`grant_claude_workspace_trust` は、役目が無くなるので消す。

## 設計者が決めたこと(切り出し時点)

- 第10節の読み元の例外を `workflow_dispatch` だけにし、`pull_request_review_comment` でもデフォルトブランチから読むこと。

## 未決

- CI の権限の設定を読まない変更(2026-10-18 追記)の、残りの確認:
  - 確認済み(公式ドキュメント): `--setting-sources user` で導入先の `settings.json` と `.mcp.json` は読まれない。ヘッドレスの実行で許可されないツールは、確認なしで拒否される。deny は、どの読み元の allow よりも優先する。`acceptEdits` は、作業ディレクトリ内のファイル編集と、一部のファイル操作の Bash(`mkdir`、`touch`、`rm`、`mv`、`cp`、`sed` など。ドキュメントの2か所で一覧が違う)だけを自動で許す。
  - ドキュメントに記載なし: CLI の `--setting-sources` の省略時の値と、空の値の形(SDK では `[]` で全て無効)。`--settings` の JSON が、`user` だけの指定でも効くか(`mcp.sh:40` の `enableAllProjectMcpServers` が、導入先の `.mcp.json` を使う場合に関わる)。`--add-dir` の skill が `project` の読み元に属するか(CLI のページに記載なし)。
  - 実装の最初に、CI のイメージで `claude doctor` か `/status` の `Setting sources` の行を見て確かめる。
  - 影響の確認: skill、`CLAUDE.md`、`.mcp.json`、hooks が `project` と一緒に外れる。dogfood の caller が `settings.json` の許可(例: `Bash(bash:*)`)に頼っていないか。頼っていれば、各 caller の許可リストを見直す。
- 第10節: 各エンジンの CLI が、skill と設定を作業ディレクトリ以外から読めるか、作業ディレクトリの設定を無効にできるかは、確かめていない。実装の最初に、エンジンごとに確かめる。
- 第10節: リポジトリの指示ファイル(`CLAUDE.md`、`AGENTS.md`、`.claude/rules/`)の読み元。PR がエージェントの指示を差し替えられる点は skill と同じだが、編集する対象の規約でもあるため、本 spec では変えない。別に判断する。

## 第8回レビューで出た、未解決の指摘

設計を続けるときに、次を解決する。行番号は、配信設計の `5188cd2a` 時点のコードである。

- **作業ツリーを上書きして戻す案は、「持ち込んだファイルを commit に入れない」条件を満たせない。** commit は作業ツリーの `git add -A` で行う(`loop-execute/lib/agent.sh:150-160`)。パスの検査は commit 済みの差分だけを見る(`paths.sh:317-339`)。`harvest_workspace_into_worktree` は、`GITHUB_WORKSPACE` の変更を作業ツリーへ写す(`agent.sh:263-329`、`loop.sh:265`)。main にだけあるファイルは未追跡のまま commit に入り、PR head にだけあるファイルを上書きで消すと削除が commit に入る。PR が skill の source を正当に直して同期先を更新した場合、戻す方式では変更が消え、`skip-worktree` の方式では commit から隠れる。エージェントがディスク上で見るのも main の版になり、「編集する対象としては作業ツリーにある」と矛盾する。
- **`pull_request_review_comment` では、skill を差し替えても守れない。** このイベントでは、workflow ファイルが PR の merge commit から読まれる。dogfood の caller はローカルの reusable を呼ぶ(`on-loop-github-pr-revise.yaml:78`)ので、PR は caller の入力、pin、detect スクリプト(`.agents/skills/github-pr-revise/scripts/detect_pr_revise.sh`)、finalize の hook スクリプト(`loop-finalize/action.yml:219-234`)を書き換えられる。「detect スクリプトは信頼できる側」という記述は、このイベントでは誤り。このイベントでの保証の範囲を決める必要がある。
- **差し替える対象が claude に偏っている。** `.claude/agents/`、cursor の `.cursor/hooks.json`・`.cursor/agents/`・`.cursor/rules`、codex の設定、MCP の探索順(`.mcp.json` → `.cursor/mcp.json` → `.github/mcp.json`、`mcp.sh:126-129`)を、エンジンごとのパスの一覧として定義する。checker も作業ツリーで動く(`verifier.sh:226`、`:369`)ので、同じ扱いにする。
- **差し替えるパスを、どこで指定するか。** `.github/workflows/CLAUDE.md` の Portability は、reusable と composite に `.claude/` などのパスを書き込むことを禁じている。caller の新しい入力にする場合は、配信設計のアンチゴール(新しい設定値を増やさない)との関係を整理する。
- **base ブランチが main 以外のとき。** integration ターゲットが main 以外のブランチから作業ツリーを作る場合、デフォルトブランチから読むと、そのブランチの skill ではなく main の版を使う。dogfood はすべて `branch_match: main` なので影響しない。なお、レビューは `pull_request_target` が PR の base ブランチから workflow を読むと指摘したが、GitHub Docs は「the default branch of the base repository」と書いており、この点は誤りと判断した。
- **L1(`loop-agent-once`)の読み元。** `agent-l1` は ref なしで checkout し、`working_directory: "."` で動く(`ci-loop-agent.yaml:295-299`、`loop-agent-once/action.yml:49-52`)。現在の dogfood の L1(triage)には影響しない。
- **checker の skill の、作業ツリーへのフォールバック**(`verifier_skill.sh:36`)を、新しい方針でどう扱うか。
- **引用の訂正。** maker の CLI の作業ディレクトリを決めているのは `loop-execute/action.yml:203`。`mcp.sh:120-130` の探索は codex のときだけ動き(`mcp.sh:79-81`)、claude は `.mcp.json` を CLI 自身が読む。
