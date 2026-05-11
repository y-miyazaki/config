<!-- omit in toc -->
# Tool Comparison Matrix (Go)

Go 開発に特化したツール選定の判断材料。

<!-- omit in toc -->
## Table of Contents

- [Formatter: gofumpt vs gofmt vs goimports](#formatter-gofumpt-vs-gofmt-vs-goimports)
  - [Guidelines](#Guidelines)
- [Linter: golangci-lint vs staticcheck vs go vet](#linter-golangci-lint-vs-staticcheck-vs-go-vet)
  - [Guidelines](#Guidelines-1)
- [Container Build: ko vs Docker vs kaniko](#container-build-ko-vs-docker-vs-kaniko)
  - [Guidelines](#Guidelines-2)
- [Release Automation: goreleaser vs GitHub Releases vs semantic-release](#release-automation-goreleaser-vs-github-releases-vs-semantic-release)
  - [Guidelines](#Guidelines-3)
- [API Documentation: swag vs go-swagger vs oapi-codegen](#api-documentation-swag-vs-go-swagger-vs-oapi-codegen)
  - [Guidelines](#Guidelines-4)
- [Protocol Buffers: buf](#protocol-buffers-buf)
  - [Guidelines](#Guidelines-5)
- [Live Reload: air](#live-reload-air)
  - [Guidelines](#Guidelines-6)
- [Vulnerability Scanning (Go): govulncheck](#vulnerability-scanning-go-govulncheck)
  - [Guidelines](#Guidelines-7)

## Formatter: gofumpt vs gofmt vs goimports

| 比較項目           | gofumpt                                           | gofmt                                     | goimports                                       |
| ------------------ | ------------------------------------------------- | ----------------------------------------- | ----------------------------------------------- |
| 提供元             | mvdan                                             | Go 公式                                   | Go 公式                                         |
| リポジトリ         | [mvdan/gofumpt](https://github.com/mvdan/gofumpt) | [golang/go](https://github.com/golang/go) | [golang/tools](https://github.com/golang/tools) |
| ライセンス         | BSD-3-Clause                                      | BSD-3-Clause                              | BSD-3-Clause                                    |
| 位置づけ           | gofmt の厳格版                                    | 標準フォーマッター                        | gofmt + import 整理                             |
| gofmt 互換         | ✅ (上位互換)                                      | -                                         | ✅                                               |
| 追加ルール         | 空行削除、グルーピング強制等                      | なし                                      | import のみ                                     |
| import 整理        | ❌                                                 | ❌                                         | ✅                                               |
| golangci-lint 統合 | ✅                                                 | ✅                                         | ✅                                               |

### Guidelines

**→ gofumpt を採用する。** gofmt の上位互換で、より厳格なルールによりチーム内のスタイルが統一される。golangci-lint 経由で実行可能。

- goimports は import 整理に特化しており、gofumpt と併用可能

## Linter: golangci-lint vs staticcheck vs go vet

| 比較項目         | golangci-lint                                                       | staticcheck                                               | go vet                                    |
| ---------------- | ------------------------------------------------------------------- | --------------------------------------------------------- | ----------------------------------------- |
| 提供元           | golangci                                                            | Dominik Honnef                                            | Go 公式                                   |
| リポジトリ       | [golangci/golangci-lint](https://github.com/golangci/golangci-lint) | [dominikh/go-tools](https://github.com/dominikh/go-tools) | [golang/go](https://github.com/golang/go) |
| ライセンス       | GPL-3.0                                                             | MIT                                                       | BSD-3-Clause                              |
| 位置づけ         | メタリンター (複数リンター統合)                                     | 単体リンター                                              | Go 標準ツール                             |
| 内蔵リンター数   | 100+                                                                | 1 (多数のチェック含む)                                    | 1                                         |
| 設定ファイル     | `.golangci.yaml`                                                    | `staticcheck.conf`                                        | なし                                      |
| 自動修正         | ✅ (一部リンター)                                                    | ❌                                                         | ❌                                         |
| CI 向け最適化    | ✅ (差分チェック、キャッシュ)                                        | ⚠️ 限定的                                                  | ✅                                         |
| staticcheck 含む | ✅                                                                   | -                                                         | ❌                                         |
| go vet 含む      | ✅                                                                   | ❌                                                         | -                                         |

### Guidelines

**→ golangci-lint を採用する。** staticcheck・go vet を含む 100+ のリンターを一括管理でき、差分チェック・キャッシュ・自動修正に対応。これ一つで十分。

## Container Build: ko vs Docker vs kaniko

| 比較項目        | ko                                            | Docker (BuildKit)                                 | kaniko                                                                        |
| --------------- | --------------------------------------------- | ------------------------------------------------- | ----------------------------------------------------------------------------- |
| 提供元          | Google (OSS)                                  | Docker Inc                                        | Google                                                                        |
| リポジトリ      | [ko-build/ko](https://github.com/ko-build/ko) | [moby/buildkit](https://github.com/moby/buildkit) | [GoogleContainerTools/kaniko](https://github.com/GoogleContainerTools/kaniko) |
| ライセンス      | Apache 2.0                                    | Apache 2.0                                        | Apache 2.0                                                                    |
| 対応言語        | Go 専用                                       | 任意                                              | 任意                                                                          |
| Dockerfile 不要 | ✅                                             | ❌                                                 | ❌                                                                             |
| ビルド速度      | 非常に高速                                    | 中程度                                            | 中程度                                                                        |
| CI での特権不要 | ✅                                             | ❌ (Docker daemon 必要)                            | ✅                                                                             |
| イメージサイズ  | 最小 (distroless ベース)                      | Dockerfile 依存                                   | Dockerfile 依存                                                               |

### Guidelines

**→ Go アプリケーションには ko を採用する。** Dockerfile 不要で高速・最小イメージ・CI で特権不要。

- Go 以外の言語を含む / 複雑なビルドステップが必要な場合は Docker を使用
- Docker daemon なしで任意の Dockerfile をビルドしたい場合は kaniko を使用

## Release Automation: goreleaser vs GitHub Releases vs semantic-release

| 比較項目         | goreleaser                                                        | GitHub Releases (手動) | semantic-release                                                                          |
| ---------------- | ----------------------------------------------------------------- | ---------------------- | ----------------------------------------------------------------------------------------- |
| 提供元           | goreleaser                                                        | GitHub                 | semantic-release                                                                          |
| リポジトリ       | [goreleaser/goreleaser](https://github.com/goreleaser/goreleaser) | - (GitHub 組み込み)    | [semantic-release/semantic-release](https://github.com/semantic-release/semantic-release) |
| ライセンス       | MIT                                                               | 商用 (GitHub に含む)   | MIT                                                                                       |
| 対応言語         | Go 中心 (他言語も可)                                              | 任意                   | 任意                                                                                      |
| クロスコンパイル | ✅ 自動                                                            | 手動                   | ❌                                                                                         |
| Changelog 生成   | ✅ 自動                                                            | 手動                   | ✅ 自動                                                                                    |
| バージョニング   | 手動 (Git tag)                                                    | 手動                   | ✅ 自動 (Conventional Commits)                                                             |
| バイナリ配布     | ✅ (tar.gz, zip, deb, rpm)                                         | 手動アップロード       | ❌                                                                                         |
| Docker イメージ  | ✅ ビルド+プッシュ                                                 | 別途設定               | 別途設定                                                                                  |
| Homebrew 連携    | ✅                                                                 | ❌                      | ❌                                                                                         |

### Guidelines

**→ Go プロジェクトには goreleaser を採用する。** クロスコンパイル + マルチプラットフォーム配布 + Docker イメージ + Homebrew を一括管理できる。

- Go 以外の言語で Conventional Commits ベースの自動バージョニングが欲しい場合は semantic-release を検討

## API Documentation: swag vs go-swagger vs oapi-codegen

| 比較項目         | swag                                          | go-swagger                                                        | oapi-codegen                                                              |
| ---------------- | --------------------------------------------- | ----------------------------------------------------------------- | ------------------------------------------------------------------------- |
| 提供元           | swaggo                                        | go-swagger                                                        | oapi-codegen                                                              |
| リポジトリ       | [swaggo/swag](https://github.com/swaggo/swag) | [go-swagger/go-swagger](https://github.com/go-swagger/go-swagger) | [oapi-codegen/oapi-codegen](https://github.com/oapi-codegen/oapi-codegen) |
| ライセンス       | MIT                                           | Apache 2.0                                                        | Apache 2.0                                                                |
| アプローチ       | コード → OpenAPI (アノテーション)             | OpenAPI ↔ コード (双方向)                                         | OpenAPI → コード                                                          |
| 入力             | Go コメント (アノテーション)                  | OpenAPI spec / Go コード                                          | OpenAPI spec (YAML/JSON)                                                  |
| 出力             | OpenAPI JSON/YAML + Swagger UI                | Go サーバー/クライアントコード                                    | Go サーバー/クライアントコード                                            |
| 型安全性         | 中程度 (アノテーション依存)                   | 高い                                                              | 高い                                                                      |
| スキーマ駆動開発 | ❌ (コードファースト)                          | ✅                                                                 | ✅ (スキーマファースト)                                                    |

### Guidelines

**→ oapi-codegen を採用する (スキーマファースト)。** API 設計を先に行い、型安全なコードを自動生成する。spec が Single Source of Truth となりチーム開発に最適。

- 既存コードからドキュメントを生成したい (コードファースト) 場合は swag を検討

## Protocol Buffers: buf

| 比較項目 | buf |
|---|---|
| 提供元 | Buf Technologies |
| リポジトリ | [bufbuild/buf](https://github.com/bufbuild/buf) |
| ライセンス | Apache 2.0 |
| 用途 | protobuf の Lint / Format / Breaking Change 検出 / コード生成管理 |
| Lint | ✅ (スタイル・命名規則) |
| Format | ✅ |
| Breaking Change 検出 | ✅ |
| BSR (レジストリ) | ✅ (Buf Schema Registry) |
| protoc 代替 | ✅ (`buf generate`) |

### Guidelines

**→ buf を採用する。** protobuf 開発のオールインワンツール。Lint・Format・Breaking Change 検出・コード生成を統一管理でき、protoc を直接使うより開発体験が大幅に向上する。

## Live Reload: air

| 比較項目 | air |
|---|---|
| 提供元 | air-verse |
| リポジトリ | [air-verse/air](https://github.com/air-verse/air) |
| ライセンス | GPL-3.0 |
| 用途 | Go アプリケーションのライブリロード (ファイル変更検知→自動リビルド) |
| 設定ファイル | `.air.toml` |
| カスタムビルドコマンド | ✅ |
| ファイル除外 | ✅ (glob パターン) |
| ログカラー | ✅ |

### Guidelines

**→ air を採用する。** Go のローカル開発でファイル変更時に自動リビルド・再起動を行うデファクトツール。設定が `.air.toml` で宣言的に管理でき、チームで統一しやすい。

## Vulnerability Scanning (Go): govulncheck

| 比較項目 | govulncheck |
|---|---|
| 提供元 | Go 公式 |
| リポジトリ | [golang/vuln](https://github.com/golang/vuln) |
| ライセンス | BSD-3-Clause |
| 用途 | Go モジュールの既知脆弱性検出 |
| 脆弱性 DB | Go Vulnerability Database (公式) |
| 到達可能性分析 | ✅ (実際に呼ばれるコードパスのみ報告) |
| JSON 出力 | ✅ |
| CI 統合 | ✅ (`go install` で導入可能) |

### Guidelines

**→ govulncheck を採用する。** Go 公式の脆弱性スキャナー。到達可能性分析により誤検知が少なく、実際に影響のある脆弱性のみを報告する。Trivy と併用することで多層防御を実現。
