<!-- omit in toc -->
# Tool Comparison Matrix (AI Agent)

AI Agent / コーディングアシスタントに特化したツール選定の判断材料。

<!-- omit in toc -->
## History

| 日付       | 内容                                                                 |
| ---------- | -------------------------------------------------------------------- |
| 2026-06-17 | 全般最新化: Copilot AI Credits をドル建て (Base+Flex) に修正、Claude Code Free tier 追加、Cursor pricing 簡略化反映、Anthropic Enterprise pricing 更新 |
| 2026-06-17 | Pricing 個人プラン細分化 (3段階→4段階)。Kiro Pro Max ($100/月) 追加反映 |
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
    - [$10〜$20 プラン帯の選択指針](#1020-プラン帯の選択指針)
  - [Billing Model](#billing-model)
  - [Configuration Files and Directories](#configuration-files-and-directories)
  - [Guidelines](#guidelines)
- [Agent Security: Guardrails](#agent-security-guardrails)
  - [Guardrails Configuration](#guardrails-configuration)
- [Agent Skills](#agent-skills)
  - [Guidelines](#guidelines-1)
- [Agent Hooks](#agent-hooks)
  - [Guidelines](#guidelines-2)
- [Agent Instructions (Steering)](#agent-instructions-steering)
  - [Guidelines](#guidelines-3)
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
| Inline Suggestions | ❌                          | ❌                     | ✅ (Tab completions)    | ✅ (Pro以上: 無制限、Free: 2,000/月) | ✅               |
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
| データ学習利用     | ❌ 利用しない               | ❌ 利用しない          | ❌ (Business以上)          | ❌ デフォルト除外 (全プラン) | ❌ 利用しない     |
| コンプライアンス   | SOC2 / ISO / GCP準拠       | SOC2                  | SOC2                      | SOC2 / FedRAMP          | SOC2 / AWS準拠   |

### Pricing

> ※ 2026-06-01 より GitHub Copilot は「リクエストベース」から「AI Credits (ドル建て)」課金に移行。クレジットは Base (月額固定) + Flex (変動追加枠) で構成される。Flex allotments は時期により変動する可能性あり。新規 Pro/Pro+/Max プランのサインアップは一時停止中。
> ※ Gemini CLI は 2026-06-18 にサービス停止。後継は Antigravity CLI (`agy`)。設定パスは `~/.gemini/` を引き続き使用し互換性あり。

| プラン       | Antigravity                   | Claude Code                       | Cursor                | GitHub Copilot                          | Kiro                         |
| ------------ | ----------------------------- | --------------------------------- | --------------------- | --------------------------------------- | ---------------------------- |
| 料金ページ   | [antigravity.google/pricing](https://antigravity.google/pricing) | [anthropic.com/pricing](https://www.anthropic.com/pricing) | [cursor.com/pricing](https://www.cursor.com/pricing) | [github.com/features/copilot](https://github.com/features/copilot#pricing) | [kiro.dev/pricing](https://kiro.dev/pricing) |
| 無料枠       | ❌ (廃止予定)                  | ✅ (Free: Claude Code含む、制限付き利用) | ✅ (Hobby: Agent限定利用+Tab限定) | ✅ (Free: 限定 AI Credits / inline suggestions 2,000回/月) | 50 クレジット/月             |
| 個人 (標準)  | Google AI Pro: $20/月          | Pro: $20/月                       | Individual: $20/月    | Pro: $10/月 ($15相当 credits: Base $10+Flex $5)  | Pro: $20/月                  |
| 個人 (中位)  | Ultra: $100/月 (5x)            | Max 5x: $100/月                   | -                     | Pro+: $39/月 ($70相当 credits: Base $39+Flex $31) | Pro+: $40/月                 |
| 個人 (準上位) | -                              | -                                 | -                     | Max: $100/月 ($200相当 credits: Base $100+Flex $100) | Pro Max: $100/月             |
| 個人 (上位)  | Ultra+: $200/月 (20x)          | Max 20x: $200/月                  | -                     | -                                       | Power: $200/月               |
| チーム/組織  | Standard: 時間課金            | Team: $20/seat/月 (年額) / $25 (月額), Premium: $100 (年額) / $125 (月額) | Teams: $40/seat/月, Enterprise: カスタム | Business: $19/user/月 (プール型) | 今後拡張                     |
| Enterprise   | Enterprise: カスタム          | Enterprise: $20/seat + 従量課金   | Enterprise: カスタム  | Enterprise: $39/user/月 (プール型) | 今後拡張                     |
| 従量追加課金 | ❌ なし (枠超過時は利用停止) | ⚠️ API key モード時のみ (トークン従量) | ⚠️ on-demand 設定時のみ (使用量に応じ課金) | ✅ 超過時 $0.01/credit で追加課金 (予算上限設定可) | ✅ 超過時 $0.04/credit で追加課金 (opt-in) |
| 枠超過時の制限 | 完全ロックアウト (数日〜1週間使用不可、翌リセットまで待機) | 一時利用停止 (5時間セッションリセットまで待機)。API key 設定時はトークン従量で継続可 | Slow pool フォールバック (低速応答、ピーク時は実質停止)。on-demand 有効時は従量課金で継続可 | 予算上限到達時はブロック (追加課金 opt-out 時) | 追加課金 opt-in しない場合は利用停止 |

#### $10〜$20 プラン帯の選択指針

> 個人の標準プラン ($10〜$20/月) は最も利用者が多い価格帯。同価格帯での優位性を整理する。

| 観点               | Antigravity ($20)         | Claude Code ($20)              | Cursor ($20)                  | GitHub Copilot ($10)                | Kiro ($20)                    |
| ------------ | ----------------------------- | --------------------------------- | --------------------- | --------------------------------------- | ---------------------------- |
| 月額               | $20                       | $20                            | $20                           | $10 (最安)                          | $20                           |
| credits相当価値    | プラン内定額              | プラン内定額                   | プラン内定額                  | $15相当 (Base $10+Flex $5)          | 1,000 credits                 |
| 枠の実質持続性     | ⚠️ 不明 (利用量次第でロックアウト) | ✅ 高い (定額内で安定)          | ✅ 高い (Agent requests 多め)  | ❌ 低い (Agent利用でcredit急速消費、数日〜1週間で枯渇の報告多数) | ⚠️ 中程度 (1,000 credits、Agent利用頻度次第) |
| 超過後も無料で継続 | ❌ 完全ロックアウト        | ❌ 利用停止 (5時間リセット待ち) | ⚠️ Slow pool (低速だが無料で継続) | ❌ ブロック (opt-out時)              | ❌ 利用停止                    |
| 超過後の従量課金   | ❌ なし                    | ✅ API key 設定で従量継続可     | ✅ on-demand で従量継続可      | ✅ $0.01/credit で追加課金 (予算上限設定可) | ✅ $0.04/credit (opt-in)      |
| 超過リスクの総合評価 | **高** (ロックアウト、回避手段なし) | **低** (API key で即座に従量移行可) | **低** (Slow pool で最低限継続 + on-demand 選択可) | **高** (credit消費が速く枯渇しやすい。追加課金opt-inすると予算膨張リスク) | **中** (opt-in すれば継続可、しなければ停止) |
| inline suggestions | -                         | -                              | 限定                          | ✅ 無制限 (credit 消費なし)          | -                             |
| Cloud Agent        | -                         | -                              | ✅                             | ✅ (PR自動作成、credit消費大)        | -                             |
| Code Review        | -                         | -                              | Bugbot (従量)                 | ✅ (PR/diff review、credit消費)      | -                             |
| CLI 自動化         | ✅ (agy)                   | ✅ (最も強い)                   | ⚠️                             | ✅ (Copilot CLI preview)             | ✅                             |
| コンテキスト窓     | 1M+                       | 200K                           | 128K〜200K                    | 128K〜200K                          | 200K                          |
| 年額割引           | あり                      | $17/月相当                     | $192/年                       | あり                                | 不明                          |

> ⚠️ **GitHub Copilot Pro のcredit枯渇問題**: AI Credits はモデル×トークン数で消費量が大きく変動する。Agent mode / Cloud Agent / Code Review は高額モデルを使用するとcreditを急速に消費し、$15相当/月の枠が数日で枯渇するケースが報告されている。inline suggestions (コード補完) のみであればcredit消費なしで無制限だが、Agent中心の利用では月額 $10 の見た目のコスパは大きく悪化する。Agent を多用するなら Pro+ ($39/月, $70相当) 以上が現実的。

**$20 プラン帯の推奨:**

- **超過リスク最小 + CLI** → Claude Code Pro ($20/月)。定額内でのモデル品質が最も高い。枠を使い切っても API key 設定で即座に従量移行でき、作業中断なし。枠自体も安定して持続する
- **超過リスク最小 + IDE** → Cursor Individual ($20/月)。Slow pool で低速ながら無料で継続利用可（唯一の「超過後も無料で使える」選択肢）。Agent requests の枠も比較的余裕あり
- **AWS 統合 + 従量予測性** → Kiro Pro ($20/月)。1,000 credits/月、超過時 $0.04/credit。opt-in しなければ停止のため予算超過リスクなし
- **コンテキスト窓最大** → Antigravity ($20/月)。1M+ tokens で大規模コードベースに有利。**ただし超過時に完全ロックアウト（従量課金オプションなし）のため、利用量が読めない場合はリスク高**
- **inline suggestions 主体の補完用途のみ** → GitHub Copilot Pro ($10/月)。コード補完のみであればcredit消費なしで無制限かつ最安。Agent 機能を多用する場合は枠が数日で枯渇するため非推奨（Pro+ $39/月以上を検討）

### Billing Model

> ※ GitHub Copilot は 2026-06-01 より全プラン AI Credits 制に移行。旧「premium requests」は廃止 (legacy)。

| 項目               | Antigravity                   | Claude Code                 | Cursor                         | GitHub Copilot                                   | Kiro                     |
| ------------------ | ----------------------------- | --------------------------- | ------------------------------ | ------------------------------------------------ | ------------------------ |
| 基本課金           | 無料枠 + サブスク             | サブスク枠 (定額内トークン) | サブスク + usage制限           | サブスク + AI Credits (トークン従量)              | サブスク + クレジット枠  |
| クレジット単価     | -                             | -                           | -                              | ドル建て (Base + Flex allotment)                 | $0.04/credit (超過時)    |
| 含まれるクレジット | -                             | -                           | -                              | Pro: $15/月, Pro+: $70/月, Max: $200/月 (Base+Flex合計) | Pro: 1,000/月, Pro+: 2,000/月, Pro Max: 5,000/月, Power: 10,000/月 |
| 組織プールモデル   | -                             | -                           | -                              | ✅ (user単位クレジットを組織全体でプール共有)      | -                        |
| 超過時の挙動       | 完全ロックアウト (従量課金なし) | 利用停止 (API key モードで従量継続可) | Slow pool / on-demand 従量課金 | 予算設定に基づき追加課金 or ブロック              | $0.04/credit 追加課金 (opt-in、未設定時は利用停止) |
| モデル選択         | Gemini 系中心 (2.5 Pro/Flash) | Claude 系中心               | ✅ 複数モデル (GPT-5, Claude等) | ✅ 複数モデル (GPT-5, Claude, Gemini等)           | ✅ (Auto / 手動)          |
| モデルによる料金差 | プラン内定額                  | プラン内定額                | モデルにより消費が異なる       | モデル×トークン数で credit 消費が大きく異なる     | クレジット消費量が異なる |
| Code Completions   | -                             | -                           | -                              | Free: 2,000/月, Pro以上: 無制限 (AI Credits 消費なし) | -                        |
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
- GitHub / PRレビュー / 開発標準化 / Cloud Agent (PR自動作成) → **GitHub Copilot**
- IDE 内完結 / 高速開発体験 / Cloud agents → **Cursor**
- GCP 中心開発 / Vertex AI 連携 → **Antigravity**
- 複数ツール併用前提の探索環境 → **Kiro + Claude Code + Copilot** など併用
- コスト最小で始めたい → GitHub Copilot (Free) または Cursor (Hobby)
- 大量利用 → Kiro Power ($200/月) または Claude Code Max 20x ($200/月) または Copilot Max ($200相当 credits/月)
- コスト予測性重視 → Claude Code (定額内) または Kiro (クレジット制)。Copilot は AI Credits 制でモデル・用途次第で変動大
- サードパーティ Agent 委任 (Claude/Codex) → GitHub Copilot Pro+ 以上

## Agent Security: Guardrails

| 比較項目             | Antigravity              | Claude Code      | Cursor           | GitHub Copilot  | Kiro                   |
| -------------------- | ------------------------ | ---------------- | ---------------- | --------------- | ---------------------- |
| ドキュメント         | [antigravity.google](https://antigravity.google/docs/security) | [docs.anthropic.com](https://docs.anthropic.com/en/docs/claude-code/security) | [IDE](https://cursor.com/docs/reference/permissions) / [CLI](https://cursor.com/docs/cli/reference/configuration) | [docs.github.com](https://docs.github.com/en/copilot/reference/copilot-cli-reference/cli-config-dir-reference) | [kiro.dev](https://kiro.dev/docs/cli/custom-agents/configuration-reference/#toolssettings-field) |
| 破壊的操作の制御     | ✅ 確認あり               | ✅ permissions    | ⚠️ 一部           | ✅ 確認あり      | ✅ 承認制               |
| ファイルアクセス制御 | ⚠️ 限定的                 | ✅ deny パターン  | ⚠️ IDE依存        | ⚠️ IDE依存       | ✅                      |
| シークレット保護     | ✅                        | ✅                | ⚠️                | ✅               | ✅                      |
| ネットワーク制御     | ⚠️                        | ✅                | ⚠️                | ⚠️               | ✅                      |
| コマンド実行制御     | ✅ (sandbox)              | ✅ (permissions)  | ⚠️                | ✅               | ✅ (allowlist/denylist) |
| 監査ログ             | ⚠️ (Vertex AI経由時のみ)    | ⚠️ セッション中心 | ⚠️                | ✅ Enterprise    | ⚠️ セッション中心       |
| データ統制           | GCP基盤準拠              | 契約プラン依存   | Business以上推奨 | Enterprise 強い | AWS基盤準拠            |

### Guardrails Configuration

詳細は [tool-comparison-matrix-ai-agent-guardrails.md](tool-comparison-matrix-ai-agent-guardrails.md) を参照。

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
