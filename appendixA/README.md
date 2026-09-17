# 付録A セマンティックレイヤー - ハンズオン環境

**dbt v2**（Rust エンジン）+ **DuckDB** + **MetricFlow（`mf` CLI）** で構築したハンズオン環境です。

## 概要

本付録のハンズオンでは、**ディメンショナルレイヤーの上に** MetricFlow のセマンティックモデルとメトリクス定義を載せ、`mf` CLI から動的にクエリする一連の流れを体験します。

第4章のディメンショナルモデリングと並行して読む想定ですが、ハンズオン実装は第4章のものを丸ごと再利用するのではなく、Semantic Layer の導入に集中できるよう最小構成に絞って再構築しています。

- staging / dimensional の 2 層構成（intermediate レイヤーは省略）
- ディメンションとファクト最新断面のみ（`dbt snapshot` と SCD Type 2 は省略、ナチュラルキー `customer_id` / `product_id` で結合）
- 追加したのは `models/dimensional/models.yml` に埋め込んだセマンティックモデル・メトリクス・time spine の定義（うち 1 モデルは発展課題として無効化）
- セマンティックレイヤー自体は DB にテーブルを作らないため、`dbt build` で実体化されるのは staging / dimensional レイヤーのみ

本付録のハンズオンが第4章と異なる点（SCD Type 2 と intermediate レイヤーを入れず、最新断面のみの 2 層構成にした理由）は本文の「プロジェクト配置」節、集計マートとの関係は本文の「集計マートとセマンティックレイヤーの対比」節にまとめています。概念・設計思想の解説は本文側に寄せているので、この README は**手を動かすための最短ガイド**です。

## dbt v1 + PostgreSQL 版との違い

元の付録A は dbt v1（Python 版 dbt Core）+ PostgreSQL で構築されています。このプロジェクトはそれを dbt v2 + DuckDB に移行したものです。

| | dbt v1 + PostgreSQL 版 | このプロジェクト |
| --- | --- | --- |
| dbt | dbt-core 1.11（Python） | dbt 2.0.4（Rust、単一バイナリ） |
| データプラットフォーム | PostgreSQL 17（Docker） | DuckDB（ローカルファイル 1 つ） |
| 必要なもの | Docker、uv、Python | dbt、DuckDB CLI、uv（`mf` 用） |
| Python 仮想環境 | 必要（dbt 本体 + mf） | 必要（**`mf` のみ**。dbt 本体はバイナリ） |
| メトリクスのクエリ | `mf` CLI | `mf` CLI（`dbt sl` は使わない。後述） |
| セマンティクスの書き方 | `models/semantic_layer/*.yml`（トップレベル `semantic_models:` / `metrics:`） | `models/dimensional/models.yml` のモデルエントリに埋め込み（新 spec） |
| Lint | sqlfluff（`sqlfluff-templater-dbt`） | `dbt lint` / `dbt format`（内蔵） |

> [!IMPORTANT]
> **セマンティクスの記述形式は v2 で変わりました。** v1 のトップレベル `semantic_models:` / `metrics:`（レガシー spec）は
> v2 では警告 `[SemanticModelDeprecated (dbt1157)]` を出して**無視され**、`semantic_manifest.json` も生成されません。
> v2 ではセマンティックモデルは独立したリソースではなく「モデルのプロパティ」なので、モデル定義の中に
> `semantic_model:` / `metrics:` を埋め込みます。同じモデルを 2 つの YAML に分けて書くと
> `duplicate resource definitions` エラーになるため、v1 の `models/semantic_layer/` ディレクトリは廃止し、
> テストとセマンティクスを `models/dimensional/models.yml` に統合しています。

> [!IMPORTANT]
> **v2 内蔵の `dbt sl` コマンドは使いません。** `dbt sl list` / `dbt sl query` / `dbt sl validate` はメトリクスを
> dbt platform 側で実行する経路で、`dbt_cloud.yml`（プロジェクト設定 + トークン）が無いと
> `Missing project in dbt_cloud.yaml` で失敗します。ローカル完結の本ハンズオンでは、v1 と同じ
> `mf` CLI（`dbt-metricflow`）を使い、v2 が生成した `target/semantic_manifest.json` を読ませます。
> 2026/09 時点の構成です。

