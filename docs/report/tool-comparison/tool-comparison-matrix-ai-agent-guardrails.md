# Tool Comparison Matrix — Agent Security: Guardrails

[tool-comparison-matrix-ai-agent.md](tool-comparison-matrix-ai-agent.md) からの分離ドキュメント。
エージェントの権限設定・ツール許可ルール・Configuration Examples を詳述する。

## History

| 日付       | 内容                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            |
| ---------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 2026-11-18 | Agent Sandbox / Isolation セクションを追加 (sandbox-runtime / Docker Sandboxes / devcontainer / 各 agent 組み込み sandbox)。Antigravity のツール許可ルール (`permissions` + `toolPermission`)、Codex `requirements.toml` のパス、Claude Code managed settings の配信方式を公式ドキュメントで確認し修正。Copilot の例を hooks 設定から `permissions-config.json` に差し替え。Antigravity の管理者設定・プロジェクトパスは未確認。Claude Code (ドキュメント URL・`ask`)、Codex (`approval_policy` / `sandbox_mode`・ドキュメント URL・設定パス)、Cursor (IDE ユーザー `~/.cursor/permissions.json`)、Kiro (V3 `permissions.rules` 形式・ドキュメント URL) を公式ドキュメントで確認し修正。Copilot CLI のパスは確認済み (変更なし) |
| 2026-06-27 | Codex (OpenAI) を追加                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           |
| 2026-06-16 | 本体から分離して新規作成。Cursor IDE/CLI 権限設定を追加                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         |

## Guardrails Configuration

