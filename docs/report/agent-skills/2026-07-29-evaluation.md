# Agent Skills / Instructions 評価レポート（`.apm` 配下）

- **調査日:** 2026-07-29
- **対象:** `.apm/packages/*/.apm/skills/*/SKILL.md`（18 スキル）、`.apm/packages/*/.apm/instructions/*.instructions.md`（8 ファイル）
- **評価基準:** `agent-skills-review`（S/Q/P/BP）、`instructions-review`（G/STRUCT/GUIDE/QUAL/CONS/COMP/SEC/STD/TEST）、および各 instructions Standards
- **前報:** [Agent Skills Evaluation (2026-07-26)](2026-07-26-evaluation.md) — 本報が現行所見。前報の「対応済」は要約のみ残す

## 要約

2026-07-26 以降の改修（Workflow/Ref Guide 整合、ロードトリガー allowlist、Output 骨格削除、DIST/E 住み分けなど）は維持されている。Phase F（refactor always 削減）後の再計測では **最大負荷は agent-skills-review → go-review 系**。refactor は always 4 ファイル・約 2000 語・合計 ~4.2k tok に低下（旧: always 7・~6k tok）。

**訂正（前報 Phase C）:** loop checklist への安定 ItemID は、運用ランの Candidates/Deferred 追跡や自動化検証の必須条件ではない。loop の主キーは path / failure / commit / `path+kind+snippet` であり、ItemID はオーサリング監査・ゲート引用向けの SHOULD。

残課題の中心は (1) markdown instructions の `Check:` 付き厚み、(2) go-validation 失敗時 category の一般論、である。loop always 削減（refactor / tech-debt）と bats×shell-script G-05 は対応済／現状維持。

---

## 1. 前回からの変化

| 領域 | 2026-07-26 | 2026-07-29 |
| ---- | ---------- | ---------- |
| review Workflow / 全 category always | 方針確定・矛盾解消済 | 維持。語数は再計測で減少（例: go-review always ~3165、前報 ~5423） |
| ロードトリガー allowlist | 対応済 | Guide 部は全スキル allowlist 準拠（違反なし） |
| Output Spec インライン骨格 | 対応済 | 再出現なし。review 6 スキルの `common-output-format.md` は同一ハッシュ |
| DIST / E / S-05 住み分け | 対応済 | 配布 instructions に DIST なし。terraform の E-01/02 は EventBridge/CloudWatch（eval の E ではない） |
| loop ItemID（Phase C） | 「検証容易のため未」 | **訂正:** 必須ではない。優先度を下げる（§3.2） |
| bats × shell-script applyTo | （本報初版で要整理と誤記） | **訂正:** G-05 Companion Coverage の意図。修正不要（§4.1 / §6.1） |
| 最大コンテキスト負荷 | go-review / terraform-review 上位 | **agent-skills-review → go-review → terraform-review → instructions-review**（refactor は Phase F で 5 位付近） |

---

## 2. Skills — コンテキスト負荷

単語数ベース（`tokens ≈ words × 1.3`）。**SKILL.md + `(always read)` 参照のみ**（条件付き参照は含まない）。

| スキル | always ファイル数 | always 語数 | SKILL 語数 | 合計語数 | 概算 tok | checklist 安定 ID |
| ------ | ----------------- | ----------- | ---------- | -------- | -------- | ----------------- |
| agent-skills-review | 6 | 3580 | 588 | 4168 | ~5418 | 25 |
| go-review | 13 | 3271 | 658 | 3929 | ~5107 | 43 |
| terraform-review | 22 | 3050 | 773 | 3823 | ~4969 | 44 |
| instructions-review | 8 | 2685 | 751 | 3436 | ~4466 | 37 |
| refactor | 4 | 2022 | 1214 | 3236 | ~4206 | 9 (gate) |
| tech-debt | 4 | 2183 | 936 | 3119 | ~4054 | 8 (gate) |
| shell-script-review | 12 | 2518 | 555 | 3073 | ~3994 | 33 |
| github-actions-review | 9 | 1873 | 484 | 2357 | ~3064 | 21 |
| changelog | 4 | 1237 | 784 | 2021 | ~2627 | 5 (gate) |
| ci-sweeper | 4 | 1107 | 887 | 1994 | ~2592 | 4 (gate) |
| docs-updater | 3 | 879 | 823 | 1702 | ~2212 | 6 |
| github-pr-body | 2 | 444 | 696 | 1140 | ~1482 | 14 |
| github-actions-validation | 3 | 625 | 437 | 1062 | ~1380 | 13 |
| shell-script-validation | 2 | 453 | 602 | 1055 | ~1371 | 12 |
| docs-creator | 3 | 504 | 444 | 948 | ~1232 | 5 |
| go-validation | 2 | 392 | 448 | 840 | ~1092 | 17 |
| terraform-validation | 2 | 350 | 429 | 779 | ~1012 | 15 |
| markdown-validation | 2 | 313 | 438 | 751 | ~976 | 11 |