> [!NOTE]
> `dbt_cloud.yml` が無いため、`dbt parse` / `dbt build` のたびに
> `Skipping semantic manifest validation due to: No dbt_cloud.yml config` という警告が出ます。
> 静的検証は `mf validate-configs` で代替できます。警告を消したい場合は環境変数
> `DBT_ENGINE_NO_WARN_SEMANTIC_MANIFEST_VALIDATION` を設定してください。

## 前提条件

本ハンズオンでは AWS リソースも Docker も使いません。第4章の基本概念を理解していることを前提とします。

検証済みバージョンは dbt 2.0.4 / DuckDB 1.5.5 / dbt-metricflow 0.15.0 です。`mf` は self-hosted 構成ではバージョン整合を利用者側で管理する必要があるため、うまく動かないときはまずこの組み合わせを試してください。

### dbt v2

```bash
# macOS（Homebrew）
brew tap dbt-labs/dbt
brew install dbt-labs/dbt/dbt

# macOS / Linux（インストーラ）
curl -fsSL https://public.cdn.getdbt.com/fs/install/install.sh | sh -s -- --update

# Windows（PowerShell）
irm https://public.cdn.getdbt.com/fs/install/install.ps1 | iex
```

```bash
dbt --version   # 2.0.4 以上であること
```

### DuckDB CLI

データベースの初期化と中身の確認に使います。

```bash
# macOS
brew install duckdb
```

