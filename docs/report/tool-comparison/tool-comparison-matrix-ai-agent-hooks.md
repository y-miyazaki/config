<!-- omit in toc -->
# Tool Comparison Matrix (AI Agent Hooks)

AI Agent Hooks のイベント体系・レスポンス形式・Stop 制御方式を横断比較する。

Agent Hooks の概要比較は [tool-comparison-matrix-ai-agent.md](tool-comparison-matrix-ai-agent.md#agent-hooks) を参照。本ドキュメントはイベント単位の詳細仕様に特化する。

<!-- omit in toc -->
## History

| 日付       | 内容                                                             |
| ---------- | ---------------------------------------------------------------- |
| 2026-06-14 | hooks.json 設定方法セクション追加。ツール並び順を A-Z 順に統一   |
| 2026-06-07 | 初版作成。Event Matrix / res Matrix / Stop Block仕様を整備 |

<!-- omit in toc -->
## Table of Contents

- [Event Matrix](#event-matrix)
  - [Guidelines](#guidelines)
- [hooks.json 設定方法](#hooksjson-設定方法)
  - [Copilot CLI](#copilot-cli)
  - [Cursor](#cursor)
  - [Claude Code](#claude-code)
  - [Kiro CLI](#kiro-cli)
  - [VS Code](#vs-code)
  - [Guidelines](#guidelines-1)
- [res Matrix (Stop / agentStop)](#res-matrix-stop--agentstop)
  - [Stop stdin / stdout Format](#stop-stdin--stdout-format)
    - [Antigravity](#antigravity)
    - [Claude Code](#claude-code-1)
    - [Copilot CLI](#copilot-cli-1)
    - [Kiro CLI](#kiro-cli-1)
    - [VS Code](#vs-code-1)
  - [Guidelines](#guidelines-2)
- [res Matrix (PostToolUse)](#res-matrix-posttooluse)
  - [PostToolUse stdin / stdout Format](#posttooluse-stdin--stdout-format)
    - [Antigravity](#antigravity-1)
    - [Claude Code](#claude-code-2)
    - [Copilot CLI](#copilot-cli-2)
    - [Kiro CLI](#kiro-cli-2)
    - [VS Code](#vs-code-2)
  - [Guidelines](#guidelines-3)
- [Stop Block Decision: 実装パターン](#stop-block-decision-実装パターン)
  - [設計方針](#設計方針)
  - [判定フロー](#判定フロー)
  - [Agent 判定の優先順位](#agent-判定の優先順位)
  - [Agent 別レスポンス仕様](#agent-別レスポンス仕様)
  - [制約事項](#制約事項)
- [必須評価軸 (MUST) 判定](#必須評価軸-must-判定)
- [.apm パッケージでの Hook イベント選定](#apm-パッケージでの-hook-イベント選定)
- [補足](#補足)

## Event Matrix

| イベント             | Antigravity           | Claude Code           | Copilot CLI           | Cursor                | Kiro CLI              | VS Code               |
| -------------------- | --------------------- | --------------------- | --------------------- | --------------------- | --------------------- | --------------------- |
| 提供元               | Google DeepMind       | Anthropic             | GitHub (Microsoft)    | Anysphere             | AWS                   | Microsoft (GitHub)    |
| ドキュメント         | [antigravity.google](https://antigravity.google/docs/hooks) | [docs.claude.com](https://docs.claude.com/en/docs/claude-code/hooks) | [docs.github.com](https://docs.github.com/en/copilot/reference/hooks-reference) | [cursor.com](https://docs.cursor.com/more/hooks) | [kiro.dev](https://kiro.dev/docs/cli/hooks/) | [code.visualstudio.com](https://code.visualstudio.com/docs/agent-customization/hooks) |
| Session Start        | ❌                     | ✅ SessionStart        | ✅ sessionStart        | ❌                     | ❌                     | ✅ SessionStart        |
| User Prompt Submit   | ❌                     | ✅ UserPromptSubmit    | ✅ userPromptSubmitted | ❌                     | ✅ userPromptSubmit    | ✅ UserPromptSubmit    |
| Pre Tool Use         | ✅ PreToolUse          | ✅ PreToolUse          | ✅ preToolUse          | ✅ beforeShellExecution | ✅ preToolUse          | ✅ PreToolUse          |
| Post Tool Use        | ✅ PostToolUse ※1     | ✅ PostToolUse         | ✅ postToolUse         | ✅ afterFileEdit        | ✅ postToolUse         | ✅ PostToolUse         |
| Post Tool Failure    | ❌ (PostToolUse の `err` で判別) | ✅ PostToolUseFailure  | ✅ postToolUseFailure  | ❌                     | ❌                     | ❌                     |
| Agent Spawn          | ❌                     | ✅ SubagentStart       | ✅ subagentStart       | ❌                     | ✅ agentSpawn          | ✅ SubagentStart       |
| Subagent Stop        | ❌                     | ✅ SubagentStop        | ✅ subagentStop        | ❌                     | ❌                     | ✅ SubagentStop        |
| Session End          | ❌                     | ✅ SessionEnd          | ✅ sessionEnd          | ❌                     | ❌                     | ❌                     |
| err Occurred       | ❌                     | ❌                     | ✅ errorOccurred       | ❌                     | ❌                     | ❌                     |
| Notification         | ❌                     | ✅ Notification        | ✅ notification        | ❌                     | ❌                     | ❌                     |
| Permission req   | ❌                     | ✅ PermissionRequest   | ✅ permissionRequest   | ❌                     | ❌                     | ❌                     |
| Compact (Pre/Post)   | ❌                     | ✅ PreCompact/PostCompact | ❌                  | ❌                     | ❌                     | ✅ PreCompact          |
| File Changed         | ❌                     | ✅ FileChanged         | ❌                     | ❌                     | ❌                     | ❌                     |
| Config Change        | ❌                     | ✅ ConfigChange        | ❌                     | ❌                     | ❌                     | ❌                     |
| Task Created/Completed | ❌                   | ✅ TaskCreated/Completed | ❌                  | ❌                     | ❌                     | ❌                     |
| Teammate Idle        | ❌                     | ✅ TeammateIdle        | ❌                     | ❌                     | ❌                     | ❌                     |

### Guidelines

**→ どのイベントが存在するかの比較。各イベントで何ができるかは res Matrix を参照。**

- Claude Code が最もイベント種別が豊富（20種以上）。細かいライフサイクル制御が可能
- Antigravity は PreInvocation / PostInvocation で Model 呼び出し前後へのステップ注入ポイントを持つ（他ツールにない独自イベント）
- Stop / PreToolUse / PostToolUse は全 6 ツールで存在し、互換 hook スクリプトの共通基盤になる
- VS Code は Claude Code と同じ PascalCase イベント名・`hookSpecificOutput` 形式を採用するが、GitHub Copilot CLI とは別実装。`.github/hooks/*.json` を共有するが stdin/stdout の JSON 構造が異なる
- Cursor は独自イベント名を使う。対応関係: `beforeShellExecution` / `beforeMCPExecution` / `beforeReadFile` = PreToolUse、`afterFileEdit` = PostToolUse、`stop` = Stop
- ※1: Antigravity の PostToolUse は観測専用。stdout は `{}` のみ。agent へのフィードバックには PreInvocation を使用する

## hooks.json 設定方法

各ツールで hooks を登録する設定ファイルの形式を示す。イベント名・キー名・構造がツールごとに異なるため、同一パッケージから複数ツール向けに配布する場合はターゲット別に定義ファイルを分離する必要がある。

### Copilot CLI

設定ファイル: `.github/hooks/<name>.json`（1 ファイル = 1 hook 定義。複数ファイルを配置可能）

```json
{
  "hooks": {
    "agentStop": [
      {
        "type": "command",
        "bash": ".github/hooks/scripts/actionlint.sh",
        "timeoutSec": 60
      }
    ],
    "preToolUse": [
      {
        "type": "command",
        "bash": "command -v lean-ctx >/dev/null 2>&1 || exit 0; lean-ctx hook rewrite",
        "timeoutSec": 15
      }
    ]
  },
  "version": 1
}
```

| 項目 | 値 |
| ---- | --- |
| イベント名 | camelCase (`agentStop`, `preToolUse`, `postToolUse`) |
| コマンドキー | `bash` |
| `type` フィールド | `"command"` (必須) |
| `version` | `1` (トップレベル、必須) |
| タイムアウト | `timeoutSec` (秒) |

### Cursor

設定ファイル: `.cursor/hooks.json`（単一ファイルに全 hook をマージ）

```json
{
  "version": 1,
  "hooks": {
    "stop": [
      {
        "command": ".cursor/hooks/scripts/actionlint.sh",
        "timeoutSec": 60
      }
    ],
    "preToolUse": [
      {
        "command": "command -v lean-ctx >/dev/null 2>&1 || exit 0; lean-ctx hook rewrite",
        "timeoutSec": 15
      }
    ]
  }
}
```

| 項目 | 値 |
| ---- | --- |
| イベント名 | camelCase (`stop`, `preToolUse`, `postToolUse`, `afterFileEdit`, `beforeShellExecution`) |
| コマンドキー | `command` (`bash` はエラー) |
| `type` フィールド | 不要 |
| `version` | `1` (トップレベル、必須。省略するとエラー) |
| タイムアウト | `timeoutSec` (秒) |

### Claude Code

設定ファイル: `.claude/settings.json` 内の `hooks` キー、または `.claude/hooks/<name>.json`

```json
{
  "hooks": {
    "Stop": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "./scripts/actionlint.sh",
            "timeout": 60
          }
        ]
      }
    ],
    "PreToolUse": [
      {
        "matcher": "Bash|Write",
        "hooks": [
          {
            "type": "command",
            "command": "lean-ctx hook rewrite",
            "timeout": 15
          }
        ]
      }
    ]
  }
}
```

| 項目 | 値 |
| ---- | --- |
| イベント名 | PascalCase (`Stop`, `PreToolUse`, `PostToolUse`) |
| コマンドキー | `command` |
| `type` フィールド | `"command"` (必須) |
| `version` | 不要 |
| タイムアウト | `timeout` (秒。`timeoutSec` ではない) |
| `matcher` | ツール名正規表現フィルタ (空文字 = 全マッチ) |
| ネスト構造 | イベント配列 → `{ matcher, hooks: [...] }` の 2 段ネスト |

### Kiro CLI

設定ファイル: `.kiro/hooks/hooks.json` または `.kiro/hooks/<name>.json`

```json
{
  "hooks": {
    "stop": [
      {
        "type": "command",
        "command": "./scripts/actionlint.sh",
        "timeout": 60
      }
    ],
    "preToolUse": [
      {
        "type": "command",
        "command": "lean-ctx hook rewrite",
        "timeout": 15
      }
    ]
  }
}
```

| 項目 | 値 |
| ---- | --- |
| イベント名 | camelCase (`stop`, `preToolUse`, `postToolUse`) |
| コマンドキー | `command` |
| `type` フィールド | `"command"` (必須) |
| `version` | 不要 |
| タイムアウト | `timeout` (秒) |

### VS Code

設定ファイル: `.github/hooks/<name>.json`（Copilot CLI と同じディレクトリを共有）

```json
{
  "hooks": {
    "Stop": [
      {
        "type": "command",
        "bash": ".github/hooks/scripts/actionlint.sh",
        "timeoutSec": 60
      }
    ],
    "PreToolUse": [
      {
        "type": "command",
        "bash": "lean-ctx hook rewrite",
        "timeoutSec": 15
      }
    ]
  },
  "version": 1
}
```

| 項目 | 値 |
| ---- | --- |
| イベント名 | PascalCase (`Stop`, `PreToolUse`, `PostToolUse`) |
| コマンドキー | `bash` |
| `type` フィールド | `"command"` (必須) |
| `version` | `1` (トップレベル、必須) |
| タイムアウト | `timeoutSec` (秒) |
| `.github/hooks/` 共有 | Copilot CLI と同一ディレクトリだがイベント名が異なる。両方のイベントを同一 JSON に記載すると両方で動作する |

### Guidelines

**→ hooks.json のフォーマットはツール間で互換性がない。ターゲット別に定義を分離する。**

| 差異ポイント | Copilot CLI | Cursor | Claude Code | Kiro CLI | VS Code |
| ------------ | ----------- | ------ | ----------- | -------- | ------- |
| コマンドキー | `bash` | `command` | `command` | `command` | `bash` |
| Stop イベント名 | `agentStop` | `stop` | `Stop` | `stop` | `Stop` |
| `version` 必須 | ✅ | ✅ | ❌ | ❌ | ✅ |
| タイムアウトキー | `timeoutSec` | `timeoutSec` | `timeout` | `timeout` | `timeoutSec` |
| matcher 対応 | ❌ | ❌ | ✅ | ❌ | ❌ |

- APM パッケージでの配布時、hooks JSON はターゲット別パッケージに分離する（例: `common-hooks-copilot`, `common-hooks-cursor`）
- APM は `target` フィールドによるフィルタリングを行わないため、Copilot 用イベントが Cursor の hooks.json に混入する。各 IDE は unknown event を無視するため実害はないが、ノイズになる
- Cursor は `version: 1` がないとエラーになる。APM の hooks.json 生成は `version` を付与しないため、ポストインストールスクリプトで注入する必要がある

## res Matrix (Stop / agentStop)

| 項目                     | Antigravity              | Claude Code                    | Copilot CLI                  | Cursor          | Kiro CLI              | VS Code                      |
| ------------------------ | ------------------------ | ------------------------------ | ---------------------------- | --------------- | --------------------- | ---------------------------- |
| イベント名               | `Stop`                   | `Stop`                         | `agentStop` / `Stop`         | `stop`          | `stop`                    | `Stop`                       |
| Block 方式 (推奨)        | exit 0 + JSON            | exit 2 (stderr) **または** exit 0 + JSON | exit 0 + JSON                | exit 2 のみ     | exit 0 + JSON             | exit 0 + JSON (hookSpecificOutput) |
| Block JSON               | `{"decision":"continue",`<br>`"reason":"..."}` | `{"decision":"block",`<br>`"reason":"..."}` | `{"decision":"block",`<br>`"reason":"..."}` | N/A             | `{"decision":"block",`<br>`"reason":"..."}` | `{"hookSpecificOutput":`<br>`{"hookEventName":"Stop",`<br>`"decision":"block",`<br>`"reason":"..."}}` |
| exit 2 の効果            | hook 自体の失敗として扱われる（agent フィードバックなし） | agent 停止を防止 + stderr が agent へ | ユーザーに警告表示のみ       | agent 停止を防止 | ユーザーに警告表示のみ    | agent に err ctx として注入 |
| exit 0 (JSON無し) の効果 | agent 通常停止           | agent 通常停止                 | agent 通常停止               | 何もしない (処理完了)  | agent 通常停止            | agent 通常停止               |
| reason の扱い            | system msg として会話に注入 | agent のコンテキストに追加 | 新しいプロンプトとして agent に送信 | stderr が agent へ | 新しいユーザーメッセージとして agent に送信 | agent のコンテキストに追加 |
| **ユーザーへの表示**     | ❌ (表示なし)             | ❌ (表示なし)                   | ❌ (表示なし)                 | ✅ (stderr 表示) | ❌ (表示なし)              | ❌ (表示なし)                 |
| **agent コンテキスト注入** | ✅ reason がコンテキストに入る | ✅ reason がコンテキストに入る | ✅ reason がコンテキストに入る | ✅ stderr がコンテキストに入る | ✅ reason がコンテキストに入る | ✅ reason がコンテキストに入る |
| **agent が修正アクションを実行** | ✅ 次ターンで reason に基づき行動 | ✅ 次ターンで reason に基づき行動 | ✅ 次ターンで reason に基づき行動 | ✅ 次ターンで修正行動 | ✅ 次ターンで reason に基づき行動 | ✅ 次ターンで reason に基づき行動 |
| 連続ブロック上限         | 不明                     | 8 回                           | ジョブタイムアウトに依存     | 不明            | 不明                      | 不明 (AI credits 消費で自然制限) |
| JSON 生成要件            | 有効な JSON 必須          | 有効な JSON 必須               | 有効な JSON 必須             | N/A             | 有効な JSON 必須 (jq 推奨) | 有効な JSON 必須             |

### Stop stdin / stdout Format

#### Antigravity

stdin:

```json
{"executionNum": 5, "terminationReason": "task_complete", "error": null, "fullyIdle": true, "conversationId": "...", "workspacePaths": ["/workspace"]}
```

stdout:

```json
{"decision": "continue", "reason": "修正すべき内容"}
```

#### Claude Code

stdin:

```json
{"hook_event_name": "Stop", "session_id": "...", "cwd": "/workspace", "transcript_path": "...", "stop_hook_active": false, "last_assistant_message": "..."}
```

stdout — block decision:

```json
{"decision": "block", "reason": "修正すべき内容"}
```

stdout — additionalContext (非エラーフィードバック):

```json
{
  "hookSpecificOutput": {
    "hookEventName": "Stop",
    "additionalContext": "テスト実行してから完了してください"
  }
}
```

#### Copilot CLI

stdin:

```json
{"hook_event_name": "agentStop", "session_id": "...", "cwd": "/workspace", "transcriptPath": "...", "stopReason": "..."}
```

stdout:

```json
{"decision": "block", "reason": "修正すべき内容"}
```

#### Kiro CLI

stdin:

```json
{"hook_event_name": "stop", "session_id": "...", "cwd": "/workspace", "assistant_response": "..."}
```

stdout:

```json
{"decision": "block", "reason": "修正すべき内容"}
```

#### VS Code

stdin:

```json
{"hook_event_name": "Stop", "session_id": "...", "cwd": "/workspace", "transcript_path": "...", "stop_hook_active": false}
```

stdout:

```json
{
  "hookSpecificOutput": {
    "hookEventName": "Stop",
    "decision": "block",
    "reason": "修正すべき内容"
  }
}
```

### Guidelines

**→ Stop hook は全 6 ツールで agent に修正を強制できる唯一のイベント。lint/test ゲートの第一選択。**

- 全ツールで reason が agent のコンテキストに入り、次ターンで agent が修正アクションを実行する
- Kiro CLI / Copilot CLI は exit 0 + JSON が唯一のブロック手段。exit 2 では警告表示のみで修正ループに入らない
- Claude Code は exit 2 でも stderr が agent に届くため修正ループに入る。JSON 方式も併用可能
- Antigravity は `"continue"` を使う。stdin に `terminationReason` があることで検出する
- Cursor は JSON block decision を解釈しない。exit 2 + stderr が唯一の手段
- JSON は `jq -n --arg` で生成し、改行文字のエスケープを保証する

## res Matrix (PostToolUse)

| 項目                       | Antigravity              | Claude Code                                 | Copilot CLI                      | Cursor          | Kiro CLI    | VS Code                     |
| -------------------------- | ------------------------ | ------------------------------------------- | -------------------------------- | --------------- | ----------- | --------------------------- |
| イベント名                 | `PostToolUse`            | `PostToolUse`                               | `postToolUse`                    | `afterFileEdit` | `postToolUse`   | `PostToolUse`               |
| exit 0 + stdout の効果     | 出力は `{}` のみ (処理なし) | JSON output 処理                       | STDOUT captured (非表示)         | 不明            | STDOUT captured (非表示) | JSON output 処理            |
| exit 2 の効果              | 不明                     | STDERR を Claude に表示 (ツール実行済み) | STDERR をユーザーに警告          | agent にフィードバック | STDERR をユーザーに警告 | agent に err ctx として注入 |
| exit code で block 可能か  | ❌ (ツール実行済み)       | ❌ (ツール実行済み)                          | ❌ (ツール実行済み)               | ❌               | ❌               | ✅ `decision: "block"` で停止可 |
| **ユーザーへの表示**       | ❌                        | ❌ (表示なし)                           | ⚠️ exit 2 時のみ警告表示         | 不明            | ⚠️ exit 2 時のみ警告表示 | ❌ (表示なし)               |
| **agent コンテキスト注入** | ❌ (出力不可)             | ✅ additionalContext で注入                  | ✅ additionalContext で注入       | ✅ agent に渡る   | ❌               | ✅ `hookSpecificOutput.additionalContext` で注入 |
| **agent が修正アクションを実行** | ❌ (PostToolUse 単体では不可。Stop で対応) | ✅ 次ツール呼出し時に認識して対応 | ✅ 次ツール呼出し時に認識して対応 | ✅ 次ターンで対応 | ❌ (フィードバック手段なし) | ✅ additionalContext / block で対応 |
| matcher (ツール名フィルタ) | ✅ (正規表現対応) | ✅ (`"Edit\|Write"` 等)                       | ❌ (全ツール)                     | ❌ (ファイル編集のみ) | ❌ (全ツール)    | ❌ (全ツール)               |

### PostToolUse stdin / stdout Format

#### Antigravity

stdin:

```json
{"toolCall": {"name": "editFile", "args": {"path": "src/main.go"}}, "result": "...", "error": null}
```

stdout: `{}` のみ（観測専用）。agent へのフィードバックには PreInvocation の `injectSteps` を使用:

```json
{
  "injectSteps": [
    {"ephemeralMessage": "lint結果: エラー3件。修正してください。"}
  ]
}
```

#### Claude Code

stdin:

```json
{"hook_event_name": "PostToolUse", "session_id": "...", "cwd": "/workspace", "tool_name": "Edit", "tool_input": {"file_path": "src/main.go"}, "tool_result": "..."}
```

stdout — additionalContext:

```json
{
  "hookSpecificOutput": {
    "hookEventName": "PostToolUse",
    "additionalContext": "lint結果: エラー3件"
  }
}
```

stdout — updatedToolOutput (結果置換):

```json
{
  "hookSpecificOutput": {
    "hookEventName": "PostToolUse",
    "updatedToolOutput": {
      "stdout": "[redacted]",
      "stderr": "",
      "interrupted": false,
      "isImage": false
    }
  }
}
```

#### Copilot CLI

stdin:

```json
{"hook_event_name": "postToolUse", "session_id": "...", "cwd": "/workspace", "toolName": "editFiles", "toolResult": "..."}
```

stdout:

```json
{
  "modifiedResult": {
    "resultType": "success",
    "textResultForLlm": "置換後のツール結果"
  },
  "additionalContext": "agent に伝えたい追加情報"
}
```

#### Kiro CLI

stdin:

```json
{"hook_event_name": "postToolUse", "session_id": "...", "cwd": "/workspace", "tool_name": "editFiles", "tool_input": {"files": ["src/main.go"]}}
```

stdout: N/A（フィードバック手段なし。exit 2 + stderr はユーザー警告のみ）

#### VS Code

stdin:

```json
{"hook_event_name": "PostToolUse", "session_id": "...", "cwd": "/workspace", "tool_name": "editFiles", "tool_input": {"files": ["src/main.go"]}, "tool_use_id": "tool-123", "tool_response": "File edited successfully"}
```

stdout — block + additionalContext:

```json
{
  "decision": "block",
  "reason": "Post-processing validation failed",
  "hookSpecificOutput": {
    "hookEventName": "PostToolUse",
    "additionalContext": "lint エラーを修正してください"
  }
}
```

stdout — additionalContext のみ:

```json
{
  "hookSpecificOutput": {
    "hookEventName": "PostToolUse",
    "additionalContext": "lint結果: エラー3件"
  }
}
```

### Guidelines

**→ PostToolUse は agent にフィードバックを渡せるツールが限定的。修正を強制するなら Stop hook を使う。**

- Claude Code / Copilot CLI / VS Code は `additionalContext` で agent のコンテキストに注入し、agent が認識して対応可能
- VS Code は PostToolUse でも `decision: "block"` による停止が可能（他ツールにない独自機能）
- Kiro CLI / Antigravity は PostToolUse で agent にフィードバックを渡す手段がない
- Antigravity は PreInvocation の `injectSteps` で補完する設計
- フォーマッタのように「hook 内で修正して終わり」の処理は PostToolUse で十分（agent の行動不要）
- agent に修正を依頼する場合は Stop hook を使うのが全ツール互換

## Stop Block Decision: 実装パターン

`report_failure` 関数を各 hook スクリプトに埋め込み、reason を渡すだけで全 agent に適切なレスポンスを返す。

### 設計方針

1. **stdin キャプチャ**: スクリプト冒頭で stdin を 1 回だけ読み取る（パイプは 2 回読めない）
2. **Agent 判定**: stdin の JSON 構造と環境変数から Agent を特定する（Agent ファースト戦略）
3. **hook_event 取得**: Agent ごとに異なるフィールド名・ケーシングで取得する
4. **res 構築**: Agent と hook_event の組み合わせに応じた JSON を stdout に出力する

### 判定フロー

### Agent 判定の優先順位

| 優先度 | 判定条件 | Agent |
| ------ | -------- | ----- |
| 1 | `terminationReason` / `toolCall` フィールドあり | Antigravity |
| 2 | `stop_hook_active` / `tool_use_id` フィールドが存在する (`has()` で判定。値が `false` でも検出) | VS Code |
| 3 | `GITHUB_COPILOT_API_TOKEN` 環境変数あり、または `transcriptPath` / `stopReason` / `toolResult` 等の Copilot CLI 固有フィールドあり (`transcript_path` は VS Code と共通のため除外) | Copilot CLI |
| 4 | `hook_event_name` が camelCase の既知値 (`stop`, `postToolUse` 等) | Kiro CLI |
| 5 | `hook_event_name` が PascalCase (上記で Copilot 除外済み) | Claude Code |
| 6 | stdin 無し / 判定不可 | Cursor / fallback |

### Agent 別レスポンス仕様

| Agent | Stop イベント時の stdout | PostToolUse 時の stdout | fallback |
| ----- | ------------------------ | ----------------------- | -------- |
| Antigravity | `{"decision":"continue",`<br>`"reason":"..."}` + exit 0 | N/A (出力 `{}` のみ) | exit 0 |
| Claude Code | `{"decision":"block",`<br>`"reason":"..."}` + exit 0 | `{"hookSpecificOutput":`<br>`{"hookEventName":"PostToolUse",`<br>`"additionalContext":"..."}}` + exit 0 | exit 2 |
| Copilot CLI | `{"decision":"block",`<br>`"reason":"..."}` + exit 0 | `{"additionalContext":"..."}` + exit 0 | exit 2 |
| Kiro CLI | `{"decision":"block",`<br>`"reason":"..."}` + exit 0 | exit 2 + stderr<br>(agent に届かない) | exit 2 |
| VS Code | `{"hookSpecificOutput":`<br>`{"hookEventName":"Stop",`<br>`"decision":"block",`<br>`"reason":"..."}}` + exit 0 | `{"decision":"block",`<br>`"reason":"...",`<br>`"hookSpecificOutput":`<br>`{"hookEventName":"PostToolUse",`<br>`"additionalContext":"..."}}` + exit 0 | exit 2 |
| Cursor / unknown | exit 2 + stderr | exit 2 + stderr | exit 2 |

### 制約事項

- `jq` は有効な JSON 生成に必須。hook スクリプトの依存コマンドとして扱う
- apm 配布ではライブラリの自動コピーが非対応のため、関数はスクリプト本体に埋め込む
- 実装例は `.apm/packages/*/.apm/hooks/scripts/*.sh` を参照。仕様の正は本ドキュメントと各 Agent の公式仕様とする
- 無限ループ対策: Claude Code は 8 回で自動停止するが、Kiro CLI / Copilot CLI / Antigravity は上限が不明。スクリプト側で環境変数や一時ファイルを用いた最大試行回数（例: カウンター制限）のセーフガード実装を推奨する

## 必須評価軸 (MUST) 判定

| 評価軸          | Antigravity | Claude Code | Copilot CLI | Cursor | Kiro CLI | VS Code |
| --------------- | ----------- | ----------- | ----------- | ------ | -------- | ------- |
| Problem Fit     | 3           | 3           | 3           | 2      | 3        | 3       |
| Security        | 3           | 3           | 3           | 2      | 2        | 3       |
| op Model | 3           | 3           | 3           | 2      | 3        | 3       |
| Integration     | 3           | 3           | 3           | 2      | 2        | 3       |
| Cost/TCO        | 3           | 3           | 3           | 3      | 3        | 3       |
| Maintainability | 2           | 3           | 2           | 2      | 2        | 3       |
| **加重平均**    | **2.8**     | **3.0**     | **2.8**     | **2.2** | **2.5** | **3.0** |

- Claude Code: イベント種別最多、decision control 最も柔軟、`additionalContext` 活用可。全評価軸で最高
- VS Code: Claude Code 互換の `hookSpecificOutput` 形式を採用。PostToolUse でも block 可能な唯一のツール。`.github/hooks/` からの設定読み込みで Claude Code 設定と共存可
- Antigravity: PreInvocation で `injectSteps` により ephemeralMessage 注入可能。Stop で `"continue"` による修正ループ構築可能。PostToolUse は観測専用
- Copilot CLI: Claude Code に次ぐイベント数。JSON block decision 対応で Stop ループ構築可能
- Kiro CLI: Stop hook の JSON block 対応で修正ループ構築可能。イベント種別は少ないが実用上十分
- Cursor: JSON block decision 非対応。独自イベント名で互換性が低い。条件付き採用

## .apm パッケージでの Hook イベント選定

| 観点 | PostToolUse | Stop |
| ---- | ----------- | ---- |
| agent が修正アクションを実行するか | Claude Code / Copilot CLI のみ | ✅ 全ツール |
| Kiro CLI で agent にフィードバックが届くか | ❌ | ✅ |
| Antigravity で agent にフィードバックが届くか | ❌ | ✅ |
| 全ツール互換でスクリプト 1 本で動くか | ❌ (ツール間で出力形式が異なる) | ✅ (decision + reason で統一可) |
| 実行タイミング | ツール実行直後（即時） | ターン完了時（まとめて） |
| 適したユースケース | 自動フォーマット（agent 行動不要） | lint/test エラーの修正ループ |

**→ .apm パッケージでは Stop hook を採用する。**

- lint/test のエラーを検知して agent に修正させるユースケースでは、Stop が唯一の全ツール互換手段
- PostToolUse は Kiro CLI / Antigravity で agent にフィードバックが届かないため、修正ループに使えない
- `report_failure` 関数で stdin の `hook_event_name` / `terminationReason` を判別し、全 agent に適切な JSON を返す設計とする

## 補足

- VS Code の hooks 仕様は [code.visualstudio.com/docs/agent-customization/hooks](https://code.visualstudio.com/docs/agent-customization/hooks) に基づく。GitHub Copilot CLI とは別実装であり、同じ `.github/hooks/` ディレクトリを使用するが stdin/stdout の JSON 構造が異なる点に注意
- Cursor の hooks 仕様は公式ドキュメントの情報が限定的であり、変更される可能性がある
- Antigravity の hooks 仕様は [antigravity.google/docs/hooks](https://antigravity.google/docs/hooks) の正式仕様に基づく。旧 Gemini CLI ([geminicli.com](https://geminicli.com/docs/hooks/reference/)) とはイベント名・JSON形式が異なるため注意
- Antigravity の PostToolUse は観測専用（出力 `{}` のみ）。agent へのフィードバックには PreInvocation の `injectSteps` または Stop の `{"decision":"continue","reason":"..."}` を使用する
- 各ツールの hooks 仕様 URL は変更される可能性があるため、定期的に確認する
