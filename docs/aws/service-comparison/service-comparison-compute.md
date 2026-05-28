<!-- omit in toc -->
# AWS Service Comparison Matrix (Compute)

ホスティング・コンピュートサービスの選定判断材料。EC2、コンテナ関連サービスを比較する。

## History

| 日付       | 内容     |
| ---------- | -------- |
| 2026-05-28 | 初版作成 |

<!-- omit in toc -->
## Table of Contents

- [History](#history)
- [Container Orchestration: ECS vs EKS vs App Runner](#container-orchestration-ecs-vs-eks-vs-app-runner)
  - [Guidelines](#guidelines)
- [Compute Host: EC2 vs ECS on Fargate vs ECS on EC2 vs Lambda](#compute-host-ec2-vs-ecs-on-fargate-vs-ecs-on-ec2-vs-lambda)
  - [Guidelines](#guidelines-1)
- [ECS Launch Type: Fargate vs EC2](#ecs-launch-type-fargate-vs-ec2)
  - [Guidelines](#guidelines-2)

## Container Orchestration: ECS vs EKS vs App Runner

| 比較項目             | ECS                                                                                                  | EKS                                                                                                  | App Runner                                                                                     |
| -------------------- | ---------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------- |
| サービスカテゴリ     | Container Orchestration                                                                              | Container Orchestration                                                                              | Container Hosting (PaaS)                                                                       |
| ドキュメント         | [ECS](https://docs.aws.amazon.com/ecs/)                                                              | [EKS](https://docs.aws.amazon.com/eks/)                                                             | [App Runner](https://docs.aws.amazon.com/apprunner/)                                           |
| 課金モデル           | コントロールプレーン無料 + Fargate/EC2 課金                                                          | クラスター $0.10/h + Fargate/EC2 課金                                                                | vCPU/メモリ従量 (アクティブ時のみ)                                                             |
| マネージド度         | 高い                                                                                                 | 中程度 (Kubernetes 運用知識必要)                                                                     | 非常に高い                                                                                     |
| 主用途               | AWS ネイティブなコンテナワークロード                                                                 | Kubernetes エコシステム活用、マルチクラウド                                                           | シンプルな Web アプリ・API                                                                     |
| 学習コスト           | 低い                                                                                                 | 高い (Kubernetes 知識必須)                                                                           | 非常に低い                                                                                     |
| スケーリング         | Service Auto Scaling                                                                                 | HPA / Karpenter / Cluster Autoscaler                                                                 | 自動 (リクエストベース)                                                                        |
| ネットワーク制御     | VPC、Security Group、Service Connect                                                                 | VPC、Security Group、Pod レベル制御                                                                  | VPC Connector (制限あり)                                                                       |
| サービスメッシュ     | ⚠️ Service Connect (基本的)                                                                           | ✅ Istio / App Mesh / Linkerd                                                                        | ❌                                                                                              |
| CI/CD 統合           | CodeDeploy、ecspresso、CDK                                                                           | ArgoCD、Flux、Helm                                                                                   | 自動デプロイ (ECR/GitHub 連携)                                                                 |
| スケジュールタスク   | ✅ EventBridge + ECS Task                                                                             | ✅ CronJob                                                                                            | ❌                                                                                              |
| GPU サポート         | ✅ (EC2 起動タイプ)                                                                                   | ✅                                                                                                    | ❌                                                                                              |
| Windows コンテナ     | ✅                                                                                                    | ✅                                                                                                    | ❌                                                                                              |
| マルチクラウド移植性 | ❌ AWS 専用                                                                                           | ✅ Kubernetes 標準                                                                                    | ❌ AWS 専用                                                                                     |
| Terraform 対応       | ✅                                                                                                    | ✅                                                                                                    | ✅                                                                                              |

### Guidelines

**→ ECS を標準採用する。** AWS ネイティブで学習コスト・運用負荷が低く、Fargate との組み合わせでインフラ管理を最小化できる。

- Kubernetes エコシステム (Helm、ArgoCD、Istio 等) の活用やマルチクラウド移植性が必要な場合は EKS を検討
- シンプルな Web API で VPC 制御やスケジュールタスクが不要な場合は App Runner を検討
- App Runner はネットワーク制御・カスタマイズ性に制限があるため、要件が複雑化した時点で ECS へ移行する前提で採用する

## Compute Host: EC2 vs ECS on Fargate vs ECS on EC2 vs Lambda

| 比較項目             | EC2                                                  | ECS on Fargate                                       | ECS on EC2                                           | Lambda                                               |
| -------------------- | ---------------------------------------------------- | ---------------------------------------------------- | ---------------------------------------------------- | ---------------------------------------------------- |
| サービスカテゴリ     | IaaS                                                 | CaaS (Serverless)                                    | CaaS                                                 | FaaS (Serverless)                                    |
| ドキュメント         | [EC2](https://docs.aws.amazon.com/ec2/)              | [Fargate](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/AWS_Fargate.html) | [ECS](https://docs.aws.amazon.com/ecs/)              | [Lambda](https://docs.aws.amazon.com/lambda/)        |
| 課金モデル           | インスタンス時間課金 (RI/SP 割引あり)                | vCPU + メモリ秒課金                                  | EC2 インスタンス課金 (RI/SP 割引あり)                | リクエスト数 + 実行時間課金                          |
| マネージド度         | 低い (OS 管理必要)                                   | 高い (インフラ管理不要)                              | 中程度 (EC2 管理必要)                                | 非常に高い                                           |
| 主用途               | フルカスタマイズが必要なワークロード                 | 標準的なコンテナワークロード                         | GPU/大容量メモリ/特殊要件                            | イベント駆動・短時間処理                             |
| 最大実行時間         | 無制限                                               | 無制限                                               | 無制限                                               | 15 分                                                |
| コールドスタート     | なし (常時稼働)                                      | あり (数十秒)                                        | なし (常時稼働)                                      | あり (数百ms〜数秒)                                  |
| スケーリング速度     | 分単位                                               | 分単位                                               | 分単位                                               | 秒単位                                               |
| 最大リソース         | インスタンスタイプ依存 (数百 vCPU)                   | 16 vCPU / 120 GB メモリ                              | インスタンスタイプ依存                               | 10 GB メモリ / 6 vCPU                                |
| ステートフル         | ✅                                                    | ⚠️ (EBS マウント可、制限あり)                         | ✅                                                    | ❌                                                    |
| SSH アクセス         | ✅                                                    | ❌ (ECS Exec で代替)                                  | ✅                                                    | ❌                                                    |
| OS カスタマイズ      | ✅                                                    | ❌                                                    | ✅                                                    | ❌                                                    |
| コスト効率 (常時稼働) | 高い (RI/SP 適用時)                                  | 中程度                                               | 高い (RI/SP 適用時)                                  | 低い (常時稼働には不向き)                            |
| コスト効率 (バースト) | 低い                                                 | 高い                                                 | 低い                                                 | 非常に高い                                           |

### Guidelines

**→ ECS on Fargate を標準採用する。** インフラ管理不要でコンテナワークロードに集中でき、運用負荷が最も低い。

- 常時高負荷で RI/SP によるコスト最適化が重要な場合は ECS on EC2 を検討
- GPU、特殊カーネルモジュール、大容量メモリが必要な場合は ECS on EC2 または EC2 を検討
- イベント駆動で 15 分以内に完了する処理は Lambda を検討
- EC2 直接利用はレガシーワークロードの移行先、または特殊要件がある場合に限定する

## ECS Launch Type: Fargate vs EC2

| 比較項目             | Fargate                              | EC2                                  |
| -------------------- | ------------------------------------ | ------------------------------------ |
| サービスカテゴリ     | Serverless Compute                   | Managed Compute                      |
| 課金モデル           | vCPU + メモリ秒課金                  | EC2 インスタンス時間課金             |
| インフラ管理         | 不要                                 | AMI 更新、パッチ適用、容量管理必要   |
| スケーリング         | タスク単位で自動                     | インスタンス + タスクの2層管理       |
| 最大タスクサイズ     | 16 vCPU / 120 GB                     | インスタンスタイプ依存               |
| EBS マウント         | ✅ (制限あり)                         | ✅                                    |
| EFS マウント         | ✅                                    | ✅                                    |
| GPU                  | ❌                                    | ✅                                    |
| Spot 利用            | ✅ Fargate Spot (最大 70% 割引)       | ✅ Spot Instance                      |
| RI/SP 割引           | ✅ Savings Plans                      | ✅ RI + Savings Plans                 |
| daemonset 相当       | ❌                                    | ✅ (daemon スケジューリング)          |
| コスト (低負荷)      | 安い (使った分だけ)                  | 高い (インスタンス常時課金)          |
| コスト (高負荷)      | 高い                                 | 安い (RI/SP + 高密度配置)            |

### Guidelines

**→ Fargate を標準採用する。** 運用負荷の削減を最優先し、インフラ管理をゼロにする。

- 月額コストが Fargate > EC2 (RI 適用) で 30% 以上差が出る高負荷ワークロードは EC2 起動タイプを検討
- GPU ワークロードは EC2 起動タイプ必須
- daemonset パターン (サイドカーではなくホストレベルのエージェント) が必要な場合は EC2 起動タイプを検討
