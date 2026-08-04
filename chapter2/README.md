# 第 2 章 dbt をはじめよう - ハンズオン環境

## 概要

dbt Labs が提供する Jaffle Shop（架空のフードショップ）のサンプルデータを使い、`dbt init` から dbt プロジェクトを作り、モデルのビルドまでを、書籍本編の流れに沿って手を動かしながら構築します。データウェアハウスには Amazon Redshift Serverless を使用し、`dbt-redshift` adapter から IAM 認証で接続します。

このディレクトリには、AWS リソースを作成する CloudFormation テンプレートと、raw データをロードする Python スクリプトだけが含まれています。dbt プロジェクト本体（`dbt_project/`）は、本 README の手順に従ってご自身で作成します。

本 README の各手順の見出しは、書籍本編「dbt をはじめよう」の対応する節に合わせています。書籍を読み進めながら、各手順のコマンドとコピー & ペースト用のコードを実行してください。各手順の解説は書籍にあるため、本 README には最小限の説明のみを記します。完成済みプロジェクトを動かすだけでよい場合は、[`chapter2-completed/`](../chapter2-completed/README.md) を参照してください。

## 構成

このディレクトリにはリポジトリからクローンした時点で以下のファイルが含まれています。

```
chapter2/
├── README.md
├── cloudformation/
│   └── redshift-serverless.yaml    # 第 2 章用の AWS リソース（Redshift Serverless / S3 バケット / VPC など）
└── utils/                          # raw データのロードと AWS リソース削除用スクリプト
    ├── load_raw_data.py            # Jaffle Shop の CSV を取得し、S3 経由で Redshift に COPY ロード
    ├── delete_resources.py         # CloudFormation スタックと関連リソースを一括削除
    └── _common.py                  # 上記スクリプトで共通に使うヘルパー
```

uv プロジェクトの定義（`pyproject.toml` / `uv.lock` / `.python-version`）と dbt プロジェクト本体（`dbt_project/`）は、手順 3・4 でこのディレクトリ直下に作成します。

## 前提条件

