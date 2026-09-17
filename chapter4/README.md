# 第4章 実践的データモデリング - ハンズオン環境

**dbt v2**（Rust エンジン）+ **DuckDB** で構築した dbt プロジェクトです。

モデリングの考え方・レイヤー構成・各マートの意味は [../README.md](../README.md) にまとめています。こちらでは環境の作り方と、dbt v1 + PostgreSQL 版との違いを扱います。

## dbt v1 + PostgreSQL 版との違い

元の第4章は dbt v1（Python 版 dbt Core）+ PostgreSQL で構築されています。このプロジェクトはそれを dbt v2 + DuckDB に移行したものです。

| | dbt v1 + PostgreSQL 版 | このプロジェクト |
| --- | --- | --- |
| dbt | dbt-core 1.11（Python） | dbt 2.0.4（Rust、単一バイナリ） |
| データプラットフォーム | PostgreSQL 17（Docker） | DuckDB（ローカルファイル 1 つ） |
| 必要なもの | Docker、uv、Python | dbt、DuckDB CLI |
| Python 仮想環境 | 必要（`uv sync`） | 不要 |
| Lint | sqlfluff（`sqlfluff-templater-dbt`） | `dbt lint` / `dbt format`（内蔵） |
| dbt platform アカウント | 不要 | 不要（`dbt login` はしない） |

> [!NOTE]
> 2026/09 時点では dbt v2 は PostgreSQL を正式サポートしていません（Snowflake / BigQuery / Databricks / Redshift / DuckDB / Spark）。
> ローカル完結で動かせる v2 のアダプタが DuckDB のみのため、このプロジェクトでは DuckDB を使います。

> [!IMPORTANT]
> `dbt login` をしない構成のため、静的解析は `baseline`（検出結果はすべて警告）に固定されます。
> `strict` が前提のカラムレベルリネージ・カラム単位の型チェックは使えません。

## 前提条件

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

## 環境構築

### 1. DuckDB データベースの作成

`chapter4/duckdb-init/` の SQL を順番に流し込みます。`chapter4` ディレクトリで実行してください。

```bash
cd chapter4
cat duckdb-init/*.sql | duckdb dbt_project/dbt_demo.duckdb
```

Windows（PowerShell）の場合:

```powershell
cd chapter4
Get-Content duckdb-init/*.sql | duckdb dbt_project/dbt_demo.duckdb
```

```
duckdb-init/
├── 01_ddl.sql                    # テーブル定義（DDL）
├── 02_sample_data_master.sql     # マスタデータ（カテゴリ、仕入先、顧客、住所）
├── 03_sample_data_products.sql   # 商品データ（商品、在庫）
├── 04_sample_data_orders.sql     # 取引データ（注文、支払い、配送）
└── 05_category_path.sql          # カテゴリ階層パスの生成
```

`01_ddl.sql` は PostgreSQL 版の DDL を DuckDB へ移植したものです。移植内容（IDENTITY → シーケンス、LTREE → VARCHAR、トリガー・インデックス・外部キーの削除など）はファイル先頭のコメントにまとめています。

### 2. データの確認（オプション）

```bash
duckdb dbt_project/dbt_demo.duckdb
```

```sql
D SELECT count(*) FROM zakka_mall."order";
D SELECT category_code, category_path FROM zakka_mall.category LIMIT 5;
D .quit
```

### 3. 接続確認とパッケージのインストール

```bash
cd dbt_project
dbt debug
dbt deps
```

### 4. ビルド

```bash
dbt build
```

25 models / 198 tests / 2 snapshots が実行されます（intermediate 層の 4 モデルは ephemeral なので no-op）。

## SCD Type 2（履歴管理）の確認

`base_dim_* → snapshot_dim_* → dim_* → fct_*` の 4 段構成の挙動は、サンプルデータを変更して確認します。

```bash
dbt run-operation add_sample_data_changes
dbt run --select base_dim_customers base_dim_products
dbt snapshot
dbt run --select marts.core
```

```bash
duckdb dbt_demo.duckdb -c "
SELECT customer_id, customer_status, email, dbt_valid_from, dbt_valid_to
FROM analytics_snapshots.snapshot_dim_customers
WHERE customer_id IN (1, 2)
ORDER BY customer_id, dbt_valid_from;"
```

顧客 1 / 2 と商品 1 / 3 について、変更前後の 2 バージョンが期間付きで保持されていれば成功です。

> [!NOTE]
> DuckDB にはトリガーが無いため、`add_sample_data_changes` マクロは PostgreSQL 版と違って
> `updated_at = NOW()` と注文番号の採番を明示的に実行しています。
> snapshot は `strategy: timestamp` で `updated_at` を見るため、この明示が無いと変更を検知できません。

## v2 の機能を試す

```bash
# 内蔵リンタ / フォーマッタ（.sqlfluff の設定とルールコードをそのまま解釈する）
dbt lint
dbt format

# dbt Docs v2（Parquet アーティファクト + 静的サイトを一括生成）
dbt docs generate
dbt docs serve

# モデルの鮮度チェック（Beta）
dbt freshness

# メタデータを Parquet で出力
dbt parse --generate-info-schema
```

## クリーンアップ

```bash
dbt clean                 # target / dbt_packages / logs を削除
rm dbt_demo.duckdb        # データベースファイルを削除
```