Windows やその他の環境は [DuckDB の Installation ページ](https://duckdb.org/docs/installation/) を参照してください。

### uv

`mf` CLI（Python パッケージ）のインストールに使います。手順は [ハンズオン共通のセットアップ](../README.md#共通の前提条件)を参照してください。Python 3.12 以上が必要です。

## 環境構築

### 1. DuckDB データベースの作成

`appendixA/duckdb-init/` の SQL を順番に流し込みます。`appendixA` ディレクトリで実行してください。

```bash
cd appendixA
cat duckdb-init/*.sql | duckdb dbt_project/dbt_demo.duckdb
```

Windows（PowerShell）の場合:

```powershell
cd appendixA
Get-Content duckdb-init/*.sql | duckdb dbt_project/dbt_demo.duckdb
```

```
duckdb-init/
├── 01_ddl.sql                    # テーブル定義（10 テーブル）
├── 02_sample_data_master.sql     # カテゴリ / 仕入先 / 顧客 / 住所
├── 03_sample_data_products.sql   # 商品 / 在庫
├── 04_sample_data_orders.sql     # 注文 / 明細 / 支払 / 配送
└── 05_category_path.sql          # カテゴリ階層パスの生成
```

`01_ddl.sql` は PostgreSQL 版の DDL を DuckDB へ移植したものです（IDENTITY → シーケンス、LTREE → VARCHAR、トリガー・インデックス・外部キーの削除）。PostgreSQL 版ではトリガーが LTREE の `category_path` を自動生成していましたが、DuckDB にはトリガーが無いため `05_category_path.sql` で再帰 CTE を使って生成します。`category_path` は `stg_zakka_mall__categories` / `dim_products` が参照するため必須です。

### 2. データの確認（オプション）

```bash
duckdb dbt_project/dbt_demo.duckdb
```

```sql
D SELECT count(*) FROM zakka_mall."order";       -- 175
D SELECT count(*) FROM zakka_mall.order_item;    -- 176
D SELECT category_code, category_path FROM zakka_mall.category LIMIT 5;
D .quit
```

### 3. mf（MetricFlow）のインストール

```bash
cd dbt_project
uv sync --frozen

source .venv/bin/activate   # macOS/Linux
# または
.venv\Scripts\activate      # Windows
```

この仮想環境には `dbt-metricflow[dbt-duckdb]` だけが入ります。モデルのビルドは dbt v2 バイナリで行うため、`dbt-core` / `dbt-postgres` / `sqlfluff` は含めていません。

`mf` は Python 版の dbt を通して `profiles.yml` を読みますが、既定の探索先は `~/.dbt` です。プロジェクト直下の `profiles.yml` を使うため、`mf` を実行するシェルで次を設定してください。

```bash
export DBT_PROFILES_DIR=$(pwd)      # macOS/Linux（dbt_project ディレクトリで実行）
```

```powershell
$env:DBT_PROFILES_DIR = (Get-Location).Path   # Windows (PowerShell)
```

### 4. 接続確認とパッケージのインストール

```bash
dbt debug          # dbt から DuckDB への接続確認
dbt deps           # dbt_utils のインストール
mf health-checks   # MetricFlow から DWH への接続確認
```

`mf health-checks` が `✅ SqlEngine.DUCKDB - SELECT 1: Success!` を返せば MetricFlow 側の接続も通っています。

## ハンズオンの実施

### Phase 1: ディメンショナルレイヤーのビルド

```bash
# staging + dimensional の構築と全テスト実行
dbt build
```

成功すると **146 / 146 success**（view モデル 7 + table モデル 5 + データテスト 134）になります。この時点で `analytics_dimensional.dim_customers` / `fct_orders` などが生成され、セマンティックレイヤーから参照できる状態になります。

`dbt build` / `dbt parse` は `target/semantic_manifest.json` も生成します。`mf` はこのファイルを読むため、YAML を編集したら（少なくとも）`dbt parse` を実行してから `mf` を使います。

### Phase 2: セマンティックレイヤーの検証

```bash
# MetricFlow の設定バリデーション
mf validate-configs

# 登録されているメトリクスとディメンションの一覧
mf list metrics
mf list dimensions --metrics revenue
mf list entities --metrics revenue
```

`mf validate-configs` は `semantic_models` / `metrics` / `time_spine` の整合性（メトリクス名、entity 名、JOIN 可能性、時間粒度など）を DWH と突き合わせてチェックします。ERRORS が 0 件、`mf list metrics` が 3 件、`mf list dimensions --metrics revenue` が 9 件になれば期待どおりです。ここで参照している YAML の中身は本文「セマンティックモデルとメトリクスの定義」節で解説しています（記述形式は v2 の新 spec に読み替えてください。対応表は後述の「v2 の新 spec への書き換え」）。

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

その雛形を `models/dimensional/models.yml` の `fct_order_items` エントリに無効化した状態で置いています（`semantic_model.enabled: false` と、2 つのメトリクスの `config.enabled: false`）。これらを `true` に変えて `dbt parse` すると次のクエリが通ります。

```bash
mf query --metrics item_revenue --group-by product__category_name --order -item_revenue --limit 10
```

有効化すると `mf list metrics` が 3 件から 5 件に増えるため、本文の掲載内容とは一致しなくなります。一方 `mf list dimensions --metrics revenue` は 9 件のまま変わりません。`revenue` は注文ヘッダー粒度のメトリクスなので、明細を経由して商品軸に到達することはないためです。粒度がメトリクスの切り口を決めるという点が、このモデルを足してみると実感できます。

## v2 の新 spec への書き換え

本文と v1 版のプロジェクトはレガシー spec で書かれています。v2 版で何をどう書き換えたかの対応表です。

| v1（レガシー spec） | v2（新 spec） |
| --- | --- |
| トップレベル `semantic_models:` のリスト（別ファイル） | `models: - name: <model>` の下の `semantic_model:` ブロック（`enabled:` は必須） |
| `model: ref('fct_orders')` | モデルエントリ自体がセマンティックモデルの対象なので不要 |
| `entities:` / `dimensions:` のリスト（`expr:` でカラム指定） | `columns:` の各カラム配下の `entity:` / `dimension:` ブロック |
| `measures:`（`agg: sum` + `expr:`） | simple メトリクス（`type: simple` + `agg:` + `expr:`）が measure を兼ねる |
| トップレベル `metrics:` | モデル配下の `metrics:` |
| `defaults.agg_time_dimension: order_date` | `semantic_model:` と同階層の `agg_time_dimension: order_date` |
| time dimension の `type_params.time_granularity: day` | カラムの `granularity: day` |
| ratio メトリクスの `type_params.numerator` / `denominator` | メトリクス直下の `numerator:` / `denominator:` |
| derived メトリクスの `type_params.expr` / `type_params.metrics` | メトリクス直下の `expr:` / `input_metrics:` |

> [!NOTE]
> ratio メトリクス（`avg_order_value`）の `numerator` / `denominator` を v1 と同じく `type_params:` の下に
> 書くと、v2 は両方を空にして `semantic_manifest.json` を出力し、`mf` 側が
> `AssertionError: ... is metric type MetricType.RATIO, so neither the numerator and denominator should not be None`
> でマニフェストをロードできなくなります。メトリクス直下に書いてください。

> [!NOTE]
> derived メトリクス（`type: derived`）を足す場合、入力メトリクスのリストは `input_metrics:` です。
> v1 の `type_params.metrics` という名前のままだと v2 は値を捨ててしまい、`mf` がマニフェストを
> ロードできません。`expr` もメトリクス直下に書きます。
>
> ```yaml
> - name: avg_order_value
>   type: derived
>   expr: revenue / order_count
>   input_metrics:
>     - name: revenue
>     - name: order_count
> ```

> [!NOTE]
> v1 では使わないメトリクスの元データにも `measures`（`subtotal` / `tax_amount` / `shipping_fee`）を定義していましたが、
> v2 では measure が simple メトリクスに統合されたため、そのまま移植すると `mf list metrics` の件数が増えてしまいます。
> v2 版では v1 が公開していた 3 メトリクス（`revenue` / `order_count` / `avg_order_value`）だけを定義しています。

## SQL の lint

v2 は sqlfluff 相当のリンタ・フォーマッタを内蔵しており、`.sqlfluff` の設定とルールコードをそのまま解釈します。v1 のように `sqlfluff-templater-dbt` を別途インストールする必要はありません。

```bash
# lint（models / snapshots / tests を対象にする。本付録は models/ のみ）
dbt lint

# 自動整形
dbt format
```

> [!NOTE]
> 本ハンズオンのモデルは lint をすべて通す状態にはしていません。`dbt lint` は 1 件のエラー
> （`stg_zakka_mall__orders` の `is_valid_record` の `case` 式、ST02。`coalesce` に書き換えられる）と
> 4 件の警告（`dim_dates` の `year` / `month` / `day` / `quarter` という予約語カラム名、RF04）を報告し、
> 終了コード 1 で終わります。いずれも本文の説明に合わせたものです。lint 設定は実務プロジェクトでの
> 使い方を示すサンプルとして同梱しており、`.sqlfluff` の `exclude_rules` に自分のチームの方針を
> 追記して使ってください。なお現在のモデルは整形済みのため、`dbt format` を実行しても差分は出ません。

## ドキュメントの生成と確認

```bash
dbt docs generate
dbt docs serve --port 7071 --no-open
```

`http://localhost:7071` を開くと、モデルの依存関係グラフとカラムの description を確認できます。

> [!NOTE]
> v1 の `--no-browser` は v2 では `--no-open` に変わり、既定ポートは 8580 です。`dbt docs serve` は
> `target/private/index/` の Parquet を読むだけなので、事前に `dbt build` か `dbt docs generate` を
> 済ませておいてください。

## クリーンアップ

```bash
# dbt 側
dbt clean
deactivate

# データベースファイルの削除
rm dbt_demo.duckdb
```

`dbt clean` は `dbt_project.yml` の `clean-targets` に指定した `target` / `dbt_packages` / `dbt_internal_packages` / `logs` の 4 つを削除します。実行ログも消えるため、後で見返したい場合は先に退避してください。`dbt_packages` が消えるので、次回は `dbt deps` からやり直します。

## トラブルシューティング

**`dbt debug` がデータベースに接続できない**

`profiles.yml` の `path: dbt_demo.duckdb` は相対パスです。`appendixA/dbt_project` ディレクトリで実行しているか、`dbt_demo.duckdb` が同ディレクトリに作られているかを確認してください（「環境構築」の手順 1 は `appendixA` ディレクトリで実行し、`dbt_project/dbt_demo.duckdb` に作成します）。DuckDB は 1 プロセスしか書き込めないため、`duckdb dbt_demo.duckdb` の対話セッションを開いたままだと dbt 側が書き込めません。`.quit` で閉じてから実行してください。

**`mf` が `Unable to load the semantic manifest` で失敗する**

まず `dbt parse` を実行して `target/semantic_manifest.json` を作り直してください。それでも失敗する場合は、ratio メトリクスの `numerator` / `denominator` をメトリクス直下に書いているか（`type_params:` の下ではないか）を確認します。

**`mf` が profiles.yml を見つけられない**

`mf` は Python 版 dbt 経由で `profiles.yml` を読み、既定では `~/.dbt` を探します。`dbt_project` ディレクトリで `export DBT_PROFILES_DIR=$(pwd)` を実行してから `mf` を使ってください。

**`mf validate-configs` が「time spine not found」で失敗する**

`models/dimensional/models.yml` に `dim_dates` の `time_spine` 設定が含まれているか確認してください。先に `dbt build` で `dim_dates` テーブルを作成してから `mf` コマンドを実行する必要があります。

**YAML を編集したのに `mf` の結果が変わらない**

`mf` は dbt が生成したセマンティックマニフェストを読みます。`semantic_model` や `metrics` の YAML を編集したら `dbt parse` を実行してから `mf` コマンドを実行してください。発展課題で `enabled` を切り替えるときにも必要です。

**`dbt sl list metrics` が `Missing project in dbt_cloud.yaml` で失敗する**

`dbt sl` は dbt platform 前提のコマンドです。本ハンズオンでは `mf` を使ってください（冒頭の IMPORTANT を参照）。

**何度も実行して DB の状態が分からなくなった**

データベースファイルを削除して作り直すと、初期化スクリプトからクリーンな状態に戻ります。

```bash
rm dbt_project/dbt_demo.duckdb          # appendixA ディレクトリで実行
cat duckdb-init/*.sql | duckdb dbt_project/dbt_demo.duckdb
```

## リファレンス

### dbt プロジェクト構成

```text
appendixA/
├── duckdb-init/                         # DDL + サンプルデータ + カテゴリパス生成
└── dbt_project/
    ├── pyproject.toml                   # mf（dbt-metricflow[dbt-duckdb]）専用の Python 依存
    ├── dbt_project.yml
    ├── packages.yml
    ├── profiles.yml                     # DuckDB のファイルパス
    ├── .sqlfluff                        # dbt lint / dbt format の設定（dialect = duckdb）
    ├── dbt_demo.duckdb                  # duckdb-init から生成（Git 管理外）
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
        └── dimensional/
            ├── models.yml               # ★ テスト + time spine + セマンティックモデル + メトリクス
            ├── dim_customers.sql        # customers + customer_addresses を JOIN（最新断面のみ）
            ├── dim_products.sql         # products + categories + suppliers を JOIN（最新断面のみ）
            ├── dim_dates.sql            # dbt_utils.date_spine + MetricFlow time spine
            ├── fct_orders.sql           # 注文ヘッダー、date_key で dim_dates と JOIN（dim_customers への JOIN は semantic layer に委ねる）
            └── fct_order_items.sql      # 注文明細、order_id / product_id / customer_id で FK 保持
```

> [!NOTE]
> v1 版では `models/semantic_layer/` に 4 ファイル（`sem_orders` / `sem_customers` / `sem_products` / `sem_order_items`）を
> 置いていました。v2 の新 spec ではセマンティクスがモデル定義の一部になるため、このディレクトリは廃止し、
> `models/dimensional/models.yml` の各モデルエントリへ統合しています。本文のディレクトリツリーとは
> この点が異なります。

`models.yml` に統合されたセマンティックモデルは次の 4 つです。

| セマンティックモデル | 対応するモデル | 役割 |
| --- | --- | --- |
| `orders` | `fct_orders` | primary entity `order` / foreign entity `customer`。`revenue` / `order_count` / `avg_order_value` を定義 |
| `customers` | `dim_customers` | primary entity `customer`。都道府県・地域・会員ステータス等の切り口を提供（メトリクスなし） |
| `products` | `dim_products` | primary entity `product`。カテゴリ・仕入先・価格ティア等の切り口を提供（メトリクスなし） |
| `order_items` | `fct_order_items` | 発展課題（`enabled: false`）。明細粒度で `item_revenue` / `items_sold` を定義 |

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

MetricFlow の time spine は独立したリソースではなく、既存の dbt モデルに付けるプロパティです。そのため本付録では `models/dimensional/models.yml` の `dim_dates` エントリに `time_spine` 設定を埋め込んでいます。設定の詳細は本文「time spineの登録」節を参照してください。v2 でも記法は v1 と同じで、`standard_granularity_column` に指定したカラムへ `granularity: day` を付けます。
