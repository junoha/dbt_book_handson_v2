# 付録A セマンティックレイヤー - ハンズオン環境

## 概要

本付録のハンズオンでは、**ディメンショナルレイヤーの上に** MetricFlow のセマンティックモデルとメトリクス定義を載せ、`mf` CLI から動的にクエリする一連の流れを体験します。

第4章のディメンショナルモデリングと並行して読む想定ですが、ハンズオン実装は第4章のものを丸ごと再利用するのではなく、Semantic Layer の導入に集中できるよう最小構成に絞って再構築しています。

- staging / dimensional の 2 層構成（intermediate レイヤーは省略）
- ディメンションとファクト最新断面のみ（`dbt snapshot` と SCD Type 2 は省略、ナチュラルキー `customer_id` / `product_id` で結合）
- 追加したのは `models/semantic_layer/` 配下の YAML 4 本（うち 1 本は発展課題として無効化）+ `models/dimensional/models.yml` に埋め込んだ time spine 設定
- セマンティックレイヤー自体は DB にテーブルを作らないため、`dbt build` で実体化されるのは staging / dimensional レイヤーのみ

本付録のハンズオンが第4章と異なる点（SCD Type 2 と intermediate レイヤーを入れず、最新断面のみの 2 層構成にした理由）は本文の「プロジェクト配置」節、集計マートとの関係は本文の「集計マートとセマンティックレイヤーの対比」節にまとめています。概念・設計思想の解説は本文側に寄せているので、この README は**手を動かすための最短ガイド**です。

## 前提条件

