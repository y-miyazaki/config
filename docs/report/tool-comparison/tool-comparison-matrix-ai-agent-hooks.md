# Tool Comparison Matrix (AI Agent Hooks)

AI Agent Hooks のイベント体系・レスポンス形式・Stop 制御方式を横断比較する。

Agent Hooks の概要比較は [tool-comparison-matrix-ai-agent.md](tool-comparison-matrix-ai-agent.md#agent-hooks) を参照。本ドキュメントはイベント単位の詳細仕様に特化する。

## History

| 日付       | 内容                                                           |
| ---------- | -------------------------------------------------------------- |
| 2026-06-27 | Codex (OpenAI) を全セクションに追加                            |
| 2026-06-14 | hooks.json 設定方法セクション追加。ツール並び順を A-Z 順に統一 |
| 2026-06-07 | 初版作成。Event Matrix / res Matrix / Stop Block 仕様を整備    |

## Event Matrix

| イベント               | Antigravity                                                 | Claude Code                                                          | Codex                                                                          | Copilot CLI                                                                     | Cursor                                           | Kiro CLI                                     | VS Code                                                                               |
| ---------------------- | ----------------------------------------------------------- | -------------------------------------------------------------------- | ------------------------------------------------------------------------------ | ------------------------------------------------------------------------------- | ------------------------------------------------ | -------------------------------------------- | ------------------------------------------------------------------------------------- |
| 提供元                 | Google DeepMind                                             | Anthropic                                                            | OpenAI                                                                         | GitHub (Microsoft)                                                              | Anysphere                                        | AWS                                          | Microsoft (GitHub)                                                                    |
| ドキュメント           | [antigravity.google](https://antigravity.google/docs/hooks) | [docs.claude.com](https://docs.claude.com/en/docs/claude-code/hooks) | [developers.openai.com/codex/hooks](https://developers.openai.com/codex/hooks) | [docs.github.com](https://docs.github.com/en/copilot/reference/hooks-reference) | [cursor.com](https://docs.cursor.com/more/hooks) | [kiro.dev](https://kiro.dev/docs/cli/hooks/) | [code.visualstudio.com](https://code.visualstudio.com/docs/agent-customization/hooks) |
| Session Start          | ❌                                                          | ✅ SessionStart                                                      | ✅ SessionStart                                                                | ✅ sessionStart                                                                 | ❌                                               | ❌                                           | ✅ SessionStart                                                                       |
| User Prompt Submit     | ❌                                                          | ✅ UserPromptSubmit                                                  | ✅ UserPromptSubmit                                                            | ✅ userPromptSubmitted                                                          | ❌                                               | ✅ userPromptSubmit                          | ✅ UserPromptSubmit                                                                   |
| Pre Tool Use           | ✅ PreToolUse                                               | ✅ PreToolUse                                                        | ✅ PreToolUse                                                                  | ✅ preToolUse                                                                   | ✅ preToolUse / beforeShellExecution ※2          | ✅ preToolUse                                | ✅ PreToolUse                                                                         |
| Post Tool Use          | ✅ PostToolUse ※1                                           | ✅ PostToolUse                                                       | ✅ PostToolUse                                                                 | ✅ postToolUse                                                                  | ✅ postToolUse / afterFileEdit ※2                | ✅ postToolUse                               | ✅ PostToolUse                                                                        |
| Stop (Turn End)        | ✅ Stop                                                     | ✅ Stop                                                              | ✅ Stop                                                                        | ✅ agentStop                                                                    | ✅ stop ※2                                       | ✅ stop                                      | ✅ Stop                                                                               |
| Post Tool Failure      | ❌ (PostToolUse の `err` で判別)                            | ✅ PostToolUseFailure                                                | ❌ (PostToolUse runs for non-zero exit too)                                    | ✅ postToolUseFailure                                                           | ❌                                               | ❌                                           | ❌                                                                                    |
| Agent Spawn            | ❌                                                          | ✅ SubagentStart                                                     | ✅ SubagentStart                                                               | ✅ subagentStart                                                                | ❌                                               | ✅ agentSpawn                                | ✅ SubagentStart                                                                      |
| Subagent Stop          | ❌                                                          | ✅ SubagentStop                                                      | ✅ SubagentStop                                                                | ✅ subagentStop                                                                 | ❌                                               | ❌                                           | ✅ SubagentStop                                                                       |
| Session End            | ❌                                                          | ✅ SessionEnd                                                        | ❌                                                                             | ✅ sessionEnd                                                                   | ❌                                               | ❌                                           | ❌                                                                                    |
| err Occurred           | ❌                                                          | ❌                                                                   | ❌                                                                             | ✅ errorOccurred                                                                | ❌                                               | ❌                                           | ❌                                                                                    |
| Notification           | ❌                                                          | ✅ Notification                                                      | ❌                                                                             | ✅ notification                                                                 | ❌                                               | ❌                                           | ❌                                                                                    |
| Permission req         | ❌                                                          | ✅ PermissionRequest                                                 | ✅ PermissionRequest                                                           | ✅ permissionRequest                                                            | ❌                                               | ❌                                           | ❌                                                                                    |
| Compact (Pre/Post)     | ❌                                                          | ✅ PreCompact/PostCompact                                            | ✅ PreCompact/PostCompact                                                      | ❌                                                                              | ❌                                               | ❌                                           | ✅ PreCompact                                                                         |
| File Changed           | ❌                                                          | ✅ FileChanged                                                       | ❌                                                                             | ❌                                                                              | ❌                                               | ❌                                           | ❌                                                                                    |
| Config Change          | ❌                                                          | ✅ ConfigChange                                                      | ❌                                                                             | ❌                                                                              | ❌                                               | ❌                                           | ❌                                                                                    |
| Task Created/Completed | ❌                                                          | ✅ TaskCreated/Completed                                             | ❌                                                                             | ❌                                                                              | ❌                                               | ❌                                           | ❌                                                                                    |
| Teammate Idle          | ❌                                                          | ✅ TeammateIdle                                                      | ❌                                                                             | ❌                                                                              | ❌                                               | ❌                                           | ❌                                                                                    |

### Guidelines

**→ どのイベントが存在するかの比較。各イベントで何ができるかは res Matrix を参照。**

- Claude Code が最もイベント種別が豊富（20 種以上）。細かいライフサイクル制御が可能
- Antigravity は PreInvocation / PostInvocation で Model 呼び出し前後へのステップ注入ポイントを持つ（他ツールにない独自イベント）
- Stop / PreToolUse / PostToolUse に相当するライフサイクルは全 6 ツールに存在するが、**hooks.json のイベントキー名はツールごとに異なり、大文字小文字も区別される**（例: Claude `Stop` ≠ Cursor `stop`）。hook **スクリプト**は共有可能だが、hook **定義 JSON** はターゲット別パッケージに分離する（後述）
- VS Code は Claude Code と同じ PascalCase イベント名・`hookSpecificOutput` 形式を採用するが、GitHub Copilot CLI とは別実装。`.github/hooks/*.json` を共有するが stdin/stdout の JSON 構造が異なる
- Cursor は camelCase の汎用イベント（`stop`, `preToolUse`, `postToolUse`）に加え、ツール種別ごとの細分化イベント（`beforeShellExecution` / `beforeMCPExecution` / `beforeReadFile` / `afterFileEdit` 等）を持つ。**`Stop` や `PreToolUse` など PascalCase キーは Cursor では一致せず、hook は発火しない**
- ※1: Antigravity の PostToolUse は観測専用。stdout は `{}` のみ。agent へのフィードバックには PreInvocation を使用する
- ※2: Cursor の hooks.json はイベント名のケースが厳密一致。`stop` / `preToolUse` / `postToolUse` が正。`Stop` / `PreToolUse` / `PostToolUse` は無視される（unknown event ではなく、単にマッチしない）

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

| 項目              | 値                                                   |
| ----------------- | ---------------------------------------------------- |
| イベント名        | camelCase (`agentStop`, `preToolUse`, `postToolUse`) |
| コマンドキー      | `bash`                                               |
| `type` フィールド | `"command"` (必須)                                   |
| `version`         | `1` (トップレベル、必須)                             |
| タイムアウト      | `timeoutSec` (秒)                                    |

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

| 項目                 | 値                                                                                                    |
| -------------------- | ----------------------------------------------------------------------------------------------------- |
| イベント名           | camelCase (`stop`, `preToolUse`, `postToolUse`, `afterFileEdit`, `beforeShellExecution`)              |
| ケース厳密一致       | **必須**。`Stop` / `PreToolUse` / `PostToolUse` は発火しない（PascalCase は Claude/Codex/VS Code 用） |
| コマンドキー         | `command` (`bash` はエラー)                                                                           |
| `type` フィールド    | 不要                                                                                                  |
| `version`            | `1` (トップレベル、必須。省略するとエラー)                                                            |
| タイムアウト         | `timeoutSec` (秒)                                                                                     |
| `stop` の stdout     | `{"followup_message":"..."}`（非空で次ユーザーメッセージを自動送信。`loop_limit` デフォルト 5）       |
| その他 hook の block | exit 2 + stderr（`beforeShellExecution` / `afterFileEdit` 等）                                        |

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

| 項目              | 値                                                       |
| ----------------- | -------------------------------------------------------- |
| イベント名        | PascalCase (`Stop`, `PreToolUse`, `PostToolUse`)         |
| コマンドキー      | `command`                                                |
| `type` フィールド | `"command"` (必須)                                       |
| `version`         | 不要                                                     |
| タイムアウト      | `timeout` (秒。`timeoutSec` ではない)                    |
| `matcher`         | ツール名正規表現フィルタ (空文字 = 全マッチ)             |
| ネスト構造        | イベント配列 → `{ matcher, hooks: [...] }` の 2 段ネスト |

### Codex

設定ファイル: `.codex/hooks.json` or inline in `.codex/config.toml`

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
            "timeout": 600
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

| 項目              | 値                                                               |
| ----------------- | ---------------------------------------------------------------- |
| イベント名        | PascalCase (`SessionStart`, `PreToolUse`, `PostToolUse`, `Stop`) |
| コマンドキー      | `command`                                                        |
| `type` フィールド | `"command"` (必須)                                               |
| `version`         | 不要                                                             |
| タイムアウト      | `timeout` (秒、デフォルト 600)                                   |
| `matcher`         | ✅ (正規表現、Claude Code と同形式)                              |
| Trust review      | 必須 (hash-based)                                                |

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

| 項目              | 値                                              |
| ----------------- | ----------------------------------------------- |
| イベント名        | camelCase (`stop`, `preToolUse`, `postToolUse`) |
| コマンドキー      | `command`                                       |
| `type` フィールド | `"command"` (必須)                              |
| `version`         | 不要                                            |
| タイムアウト      | `timeout` (秒)                                  |

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

| 項目                  | 値                                                                                                         |
| --------------------- | ---------------------------------------------------------------------------------------------------------- |
| イベント名            | PascalCase (`Stop`, `PreToolUse`, `PostToolUse`)                                                           |
| コマンドキー          | `bash`                                                                                                     |
| `type` フィールド     | `"command"` (必須)                                                                                         |
| `version`             | `1` (トップレベル、必須)                                                                                   |
| タイムアウト          | `timeoutSec` (秒)                                                                                          |
| `.github/hooks/` 共有 | Copilot CLI と同一ディレクトリだがイベント名が異なる。両方のイベントを同一 JSON に記載すると両方で動作する |

### Guidelines

**→ hooks.json のフォーマットはツール間で互換性がない。ターゲット別パッケージに定義を分離する（単一パッケージで `Stop` を共通キーとして配布する設計は不可）。**

| 差異ポイント     | Codex         | Copilot CLI   | Cursor        | Claude Code   | Kiro CLI      | VS Code       |
| ---------------- | ------------- | ------------- | ------------- | ------------- | ------------- | ------------- |
| コマンドキー     | `command`     | `bash`        | `command`     | `command`     | `command`     | `bash`        |
| Stop イベント名  | `Stop`        | `agentStop`   | `stop`        | `Stop`        | `stop`        | `Stop`        |
| Pre イベント名   | `PreToolUse`  | `preToolUse`  | `preToolUse`  | `PreToolUse`  | `preToolUse`  | `PreToolUse`  |
| Post イベント名  | `PostToolUse` | `postToolUse` | `postToolUse` | `PostToolUse` | `postToolUse` | `PostToolUse` |
| ケース厳密一致   | ✅ PascalCase | ✅ camelCase  | ✅ camelCase  | ✅ PascalCase | ✅ camelCase  | ✅ PascalCase |
| `version` 必須   | ❌            | ✅            | ✅            | ❌            | ❌            | ✅            |
| タイムアウトキー | `timeout`     | `timeoutSec`  | `timeoutSec`  | `timeout`     | `timeout`     | `timeoutSec`  |
| matcher 対応     | ✅            | ❌            | ❌            | ✅            | ❌            | ❌            |

### APM パッケージでの hooks 配布設計

[APM Hooks and Commands](https://microsoft.github.io/apm/producer/author-primitives/hooks-and-commands/) では、ソース hook JSON を Claude 形式（`PreToolUse`, `Stop`）または Copilot 形式（`preToolUse`, `agentStop`）で記述し、インストール時に各ターゲットの integrator がイベント名をリネームしてマージする。ただし **Cursor の hooks.json はイベントキーがケース厳密一致**であり、PascalCase の `Stop` / `PreToolUse` / `PostToolUse` をそのまま書くと発火しない（2026-07 実測）。

このため本リポジトリでは **hooks はターゲット別サブパッケージに最初から分離する**設計とする:

| パッケージ例           | `apm.yml` の `target` | hooks JSON のイベントキー例                      |
| ---------------------- | --------------------- | ------------------------------------------------ |
| `common-hooks-claude`  | `claude`              | `Stop`, `PreToolUse`, `PostToolUse` (PascalCase) |
| `common-hooks-cursor`  | `cursor`              | `stop`, `preToolUse`, `postToolUse` (camelCase)  |
| `common-hooks-copilot` | `copilot`             | `agentStop`, `preToolUse`, `postToolUse`         |

- **やってはいけない**: 1 つの hooks パッケージに `Stop` キーだけで全ターゲット向けに配布し、マージ時のリネームに任せる（Cursor ではヒットしない）
- **正しい**: `*-hooks-claude` / `*-hooks-cursor` / `*-hooks-copilot` のようにターゲット別パッケージを分け、各パッケージの `.apm/hooks/*.json` にそのターゲットのネイティブイベント名を直接記述する。hook **スクリプト**（`scripts/*.sh`）は共通化可能
- コンシューマの `dependencies.apm` で `targets:` を指定し、インストール先 harness を限定する（APM 公式推奨）
- Cursor は `version: 1` がないとエラーになる。生成物に `version` が欠ける場合はポストインストールで注入する

## res Matrix (Stop / agentStop)

| 項目                             | Antigravity                                               | Claude Code                                 | Codex                                          | Copilot CLI                                 | Cursor                                                  | Kiro CLI                                    | VS Code                                                                                               |
| -------------------------------- | --------------------------------------------------------- | ------------------------------------------- | ---------------------------------------------- | ------------------------------------------- | ------------------------------------------------------- | ------------------------------------------- | ----------------------------------------------------------------------------------------------------- |
| イベント名                       | `Stop`                                                    | `Stop`                                      | `Stop`                                         | `agentStop` / `Stop`                        | `stop`                                                  | `stop`                                      | `Stop`                                                                                                |
| Block 方式 (推奨)                | exit 0 + JSON                                             | exit 2 (stderr) **または** exit 0 + JSON    | exit 0 + JSON **または** exit 2 + stderr       | exit 0 + JSON                               | exit 0 + JSON (`followup_message`)                      | exit 0 + JSON                               | exit 0 + JSON (hookSpecificOutput)                                                                    |
| Block JSON                       | `{"decision":"continue",`<br>`"reason":"..."}`            | `{"decision":"block",`<br>`"reason":"..."}` | `{"decision":"block",`<br>`"reason":"..."}`    | `{"decision":"block",`<br>`"reason":"..."}` | `{"followup_message":"..."}`                            | `{"decision":"block",`<br>`"reason":"..."}` | `{"hookSpecificOutput":`<br>`{"hookEventName":"Stop",`<br>`"decision":"block",`<br>`"reason":"..."}}` |
| exit 2 の効果                    | hook 自体の失敗として扱われる（agent フィードバックなし） | agent 停止を防止 + stderr が agent へ       | reason が agent に届き修正ループに入る         | ユーザーに警告表示のみ                      | ErrorOutput に記録（修正ループにならない）              | ユーザーに警告表示のみ                      | agent に err ctx として注入                                                                           |
| exit 0 (JSON 無し) の効果        | agent 通常停止                                            | agent 通常停止                              | agent 通常停止                                 | agent 通常停止                              | 通常完了（follow-up なし）                              | agent 通常停止                              | agent 通常停止                                                                                        |
| reason の扱い                    | system msg として会話に注入                               | agent のコンテキストに追加                  | 新しい continuation prompt として agent に送信 | 新しいプロンプトとして agent に送信         | `followup_message` として次ユーザーメッセージに自動送信 | 新しいユーザーメッセージとして agent に送信 | agent のコンテキストに追加                                                                            |
| **ユーザーへの表示**             | ❌ (表示なし)                                             | ❌ (表示なし)                               | ❌ (表示なし)                                  | ❌ (表示なし)                               | ✅ (Hooks チャンネルに stdout / ErrorOutput)            | ❌ (表示なし)                               | ❌ (表示なし)                                                                                         |
| **agent コンテキスト注入**       | ✅ reason がコンテキストに入る                            | ✅ reason がコンテキストに入る              | ✅ reason がコンテキストに入る                 | ✅ reason がコンテキストに入る              | ✅ `followup_message` が次ターンに渡る                  | ✅ reason がコンテキストに入る              | ✅ reason がコンテキストに入る                                                                        |
| **agent が修正アクションを実行** | ✅ 次ターンで reason に基づき行動                         | ✅ 次ターンで reason に基づき行動           | ✅ 次ターンで reason に基づき行動              | ✅ 次ターンで reason に基づき行動           | ✅ `followup_message` 非空時に自動 follow-up            | ✅ 次ターンで reason に基づき行動           | ✅ 次ターンで reason に基づき行動                                                                     |
| 連続ブロック上限                 | 不明                                                      | 8 回                                        | 不明 (スクリプト側でセーフガード推奨)          | ジョブタイムアウトに依存                    | `loop_limit` デフォルト 5                               | 不明                                        | 不明 (AI credits 消費で自然制限)                                                                      |
| JSON 生成要件                    | 有効な JSON 必須                                          | 有効な JSON 必須                            | 有効な JSON 必須                               | 有効な JSON 必須                            | `followup_message` 用に jq 推奨                         | 有効な JSON 必須 (jq 推奨)                  | 有効な JSON 必須                                                                                      |

### Stop stdin / stdout Format

#### Antigravity

stdin:

```json
{
  "executionNum": 5,
  "terminationReason": "task_complete",
  "error": null,
  "fullyIdle": true,
  "conversationId": "...",
  "workspacePaths": ["/workspace"]
}
```

stdout:

```json
{ "decision": "continue", "reason": "修正すべき内容" }
```

#### Claude Code

stdin:

```json
{
  "hook_event_name": "Stop",
  "session_id": "...",
  "cwd": "/workspace",
  "transcript_path": "...",
  "stop_hook_active": false,
  "last_assistant_message": "..."
}
```

stdout — block decision:

```json
{ "decision": "block", "reason": "修正すべき内容" }
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

#### Codex

stdin:

```json
{
  "hook_event_name": "Stop",
  "session_id": "...",
  "cwd": "/workspace",
  "stop_hook_active": false,
  "last_assistant_message": "...",
  "turn_id": "...",
  "transcript_path": "...",
  "model": "...",
  "permission_mode": "..."
}
```

stdout — block decision:

```json
{ "decision": "block", "reason": "修正すべき内容" }
```

#### Copilot CLI

stdin:

```json
{
  "hook_event_name": "agentStop",
  "session_id": "...",
  "cwd": "/workspace",
  "transcriptPath": "...",
  "stopReason": "..."
}
```

stdout:

```json
{ "decision": "block", "reason": "修正すべき内容" }
```

#### Cursor

stdin:

```json
{
  "hook_event_name": "stop",
  "status": "completed",
  "loop_count": 0,
  "conversation_id": "...",
  "generation_id": "...",
  "cursor_version": "3.11.13",
  "workspace_roots": ["/workspace"]
}
```

stdout — 修正ループ用（推奨）:

```json
{ "followup_message": "修正すべき内容" }
```

`followup_message` が非空のとき、Cursor はそれを次のユーザーメッセージとして自動送信する。`loop_count` は follow-up 回数、`loop_limit`（hook 定義、デフォルト 5）で上限を制御する。

`stop` で exit 2 + stderr を使った場合、Hooks チャンネルの ErrorOutput には出るが stdout は `{}` のままになり、修正ループには入らない（2026-07 実測）。lint/test ゲートには `followup_message` を使う。

`afterFileEdit` / `beforeShellExecution` 等の **非 `stop` hook** では、引き続き exit 2 + stderr でブロック可能。

#### Kiro CLI

stdin:

```json
{
  "hook_event_name": "stop",
  "session_id": "...",
  "cwd": "/workspace",
  "assistant_response": "..."
}
```

stdout:

```json
{ "decision": "block", "reason": "修正すべき内容" }
```

#### VS Code

stdin:

```json
{
  "hook_event_name": "Stop",
  "session_id": "...",
  "cwd": "/workspace",
  "transcript_path": "...",
  "stop_hook_active": false
}
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
- Cursor `stop` は `{"followup_message":"..."}` + exit 0 が修正ループの正規手段。`decision:block` JSON は解釈しない。exit 2 + stderr は ErrorOutput 記録のみで `stop` のゲートには使わない
- Cursor の `afterFileEdit` 等（非 `stop`）は exit 2 + stderr でブロック可能
- JSON は `jq -n --arg` で生成し、改行文字のエスケープを保証する

## res Matrix (PostToolUse)

| 項目                             | Antigravity                                | Claude Code                              | Codex                                        | Copilot CLI                       | Cursor                 | Kiro CLI                    | VS Code                                          |
| -------------------------------- | ------------------------------------------ | ---------------------------------------- | -------------------------------------------- | --------------------------------- | ---------------------- | --------------------------- | ------------------------------------------------ |
| イベント名                       | `PostToolUse`                              | `PostToolUse`                            | `PostToolUse`                                | `postToolUse`                     | `afterFileEdit`        | `postToolUse`               | `PostToolUse`                                    |
| exit 0 + stdout の効果           | 出力は `{}` のみ (処理なし)                | JSON output 処理                         | JSON output 処理                             | STDOUT captured (非表示)          | 不明                   | STDOUT captured (非表示)    | JSON output 処理                                 |
| exit 2 の効果                    | 不明                                       | STDERR を Claude に表示 (ツール実行済み) | feedback が agent に届く                     | STDERR をユーザーに警告           | agent にフィードバック | STDERR をユーザーに警告     | agent に err ctx として注入                      |
| exit code で block 可能か        | ❌ (ツール実行済み)                        | ❌ (ツール実行済み)                      | ✅ `decision: "block"` で tool result を置換 | ❌ (ツール実行済み)               | ❌                     | ❌                          | ✅ `decision: "block"` で停止可                  |
| **ユーザーへの表示**             | ❌                                         | ❌ (表示なし)                            | ❌ (表示なし)                                | ⚠️ exit 2 時のみ警告表示          | 不明                   | ⚠️ exit 2 時のみ警告表示    | ❌ (表示なし)                                    |
| **agent コンテキスト注入**       | ❌ (出力不可)                              | ✅ additionalContext で注入              | ✅ additionalContext / decision:block で注入 | ✅ additionalContext で注入       | ✅ agent に渡る        | ❌                          | ✅ `hookSpecificOutput.additionalContext` で注入 |
| **agent が修正アクションを実行** | ❌ (PostToolUse 単体では不可。Stop で対応) | ✅ 次ツール呼出し時に認識して対応        | ✅ 次ツール呼出し時に認識して対応            | ✅ 次ツール呼出し時に認識して対応 | ✅ 次ターンで対応      | ❌ (フィードバック手段なし) | ✅ additionalContext / block で対応              |
| matcher (ツール名フィルタ)       | ✅ (正規表現対応)                          | ✅ (`"Edit\|Write"` 等)                  | ✅ (正規表現対応)                            | ❌ (全ツール)                     | ❌ (ファイル編集のみ)  | ❌ (全ツール)               | ❌ (全ツール)                                    |

### PostToolUse stdin / stdout Format

#### Antigravity

stdin:

```json
{
  "toolCall": { "name": "editFile", "args": { "path": "src/main.go" } },
  "result": "...",
  "error": null
}
```

stdout: `{}` のみ（観測専用）。agent へのフィードバックには PreInvocation の `injectSteps` を使用:

```json
{
  "injectSteps": [{ "ephemeralMessage": "lint結果: エラー3件。修正してください。" }]
}
```

#### Claude Code

stdin:

```json
{
  "hook_event_name": "PostToolUse",
  "session_id": "...",
  "cwd": "/workspace",
  "tool_name": "Edit",
  "tool_input": { "file_path": "src/main.go" },
  "tool_result": "..."
}
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

#### Codex

stdin:

```json
{
  "hook_event_name": "PostToolUse",
  "session_id": "...",
  "cwd": "/workspace",
  "tool_name": "Edit",
  "tool_input": { "file_path": "src/main.go" },
  "tool_response": "File edited successfully"
}
```

stdout — block + additionalContext:

```json
{
  "decision": "block",
  "reason": "...",
  "hookSpecificOutput": {
    "hookEventName": "PostToolUse",
    "additionalContext": "lint エラーを修正してください"
  }
}
```

#### Copilot CLI

stdin:

```json
{
  "hook_event_name": "postToolUse",
  "session_id": "...",
  "cwd": "/workspace",
  "toolName": "editFiles",
  "toolResult": "..."
}
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
{
  "hook_event_name": "postToolUse",
  "session_id": "...",
  "cwd": "/workspace",
  "tool_name": "editFiles",
  "tool_input": { "files": ["src/main.go"] }
}
```

stdout: N/A（フィードバック手段なし。exit 2 + stderr はユーザー警告のみ）

#### VS Code

stdin:

```json
{
  "hook_event_name": "PostToolUse",
  "session_id": "...",
  "cwd": "/workspace",
  "tool_name": "editFiles",
  "tool_input": { "files": ["src/main.go"] },
  "tool_use_id": "tool-123",
  "tool_response": "File edited successfully"
}
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
4. **res 構築**: Agent と hook_event の組み合わせに応じた JSON を stdout に出力する（Cursor `stop` は `followup_message`。非 `stop` の Cursor / unknown は exit 2 + stderr）

### 判定フロー

### Agent 判定の優先順位

| 優先度 | 判定条件                                                                                                                                                                           | Agent                      |
| ------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------- |
| 1      | `terminationReason` / `toolCall` フィールドあり                                                                                                                                    | Antigravity                |
| 2      | `stop_hook_active` / `tool_use_id` フィールドが存在する (`has()` で判定。値が `false` でも検出)                                                                                    | VS Code                    |
| 3      | `GITHUB_COPILOT_API_TOKEN` 環境変数あり、または `transcriptPath` / `stopReason` / `toolResult` 等の Copilot CLI 固有フィールドあり (`transcript_path` は VS Code と共通のため除外) | Copilot CLI                |
| 4      | `hook_event_name` ありかつ `cursor_version` / `generation_id` / `workspace_roots` のいずれかあり、または `afterFileEdit` 等 Cursor 固有イベント名                                  | Cursor                     |
| 5      | `hook_event_name` が camelCase の既知値 (`stop`, `postToolUse` 等。上記 Cursor 判定を通過したもの)                                                                                 | Kiro CLI                   |
| 6      | `permission_mode` / `turn_id` フィールドあり (Codex 固有)                                                                                                                          | Codex                      |
| 7      | `hook_event_name` が PascalCase (上記で Copilot/Codex 除外済み)                                                                                                                    | Claude Code                |
| 8      | stdin 無し / 判定不可                                                                                                                                                              | fallback (exit 2 + stderr) |

### Agent 別レスポンス仕様

| Agent       | Stop イベント時の stdout                                                                                       | PostToolUse 時の stdout                                                                                                                               | fallback        |
| ----------- | -------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------- | --------------- |
| Antigravity | `{"decision":"continue",`<br>`"reason":"..."}` + exit 0                                                        | N/A (出力 `{}` のみ)                                                                                                                                  | exit 0          |
| Claude Code | `{"decision":"block",`<br>`"reason":"..."}` + exit 0                                                           | `{"hookSpecificOutput":`<br>`{"hookEventName":"PostToolUse",`<br>`"additionalContext":"..."}}` + exit 0                                               | exit 2          |
| Codex       | `{"decision":"block",`<br>`"reason":"..."}` + exit 0                                                           | `{"decision":"block",`<br>`"reason":"...",`<br>`"hookSpecificOutput":`<br>`{"hookEventName":"PostToolUse",`<br>`"additionalContext":"..."}}` + exit 0 | exit 2          |
| Copilot CLI | `{"decision":"block",`<br>`"reason":"..."}` + exit 0                                                           | `{"additionalContext":"..."}` + exit 0                                                                                                                | exit 2          |
| Kiro CLI    | `{"decision":"block",`<br>`"reason":"..."}` + exit 0                                                           | exit 2 + stderr<br>(agent に届かない)                                                                                                                 | exit 2          |
| VS Code     | `{"hookSpecificOutput":`<br>`{"hookEventName":"Stop",`<br>`"decision":"block",`<br>`"reason":"..."}}` + exit 0 | `{"decision":"block",`<br>`"reason":"...",`<br>`"hookSpecificOutput":`<br>`{"hookEventName":"PostToolUse",`<br>`"additionalContext":"..."}}` + exit 0 | exit 2          |
| Cursor      | `{"followup_message":"..."}` + exit 0 (`stop`)                                                                 | exit 2 + stderr (`afterFileEdit` 等)                                                                                                                  | exit 2 + stderr |

### 制約事項

- `jq` は有効な JSON 生成に必須。hook スクリプトの依存コマンドとして扱う
- apm 配布ではライブラリの自動コピーが非対応のため、関数はスクリプト本体に埋め込む
- 実装例は `.apm/packages/*/.apm/hooks/scripts/*.sh` を参照。仕様の正は本ドキュメントと各 Agent の公式仕様とする
- 無限ループ対策: Claude Code は 8 回で自動停止するが、Kiro CLI / Copilot CLI / Antigravity は上限が不明。スクリプト側で環境変数や一時ファイルを用いた最大試行回数（例: カウンター制限）のセーフガード実装を推奨する

## 必須評価軸 (MUST) 判定

| 評価軸          | Antigravity | Claude Code | Codex   | Copilot CLI | Cursor  | Kiro CLI | VS Code |
| --------------- | ----------- | ----------- | ------- | ----------- | ------- | -------- | ------- |
| Problem Fit     | 3           | 3           | 3       | 3           | 2       | 3        | 3       |
| Security        | 3           | 3           | 3       | 3           | 2       | 2        | 3       |
| op Model        | 3           | 3           | 3       | 3           | 2       | 3        | 3       |
| Integration     | 3           | 3           | 3       | 3           | 2       | 2        | 3       |
| Cost/TCO        | 3           | 3           | 3       | 3           | 3       | 3        | 3       |
| Maintainability | 2           | 3           | 3       | 2           | 2       | 2        | 3       |
| **加重平均**    | **2.8**     | **3.0**     | **3.0** | **2.8**     | **2.2** | **2.5**  | **3.0** |

- Claude Code: イベント種別最多、decision control 最も柔軟、`additionalContext` 活用可。全評価軸で最高
- VS Code: Claude Code 互換の `hookSpecificOutput` 形式を採用。PostToolUse でも block 可能な唯一のツール。`.github/hooks/` からの設定読み込みで Claude Code 設定と共存可
- Codex: Claude Code と同形式 (PascalCase、matcher、decision JSON)。イベント 10 種で充実。hash-based trust review でセキュリティも高い
- Antigravity: PreInvocation で `injectSteps` により ephemeralMessage 注入可能。Stop で `"continue"` による修正ループ構築可能。PostToolUse は観測専用
- Copilot CLI: Claude Code に次ぐイベント数。JSON block decision 対応で Stop ループ構築可能
- Kiro CLI: Stop hook の JSON block 対応で修正ループ構築可能。イベント種別は少ないが実用上十分
- Cursor: `stop` は `followup_message` で修正ループ構築可能。`decision:block` JSON は非対応。`afterFileEdit` 等は exit 2 + stderr。独自イベント名のため他ツールとの hooks JSON 混在に注意

## .apm パッケージでの Hook イベント選定

| 観点                                          | PostToolUse                            | Stop                            |
| --------------------------------------------- | -------------------------------------- | ------------------------------- |
| agent が修正アクションを実行するか            | Claude Code / Codex / Copilot CLI のみ | ✅ 全ツール                     |
| Kiro CLI で agent にフィードバックが届くか    | ❌                                     | ✅                              |
| Antigravity で agent にフィードバックが届くか | ❌                                     | ✅                              |
| 全ツール互換でスクリプト 1 本で動くか         | ❌ (ツール間で出力形式が異なる)        | ✅ (decision + reason で統一可) |
| 実行タイミング                                | ツール実行直後（即時）                 | ターン完了時（まとめて）        |
| 適したユースケース                            | 自動フォーマット（agent 行動不要）     | lint/test エラーの修正ループ    |

**→ .apm パッケージでは Stop 相当イベントの hook を採用する（定義 JSON はターゲット別）。**

- lint/test のエラーを検知して agent に修正させるユースケースでは、Stop 相当イベントが唯一の全ツール互換手段
- PostToolUse は Kiro CLI / Antigravity で agent にフィードバックが届かないため、修正ループに使えない
- hook スクリプトは 1 本で全 agent 対応可能だが、`.apm/hooks/*.json` のイベントキーはターゲット別パッケージでネイティブ名を使う（Cursor では `stop` / `preToolUse` / `postToolUse`。`Stop` / `PreToolUse` / `PostToolUse` は不可）
- `report_failure` 関数で stdin の `hook_event_name` / `terminationReason` / `cursor_version` 等を判別し、全 agent に適切な JSON または exit code を返す設計とする（Cursor `stop` → `followup_message`、その他 Cursor → exit 2 + stderr）

## 補足

- VS Code の hooks 仕様は [code.visualstudio.com/docs/agent-customization/hooks](https://code.visualstudio.com/docs/agent-customization/hooks) に基づく。GitHub Copilot CLI とは別実装であり、同じ `.github/hooks/` ディレクトリを使用するが stdin/stdout の JSON 構造が異なる点に注意
- Cursor の hooks 仕様は [cursor.com/docs/hooks](https://cursor.com/docs/hooks) に基づく。イベントキーは camelCase 厳密一致（`stop`, `preToolUse`, `postToolUse`）。`stop` の修正ループは `followup_message` が正規 API（exit 2 + stderr は Hooks ログ用でゲートには非推奨）
- APM hooks 配布の設計指針は [microsoft.github.io/apm — Hooks and Commands](https://microsoft.github.io/apm/producer/author-primitives/hooks-and-commands/) を参照。本リポジトリはターゲット別 hooks パッケージ分離を採用
- Antigravity の hooks 仕様は [antigravity.google/docs/hooks](https://antigravity.google/docs/hooks) の正式仕様に基づく。旧 Gemini CLI ([geminicli.com](https://geminicli.com/docs/hooks/reference/)) とはイベント名・JSON 形式が異なるため注意
- Antigravity の PostToolUse は観測専用（出力 `{}` のみ）。agent へのフィードバックには PreInvocation の `injectSteps` または Stop の `{"decision":"continue","reason":"..."}` を使用する
- 各ツールの hooks 仕様 URL は変更される可能性があるため、定期的に確認する
