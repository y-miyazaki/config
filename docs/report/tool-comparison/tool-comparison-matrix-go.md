# Tool Comparison Matrix (Go)

Go 開発に特化したツール選定の判断材料。

## History

| 日付       | 内容                                                                               |
| ---------- | ---------------------------------------------------------------------------------- |
| 2026-05-21 | History セクション追加                                                             |
| 2026-05-12 | 初版作成。Formatter / Linter / Container Build / Release / API Doc / Mock 等を比較 |

## Formatter: gofumpt vs gofmt vs goimports

| 比較項目           | gofumpt                                           | gofmt                                     | goimports                                       |
| ------------------ | ------------------------------------------------- | ----------------------------------------- | ----------------------------------------------- |
| 提供元             | mvdan                                             | Go 公式                                   | Go 公式                                         |
| リポジトリ         | [mvdan/gofumpt](https://github.com/mvdan/gofumpt) | [golang/go](https://github.com/golang/go) | [golang/tools](https://github.com/golang/tools) |
| ライセンス         | BSD-3-Clause                                      | BSD-3-Clause                              | BSD-3-Clause                                    |
| 位置づけ           | gofmt の厳格版                                    | 標準フォーマッター                        | gofmt + import 整理                             |
| gofmt 互換         | ✅ (上位互換)                                     | -                                         | ✅                                              |
| 追加ルール         | 空行削除、グルーピング強制等                      | なし                                      | import のみ                                     |
| import 整理        | ❌                                                | ❌                                        | ✅                                              |
| golangci-lint 統合 | ✅                                                | ✅                                        | ✅                                              |

### Guidelines

**→ gofumpt を採用する。** gofmt の上位互換で、より厳格なルールによりチーム内のスタイルが統一される。golangci-lint 経由で実行可能。

- goimports は import 整理に特化しており、gofumpt と併用可能

## Linter: go vet vs golangci-lint vs staticcheck

| 比較項目         | go vet                                    | golangci-lint                                                       | staticcheck                                               |
| ---------------- | ----------------------------------------- | ------------------------------------------------------------------- | --------------------------------------------------------- |
| 提供元           | Go 公式                                   | golangci                                                            | Dominik Honnef                                            |
| リポジトリ       | [golang/go](https://github.com/golang/go) | [golangci/golangci-lint](https://github.com/golangci/golangci-lint) | [dominikh/go-tools](https://github.com/dominikh/go-tools) |
| ライセンス       | BSD-3-Clause                              | GPL-3.0                                                             | MIT                                                       |
| 位置づけ         | Go 標準ツール                             | メタリンター (複数リンター統合)                                     | 単体リンター                                              |
| 内蔵リンター数   | 1                                         | 100+                                                                | 1 (多数のチェック含む)                                    |
| 設定ファイル     | なし                                      | `.golangci.yaml`                                                    | `staticcheck.conf`                                        |
| 自動修正         | ❌                                        | ✅ (一部リンター)                                                   | ❌                                                        |
| CI 向け最適化    | ✅                                        | ✅ (差分チェック、キャッシュ)                                       | ⚠️ 限定的                                                 |
| staticcheck 含む | ❌                                        | ✅                                                                  | -                                                         |
| go vet 含む      | -                                         | ✅                                                                  | ❌                                                        |

### Guidelines

**→ golangci-lint を採用する。** staticcheck・go vet を含む 100+ のリンターを一括管理でき、差分チェック・キャッシュ・自動修正に対応。これ一つで十分。

## Container Build: Docker vs kaniko vs ko

| 比較項目        | Docker (BuildKit)                                 | kaniko                                                                        | ko                                            |
| --------------- | ------------------------------------------------- | ----------------------------------------------------------------------------- | --------------------------------------------- |
| 提供元          | Docker Inc                                        | Google                                                                        | Google (OSS)                                  |
| リポジトリ      | [moby/buildkit](https://github.com/moby/buildkit) | [GoogleContainerTools/kaniko](https://github.com/GoogleContainerTools/kaniko) | [ko-build/ko](https://github.com/ko-build/ko) |
| ライセンス      | Apache 2.0                                        | Apache 2.0                                                                    | Apache 2.0                                    |
| 対応言語        | 任意                                              | 任意                                                                          | Go 専用                                       |
| Dockerfile 不要 | ❌                                                | ❌                                                                            | ✅                                            |
| ビルド速度      | 中程度                                            | 中程度                                                                        | 非常に高速                                    |
| CI での特権不要 | ❌ (Docker daemon 必要)                           | ✅                                                                            | ✅                                            |
| イメージサイズ  | Dockerfile 依存                                   | Dockerfile 依存                                                               | 最小 (distroless ベース)                      |

### Guidelines

**→ Go アプリケーションには ko を採用する。** Dockerfile 不要で高速・最小イメージ・CI で特権不要。

- Go 以外の言語を含む / 複雑なビルドステップが必要な場合は Docker を使用
- Docker daemon なしで任意の Dockerfile をビルドしたい場合は kaniko を使用

## Release Automation: GitHub Releases vs goreleaser vs semantic-release

| 比較項目         | GitHub Releases (手動) | goreleaser                                                        | semantic-release                                                                          |
| ---------------- | ---------------------- | ----------------------------------------------------------------- | ----------------------------------------------------------------------------------------- |
| 提供元           | GitHub                 | goreleaser                                                        | semantic-release                                                                          |
| リポジトリ       | - (GitHub 組み込み)    | [goreleaser/goreleaser](https://github.com/goreleaser/goreleaser) | [semantic-release/semantic-release](https://github.com/semantic-release/semantic-release) |
| ライセンス       | 商用 (GitHub に含む)   | MIT                                                               | MIT                                                                                       |
| 対応言語         | 任意                   | Go 中心 (他言語も可)                                              | 任意                                                                                      |
| クロスコンパイル | 手動                   | ✅ 自動                                                           | ❌                                                                                        |
| Changelog 生成   | 手動                   | ✅ 自動                                                           | ✅ 自動                                                                                   |
| バージョニング   | 手動                   | 手動 (Git tag)                                                    | ✅ 自動 (Conventional Commits)                                                            |
| バイナリ配布     | 手動アップロード       | ✅ (tar.gz, zip, deb, rpm)                                        | ❌                                                                                        |
| Docker イメージ  | 別途設定               | ✅ ビルド+プッシュ                                                | 別途設定                                                                                  |
| Homebrew 連携    | ❌                     | ✅                                                                | ❌                                                                                        |

### Guidelines

**→ Go プロジェクトには goreleaser を採用する。** クロスコンパイル + マルチプラットフォーム配布 + Docker イメージ + Homebrew を一括管理できる。

- Go 以外の言語で Conventional Commits ベースの自動バージョニングが欲しい場合は semantic-release を検討

## API Documentation: go-swagger vs oapi-codegen vs swag

| 比較項目         | go-swagger                                                        | oapi-codegen                                                              | swag                                          |
| ---------------- | ----------------------------------------------------------------- | ------------------------------------------------------------------------- | --------------------------------------------- |
| 提供元           | go-swagger                                                        | oapi-codegen                                                              | swaggo                                        |
| リポジトリ       | [go-swagger/go-swagger](https://github.com/go-swagger/go-swagger) | [oapi-codegen/oapi-codegen](https://github.com/oapi-codegen/oapi-codegen) | [swaggo/swag](https://github.com/swaggo/swag) |
| ライセンス       | Apache 2.0                                                        | Apache 2.0                                                                | MIT                                           |
| アプローチ       | OpenAPI ↔ コード (双方向)                                         | OpenAPI → コード                                                          | コード → OpenAPI (アノテーション)             |
| 入力             | OpenAPI spec / Go コード                                          | OpenAPI spec (YAML/JSON)                                                  | Go コメント (アノテーション)                  |
| 出力             | Go サーバー/クライアントコード                                    | Go サーバー/クライアントコード                                            | OpenAPI JSON/YAML + Swagger UI                |
| 型安全性         | 高い                                                              | 高い                                                                      | 中程度 (アノテーション依存)                   |
| スキーマ駆動開発 | ✅                                                                | ✅ (スキーマファースト)                                                   | ❌ (コードファースト)                         |

### Guidelines

**→ oapi-codegen を採用する (スキーマファースト)。** API 設計を先に行い、型安全なコードを自動生成する。spec が Single Source of Truth となりチーム開発に最適。

- 既存コードからドキュメントを生成したい (コードファースト) 場合は swag を検討

## Protocol Buffers: buf

| 比較項目             | buf                                                               |
| -------------------- | ----------------------------------------------------------------- |
| 提供元               | Buf Technologies                                                  |
| リポジトリ           | [bufbuild/buf](https://github.com/bufbuild/buf)                   |
| ライセンス           | Apache 2.0                                                        |
| 用途                 | protobuf の Lint / Format / Breaking Change 検出 / コード生成管理 |
| Lint                 | ✅ (スタイル・命名規則)                                           |
| Format               | ✅                                                                |
| Breaking Change 検出 | ✅                                                                |
| BSR (レジストリ)     | ✅ (Buf Schema Registry)                                          |
| protoc 代替          | ✅ (`buf generate`)                                               |

### Guidelines

**→ buf を採用する。** protobuf 開発のオールインワンツール。Lint・Format・Breaking Change 検出・コード生成を統一管理でき、protoc を直接使うより開発体験が大幅に向上する。

## Live Reload: air

| 比較項目               | air                                                                   |
| ---------------------- | --------------------------------------------------------------------- |
| 提供元                 | air-verse                                                             |
| リポジトリ             | [air-verse/air](https://github.com/air-verse/air)                     |
| ライセンス             | GPL-3.0                                                               |
| 用途                   | Go アプリケーションのライブリロード (ファイル変更検知 → 自動リビルド) |
| 設定ファイル           | `.air.toml`                                                           |
| カスタムビルドコマンド | ✅                                                                    |
| ファイル除外           | ✅ (glob パターン)                                                    |
| ログカラー             | ✅                                                                    |

### Guidelines

**→ air を採用する。** Go のローカル開発でファイル変更時に自動リビルド・再起動を行うデファクトツール。設定が `.air.toml` で宣言的に管理でき、チームで統一しやすい。

## Vulnerability Scanning (Go): govulncheck

| 比較項目       | govulncheck                                   |
| -------------- | --------------------------------------------- |
| 提供元         | Go 公式                                       |
| リポジトリ     | [golang/vuln](https://github.com/golang/vuln) |
| ライセンス     | BSD-3-Clause                                  |
| 用途           | Go モジュールの既知脆弱性検出                 |
| 脆弱性 DB      | Go Vulnerability Database (公式)              |
| 到達可能性分析 | ✅ (実際に呼ばれるコードパスのみ報告)         |
| JSON 出力      | ✅                                            |
| CI 統合        | ✅ (`go install` で導入可能)                  |

### Guidelines

**→ govulncheck を採用する。** Go 公式の脆弱性スキャナー。到達可能性分析により誤検知が少なく、実際に影響のある脆弱性のみを報告する。Trivy と併用することで多層防御を実現。

## Mock Generation: gomock vs mockery vs moq

| 比較項目           | gomock (uber-go/mock)                           | mockery                                             | moq                                           |
| ------------------ | ----------------------------------------------- | --------------------------------------------------- | --------------------------------------------- |
| 提供元             | Uber (golang/mock から移行)                     | vektra                                              | Mat Ryer                                      |
| リポジトリ         | [uber-go/mock](https://github.com/uber-go/mock) | [vektra/mockery](https://github.com/vektra/mockery) | [matryer/moq](https://github.com/matryer/moq) |
| ライセンス         | Apache 2.0                                      | BSD-3-Clause                                        | MIT                                           |
| 最新バージョン     | v0.5.x (2025)                                   | v3 (2026-03)                                        | v0.5.3 (2025-02)                              |
| アプローチ         | コード生成 + DSL                                | コード生成 (testify/mock ベース)                    | コード生成 (関数フィールド)                   |
| コード生成ツール   | `mockgen`                                       | `mockery`                                           | `moq`                                         |
| go generate 対応   | ✅                                              | ✅                                                  | ✅                                            |
| Generics 対応      | ✅                                              | ✅                                                  | ✅                                            |
| 呼び出し順序検証   | ✅ (`InOrder`, `gomock.InOrder`)                | ✅ (`.On().After()`)                                | ❌                                            |
| 呼び出し回数検証   | ✅ (`Times`, `MinTimes`, `MaxTimes`)            | ✅ (`.Times()`)                                     | ❌ (手動で実装)                               |
| 引数マッチャー     | ✅ (豊富: `Any`, `Eq`, カスタム)                | ✅ (testify の `mock.Anything` 等)                  | ❌ (関数内で自前検証)                         |
| 外部依存           | なし                                            | testify                                             | なし                                          |
| 生成コードの複雑さ | 中程度 (Controller + Recorder)                  | 中程度 (testify/mock 埋め込み)                      | 低い (シンプルな struct)                      |
| 学習コスト         | 中程度                                          | 低い (testify 利用者なら容易)                       | 非常に低い                                    |

### Guidelines

**→ mockery を採用する (testify 利用プロジェクト)。** testify/mock ベースのコード生成により、既に testify を使っているプロジェクトでは学習コストが最小。v3 で設定が `packages` ベースに統一され、`go generate` との統合も改善。

- testify に依存したくない / よりシンプルな mock が欲しい場合は moq を検討。関数フィールドベースで IDE 補完が効きやすく、生成コードが読みやすい
- 呼び出し順序・回数の厳密な検証が必要な場合は gomock を検討。DSL が最も表現力が高い
- `golang/mock` はアーカイブ済み。gomock を使う場合は必ず `go.uber.org/mock` を使用すること
