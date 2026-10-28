# Loop Engineering

## 概要

Loop Engineering とは、AI コーディングエージェントに対する「プロンプトする人」を自分自身から「システム」に置き換える設計手法。ループとは再帰的なゴールであり、目的を定義して AI が完了するまで反復する仕組みを指す。

> "You shouldn't be prompting coding agents anymore. You should be designing loops that prompt your agents." — Peter Steinberger
>
> "I don't prompt Claude anymore. I have loops running that prompt Claude and figuring out what to do. My job is to write loops." — Boris Cherny (Head of Claude Code, Anthropic)

## 位置づけ

```
Factory Model（ソフトウェアを作るシステム全体）
  └─ Loop Engineering（ループを設計し、エージェントを駆動する層）
       └─ Agent Harness Engineering（単一エージェントの実行環境）
            └─ Prompt Engineering（個別のプロンプト作成）
```

本リポジトリの [Harness Engineering](harness-engineering.md) は単一エージェントの実行環境（Layer 1-6）を定義している。Loop Engineering はその一階層上に位置し、ハーネスをスケジュール駆動で自律的に回す仕組みとなる。

## 5 つの構成要素 + 記憶

| 構成要素             | ループ内での役割                           | Codex                      | Claude Code                                         |
| -------------------- | ------------------------------------------ | -------------------------- | --------------------------------------------------- |
| Automations          | スケジュールに基づくタスク発見とトリアージ | Automations tab, `/goal`   | Scheduled tasks, `/loop`, `/goal`, GitHub Actions   |
| Worktrees            | 並列実行の隔離                             | ビルトイン worktree        | `git worktree`, `--worktree`, `isolation: worktree` |
| Skills               | プロジェクト知識の永続化                   | Agent Skills (`SKILL.md`)  | Agent Skills (`SKILL.md`)                           |
| Plugins / Connectors | 外部ツールとの接続（MCP）                  | Connectors (MCP) + plugins | MCP servers + plugins                               |
| Sub-agents           | 実装者と検証者の分離（Maker / Checker）    | `.codex/agents/` (TOML)    | `.claude/agents/`, agent teams                      |
| Memory / State       | 会話外に存在する永続的な状態管理           | Markdown, Linear           | Markdown (`AGENTS.md`), Linear (MCP)                |

## ループの構造（フロー）

```
Schedule/Automation
  → Triage Skill（問題の検出・分類）
    → `.loop/state-*.json` / run-log の読み書き
      → Isolated Worktree（隔離された作業ディレクトリ）
        → Maker Sub-agent（実装）
          → Checker Sub-agent（検証・テスト・ゲート）
            → MCP / Git / Tickets（外部連携）
              → Human Gate?
                ├─ safe/allowlisted → Commit / PR / Action
                └─ risky/ambiguous → Escalate to human
```

## 代表的なパターン

| パターン           | 実行間隔    | トークンコスト | 概要                                       |
| ------------------ | ----------- | -------------- | ------------------------------------------ |
| Daily Triage       | 1 日-2 時間 | Low            | CI 失敗・Issue・コミットの要約とトリアージ |
| PR Babysitter      | 5-15 分     | High           | PR の状態監視と自動対応                    |
| CI Sweeper         | 5-15 分     | Very High      | CI 失敗の自動修正                          |
| Dependency Sweeper | 6 時間-1 日 | Medium         | 依存関係の自動更新                         |
| Changelog Drafter  | 1 日/tag    | Low            | CHANGELOG の自動起草                       |
| Post-Merge Cleanup | 1 日-6 時間 | Low            | マージ後のコード整理                       |
| Issue Triage       | 2 時間-1 日 | Low            | Issue の自動分類・ラベル付け               |

### 段階的ロールアウト

- **L1 Report**: レポートのみ出力。人間が判断・実行する
- **L2 Assisted**: 修正を提案し、人間が承認する
- **L3 Unattended**: 完全自律実行（許可リスト内のみ）

## 設計方針

設計の詳細は [Loop Engineering Design](../../explanation/loop-engineering/loop-engineering-design.md) を参照。

## 注意点とリスク

| リスク               | 説明                                                           |
| -------------------- | -------------------------------------------------------------- |
| トークンコストの爆発 | Sub-agent と長時間ループでコストが急増する可能性               |
| Verification 責任    | 無人ループは無人のミスを生む。Checker セッションの信頼性が限界 |
| Comprehension Debt   | ループが高速に出力するほど、人間の理解が追いつかなくなる       |
| Cognitive Surrender  | ループに判断を委ねることで、エンジニアとしての判断力が衰退する |

## ツール

- `npx @cobusgreyling/loop-audit . --suggest` — Loop Readiness Score（ループ導入準備度の評価）
- `npx @cobusgreyling/loop-init . --pattern <pattern> --tool <tool>` — スターターのスキャフォールド
- `npx @cobusgreyling/loop-cost --pattern <pattern> --cadence <cadence>` — トークンコスト見積もり

## 出典

