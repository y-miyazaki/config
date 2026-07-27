# Agent Skills 評価レポート（`.apm` 配下）

- **調査日:** 2026-07-26
- **対象:** `.apm/packages/*/.apm/skills/*/SKILL.md`（18 スキル）
- **評価基準:** `agent-skills-review` の S/Q/P/BP チェック、および `agent-skills.instructions.md`
- **本レポートの位置づけ:** 初回調査 + 2026-07-26 追記（方針確定・一部改修反映）

## 要約

構造（S-01 の 5 H2）は全スキルで揃っている。review 系は **category を `(always read)` としフルチェックリストを適用する**方針に統一（Workflow の選択的読込記述は削除済）。一方で **always-read 参照の語数**（特に go-review / github-pr-body / loop 系）はコンテキスト負荷として残る。チェックリストは review/validation 系は ItemID が充実する一方、**changelog / ci-sweeper / refactor / tech-debt は安定 ID が無く** Failed/Deferred 報告や横断比較がしづらい。記載面では **Output Spec へのインライン骨格の重複**（対応済）、矛盾したロード契約（**対応済:** 単一トリガー語彙）、description の `Use when` 欠落が改善余地。

## 対象スキル一覧とコンテキスト負荷

単語数ベースの概算（`tokens ≈ words × 1.3`）。**SKILL.md + always-read 参照**を起動時に読む想定。

| スキル                    | always ファイル数 | always 語数 | SKILL 語数 | 合計語数 | 概算 tok |
| ------------------------- | ----------------- | ----------- | ---------- | -------- | -------- |
| go-review                 | 14                | 5423        | 638        | 6061     | ~7879    |
| github-pr-body            | 2                 | 452         | 631        | 1083     | ~1408    |
| refactor                  | 9                 | 4573        | 942        | 5515     | ~7169    |
| terraform-review          | 21                | 3769        | 714        | 4483     | ~5827    |
| tech-debt                 | 6                 | 3458        | 799        | 4257     | ~5534    |
| shell-script-review       | 13                | 3365        | 511        | 3876     | ~5038    |
| agent-skills-review       | 5                 | 2970        | 693        | 3663     | ~4761    |
| instructions-review       | 8                 | 2439        | 731        | 3170     | ~4121    |
| ci-sweeper                | 6                 | 1816        | 722        | 2538     | ~3299    |
| changelog                 | 5                 | 1815        | 701        | 2516     | ~3270    |
| github-actions-review     | 8                 | 1968        | 443        | 2411     | ~3134    |
| docs-updater              | 4                 | 1300        | 662        | 1962     | ~2550    |
| github-actions-validation | 3                 | 683         | 390        | 1073     | ~1394    |
| shell-script-validation   | 2                 | 491         | 562        | 1053     | ~1368    |
| docs-creator              | 3                 | 583         | 417        | 1000     | ~1300    |
| go-validation             | 2                 | 445         | 405        | 850      | ~1105    |
| terraform-validation      | 2                 | 403         | 362        | 765      | ~994     |
| markdown-validation       | 2                 | 361         | 387        | 748      | ~972     |

validation 系は概ね健全（~1k tok）。review / PR body / loop 系が突出。

---

## 1. コンテキストの無駄（Context Waste）

### 1.1 review 系の always-read とトークンコスト

**対応済（2026-07-26）:** terraform-review / go-review / shell-script-review / github-actions-review の Workflow にあった「該当 category だけ読む」「changed files に触れる category のみ」等の記述を削除。Ref Guide の `(always read)` と `Apply the full review checklist` で一致。

**方針:** review 系はフルチェックリストレビューが目的。`common-checklist.md`（索引）と全 `category-*.md`（Check/Why/Fix）を起動時に読み、全 ItemID を評価する。狭い PR でも見落としを避けるため、category の条件付き遅延ロードは**採用しない**。トークンコストは許容する設計トレードオフ（下表の語数は情報量として記録）。

