# Loop エージェントの skill と設定の読み元

**Status:** Draft(未レビュー。設計の続きが必要)
**Date:** 2026-10-17
**Related:** [Loop 配信設計](2026-10-17-loop-delivery-plan-design.md)(この spec は、配信設計の第10節として書いたものを切り出した)
注記: 既存 spec に合わせて日本語で記述する。

## 経緯

配信設計の第8回レビューで、この節に重大な指摘が3件出た。配信の整理とは別の話題(信頼できない PR に対して、loop がどこまで守れるか)なので、ユーザーの判断で別の spec に分けた。配信設計は、移行の手順で、リリース前から開いている PR に main を取り込ませて回避する。

## 方針(ユーザー承認済み)

maker と checker が使う skill と設定は、PR head の作業ツリーからではなく、リポジトリのデフォルトブランチから読む。

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
| 権限の設定(`.claude/settings.json`) | 作業ツリー(`--setting-sources project`)                           | `agent.sh:57`                                  |
| MCP の設定(`.mcp.json` など)        | 作業ツリー                                                        | `loop-execute/lib/mcp.sh:120-130`              |

PR を対象にするターゲット(pr-revise、ci-sweeper の PR ターゲット)では、作業ツリーは PR head である(`loop-detect/lib/detect.sh:356-359`、`ci-loop-agent.yaml:454-455`、`:474-475`)。そのため次の2つが起きる。

- PR が skill や権限の設定を書き換えると、その PR に対して書き込み権限付きで動くエージェントの指示と権限を、PR の作者が差し替えられる。
- [Loop 配信設計](2026-10-17-loop-delivery-plan-design.md)のリリース前から開いている PR では、PR head の旧い skill が、旧いプロンプトのキー(`may_edit`)を探す。新しいキー(`agent_edit_allowed`)を見つけられず、編集せずに REJECT で終わり得る(配信設計の第7-1節のプロンプトのキーの改名。配信設計は、移行の手順で、該当する PR に main を取り込ませて回避する)。

**新しい読み元:**

- maker の skill、checker の skill、権限の設定、MCP の設定は、デフォルトブランチから読む。イベントに関係なく同じにする。`pull_request_review_comment` では、ジョブの checkout が PR の merge commit になるので、デフォルトブランチを別に取得する。
- 例外は `workflow_dispatch` で、起動時に選んだ ref から読む。起動できるのは書き込み権限を持つ人だけで、作業ブランチの skill を dogfood で確かめる手段(配信設計の移行の節のリリース前の確認)になるためである。
- 作業ツリーの skill と設定は、エージェントに使わせない。エージェントが編集する対象のファイルとしては、これまでどおり作業ツリーにある。
- 読み元を変えても、エージェントの差分(commit)に、読み元から持ち込んだファイルが入ってはならない。

**対象にしないもの:** リポジトリの指示ファイル(`CLAUDE.md`、`AGENTS.md`、`.claude/rules/`)は、編集する対象のコードの規約であり、PR がその規約を変えることもある。この spec の初版では読み元を変えない(未決に記す)。

**挙動の変化(意図した変更):** skill や設定を書き換える PR に対して pr-revise や ci-sweeper が動くとき、PR の版ではなく、デフォルトブランチの版の skill と設定を使う。PR を対象にしない loop(作業ツリーがデフォルトブランチから作られる loop)では、読み元の内容は現在と同じである。

## ビルダーに任せること(切り出し時点の案)

- 第10節の読み元の切り替え方。条件は、エージェントの差分に持ち込んだファイルが入らないこと、4つのエンジン(claude、codex、copilot、cursor)のどれでも、作業ツリーの skill と設定が使われないことである。候補は次のとおり。
  - 作業ツリーの該当ディレクトリを、デフォルトブランチの内容で上書きし、commit の前に元に戻す(`git update-index --skip-worktree` か、commit の前の `git checkout -- <paths>`)。
  - エンジンが対応していれば、設定と skill の場所を CLI の引数か環境変数で指定し、作業ツリーの設定を読ませない(claude の `--setting-sources` と `--add-dir` など)。

## 設計者が決めたこと(切り出し時点)

- 第10節の読み元の例外を `workflow_dispatch` だけにし、`pull_request_review_comment` でもデフォルトブランチから読むこと。