### 2.1 無駄・偏りの所見

| 問題 | 証拠 | 推奨 |
| ---- | ---- | ---- |
| **refactor always 削減** | 旧: always 7・~3692 語で最大負荷 | **対応済:** survey always 4（checklist/output/scope/operations）・合計 ~3236 語。最大負荷は agent-skills-review に移行。techniques・verification は `may_edit`、input-schema は structured/automation JSON 時 |
| **tech-debt taxonomy always** | taxonomy ~801 語を always | **意図的維持**（分類品質）。input-schema は detect 時のみ。ゲート ItemID（CLASS/EVID/EDIT 等）追加済 |
| **agent-skills-review / instructions-review** | category 全文 always（メタレビュー） | 意図的。フルチェックリスト方針と一致 |
| **review 系** | 全 category always を維持（意図的） | 現状維持。大規模 PR は出力優先度のみ調整 |
| **go-validation 失敗 category** | `category-security.md` ~1540、`category-testing.md` ~1499（read on failure） | ツール出力の読み方に圧縮候補（前報と同じ） |
| **automation-envelope 複製** | changelog/ci-sweeper/refactor/tech-debt/docs-updater 各 ~448–504 語・内容近似 | 共通契約 1 ファイル化は DIST/配布単位とトレードオフ。現状維持も妥当 |
| **github-pr-body** | always 2 のみ（baseline） | 前報対応の効果が継続 |

validation / docs-creator / pr-body baseline は ~1–1.4k tok で健全。

---

## 3. Skills — 統一性・冗長・曖昧・チェック／機能

### 3.1 統一性（良好）

- 全 18 スキルが S-01 の 5 H2（Input → Output Specification → Execution Scope → Reference Files Guide → Workflow）
- Reference Files Guide のトリガーは allowlist のみ（違反なし）
- review 6 スキルの `common-output-format.md` は同一 content hash（意図的複製）
- ほぼ全てに Error Handling 表、USE FOR / DO NOT USE FOR
- 全スキルに `eval` 系成果物あり（docs-creator のみ `scripts/` なし — validation スクリプト不要なユーティリティとして妥当）

### 3.2 安定 ItemID（loop）— 前報訂正

| スキル | checklist ID | 影響の再評価 |
| ------ | ------------- | ------------ |
| changelog / ci-sweeper / refactor / tech-debt | gate 型 ID あり（Phase C' / F） | **運用検証は困らない。** 主キーは path・failure・候補行。ItemID はゲート引用・Deferred 理由向け SHOULD（§6.1） |
| docs-updater / docs-creator | UV / QV | 自己検査ゲート用。Candidates 行の主キーではない |

**推奨（SHOULD）:** オーサリング比較や「どのゲートを Deferred にしたか」を短く引用したい場合のみ `SCOPE-01` / `EDIT-01` 等を付与。必須ロードマップから外す。

### 3.3 冗長

| 項目 | 状態 |
| ---- | ---- |
| Output Spec のインライン骨格 | 再出現なし |
| SKILL 本文と references の重複（BP-03） | refactor / tech-debt の SKILL は changelog より長い（~850–1060 語）。**現状維持推奨** — Phase A/B・architecture・automation 分岐は SKILL に残す。短縮は checklist 参照への置換など最小限のみ（BP-04 と両立するときだけ） |
| review output format 6 複製 | 配布単位のため許容。単一生成元の文書化は Low |

### 3.4 曖昧語（Q-06）

- スキル本文の `appropriately` / `as needed` / `depending on context`:**ヒットなし**
- `agent-skills-review` の `category-quality.md` / checklist に上記語が **禁止例として** 残る（メタ説明）。削除不要。誤検知に注意

description の `Use when` 文言: refactor / tech-debt は欠落気味だが、BP-01 は文言必須ではない（第三者視点 + 起動トリガー内容で可）。

### 3.5 追加チェック・機能ギャップ

