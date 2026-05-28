<!-- omit in toc -->
# AWS Service Comparison Matrix (Gateway)

ロードバランサー・API Gateway 等のトラフィック制御サービスの選定判断材料。

## History

| 日付       | 内容     |
| ---------- | -------- |
| 2026-05-28 | 初版作成 |

<!-- omit in toc -->
## Table of Contents

- [History](#history)
- [Load Balancer: ALB vs NLB vs CLB](#load-balancer-alb-vs-nlb-vs-clb)
  - [Guidelines](#guidelines)
- [API Gateway: API Gateway REST vs API Gateway HTTP vs ALB](#api-gateway-api-gateway-rest-vs-api-gateway-http-vs-alb)
  - [Guidelines](#guidelines-1)
- [CDN / Edge: CloudFront vs Global Accelerator](#cdn--edge-cloudfront-vs-global-accelerator)
  - [Guidelines](#guidelines-2)

## Load Balancer: ALB vs NLB vs CLB

| 比較項目             | ALB                                                  | NLB                                                  | CLB (Classic)                                        |
| -------------------- | ---------------------------------------------------- | ---------------------------------------------------- | ---------------------------------------------------- |
| サービスカテゴリ     | L7 Load Balancer                                     | L4 Load Balancer                                     | L4/L7 Load Balancer (レガシー)                       |
| ドキュメント         | [ALB](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/) | [NLB](https://docs.aws.amazon.com/elasticloadbalancing/latest/network/) | [CLB](https://docs.aws.amazon.com/elasticloadbalancing/latest/classic/) |
| 課金モデル           | 時間 + LCU (新規接続/アクティブ接続/帯域/ルール)     | 時間 + NLCU                                          | 時間 + データ転送量                                  |
| 主用途               | HTTP/HTTPS ルーティング                              | TCP/UDP 高スループット、固定 IP                      | レガシー (新規利用非推奨)                            |
| プロトコル           | HTTP, HTTPS, gRPC, WebSocket                         | TCP, UDP, TLS                                        | HTTP, HTTPS, TCP, SSL                                |
| ルーティング         | パスベース、ホストベース、ヘッダー、クエリ文字列     | ポートベースのみ                                     | ポートベースのみ                                     |
| 固定 IP              | ❌ (DNS 名のみ)                                       | ✅ (Elastic IP 割当可)                                | ❌                                                    |
| 静的 IP / PrivateLink | ❌                                                    | ✅                                                    | ❌                                                    |
| レイテンシ           | 中程度 (L7 処理あり)                                 | 極低 (L4 パススルー)                                 | 中程度                                               |
| スループット         | 高い                                                 | 非常に高い (数百万 RPS)                              | 中程度                                               |
| TLS 終端             | ✅                                                    | ✅                                                    | ✅                                                    |
| WAF 統合             | ✅                                                    | ❌                                                    | ❌                                                    |
| 認証統合             | ✅ (Cognito / OIDC)                                   | ❌                                                    | ❌                                                    |
| ヘルスチェック       | HTTP/HTTPS (詳細)                                    | TCP/HTTP/HTTPS                                       | TCP/HTTP                                             |
| ターゲットタイプ     | Instance, IP, Lambda                                 | Instance, IP, ALB                                    | Instance                                             |
| ECS 統合             | ✅ (動的ポートマッピング)                             | ✅                                                    | ⚠️                                                    |
| Terraform 対応       | ✅                                                    | ✅                                                    | ✅                                                    |

### Guidelines

**→ ALB を標準採用する。** HTTP/HTTPS ワークロードに最適で、パスベースルーティング・WAF・認証統合が利用できる。

- TCP/UDP プロトコル、固定 IP 要件、PrivateLink 公開、極低レイテンシが必要な場合は NLB を採用
- NLB → ALB のターゲット構成で「固定 IP + L7 ルーティング」を両立するパターンも有効
- CLB は新規利用禁止。既存環境は ALB/NLB へ移行する

## API Gateway: API Gateway REST vs API Gateway HTTP vs ALB

| 比較項目             | API Gateway REST                                     | API Gateway HTTP                                     | ALB                                                  |
| -------------------- | ---------------------------------------------------- | ---------------------------------------------------- | ---------------------------------------------------- |
| サービスカテゴリ     | Managed API Gateway                                  | Managed API Gateway (軽量)                           | L7 Load Balancer                                     |
| ドキュメント         | [REST API](https://docs.aws.amazon.com/apigateway/latest/developerguide/apigateway-rest-api.html) | [HTTP API](https://docs.aws.amazon.com/apigateway/latest/developerguide/http-api.html) | [ALB](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/) |
| 課金モデル           | リクエスト課金 ($3.50/100万)                         | リクエスト課金 ($1.00/100万)                         | 時間 + LCU                                           |
| 主用途               | フル機能 API 管理                                    | シンプルな HTTP プロキシ                             | コンテナ/EC2 へのルーティング                        |
| レイテンシ           | 中程度 (29ms+ オーバーヘッド)                        | 低い (10ms+ オーバーヘッド)                          | 低い                                                 |
| リクエスト上限       | 10,000 RPS (リージョン)                              | 10,000 RPS (リージョン)                              | 実質無制限                                           |
| 認証                 | IAM, Cognito, Lambda Authorizer, API Key             | IAM, Cognito (JWT), Lambda Authorizer                | Cognito, OIDC                                        |
| リクエスト変換       | ✅ (VTL テンプレート)                                 | ❌                                                    | ❌                                                    |
| レスポンスキャッシュ | ✅                                                    | ❌                                                    | ❌                                                    |
| 使用量プラン/スロットリング | ✅                                              | ⚠️ (ルート単位スロットリング)                         | ❌                                                    |
| WebSocket            | ✅                                                    | ❌                                                    | ✅                                                    |
| カスタムドメイン     | ✅                                                    | ✅                                                    | ✅ (Route 53 + ACM)                                   |
| WAF 統合             | ✅                                                    | ❌                                                    | ✅                                                    |
| AWS サービス統合     | ✅ (直接プロキシ)                                     | ✅ (Lambda, HTTP, ALB, Step Functions)                | ❌ (バックエンドへのルーティングのみ)                 |
| Private API          | ✅ (VPC Endpoint)                                     | ✅ (VPC Link)                                         | ✅ (Internal ALB)                                     |
| Terraform 対応       | ✅                                                    | ✅                                                    | ✅                                                    |

### Guidelines

**→ ユースケースに応じて使い分ける。**

- Lambda バックエンドのシンプルな API → API Gateway HTTP API (低コスト・低レイテンシ)
- API キー管理、使用量プラン、リクエスト変換、キャッシュが必要 → API Gateway REST API
- ECS/EC2 バックエンドで高スループットが必要 → ALB
- API Gateway はリクエスト課金のため、高トラフィック (月数億リクエスト以上) では ALB の方がコスト効率が良い場合がある
- 内部マイクロサービス間通信には API Gateway を使わず、ALB または ECS Service Connect を推奨

## CDN / Edge: CloudFront vs Global Accelerator

| 比較項目             | CloudFront                                           | Global Accelerator                                   |
| -------------------- | ---------------------------------------------------- | ---------------------------------------------------- |
| サービスカテゴリ     | CDN                                                  | Network Accelerator                                  |
| ドキュメント         | [CloudFront](https://docs.aws.amazon.com/cloudfront/) | [Global Accelerator](https://docs.aws.amazon.com/global-accelerator/) |
| 課金モデル           | リクエスト + データ転送量                            | 固定時間 + データ転送量 (DT Premium)                 |
| 主用途               | 静的/動的コンテンツ配信、キャッシュ                  | TCP/UDP の低レイテンシグローバルルーティング         |
| プロトコル           | HTTP/HTTPS, WebSocket                                | TCP, UDP                                             |
| キャッシュ           | ✅ (エッジキャッシュ)                                 | ❌ (パススルー)                                       |
| 固定 IP              | ❌ (DNS 名)                                           | ✅ (Anycast IP)                                       |
| オリジン             | S3, ALB, EC2, カスタムオリジン                       | ALB, NLB, EC2, Elastic IP                            |
| エッジ関数           | ✅ (CloudFront Functions, Lambda@Edge)                | ❌                                                    |
| WAF 統合             | ✅                                                    | ❌ (DDoS Shield のみ)                                 |
| ヘルスチェック       | オリジンフェイルオーバー                             | ✅ (エンドポイントヘルスチェック)                     |
| マルチリージョン FO  | ⚠️ (オリジングループ)                                 | ✅ (エンドポイントグループ)                           |
| DDoS 防御            | ✅ Shield Standard (自動)                             | ✅ Shield Standard (自動)                             |
| Terraform 対応       | ✅                                                    | ✅                                                    |

### Guidelines

**→ CloudFront を標準採用する。** HTTP/HTTPS ワークロードではキャッシュによるレイテンシ削減・コスト削減が大きい。

- TCP/UDP プロトコル (ゲーム、IoT) で固定 IP + グローバル低レイテンシが必要な場合は Global Accelerator を採用
- マルチリージョン Active-Active 構成のフェイルオーバーには Global Accelerator が適する
- CloudFront + Global Accelerator の併用: CloudFront のオリジンとして Global Accelerator を使い、キャッシュ + 高速ルーティングを両立するパターン
