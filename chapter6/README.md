# 第 6 章 ハンズオン

## 前提

uv・AWS CLI のインストール、`dbt-book` プロファイルの作成、環境変数 `AWS_PROFILE` の設定は、[ハンズオン共通のセットアップ](../README.md#共通の前提条件)にまとめています。まだの場合は先に済ませてください。

以降のコマンドは `AWS_PROFILE=dbt-book` を設定した状態で実行します（未設定なら共通のセットアップを参照）。
以下では、本ディレクトリ（`chapter6/`）直下でコマンドを実行します。

## ハンズオンのセットアップ

### 1. Python 環境の準備と raw データの生成

まず Python 仮想環境をセットアップし、`jafgen` で raw データを生成します。

```bash
uv sync --frozen
uv run jafgen
```

`uv sync --frozen` で `jafgen` を含む依存がインストールされ、`uv run jafgen` により `jaffle-data/` 配下に 7 つの CSV が生成されます。

### 2. MWAA 環境の構築

続いて、以下のスクリプトで AWS リソースを構築します。

```bash
uv run python utils/setup.py
```

このスクリプトでは以下の処理を順に実行します。

1. `jaffle-data/` に必要な CSV が生成済みか確認（未生成なら手順 1 の実行を促して中断）
2. CloudFormation スタック `dbt-book-ch6` により S3 バケットと Athena ワークグループを作成
3. 生成された CSV のうち 4 つ (`raw_customers.csv`, `raw_orders.csv`, `raw_items.csv`, `raw_products.csv`) を `mwaa/dags/jafgen_data/` にコピー
4. `mwaa/` 以下のファイルを MWAA 用 S3 バケットにアップロード（DAG ファイル・dbt プロジェクト・`jafgen_data/` の CSV を含む）
5. CloudFormation スタック `dbt-book-ch6-mwaa` により MWAA 環境を作成

MWAA 環境の作成には 30 分程度かかります。
環境の状態は以下のコマンドで確認できます。

```bash
aws mwaa get-environment --name dbt-book-ch6-mwaa --query 'Environment.Status' --output text
```

`AVAILABLE` と表示されたら、セットアップは完了です。

> [!CAUTION]
> MWAA 環境は起動時間に応じて課金が発生します（タスク実行の有無は関係ありません）。
> 環境を停止する仕組みはないため、ハンズオンを中断・終了する場合は「ハンズオンのクリーンアップ」の手順で速やかに削除してください。

## Airflow UI へのアクセス

AWS マネジメントコンソールから、以下の手順で Airflow UI にアクセスします。

1. 左上の検索バーに「mwaa」と入力し、「マネージド Apache Airflow」をクリック
2. MWAA 環境の一覧画面で `dbt-book-ch6-mwaa` を選択
3. 「Airflow UI を開く」をクリック

> [!TIP]
> 以下のコマンドで Airflow UI の URL を取得しアクセスすることも可能です。
>
> ```bash
> aws mwaa get-environment --name dbt-book-ch6-mwaa --query 'Environment.WebserverUrl' --output text
> ```

## DAG の実行

Airflow UI から DAG を実行します。

### サンプル DAG の動作確認 (`dag_00_example`)

最初に、Airflow を体験するために `dag_00_example` を実行します。
この DAG は毎分実行されるよう設定されています。

1. Airflow UI のメニューから「Dags」を開き、`dag_00_example` をクリックする
2. DAG ID の横にあるトグルボタンをクリックして DAG を有効化する
3. しばらく待つと自動的に実行が開始される。タスクが順次成功することを確認する
4. 確認できたら、**再びトグルボタンをクリックして DAG を停止する**（停止し忘れると毎分実行され続けるので注意）

### dbt 関連 DAG の手動実行

つづいて、以下の順で DAG を手動実行してください。
DAG を手動実行するには、DAG 詳細画面の右上にある「Trigger」をクリックし、開いたモーダルで再び「Trigger」をクリックします。

1. `dag_01_generate_raw_data` — Athena のデータベース・テーブル作成と、raw データの S3 アップロード（実行時間: 約 30 秒）
2. `dag_02_dbt_bash` または `dag_03_dbt_cosmos` — dbt モデルのデプロイ（Bash 版と Cosmos 版のいずれか。実行時間: 1〜数分）

### 典型的なワークフローの実行

`dag_04_typical_workflow` は「ソース更新 → `dbt source freshness` → `dbt build`」を組み合わせた DAG です。
スケジュールが設定されていますが、手動で実行し動作を確認できます。

> [!NOTE]
> `dag_04_typical_workflow` は内部でソースデータの取り込みを行いますが、Athena のデータベースおよびテーブルの DDL は実行しません。
> そのため、`dag_04_typical_workflow` を単独で動かす場合でも、事前に `dag_01_generate_raw_data` の DDL タスク（データベース・テーブル作成）が成功している必要があります。

### Asset を用いた複数 DAG 連携の実行

`dag_05_asset_driven.py` では、「典型的なワークフロー」の発展例として、Asset による複数 DAG 連携の例を示しています。
1 ファイルに以下 3 つの DAG が定義されています。

1. `dag_05_ingest_transactions` — トランザクション系ソース (`raw_orders`, `raw_items`) をアップロードし、各テーブルに対応する Asset を更新（毎時実行想定）
2. `dag_05_ingest_master` — マスタ系ソース (`raw_customers`, `raw_products`) をアップロードし、各テーブルに対応する Asset を更新（日次実行想定）
3. `dag_05_run_dbt` — 4 つの Asset すべての更新を待って dbt を実行（AND 条件）

3 つの DAG をトグルで有効化すると、それぞれのスケジュールに従ってソースが更新され、すべての Asset が更新されたタイミングで `dag_05_run_dbt` が自動起動されます。
自動的に起動する様子を確認するために、`dag_05_ingest_transactions`と`dag_05_ingest_master`を手動で実行してください。

> [!NOTE]
> `dag_05_*` の DAG は、`dag_04_typical_workflow` や `dag_02_dbt_bash` / `dag_03_dbt_cosmos` と同じ Athena テーブルを更新します。
> 複数の DAG を同時に有効化するとタスクが重複実行される場合があるため、試す際はいずれか 1 つに絞って有効化してください。
> また、事前に `dag_01_generate_raw_data` の DDL タスクを成功させ、Athena のデータベース・テーブルを作成しておく必要があります。

## 動作確認

実行した DAG が成功したことと、生成されたデータを以下の手順で確認します。

### Airflow UI 上での確認

実行した DAG の DAG Run 詳細画面で、すべてのタスクが緑色（success）になっていることを確認します。
個々のタスクの実行内容やログは、タスク詳細画面の「Logs」タブから参照できます。

### Athena 上での確認

`dag_02_dbt_bash` または `dag_03_dbt_cosmos` のいずれかが成功した後、Athena クエリエディタで以下のクエリを実行し、`customers` モデルがデプロイされていることを確認してください。

```sql
SELECT * FROM jaffle_shop_ch6_prod.customers LIMIT 10
```

`customer_id` などのカラムを含むレコードが返ってくれば成功です。
`jaffle_shop_ch6_prod` データベースには、`customers` のほかに staging モデル（`stg_jaffle_shop__customers` など）も作成されています。

## ハンズオンのクリーンアップ

ハンズオンで作成した AWS リソースを削除します。

```sh
uv run python utils/delete_resources.py
```

スクリプトを実行すると削除対象のリソース一覧が表示され、確認プロンプトで `y` を入力すると一括で削除されます（デフォルトはキャンセル）。
削除対象は以下の通りです。

- CloudFormation スタック `dbt-book-ch6-mwaa` / `dbt-book-ch6`（スタック内で作成された MWAA 環境、VPC、IAM ロール、Athena ワークグループ、S3 バケットなどを含む）
- Glue データベース `jaffle_shop_ch6_raw` / `jaffle_shop_ch6_prod`（DAG や dbt プロジェクトの実行により作成されたもの）

なお、MWAA 環境の削除には時間がかかる場合があります。
途中で `Ctrl + C` によりスクリプトの実行を中断し、しばらく経ってから再実行しても問題ありません。