- [Addy Osmani — Loop Engineering](https://addyosmani.com/blog/loop-engineering/)
- [cobusgreyling/loop-engineering (GitHub)](https://github.com/cobusgreyling/loop-engineering)
- [suwash — Loop Engineering 方法論整理 (Zenn)](https://zenn.dev/suwash/articles/loop-engineering_20260610)

---

## ループパッケージ設計

パッケージ構成・命名規約・依存関係・実行フローの詳細は [Loop Engineering Design](../../explanation/loop-engineering/loop-engineering-design.md) を参照。

## 本リポジトリへの適用可能性

用語・フェーズ・役割の対応は [Ubiquitous Language](../../explanation/loop-engineering/CONTEXT.md) を参照。実装状況の正は [Loop Engineering Design](../../explanation/loop-engineering/loop-engineering-design.md#implementation-status)。

### 現状の資産マッピング

本リポジトリは Loop Engineering の構成要素を、外部カタログの `STATE.md` / `.claude/agents/` ではなく **GHA ループ基盤** で実装している。

| Loop 要素            | 本リポジトリの現状                                                                                                       | 充足度     |
| -------------------- | ------------------------------------------------------------------------------------------------------------------------ | ---------- |
| Automations          | `on-loop-*.yaml` callers、`ci-loop-caller` / `ci-loop-caller-entity`、Renovate、既存 `ci-*.yaml`                         | ◎ 実現済み |
| Worktrees            | `loop-worktree-setup` + `loop-execute`（L2/L3）                                                                          | ◎ 実現済み |
| Skills               | APM パッケージ経由の entry / review / validation / `loop-verifier`（`.claude/skills/` は同期成果物）                     | ◎ 充実     |
| Plugins / Connectors | APM パッケージの MCP（GitHub / AWS / Terraform など）。ルート `apm.yml` の空配列ではない                                 | ◎ 導入済み |
| Sub-agents           | Maker / Checker は `loop-execute` の 2 セッション（`agent_maker_*` / `agent_checker_*`）。`.claude/agents/` は使わない   | ◎ 実現済み |
| Memory / State       | `.loop/state-<loop_name>.json`、sidecar ledger、`loop-run-log.md`、`loop-budget.json`。静的知識は `AGENTS.md` / steering | ◎ 実現済み |

### 実装済みループ（`loop_name` = 状態ファイル）

状態パスは常に `.loop/state-<loop_name>.json`。別名ファイルは置かない。ドメイン ledger だけ sidecar を足す（例: `state-ci-sweeper-run-ledger.json`）。

| `loop_name`            | 状態ファイル                            | レベル      |
| ---------------------- | --------------------------------------- | ----------- |
| `docs-updater`         | `.loop/state-docs-updater.json`         | L2          |
| `ci-sweeper`           | `.loop/state-ci-sweeper.json`           | L2          |
| `changelog`            | `.loop/state-changelog.json`            | L2          |
| `refactor`             | `.loop/state-refactor.json`             | L2          |
| `tech-debt`            | `.loop/state-tech-debt.json`            | L2          |
| `github-issue-triage`  | `.loop/state-github-issue-triage.json`  | L1 (Report) |
| `github-issue-autofix` | `.loop/state-github-issue-autofix.json` | L2          |
| `github-pr-revise`     | `.loop/state-github-pr-revise.json`     | L2          |

外部パターン名との対応: CI Sweeper / Changelog Drafter / Issue Triage / PR 改訂は上表で dogfood 済み。`loop-stale-pr` は未着手。

### 未導入パターン（優先度順）

#### 1. Daily Triage — CI/Lint Drift 検出（推奨度: ★★★）

**目的**: コンシューマリポジトリでの lint config drift、CI workflow 変更の影響を日次で検出。

**実装イメージ**:

- GitHub Actions cron（`on-loop-daily-triage.yaml` 相当）
- `apm audit --ci` 結果を `.loop/state-<loop_name>.json` と run-log に記録
- 差分があれば Issue 自動作成（L1）

**既存資産**: `ci-apm-audit.yaml`、`go-validation` / `shell-script-validation`。CI 失敗の自動修正は `ci-sweeper` が担当し、本パターンとは分離する。

#### 2. Post-Merge Cleanup — APM 同期チェック（推奨度: ★★★）

**目的**: マージ後に生成ファイルの同期を検証する。

**実装イメージ**: `on-push` で `apm install --update` → diff。不整合なら PR または Issue。エージェント不要で開始できる。

#### 3. Dependency Sweeper — Renovate + 検証ループ（推奨度: ★★☆）

**目的**: Renovate PR の影響範囲を Maker/Checker でコメントする。

**既存資産**: `renovate/` プリセット、`go-review` / `github-actions-review`、GitHub MCP。トークンコストは更新頻度に比例する。

#### 4. Stale PR / その他カタログパターン（推奨度: ★☆☆）

`loop-stale-pr` など外部カタログにあって未着手のループ。Issue 量・ROI を見てから caller を足す。

### 残作業（基盤）

| 項目                   | 内容                                                                                                     |
| ---------------------- | -------------------------------------------------------------------------------------------------------- |
| `loop-audit` Readiness | 外部スコアをそのまま使わず、四平面（`level` / `may_edit` / `write_target` / `delivery`）で定義するか未決 |
| L3 Unattended          | Human Gate 条件を明文化したうえで許可リスト内のみ拡大                                                    |

### 推奨アプローチ

**済（dogfood）**: Detect → Execute（Maker）→ Verify（Checker）→ Finalize。状態は `.loop/state-<loop_name>.json`。L2 の `open_pr` は merge-gated `pending`。

**次**: Daily Triage と Post-Merge Cleanup（エージェント不要または L1）。その後 Dependency Sweeper。L3 はゲート明文化後。
