<!-- omit in toc -->
# Tool Comparison Matrix (AI Agent Hooks)

AI Agent Hooks のイベント体系・レスポンス形式・Stop 制御方式を横断比較する。

Agent Hooks の概要比較は [tool-comparison-matrix-ai-agent.md](tool-comparison-matrix-ai-agent.md#agent-hooks) を参照。本ドキュメントはイベント単位の詳細仕様に特化する。

## History

| 日付       | 内容                                                             |
| ---------- | ---------------------------------------------------------------- |
| 2026-06-07 | 初版作成。Event Matrix / Response Matrix / Stop Block仕様を整備 |

<!-- omit in toc -->
## Table of Contents

- [History](#history)
- [Event Matrix](#event-matrix)
  - [Guidelines](#guidelines)
- [Response Matrix (Stop / agentStop)](#response-matrix-stop--agentstop)
  - [Guidelines](#guidelines-1)
- [Response Matrix (PostToolUse)](#response-matrix-posttooluse)
  - [Guidelines](#guidelines-2)
- [Stop Block Decision: 実装パターン](#stop-block-decision-実装パターン)
  - [Guidelines](#guidelines-3)
- [必須評価軸 (MUST) 判定](#必須評価軸-must-判定)
- [補足](#補足)

## Event Matrix

| イベント             | Kiro              | Claude Code           | GitHub Copilot        | Cursor                | Antigravity           |
| -------------------- | --------------------- | --------------------- | --------------------- | --------------------- | --------------------- |
| 提供元               | AWS                   | Anthropic             | GitHub (Microsoft)    | Anysphere             | Google DeepMind       |
| ドキュメント         | [kiro.dev](https://kiro.dev/docs/cli/hooks/) | [docs.claude.com](https://docs.claude.com/en/docs/claude-code/hooks) | [docs.github.com](https://docs.github.com/en/copilot/reference/hooks-reference) | [cursor.com](https://docs.cursor.com/more/hooks) | [geminicli.com](https://geminicli.com/docs/hooks/reference/) |
| Session Start        | ❌                     | ✅ SessionStart        | ✅ sessionStart        | ❌                     | ✅ SessionStart        |
| User Prompt Submit   | ✅ userPromptSubmit    | ✅ UserPromptSubmit    | ✅ userPromptSubmitted | ❌                     | ✅ BeforeAgent         |
| Pre Tool Use         | ✅ preToolUse          | ✅ PreToolUse          | ✅ preToolUse          | ✅ (beforeShellExecution等) | ✅ BeforeTool     |
| Post Tool Use        | ✅ postToolUse         | ✅ PostToolUse         | ✅ postToolUse         | ✅ afterFileEdit        | ✅ AfterTool          |
| Post Tool Failure    | ❌                     | ✅ PostToolUseFailure  | ✅ postToolUseFailure  | ❌                     | ❌                     |
| Agent Stop           | ✅ stop                | ✅ Stop                | ✅ agentStop           | ✅ stop                 | ✅ AfterAgent          |
| Agent Spawn          | ✅ agentSpawn          | ✅ SubagentStart       | ✅ subagentStart       | ❌                     | ❌                     |
| Subagent Stop        | ❌                     | ✅ SubagentStop        | ✅ subagentStop        | ❌                     | ❌                     |
| Session End          | ❌                     | ✅ SessionEnd          | ✅ sessionEnd          | ❌                     | ✅ SessionEnd          |
| Error Occurred       | ❌                     | ❌                     | ✅ errorOccurred       | ❌                     | ❌                     |
| Notification         | ❌                     | ✅ Notification        | ✅ notification        | ❌                     | ✅ Notification        |
| Permission Request   | ❌                     | ✅ PermissionRequest   | ✅ permissionRequest   | ❌                     | ❌                     |
| Compact (Pre/Post)   | ❌                     | ✅ PreCompact/PostCompact | ❌                  | ❌                     | ✅ PreCompress         |
| Before Model         | ❌                     | ❌                     | ❌                     | ❌                     | ✅ BeforeModel         |
| After Model          | ❌                     | ❌                     | ❌                     | ❌                     | ✅ AfterModel          |
| Before Tool Selection | ❌                    | ❌                     | ❌                     | ❌                     | ✅ BeforeToolSelection |
| File Changed         | ❌                     | ✅ FileChanged         | ❌                     | ❌                     | ❌                     |
| Config Change        | ❌                     | ✅ ConfigChange        | ❌                     | ❌                     | ❌                     |
| Task Created/Completed | ❌                   | ✅ TaskCreated/Completed | ❌                  | ❌                     | ❌                     |
| Teammate Idle        | ❌                     | ✅ TeammateIdle        | ❌                     | ❌                     | ❌                     |

### Guidelines

**→ Claude Code が最もイベント種別が豊富。Antigravity は Model hooks (BeforeModel/AfterModel/BeforeToolSelection) を独自に持ち、LLM リクエスト自体を制御可能。**

- Stop hook は全 5 ツールでサポートされ、lint/test による修正ループの起点になる
- Antigravity の AfterAgent が他ツールの Stop に相当する。`decision: "deny"` + `reason` でリトライを強制する
- Antigravity は BeforeModel/AfterModel でモデルリクエスト・レスポンスの直接改変が可能（他ツールにない独自機能）
- PreToolUse / BeforeTool は破壊的コマンドのブロックに全ツールで活用可能
- PostToolUse / AfterTool はフォーマッタ/リンター自動実行に全ツールで活用可能
- Cursor は独自イベント名を使い、他 4 ツールと互換性が低い

## Response Matrix (Stop / agentStop)

| 項目                     | Kiro                  | Claude Code                    | GitHub Copilot               | Cursor          | Antigravity              |
| ------------------------ | ------------------------- | ------------------------------ | ---------------------------- | --------------- | ------------------------ |
| イベント名               | `stop`                    | `Stop`                         | `agentStop` / `Stop`         | `stop`          | `AfterAgent`             |
| Block 方式 (推奨)        | exit 0 + JSON             | exit 2 (stderr) **または** exit 0 + JSON | exit 0 + JSON                | exit 2 のみ     | exit 0 + JSON **または** exit 2 |
| Block JSON               | `{"decision":"block","reason":"..."}` | `{"decision":"block","reason":"..."}` | `{"decision":"block","reason":"..."}` | N/A             | `{"decision":"deny","reason":"..."}` |
| exit 2 の効果            | ユーザーに警告表示のみ    | agent 停止を防止 + stderr が agent へ | ユーザーに警告表示のみ       | agent 停止を防止 | リトライ強制 + stderr が agent へ |
| exit 0 (JSON無し) の効果 | agent 通常停止            | agent 通常停止                 | agent 通常停止               | agent 通常停止  | agent 通常停止           |
| reason の扱い            | 新しいユーザーメッセージとして agent に送信 | agent のコンテキストに追加 | 新しいプロンプトとして agent に送信 | stderr が agent へ | agent へ新しいプロンプトとして送信（リトライ） |
| additionalContext        | ❌                         | ✅ `hookSpecificOutput.additionalContext` | ❌                           | ❌               | ❌                        |
| clearContext             | ❌                         | ❌                              | ❌                            | ❌               | ✅ `hookSpecificOutput.clearContext` |
| stdin (入力)             | JSON (`hook_event_name`, `session_id`, `cwd`, `assistant_response`) | JSON (`hook_event_name`, `session_id`, `cwd`, `transcript_path`, `stop_hook_active`, `last_assistant_message`) | JSON (`hook_event_name`, `session_id`, `cwd`, `transcriptPath`, `stopReason`) | なし | JSON (`hook_event_name`, `session_id`, `cwd`, `prompt`, `prompt_response`, `stop_hook_active`) |
| 連続ブロック上限         | 不明                      | 8 回                           | ジョブタイムアウトに依存     | 不明            | 不明                     |
| JSON 生成要件            | 有効な JSON 必須 (jq 推奨) | 有効な JSON 必須               | 有効な JSON 必須             | N/A             | 有効な JSON 必須          |

### Guidelines

**→ 互換スクリプトを書くには stdin の `hook_event_name` で分岐し、Stop 系なら JSON、それ以外なら exit 2 を返す。**

- Kiro / GitHub Copilot は exit 0 + JSON が唯一のブロック手段。exit 2 では agent は止まるが修正ループに入らない
- Claude Code は exit 2 でも stderr が agent に届くため修正ループに入る。JSON 方式も併用可能
- Antigravity は exit 2 でリトライ強制（stderr が agent へ）。JSON `{"decision":"deny","reason":"..."}` でも同等。`"deny"` を使う点が他と異なる
- Cursor は JSON block decision を解釈しない。exit 2 + stderr が唯一の手段
- JSON は `jq -n --arg reason "$reason" '{"decision":"block","reason":$reason}'` で生成し、改行文字のエスケープを保証する
- Antigravity のみ `"block"` ではなく `"deny"` を使う。互換スクリプトでは hook_event_name で分岐する

## Response Matrix (PostToolUse)

| 項目                       | Kiro        | Claude Code                                 | GitHub Copilot                   | Cursor          | Antigravity              |
| -------------------------- | --------------- | ------------------------------------------- | -------------------------------- | --------------- | ------------------------ |
| イベント名                 | `postToolUse`   | `PostToolUse`                               | `postToolUse`                    | `afterFileEdit` | `AfterTool`              |
| exit 0 + stdout の効果     | STDOUT captured (非表示) | JSON output 処理                       | STDOUT captured (非表示)         | 不明            | JSON output 処理          |
| exit 2 の効果              | STDERR をユーザーに警告 | STDERR を Claude に表示 (ツール実行済み) | STDERR をユーザーに警告          | agent にフィードバック | ツール結果を隠蔽 + stderr を代替結果として agent へ |
| exit code で block 可能か  | ❌               | ❌ (ツール実行済み)                          | ❌ (ツール実行済み)               | ❌               | ⚠️ 結果の隠蔽のみ (実行は済み) |
| additionalContext          | ❌               | ✅ `hookSpecificOutput.additionalContext`    | ✅ `additionalContext`           | ❌               | ✅ `hookSpecificOutput.additionalContext` |
| modifiedResult / updatedToolOutput | ❌       | ✅ `hookSpecificOutput.updatedToolOutput`    | ✅ `modifiedResult`              | ❌               | ⚠️ `decision:"deny"` + `reason` で結果置換 |
| tailToolCallRequest        | ❌               | ❌                                           | ❌                                | ❌               | ✅ `hookSpecificOutput.tailToolCallRequest` |
| matcher (ツール名フィルタ) | ❌ (全ツール)    | ✅ (`"Edit\|Write"` 等)                       | ❌ (全ツール)                     | ❌ (ファイル編集のみ) | ✅ (正規表現対応) |

### Guidelines

**→ PostToolUse はツール実行済みのため block できない。Context 注入でフィードバックする。**

- Claude Code / GitHub Copilot / Antigravity は `additionalContext` で lint 結果等を agent のコンテキストに注入可能
- Antigravity は `tailToolCallRequest` で別ツールを即座にチェーン実行可能（他ツールにない独自機能）
- Antigravity は matcher に正規表現が使え、特定ツールだけにフックを限定しやすい
- Kiro / Cursor は PostToolUse での agent フィードバック手段が限定的。Stop hook で補完する
- フォーマッタのように「修正して終わり」の処理は PostToolUse で十分。agent に修正を依頼する場合は Stop hook を使う

## Stop Block Decision: 実装パターン

全 agent 互換の `report_failure` 関数パターン:

```bash
HOOK_STDIN_DATA=""
if [[ ! -t 0 ]]; then
    HOOK_STDIN_DATA=$(cat)
fi

function report_failure {
    local reason="$1"
    local hook_event=""

    if [[ -n "$HOOK_STDIN_DATA" ]]; then
        hook_event=$(echo "$HOOK_STDIN_DATA" | jq -r '.hook_event_name // .hookEventName // empty' 2> /dev/null || true)
    fi

    case "$hook_event" in
        Stop | stop | agentStop | SubagentStop)
            # Kiro / GitHub Copilot / Claude Code (JSON mode)
            jq -n --arg reason "$reason" '{"decision": "block", "reason": $reason}'
            exit 0
            ;;
        AfterAgent)
            # Antigravity: "deny" でリトライ強制
            jq -n --arg reason "$reason" '{"decision": "deny", "reason": $reason}'
            exit 0
            ;;
        *)
            # Claude Code (exit 2 mode) / Cursor / Antigravity (exit 2) / fallback
            echo "$reason" >&2
            exit 2
            ;;
    esac
}
```

| 条件                              | 出力                              | Exit Code |
| --------------------------------- | --------------------------------- | --------- |
| stdin に `Stop` / `stop` / `agentStop` | `{"decision":"block","reason":"..."}` stdout | 0         |
| stdin に `AfterAgent`             | `{"decision":"deny","reason":"..."}` stdout | 0         |
| stdin なし / その他イベント       | reason を stderr                  | 2         |

### Guidelines

**→ `report_failure` を各 hook スクリプトに埋め込み、reason だけ渡せば全 agent で動作する。**

- apm 配布ではライブラリの自動コピーが非対応のため、スクリプト本体に関数を埋め込む
- `jq` は有効な JSON 生成に必須。hook スクリプトの依存コマンドとして明記する
- stdin の読み取りはスクリプト冒頭で 1 回だけ行う（パイプは 2 回読めないため）
- Claude Code は Stop で exit 2 でも動作するが、JSON 方式に統一すると全ツール互換になる
- Antigravity は `"deny"` を使うため `AfterAgent` の分岐が必要。`"block"` は認識されない

## 必須評価軸 (MUST) 判定

| 評価軸          | Kiro | Claude Code | GitHub Copilot | Cursor | Antigravity |
| --------------- | -------- | ----------- | -------------- | ------ | ----------- |
| Problem Fit     | 3        | 3           | 3              | 2      | 3           |
| Security        | 2        | 3           | 3              | 2      | 3           |
| Operation Model | 3        | 3           | 3              | 2      | 3           |
| Integration     | 2        | 3           | 3              | 2      | 3           |
| Cost/TCO        | 3        | 3           | 3              | 3      | 3           |
| Maintainability | 2        | 3           | 2              | 2      | 2           |
| **加重平均**    | **2.5**  | **3.0**     | **2.8**        | **2.2** | **2.8**    |

- Claude Code: イベント種別最多、decision control 最も柔軟、`additionalContext` 活用可。全評価軸で最高
- Antigravity: Model hooks で LLM リクエスト自体を制御可能。AfterAgent でリトライ強制。BeforeToolSelection でツール制限も可能。Claude Code に次ぐ柔軟性
- GitHub Copilot: Claude Code に次ぐイベント数。JSON block decision 対応で Stop ループ構築可能
- Kiro: Stop hook の JSON block 対応で修正ループ構築可能。イベント種別は少ないが実用上十分
- Cursor: JSON block decision 非対応。独自イベント名で互換性が低い。条件付き採用

## 補足

- Cursor の hooks 仕様は公式ドキュメントの情報が限定的であり、変更される可能性がある
- Antigravity (旧 Gemini CLI) は 2026-06-18 に Gemini CLI から移行完了予定。hooks 仕様は Gemini CLI 時代から安定しており、設定パス (`~/.gemini/`) も互換性あり
- 各ツールの hooks 仕様 URL は変更される可能性があるため、定期的に確認する