uv・AWS CLI のインストール、`dbt-book` プロファイルの作成、環境変数 `AWS_PROFILE` と `AWS_DEFAULT_REGION` の設定は、[ハンズオン共通のセットアップ](../README.md#共通の前提条件)にまとめています。まだの場合は先に済ませてください。
以降のコマンドは `AWS_PROFILE=dbt-book`、`AWS_DEFAULT_REGION=ap-northeast-1` を設定した状態で実行します（未設定なら共通のセットアップを参照）。

本章は dbt プロジェクトを 1 から構築するため、ほかの章と違って `uv sync` で始めません。Python 環境の作成（`uv init`）と dbt のインストール（`uv add`）も、手順の一部として進めます。

以降では、特に断りがない限り本ディレクトリ（`chapter2/`）直下でコマンドを実行します。

## 1. AWS リソースの作成

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

スタックの作成には 5〜10 分ほどかかります。完了したら、以降の手順で参照する出力値を確認します。

```sh
aws cloudformation describe-stacks \
  --stack-name dbt-book-ch2 \
  --query 'Stacks[0].Outputs'
```

主な出力値は次のとおりです。

| 出力キー | 内容 |
| --- | --- |
| `RedshiftEndpoint` | ワークグループのエンドポイント（ホスト名）。手順 4 の `dbt init` で `host` に入力します。 |
| `RedshiftDatabaseName` | 既定のデータベース名。常に `dev` で、手順 4 の `dbt init` で `dbname` に入力します。 |
| `LandingBucketName` | raw CSV をアップロードする S3 バケット名。`load_raw_data.py` が自動で取得します。 |
| `RedshiftS3RoleArn` | Redshift が S3 を読むための IAM ロール ARN。`COPY` 用に `load_raw_data.py` が自動で取得します。 |
| `RedshiftWorkgroupName` | Redshift Data API の発行先ワークグループ名。`load_raw_data.py` が自動で取得します。 |

自分で控えておくのは、ホスト名の `RedshiftEndpoint` だけで十分です。残りはスクリプトが Outputs から自動で取得します。

## 2. ソースデータの準備

Jaffle Shop の CSV を取得し、S3 経由で Redshift にロードします。

```sh
uv run --with boto3 --python 3.12 python utils/load_raw_data.py
```

> [!NOTE]
> `load_raw_data.py` は AWS SDK の boto3 を使います。この時点ではまだ dbt をインストールしていないため、`--with boto3` で一時的に boto3 を補って実行します。手順 3 で dbt をインストールした後は、`uv run python utils/load_raw_data.py` でも実行できます（boto3 は dbt-redshift に同梱されます）。

`utils/load_raw_data.py` は次の処理をまとめて実行します。

1. Jaffle Shop の CSV を `jaffle-data/` に取得（既に存在する場合はスキップ）
2. CloudFormation スタックの Outputs から S3 バケット名・IAM ロール ARN・ワークグループ名を取得
3. `jaffle-data/` 配下の CSV を `s3://<バケット>/raw/` にアップロード
4. Redshift Data API で `CREATE SCHEMA` / `DROP TABLE` / `CREATE TABLE` / `COPY` を発行
5. ステートメントの完了を待機

完了すると、Redshift の `dev.jaffle_shop_ch2_raw` スキーマに `raw_customers` / `raw_orders` / `raw_items` の 3 テーブルが作成されます。ロード結果は、Redshift Query Editor v2 でワークグループ `dbt-book-ch2-wg` に接続し、`dev` → `jaffle_shop_ch2_raw` を開くと確認できます。

## 3. dbt のインストール

`chapter2/` 直下で uv プロジェクトを初期化し、Python 3.12 を固定します。

```sh
uv init --bare --python 3.12
uv python pin 3.12
```

`--bare` は、Python パッケージ配布用の雛形ファイルを生成せず、`pyproject.toml` だけを作成するオプションです。dbt のように、ツールの実行環境として uv を使う用途に向いています。

dbt-core と dbt-redshift adapter を依存関係として追加します。

```sh
uv add "dbt-core>=1.11,<1.12" "dbt-redshift>=1.10,<1.11"
```

執筆時点で最新の `dbt-core` 1.11 系と `dbt-redshift` 1.10 系を使います。`>=1.11,<1.12` は、パッチ更新は取り込みつつ、次のマイナーバージョンには自動で上げない指定です。

`pyproject.toml` と `uv.lock` が作成され、`.venv/` に dbt-core・dbt-redshift とその依存パッケージがインストールされます。バージョンを確認します。

```sh
uv run dbt --version
```

コアエンジンと adapter のバージョンが表示されれば成功です。`postgres` が同時に表示されるのは、`dbt-redshift` が内部で `dbt-postgres` を利用しているためです。

```
Core:
  - installed: 1.11.12
  - latest:    1.11.12 - Up to date!

Plugins:
  - redshift: 1.10.2 - Up to date!
  - postgres: 1.10.2 - Up to date!
```

## 4. dbt プロジェクトの初期化

`chapter2/` 直下で、`dbt_project` という名前の dbt プロジェクトを作成します。

```sh
uv run dbt init dbt_project
```

`dbt init` は、`dbt_project/` サブディレクトリに雛形一式を作成したあと、接続先を対話的に問い合わせます。Redshift Serverless を使うため、以下の値を入力します。

- Which database would you like to use?: `1`（redshift）
- host: 手順 1 の `RedshiftEndpoint` の値（例: `dbt-book-ch2-wg.<account>.<region>.redshift-serverless.amazonaws.com`）
- port: `5439`（Enter で既定値）
- user: `placeholder`（IAM 認証では使われませんが、空欄では通らないため任意の文字列を入力）
- authentication method: `2`（iam）
- dbname: `dev`
- schema: `jaffle_shop_ch2_dev`
- threads: `4`

入力を終えると、接続プロファイルが `~/.dbt/profiles.yml` に書き出されます。生成された内容は次のようになります。

```yaml
dbt_project:
  outputs:
    dev:
      dbname: dev
      host: dbt-book-ch2-wg.<account>.<region>.redshift-serverless.amazonaws.com
      method: iam
      port: 5439
      schema: jaffle_shop_ch2_dev
      threads: 4
      type: redshift
      user: placeholder
  target: dev
```

IAM 認証では、`AWS_PROFILE` で指定した AWS プロファイルの一時クレデンシャルが接続に使われます。

`dbt init` が生成するファイル・ディレクトリは次のとおりです。

```
chapter2/
├── logs/                    # 以降は使わないため削除可
└── dbt_project/             # dbt プロジェクト本体
    ├── .gitignore
    ├── README.md
    ├── analyses/
    ├── dbt_project.yml
    ├── macros/
    ├── models/
    │   └── example/         # 雛形サンプル。使わないため削除可
    ├── seeds/
    ├── snapshots/
    └── tests/

~/.dbt/
└── profiles.yml             # 接続プロファイル（先ほど確認した内容）
```

`models/example/` と `logs/` は本ハンズオンでは使わないため、混乱を避けるなら削除して構いません。`analyses/`・`seeds/`・`snapshots/`・`tests/` も使いませんが、そのまま残して問題ありません。

## 5. 接続確認

プロジェクトディレクトリに移動し、接続を確認します。

```sh
cd dbt_project
uv run dbt debug
```

すべてのチェックで `OK` が表示され、最後に `All checks passed!` が出力されれば接続成功です。

> [!TIP]
> `Connection test` でタイムアウトや `Connection refused` が出る場合は、CloudFormation の `AllowedCidrIp` に渡したグローバル IP が現在の IP と一致しているかを確認してください。IP が変わっている場合は、`MY_IP=$(curl -s https://checkip.amazonaws.com)` で取得し直したうえで、手順 1 の `aws cloudformation deploy` を再実行します。
> `ExpiredToken` が出る場合は、`aws login --profile dbt-book` を再実行してください。

続いて、最小構成のモデルを 1 つ作成し、dbt から Redshift にテーブルを作成できることを確認します。`dbt_project/models/sample.sql` を作成します。

```sql
-- models/sample.sql
{{ config(materialized='table') }}

select *
from jaffle_shop_ch2_raw.raw_customers
```

`sample` モデルだけを指定して実行します。

```sh
uv run dbt run --select sample
```

`Completed successfully` と表示され、`jaffle_shop_ch2_dev` スキーマに `sample` テーブルが作成されれば疎通確認は完了です。この `sample.sql` は次の手順 6 で source を使う形に書き換えます。

## 6. source の定義

raw テーブルを source として宣言します。`models/staging/jaffle_shop/_jaffle_shop__sources.yml` を作成します。

```yaml
version: 2

sources:
  - name: jaffle_shop
    description: "Jaffle Shopの業務データ"
    schema: jaffle_shop_ch2_raw
    tables:
      - name: raw_customers
        description: "顧客マスターデータ"
        columns:
          - name: id
            description: "顧客ID（UUID）"
          - name: name
            description: "顧客名"
      - name: raw_orders
        description: "注文トランザクションデータ"
        columns:
          - name: id
            description: "注文ID（UUID）"
          - name: customer
            description: "顧客ID（UUID、外部キー）"
          - name: ordered_at
            description: "注文日時（ISO 8601形式）"
          - name: store_id
            description: "店舗ID（UUID）"
          - name: subtotal
            description: "小計金額（セント単位）"
          - name: tax_paid
            description: "税額（セント単位）"
          - name: order_total
            description: "合計金額（セント単位）"
      - name: raw_items
        description: "注文明細データ"
        columns:
          - name: id
            description: "注文明細ID（UUID）"
          - name: order_id
            description: "注文ID（UUID、外部キー）"
          - name: sku
            description: "商品コード（例：JAF-001, BEV-003）"
```

手順 5 で作成した `models/sample.sql` を、source を参照する形に書き換えます。

```sql
-- models/sample.sql
{{ config(materialized='table') }}

select *
from {{ source('jaffle_shop', 'raw_customers') }}
```

再度実行し、同じ結果が得られることを確認します。

```sh
uv run dbt run --select sample
```

source の疎通が確認できたら、`sample.sql` は不要なので削除します。Redshift 上の `sample` テーブルは残るため、必要に応じて Query Editor v2 から `drop table jaffle_shop_ch2_dev.sample;` で削除してください。

## 7. staging レイヤーの構築

1 つの source テーブルに対して 1 つの staging モデルを作成します。金額のドル変換は、まず `round()` を直接書きます（手順 10 でマクロに置き換えます）。

`models/staging/jaffle_shop/stg_jaffle_shop__customers.sql`

```sql
with source as (
    select * from {{ source('jaffle_shop', 'raw_customers') }}
),

renamed as (
    select
        id as customer_id,
        name as customer_name
    from source
)

select * from renamed
```

`models/staging/jaffle_shop/stg_jaffle_shop__orders.sql`

```sql
with source as (
    select * from {{ source('jaffle_shop', 'raw_orders') }}
),

renamed as (
    select
        id as order_id,
        customer as customer_id,
        store_id,
        ordered_at,
        round(subtotal / 100.0, 2) as subtotal,
        round(tax_paid / 100.0, 2) as tax_paid,
        round(order_total / 100.0, 2) as order_total
    from source
)

select * from renamed
```

`models/staging/jaffle_shop/stg_jaffle_shop__items.sql`

```sql
with source as (
    select * from {{ source('jaffle_shop', 'raw_items') }}
),

renamed as (
    select
        id as order_item_id,
        order_id,
        sku as product_id
    from source
)

select * from renamed
```

staging モデルの YAML 定義を `models/staging/jaffle_shop/_jaffle_shop__models.yml` として作成します。

```yaml
version: 2

models:
  - name: stg_jaffle_shop__customers
    description: "顧客データのstagingモデル。カラム名の標準化を行う。"
    columns:
      - name: customer_id
        description: "顧客の一意識別子（UUID）"
      - name: customer_name
        description: "顧客のフルネーム"

  - name: stg_jaffle_shop__orders
    description: "注文データのstagingモデル。カラム名の標準化と金額のドル変換を行う。"
    columns:
      - name: order_id
        description: "注文の一意識別子（UUID）"
      - name: customer_id
        description: "注文した顧客のID"
      - name: store_id
        description: "店舗ID（UUID）"
      - name: ordered_at
        description: "注文日時"
      - name: subtotal
        description: "小計金額（ドル単位）"
      - name: tax_paid
        description: "税額（ドル単位）"
      - name: order_total
        description: "合計金額（ドル単位）"

  - name: stg_jaffle_shop__items
    description: "注文明細データのstagingモデル。カラム名の標準化を行う。"
    columns:
      - name: order_item_id
        description: "注文明細の一意識別子（UUID）"
      - name: order_id
        description: "対応する注文のID"
      - name: product_id
        description: "商品コード（SKU）"
```

## 8. marts レイヤーの構築

staging モデルを `ref()` で参照して、分析用のマートを作成します。`customers` が `orders` を参照するため、書籍と同じ順序で作成します。

`models/marts/sales/orders.sql`

```sql
with orders as (
    select * from {{ ref('stg_jaffle_shop__orders') }}
),

items as (
    select * from {{ ref('stg_jaffle_shop__items') }}
),

order_items_summary as (
    -- 注文ごとに商品数とカテゴリ別（jaffle/beverage）件数を集計
    select
        order_id,
        count(order_item_id) as item_count,
        count(
            case when product_id like 'JAF-%' then 1 end
        ) as jaffle_count,
        count(
            case when product_id like 'BEV-%' then 1 end
        ) as beverage_count
    from items
    group by order_id
),

final as (
    -- ordersに集計結果を結合し、集計がない注文はcoalesceで0埋め
    -- store_idはstagingでは保持しているが、本マートでは選択しない
    select
        orders.order_id,
        orders.customer_id,
        orders.ordered_at,
        orders.subtotal,
        orders.tax_paid,
        orders.order_total,
        coalesce(order_items_summary.item_count, 0) as item_count,
        coalesce(order_items_summary.jaffle_count, 0) as jaffle_count,
        coalesce(order_items_summary.beverage_count, 0) as beverage_count
    from orders
    left join order_items_summary
        on orders.order_id = order_items_summary.order_id
)

select * from final
```

`models/marts/sales/customers.sql`

```sql
with customers as (
    select * from {{ ref('stg_jaffle_shop__customers') }}
),

orders as (
    select * from {{ ref('orders') }}
),

customer_orders as (
    -- 顧客ごとに注文実績（初回・最新日、注文回数、金額、カテゴリ別件数）を集計
    select
        customer_id,
        min(ordered_at) as first_order_date,
        max(ordered_at) as most_recent_order_date,
        count(order_id) as number_of_orders,
        sum(order_total) as total_amount,
        sum(item_count) as total_items_ordered,
        sum(jaffle_count) as jaffle_items,
        sum(beverage_count) as beverage_items
    from orders
    group by customer_id
),

final as (
    -- customersに集計結果を結合し、集計がない顧客はcoalesceで0埋め
    select
        customers.customer_id,
        customers.customer_name,
        customer_orders.first_order_date,
        customer_orders.most_recent_order_date,
        coalesce(customer_orders.number_of_orders, 0) as number_of_orders,
        coalesce(customer_orders.total_amount, 0) as customer_lifetime_value,
        coalesce(customer_orders.total_items_ordered, 0) as total_items_ordered,
        coalesce(customer_orders.jaffle_items, 0) as jaffle_items,
        coalesce(customer_orders.beverage_items, 0) as beverage_items
    from customers
    left join customer_orders
        on customers.customer_id = customer_orders.customer_id
)

select * from final
```

marts モデルの YAML 定義を `models/marts/sales/_sales__models.yml` として作成します。

```yaml
version: 2

models:
  - name: customers
    description: "顧客サマリーテーブル。注文回数、合計金額、初回・最終注文日、商品カテゴリ別の注文数を含む。"
    columns:
      - name: customer_id
        description: "顧客の一意識別子（UUID）"
      - name: customer_name
        description: "顧客のフルネーム"
      - name: first_order_date
        description: "初回注文日時"
      - name: most_recent_order_date
        description: "最終注文日時"
      - name: number_of_orders
        description: "注文回数"
      - name: customer_lifetime_value
        description: "顧客生涯価値（ドル単位）"
      - name: total_items_ordered
        description: "注文した商品の合計数"
      - name: jaffle_items
        description: "注文したジャッフルの数"
      - name: beverage_items
        description: "注文した飲み物の数"

  - name: orders
    description: "注文詳細テーブル。金額（ドル単位）と商品カテゴリ別の数量を含む。"
    columns:
      - name: order_id
        description: "注文の一意識別子（UUID）"
      - name: customer_id
        description: "注文した顧客のID"
      - name: ordered_at
        description: "注文日時"
      - name: subtotal
        description: "小計金額（ドル単位）"
      - name: tax_paid
        description: "税額（ドル単位）"
      - name: order_total
        description: "合計金額（ドル単位）"
      - name: item_count
        description: "注文に含まれる商品数"
      - name: jaffle_count
        description: "注文に含まれるジャッフルの数"
      - name: beverage_count
        description: "注文に含まれる飲み物の数"
```

## 9. マテリアライゼーションの設定

`dbt init` が生成した `dbt_project.yml` の末尾にある `models:` ブロックを、次の内容に置き換えます。staging を view、marts を table としてマテリアライズする設定です。

```yaml
models:
  dbt_project:
    staging:
      jaffle_shop:
        +materialized: view
    marts:
      sales:
        +materialized: table
```

## 10. Jinja テンプレートとマクロによる共通処理の再利用

手順 7 の `stg_jaffle_shop__orders.sql` では、セントからドルへの変換を `round()` で 3 回繰り返し書きました。この共通処理をマクロに切り出します。`macros/cents_to_dollars.sql` を作成します。

```sql
{% macro cents_to_dollars(column_name, decimal_places=2) %}
    round({{ column_name }} / 100.0, {{ decimal_places }})
{% endmacro %}
```

`stg_jaffle_shop__orders.sql` の 3 つの金額カラムを、マクロ呼び出しに置き換えます。ファイル全体は次のようになります。

```sql
with source as (
    select * from {{ source('jaffle_shop', 'raw_orders') }}
),

renamed as (
    select
        id as order_id,
        customer as customer_id,
        store_id,
        ordered_at,
        {{ cents_to_dollars('subtotal') }} as subtotal,
        {{ cents_to_dollars('tax_paid') }} as tax_paid,
        {{ cents_to_dollars('order_total') }} as order_total
    from source
)

select * from renamed
```

マクロが SQL に展開される様子は `dbt compile` で確認できます。

```sh
uv run dbt compile
```

`target/compiled/` 配下の `stg_jaffle_shop__orders.sql` を見ると、マクロ部分が `round(subtotal / 100.0, 2)` のように展開されています。

## 11. dbt の実行

すべてのモデルとマクロが揃いました。ここまでで `dbt_project/` は次の構成になっています。

```
dbt_project/
├── dbt_project.yml
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

`dbt_project/` 直下で全モデルをビルドします。

```sh
uv run dbt run
```

staging の 3 ビューと marts の 2 テーブルが、DAG の順序に従って作成されます。

```
Concurrency: 4 threads (target='dev')

1 of 5 START sql view model jaffle_shop_ch2_dev.stg_jaffle_shop__customers ... [RUN]
2 of 5 START sql view model jaffle_shop_ch2_dev.stg_jaffle_shop__items ....... [RUN]
3 of 5 START sql view model jaffle_shop_ch2_dev.stg_jaffle_shop__orders ...... [RUN]
1 of 5 OK created sql view model jaffle_shop_ch2_dev.stg_jaffle_shop__customers [CREATE VIEW in 0.85s]
3 of 5 OK created sql view model jaffle_shop_ch2_dev.stg_jaffle_shop__orders .. [CREATE VIEW in 0.87s]
2 of 5 OK created sql view model jaffle_shop_ch2_dev.stg_jaffle_shop__items ... [CREATE VIEW in 0.89s]
4 of 5 START sql table model jaffle_shop_ch2_dev.orders ...................... [RUN]
4 of 5 OK created sql table model jaffle_shop_ch2_dev.orders .................. [SELECT in 1.42s]
5 of 5 START sql table model jaffle_shop_ch2_dev.customers ................... [RUN]
5 of 5 OK created sql table model jaffle_shop_ch2_dev.customers ............... [SELECT in 1.28s]

Finished running 3 view models, 2 table models in 0 hours 0 minutes and 8.85 seconds.

Completed successfully

Done. PASS=5 WARN=0 ERROR=0 SKIP=0 TOTAL=5
```

`Completed successfully` と表示されれば成功です。

モデル出力のプレビューには `dbt show` を使います。

```sh
uv run dbt show --select customers --limit 5
```

実行対象を絞り込むには `--select` / `--exclude` を使います。

```sh
# 特定モデルのみ
uv run dbt run --select customers

# 特定モデルとその上流すべて
uv run dbt run --select +customers

# 特定モデルとその下流すべて
uv run dbt run --select stg_jaffle_shop__orders+

# ディレクトリ配下
uv run dbt run --select staging.jaffle_shop

# 特定モデルを除外
uv run dbt run --exclude orders
```

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

- [`chapter2-completed/`](../chapter2-completed/README.md): 第 2 章の完成済みプロジェクト。1 から構築せず、`uv sync` で動かすだけの手順をまとめています。答え合わせにも使えます。
