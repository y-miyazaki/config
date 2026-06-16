<!-- omit in toc -->
# Tool Comparison Matrix (AI Agent)

AI Agent / コーディングアシスタントに特化したツール選定の判断材料。

<!-- omit in toc -->
## History

| 日付       | 内容                                                                 |
| ---------- | -------------------------------------------------------------------- |
| 2026-06-16 | ツール並び順を A-Z 順に統一                                          |
| 2026-06-06 | markdown-link-check hooks 動作確認用にドキュメントを更新。             |
| 2026-06-06 | Gemini CLI → Antigravity に移行。IDE/CLI設定パスの分離を明確化。copilot-instructions.md設計方針を反映 |
| 2026-06-05 | GitHub Copilot 6月課金モデル変更 (AI Credits制) 反映、Cursor/Gemini情報修正、Agent Hooks セクション追加 |
| 2026-05-21 | History セクション追加                                               |
| 2026-05-12 | 初版作成。Kiro / Claude Code / GitHub Copilot / Cursor / Gemini を比較 |

<!-- omit in toc -->
## Table of Contents

- [Coding Agent: Antigravity vs Claude Code vs Cursor vs GitHub Copilot vs Kiro](#coding-agent-antigravity-vs-claude-code-vs-cursor-vs-github-copilot-vs-kiro)
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

## Coding Agent: Antigravity vs Claude Code vs Cursor vs GitHub Copilot vs Kiro

| 比較項目           | Antigravity                | Claude Code           | Cursor                    | GitHub Copilot         | Kiro            |
| ------------------ | -------------------------- | --------------------- | ------------------------- | ---------------------- | --------------- |
| 提供元             | Google DeepMind            | Anthropic             | Anysphere                 | GitHub (Microsoft)     | AWS             |
| リポジトリ         | -                          | -                     | -                         | -                      | -               |
| ドキュメント       | [antigravity.google](https://antigravity.google/docs) | [docs.anthropic.com](https://docs.anthropic.com/en/docs/claude-code) | [docs.cursor.com](https://docs.cursor.com) | [docs.github.com](https://docs.github.com/en/copilot) | [kiro.dev/docs/cli](https://kiro.dev/docs/cli) |
| ライセンス         | 商用                       | 商用                  | 商用                      | 商用                   | 商用            |
| 動作形態           | IDE / CLI                  | IDE / CLI             | AIネイティブIDE           | IDE / CLI              | IDE / CLI       |
| エージェントモード | ✅                          | ✅                     | ✅                         | ✅                      | ✅               |
| マルチファイル編集 | ✅                          | ✅                     | ✅                         | ✅                      | ✅               |
| ターミナル実行     | ✅                          | ✅                     | ✅                         | ✅                      | ✅               |
| MCP 対応           | ✅                          | ✅                     | ✅                         | ✅                      | ✅               |
| AWS 統合           | ❌                          | ❌                     | ❌                         | ⚠️ 一部連携             | ✅ (ネイティブ)  |
| GCP 統合           | ✅ (ネイティブ)             | ❌                     | ❌                         | ⚠️ 一部連携             | ❌               |
| セルフホスト / VPC | ⚠️ (GCP Enterprise)         | ❌                     | ❌                         | ⚠️ (Enterprise構成次第) | ✅ (AWS環境連携) |
| CLI 自動化適性     | ✅ (agy コマンド)            | ✅ 非常に強い          | ⚠️ 中程度                  | ⚠️ 中程度               | ✅               |
| 大規模導入適性     | ✅ (Google Cloud組織)       | ✅ (Team / Enterprise) | ✅ (Business / Enterprise) | ✅ 非常に強い           | ⚠️ 今後拡大      |
| コンテキスト窓     | 1M+ tokens                 | 200K tokens           | 128K〜200K tokens         | 128K〜200K tokens      | 200K tokens      |
| モデル選択         | Gemini 系中心 (実験的に Gemma) | Claude 系のみ          | ✅ 複数 (GPT-5, Claude等)  | ✅ 複数 (GPT-5, Claude等) | ✅ (Auto / 手動)  |
| データ学習利用     | ❌ 利用しない               | ❌ 利用しない          | ❌ (Business以上)          | ❌ (Business以上)        | ❌ 利用しない     |
| コンプライアンス   | SOC2 / ISO / GCP準拠       | SOC2                  | SOC2                      | SOC2 / FedRAMP          | SOC2 / AWS準拠   |

### Pricing

> ※ 2026-06-01 より GitHub Copilot は「リクエストベース」から「AI Credits (トークンベース)」課金に移行。1 AI credit = $0.01 USD。モデル選択とトークン消費量で実コストが大きく変動するため、月額はあくまで基本料金+含まれるクレジット枠の目安。
> ※ Gemini CLI は 2026-06-18 にサービス停止。後継は Antigravity CLI (`agy`)。設定パスは `~/.gemini/` を引き続き使用し互換性あり。

| プラン       | Antigravity                   | Claude Code                       | Cursor                | GitHub Copilot                          | Kiro                         |
| ------------ | ----------------------------- | --------------------------------- | --------------------- | --------------------------------------- | ---------------------------- |
| 料金ページ   | [antigravity.google/pricing](https://antigravity.google/pricing) | [anthropic.com/pricing](https://www.anthropic.com/pricing) | [cursor.com/pricing](https://www.cursor.com/pricing) | [github.com/features/copilot](https://github.com/features/copilot#pricing) | [kiro.dev/pricing](https://kiro.dev/pricing) |
| 無料枠       | ❌ (廃止予定)                  | ❌                                 | ✅ (Hobby: Agent限定利用+Tab限定) | ✅ (Free: 限定 AI Credits / コード補完は無制限) | 50 クレジット/月             |
| 個人 (標準)  | Google AI Pro: $20/月          | Pro: $20/月                       | Pro: $20/月           | Pro: $10/月 (1,500 credits含む)         | Pro: $20/月                  |
| 個人 (上位)  | Ultra: $100/月 (5x), Ultra+: $200/月 (20x) | Max 5x: $100/月, Max 20x: $200/月 | Pro+: $60/月, Ultra: $200/月 | Pro+: $39/月 (7,000 credits), Max: $100/月 (20,000 credits) | Pro+: $40/月, Power: $200/月 |
| チーム/組織  | Standard: 時間課金            | Team: $25/seat/月, Premium: $125/seat/月 | Teams Standard: $40/seat/月, Premium: $120/seat/月 | Business: $19/user/月 (1,900 credits/user, プール型) | 今後拡張                     |
| Enterprise   | Enterprise: カスタム          | Enterprise: カスタム              | Enterprise: カスタム  | Enterprise: $39/user/月 (3,900 credits/user, プール型) | 今後拡張                     |
| 従量追加課金 | ⚠️ GCP課金連携                 | ⚠️ API利用時あり                   | ⚠️ usage 条件あり      | ✅ 超過時 $0.01/credit で追加課金 (予算上限設定可) | ✅ 超過時 $0.04/credit で追加課金 (opt-in) |

### Billing Model

> ※ GitHub Copilot は 2026-06-01 より全プラン AI Credits 制に移行。旧「premium requests」は廃止 (legacy)。

| 項目               | Antigravity                   | Claude Code                 | Cursor                         | GitHub Copilot                                   | Kiro                     |
| ------------------ | ----------------------------- | --------------------------- | ------------------------------ | ------------------------------------------------ | ------------------------ |
| 基本課金           | 無料枠 + サブスク             | サブスク枠 (定額内トークン) | サブスク + usage制限           | サブスク + AI Credits (トークン従量)              | サブスク + クレジット枠  |
| クレジット単価     | -                             | -                           | -                              | 1 AI credit = $0.01 USD                          | $0.04/credit (超過時)    |
| 含まれるクレジット | -                             | -                           | -                              | Pro: 1,500/月, Pro+: 7,000/月, Max: 20,000/月    | Pro: 1,000/月, Pro+: 2,000/月, Power: 10,000/月 |
| 組織プールモデル   | -                             | -                           | -                              | ✅ (user単位クレジットを組織全体でプール共有)      | -                        |
| 超過時の挙動       | レート制限                    | レート制限 / 上位プラン誘導 | 制限 or 追加課金               | 予算設定に基づき追加課金 or ブロック              | $0.04/credit 追加課金 (opt-in) |
| モデル選択         | Gemini 系中心 (2.5 Pro/Flash) | Claude 系中心               | ✅ 複数モデル (GPT-5, Claude等) | ✅ 複数モデル (GPT-5, Claude, Gemini等)           | ✅ (Auto / 手動)          |
| モデルによる料金差 | プラン内定額                  | プラン内定額                | モデルにより消費が異なる       | モデル×トークン数で credit 消費が大きく異なる     | クレジット消費量が異なる |
| Code Completions   | -                             | -                           | -                              | AI Credits 消費なし (Freeを含む全プランで無制限)  | -                        |
| 年額割引           | ✅ (年額プランあり)            | ✅ ($17/月相当)              | ✅ ($192/年 = Pro)              | ✅ (年額プランあり、旧request-baseは legacy扱い)  | 不明 / 今後次第          |

### Configuration Files and Directories

| 用途                | Antigravity                     | Claude Code                      | Cursor                            | GitHub Copilot                    | Kiro                           |
| ------------------- | ------------------------------- | -------------------------------- | --------------------------------- | --------------------------------- | ------------------------------ |
| Steering (指示)     | `GEMINI.md`                     | `CLAUDE.md` / `.claude/rules/*.md` | `.cursorrules` / `.cursor/rules/` | `.github/copilot-instructions.md` / `.github/instructions/*.instructions.md` | `.kiro/steering/*.md`          |
| AGENTS.md (共通)    | ✅ 読込                          | ✅ (`@AGENTS.md` import推奨)     | ✅ 読込                            | ✅ 読込                            | ✅ 読込                         |
| Skills (スキル)     | `.agents/skills/<name>/SKILL.md`  | `.claude/skills/<name>/SKILL.md` | `.cursor/skills/<name>/SKILL.md`      | `.github/skills/<name>/SKILL.md`  | `.kiro/skills/<name>/SKILL.md` |
| MCP 設定            | `.agents/mcp_config.json`       | `.mcp.json`                      | `.cursor/mcp.json`                | `.github/mcp.json` / `.mcp.json`  | `.kiro/settings/mcp.json`      |
| MCP 設定 (IDE)      | -                                       | -                                | -                                 | `.vscode/mcp.json`                | -                              |
| Hooks 設定          | `.gemini/antigravity-cli/settings.json` 内 `hooks` | `.claude/settings.json` 内 `hooks` | `.cursor/hooks.json` (プロジェクト) / `~/.cursor/hooks.json` (ユーザー) | `.github/hooks/*.json`            | IDE: `.kiro/hooks/*.kiro.hook` / CLI: Agent設定内 `hooks` フィールド |
| Agent 定義          | -                               | `.claude/agents/`                | ⚠️ 独自UI管理                      | `.github/agents/*.md`             | `.kiro/agents/`                |
| プロンプト          | Custom commands                 | `.claude/commands/` (レガシー)   | -                                 | `.github/prompts/`                | `.kiro/prompts/`               |
| プロジェクト設定    | `.gemini/antigravity-cli/settings.json` | `.claude/settings.json`          | `.cursor/settings.json`           | `.github/copilot/settings.json`   | `.kiro/agents/*.json`          |
| ユーザー設定        | `~/.gemini/`                    | `~/.claude/`                     | `~/.cursor/`                      | `~/.copilot/`                     | `~/.kiro/`                     |

### Guidelines

**→ 技術スタック / 組織要件 / セキュリティ要件 / 開発速度で選択する。**

- AWS 中心開発 / IAM / 組織統制重視 → **Kiro**
- CLI 中心 / 自動化 / 高品質対話 → **Claude Code**
- GitHub / PRレビュー / 開発標準化 → **GitHub Copilot**
- IDE 内完結 / 高速開発体験 → **Cursor**
- GCP 中心開発 / Vertex AI 連携 → **Antigravity**
- 複数ツール併用前提の探索環境 → **Kiro + Claude Code + Copilot** など併用
- コスト最小で始めたい → GitHub Copilot (Free) または Cursor (Hobby)
- 大量利用 → Kiro Power ($200/月) または Claude Code Max 20x ($200/月) または Copilot Max ($100/月, 20,000 credits)
- コスト予測性重視 → Claude Code (定額内) または Kiro (クレジット制)。Copilot は AI Credits 制でモデル・用途次第で変動大

## Agent Security: Guardrails

| 比較項目             | Antigravity              | Claude Code      | Cursor           | GitHub Copilot  | Kiro                   |
| -------------------- | ------------------------ | ---------------- | ---------------- | --------------- | ---------------------- |
| 破壊的操作の制御     | ✅ 確認あり               | ✅ permissions    | ⚠️ 一部           | ✅ 確認あり      | ✅ 承認制               |
| ファイルアクセス制御 | ⚠️ 限定的                 | ✅ deny パターン  | ⚠️ IDE依存        | ⚠️ IDE依存       | ✅                      |
| シークレット保護     | ✅                        | ✅                | ⚠️                | ✅               | ✅                      |
| ネットワーク制御     | ⚠️                        | ✅                | ⚠️                | ⚠️               | ✅                      |
| コマンド実行制御     | ✅ (sandbox)              | ✅ (permissions)  | ⚠️                | ✅               | ✅ (allowlist/denylist) |
| 監査ログ             | ⚠️ (Vertex AI経由時のみ)    | ⚠️ セッション中心 | ⚠️                | ✅ Enterprise    | ⚠️ セッション中心       |
| データ統制           | GCP基盤準拠              | 契約プラン依存   | Business以上推奨 | Enterprise 強い | AWS基盤準拠            |

### Guardrails Configuration

| 設定項目                | Antigravity               | Claude Code                   | Cursor                    | GitHub Copilot          | Kiro                                    |
| ----------------------- | ------------------------- | ----------------------------- | ------------------------- | ----------------------- | --------------------------------------- |
| 権限設定ファイル        | `.gemini/antigravity-cli/settings.json` | `.claude/settings.json`       | `.cursor/settings.json`   | `.github/copilot/settings.json` | `.kiro/agents/*.json`                   |
| ユーザー権限設定        | `~/.gemini/antigravity-cli/settings.json` | `~/.claude/settings.json`     | `~/.cursor/settings.json` | `~/.copilot/settings.json`      | `~/.kiro/agents/*.json`                 |
| ローカル設定 (Git除外)  | -                         | `.claude/settings.local.json` | -                   | `.github/copilot/settings.local.json` | -                                       |
| ツール許可ルール        | sandbox 設定              | `allow` / `deny` リスト       | `permissions-config.json` | `permissions-config.json`       | `allowedTools` / `toolsSettings`        |
| 管理者設定 (Enterprise) | GCP Organization policy   | managed policy (JSON)         | -                         | Organization policy     | -                                       |

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

**GitHub Copilot** (`.github/copilot/settings.json`):

```json
{
  "hooks": {
    "pre-tool-use": [{ "event": "Bash", "command": "echo 'confirm'" }]
  }
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

| 比較項目             | Antigravity                                | Claude Code                      | Cursor                                    | GitHub Copilot                   | Kiro                           |
| -------------------- | ------------------------------------------ | -------------------------------- | ----------------------------------------- | -------------------------------- | ------------------------------ |
| ドキュメント         | [antigravity.google](https://antigravity.google/docs/skills) | [docs.anthropic.com](https://docs.anthropic.com/en/docs/claude-code/skills) | [docs.cursor.com](https://docs.cursor.com/context/rules) / [Marketplace](https://cursor.com/marketplace) | [docs.github.com](https://docs.github.com/en/copilot/concepts/agents/about-agent-skills) | [kiro.dev](https://kiro.dev/docs/cli/skills/) |
| 定義形式             | Markdown (`SKILL.md`)                      | Markdown (`SKILL.md`)            | MDC (YAML frontmatter + Markdown)         | Markdown (`SKILL.md`)            | Markdown (`SKILL.md`)          |
| 格納パス             | `.agents/skills/<name>/SKILL.md`           | `.claude/skills/<name>/SKILL.md` | `.cursor/skills/<name>/SKILL.md`          | `.github/skills/<name>/SKILL.md` | `.kiro/skills/<name>/SKILL.md` |
| 代替パス (alias)     | `.agents/skills/<name>/`                   | `.agents/skills/<name>/`         | `.agents/skills/<name>/` (⚠️ Rules扱い)    | `.agents/skills/<name>/`         | `.agents/skills/<name>/`       |
| グローバルスキル     | `~/.gemini/skills/<name>/`                 | `~/.claude/skills/<name>/`       | `~/.cursor/skills/<name>/`                | -                                | `~/.kiro/skills/<name>/`       |
| プロジェクト単位     | ✅                                          | ✅                                | ✅                                         | ✅                                | ✅                              |
| 条件付き適用         | ✅ (description ベースで自動活性化)         | ✅ (`paths` frontmatter)          | ✅ (`globs` frontmatter)                   | ✅                                | ✅ (ファイルパターン)           |
| スラッシュコマンド化 | ✅ (`/skills` コマンド)                     | ✅ (`/skill-name`)                | ⚠️ (`.cursor/skills/` のみ対応)            | ✅ (`/skill-name`)                | ✅ (`/skill-name`)              |
| サブエージェント実行 | ✅ (Subagents)                              | ✅ (`context: fork`)              | ✅ (Background Agents)                     | -                                | ✅                              |
| 動的コンテキスト注入 | -                                          | ✅ (`` !`command` `` 構文)        | -                                         | -                                | -                              |
| 再利用性             | 高い (git install / `.agents/` alias)      | 高い (plugin / symlink)          | 高い (Marketplace / symlink)              | 高い (symlink / submodule)       | 高い (symlink / submodule)     |
| オープンスタンダード | ✅ (Agent Skills)                           | ✅ (Agent Skills)                 | ⚠️ (SKILL.md 読込可、独自 Rules 体系併存)  | ✅ (Agent Skills)                 | ✅ (Agent Skills)               |

> ※ 「Agent Skills」は共通仕様団体による正式標準ではなく、de-facto standard (事実上の共通フォーマット)。ツール間でSKILL.md の大部分を共有可能だが、frontmatter・tool呼び出し・path指定等に差異がある。

### Guidelines

**→ Skill は機能単位で分離し、Git 管理する。**

- レビュー系 / バリデーション系 / Terraform系 / ドキュメント生成系で分割する
- 複数リポジトリで共通のスキルを使いたい場合は Git submodule / 共通リポジトリで横展開する
- Skill の品質 = Agent の出力品質。PR レビュー対象とする
- Agent Skills 対応ツール (Kiro / Claude Code / GitHub Copilot / Antigravity) 間では `SKILL.md` の大部分を共有可能 (frontmatter・path指定等に差異あり)

## Agent Hooks

| 比較項目             | Antigravity                            | Claude Code                        | Cursor                              | GitHub Copilot             | Kiro                                             |
| -------------------- | -------------------------------------- | ---------------------------------- | ----------------------------------- | -------------------------- | ------------------------------------------------ |
| ドキュメント         | [antigravity.google](https://antigravity.google/docs/hooks) | [docs.anthropic.com](https://docs.anthropic.com/en/docs/claude-code/hooks) | [cursor.com](https://cursor.com/docs/hooks) / [Deep Dive](https://blog.gitbutler.com/cursor-hooks-deep-dive) | [docs.github.com](https://docs.github.com/en/copilot/concepts/agents/hooks) | [kiro.dev](https://kiro.dev/docs/cli/hooks/) |
| Hooks 対応           | ✅                                      | ✅                                  | ✅                                   | ✅                          | ✅                                                |
| 設定ファイル (プロジェクト) | `.gemini/antigravity-cli/settings.json`  | `.claude/settings.json`            | `.cursor/hooks.json`                | `.github/hooks/*.json`     | IDE: `.kiro/hooks/*.kiro.hook` / CLI: Agent設定  |
| 設定ファイル (ユーザー)    | `~/.gemini/antigravity-cli/settings.json`  | `~/.claude/settings.json`          | `~/.cursor/hooks.json`              | `~/.copilot/settings.json`   | `~/.kiro/` 配下                                   |
| 設定ファイル (IDE)         | -                                      | -                                  | -                                   | VS Code User Settings        | `.kiro/hooks/*.kiro.hook`                         |
| イベント種別         | PreToolUse, PostToolUse, PreInvocation, PostInvocation, Stop の 5 種 | PreToolUse, PostToolUse, Notification | beforeSubmitPrompt, beforeShellExecution, beforeMCPExecution, beforeReadFile, afterFileEdit, stop | Pre/Post Tool Use          | Pre/Post Tool Use, Notification                  |
| ブロック/拒否        | ✅ (exit code 2 で System Block)        | ✅                                  | ✅ (`permission: "deny"`)            | ✅                          | ✅                                                |
| コンテキスト注入     | ✅ (systemMessage)                      | ✅                                  | ✅ (`agentMessage` / `userMessage`)  | ⚠️                          | ✅                                                |
| プロジェクト単位設定 | ✅ (`.gemini/antigravity-cli/settings.json`) | ✅                                  | ✅ (`.cursor/hooks.json`)            | ✅                          | ✅                                                |
| セキュリティ指紋検証 | ✅ (変更検知で再承認)                    | -                                  | -                                   | -                          | -                                                |

### Guidelines

**→ Hooks はエージェントの行動を制御・監査するための重要なセキュリティ機構。**

- ファイル編集後のフォーマッタ/リンター自動実行に活用する
- 破壊的コマンド (rm -rf, git push --force 等) のブロックに活用する
- 機密ファイル読み取りの検知・防止に活用する
- 監査ログ記録で agent の行動を追跡可能にする
- Antigravity は最も多くのフックイベント (11種) を提供し、きめ細かい制御が可能

## Agent Instructions (Steering)

| 比較項目       | Antigravity                             | Claude Code                     | Cursor                            | GitHub Copilot                    | Kiro                                    |
| -------------- | --------------------------------------- | ------------------------------- | --------------------------------- | --------------------------------- | --------------------------------------- |
| ドキュメント   | [antigravity.google](https://antigravity.google/docs/gemini-md) | [docs.anthropic.com](https://docs.anthropic.com/en/docs/claude-code/memory) | [cursor.com](https://cursor.com/ja/docs/rules) | [docs.github.com](https://docs.github.com/en/copilot/how-tos/copilot-on-github/customize-copilot/add-custom-instructions/add-repository-instructions) | [kiro.dev](https://kiro.dev/docs/cli/steering/) |
| 格納パス (全体)  | `GEMINI.md` / `AGENTS.md`              | `CLAUDE.md` / `.claude/CLAUDE.md` | `.cursorrules` / `.cursor/rules/` | `.github/copilot-instructions.md` | `.kiro/steering/*.md`                   |
| 格納パス (パス固有) | -                                       | `.claude/rules/*.md` (paths frontmatter) | `.cursor/rules/*.md` (globs frontmatter) | `.github/instructions/*.instructions.md` (applyTo frontmatter) | -                                    |
| 階層的指示     | ✅ (Global → Project → Subdir で継承)    | ✅ (ディレクトリ階層で継承)      | ✅ (複数ファイル)                  | ⚠️ 単一ファイル中心                | ✅ (複数ファイル分割)                    |
| グローバル指示 | `~/.gemini/GEMINI.md`                   | `~/.claude/CLAUDE.md`           | `~/.cursor/rules/`                | `~/.copilot/copilot-instructions.md`  | `~/.kiro/steering/`                     |
| 適用優先度     | Global → Project → Subdir (全連結)      | Global → Root → Subdir          | Global → Project                  | Global → Repo-wide → Path-specific | Global → Project (Project優先)          |
| 適用優先度 (IDE) | -                                       | -                               | -                                 | VS Code User Settings → Repo   | -                                      |
| 形式           | Markdown                                | Markdown                        | Markdown (MDC)                    | Markdown                          | Markdown                                |

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
