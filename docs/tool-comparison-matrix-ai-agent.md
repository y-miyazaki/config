<!-- omit in toc -->
# Tool Comparison Matrix (AI Agent)

AI Agent / コーディングアシスタントに特化したツール選定の判断材料。

<!-- omit in toc -->
## Table of Contents

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
- [Agent Instructions](#agent-instructions)
  - [Guidelines](#guidelines-3)

## Coding Agent: Kiro vs Claude Code vs GitHub Copilot vs Cursor vs Gemini

| 比較項目           | Kiro            | Claude Code           | GitHub Copilot         | Cursor                    | Gemini                     |
| ------------------ | --------------- | --------------------- | ---------------------- | ------------------------- | -------------------------- |
| 提供元             | AWS             | Anthropic             | GitHub (Microsoft)     | Anysphere                 | Google                     |
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
| モデル選択         | ✅ (Auto / 手動)  | Claude 系のみ          | ✅ 複数 (GPT-5, Claude等) | ✅ 複数 (GPT-5, Claude等)  | Gemini 系のみ              |
| データ学習利用     | ❌ 利用しない     | ❌ 利用しない          | ❌ (Business以上)        | ❌ (Business以上)          | ❌ 利用しない               |
| コンプライアンス   | SOC2 / AWS準拠   | SOC2                  | SOC2 / FedRAMP          | SOC2                      | SOC2 / ISO / GCP準拠       |

### Pricing

> ※ 価格は変動しやすいため参考値。契約通貨・地域・キャンペーンで差異あり。

| プラン       | Kiro                         | Claude Code                       | GitHub Copilot               | Cursor                | Gemini                        |
| ------------ | ---------------------------- | --------------------------------- | ---------------------------- | --------------------- | ----------------------------- |
| 無料枠       | 50 クレジット/月             | ❌                                 | ✅ (50 premium requests/月)   | ✅ (2,000 completions) | ✅ (個人無料、日次クォータあり) |
| 個人 (標準)  | Pro: $20/月                  | Pro: $20/月                       | Pro: $10/月                  | Pro: $20/月           | Google Dev Program: $24.99/月 |
| 個人 (上位)  | Pro+: $40/月, Power: $200/月 | Max 5x: $100/月, Max 20x: $200/月 | Pro+: $39/月                 | Pro+: $60/月          | -                             |
| チーム/組織  | 今後拡張                     | Team: $25/seat/月, Premium: $125/seat/月 | Business: $19/user/月        | Business: $40/user/月 | Standard: 時間課金            |
| Enterprise   | 今後拡張                     | Enterprise: カスタム              | Enterprise: $39/user/月      | Enterprise: カスタム  | Enterprise: カスタム          |
| 従量追加課金 | ⚠️ あり得る                   | ⚠️ API利用時あり                   | ✅ usage-based ($0.01/credit) | ⚠️ usage 条件あり      | ⚠️ GCP課金連携                 |

### Billing Model

| 項目               | Kiro                     | Claude Code                 | GitHub Copilot                   | Cursor                         | Gemini                        |
| ------------------ | ------------------------ | --------------------------- | -------------------------------- | ------------------------------ | ----------------------------- |
| 基本課金           | サブスク + クレジット枠  | サブスク枠 (定額内トークン) | サブスク + usage-based           | サブスク + usage制限           | 無料枠 + サブスク             |
| 超過時の挙動       | 追加購入 or 待機         | レート制限 / 上位プラン誘導 | 追加課金 or 制限                 | 制限 or 追加課金               | レート制限                    |
| モデル選択         | ✅ (Auto / 手動)          | Claude 系中心               | ✅ 複数モデル (GPT-5, Claude等)   | ✅ 複数モデル (GPT-5, Claude等) | Gemini 系中心 (2.5 Pro/Flash) |
| モデルによる料金差 | クレジット消費量が異なる | プラン内定額                | モデルにより credit 消費が異なる | モデルにより消費が異なる       | プラン内定額                  |
| 年額割引           | 不明 / 今後次第          | ✅ ($17/月相当)              | ✅ ($390/年 = Pro+)               | ✅ ($192/年 = Pro)              | ✅ (年額プランあり)            |

### Configuration Files and Directories

| 用途                | Kiro                           | Claude Code                      | GitHub Copilot                    | Cursor                            | Gemini                  |
| ------------------- | ------------------------------ | -------------------------------- | --------------------------------- | --------------------------------- | ----------------------- |
| Instructions (指示) | `.kiro/instructions/*.md`      | `CLAUDE.md` / `<dir>/CLAUDE.md`  | `.github/copilot-instructions.md` | `.cursorrules` / `.cursor/rules/` | `GEMINI.md`             |
| Skills (スキル)     | `.kiro/skills/<name>/SKILL.md` | `.claude/skills/<name>/SKILL.md` | `.github/skills/<name>/SKILL.md`  | `.cursor/rules/*.md`              | ⚠️ 独自機能中心          |
| MCP 設定            | `.kiro/mcp.json`               | `.mcp.json`                      | `.vscode/mcp.json`                | `.cursor/mcp.json`                | `.gemini/settings.json` |
| Agent 定義          | `.kiro/agents/`                | `.claude/agents/`                | `.github/copilot-agents.yml`      | ⚠️ 独自UI管理                      | -                       |
| プロンプト          | `.kiro/prompts/`               | `.claude/commands/` (レガシー)   | `.github/prompts/`                | -                                 | -                       |
| プロジェクト設定    | `.kiro/settings.json`          | `.claude/settings.json`          | `.vscode/settings.json`           | `.cursor/settings.json`           | `.gemini/settings.json` |
| ユーザー設定        | `~/.local/share/kiro-cli/`     | `~/.claude/`                     | VS Code User Settings             | `~/.cursor/`                      | `~/.gemini/`            |

### Guidelines

**→ 技術スタック / 組織要件 / セキュリティ要件 / 開発速度で選択する。**

- AWS 中心開発 / IAM / 組織統制重視 → **Kiro**
- CLI 中心 / 自動化 / 高品質対話 → **Claude Code**
- GitHub / PRレビュー / 開発標準化 → **GitHub Copilot**
- IDE 内完結 / 高速開発体験 → **Cursor**
- GCP 中心開発 / 無料枠で始めたい → **Gemini**
- 複数ツール併用前提の探索環境 → **Kiro + Claude Code + Copilot** など併用
- コスト最小で始めたい → Gemini (個人無料) または GitHub Copilot (Free)
- 大量利用 → Kiro Power ($200/月) または Claude Code Max 20x ($200/月)

## Agent Security: Guardrails

| 比較項目             | Kiro                   | Claude Code      | GitHub Copilot  | Cursor           | Gemini                   |
| -------------------- | ---------------------- | ---------------- | --------------- | ---------------- | ------------------------ |
| 破壊的操作の制御     | ✅ 承認制               | ✅ permissions    | ✅ 確認あり      | ⚠️ 一部           | ✅ 確認あり               |
| ファイルアクセス制御 | ✅                      | ✅ deny パターン  | ⚠️ IDE依存       | ⚠️ IDE依存        | ⚠️ 限定的                 |
| シークレット保護     | ✅                      | ✅                | ✅               | ⚠️                | ✅                        |
| ネットワーク制御     | ✅                      | ✅                | ⚠️               | ⚠️                | ⚠️                        |
| コマンド実行制御     | ✅ (allowlist/denylist) | ✅ (permissions)  | ✅               | ⚠️                | ✅ (sandbox)              |
| 監査ログ             | ⚠️ セッション中心       | ⚠️ セッション中心 | ✅ Enterprise    | ⚠️                | ✅ (GCP Cloud Audit Logs) |
| データ統制           | AWS基盤準拠            | 契約プラン依存   | Enterprise 強い | Business以上推奨 | GCP基盤準拠              |

### Guardrails Configuration

| 設定項目                | Kiro                                    | Claude Code                   | GitHub Copilot          | Cursor                    | Gemini                    |
| ----------------------- | --------------------------------------- | ----------------------------- | ----------------------- | ------------------------- | ------------------------- |
| 権限設定ファイル        | `.kiro/settings.json`                   | `.claude/settings.json`       | `.vscode/settings.json` | `.cursor/settings.json`   | `.gemini/settings.json`   |
| ユーザー権限設定        | `~/.local/share/kiro-cli/settings.json` | `~/.claude/settings.json`     | VS Code User Settings   | `~/.cursor/settings.json` | `~/.gemini/settings.json` |
| ローカル設定 (Git除外)  | `.kiro/settings.local.json`             | `.claude/settings.local.json` | -                       | -                         | -                         |
| ツール許可ルール        | `allow` / `deny` リスト                 | `allow` / `deny` リスト       | IDE設定                 | IDE設定                   | sandbox 設定              |
| 管理者設定 (Enterprise) | -                                       | managed policy (JSON)         | Organization policy     | -                         | GCP Organization policy   |

### Configuration Examples

**Kiro** (`.kiro/settings.json`):

```json
{
  "tools": {
    "allow": ["read", "write", "shell(npm test *)"],
    "deny": ["shell(rm -rf *)", "shell(git push --force *)"]
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
  "github.copilot.chat.agent.tools": {
    "terminal": { "confirmBeforeRun": true }
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

| 比較項目             | Kiro                           | Claude Code                      | GitHub Copilot                   | Cursor                  | Gemini         |
| -------------------- | ------------------------------ | -------------------------------- | -------------------------------- | ----------------------- | -------------- |
| 定義形式             | Markdown (`SKILL.md`)          | Markdown (`SKILL.md`)            | Markdown (`SKILL.md`)            | Markdown                | ⚠️ 独自機能中心 |
| 格納パス             | `.kiro/skills/<name>/SKILL.md` | `.claude/skills/<name>/SKILL.md` | `.github/skills/<name>/SKILL.md` | `.cursor/rules/*.md`    | -              |
| グローバルスキル     | -                              | `~/.claude/skills/<name>/`       | -                                | `~/.cursor/rules/`      | -              |
| プロジェクト単位     | ✅                              | ✅                                | ✅                                | ✅                       | ⚠️              |
| 条件付き適用         | ✅ (ファイルパターン)           | ✅ (`paths` frontmatter)          | ✅                                | ⚠️                       | ⚠️              |
| スラッシュコマンド化 | ✅ (`/skill-name`)              | ✅ (`/skill-name`)                | ✅ (`/skill-name`)                | ⚠️                       | ⚠️              |
| サブエージェント実行 | ✅                              | ✅ (`context: fork`)              | -                                | -                       | -              |
| 動的コンテキスト注入 | -                              | ✅ (`` !`command` `` 構文)        | -                                | -                       | -              |
| 再利用性             | 高い (symlink / submodule)     | 高い (plugin / symlink)          | 高い (symlink / submodule)       | 中程度 (ファイルコピー) | 中程度         |
| オープンスタンダード | ✅ (Agent Skills)               | ✅ (Agent Skills)                 | ✅ (Agent Skills)                 | ❌                       | ❌              |

### Guidelines

**→ Skill は機能単位で分離し、Git 管理する。**

- レビュー系 / バリデーション系 / Terraform系 / ドキュメント生成系で分割する
- 複数リポジトリで共通のスキルを使いたい場合は Git submodule / 共通リポジトリで横展開する
- Skill の品質 = Agent の出力品質。PR レビュー対象とする
- Agent Skills オープンスタンダード対応ツール (Kiro / Claude Code / GitHub Copilot) 間では同一の `SKILL.md` を共有可能

## Agent Instructions

| 比較項目       | Kiro                                    | Claude Code                     | GitHub Copilot                    | Cursor                            | Gemini                |
| -------------- | --------------------------------------- | ------------------------------- | --------------------------------- | --------------------------------- | --------------------- |
| 格納パス       | `.kiro/instructions/*.md`               | `CLAUDE.md` / `<dir>/CLAUDE.md` | `.github/copilot-instructions.md` | `.cursorrules` / `.cursor/rules/` | `GEMINI.md`           |
| 階層的指示     | ✅ (複数ファイル分割)                    | ✅ (ディレクトリ階層で継承)      | ⚠️ 単一ファイル中心                | ✅ (複数ファイル)                  | ⚠️ 単一ファイル中心    |
| グローバル指示 | `~/.local/share/kiro-cli/instructions/` | `~/.claude/CLAUDE.md`           | VS Code User Settings             | `~/.cursor/rules/`                | `~/.gemini/GEMINI.md` |
| 適用優先度     | Global → Project                        | Global → Root → Subdir          | Single / IDE設定                  | Global → Project                  | Global → Project      |
| 形式           | Markdown                                | Markdown                        | Markdown                          | Markdown                          | Markdown              |

### Guidelines

**→ Instructions はプロジェクトのコーディング規約・アーキテクチャ方針を記述し、Git 管理する。**

- 全エージェントで共通の指示内容 (コーディングスタイル、セキュリティルール等) を定義する
- 複数エージェントを併用する場合は、各ツールの指示ファイルに同等の内容を記載するか、共通ファイルから生成する仕組みを検討する
- 指示が肥大化するとコンテキストウィンドウを圧迫するため、簡潔に保つ
- Agent Skills オープンスタンダード対応ツール間では Instructions の記述方針を統一しやすい
