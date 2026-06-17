<!-- omit in toc -->
# Tool Comparison Matrix — Agent Security: Guardrails

[tool-comparison-matrix-ai-agent.md](tool-comparison-matrix-ai-agent.md) からの分離ドキュメント。
エージェントの権限設定・ツール許可ルール・Configuration Examples を詳述する。

<!-- omit in toc -->
## History

| 日付       | 内容                                                                 |
| ---------- | -------------------------------------------------------------------- |
| 2026-06-16 | 本体から分離して新規作成。Cursor IDE/CLI 権限設定を追加              |

<!-- omit in toc -->
## Table of Contents

- [Guardrails Configuration](#guardrails-configuration)
- [Configuration Examples](#configuration-examples)
- [Guidelines](#guidelines)

## Guardrails Configuration

| 設定項目                | Antigravity               | Claude Code                   | Cursor                    | GitHub Copilot          | Kiro                                    |
| ----------------------- | ------------------------- | ----------------------------- | ------------------------- | ----------------------- | --------------------------------------- |
| ドキュメント            | [antigravity.google](https://antigravity.google/docs/security) | [docs.anthropic.com](https://docs.anthropic.com/en/docs/claude-code/security) | [IDE](https://cursor.com/docs/reference/permissions) / [CLI](https://cursor.com/docs/cli/reference/configuration) | [docs.github.com](https://docs.github.com/en/copilot/reference/copilot-cli-reference/cli-config-dir-reference) | [kiro.dev](https://kiro.dev/docs/cli/custom-agents/configuration-reference/#toolssettings-field) |
| 権限設定ファイル        | `.gemini/antigravity-cli/settings.json` | `.claude/settings.json`       | IDE: `.cursor/permissions.json` / CLI: `.cursor/cli.json`   | `.github/copilot/settings.json` | `.kiro/agents/*.json`                   |
| ユーザー権限設定        | `~/.gemini/antigravity-cli/settings.json` | `~/.claude/settings.json`     | `~/.cursor/cli-config.json` (CLI) / IDE は動的承認 | `~/.copilot/permissions-config.json`      | `~/.kiro/agents/*.json`                 |
| ローカル設定 (Git除外)  | -                         | `.claude/settings.local.json` | -                   | `.github/copilot/settings.local.json` | -                                       |
| ツール許可ルール        | sandbox 設定              | `allow` / `deny` リスト       | `mcpAllowlist` / `terminalAllowlist` / `autoRun`   | `permissions-config.json` (自動記録)       | `allowedTools` / `toolsSettings`        |
| 管理者設定 (Enterprise) | GCP Organization policy   | managed policy (JSON)         | -                         | Organization policy     | -                                       |

## Configuration Examples

**Kiro** (`.kiro/agents/default.json`):

```json
{
  "allowedTools": ["read", "write", "shell"],
  "toolsSettings": {
    "shell": {
      "allowedCommands": ["npm test.*"],
      "deniedCommands": ["rm -rf.*", "git push --force.*"]
    }
  }
}
```

**Claude Code** (`.claude/settings.json`):

```json
{
  "permissions": {
    "allow": ["Read", "Write", "Bash(npm test *)", "Bash(go test *)"],
    "deny": ["Bash(rm -rf *)", "Bash(git push --force *)", "Bash(terraform apply *)"]
  }
}
```

**Cursor IDE** (`.cursor/permissions.json`):

```json
{
  "mcpAllowlist": ["github:*"],
  "terminalAllowlist": ["git", "npm test", "go test"],
  "autoRun": {
    "block_instructions": [
      "Destructive git operations: push --force, reset --hard, clean -f.",
      "Any command that installs packages or modifies .env files."
    ]
  }
}
```

**Cursor CLI** (`.cursor/cli.json`):

```json
{
  "version": 1,
  "editor": { "vimMode": false },
  "permissions": {
    "allow": ["Shell(git)", "Shell(go test)", "Read(src/**)", "Write(src/**)"],
    "deny": ["Shell(rm -rf)", "Shell(sudo)", "Read(.env*)", "Write(~/**)"]
  }
}
```

**GitHub Copilot** (`.github/copilot/settings.json`):

```json
{
  "hooks": {
    "pre-tool-use": [{ "event": "Bash", "command": "echo 'confirm'" }]
  }
}
```

## Guidelines

**→ エージェント導入時は以下のセキュリティ設定を必ず行う:**

1. 本番操作は明示承認必須とする (破壊的操作の制限を指示ファイルに明記)
2. `.env` / credentials / secrets へのアクセス制限を定義する
3. 外部へのコード・データ送信ルールを明記する
4. Instructions / Rules は Git 管理し、PR レビュー対象とする
5. 学習利用・データ保持ポリシーを確認し、機密コードが学習に使われないプランを選択する
