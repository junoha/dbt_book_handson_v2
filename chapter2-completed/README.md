# 第 2 章 dbt をはじめよう - 完成済みプロジェクト

## 概要

第 2 章のハンズオンの完成済みプロジェクトです。source 定義、staging / marts の各モデル、マクロ、マテリアライゼーション設定がすべて含まれています。1 からプロジェクトを構築せずに、`uv sync` で依存を入れて Redshift Serverless 上でモデルをビルドすることだけを目的とした最小手順をまとめています。

データウェアハウスには Amazon Redshift Serverless を使用し、`dbt-redshift` adapter から IAM 認証で接続します。raw データ（`raw_customers` / `raw_orders` / `raw_items`）は、S3 にアップロードしたうえで Redshift Serverless に `COPY` コマンドでロードします。

各手順やモデルの解説は書籍本編を参照してください。`dbt init` からモデルの作成までを自分の手で進めたい場合は、[`chapter2/`](../chapter2/README.md) を参照してください。

## 構成

このディレクトリには、第 2 章の完成済みプロジェクト一式が含まれています。

```
chapter2-completed/
├── README.md
├── cloudformation/
│   └── redshift-serverless.yaml    # 第 2 章用の AWS リソース（Redshift Serverless / S3 バケット / VPC など）
├── utils/                          # raw データのロードと AWS リソース削除用スクリプト
│   ├── load_raw_data.py            # Jaffle Shop の CSV を取得し、S3 経由で Redshift に COPY ロード
│   ├── delete_resources.py         # CloudFormation スタックと関連リソースを一括削除
│   └── _common.py                  # 上記スクリプトで共通に使うヘルパー
├── pyproject.toml                  # uv プロジェクトの定義
├── uv.lock                         # 依存パッケージのロック
├── .python-version                 # 使用する Python バージョン
└── dbt_project/                    # 完成済みの dbt プロジェクト本体
    ├── .env.sample
    ├── dbt_project.yml
    ├── profiles.yml
    ├── macros/
    │   └── cents_to_dollars.sql
    └── models/
        ├── staging/
        │   └── jaffle_shop/
        │       ├── _jaffle_shop__sources.yml
        │       ├── _jaffle_shop__models.yml
        │       ├── stg_jaffle_shop__customers.sql
        │       ├── stg_jaffle_shop__orders.sql
        │       └── stg_jaffle_shop__items.sql
        └── marts/
            └── sales/
                ├── _sales__models.yml
                ├── customers.sql
                └── orders.sql
```

このプロジェクトの `profiles.yml` は、接続先ホスト名を環境変数 `DBT_REDSHIFT_HOST` から、AWS プロファイルを `AWS_PROFILE` から読み取ります。値は `dbt_project/.env.sample` を基に用意する `.env` にまとめます。

> [!NOTE]
> 書籍本編では、`dbt init` が生成する `~/.dbt/profiles.yml` をそのまま使います。一方この完成済みプロジェクトでは、接続設定をプロジェクトと一緒に配布できるよう、`profiles.yml` を `dbt_project/` 配下に置いています。ホスト名や AWS プロファイル名は直接書かず、`env_var()` で `.env` から読み込む構成です。この構成の考え方は、書籍本編の「profiles.yml の配置」コラムで説明しています。`.env.sample` はその設定値の雛形で、手順 3 でコピーして `.env` を作成します。

## 前提条件

