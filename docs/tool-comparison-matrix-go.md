# ツール比較マトリクス (Go)

Go 開発に特化したツール選定の判断材料。

<!-- omit toc -->
## Table of Contents

- [ツール比較マトリクス (Go)](#ツール比較マトリクス-go)
  - [Table of Contents](#table-of-contents)
  - [フォーマッター: gofumpt vs gofmt vs goimports](#フォーマッター-gofumpt-vs-gofmt-vs-goimports)
    - [選定ガイドライン](#選定ガイドライン)
  - [Linter: golangci-lint vs staticcheck vs go vet](#linter-golangci-lint-vs-staticcheck-vs-go-vet)
    - [選定ガイドライン](#選定ガイドライン-1)
  - [コンテナビルド: ko vs Docker vs kaniko](#コンテナビルド-ko-vs-docker-vs-kaniko)
    - [選定ガイドライン](#選定ガイドライン-2)
  - [リリース自動化: goreleaser vs GitHub Releases vs semantic-release](#リリース自動化-goreleaser-vs-github-releases-vs-semantic-release)
    - [選定ガイドライン](#選定ガイドライン-3)
  - [API ドキュメント生成: swag vs go-swagger vs oapi-codegen](#api-ドキュメント生成-swag-vs-go-swagger-vs-oapi-codegen)
    - [選定ガイドライン](#選定ガイドライン-4)

## フォーマッター: gofumpt vs gofmt vs goimports

| 比較項目           | gofumpt                      | gofmt              | goimports           |
| ------------------ | ---------------------------- | ------------------ | ------------------- |
| 提供元             | mvdan                        | Go 公式            | golang.org/x/tools  |
| 位置づけ           | gofmt の厳格版               | 標準フォーマッター | gofmt + import 整理 |
| gofmt 互換         | ✅ (上位互換)                 | -                  | ✅                   |
| 追加ルール         | 空行削除、グルーピング強制等 | なし               | import のみ         |
| import 整理        | ❌                            | ❌                  | ✅                   |
| golangci-lint 統合 | ✅                            | ✅                  | ✅                   |
| CI での推奨        | ✅ (より一貫したスタイル)     | ✅ (最低限)         | ✅ (import管理)      |

### 選定ガイドライン

- **gofumpt (このリポジトリ)**: gofmt より厳格なルールでチーム内のスタイル統一を強化。golangci-lint 経由で実行可能

## Linter: golangci-lint vs staticcheck vs go vet

| 比較項目         | golangci-lint                   | staticcheck            | go vet        |
| ---------------- | ------------------------------- | ---------------------- | ------------- |
| 位置づけ         | メタリンター (複数リンター統合) | 単体リンター           | Go 標準ツール |
| 内蔵リンター数   | 100+                            | 1 (多数のチェック含む) | 1             |
| 設定ファイル     | `.golangci.yaml`                | `staticcheck.conf`     | なし          |
| 自動修正         | ✅ (一部リンター)                | ❌                      | ❌             |
| CI 向け最適化    | ✅ (差分チェック、キャッシュ)    | ⚠️ 限定的               | ✅             |
| カスタムルール   | ✅ (プラグイン)                  | ❌                      | ❌             |
| 実行速度         | 高速 (並列実行)                 | 高速                   | 高速          |
| staticcheck 含む | ✅                               | -                      | ❌             |
| go vet 含む      | ✅                               | ❌                      | -             |

### 選定ガイドライン

- **golangci-lint を選ぶ場合 (推奨)**: staticcheck や go vet を含む多数のリンターを一括管理できるため、基本的にこれ一つで十分

## コンテナビルド: ko vs Docker vs kaniko

| 比較項目             | ko                       | Docker (BuildKit)      | kaniko          |
| -------------------- | ------------------------ | ---------------------- | --------------- |
| 提供元               | Google (OSS)             | Docker Inc             | Google          |
| 対応言語             | Go 専用                  | 任意                   | 任意            |
| Dockerfile 不要      | ✅                        | ❌                      | ❌               |
| ビルド速度           | 非常に高速               | 中程度                 | 中程度          |
| マルチアーキテクチャ | ✅                        | ✅ (buildx)             | ✅               |
| CI での特権不要      | ✅                        | ❌ (Docker daemon 必要) | ✅               |
| イメージサイズ       | 最小 (distroless ベース) | Dockerfile 依存        | Dockerfile 依存 |
| カスタマイズ性       | 低い (Go バイナリのみ)   | 高い                   | 高い            |

### 選定ガイドライン

- **ko (このリポジトリ)**: Go アプリケーションのコンテナ化に最適。Dockerfile 不要で高速・セキュア
- **Docker**: Go 以外の言語、複雑なビルドステップが必要な場合

## リリース自動化: goreleaser vs GitHub Releases vs semantic-release

| 比較項目         | goreleaser                | GitHub Releases (手動) | semantic-release              |
| ---------------- | ------------------------- | ---------------------- | ----------------------------- |
| 提供元           | goreleaser                | GitHub                 | semantic-release              |
| 対応言語         | Go 中心 (他言語も可)      | 任意                   | 任意                          |
| クロスコンパイル | ✅ 自動                    | 手動                   | ❌                             |
| Changelog 生成   | ✅ 自動                    | 手動                   | ✅ 自動                        |
| バージョニング   | 手動 (Git tag)            | 手動                   | ✅ 自動 (Conventional Commits) |
| バイナリ配布     | ✅ (tar.gz, zip, deb, rpm) | 手動アップロード       | ❌                             |
| Docker イメージ  | ✅ ビルド+プッシュ         | 別途設定               | 別途設定                      |
| Homebrew 連携    | ✅                         | ❌                      | ❌                             |

### 選定ガイドライン

- **goreleaser (このリポジトリ)**: Go プロジェクトのリリースに最適。クロスコンパイル + マルチプラットフォーム配布を一括管理

## API ドキュメント生成: swag vs go-swagger vs oapi-codegen

| 比較項目         | swag                              | go-swagger                     | oapi-codegen                   |
| ---------------- | --------------------------------- | ------------------------------ | ------------------------------ |
| アプローチ       | コード → OpenAPI (アノテーション) | OpenAPI ↔ コード (双方向)      | OpenAPI → コード               |
| 入力             | Go コメント (アノテーション)      | OpenAPI spec / Go コード       | OpenAPI spec (YAML/JSON)       |
| 出力             | OpenAPI JSON/YAML + Swagger UI    | Go サーバー/クライアントコード | Go サーバー/クライアントコード |
| Swagger UI 統合  | ✅ 組み込み                        | ✅                              | ❌ (別途設定)                   |
| 型安全性         | 中程度 (アノテーション依存)       | 高い                           | 高い                           |
| スキーマ駆動開発 | ❌ (コードファースト)              | ✅                              | ✅ (スキーマファースト)         |
| メンテナンス性   | ⚠️ アノテーション肥大化            | 中程度                         | 高い (spec が正)               |

### 選定ガイドライン

- **oapi-codegen (スキーマファースト)**: API 設計を先に行い、型安全なコードを自動生成。チーム開発に最適
- **swag (コードファースト)**: 既存コードからドキュメントを生成したい場合。プロトタイプ向き
