<!-- omit in toc -->
# Tool Comparison Matrix (AI Governance)

AI Security / AI Skills 品質管理 / Agent 設定配布ツール選定の判断材料。

対象ツールはカテゴリが異なるため、用途別に分類して比較する。

評価軸の共通ルールは [tool-comparison-evaluation-criteria.md](tool-comparison-evaluation-criteria.md) を参照する。

## History

| 日付       | 内容                                                                 |
| ---------- | -------------------------------------------------------------------- |
| 2026-05-23 | スコープ境界と追加比較候補 (Skill/Plugin 配布レイヤ) を追記           |
| 2026-05-23 | 言語依存パッケージマネージャー比較を分離し、AI Governance の範囲を明確化 |
| 2026-05-23 | リポジトリ依存の記述を削除し、フラットな評価方針に更新               |
| 2026-05-23 | 初版作成。AI Security / AI Skills Lint・Evaluation / Package 管理を比較 |

<!-- omit in toc -->
## Table of Contents

- [History](#history)
- [カテゴリ概要](#カテゴリ概要)
- [スコープ境界](#スコープ境界)
- [AI Security Scanning: Snyk vs Trivy](#ai-security-scanning-snyk-vs-trivy)
  - [Pricing](#pricing)
  - [Guidelines](#guidelines)
- [AI Skills Lint / Evaluation: Waza vs markdownlint-cli2 vs apm audit](#ai-skills-lint--evaluation-waza-vs-markdownlint-cli2-vs-apm-audit)
  - [Guidelines](#guidelines-1)
- [Agent Capability Distribution: APM vs Git Sync vs Agent-native Plugin](#agent-capability-distribution-apm-vs-git-sync-vs-agent-native-plugin)
  - [Guidelines](#guidelines-2)
- [推奨構成パターン](#推奨構成パターン)
  - [Guidelines](#guidelines-3)

## カテゴリ概要

| カテゴリ                     | ツール                              | 主な用途                                         |
| ---------------------------- | ----------------------------------- | ------------------------------------------------ |
| AI Security Scanning         | Snyk / Trivy                        | 脆弱性 / 設定不備 / シークレット検知              |
| AI Skills Lint / Evaluation  | Waza / markdownlint-cli2 / apm audit | Skill 品質チェック / Markdown 品質 / 依存監査     |
| Agent Capability Distribution | APM / Git Sync / Agent-native Plugin | Agent 能力資産 (設定/Skill/Plugin) の配布方式        |

## スコープ境界

- このドキュメントは AI Governance レイヤ (Security / Skill品質 / Agent設定配布) のみを扱う
- 言語依存の依存管理 (`go mod`, `npm/pnpm/yarn`, `uv/pip`) は対象外
- Node.js の依存管理は [tool-comparison-matrix-nodejs.md](tool-comparison-matrix-nodejs.md) で扱う
- Go の `go mod` は Go 比較ドキュメントで扱う (必要時に [tool-comparison-matrix-go.md](tool-comparison-matrix-go.md) へ追記)
- Python 依存管理は現時点では比較対象に含めない

## AI Security Scanning: Snyk vs Trivy

| 比較項目                 | Snyk                                                                 | Trivy                                                                  |
| ------------------------ | -------------------------------------------------------------------- | ---------------------------------------------------------------------- |
| 提供元                   | Snyk                                                                 | Aqua Security                                                          |
| リポジトリ               | [snyk/cli](https://github.com/snyk/cli)                              | [aquasecurity/trivy](https://github.com/aquasecurity/trivy)           |
| ライセンス/提供形態      | CLI 提供 + SaaS プラットフォーム                                    | OSS (CLI)                                                              |
| 主なスキャン対象         | OSS 依存関係 / コード / コンテナ / IaC                              | Filesystem / Container / Repo / SBOM                                  |
| 主な検出タイプ           | 脆弱性 (SCA) / コード分析 / IaC misconfig                           | 脆弱性 / misconfig / secrets / license                                |
| 主な CLI 例              | `snyk test`, `snyk code test`, `snyk container test`, `snyk iac test` | `trivy fs`, `trivy image`, `trivy config`, `trivy sbom`               |
| マネージド統合           | ✅ (Snyk プラットフォーム)                                             | ⚠️ OSS 中心 (必要に応じて周辺サービスを組み合わせ)                      |
| セルフホスト適性         | ⚠️ CLI はローカル実行可、運用統合は SaaS 寄り                         | ✅ OSS 単体で導入しやすい                                               |
| 導入の主な前提条件       | SaaS 利用可否 / 予算 / 開発者向け修正支援の必要性                     | OSS 運用体制 / 誤検知調整の運用余力                                     |

### Pricing

| プラン     | Snyk                                    | Trivy                    |
| ---------- | --------------------------------------- | ------------------------ |
| OSS/無料枠 | 無料枠あり (詳細は最新プラン要確認)      | OSS は無料               |
| 有料       | 商用プランあり                           | Enterprise/周辺製品は別途 |

### Guidelines

**→ 優劣ではなく要件適合で選択する。コスト最小化なら Trivy、修正ワークフロー統合を重視するなら Snyk、厳格運用なら併用。**

- OSS 中心・セルフホスト前提なら Trivy
- 開発者向け修正導線や組織横断ガバナンスを重視するなら Snyk
- 規制対応や多層防御が必要なら Trivy + Snyk の併用を検討
- 最終判断は [tool-comparison-evaluation-criteria.md](tool-comparison-evaluation-criteria.md) の加重スコアで行う

## AI Skills Lint / Evaluation: Waza vs markdownlint-cli2 vs apm audit

| 比較項目                     | Waza                                              | markdownlint-cli2                           | apm audit                                      |
| ---------------------------- | ------------------------------------------------- | ------------------------------------------- | ---------------------------------------------- |
| 主用途                       | AI Skill の readiness/eval                        | Markdown の静的 lint                         | APM 依存関係・構成の監査                         |
| 実行例                       | `waza check <skill>` / `waza run eval.yaml`       | `markdownlint-cli2 "docs/**"`              | `apm audit --ci`                                |
| 対象                         | `SKILL.md`, `eval.yaml`, `evals/tasks/*.yaml`     | `README.md`, `docs/**/*.md`                  | `apm.yml`, `apm.lock.yaml`, パッケージ依存        |
| 判定タイプ                   | スキーマ妥当性 / 評価スコア / トークン分析         | Markdown 文法/フォーマット                   | 依存整合性 / 監査ポリシー                        |
| 失敗時の主な示唆             | 仕様逸脱・評価不足・タスク不足                    | 形式崩れ・リンク不整合                        | 依存問題・監査違反                               |
| 導入効果                     | AI Skill の品質保証を直接評価                      | 文書品質を安定化                              | 構成と依存の監査一貫性を担保                      |
| 代替可能性                   | 低 (Skill eval を代替しにくい)                     | 中 (他 lint へ置換可能)                       | 低 (APM 運用時は事実上必須)                       |

### Guidelines

**→ 目的が異なるため代替ではなく組み合わせ判断を行う。AI Skill を運用するなら Waza は必要、ドキュメント品質には markdownlint、APM 利用時は apm audit が必要。**

- `waza check` で readiness のハードエラーを先に潰す
- `waza run eval.yaml` で振る舞い品質を評価
- docs 変更を含む場合は markdownlint を追加
- APM パッケージ配布を行う場合は `apm audit --ci` を必須化

## Agent Capability Distribution: APM vs Git Sync vs Agent-native Plugin

| 比較項目                 | APM                                                     | Git Sync モデル                                   | Agent-native Plugin モデル                         |
| ------------------------ | ------------------------------------------------------- | ------------------------------------------------- | -------------------------------------------------- |
| ツール種別               | Agent 設定配布マネージャー                              | Git ベース配布                                    | ベンダー提供の拡張配布                             |
| 主用途                   | Agent 設定配布 (MCP/Instructions/Skills/Hooks)         | Skill/Rules の Git 共有                            | Agent 機能の即時導入                                |
| 代表例                   | APM package                                             | gh skill / Claude Skills / Cursor rules の Git 管理 | Claude の plugin 的拡張、拡張マーケット導入モデル   |
| 配布単位                 | 設定パッケージ                                          | リポジトリ/ファイル                               | Plugin/拡張機能                                    |
| 再現配布                 | ✅                                                       | ⚠️ (Git 運用次第)                                  | ⚠️ (提供元依存)                                    |
| バージョン固定           | ✅ (`apm.lock.yaml`)                                     | ⚠️ (Git 運用次第)                                  | ⚠️ (提供元更新に依存)                              |
| 監査/統制                | ✅ (`apm audit`)                                         | ⚠️ (レビュー運用依存)                              | ⚠️ (Marketplace/提供元ポリシー依存)                |
| 導入速度                 | 中                                                       | 低〜中                                              | 高                                                 |
| ベンダーロックイン       | 低〜中                                                   | 低                                                   | 中〜高                                             |

### Guidelines

**→ APM は再現性と統制、Git Sync モデルは運用単純性、Agent-native Plugin は導入速度を優先するときに選ぶ。**

- Agent 設定資産を複数環境で再現配布する要件がある場合は APM を採用
- Git Sync モデルは gh skill / Claude Skills / Cursor rules のような Git 管理型配布を含む
- 単一ツールへ統一せず、責務境界 (設定配布/実行依存) で管理
- 本番運用では、Plugin モデルを使う場合でもレビュー済み設定を Git 管理で補完する

## 推奨構成パターン

| パターン          | 構成                                                | 用途                                           |
| ----------------- | --------------------------------------------------- | ---------------------------------------------- |
| 最小構成          | Trivy + Waza + markdownlint-cli2 + APM             | セキュリティ/Skill品質/設定配布をバランスよく担保 |
| 開発者体験強化    | Trivy + Snyk + Waza + APM                          | 開発者向け脆弱性フィードバックを強化             |
| 厳格運用 (CI 強化) | Trivy + Snyk + Waza + markdownlint-cli2 + apm audit | 監査・品質ゲートを多層化                         |

### Guidelines

**→ 先に要件を定義し、次に必要ツールだけ採用する。不要ツールは導入しない。**

- セキュリティ基盤のみ必要: Trivy
- AI Skill 品質保証が必要: Waza を追加
- Agent 設定を複数環境で再現配布する必要がある: APM を追加
- 開発者向け脆弱性修正体験を強化したい: Snyk を追加
