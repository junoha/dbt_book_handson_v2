# 第7章 ハンズオン: レイクハウスにおけるdbtの活用

Apache Iceberg と dbt を組み合わせて、AWS 上にレイクハウスを構築するハンズオンです。
Hive形式のテーブルで運用しているJaffle ShopのデータをIcebergに移行し、隠しパーティショニング、merge戦略による差分更新、スキーマ進化、タイムトラベルを体験します。
さらにハンズオン2では、dbt-glueで別エンジン（Spark）から同じデータにアクセスし、dbt-loomによるプロジェクト間リネージの統合を扱います。

## 前提

uv・AWS CLI のインストール、`dbt-book` プロファイルの作成、環境変数 `AWS_PROFILE` の設定は、[ハンズオン共通のセットアップ](../README.md#共通の前提条件)にまとめています。まだの場合は先に済ませてください。
以降のコマンドは `AWS_PROFILE=dbt-book` を設定した状態で実行します（未設定なら共通のセットアップを参照）。

## Python 環境のセットアップ

macOS / Linux:

```sh
cd chapter7
uv sync --frozen
source .venv/bin/activate  # macOS / Linux
```

Windows (PowerShell):

```powershell
cd chapter7
uv sync --frozen
.venv\Scripts\activate
```

以降のコマンドは、この仮想環境がアクティブな状態で実行します。

> [!NOTE]
> 本章ではdbt-athenaとdbt-glueを同一の仮想環境で利用するため、dbt-coreは1.10.xを使用しています。dbt-glueの執筆時点での最新版（1.10.19）がdbt-core 1.11に未対応であるためです。他の章ではdbt-core 1.11.xを使用していますが、本章のハンズオンに影響はありません。

## AWS リソースのデプロイ

macOS / Linux:

```sh
export AWS_DEFAULT_REGION=ap-northeast-1
```

Windows (PowerShell):

```powershell
$env:AWS_DEFAULT_REGION = "ap-northeast-1"
```

```bash
aws cloudformation deploy \
  --template-file cloudformation/ch7-iceberg-resources.yml \
  --stack-name dbt-book-ch7-iceberg \
  --capabilities CAPABILITY_NAMED_IAM
```

## 環境変数の設定

以降のステップで使う変数をシェルに設定します。

macOS / Linux:

```sh
export CH7_S3_BUCKET_NAME=$(aws cloudformation describe-stacks \
  --stack-name dbt-book-ch7-iceberg \
  --query 'Stacks[0].Outputs[?OutputKey==`S3BucketName`].OutputValue' \
  --output text)

export ATHENA_WORKGROUP=$(aws cloudformation describe-stacks \
  --stack-name dbt-book-ch7-iceberg \
  --query 'Stacks[0].Outputs[?OutputKey==`WorkGroupName`].OutputValue' \
  --output text)

export GLUE_ROLE_ARN=$(aws cloudformation describe-stacks \
  --stack-name dbt-book-ch7-iceberg \
  --query 'Stacks[0].Outputs[?OutputKey==`GlueRoleArn`].OutputValue' \
  --output text)
```

Windows (PowerShell):

```powershell
$env:CH7_S3_BUCKET_NAME = (aws cloudformation describe-stacks `
  --stack-name dbt-book-ch7-iceberg `
  --query 'Stacks[0].Outputs[?OutputKey==``S3BucketName``].OutputValue' `
  --output text)

$env:ATHENA_WORKGROUP = (aws cloudformation describe-stacks `
  --stack-name dbt-book-ch7-iceberg `
  --query 'Stacks[0].Outputs[?OutputKey==``WorkGroupName``].OutputValue' `
  --output text)

$env:GLUE_ROLE_ARN = (aws cloudformation describe-stacks `
  --stack-name dbt-book-ch7-iceberg `
  --query 'Stacks[0].Outputs[?OutputKey==``GlueRoleArn``].OutputValue' `
  --output text)
