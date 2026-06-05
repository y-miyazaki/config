<!-- omit in toc -->
# Tool Comparison Matrix (AI Agent)

AI Agent / コーディングアシスタントに特化したツール選定の判断材料。

## History

| 日付       | 内容                                                                 |
| ---------- | -------------------------------------------------------------------- |
| 2026-06-05 | GitHub Copilot 6月課金モデル変更 (AI Credits制) 反映、Cursor/Gemini情報修正、Agent Hooks セクション追加 |
| 2026-05-21 | History セクション追加                                               |
| 2026-05-12 | 初版作成。Kiro / Claude Code / GitHub Copilot / Cursor / Gemini を比較 |

<!-- omit in toc -->
## Table of Contents

- [History](#history)
- [Coding Agent: Kiro vs Claude Code vs GitHub Copilot vs Cursor vs Gemini](#coding-agent-kiro-vs-claude-code-vs-github-copilot-vs-cursor-vs-gemini)
  - [Pricing](#pricing)
  - [Billing Model](#billing-model)
  - [Configuration Files and Directories](#configuration-files-and-directories)
  - [Guidelines](#guidelines)
- [Agent Security: Guardrails](#agent-security-guardrails)
  - [Guardrails Configuration](#guardrails-configuration)
  - [Configuration Examples](#configuration-examples)
  - [Guidelines](#guidelines-1)
- [Agent Skills](#agent-skills)
  - [Guidelines](#guidelines-2)
- [Agent Hooks](#agent-hooks)
  - [Guidelines](#guidelines-3)
- [Agent Instructions (Steering)](#agent-instructions-steering)
  - [Guidelines](#guidelines-4)
- [今後の改善候補](#今後の改善候補)

## Coding Agent: Kiro vs Claude Code vs GitHub Copilot vs Cursor vs Gemini

| 比較項目           | Kiro            | Claude Code           | GitHub Copilot         | Cursor                    | Gemini                     |
| ------------------ | --------------- | --------------------- | ---------------------- | ------------------------- | -------------------------- |
| 提供元             | AWS             | Anthropic             | GitHub (Microsoft)     | Anysphere                 | Google                     |
| ドキュメント       | [kiro.dev/docs/cli](https://kiro.dev/docs/cli) | [docs.anthropic.com](https://docs.anthropic.com/en/docs/claude-code) | [docs.github.com](https://docs.github.com/en/copilot) | [docs.cursor.com](https://docs.cursor.com) | [geminicli.com](https://geminicli.com/docs/) / [ai.google.dev](https://ai.google.dev/gemini-api/docs) |
| ライセンス         | 商用            | 商用                  | 商用                   | 商用                      | 商用                       |
| 動作形態           | IDE / CLI       | IDE / CLI             | IDE / CLI              | AIネイティブIDE           | IDE / CLI                  |
| エージェントモード | ✅               | ✅                     | ✅                      | ✅                         | ✅                          |
| マルチファイル編集 | ✅               | ✅                     | ✅                      | ✅                         | ✅                          |
| ターミナル実行     | ✅               | ✅                     | ✅                      | ✅                         | ✅                          |
| MCP 対応           | ✅               | ✅                     | ✅                      | ✅                         | ✅                          |
| AWS 統合           | ✅ (ネイティブ)  | ❌                     | ⚠️ 一部連携             | ❌                         | ❌                          |
| GCP 統合           | ❌               | ❌                     | ⚠️ 一部連携             | ❌                         | ✅ (ネイティブ)             |
| セルフホスト / VPC | ✅ (AWS環境連携) | ❌                     | ⚠️ (Enterprise構成次第) | ❌                         | ⚠️ (GCP Enterprise)         |
| CLI 自動化適性     | ✅               | ✅ 非常に強い          | ⚠️ 中程度               | ⚠️ 中程度                  | ✅ (Gemini CLI)             |
| 大規模導入適性     | ⚠️ 今後拡大      | ✅ (Team / Enterprise) | ✅ 非常に強い           | ✅ (Business / Enterprise) | ✅ (Google Cloud組織)       |
| コンテキスト窓     | 200K tokens      | 200K tokens           | 128K〜200K tokens      | 128K〜200K tokens         | 1M+ tokens                 |
| モデル選択         | ✅ (Auto / 手動)  | Claude 系のみ          | ✅ 複数 (GPT-5, Claude等) | ✅ 複数 (GPT-5, Claude等)  | Gemini 系中心 (実験的に Gemma) |
| データ学習利用     | ❌ 利用しない     | ❌ 利用しない          | ❌ (Business以上)        | ❌ (Business以上)          | ❌ 利用しない               |
| コンプライアンス   | SOC2 / AWS準拠   | SOC2                  | SOC2 / FedRAMP          | SOC2                      | SOC2 / ISO / GCP準拠       |

### Pricing

> ※ 2026-06-01 より GitHub Copilot は「リクエストベース」から「AI Credits (トークンベース)」課金に移行。1 AI credit = $0.01 USD。モデル選択とトークン消費量で実コストが大きく変動するため、月額はあくまで基本料金+含まれるクレジット枠の目安。
> ※ Gemini CLI は 2026-06-18 に無料枠 (Unpaid tier / Google One) 向けサービスを終了し、Antigravity CLI へ移行予定。有料 API キー利用者は引き続き利用可。

| プラン       | Kiro                         | Claude Code                       | GitHub Copilot                          | Cursor                | Gemini                        |
| ------------ | ---------------------------- | --------------------------------- | --------------------------------------- | --------------------- | ----------------------------- |
| 料金ページ   | [kiro.dev/pricing](https://kiro.dev/pricing) | [anthropic.com/pricing](https://www.anthropic.com/pricing) | [github.com/features/copilot](https://github.com/features/copilot#pricing) | [cursor.com/pricing](https://www.cursor.com/pricing) | [ai.google.dev/pricing](https://ai.google.dev/pricing) |
| 無料枠       | 50 クレジット/月             | ❌                                 | ✅ (Free: 限定 AI Credits / コード補完は無制限) | ✅ (Hobby: Agent限定利用+Tab限定) | ⚠️ (6/18以降 Antigravity CLI へ移行、無料枠廃止予定) |
| 個人 (標準)  | Pro: $20/月                  | Pro: $20/月                       | Pro: $10/月 (1,500 credits含む)         | Pro: $20/月           | Gemini Advanced: $19.99/月 (Google One AI Premium) |
| 個人 (上位)  | Pro+: $40/月, Power: $200/月 | Max 5x: $100/月, Max 20x: $200/月 | Pro+: $39/月 (7,000 credits), Max: $100/月 (20,000 credits) | Pro+: $60/月, Ultra: $200/月 | -                             |
| チーム/組織  | 今後拡張                     | Team: $25/seat/月, Premium: $125/seat/月 | Business: $19/user/月 (1,900 credits/user, プール型) | Teams Standard: $40/seat/月, Premium: $120/seat/月 | Standard: 時間課金            |
| Enterprise   | 今後拡張                     | Enterprise: カスタム              | Enterprise: $39/user/月 (3,900 credits/user, プール型) | Enterprise: カスタム  | Enterprise: カスタム          |
| 従量追加課金 | ✅ 超過時 $0.04/credit で追加課金 (opt-in) | ⚠️ API利用時あり                   | ✅ 超過時 $0.01/credit で追加課金 (予算上限設定可) | ⚠️ usage 条件あり      | ⚠️ GCP課金連携                 |

### Billing Model

> ※ GitHub Copilot は 2026-06-01 より全プラン AI Credits 制に移行。旧「premium requests」は廃止 (legacy)。

| 項目               | Kiro                     | Claude Code                 | GitHub Copilot                                   | Cursor                         | Gemini                        |
| ------------------ | ------------------------ | --------------------------- | ------------------------------------------------ | ------------------------------ | ----------------------------- |
| 基本課金           | サブスク + クレジット枠  | サブスク枠 (定額内トークン) | サブスク + AI Credits (トークン従量)              | サブスク + usage制限           | 無料枠 + サブスク             |
| クレジット単価     | $0.04/credit (超過時)    | -                           | 1 AI credit = $0.01 USD                          | -                              | -                             |
| 含まれるクレジット | Pro: 1,000/月, Pro+: 2,000/月, Power: 10,000/月 | -                           | Pro: 1,500/月, Pro+: 7,000/月, Max: 20,000/月    | -                              | -                             |
| 組織プールモデル   | -                        | -                           | ✅ (user単位クレジットを組織全体でプール共有)      | -                              | -                             |
| 超過時の挙動       | $0.04/credit 追加課金 (opt-in) | レート制限 / 上位プラン誘導 | 予算設定に基づき追加課金 or ブロック              | 制限 or 追加課金               | レート制限                    |
| モデル選択         | ✅ (Auto / 手動)          | Claude 系中心               | ✅ 複数モデル (GPT-5, Claude, Gemini等)           | ✅ 複数モデル (GPT-5, Claude等) | Gemini 系中心 (2.5 Pro/Flash) |
| モデルによる料金差 | クレジット消費量が異なる | プラン内定額                | モデル×トークン数で credit 消費が大きく異なる     | モデルにより消費が異なる       | プラン内定額                  |
| Code Completions   | -                        | -                           | AI Credits 消費なし (Freeを含む全プランで無制限)  | -                              | -                             |
| 年額割引           | 不明 / 今後次第          | ✅ ($17/月相当)              | ✅ (年額プランあり、旧request-baseは legacy扱い)  | ✅ ($192/年 = Pro)              | ✅ (年額プランあり)            |

### Configuration Files and Directories

| 用途                | Kiro                           | Claude Code                      | GitHub Copilot                    | Cursor                            | Gemini (CLI)                    |
| ------------------- | ------------------------------ | -------------------------------- | --------------------------------- | --------------------------------- | ------------------------------- |
| Steering (指示)     | `.kiro/steering/*.md`          | `CLAUDE.md` / `<dir>/CLAUDE.md`  | `.github/copilot-instructions.md` | `.cursorrules` / `.cursor/rules/` | `GEMINI.md` / `.gemini/GEMINI.md` |
| Skills (スキル)     | `.kiro/skills/<name>/SKILL.md` | `.claude/skills/<name>/SKILL.md` | `.github/skills/<name>/SKILL.md`  | `.cursor/skills/<name>/SKILL.md`      | `.gemini/skills/<name>/SKILL.md` |
| MCP 設定            | `.kiro/settings/mcp.json`      | `.mcp.json`                      | `.vscode/mcp.json`                | `.cursor/mcp.json`                | `.gemini/settings.json`         |
| Hooks 設定          | IDE: `.kiro/hooks/*.kiro.hook` / CLI: Agent設定内 `hooks` フィールド | `.claude/settings.json` 内 `hooks` | `.github/hooks/*.json`            | `.cursor/hooks.json` (プロジェクト) / `~/.cursor/hooks.json` (ユーザー) | `.gemini/settings.json` 内 `hooks` |
| Agent 定義          | `.kiro/agents/`                | `.claude/agents/`                | `.github/copilot-agents.yml`      | ⚠️ 独自UI管理                      | -                               |
| プロンプト          | `.kiro/prompts/`               | `.claude/commands/` (レガシー)   | `.github/prompts/`                | -                                 | Custom commands                 |
| プロジェクト設定    | `.kiro/agents/*.json`          | `.claude/settings.json`          | `.vscode/settings.json`           | `.cursor/settings.json`           | `.gemini/settings.json`         |
| ユーザー設定        | `~/.kiro/`                     | `~/.claude/`                     | VS Code User Settings             | `~/.cursor/`                      | `~/.gemini/`                    |

### Guidelines

**→ 技術スタック / 組織要件 / セキュリティ要件 / 開発速度で選択する。**

- AWS 中心開発 / IAM / 組織統制重視 → **Kiro**
- CLI 中心 / 自動化 / 高品質対話 → **Claude Code**
- GitHub / PRレビュー / 開発標準化 → **GitHub Copilot**
- IDE 内完結 / 高速開発体験 → **Cursor**
- GCP 中心開発 / Vertex AI 連携 → **Gemini**
- 複数ツール併用前提の探索環境 → **Kiro + Claude Code + Copilot** など併用
- コスト最小で始めたい → GitHub Copilot (Free) または Cursor (Hobby)
- 大量利用 → Kiro Power ($200/月) または Claude Code Max 20x ($200/月) または Copilot Max ($100/月, 20,000 credits)
- コスト予測性重視 → Claude Code (定額内) または Kiro (クレジット制)。Copilot は AI Credits 制でモデル・用途次第で変動大

## Agent Security: Guardrails

| 比較項目             | Kiro                   | Claude Code      | GitHub Copilot  | Cursor           | Gemini                   |
| -------------------- | ---------------------- | ---------------- | --------------- | ---------------- | ------------------------ |
| 破壊的操作の制御     | ✅ 承認制               | ✅ permissions    | ✅ 確認あり      | ⚠️ 一部           | ✅ 確認あり               |
| ファイルアクセス制御 | ✅                      | ✅ deny パターン  | ⚠️ IDE依存       | ⚠️ IDE依存        | ⚠️ 限定的                 |
| シークレット保護     | ✅                      | ✅                | ✅               | ⚠️                | ✅                        |
| ネットワーク制御     | ✅                      | ✅                | ⚠️               | ⚠️                | ⚠️                        |
| コマンド実行制御     | ✅ (allowlist/denylist) | ✅ (permissions)  | ✅               | ⚠️                | ✅ (sandbox)              |
| 監査ログ             | ⚠️ セッション中心       | ⚠️ セッション中心 | ✅ Enterprise    | ⚠️                | ⚠️ (Vertex AI経由時のみ)    |
| データ統制           | AWS基盤準拠            | 契約プラン依存   | Enterprise 強い | Business以上推奨 | GCP基盤準拠              |

### Guardrails Configuration

| 設定項目                | Kiro                                    | Claude Code                   | GitHub Copilot          | Cursor                    | Gemini                    |
| ----------------------- | --------------------------------------- | ----------------------------- | ----------------------- | ------------------------- | ------------------------- |
| 権限設定ファイル        | `.kiro/agents/*.json`                   | `.claude/settings.json`       | `.vscode/settings.json` | `.cursor/settings.json`   | `.gemini/settings.json`   |
| ユーザー権限設定        | `~/.kiro/agents/*.json`                 | `~/.claude/settings.json`     | VS Code User Settings   | `~/.cursor/settings.json` | `~/.gemini/settings.json` |
| ローカル設定 (Git除外)  | -                                       | `.claude/settings.local.json` | -                       | -                         | -                         |
| ツール許可ルール        | `allowedTools` / `toolsSettings`        | `allow` / `deny` リスト       | IDE設定                 | IDE設定                   | sandbox 設定              |
| 管理者設定 (Enterprise) | -                                       | managed policy (JSON)         | Organization policy     | -                         | GCP Organization policy   |

### Configuration Examples

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

**GitHub Copilot** (`.vscode/settings.json`):

```json
{
  "github.copilot.chat.terminal.confirmBeforeRun": true
}
```

### Guidelines

**→ エージェント導入時は以下のセキュリティ設定を必ず行う:**

1. 本番操作は明示承認必須とする (破壊的操作の制限を指示ファイルに明記)
2. `.env` / credentials / secrets へのアクセス制限を定義する
3. 外部へのコード・データ送信ルールを明記する
4. Instructions / Rules は Git 管理し、PR レビュー対象とする
5. 学習利用・データ保持ポリシーを確認し、機密コードが学習に使われないプランを選択する

## Agent Skills

| 比較項目             | Kiro                           | Claude Code                      | GitHub Copilot                   | Cursor                                    | Gemini (CLI)                               |
| -------------------- | ------------------------------ | -------------------------------- | -------------------------------- | ----------------------------------------- | ------------------------------------------ |
| ドキュメント         | [kiro.dev](https://kiro.dev/docs/cli/skills/) | [docs.anthropic.com](https://docs.anthropic.com/en/docs/claude-code/skills) | [docs.github.com](https://docs.github.com/en/copilot/concepts/agents/about-agent-skills) | [docs.cursor.com](https://docs.cursor.com/context/rules) / [Marketplace](https://cursor.com/marketplace) | [geminicli.com](https://geminicli.com/docs/cli/skills/) |
| 定義形式             | Markdown (`SKILL.md`)          | Markdown (`SKILL.md`)            | Markdown (`SKILL.md`)            | MDC (YAML frontmatter + Markdown)         | Markdown (`SKILL.md`)                      |
| 格納パス             | `.kiro/skills/<name>/SKILL.md` | `.claude/skills/<name>/SKILL.md` | `.github/skills/<name>/SKILL.md` | `.cursor/skills/<name>/SKILL.md`          | `.gemini/skills/<name>/SKILL.md`           |
| 代替パス (alias)     | `.agents/skills/<name>/`       | `.agents/skills/<name>/`         | `.agents/skills/<name>/`         | `.agents/skills/<name>/` (⚠️ Rules扱い)    | `.agents/skills/<name>/`                   |
| グローバルスキル     | `~/.kiro/skills/<name>/`       | `~/.claude/skills/<name>/`       | -                                | `~/.cursor/skills/<name>/`                | `~/.gemini/skills/<name>/`                 |
| プロジェクト単位     | ✅                              | ✅                                | ✅                                | ✅                                         | ✅                                          |
| 条件付き適用         | ✅ (ファイルパターン)           | ✅ (`paths` frontmatter)          | ✅                                | ✅ (`globs` frontmatter)                   | ✅ (description ベースで自動活性化)         |
| スラッシュコマンド化 | ✅ (`/skill-name`)              | ✅ (`/skill-name`)                | ✅ (`/skill-name`)                | ⚠️ (`.cursor/skills/` のみ対応)            | ✅ (`/skills` コマンド)                     |
| サブエージェント実行 | ✅                              | ✅ (`context: fork`)              | -                                | ✅ (Background Agents)                     | ✅ (Subagents)                              |
| 動的コンテキスト注入 | -                              | ✅ (`` !`command` `` 構文)        | -                                | -                                         | -                                          |
| 再利用性             | 高い (symlink / submodule)     | 高い (plugin / symlink)          | 高い (symlink / submodule)       | 高い (Marketplace / symlink)              | 高い (git install / `.agents/` alias)      |
| オープンスタンダード | ✅ (Agent Skills)               | ✅ (Agent Skills)                 | ✅ (Agent Skills)                 | ⚠️ (SKILL.md 読込可、独自 Rules 体系併存)  | ✅ (Agent Skills)                           |

> ※ 「Agent Skills」は共通仕様団体による正式標準ではなく、de-facto standard (事実上の共通フォーマット)。ツール間でSKILL.md の大部分を共有可能だが、frontmatter・tool呼び出し・path指定等に差異がある。

### Guidelines

**→ Skill は機能単位で分離し、Git 管理する。**

- レビュー系 / バリデーション系 / Terraform系 / ドキュメント生成系で分割する
- 複数リポジトリで共通のスキルを使いたい場合は Git submodule / 共通リポジトリで横展開する
- Skill の品質 = Agent の出力品質。PR レビュー対象とする
- Agent Skills 対応ツール (Kiro / Claude Code / GitHub Copilot / Gemini CLI) 間では `SKILL.md` の大部分を共有可能 (frontmatter・path指定等に差異あり)

## Agent Hooks

| 比較項目             | Kiro                                             | Claude Code                        | GitHub Copilot             | Cursor                              | Gemini (CLI)                           |
| -------------------- | ------------------------------------------------ | ---------------------------------- | -------------------------- | ----------------------------------- | -------------------------------------- |
| ドキュメント         | [kiro.dev](https://kiro.dev/docs/cli/hooks/) | [docs.anthropic.com](https://docs.anthropic.com/en/docs/claude-code/hooks) | [docs.github.com](https://docs.github.com/en/copilot/concepts/agents/hooks) | [cursor.com](https://cursor.com/docs/hooks) / [Deep Dive](https://blog.gitbutler.com/cursor-hooks-deep-dive) | [geminicli.com](https://geminicli.com/docs/hooks/) |
| Hooks 対応           | ✅                                                | ✅                                  | ✅                          | ✅                                   | ✅                                      |
| 設定ファイル (プロジェクト) | IDE: `.kiro/hooks/*.kiro.hook` / CLI: Agent設定  | `.claude/settings.json`            | `.github/hooks/*.json`     | `.cursor/hooks.json`                | `.gemini/settings.json`                |
| 設定ファイル (ユーザー)    | `~/.kiro/` 配下                                   | `~/.claude/settings.json`          | VS Code User Settings      | `~/.cursor/hooks.json`              | `~/.gemini/settings.json`              |
| イベント種別         | Pre/Post Tool Use, Notification                  | PreToolUse, PostToolUse, Notification | Pre/Post Tool Use          | beforeSubmitPrompt, beforeShellExecution, beforeMCPExecution, beforeReadFile, afterFileEdit, stop | SessionStart/End, BeforeAgent/AfterAgent, BeforeTool/AfterTool, BeforeModel/AfterModel 等 11種 |
| ブロック/拒否        | ✅                                                | ✅                                  | ✅                          | ✅ (`permission: "deny"`)            | ✅ (exit code 2 で System Block)        |
| コンテキスト注入     | ✅                                                | ✅                                  | ⚠️                          | ✅ (`agentMessage` / `userMessage`)  | ✅ (systemMessage)                      |
| プロジェクト単位設定 | ✅                                                | ✅                                  | ✅                          | ✅ (`.cursor/hooks.json`)            | ✅ (`.gemini/settings.json`)            |
| セキュリティ指紋検証 | -                                                | -                                  | -                          | -                                   | ✅ (変更検知で再承認)                    |

### Guidelines

**→ Hooks はエージェントの行動を制御・監査するための重要なセキュリティ機構。**

- ファイル編集後のフォーマッタ/リンター自動実行に活用する
- 破壊的コマンド (rm -rf, git push --force 等) のブロックに活用する
- 機密ファイル読み取りの検知・防止に活用する
- 監査ログ記録で agent の行動を追跡可能にする
- Gemini CLI は最も多くのフックイベント (11種) を提供し、きめ細かい制御が可能

## Agent Instructions (Steering)

| 比較項目       | Kiro                                    | Claude Code                     | GitHub Copilot                    | Cursor                            | Gemini (CLI)                            |
| -------------- | --------------------------------------- | ------------------------------- | --------------------------------- | --------------------------------- | --------------------------------------- |
| ドキュメント   | [kiro.dev](https://kiro.dev/docs/cli/steering/) | [docs.anthropic.com](https://docs.anthropic.com/en/docs/claude-code/memory) | [docs.github.com](https://docs.github.com/en/copilot/how-tos/copilot-on-github/customize-copilot/add-custom-instructions/add-repository-instructions) | [cursor.com](https://cursor.com/ja/docs/rules) | [geminicli.com](https://geminicli.com/docs/cli/gemini-md/) |
| 格納パス       | `.kiro/steering/*.md`                   | `CLAUDE.md` / `<dir>/CLAUDE.md` | `.github/copilot-instructions.md` | `.cursorrules` / `.cursor/rules/` | `GEMINI.md` / `.gemini/GEMINI.md`       |
| 階層的指示     | ✅ (複数ファイル分割)                    | ✅ (ディレクトリ階層で継承)      | ⚠️ 単一ファイル中心                | ✅ (複数ファイル)                  | ✅ (Global → Project → Subdir で継承)    |
| グローバル指示 | `~/.kiro/steering/`                     | `~/.claude/CLAUDE.md`           | VS Code User Settings             | `~/.cursor/rules/`                | `~/.gemini/GEMINI.md`                   |
| 適用優先度     | Global → Project (Project優先)          | Global → Root → Subdir          | Single / IDE設定                  | Global → Project                  | Global → Project → Subdir (全連結)      |
| 形式           | Markdown                                | Markdown                        | Markdown                          | Markdown (MDC)                    | Markdown                                |

### Guidelines

**→ Instructions はプロジェクトのコーディング規約・アーキテクチャ方針を記述し、Git 管理する。**

- 全エージェントで共通の指示内容 (コーディングスタイル、セキュリティルール等) を定義する
- 複数エージェントを併用する場合は、各ツールの指示ファイルに同等の内容を記載するか、共通ファイルから生成する仕組みを検討する
- 指示が肥大化するとコンテキストウィンドウを圧迫するため、簡潔に保つ
- Agent Skills オープンスタンダード対応ツール間では Instructions の記述方針を統一しやすい

## 今後の改善候補

> 本ドキュメントを「ツール比較」から「Agent Architecture Comparison」へ昇華させるための検討事項。

| 優先度 | 改善内容                                      | 概要                                                                                     |
| ------ | --------------------------------------------- | ---------------------------------------------------------------------------------------- |
| 高     | MCP 比較章の追加                              | stdio/HTTP・OAuth・Remote MCP・Registry・Approval Model 等の差異を比較                   |
| 高     | Agent 定義章の追加                            | Sub Agent・Agent Routing・Agent Marketplace の比較                                       |
| 中     | Instructions / Skills / Hooks / MCP / Agent 責務整理 | 何を守るか / どう実行するか / 強制する / 外部能力 / 誰が実行するか の対応表             |
| 中     | 事実と評価の分離                              | Objective Comparison (事実) と Opinionated Assessment (筆者評価) を明示的に分ける         |
| 低     | Guardrails → Agent Governance 再構成          | Permissions / Guardrails / Hooks / Audit を上位概念で統合                                |