| スキル                    | always category 数 | always 語数（category 部） | 状態                                                                       |
| ------------------------- | ------------------ | -------------------------- | -------------------------------------------------------------------------- |
| **terraform-review**      | 19                 | ~2700                      | **意図的** — 全 category always。Workflow 矛盾は解消済                     |
| **go-review**             | 12                 | ~4200                      | **意図的** — 同上。大規模 PR（>50 ファイル）は step 6 で出力優先度のみ調整 |
| **shell-script-review**   | 11                 | ~2400                      | **意図的** — 同上                                                          |
| **github-actions-review** | 6                  | ~1400                      | **意図的** — 同上                                                          |

**まだ検討余地があるもの（review 系以外）:**

| 問題                                        | 証拠                                           | 推奨                                                                                                                                             |
| ------------------------------------------- | ---------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------ |
| **github-pr-body** の category 遅延ロード   | 実装詳細・分類・workflows を always にしていた | **対応済（2026-07-26）:** baseline は checklist + output のみ always。full-body は guidelines/template-mapping、失敗時・デバッグ時にその他を読む |
| **refactor / tech-debt** の automation 文書 | `category-automation-envelope.md` 等           | **対応済:** `(read on automation path)` に正規化。対話パスでは読まない                                                                           |

**参考:** **go-validation** はスクリプトが先に走るため、重い `category-security.md` / `category-testing.md` を `(read on failure)` にしている（review とは前提が異なるパターン）。

### 1.2 Output 契約の二重定義（P-02 / BP-03）

