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
| Sub-agents           | 実装者と検証者の分離                       | `.codex/agents/` (TOML)    | `.claude/agents/`, agent teams                      |
| Memory / State       | 会話外に存在する永続的な状態管理           | Markdown, Linear           | Markdown (`AGENTS.md`), Linear (MCP)                |

## ループの構造（フロー）

```
Schedule/Automation
  → Triage Skill（問題の検出・分類）
    → STATE/Memory の読み書き
      → Isolated Worktree（隔離された作業ディレクトリ）
        → Implementer Sub-agent（実装）
          → Verifier Sub-agent（検証・テスト・ゲート）
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

設計の詳細は [Loop Engineering Design](../../explanation/loop-engineering-design.md) を参照。

## 注意点とリスク

| リスク               | 説明                                                           |
| -------------------- | -------------------------------------------------------------- |
| トークンコストの爆発 | Sub-agent と長時間ループでコストが急増する可能性               |
| Verification 責任    | 無人ループは無人のミスを生む。検証者 Sub-agent の信頼性が限界  |
| Comprehension Debt   | ループが高速に出力するほど、人間の理解が追いつかなくなる       |
| Cognitive Surrender  | ループに判断を委ねることで、エンジニアとしての判断力が衰退する |

## ツール

- `npx @cobusgreyling/loop-audit . --suggest` — Loop Readiness Score（ループ導入準備度の評価）
- `npx @cobusgreyling/loop-init . --pattern <pattern> --tool <tool>` — スターターのスキャフォールド
- `npx @cobusgreyling/loop-cost --pattern <pattern> --cadence <cadence>` — トークンコスト見積もり

## 出典

- [Addy Osmani — Loop Engineering](https://addyosmani.com/blog/loop-engineering/)
- [cobusgreyling/loop-engineering (GitHub)](https://github.com/cobusgreyling/loop-engineering)
- [Cobus Greyling — Loop Engineering (Substack)](https://cobusgreyling.substack.com/p/loop-engineering)
- [suwash — Loop Engineering 方法論整理 (Zenn)](https://zenn.dev/suwash/articles/loop-engineering_20260610)

---

## ループパッケージ設計

パッケージ構成・命名規約・依存関係・実行フローの詳細は [Loop Engineering Design](../../explanation/loop-engineering-design.md) を参照。

## 本リポジトリへの適用可能性

### 現状の資産マッピング

本リポジトリは Loop Engineering の 5 要素のうち、すでに大部分を保有している。

| Loop 要素            | 本リポジトリの現状                                                         | 充足度             |
| -------------------- | -------------------------------------------------------------------------- | ------------------ |
| Automations          | Renovate（依存管理）、CI workflows（`ci-*.yaml`）、`on-*` caller workflows | ◎ 部分的に実現済み |
| Worktrees            | 未導入（PR ベースの隔離のみ）                                              | △                  |
| Skills               | `.claude/skills/` に 12 スキル定義済み（review, validation 系）            | ◎ 充実             |
| Plugins / Connectors | MCP 未定義（`apm.yml` の `mcp: []`）                                       | × 未導入           |
| Sub-agents           | 未定義（`.claude/agents/` 不在）                                           | × 未導入           |
| Memory / State       | `AGENTS.md`、steering files が静的な知識を保持                             | △ 動的状態なし     |

### 導入候補パターン（優先度順）

#### 1. Daily Triage — CI/Lint Drift 検出（推奨度: ★★★）

**目的**: コンシューマリポジトリでの lint config drift、CI workflow 変更の影響を日次で検出

**実装イメージ**:

- GitHub Actions cron workflow（`on-loop-daily-triage.yaml`）
- `apm audit --ci` 結果を `STATE.md` に記録
- 差分があれば Issue 自動作成

**既存資産の活用**:

- `ci-apm-audit.yaml` がベース
- `go-validation`, `shell-script-validation` スキルがトリアージロジック提供

**トークンコスト**: Low（レポート出力のみ）

**判断材料**:

- メリット: config drift 問題（Harness Engineering 文書で既に課題認識済み）を自動検出
- リスク: 低い。L1（レポートのみ）から開始するため、誤操作リスクなし
- 前提条件: GitHub Actions のスケジュール実行のみ。エージェント不要で開始可能

#### 2. Post-Merge Cleanup — APM 同期チェック（推奨度: ★★★）

**目的**: 本リポジトリへのマージ後、生成ファイルの同期状態を自動検証

**実装イメージ**:

- `on-push` トリガーで `apm install --update` → diff 検出
- 不整合があれば PR 自動作成または Issue 起票

**既存資産の活用**:

- `apm install --update` コマンド
- 既存の `on-ci-push-*` ワークフローパターン

**トークンコスト**: Low（シェルスクリプトベース、エージェント不要）

**判断材料**:

- メリット: 生成ファイル不整合の即時検出。手動の `apm install --update` 忘れを防止
- リスク: 極低。diff 検出のみで変更を加えない
- 前提条件: 既存 CI 基盤で実現可能

#### 3. Dependency Sweeper — Renovate + 検証ループ（推奨度: ★★☆）

**目的**: Renovate PR に対し、エージェントが影響範囲を分析してレビューコメントを付与

**実装イメージ**:

- `pull_request` トリガー（label: `renovate`）
- Sub-agent が変更内容を読み、breaking の可能性を判定
- コメントで影響範囲サマリーを出力

**既存資産の活用**:

- `renovate/` プリセット群
- `go-review`, `github-actions-review` スキル

**トークンコスト**: Medium

**判断材料**:

- メリット: Renovate automerge 以外の PR に対する判断支援
- リスク: トークンコストが依存更新頻度に比例。誤判定時のノイズ
- 前提条件: MCP または GitHub API 連携が必要。Sub-agent 定義が必要

#### 4. Issue Triage — コンシューマリポジトリ向け（推奨度: ★☆☆）

**目的**: コンシューマリポジトリから報告される config 不整合・スキル不具合のトリアージ

**判断材料**:

- メリット: 多数のコンシューマを持つ場合に有効
- リスク: 現時点で Issue 量が少なければ ROI が低い
- 前提条件: GitHub MCP connector 導入が必須

### 実装に必要なステップ

| ステップ | 内容                                          | 対象パターン   |
| -------- | --------------------------------------------- | -------------- |
| 1        | `STATE.md` を定義（ループの状態管理ファイル） | 全パターン共通 |
| 2        | cron 付き GitHub Actions workflow 作成        | Pattern 1, 2   |
| 3        | Sub-agent 定義（`.claude/agents/`）           | Pattern 3, 4   |
| 4        | MCP connector 設定（GitHub API）              | Pattern 3, 4   |
| 5        | `loop-audit` による Readiness Score 測定      | 全パターン共通 |

### 推奨アプローチ

**Phase 1（エージェント不要・即時開始可能）**:

- Pattern 1 (Daily Triage) と Pattern 2 (Post-Merge Cleanup) を GitHub Actions cron で実装
- `STATE.md` に結果を記録し、手動レビュー
- トークンコスト: ゼロ（シェルスクリプト＋既存 CI ツールのみ）

**Phase 2（エージェント導入）**:

- Sub-agent 定義の追加
- Pattern 3 (Dependency Sweeper) の実装
- `loop-audit` による成熟度測定

**Phase 3（自律化）**:

- L2 (Assisted) → L3 (Unattended) への段階的移行
- Human Gate の条件を明文化した上で自動実行範囲を拡大