| 観点 | 現状 | 推奨 |
| ---- | ---- | ---- |
| **P-03（書く前に読む）** | 生成系 Workflow には読み取りあり。checklist 固定は docs-* 以外で弱い | 必要なら ID 付き MUST（loop に ItemID を入れる場合の代表ユースケース） |
| **shell-script-validation × TEST-00** | validation は Bats 範囲外と明記。review に TEST-00 | 境界は正しい。呼び出し側再掲は任意 |
| **Input required/optional 表** | loop 5 + validation 4 + docs-creator + agent-skills-review で統一（§6.1 K 対応済） | — |
| **E-01 eval カバレッジ** | 成果物は全スキルにある | maintainer SHOULD（AGENTS.md）。review ItemID 化はしない |
| **waza 実測** | 本報は語数概算のみ | リリース前は `validate_waza.sh` / `waza check` を別途 |

### 3.6 チェック数の偏り

| スキル | ItemID 概数（category+checklist） | コメント |
| ------ | --------------------------------- | -------- |
| terraform-review | 44 | 網羅的。always 維持は意図的 |
| go-review | 43 | 同上。語数は前報より減 |
| instructions-review | 37 | メタレビューとして妥当 |
| shell-script-review | 33 | 同上 |
| agent-skills-review | 24 | 同上 |
| github-actions-review | 21 | 妥当 |
| loop 4 スキル | 4–9 (gate) | §3.2 / §6.1 Phase C'・F で gate 型 ID 導入済。必須ロードマップ外のまま |

---

## 4. Instructions

対象 8 ファイル。いずれも 5 H2（Scope → Standards → Guidelines → Testing and Validation → Security Guidelines）を持つ。

| ファイル | 概算語数 | Guidelines 形態 | 特記 |
| -------- | -------- | --------------- | ---- |
| bats.instructions.md | ~1069 | **厚**（`Check:` 子付き） | `applyTo: **/*.sh,**/*.bats` — **G-05 意図**（`.sh` 編集時にペアリング規則を載せる） |
| shell-script.instructions.md | ~961 | 薄（ItemID + title） | sync 型の模範。TEST-00 で stem `bats` を参照 |
| markdown.instructions.md | ~900 | **厚**（DOC/TERM に `Check:` + 例） | markdown-review スキル無し。常時ルールとして厚い |
| go.instructions.md | ~706 | 薄 | go-review と ID 整合。Guidelines に G-01..04 が review 側に無い差分あり（軽微） |
| agent-skills.instructions.md | ~658 | 薄（BP/P/Q/S） | Standards に Reference Files Matrix + allowlist（配布契約の正） |
| terraform.instructions.md | ~596 | 薄 | E-01/02 は EventBridge / log retention（eval E ではない） |
| instructions.instructions.md | ~476 | 薄 | applyTo が instructions + cursor/kiro/claude rules |
| github-actions-workflow.instructions.md | ~422 | 薄 | 妥当 |

### 4.1 統一性・冗長

| 問題 | 証拠 | 推奨 |
| ---- | ---- | ---- |
| **Guidelines 厚みの二極化** | markdown / bats は `Check:` 付き。他は thin sync | markdown: 常時適用のため厚みは実用上許容だが例圧縮は可。bats: suite 規約の SoT として厚みは妥当。thin 化は任意 |
| **bats × shell-script `applyTo`（訂正）** | 両方 `**/*.sh` | **現状維持（G-05）**。`.sh` 編集時に実装規則 + suite ペアリングを同時適用する意図。[instructions-sync-workflow](../../explanation/instructions-sync-workflow.md) / instructions-review G-05 と一致。狭めると TEST-00 / BAT-01 が script 編集時に落ちる |
| **agent-skills instructions の曖昧語** | Standards/説明に Q-06 禁止語の列挙 | 禁止リストとしての出現は可。本文ルールには使わない（現状問題なし） |
| **QUAL-02 冗長** | markdown DOC-05 に ✅❌ 長例 | always-on instructions としてはトークンコスト。例を薄くするか review 移管方針を決める |

### 4.2 Skills × Instructions 住み分け

| レイヤ | 役割 | 現状 |
| ------ | ---- | ---- |
| instructions（配布 always-on） | 薄い ItemID + 非自明 Standards | sync 対象は概ね準拠。markdown/bats 例外 |
| `*-review` category | Check / Why / Fix | review 起動時 always |
| `.apm/AGENTS.md` / 本リポ CLAUDE.md | DIST、Loop、maintainer | 配布 instructions に埋め込まない方針を維持 |
| loop 出力契約 | Candidates/Changes/Deferred + path 照合 | ItemID 不要（§3.2） |

---

## 5. 記載テンプレ（維持）

**review 系（フルチェックリスト）:** 全 `category-*.md` を `(always read)`。troubleshooting は `(read on failure)`。