- review 系 6 スキル（agent-skills / github-actions / instructions / go / shell-script / terraform）の `common-output-format.md` は **同一ハッシュ**（保守上のコピー同期コストあり。配布ポータビリティのため意図的なら許容）。
- ~~うち複数が SKILL.md 内に ```markdown 骨格（~39–59 語）を再掲。~~ **対応済（2026-07-26）:** Output Spec は `common-output-format.md` への参照 + SoT 一文に統一。骨格フェンスは削除。
- agent-skills-review の Examples も骨格再掲をやめ、同ファイル参照に変更。

### 1.3 モデル既知知識・冗長説明（BP-03）

- go-validation の failure 用 category（`category-security.md` / `category-testing.md`、各 ~1500 語）は失敗時のみ読込だが、汎用 Go 知識が厚く圧縮候補（validate.sh 出力の読み方に留めるならさらに薄くできる）。
- loop 系の `category-automation-envelope.md` はスキルごとに ~440–500 語で内容が近似。共通契約を 1 ファイルに寄せられるならパッケージ横断の複製コストを削減できる（DIST-01 とトレードオフ。配布単位がスキルな各 ~1500 語 — 失敗時のみでも、ツール出力の読み方以上に一般論が厚い場合は圧縮候補。なら現状維持も妥当）。

### 1.4 ロード契約の曖昧さによる過剰読込

**対応済（2026-07-26）:** ロードトリガーは allowlist のみ許可。BP-02 / instructions は「許容語彙以外を指摘」方式（特定の誤り文言の列挙ではない）。

---

## 2. チェック項目の不足・不整合

### 2.1 安定 ItemID の欠如（loop / 運用系）

| スキル       | checklist の ID          | 影響                                     |
| ------------ | ------------------------ | ---------------------------------------- |
| changelog    | なし（表・箇条書きのみ） | Failed/Deferred を ItemID で追跡できない |
| ci-sweeper   | なし                     | 同上                                     |
| refactor     | なし（ゲート叙述のみ）   | survey/apply ゲートを ID 参照できない    |
| tech-debt    | なし                     | taxonomy はあるがチェック ID が無い      |
| docs-updater | UV-01〜06（良い）        | 模範                                     |
| docs-creator | QV-01〜05（良い）        | 模範                                     |

**推奨:** loop 系も `SCOPE-01` / `EDIT-01` / `VERIFY-01` のような短い安定 ID を付け、出力の Candidates/Deferred 行と対応させる。

### 2.2 agent-skills-review チェックリストと instructions のギャップ

**方針確定（2026-07-26）:** review checklist と instructions Standards の住み分け。

| 項目                         | 扱い                                                                                                                                                                          |
| ---------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **DIST（再配布ポリシー）**   | **review ItemID にしない** — [.apm/AGENTS.md § Redistribution policy (DIST)](../../../.apm/AGENTS.md#redistribution-policy-dist--this-repository-only) の maintainer ポリシー |
| **S-05（Output SoT）**       | **対応済** — Standards から削除。review の **P-02** に一本化                                                                                                                  |
| **S-04（Clarity over DRY）** | Standards に残す。単独 review ItemID は不要（メタ原則）                                                                                                                       |
| **S-06（`<agent-root>`）**   | Standards + `validate.sh` でカバー。review は S-07 と併用                                                                                                                     |
| **E-01 / E-03（eval）**      | **review ItemID にしない** — AGENTS.md release bar で SHOULD（maintainer 判断）。ツール差（waza / skill-creator）のため強制困難                                               |
| **E-02 / E-04**              | checklist 対象外                                                                                                                                                              |

Guidelines（P/Q/S/BP）は `category-*.md` から sync 生成。実務レビューは現行 checklist で足りる。

### 2.3 terraform-review: COMP ID の飛び番

**対応済（2026-07-26）:** 削除済みだった COMP-01/02（組織ガバナンス・trivy pipeline）は復元せず、残存項目を **COMP-01**（No Default VPC/Open SG/Public S3）・**COMP-02**（IAM jsonencode / aws_iam_policy_document）に再採番。`terraform.instructions.md` も同期。

### 2.4 スキル横断で足りない／弱い観点

| 観点                                  | 現状                                                                                                                  | 推奨                                                                                             |
| ------------------------------------- | --------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------ |
| **P-03（書く前に読む）**              | 生成・更新系（docs-*/changelog/pr-body）は Workflow に読み取りがあるが、checklist Item として固定していないものがある | 「編集前に対象ファイル／detect JSON を読む」を ID 付き MUST にする                               |
| **shell-script-validation × TEST-00** | validation は Bats ペアリングを範囲外と明記。review に TEST-00 あり                                                   | 境界は正しい。呼び出し側ドキュメントで「validation だけでは TEST-00 は見ない」を再掲すると誤用減 |
| **Q-11（必須/任意パラメータ）**       | Input 節はあるが、defaults と required の表形式が弱いスキルあり                                                       | Input を「required / optional+default」の表に揃える                                              |
| **E-01 eval カバレッジ**              | 多くのスキルに eval はある                                                                                            | **方針確定:** maintainer SHOULD（AGENTS.md）。review ItemID 化はしない                           |

### 2.5 チェック数の偏り（過不足の両面）

| スキル                | checklist Item 数（概数） | コメント                                                                                                              |
| --------------------- | ------------------------- | --------------------------------------------------------------------------------------------------------------------- |
| go-review             | ~100                      | 網羅的。全 category always-read は意図的（トークンコストは許容）。大規模 PR は security/correctness 優先の defer のみ |
| shell-script-review   | ~65                       | 同上                                                                                                                  |
| terraform-review      | ~66                       | カテゴリ分割は良い。全 category always は意図的                                                                       |
| github-actions-review | ~28                       | 妥当                                                                                                                  |
| markdown-validation   | ~11                       | 妥当                                                                                                                  |

「項目不足」だけでなく、**go-review は項目数が多く always-read 参照も大きい**点はトークン負荷として記録するが、review の網羅性のため現状維持とする。

---

## 3. 記載方法の改善点

### 3.1 よくできている点

- 全 18 スキルが S-01 の 5 H2（Input → Output → Scope → References → Workflow）をフェンス外で正しく持つ
- ほぼ全てに `### Error Handling` 表あり（Q-10）
- `### USE FOR` / `### DO NOT USE FOR` の境界が揃っている（Q-02）
- description の大半が第三者視点 + 起動トリガー文（BP-01; `Use when` は推奨で非必須）
- Output Spec は要約、詳細は references（**P-02** の方向性）