uv・AWS CLI のインストール、`dbt-book` プロファイルの作成、環境変数 `AWS_PROFILE` と `AWS_DEFAULT_REGION` の設定は、[ハンズオン共通のセットアップ](../README.md#共通の前提条件)にまとめています。まだの場合は先に済ませてください。
以降のコマンドは `AWS_PROFILE=dbt-book`、`AWS_DEFAULT_REGION=ap-northeast-1` を設定した状態で実行します（未設定なら共通のセットアップを参照）。

以降では、特に断りがない限り本ディレクトリ（`chapter2-completed/`）直下でコマンドを実行します。

## 1. CloudFormation スタックのデプロイ

ローカル PC のグローバル IP を確認し、その CIDR を `AllowedCidrIp` パラメータに渡してデプロイします。

```sh
# macOS / Linux
MY_IP=$(curl -s https://checkip.amazonaws.com)
echo "${MY_IP}"

aws cloudformation deploy \
  --template-file cloudformation/redshift-serverless.yaml \
  --stack-name dbt-book-ch2 \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides AllowedCidrIp="${MY_IP}/32"
```

```powershell
# Windows (PowerShell)
$MY_IP = (Invoke-RestMethod -Uri https://checkip.amazonaws.com).Trim()
Write-Host $MY_IP

aws cloudformation deploy `
  --template-file cloudformation/redshift-serverless.yaml `
  --stack-name dbt-book-ch2 `
  --capabilities CAPABILITY_NAMED_IAM `
  --parameter-overrides AllowedCidrIp="$MY_IP/32"
```

> [!NOTE]
> 本ハンズオンでは学習効率を優先し、Redshift Serverless をパブリックサブネットに配置して、グローバル IP からポート 5439 への接続を許可しています。実運用では、Redshift Serverless をプライベートサブネットに配置し、踏み台サーバーや VPN / Direct Connect、または同一 VPC 内の dbt 実行基盤（ECS / CodeBuild / Airflow など）からのみアクセスを許可する構成が一般的です。

スタックの作成には 5〜10 分ほどかかります。完了したら、出力値を確認します。手順 3 で `.env` に設定する `RedshiftEndpoint` の値を控えておいてください。

```sh
aws cloudformation describe-stacks \
  --stack-name dbt-book-ch2 \
  --query 'Stacks[0].Outputs'
```

## 2. 依存パッケージのインストールと raw データのロード

`uv sync` でロックファイルどおりに依存パッケージをインストールし、raw データを Redshift にロードします。

```sh
# 依存パッケージのインストール（dbt-core / dbt-redshift / boto3）
uv sync

# Jaffle Shop の CSV を取得し、S3 経由で Redshift にロード
uv run python utils/load_raw_data.py
```

完了すると、Redshift の `dev.jaffle_shop_ch2_raw` スキーマに `raw_customers` / `raw_orders` / `raw_items` の 3 テーブルが作成されます。

## 3. dbt プロジェクトの実行

dbt プロジェクトのディレクトリに移動し、接続情報を用意します。`.env.sample` をコピーして `.env` を作り、`DBT_REDSHIFT_HOST` に手順 1 で控えた `RedshiftEndpoint` の値を設定してください（`AWS_PROFILE` と `DBT_PROFILES_DIR` は既定値のままで動きます）。

```sh
# macOS / Linux
cd dbt_project
cp .env.sample .env
```

```powershell
# Windows (PowerShell)
cd dbt_project
Copy-Item .env.sample .env
```

エディタで `.env` を開き、`DBT_REDSHIFT_HOST` を `RedshiftEndpoint` の値に書き換えます。続いて、`.env` を `uv run` に読み込ませるため、環境変数 `UV_ENV_FILE` を設定します。これにより、以降は `uv run dbt ...` を実行するだけで `.env` が自動的に読み込まれます。

```sh
# macOS / Linux (bash / zsh)
export UV_ENV_FILE="$PWD/.env"
```

```powershell
# Windows (PowerShell)
$env:UV_ENV_FILE = "$PWD\.env"
```

> [!NOTE]
> `UV_ENV_FILE` はターミナルのセッションごとに設定が必要です。ターミナルを開き直した場合は、`dbt_project/` に移動して再度設定してください。

接続を確認し、全モデルをビルドします。

```sh
# 接続確認
uv run dbt debug

# 全モデルの実行
uv run dbt run
```

`dbt run` が `Completed successfully` で終わると、`jaffle_shop_ch2_dev` スキーマに staging の 3 ビューと marts の 2 テーブル（`orders` / `customers`）が作成されます。

> [!TIP]
> `dbt debug` でタイムアウトや `Connection refused` が出る場合は、CloudFormation の `AllowedCidrIp` に渡したグローバル IP が現在の IP と一致しているかを確認してください。IP が変わっている場合は、手順 1 の `aws cloudformation deploy` を再実行します。
> `ExpiredToken` が出る場合は、`aws login --profile dbt-book` を再実行してください。

## ビルド成果物のクリーンアップ

`target/` や `dbt_packages/` などの生成物を削除するには、`dbt_project/` 直下で次を実行します。

```sh
uv run dbt clean
```

## ハンズオンのクリーンアップ

ハンズオンで作成した AWS リソースを削除します。直前の手順に続けて、`dbt_project/` 直下から実行します。

```sh
uv run python ../utils/delete_resources.py
```

スクリプトを実行すると削除対象のリソース一覧が表示され、確認プロンプトで `y` を入力すると一括で削除されます（デフォルトはキャンセル）。削除対象は以下のとおりです。

- CloudFormation スタック `dbt-book-ch2`（スタック内で作成された Redshift Serverless、VPC、IAM ロール、S3 バケットなどを含む）
- Secrets Manager シークレット `dbt-book-ch2-redshift-admin`（`--force-delete-without-recovery` により即時削除）

## 関連ディレクトリ

- [`chapter2/`](../chapter2/README.md): dbt プロジェクトを 1 から構築するハンズオン。`uv init` や `dbt init`、モデルの作成を含む、書籍本編に沿った手順をまとめています。