**loop / 生成系:** automation 文書は `(read on automation path)`。対話パスで不要な schema/techniques は遅延候補。

**スクリプト主導 + AI 補完（github-pr-body）:** baseline = checklist + output。full-body / debugging / failure で分岐 — 現状が模範。

---

## 6. 推奨ロードマップと残タスク

### 6.1 対応済・現状維持（作業不要）

| フェーズ | 内容 | 状態 |
| -------- | ---- | ---- |
| A–B, D–E | review Workflow / トリガー allowlist / DIST·E 住み分け / 表記整理 | **対応済（2026-07-26）** |
| F | refactor / tech-debt: always 条件調整 + ゲート ItemID（内容削除なし） | **対応済（2026-07-29）** |
| G | bats × shell-script `applyTo`（`**/*.sh` 重複） | **現状維持（G-05 意図）** — 修正タスクから除外 |
| L | checklist ItemID 記載メタ（index vs gate）を BP-05 + Standards に定義 | **対応済（2026-07-29）** — 混成禁止。全 common-checklist を index/gate/recipe に正規化 |
| C' | changelog / ci-sweeper ゲート ItemID | **対応済（2026-07-29）** — MAP/LINK/REL/SCOPE/OUT、CLASS/SCOPE/VERIFY/OUT（gate 型） |
| K | Input `(required)` / `(optional)` 表記 | **対応済（2026-07-29）** — loop 5 + docs-creator + validation 4 + agent-skills-review |

### 6.2 残タスク（修正が必要・検討対象）

| ID | 優先度 | 対象 | やること | 完了条件 |
| -- | ------ | ---- | -------- | -------- |
| **H** | Medium | `markdown.instructions.md` | DOC-05 等の長例・`Check:` 子を圧縮するか、markdown-review（未存在）へ Check/Why/Fix を移す方針を決めて実施 | always-on 語数が薄 sync 帯に近づく、または「厚みは意図的」と Standards に一文で固定 |
| **H2** | Medium | `bats.instructions.md` | companion として厚み意図的と明記（`bats-review` は作らない） | 方針が文書化され、shell-script-review TEST-00 と二重定義が無い |
| **BP** | Low（任意） | `refactor` / `tech-debt` `SKILL.md` | BP-03: **記載レベル・loop 間の統一性を損なわない範囲でのみ**短縮。語数合わせは目的にしない | changelog 帯（~700 語）への無理な寄せは **BP-04 違反**。現状は Phase A/B・architecture・automation 分岐のため長さは妥当。**見送り推奨** |
| **I** | Low | `go-validation` failure categories | `category-security.md` / `category-testing.md` をツール出力の読み方中心に圧縮 | 失敗時ロード語数が大幅減。一般 Go 論が残らない |
| **J** | Low | loop `category-automation-envelope.md` | 5 スキル近似複製の共通化是非を説明ドキュメントに一文で決める（実装は任意） | 「共通化しない / する」が docs に残る |

### 6.3 検証・計測（レポート外の未実施）

| ID | 内容 | メモ |
| -- | ---- | ---- |
| **V1** | 全スキル `validate_waza.sh` / `waza check` | 本報は語数概算のみ |
| **V2** | 必要なら `waza run eval.yaml` | リリースバーは AGENTS.md SHOULD |
| **V3** | 配布先 `.cursor/rules` 等の二次監査 | ソース SoT 監査とは別 |

---

## 7. 調査方法・限界

- ソース: `.apm/packages/**/skills/**`、`.apm/packages/**/instructions/*.instructions.md`
- 定量: 語数、always-read リンク解析、ItemID 抽出、`common-output-format.md` content hash、曖昧語パターン、applyTo 比較
- **未実施:** 各スキルの `validate_waza.sh` / `waza check` 実走、`waza run eval.yaml`、エージェント実機トークン計測、配布先 `.cursor/rules` の二次監査
- 概算 tok は語数×1.3。実トークナイザとはずれる
- always 語数は Reference Files Guide の `(always read)` のみ。条件付き参照を読む実行ではさらに増える

## 関連

- 前報: [Agent Skills Evaluation (2026-07-26)](2026-07-26-evaluation.md)
- 評価スキル: `.apm/packages/common/.apm/skills/agent-skills-review/`、`instructions-review/`
- オーサリング: `.apm/packages/common/.apm/instructions/agent-skills.instructions.md`、`instructions.instructions.md`
- Loop 出力: [Loop Automation Report Format](../../explanation/loop-engineering/common-loop-triage-format.md)
- Waza: [docs/report/waza/](../waza/waza-capabilities.md)