### 3.2 改善すべき記載

| 項目                                     | 対象例                                                       | 改善                                                                                                                                                                                                                                     |
| ---------------------------------------- | ------------------------------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Naming Conventions の過剰義務**        | STRUCT-04/STD-01 が常識表を強制                              | **対応済:** STD-01/STRUCT-04 を SHOULD（非自明のみ）。terraform/shell/markdown 等の常識表を削除または圧縮                                                                                                                                |
| **BP-01: トリガー文の扱い**              | refactor, tech-debt 等                                       | **対応済:** 文言 `Use when` は必須にしない。第三者視点 + 起動トリガー内容 + 実装手順なしを BP-01 とし、`validate.sh` の literal 欠落 Fail を削除                                                                                         |
| **矛盾するロード契約**                   | refactor / tech-debt / changelog 等の `always read — … path` | **対応済:** allowlist 単一トリガー（`(read on automation path)` 等）に正規化。compound `always read —` は残存なし                                                                                                                        |
| **曖昧語（Q-04a）**                      | `appropriately` 等の行動隠蔽語                               | **対応済:** `appropriately`/`as needed`/`depending on context` 等は具体化。`etc.` は代表例の後なら可（列挙不能・LLM 判断レイヤ）                                                                                                         |
| **インライン出力骨格**                   | review 系 SKILL の ```markdown                               | **対応済:** Output Spec / Examples から削除。Result は `common-output-format.md` 参照                                                                                                                                                    |
| **Examples の形式強制**                  | Prompt/Command/Result 固定や骨格禁止をルール化               | **対応済:** review ItemID も Writing Style 制約も削除。出力重複は P-02/BP-03 の範囲で判断                                                                                                                                                |
| **DIST / E / S-05 の二重掲載**           | instructions Standards と review の乖離                      | **対応済:** DIST/E は maintainer 文書（`.apm/AGENTS.md`）のみ。配布 instructions からはリンク削除。S-05 削除 → P-02                                                                                                                      |
| **Scope のパス列挙**                     | `*.go` / `.github/workflows/…` 等を Scope に重複             | **対応済:** 意図一文に変更（`applyTo` がパスを担う）                                                                                                                                                                                     |
| **Input の型・必須**                     | 表記のばらつき（`(required)` の有無など）                    | **低優先:** 全スキル既に箇条書き。ループ系は各 `SKILL.md` と [Loop Engineering](../../explanation/loop-engineering/index.md) / [apm-package-design.md](../../explanation/apm-package-design.md) を参照（配布 instructions には載せない） |
| **Workflow と Ref Guide の矛盾**         | review 系の「該当 category のみ」記述                        | **対応済:** 4 review スキルで削除。全 category `(always read)` + フルチェックリスト適用に統一                                                                                                                                            |
| **Workflow の分岐表記**                  | loop 系の `When may_edit…` 混在                              | **対応済:** changelog / ci-sweeper / tech-debt / docs-updater / refactor で `IF` / `ELSE IF` / `ELSE` の数値付き箇条書きに統一                                                                                                           |
| **カテゴリファイルのヘッダ階層（S-03）** | 概ね準拠                                                     | 新規追加時も category は H2 起点を維持                                                                                                                                                                                                   |

### 3.3 記載テンプレ提案（Reference Files Guide）

**review 系（フルチェックリスト）:**

```markdown
- [common-checklist.md](references/common-checklist.md) (always read)
- [common-output-format.md](references/common-output-format.md) (always read)
- [category-global.md](references/category-global.md) (always read)
- [category-security.md](references/category-security.md) (always read)
- …（全 category-*.md を always read）
- [common-troubleshooting.md](references/common-troubleshooting.md) (read on failure)
```

**loop / 生成系（パス分岐あり）:**

```markdown
- [category-automation-envelope.md](references/category-automation-envelope.md) (read on automation path)
```

**スクリプト主導 + AI 補完（github-pr-body 型）:**

```markdown
- [common-checklist.md](references/common-checklist.md) (always read)
- [common-output-format.md](references/common-output-format.md) (always read)
- [category-pr-body-guidelines.md](references/category-pr-body-guidelines.md) (read when full-body mode)
- [category-implementation-details.md](references/category-implementation-details.md) (read on debugging)
- [common-troubleshooting.md](references/common-troubleshooting.md) (read on failure)
```

許容外のトリガーは指摘対象（allowlist 外）。

---

## 4. スキル別ハイライト

### 優先度 High（コンテキスト削減）

1. **refactor / tech-debt** — SKILL 本文のスリム化（automation 文書の条件付きロードは対応済）

**対応済・現状維持:** review 4 スキル（terraform / go / shell-script / github-actions）は全 category `(always read)` を意図的設計とする（1.1 参照）。**github-pr-body** は baseline / full-body / failure / debugging で参照を分離（1.1 参照）。

### 優先度 Medium（チェック・契約）

1. **changelog / ci-sweeper / refactor / tech-debt** — 安定 ItemID 導入
2. **terraform-review** — COMP 欠番（対応済）

### 優先度 Low（表記統一）

1. refactor / tech-debt の description に起動トリガー内容（文言は任意; `Use when` 推奨）
2. 曖昧語の一掃、インライン骨格の削除
3. review 系 `common-output-format.md` の同期戦略（単一生成元 vs 意図的複製）の文書化

### 良好（参考実装）

- **markdown-validation / terraform-validation / go-validation** — always 負荷が低い
- **docs-creator / docs-updater** — checklist に QV/UV ID + PASS 条件
- **validation 系全般** — 重い category を failure 時のみにするパターン

---

## 5. 推奨ロードマップ

| フェーズ | 内容                                                                             | 期待効果                       | 状態                                                       |
| -------- | -------------------------------------------------------------------------------- | ------------------------------ | ---------------------------------------------------------- |
| A        | review 系の Workflow / Ref Guide 整合（全 category always + フルチェックリスト） | 契約矛盾の解消                 | **対応済（2026-07-26）**                                   |
| B        | github-pr-body / loop の参照トリガー正規化                                       | 対話パスの無駄読み削減         | pr-body 対応済（2026-07-26）。loop automation 分岐は対応済 |
| C        | loop checklist に ItemID                                                         | レポート比較・自動化検証が容易 | 未                                                         |
| D        | instructions / review の DIST・E・S-05 住み分け                                  | maintainer vs checklist の整理 | **対応済（2026-07-26）**                                   |
| E        | 表記統一（起動トリガー・曖昧語・骨格削除）                                       | 発見性・実行精度の底上げ       | 大部分対応済                                               |

---

## 6. 調査方法・限界

- ソース: `.apm/packages/**/skills/**/SKILL.md` および `references/`
- 定量: 語数・ファイル数・ItemID 抽出・always-read リンク解析・content hash
- **未実施:** 各スキルの `validate_waza.sh` / `waza check` 実走、`waza run eval.yaml`、エージェント実機でのトークン計測
- 概算 tok は語数×1.3。実トークナイザとはずれる

## 関連

- 評価スキル: `.apm/packages/common/.apm/skills/agent-skills-review/`
- オーサリング規則: `.apm/packages/common/.apm/instructions/agent-skills.instructions.md`
- Waza 関連レポート: [docs/report/waza/](../waza/waza-capabilities.md)