| 設定項目                | Antigravity                                                                                               | Claude Code                                                       | Codex                                                                                                                            | Cursor                                                                                                            | GitHub Copilot                                                                                                 | Kiro                                                                                                                       |
| ----------------------- | --------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------- |
| ドキュメント            | [antigravity.google](https://antigravity.google/docs/ide/settings)                                        | [code.claude.com](https://code.claude.com/docs/en/permissions)    | [learn.chatgpt.com](https://learn.chatgpt.com/docs/config-file/config-reference)                                                 | [IDE](https://cursor.com/docs/reference/permissions) / [CLI](https://cursor.com/docs/cli/reference/configuration) | [docs.github.com](https://docs.github.com/en/copilot/reference/copilot-cli-reference/cli-config-dir-reference) | [kiro.dev](https://kiro.dev/docs/custom-agents/configuration-reference/#permissions-field)                                 |
| 権限設定ファイル        | `.gemini/antigravity-cli/settings.json`                                                                   | `.claude/settings.json`                                           | `.codex/config.toml` (approval_policy / sandbox_mode; trusted project のみ)                                                      | IDE: `.cursor/permissions.json` / CLI: `.cursor/cli.json`                                                         | `.github/copilot/settings.json`                                                                                | `.kiro/agents/*.json`                                                                                                      |
| ユーザー権限設定        | `~/.gemini/antigravity-cli/settings.json`                                                                 | `~/.claude/settings.json`                                         | `~/.codex/config.toml`                                                                                                           | `~/.cursor/cli-config.json` (CLI) / `~/.cursor/permissions.json` (IDE)                                            | `~/.copilot/permissions-config.json`                                                                           | `~/.kiro/agents/*.json`                                                                                                    |
| ローカル設定 (Git 除外) | -                                                                                                         | `.claude/settings.local.json`                                     | -                                                                                                                                | -                                                                                                                 | `.github/copilot/settings.local.json`                                                                          | -                                                                                                                          |
| ツール許可ルール        | `permissions` の `allow` / `ask` / `deny` (`action(target)`) + `toolPermission` / `enableTerminalSandbox` | `allow` / `ask` / `deny` リスト                                   | `sandbox_mode` (read-only / workspace-write / danger-full-access) + `approval_policy` (on-request / never / granular)            | `mcpAllowlist` / `terminalAllowlist` / `autoRun`                                                                  | `permissions-config.json` (自動記録)                                                                           | `permissions.rules` (V3: capability / match / effect) ※旧: `allowedTools` / `toolsSettings` (V3 では `toolsSettings` 無視) |
| 管理者設定 (Enterprise) | GCP Organization policy (未確認。設定ページに管理者ポリシーファイルの記載なし)                            | managed settings (`managed-settings.json` / MDM / server-managed) | `requirements.toml` (Unix: `/etc/codex/requirements.toml` / Windows: `%ProgramData%\OpenAI\Codex\requirements.toml` / macOS MDM) | -                                                                                                                 | Organization policy                                                                                            | -                                                                                                                          |

## Configuration Examples

**Kiro** (`.kiro/agents/default.json`, CLI V3 / IDE 1.0):

```json
{
  "permissions": {
    "rules": [
      { "capability": "shell", "match": ["npm test *"], "effect": "allow" },
      { "capability": "shell", "match": ["rm -rf *", "git push --force *"], "effect": "deny" }
    ]
  }
}
```

旧形式 (CLI 2.x): `allowedTools` / `toolsSettings.shell.allowedCommands` / `deniedCommands`。V3 では `/upgrade-agent` で `permissions.rules` に変換される。

**Claude Code** (`.claude/settings.json`):

```json
{
  "permissions": {
    "allow": ["Read", "Write", "Bash(npm test *)", "Bash(go test *)"],
    "deny": ["Bash(rm -rf *)", "Bash(git push --force *)", "Bash(terraform apply *)"]
  }
}
```

**Codex** (`.codex/config.toml`):

```toml
# .codex/config.toml
sandbox_mode = "workspace-write"
approval_policy = "on-request"

[features]
hooks = true
```

**Cursor IDE** (`.cursor/permissions.json`):

```json
{
  "mcpAllowlist": ["github:*"],
  "terminalAllowlist": ["git", "npm test", "go test"],
  "autoRun": {
    "block_instructions": ["Destructive git operations: push --force, reset --hard, clean -f.", "Any command that installs packages or modifies .env files."]
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

**GitHub Copilot CLI** (`~/.copilot/permissions-config.json`、CLI が自動記録。`allowed_directories` の絶対パスは実在が必要):

```json
{
  "locations": {
    "/path/to/project": {
      "tool_approvals": [{ "kind": "commands", "commandIdentifiers": ["git:*"] }, { "kind": "write" }],
      "allowed_directories": ["/path/to/shared-docs"]
    }
  }
}
```

deny / ask ルールは `permissions-config.json` に無く、`--deny-tool` などの CLI フラグで指定する。

## Agent Sandbox / Isolation

[Guardrails Configuration](#guardrails-configuration) の権限ルール (allow / ask / deny) とは別に、OS レベルでエージェントの実行プロセスを隔離する仕組みを比較する。権限ルールは「何を実行してよいか」、sandbox は「実行されたプロセスが何に触れるか」を制限する。2026-11-18 時点の公式ドキュメントで確認した内容のみ記載し、確認できない項目は `未確認` とする。

| 比較項目             | Anthropic sandbox-runtime                                                                               | Claude Code sandbox                                                                                                  | Codex sandbox                                                                           | Cursor sandbox                                                                                                        | devcontainer (本リポジトリ)                                                                                                                | Docker Sandboxes                                                                                      |
| -------------------- | ------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------ | ----------------------------------------------------------------------------------------------------- |
| 提供元               | Anthropic                                                                                               | Anthropic                                                                                                            | OpenAI                                                                                  | Cursor                                                                                                                | -                                                                                                                                          | Docker                                                                                                |
| リポジトリ           | [anthropic-experimental/sandbox-runtime](https://github.com/anthropic-experimental/sandbox-runtime)     | -                                                                                                                    | -                                                                                       | -                                                                                                                     | `.devcontainer/devcontainer.json` (本リポジトリ)                                                                                           | docker/sbx-releases (Issue 窓口)                                                                      |
| ドキュメント         | 上記 README                                                                                             | [code.claude.com](https://code.claude.com/docs/en/sandboxing)                                                        | [learn.chatgpt.com](https://learn.chatgpt.com/docs/sandboxing)                          | [cursor.com](https://cursor.com/docs/agent/security/run-modes)                                                        | -                                                                                                                                          | [docs.docker.com](https://docs.docker.com/ai/sandboxes/)                                              |
| ライセンス           | Apache-2.0                                                                                              | 未確認 (sandbox-runtime ベース)                                                                                      | 未確認                                                                                  | 未確認                                                                                                                | -                                                                                                                                          | 未確認                                                                                                |
| 提供形態             | CLI `srt` / ライブラリ (npm `@anthropic-ai/sandbox-runtime`)。beta research preview                     | Claude Code 組み込み (`/sandbox`)。既定オフ                                                                          | Codex 組み込み (`sandbox_mode`)                                                         | Cursor 組み込み (`sandbox.json`)                                                                                      | コンテナ環境定義                                                                                                                           | `sbx` CLI (ローカル / Docker 管理クラウド)                                                            |
| 分離方式             | macOS: Seatbelt / Linux: bubblewrap + seccomp / Windows: 専用ローカルユーザー + WFP (alpha)             | macOS: Seatbelt / Linux・WSL2: bubblewrap + socat                                                                    | macOS: Seatbelt / Linux・WSL2: bubblewrap / Windows: ネイティブ sandbox                 | macOS: Seatbelt / Linux: Landlock + seccomp                                                                           | Docker コンテナ (プロセス・ファイルシステム名前空間)                                                                                       | microVM (サンドボックスごとに専用 VM と専用 Docker daemon)                                            |
| ファイルシステム境界 | 書込みは allow-only、読取りは deny-then-allow (`allowWrite` / `denyRead`)                               | 書込みは作業ディレクトリ等のみ。読取りは既定でほぼ全域 (`~/.ssh` 等を含む)。`.claude` 等の保護パスは書込み不可       | `workspace-write` は workspace 内のみ書込み可。`writable_roots` で拡張                  | workspace は読書き可。`.git/config` 等は保護。読取りは既定 System (workspace 外も可) / Workspace 設定で承認制 (3.23+) | bind mount `/workspace` のみ書込み対象だが、コンテナ内ユーザーはコンテナ全体を読書き可。ホストの他パスは mount 以外不可視                  | workspace を passthrough mount (direct) / read-only clone (clone mode) / mountless (0.42.0+)          |
| ネットワーク境界     | ホスト側 HTTP / SOCKS5 プロキシでドメイン allow / deny。`allowedDomains` 空 = 通信不可                  | プロキシ経由でホスト名フィルタ。`allowedDomains` 既定は空。未知ホストは permission mode に従う                       | 未確認 (ローカル sandbox の既定ネットワーク可否は参照ページに記載なし)                  | 既定でブロック。モード: sandbox.json Only / sandbox.json + Defaults (既定) / Allow All                                | 制限なし (`runArgs` に `--add-host=host.docker.internal:host-gateway` を追加)                                                              | 全 outbound TCP をホストプロキシ経由にし、network policy で制御                                       |
| クレデンシャル境界   | `credentials` の `deny` / `mask` (sentinel をプロキシで実値に置換。mask は `network.tlsTerminate` 前提) | `sandbox.credentials` の `deny` / `mask` (mask は `network.tlsTerminate` と信頼スコープが必要)。標準の deny 一覧なし | 未確認                                                                                  | 未確認                                                                                                                | 境界なし。`~/.aws` と `~/.config/gh` を bind mount でコンテナに渡し、ホストの Docker socket 系 feature (`docker-outside-of-docker`) を利用 | エージェントには sentinel のみ公開。プロキシが送信時に実クレデンシャルへ置換                          |
| 対応プラットフォーム | macOS / Linux / Windows (alpha)。WSL は未確認                                                           | macOS / Linux / WSL2。WSL1・ネイティブ Windows は非対応 (未保護で実行)                                               | macOS / Linux / WSL2 / Windows (ネイティブ)                                             | macOS (v2.0+) / Linux (kernel 6.2+ と Landlock v3)。Windows は記載なし                                                | Docker 実行環境 (Dev Containers 対応エディタ)。OS 別は未確認                                                                               | 未確認 (参照ページに OS 一覧なし)                                                                     |
| 対象範囲の注意       | Bash 相当のコマンド実行のみ。ライブラリ組み込みで他用途も可                                             | Bash / PowerShell / Monitor とその子プロセスのみ。Read / Edit / Write ツール、hooks、ローカル MCP サーバーは対象外   | 子プロセス (git・package manager 等) も対象。`danger-full-access` で無効化              | 端末コマンドのみ。Run Mode が Run Everything の場合は非 sandbox                                                       | エージェント全体を包含 (ツールを問わない)。ただしコンテナ内は信頼境界に含まれる                                                            | エージェント全体を VM 内で実行                                                                        |
| 導入コスト           | 中 (`npm i -g` + Linux は bubblewrap / socat / ripgrep、Windows は管理者権限のセットアップ)             | 低〜中 (macOS は追加不要。Linux / WSL2 は bubblewrap / socat 導入、Ubuntu 24.04+ は AppArmor 設定が必要な場合あり)   | 低 (macOS 追加不要。Linux は bubblewrap、Ubuntu 24.04 は AppArmor 設定が必要な場合あり) | 低 (macOS 追加不要。Linux は kernel 要件。CLI は AppArmor パッケージが必要な場合あり)                                 | 中 (Docker と Dockerfile / mount 設計が必要。本リポジトリは構築済み)                                                                       | 中 (`sbx` CLI 導入。VM のためリソース消費大)                                                          |
| 価格                 | 無料 (OSS)                                                                                              | 追加料金の記載なし (組み込み機能)                                                                                    | 追加料金の記載なし (ChatGPT Work の管理ポリシー等は別)                                  | sandbox 自体のプラン要件は記載なし。チーム管理者ポリシーの一部は Enterprise 機能                                      | 無料 (Docker 環境の費用は別)                                                                                                               | `sbx` CLI とローカル実行は無料 (商用含む)。クラウド実行は従量課金。組織ポリシー集中管理は別途有料契約 |

**→ OS レベル隔離の強度は、プロセス単位 (Seatbelt / bubblewrap 等の各 agent 組み込みと sandbox-runtime) < コンテナ (devcontainer) < microVM (Docker Sandboxes) の順を基本とし、境界の外 (クレデンシャル・Docker socket・対象外ツール) の設計で実効性が決まる。**

### Sandbox / Isolation Guidelines

- 選定方針:
  - 端末コマンド実行の隔離を最小コストで得るなら、使用中エージェントの組み込み sandbox を優先する。
  - エージェント全体・クレデンシャルまで隔離する必要がある場合は、コンテナまたは microVM を選ぶ。
  - 評価は [Tool Comparison Evaluation Rules](tool-comparison-evaluation-rules.md) の必須評価軸 (Security / Operation Model / Cost/TCO) で行う。
- 採用条件:
  - 組み込み sandbox: 対象プラットフォーム (macOS / Linux / WSL2 等) で動作し、対象範囲 (端末コマンドのみ) で要件を満たす。
  - sandbox-runtime: 任意のコマンドやエージェント基盤を自前で包みたく、beta (APIs・設定形式が変わりうる) を許容できる。
  - devcontainer: ツール・バージョンの再現性と、ホストからの作業環境分離を重視する。
  - Docker Sandboxes: VM レベルの隔離とクレデンシャル非公開が必須で、リソース消費を許容できる。
- 不採用条件:
  - 組み込み sandbox: ネイティブ Windows など非対応環境が主 (Claude Code は未保護で実行される。`sandbox.failIfUnavailable` で停止可能)。
  - sandbox-runtime: Windows 利用が本番要件 (alpha)、または Schannel 依存ツールを使う。
  - devcontainer: 認証情報を mount し Docker socket 系 feature も使うため、信頼できないコードに対する強い隔離境界としては採用しない。
  - Docker Sandboxes: 対応 OS・ライセンスが要件に合うか未確認のまま本番採用しない。
- 併用条件:
  - devcontainer (環境の再現・ホスト分離) + 組み込み sandbox (コマンド単位のファイル・ネットワーク制限) を併用する。ネストの場合は Claude Code の `enableWeakerNestedSandbox` 等、境界が弱まる設定を確認する。
  - sandbox は権限ルール ([Guardrails Configuration](#guardrails-configuration)) と併用する。sandbox は Read / Edit / Write ツールを対象としない場合がある。
- 更新条件:
  - 各ツールのメジャーリリース、beta / alpha 状態の変更、対応 OS・ライセンス・価格改定があったとき。
  - 未確認項目 (Codex ネットワーク既定・クレデンシャル、Cursor クレデンシャル、Docker Sandboxes の OS・ライセンス) が公式ドキュメントで確認できたとき。

## Guidelines

**→ エージェント導入時は以下のセキュリティ設定を必ず行う:**

1. 本番操作は明示承認必須とする (破壊的操作の制限を指示ファイルに明記)
2. `.env` / credentials / secrets へのアクセス制限を定義する
3. 外部へのコード・データ送信ルールを明記する
4. Instructions / Rules は Git 管理し、PR レビュー対象とする
5. 学習利用・データ保持ポリシーを確認し、機密コードが学習に使われないプランを選択する
