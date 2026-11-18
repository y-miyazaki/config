# Tool Comparison Matrix (AI Spec-Driven Development)

仕様駆動開発 (Spec-Driven Development) ツールの選定の判断材料。仕様 → 設計 → タスクの成果物を AI Agent に渡すワークフローを比較する。

## History

| 日付       | 内容                                                                                                                                                                |
| ---------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 2026-11-18 | 初版作成。Kiro specs / OpenSpec / Spec Kit を比較。追記: Kiro の料金・ライセンス (kiro.dev/pricing, /license) と Spec Kit の Cursor 対応 (integrations 一覧) を確認 |

## Spec-Driven Development: Kiro specs vs OpenSpec vs Spec Kit

| 比較項目     | Kiro specs                                                                                                                                  | OpenSpec                                                      | Spec Kit                                                                        |
| ------------ | ------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------- | ------------------------------------------------------------------------------- |
| 提供元       | Kiro (AWS)                                                                                                                                  | Fission-AI                                                    | GitHub                                                                          |
| リポジトリ   | -                                                                                                                                           | [Fission-AI/OpenSpec](https://github.com/Fission-AI/OpenSpec) | [github/spec-kit](https://github.com/github/spec-kit)                           |
| ドキュメント | [kiro.dev/docs/specs](https://kiro.dev/docs/specs/)                                                                                         | [openspec.dev](https://openspec.dev/)                         | [github.github.com/spec-kit](https://github.github.com/spec-kit/)               |
| ライセンス   | プロプライエタリ (AWS Customer Agreement / AWS IP License。IDE・CLI の条件であり specs 単独の記載はなし)                                    | MIT                                                           | MIT                                                                             |
| 提供形態     | Kiro IDE / CLI / Web / Mobile に内蔵                                                                                                        | npm (`@fission-ai/openspec`)                                  | `uv tool install specify-cli`                                                   |
| 主な成果物   | `requirements.md` (バグ修正は `bugfix.md`) / `design.md` / `tasks.md`                                                                       | `proposal.md` / `specs/` / `design.md` / `tasks.md`           | Specify → Plan → Tasks → Implement → Converge の各 Markdown                     |
| 実行例       | Kiro 内で Feature / Bugfix Spec を作成                                                                                                      | `/opsx:propose` → `/opsx:apply` → `/opsx:archive`             | `specify init <name> --integration <agent>` → `/speckit.specify`                |
| 対応 Agent   | Kiro のみ                                                                                                                                   | 40 超 (Claude Code / Codex / Cursor / Copilot / Kiro を確認)  | 40 超 (Claude / Copilot / Kiro / Codex を確認。Cursor は `cursor-agent` で対応) |
| 料金         | Free $0 (50 credits) / Pro $20 / Pro+ $40 / Pro Max $100 / Power $200 / Teams $20 per seat。specs は専用機能として区分されず credits を消費 | 無料 (OSS)                                                    | 無料 (OSS)                                                                      |

出典 (2026-11-18 時点): 各公式ドキュメントと GitHub API。Spec Kit 最新リリースは v1.4.2 (2026-11-17)。

### Guidelines

**→ 複数 Agent を APM で配布する構成では、Agent 非依存の OpenSpec または Spec Kit を候補とする (条件付き推奨)。** Kiro のみで開発する場合は Kiro specs が追加導入なしで使える。

- 選定方針: 対応 Agent の広さと、成果物が Markdown でリポジトリにコミットできること
- 採用条件 (OpenSpec / Spec Kit): 複数 Agent で同一の仕様成果物を共有したい場合
- 採用条件 (Kiro specs): 開発 Agent を Kiro に統一している場合
- 不採用条件: 仕様と実装が小規模で、AGENTS.md と Issue で足りる場合は導入コストに見合わない
- 併用条件: Kiro specs と他ツールの成果物形式は異なるため、同一機能での併用は避ける
- 未確認: 各ツールの Codex / Cursor 向け生成ファイルの内容。導入前に実測する
- 更新条件: 本リポジトリが仕様駆動の運用を導入する時、または対応 Agent の変更時に再評価する