Docker（`docker compose` が実行できること）と uv のインストールは、[ハンズオン共通のセットアップ](../README.md#共通の前提条件)にまとめています。まだの場合は先に済ませてください。本ハンズオンでは Python 3.12 以上を使い、AWS リソースは使いません。
また、第4章の基本概念を理解していることを前提とします。

本ハンズオンのコマンドはmacOS / Linuxのシェル（bash / zsh）とWindowsのPowerShellで動作します。

## 環境構築

### 1. Docker 環境の起動

```bash
cd appendixA
docker compose up -d
docker compose ps
```

PostgreSQL は `localhost:5432` で待ち受けます。DDL とサンプルデータは初期化スクリプトで自動投入されます。

- `01_ddl.sql` — テーブル定義（10 テーブル）とトリガー
- `02_sample_data_master.sql` — カテゴリ / 仕入先 / 顧客 / 住所
- `03_sample_data_products.sql` — 商品 / 在庫
- `04_sample_data_orders.sql` — 注文 / 明細 / 支払 / 配送

### 2. pgAdmin での確認（オプション）

`http://localhost:8080` を開きます。`PGADMIN_CONFIG_SERVER_MODE: "False"` を指定しているため pgAdmin 自体へのログインは不要です。事前登録されたサーバー（`pg-config.json` で定義）を開くときに PostgreSQL のパスワード `dbt_password` を求められます。

投入されたソースデータを SQL で直接確認したい場合に使います。ハンズオンを進めるうえでは必須ではありません。

### 3. dbt プロジェクトのセットアップ

```bash
cd dbt_project
uv sync --frozen

source .venv/bin/activate   # macOS/Linux
# または
.venv\Scripts\activate      # Windows
```

### 4. 接続確認とパッケージのインストール

```bash
dbt debug          # dbt から PostgreSQL への接続確認
dbt deps           # dbt_utils のインストール
mf health-checks   # MetricFlow から DWH への接続確認
```

## ハンズオンの実施

### Phase 1: ディメンショナルレイヤーのビルド

```bash
# staging + dimensional の構築と全テスト実行
dbt build
```

成功すると **146 / 146 PASS**（view モデル 7 + table モデル 5 + データテスト 134）になります。この時点で `analytics_dimensional.dim_customers` / `fct_orders` などが生成され、セマンティックレイヤーから参照できる状態になります。

### Phase 2: セマンティックレイヤーの検証

```bash
# MetricFlow の設定バリデーション
mf validate-configs

# 登録されているメトリクスとディメンションの一覧
mf list metrics
mf list dimensions --metrics revenue
mf list entities --metrics revenue
```

`mf validate-configs` は `semantic_models` / `metrics` / `time_spine` の整合性（measure 名、entity 名、JOIN 可能性、時間粒度など）を静的にチェックします。ここで参照している YAML の中身は本文「セマンティックモデルとメトリクスの定義」節で解説しています。

### Phase 3: メトリクスのクエリ

```bash
# 月次の売上
mf query --metrics revenue --group-by metric_time__month

# 顧客セグメント別（ディメンションを差し替えるだけで切り口が変わる）
mf query --metrics revenue,order_count --group-by customer__customer_tenure_segment --order -revenue

# 配送完了の注文のみ（フィルタ）
mf query --metrics revenue --group-by metric_time__month --order metric_time__month --where "{{ Dimension('order__order_status') }} = 'delivered'"

# 地域別×月次のクロス集計
mf query --metrics revenue --group-by metric_time__month,customer__region --order metric_time__month --limit 24

# ratio メトリクス（平均注文単価）
mf query --metrics avg_order_value --group-by metric_time__month

# 生成された SQL を確認
mf query --metrics revenue,order_count --group-by customer__prefecture --explain
```

`--where` で使う `{{ Dimension('entity__dimension_name') }}` は MetricFlow 特有のテンプレート構文で、フィルタ対象のエンティティとディメンションを明示するための書式です。

その他のクエリ例と実行結果は本文「MetricFlow CLIによる動的クエリ」節を参照してください。

### 発展課題: 商品軸で売上を切る

本付録の `revenue` は注文ヘッダー粒度（`fct_orders`）で定義しているため、「カテゴリ別売上」のように商品軸で切ることはできません。商品軸を使うには `product` への外部キーを持つ明細粒度のセマンティックモデルが必要です。

その雛形を `models/semantic_layer/sem_order_items.yml` に `enabled: false` で置いています（本文のディレクトリツリーには載せていない発展課題用のファイルです）。ファイル内の `config.enabled` を `true` に変えて `dbt parse` すると次のクエリが通ります。

```bash
mf query --metrics item_revenue --group-by product__category_name --order -item_revenue --limit 10
```

有効化すると `mf list metrics` が 3 件から 5 件に増えるため、本文の掲載内容とは一致しなくなります。一方 `mf list dimensions --metrics revenue` は 9 件のまま変わりません。`revenue` は注文ヘッダー粒度の measure なので、明細を経由して商品軸に到達することはないためです。粒度がメトリクスの切り口を決めるという点が、このモデルを足してみると実感できます。

## SQL の lint（オプション）

本プロジェクトには [SQLFluff](https://docs.sqlfluff.com/) の設定（`.sqlfluff`）が含まれており、`pyproject.toml` の依存にも `sqlfluff-templater-dbt` が入っています。dbt テンプレート（`ref()` や `config()`）を解決してから lint するため、実行前に `dbt deps` を済ませておいてください。

```bash
# lint（本付録は models/ のみが対象。snapshots/ と tests/ は使わない）
sqlfluff lint models/

# 自動修正
sqlfluff fix models/
```

> [!NOTE]
> 本ハンズオンのモデルは lint をすべて通す状態にはしていません。`dim_dates` の `year` / `month` などの予約語カラム名（RF04）と、`stg_zakka_mall__orders` の `is_valid_record` の `case` 式（ST02、`coalesce` に書き換えられる）は本文の説明に合わせたものです。lint 設定は実務プロジェクトでの使い方を示すサンプルとして同梱しており、`.sqlfluff` の `exclude_rules` に自分のチームの方針を追記して使ってください。

## ドキュメントの生成と確認

```bash
dbt docs generate
dbt docs serve --host 0.0.0.0 --port 7071 --no-browser
```

`http://localhost:7071` を開くと、モデルの依存関係グラフとカラムの description を確認できます。左のリソース一覧にはセマンティックモデルも並び、`sem_orders` などがどの dbt モデルを参照しているかを追えます。

## クリーンアップ

```bash
# dbt 側
dbt clean
deactivate

# Docker 側
cd ..                                    # appendixA/ へ
docker compose down                      # コンテナ停止
docker compose down -v --remove-orphans  # 完全削除（ボリュームも消す）
```

`dbt clean` は `dbt_project.yml` の `clean-targets` に指定した `target` / `dbt_packages` / `dbt_internal_packages` / `logs` の 4 つを削除します。実行ログも消えるため、後で見返したい場合は先に退避してください。`dbt_packages` が消えるので、次回は `dbt deps` からやり直します。

## トラブルシューティング

**`mf validate-configs` が「time spine not found」で失敗する**

`models/dimensional/models.yml` に `dim_dates` の `time_spine` 設定が含まれているか確認してください。先に `dbt build` で `dim_dates` テーブルを作成してから `mf` コマンドを実行する必要があります。

**`dbt debug` が PostgreSQL に接続できない**

`docker compose ps` で `dbt_zakka_mall` コンテナが `healthy` になっているか確認してください。ポート 5432 が他プロセスで使われている場合は `compose.yml` のポートマッピングを変更するか、競合プロセスを停止します。

**YAML を編集したのに `mf` の結果が変わらない**

`mf` は dbt が生成したセマンティックマニフェストを読みます。`semantic_models` や `metrics` の YAML を編集したら `dbt parse` を実行してから `mf` コマンドを実行してください。発展課題で `enabled` を切り替えるときにも必要です。

## リファレンス

### dbt プロジェクト構成

```text
appendixA/
├── compose.yml
├── init-scripts/                        # DDL + サンプルデータ 4 ファイル
└── dbt_project/
    ├── pyproject.toml
    ├── dbt_project.yml
    ├── packages.yml
    ├── profiles.yml
    └── models/
        ├── staging/
        │   └── zakka_mall/              # ソース名 zakka_mall 配下にまとめる公式推奨スタイル
        │       ├── _zakka_mall__sources.yml
        │       ├── _zakka_mall__models.yml
        │       ├── stg_zakka_mall__customers.sql
        │       ├── stg_zakka_mall__customer_addresses.sql
        │       ├── stg_zakka_mall__categories.sql
        │       ├── stg_zakka_mall__suppliers.sql
        │       ├── stg_zakka_mall__products.sql
        │       ├── stg_zakka_mall__orders.sql
        │       └── stg_zakka_mall__order_items.sql
        ├── dimensional/
        │   ├── models.yml               # ディメンションとファクトのテスト + dim_dates の time_spine 設定
        │   ├── dim_customers.sql        # customers + customer_addresses を JOIN（最新断面のみ）
        │   ├── dim_products.sql         # products + categories + suppliers を JOIN（最新断面のみ）
        │   ├── dim_dates.sql            # dbt_utils.date_spine + MetricFlow time spine
        │   ├── fct_orders.sql           # 注文ヘッダー、date_key で dim_dates と JOIN（dim_customers への JOIN は semantic layer に委ねる）
        │   └── fct_order_items.sql      # 注文明細、order_id / product_id / customer_id で FK 保持
        └── semantic_layer/              # ★ 本付録の主役
            ├── sem_orders.yml           # fct_orders ベースの semantic model + metrics
            ├── sem_customers.yml        # dim_customers ベースの semantic model（ディメンション専用）
            ├── sem_products.yml         # dim_products ベースの semantic model（ディメンション専用）
            └── sem_order_items.yml      # 発展課題（enabled: false）。商品軸で売上を切るための明細粒度モデル
```

## 実装詳細の補足

### vars によるパラメータ管理

`dbt_project.yml` の `vars` で 3 つのパラメータを定義しています。

- `start_date` / `end_date` — `dim_dates` が使う `dbt_utils.date_spine` の範囲
- `analysis_as_of_date` — `stg_zakka_mall__customers` の `customer_tenure_segment`（会員継続期間セグメント）を判定する基準日

`analysis_as_of_date` を `current_date` にすると実行日によって顧客のセグメントが変わり、`mf query` の結果が再現しなくなります。基準日を明示することで、いつ実行しても同じ内訳が得られます。別の時点で分析したい場合はコマンドラインから上書きできます。

```bash
dbt run --select stg_zakka_mall__customers --vars '{analysis_as_of_date: 2025-06-30}'
```

### time spine を専用ファイルにしない理由

MetricFlow の time spine は独立したリソースではなく、既存の dbt モデルに付けるプロパティです。そのため本付録では `models/dimensional/models.yml` の `dim_dates` エントリに `time_spine` 設定を埋め込んでおり、`semantic_layer/` 配下に time spine 用の YAML は置いていません。設定の詳細は本文「time spineの登録」節を参照してください。