## 未決

- 第10節: 各エンジンの CLI が、skill と設定を作業ディレクトリ以外から読めるか、作業ディレクトリの設定を無効にできるかは、確かめていない。実装の最初に、エンジンごとに確かめる。
- 第10節: リポジトリの指示ファイル(`CLAUDE.md`、`AGENTS.md`、`.claude/rules/`)の読み元。PR がエージェントの指示を差し替えられる点は skill と同じだが、編集する対象の規約でもあるため、本 spec では変えない。別に判断する。

## 第8回レビューで出た、未解決の指摘

設計を続けるときに、次を解決する。行番号は、配信設計の `5188cd2a` 時点のコードである。

- **作業ツリーを上書きして戻す案は、「持ち込んだファイルを commit に入れない」条件を満たせない。** commit は作業ツリーの `git add -A` で行う(`loop-execute/lib/agent.sh:150-160`)。パスの検査は commit 済みの差分だけを見る(`paths.sh:317-339`)。`harvest_workspace_into_worktree` は、`GITHUB_WORKSPACE` の変更を作業ツリーへ写す(`agent.sh:263-329`、`loop.sh:265`)。main にだけあるファイルは未追跡のまま commit に入り、PR head にだけあるファイルを上書きで消すと削除が commit に入る。PR が skill の source を正当に直して同期先を更新した場合、戻す方式では変更が消え、`skip-worktree` の方式では commit から隠れる。エージェントがディスク上で見るのも main の版になり、「編集する対象としては作業ツリーにある」と矛盾する。
- **`pull_request_review_comment` では、skill を差し替えても守れない。** このイベントでは、workflow ファイルが PR の merge commit から読まれる。dogfood の caller はローカルの reusable を呼ぶ(`on-loop-github-pr-revise.yaml:78`)ので、PR は caller の入力、pin、detect スクリプト(`.agents/skills/github-pr-revise/scripts/detect_pr_revise.sh`)、finalize の hook スクリプト(`loop-finalize/action.yml:219-234`)を書き換えられる。「detect スクリプトは信頼できる側」という記述は、このイベントでは誤り。このイベントでの保証の範囲を決める必要がある。
- **差し替える対象が claude に偏っている。** `.claude/settings.json` の hooks が実行するスクリプト(`.claude/hooks/`)、`.claude/agents/`、cursor の `.cursor/cli.json`(権限)・`.cursor/hooks.json`・`.cursor/agents/`・`.cursor/rules`、codex の設定、MCP の探索順(`.mcp.json` → `.cursor/mcp.json` → `.github/mcp.json`、`mcp.sh:126-129`)を、エンジンごとのパスの一覧として定義する。checker も作業ツリーで動く(`verifier.sh:226`、`:369`)ので、同じ扱いにする。
- **差し替えるパスを、どこで指定するか。** `.github/workflows/CLAUDE.md` の Portability は、reusable と composite に `.claude/` などのパスを書き込むことを禁じている。caller の新しい入力にする場合は、配信設計のアンチゴール(新しい設定値を増やさない)との関係を整理する。
- **base ブランチが main 以外のとき。** integration ターゲットが main 以外のブランチから作業ツリーを作る場合、デフォルトブランチから読むと、そのブランチの skill ではなく main の版を使う。dogfood はすべて `branch_match: main` なので影響しない。なお、レビューは `pull_request_target` が PR の base ブランチから workflow を読むと指摘したが、GitHub Docs は「the default branch of the base repository」と書いており、この点は誤りと判断した。
- **L1(`loop-agent-once`)の読み元。** `agent-l1` は ref なしで checkout し、`working_directory: "."` で動く(`ci-loop-agent.yaml:295-299`、`loop-agent-once/action.yml:49-52`)。現在の dogfood の L1(triage)には影響しない。
- **checker の skill の、作業ツリーへのフォールバック**(`verifier_skill.sh:36`)を、新しい方針でどう扱うか。
- **引用の訂正。** maker の CLI の作業ディレクトリを決めているのは `loop-execute/action.yml:203`。`mcp.sh:120-130` の探索は codex のときだけ動き(`mcp.sh:79-81`)、claude は `.mcp.json` を CLI 自身が読む。