```

## 生データの用意

Jaffle Shop Generator（jafgen）でサンプルデータを生成し、S3にアップロードしてGlue Data Catalogに登録します。jafgenは`uv sync --frozen`でインストール済みです。

```bash
jafgen 1
uv run python utils/upload_raw_data.py
uv run python utils/create_raw_tables.py
```

完了すると、Glue Data Catalog上に `jaffle_shop_iceberg.raw_customers`（`id`, `name`）と `jaffle_shop_iceberg.raw_orders`（`id`, `customer`, `ordered_at`, `store_id`, `subtotal`, `tax_paid`, `order_total`）がHive形式のテーブルとして登録されます。

---

## ハンズオン1

dbt-athena プロジェクト（`dbt-athena-project/`）を使い、Hive形式のテーブルをIcebergに移行しながら、Icebergの各機能をdbtから扱います。

### Step 1: staging層とmart層の構築、隠しパーティショニング

staging層（stg_customers, stg_orders）とmart層（orders, customer_orders）を作成します。mart層の`orders`テーブルにはIcebergの隠しパーティショニング（`day(ordered_at)`）が設定されており、日付条件でのクエリが高速化されます。

macOS / Linux:

```sh
cd dbt-athena-project
export DBT_PROFILES_DIR=$(pwd)
dbt run
```

Windows (PowerShell):

```powershell
cd dbt-athena-project
$env:DBT_PROFILES_DIR = (Get-Location).Path
dbt run
```

ordersテーブルの件数と期間を確認します。

```bash
uv run python ../utils/run_athena.py "SELECT count(*), min(ordered_at), max(ordered_at) FROM jaffle_shop_iceberg.orders"
```

日付パーティションが作られていることをIcebergのメタデータテーブルで確認します。

```bash
uv run python ../utils/run_athena.py "SELECT partition, record_count FROM jaffle_shop_iceberg.\"orders\$partitions\" ORDER BY partition LIMIT 3"
```

フルスキャンを実行します。`--stats`を付けると先頭行にDataScannedBytes（スキャンしたバイト数）とEngineExecutionMillis（実行時間ミリ秒）が出力されます。

```bash
uv run python ../utils/run_athena.py "SELECT sum(order_total) FROM jaffle_shop_iceberg.orders" --stats
```

1か月フィルタで同じ集計を実行します。

```bash
uv run python ../utils/run_athena.py "SELECT sum(order_total) FROM jaffle_shop_iceberg.orders WHERE ordered_at >= TIMESTAMP '2019-01-01 00:00:00' AND ordered_at < TIMESTAMP '2019-02-01 00:00:00'" --stats
```

1日フィルタでさらに絞ります。先頭行のDataScannedBytesがフルスキャン→1か月→1日と減っていくことを確認してください。

```bash
uv run python ../utils/run_athena.py "SELECT sum(order_total) FROM jaffle_shop_iceberg.orders WHERE ordered_at >= TIMESTAMP '2019-01-15 00:00:00' AND ordered_at < TIMESTAMP '2019-01-16 00:00:00'" --stats
```

### Step 2: merge戦略でのインクリメンタル更新と削除対応

顧客ごとの注文サマリ（`customer_orders`）をmerge戦略のインクリメンタルモデルとして構築し、差分更新とデータ保護ポリシーに基づく削除を体験します。

#### 2-a. customer_ordersの初回フルビルド

customer_ordersモデルを初回実行し、全顧客の注文サマリを作成します。

```bash
dbt run --select customer_orders
```

件数と合計注文数を確認します。

```bash
uv run python ../utils/run_athena.py "SELECT count(*), sum(order_count), max(last_order_at) FROM jaffle_shop_iceberg.customer_orders"
```

#### 2-b. ソースデータの変更と差分更新

新規注文の追加と、データ保護ポリシーに基づく削除フラグの付与をシミュレーションします。以下のスクリプトが、ソースデータの変更（`gdpr_deleted`カラムの追加、新規注文20件の追加）と、対応するdbtモデルファイルの更新を一括で行います。

```bash
cd ..
uv run python utils/simulate_updates_step2.py
```

モデルを再実行します。`orders`は新規20件のみインクリメンタルに取り込み、`customer_orders`はmerge戦略で差分更新されます。

```bash
cd dbt-athena-project
dbt run
```

`gdpr_deleted=true`の顧客がマート上に存在していることを確認します。

```bash
uv run python ../utils/run_athena.py "SELECT gdpr_deleted, count(*) FROM jaffle_shop_iceberg.customer_orders GROUP BY gdpr_deleted"
```

注文数の合計が20件増えていることも確認します。

```bash
uv run python ../utils/run_athena.py "SELECT count(*), sum(order_count), max(last_order_at) FROM jaffle_shop_iceberg.customer_orders"
```

差分更新は動いていますが、`gdpr_deleted=true`の顧客はマートに残ったままです。データ保護ポリシーに基づきこれらの顧客はマートから除外する必要があるため、次のステップで`delete_condition`を使って対応します。

#### 2-c. delete_conditionで削除対応

以下のスクリプトが、`customer_orders.sql`に`delete_condition`を追加します。MERGE文の実行時に`gdpr_deleted=true`のレコードが削除されるようになります。

```bash
cd ..
uv run python utils/apply_delete_condition.py
```

再実行すると、`gdpr_deleted=true`の顧客がマートから削除されます。

```bash
cd dbt-athena-project
dbt run --select customer_orders
```

削除対象が消えたことを確認します。`gdpr_deleted=true`の行がなくなっているはずです。

```bash
uv run python ../utils/run_athena.py "SELECT gdpr_deleted, count(*) FROM jaffle_shop_iceberg.customer_orders GROUP BY gdpr_deleted"
```

Icebergのスナップショット履歴を確認します。初回ビルド、差分更新、削除の3つの操作が記録されています。

```bash
uv run python ../utils/run_athena.py "SELECT operation, committed_at FROM jaffle_shop_iceberg.\"customer_orders\$snapshots\" ORDER BY committed_at"
```

### Step 3: スキーマ進化でカラム追加

ソースデータに`coupon_discount`カラムを追加し、既存のIcebergテーブルを再作成せずにカラムを追加します。以下のスクリプトがソースデータの変更とdbtモデルファイルの更新を一括で行います。

```bash
cd ..
uv run python utils/simulate_updates_step3.py
```

ordersモデルを再実行します。`on_schema_change='append_new_columns'`の設定により、Icebergテーブル側に`coupon_discount`カラムが自動で追加されます。

```bash
cd dbt-athena-project
dbt run --select stg_orders orders
```

カラムが追加されたことを確認します。

```bash
uv run python ../utils/run_athena.py "SHOW COLUMNS IN jaffle_shop_iceberg.orders"
```

既存レコードは`coupon_discount`がNULL、新規追加の20件だけが値を持つことを確認します。

```bash
uv run python ../utils/run_athena.py "SELECT coupon_discount IS NULL AS is_null, count(*) FROM jaffle_shop_iceberg.orders GROUP BY coupon_discount IS NULL"
```

クーポン付きの行をサンプルで確認します。

```bash
uv run python ../utils/run_athena.py "SELECT order_id, ordered_at, order_total, coupon_discount FROM jaffle_shop_iceberg.orders WHERE coupon_discount IS NOT NULL ORDER BY ordered_at LIMIT 5"
```

### Step 4: タイムトラベル

Icebergのスナップショット履歴を使って、過去の状態を参照します。

スナップショット一覧を取得します。

```bash
uv run python ../utils/run_athena.py "SELECT committed_at, snapshot_id, operation FROM jaffle_shop_iceberg.\"customer_orders\$snapshots\" ORDER BY committed_at"
```

現在の状態を確認します（削除適用後の件数）。

```bash
uv run python ../utils/run_athena.py "SELECT count(*), sum(order_count) FROM jaffle_shop_iceberg.customer_orders"
```

上記で取得した1つ目のスナップショットIDを使って、初回ビルド時点の状態を参照します。削除前の全顧客が見えることを確認してください。`<snapshot_id>`を実際の値に置き換えてください。

```bash
uv run python ../utils/run_athena.py "SELECT count(*), sum(order_count) FROM jaffle_shop_iceberg.customer_orders FOR VERSION AS OF <snapshot_id>"
```

タイムスタンプを指定しての参照も可能です。スナップショット一覧で確認した`committed_at`の値を使います。

```bash
uv run python ../utils/run_athena.py "SELECT count(*), sum(order_count) FROM jaffle_shop_iceberg.customer_orders FOR TIMESTAMP AS OF TIMESTAMP '<committed_atの値>'"
```

---

## ハンズオン2

dbt-glue プロジェクト（`dbt-glue-project/`）を使い、ハンズオン1で作成したIcebergテーブルを別のエンジン（AWS Glue/Spark）から参照します。dbt-loomで2つのdbtプロジェクト間のリネージを統合します。

ハンズオン1が完了している前提です（`orders`テーブルが存在し、`dbt-athena-project/target/manifest.json`が生成されていること）。

### Step 1: dbt-glueプロジェクトの接続確認

macOS / Linux:

```sh
cd ../dbt-glue-project
export DBT_PROFILES_DIR=$(pwd)
dbt debug
```

Windows (PowerShell):

```powershell
cd ..\dbt-glue-project
$env:DBT_PROFILES_DIR = (Get-Location).Path
dbt debug
```

Glue Interactive Sessionの起動に初回1分ほどかかります。`All checks passed!`が出れば成功です。

### Step 2: dbt-loomでプロジェクトをつなぐ

dbt-athenaプロジェクトの`manifest.json`が最新であることを確認します。未生成なら`dbt compile`を実行してください。

macOS / Linux:

```sh
cd ../dbt-athena-project
export DBT_PROFILES_DIR=$(pwd)
dbt compile
```

Windows (PowerShell):

```powershell
cd ..\dbt-athena-project
$env:DBT_PROFILES_DIR = (Get-Location).Path
dbt compile
```

dbt-glueプロジェクトに戻り、`dbt ls`でdbt-loomがdbt-athenaのモデルを取り込めることを確認します。

macOS / Linux:

```sh
cd ../dbt-glue-project
export DBT_PROFILES_DIR=$(pwd)
dbt ls
```

Windows (PowerShell):

```powershell
cd ..\dbt-glue-project
$env:DBT_PROFILES_DIR = (Get-Location).Path
dbt ls
```

`jaffle_shop_iceberg.orders`などがリストに現れれば成功です。

### Step 3: RFM分析モデルの実行

`rfm_input`はdbt-loom経由でdbt-athenaプロジェクトの`orders`を参照する中間モデル、`customer_rfm`はntileを使ったRFMスコアリングの本体です。

rfm_inputを作成します。

```bash
dbt run --select rfm_input
```

件数を確認します。

```bash
cd ..
uv run python utils/run_athena.py "SELECT count(*) FROM jaffle_shop_iceberg.rfm_input"
```

RFMスコアリングを実行します。

```bash
cd dbt-glue-project
dbt run --select customer_rfm
```

Athenaから結果を確認します。

```bash
cd ..
uv run python utils/run_athena.py "SELECT count(*) FROM jaffle_shop_iceberg.customer_rfm"
```

RFMスコアのサンプルを確認します。

```bash
uv run python utils/run_athena.py "SELECT customer_id, recency, frequency, monetary, r_score, f_score, m_score FROM jaffle_shop_iceberg.customer_rfm ORDER BY customer_id LIMIT 5"
```

最優良顧客（全スコア5）の件数を確認します。

```bash
uv run python utils/run_athena.py "SELECT count(*) FROM jaffle_shop_iceberg.customer_rfm WHERE r_score=5 AND f_score=5 AND m_score=5"
```

プロジェクトをまたいだリネージを確認します。

macOS / Linux:

```sh
cd dbt-glue-project
dbt ls --select +customer_rfm
```

---

## リセット（最初からやり直す場合）

ハンズオンを途中までやった状態から最初からやり直したい場合は、`chapter7/`ディレクトリに移動してから以下のスクリプトを実行します。AWSリソース（CloudFormationスタック）は残したまま、データとモデルの状態を初期化します。

```bash
cd chapter7
uv run python utils/reset.py
```

リセット後はStep 1から再開できます。

---

## クリーンアップ

ハンズオン終了後、以下のスクリプトでAWSリソースを一括削除します。

```bash
cd chapter7
uv run python utils/delete_resources.py
```

---

## ディレクトリ構成

```
chapter7/
├── README.md
├── pyproject.toml
├── cloudformation/
│   └── ch7-iceberg-resources.yml
├── utils/
│   ├── _common.py                     # 共通ユーティリティ
│   ├── run_athena.py                  # Athena クエリ実行ヘルパー
│   ├── upload_raw_data.py             # CSV を S3 にアップロード
│   ├── create_raw_tables.py           # Hive テーブル定義の作成
│   ├── simulate_updates_step2.py      # Step 2: ソースデータ変更 + モデル更新
│   ├── apply_delete_condition.py      # Step 2-c: delete_condition 追加
│   ├── simulate_updates_step3.py      # Step 3: ソースデータ変更 + モデル更新
│   ├── reset.py                       # 初期状態にリセット
│   └── delete_resources.py            # AWS リソース一括削除
├── steps/
│   ├── step2/                         # Step 2 で使うモデルのスナップショット
│   └── step3/                         # Step 3 で使うモデルのスナップショット
├── dbt-athena-project/
│   ├── dbt_project.yml
│   ├── profiles.yml
│   └── models/
│       ├── staging/
│       └── marts/
└── dbt-glue-project/
    ├── dbt_project.yml
    ├── profiles.yml
    ├── dbt_loom.config.yml
    └── models/marts/
```
