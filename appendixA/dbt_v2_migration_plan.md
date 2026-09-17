# 付録A dbt v2 版ハンズオン構築計画

`appendixA/dbt_project`（dbt v1 = Python 版 dbt Core + PostgreSQL + MetricFlow）を、dbt v2（Rust エンジン）+ DuckDB のプロジェクトとして再構築するための計画。第4章（`chapter4/dbt_v2_migration_plan.md`）と同じ方針を踏襲するが、**セマンティックレイヤー固有の非互換が 3 つあり、そこが本計画の中心**になる。

作成日: 2026-09-17 / 検証環境: dbt 2.0.4、DuckDB 1.5.5、dbt-metricflow 0.15.0（dbt-core 1.12.5 / dbt-duckdb 1.11.0）

---

## 1. 前提として確認した事実（実機検証済み）

スクラッチプロジェクト（DuckDB + semantic model + metrics）を作って dbt 2.0.4 で実際に確認した結果。

| # | 確認したこと | 結果 |
| --- | --- | --- |
| 1 | v2 は付録Aの**レガシー spec**（トップレベル `semantic_models:` / `metrics:`）を解釈するか | **しない。** 警告 `[SemanticModelDeprecated (dbt1157)]` を出して無視し、`manifest.json` の `semantic_models` / `metrics` は 0 件。`semantic_manifest.json` も生成されない |
| 2 | v2 の**新 spec**（`models:` 配下に `semantic_model:` / `metrics:` を入れ子）は動くか | **動く。** `dbt parse` で `target/semantic_manifest.json` と `target/private/index/dbt.semantic_*.parquet` が生成される |
| 3 | v2 内蔵の `dbt sl`（list / query / validate）はローカルで使えるか | **使えない。** `dbt_cloud.yml`（dbt platform のプロジェクト設定 + トークン）が必須で、手書きの `dbt_cloud.yaml` を置いても `[error] [IoError (dbt1001)]: Missing project in dbt_cloud.yaml`。`dbt sl` はメトリクスを platform 側で実行する経路 |
| 4 | `mf` CLI（pip `dbt-metricflow`）は v2 が生成した semantic manifest を読めるか | **読める。** `mf list metrics` / `mf list dimensions` / `mf list entities` / `mf query`（`--group-by` / `--where` / `--order` / `--limit` / `--explain`）/ `mf validate-configs` / `mf health-checks`（`SqlEngine.DUCKDB - SELECT 1: Success!`）がすべて成功 |
| 5 | ratio メトリクス（`avg_order_value`）は移植できるか | **書き方が変わる。** 新 spec では `numerator:` / `denominator:` を**メトリクス直下**に書く。v1 と同じく `type_params:` 配下に書くと v2 は numerator/denominator を空で出力し、`mf` 側が `AssertionError: ... is metric type MetricType.RATIO, so neither the numerator and denominator should not be None` でマニフェストをロードできない |
| 6 | derived メトリクス（`type: derived` + `expr`）は動くか | **動く（キー名が変わる）。** 入力メトリクスのリストは v1 の `type_params.metrics` ではなく **`input_metrics:`**（メトリクス直下）。`expr` もメトリクス直下。この形なら v2 が `type_params.metrics` を埋め、`mf query` が正しい値を返す。`type_params:` 配下や `metrics:` という名前で書くと v2 が無視して null のまま出力し、`mf` がロードに失敗する。`alias` / `filter` / `offset_window` も各エントリで指定可 |
| 7 | 同じモデルを 2 つの YAML ファイルに分けて書けるか（`dimensional/models.yml` にテスト、`semantic_layer/*.yml` にセマンティクス） | **できない。** `[error] [InvalidConfig (dbt1005)]: Found duplicate resource definitions for model named 'fct_orders'`。新 spec ではセマンティクスがモデル定義の一部になるため、**`models/semantic_layer/` に分離しておく構成が成立しない**（§2 で方針を決める） |
| 8 | ディメンション専用セマンティックモデル（measure / metrics なし、`agg_time_dimension` なし）は許容されるか | **許容される。** `dim_customers` 相当を primary entity + categorical dimension だけで定義し、`mf query --metrics revenue --group-by customer__region` のエンティティ結合まで成功 |
| 9 | time spine（`dim_dates` の `time_spine.standard_granularity_column`）は v2 でそのまま使えるか | **使える。** 記法は v1 と同じ。`metric_time__month` での集計も成功 |
| 10 | `dbt_cloud.yml` 無しの副作用 | `dbt parse` 時に `[warning] [InvalidConfig (dbt1005)]: Skipping semantic manifest validation due to: No dbt_cloud.yml config` が毎回出る。`DBT_ENGINE_NO_WARN_SEMANTIC_MANIFEST_VALIDATION` で抑止可能。静的検証は `mf validate-configs` で代替する |
| 11 | Python 依存は消せるか | **消せない。** メトリクスのクエリに `mf` が必要なため、第4章と違って uv + venv は残る（`dbt-metricflow[dbt-duckdb]` が dbt-core 1.12.5 / dbt-duckdb 1.11.0 を引き連れてくるが、モデルのビルドは v2 バイナリで行う） |
| 12 | DDL・サンプルデータは第4章の移植成果を流用できるか | `appendixA/init-scripts/01_ddl.sql` は chapter4 の v1 版と**完全一致**（diff 0）。よって `chapter4/duckdb-init/01_ddl.sql` と `05_category_path.sql` はそのまま流用できる。`02` / `03` / `04` はデータ内容が異なる（04 の INSERT 行数は 401 行 vs 第4章 961 行）ため個別移植が必要 |
| 13 | `category_path`（PostgreSQL では LTREE + トリガー生成）は付録Aで使われているか | **使われている**（`stg_zakka_mall__categories` / `dim_products`）。よって `05_category_path.sql` 相当の後処理は必須 |

### 結論（アーキテクチャ）

- データプラットフォーム: **DuckDB**（第4章と同じ。v2 がローカル完結で使えるアダプタは DuckDB のみ）
- メトリクスのクエリ手段: **`mf` CLI を継続**（`dbt sl` は dbt platform 前提のため採用しない）
- セマンティクスの記述: **新 spec へ全面書き換え**（レガシー spec は v2 では無視されるため、移植ではなく書き換えが必須）

---

## 2. 先に決めるべき方針: セマンティクス YAML の配置

事実 #7 のとおり、新 spec ではセマンティクスがモデル定義に埋め込まれるため、v1 の「`models/dimensional/models.yml` にテスト、`models/semantic_layer/*.yml` にセマンティックモデルとメトリクス」という 2 分割が成立しない。3 案を比較する。

| 案 | 内容 | 長所 | 短所 |
| --- | --- | --- | --- |
| **A（推奨）** | `models/dimensional/models.yml` にセマンティクスを統合し、`models/semantic_layer/` を廃止 | ファイル数が最小。v2 の「セマンティクスはモデルの属性」という思想がそのまま形に出る | 本文のディレクトリツリー（`semantic_layer/` が主役）と一致しなくなる。README で差分を明示する必要がある |
| B | モデル定義そのもの（description / columns / tests / semantic_model / metrics）を `models/semantic_layer/*.yml` へ移し、`dimensional/models.yml` には `dim_dates` の time spine だけ残す | ディレクトリ名を維持できる | ディメンション・ファクトのテストが `semantic_layer/` 配下に散る。「semantic_layer にはセマンティクスだけ」という説明が崩れるので、結局本文と乖離する |
| C | レガシー spec を維持し、`mf` 用のマニフェスト生成だけ Python 版 dbt-core 1.12 で行う | YAML を書き換えなくて済む | ビルドは v2、パースは v1 という二重運用になり、v2 移行の意味が失われる。採用しない |

**A を推奨**。「v2 ではセマンティックモデルは独立リソースではなくモデルのプロパティになった」という変化自体が付録の学習ポイントになるため、README にその差分を書いて統合する。

---

## 3. 構築フェーズ

### Phase 0: 出発点を作る

- `appendixA/dbt_project` を現状のまま起点にする（`.venv` / `target` / `logs` / `dbt_packages` は持ち込まない）。
- `appendixA/dbt_project/.gitignore` を新規作成（第4章と同じ内容 + `*.duckdb` / `*.duckdb.wal`）。
- 作業ブランチは `v2-apdxA` を想定。

### Phase 1: DuckDB 基盤の整備

- `appendixA/duckdb-init/` を作成する。
  - `01_ddl.sql` — `chapter4/duckdb-init/01_ddl.sql` をコピー（DDL が完全一致のため）。冒頭コメントの参照元パスを appendixA 向けに直す。
  - `02_sample_data_master.sql` / `03_sample_data_products.sql` / `04_sample_data_orders.sql` — `appendixA/init-scripts/` から移植。機械的な修正は 2 点のみ。
    - `ALTER TABLE ... DISABLE/ENABLE TRIGGER` を削除（`04` に 2 箇所）
    - 先頭に `SET TimeZone = 'UTC';` を追加（PostgreSQL コンテナと同じ日付解釈にするため）
  - `05_category_path.sql` — `chapter4/duckdb-init/05_category_path.sql` をコピー（LTREE + トリガーの代替。`category_path` は付録Aでも使用）。
- 投入確認: `cat duckdb-init/*.sql | duckdb dbt_project/dbt_demo.duckdb` がエラーなく完了し、`zakka_mall.category.category_path` が埋まっていること。
- v1 の残骸を削除: `compose.yml` / `pg-config.json` / `init-scripts/`。

### Phase 2: プロジェクト設定の v2 化

- `profiles.yml` を duckdb アダプタに書き換え（`path: dbt_demo.duckdb`、`schema: analytics`）。`search_path`（PostgreSQL 専用）と `prod` ターゲットの扱いを整理する。
  - ソース定義が `database: dbt_demo` を指しているため、ファイル名は `dbt_demo.duckdb` にする（第4章と同じ制約）。
- `dbt_project.yml`: `require_generic_test_arguments_property: true` を `flags:` に追加（テストは既に `arguments:` 形式なので挙動を固定するだけ）。`static_analysis: baseline` の明示も第4章に合わせる。
- `pyproject.toml`: `dbt-core` / `dbt-postgres` / `sqlfluff-templater-dbt` を外し、**`dbt-metricflow[dbt-duckdb]` のみ**にする（`mf` 用）。`uv.lock` を作り直す。
- `.sqlfluff`: `dialect` を `duckdb` に、`[sqlfluff:templater:dbt]` セクション（`project_dir` など）を削除。**`templater = dbt` の行は残す**（v2 が対応するのは dbt テンプレータのみで、省略すると jinja 扱いで警告になる）。
- `mf` が読む profiles の解決方法を決める（`DBT_PROFILES_DIR=.` を README に書く、または `--profiles-dir` を渡す）。dbt-core 1.x は既定で `~/.dbt` を見るため、プロジェクト直下の `profiles.yml` は明示が必要。

### Phase 3: セマンティクスを新 spec へ書き換え

Phase 2 と並ぶ本体作業。`models/semantic_layer/` の 4 ファイル（`sem_orders` / `sem_customers` / `sem_products` / `sem_order_items`）を、方針 A に従って `models/dimensional/models.yml` のモデルエントリへ統合する。

| v1（レガシー spec） | v2（新 spec） |
| --- | --- |
| トップレベル `semantic_models:` のリスト | `models: - name: <model>` の下に `semantic_model:` ブロック |
| `entities:` / `dimensions:` のリスト（`expr:` でカラム指定） | `columns:` の各カラム配下に `entity:` / `dimension:` ブロック |
| `measures:`（`agg: sum` + `expr:`） | simple メトリクス（`metrics:` に `type: simple` + `agg:` + `expr:`）が measure を兼ねる |
| トップレベル `metrics:` | モデル配下の `metrics:` |
| `defaults.agg_time_dimension: order_date` | `semantic_model:` と同階層の `agg_time_dimension: order_date`（時間軸を持つモデルでは必須） |
| ratio メトリクスの `type_params.numerator` / `denominator` | メトリクス直下の `numerator:` / `denominator:`（事実 #5） |
| 単一カラムに対応しない dimension / entity（`expr` で式を書く） | `derived_semantics:` キーに移す |
| derived メトリクスの `type_params.expr` / `type_params.metrics` | メトリクス直下の `expr:` / **`input_metrics:`**（付録Aでは未使用。発展させる場合の参考） |

- `sem_order_items.yml` の発展課題（`config.enabled: false`）は、`semantic_model.enabled: false` として `fct_order_items` のエントリに畳み込む。README の「`true` に変えて `dbt parse`」という手順は維持できる。
- メトリクス名（`revenue` / `order_count` / `avg_order_value` / `item_revenue`）とディメンション名は v1 と同じにし、README のクエリ例をそのまま使えるようにする。
- 二重定義エラー（事実 #7）を避けるため、統合後に `models/semantic_layer/` を削除する。

### Phase 4: 段階的にビルドを通す

1. `dbt deps` → `dbt parse`（`semantic_manifest.json` が生成されることを確認）
2. `dbt build`（staging 7 + dimensional 5 モデル + データテスト）
3. SQL 方言の差分を潰す。要注意箇所は第4章と同じ観点。
   - `stg_zakka_mall__customers` の `'{{ var("analysis_as_of_date") }}'::date - interval '1 year'`（DuckDB でも動くが結果の同一性を確認）
   - `dim_dates` の `date_trunc('month', date_day) + interval '1 month' - interval '1 day'`
   - `TIMESTAMPTZ` を扱う派生カラム（第4章では `at time zone 'UTC'` の明示が必要だった。v2 の DuckDB アダプタは `settings` の TimeZone を適用しない）
4. `mf` 側を通す。
   - `mf health-checks` → `SqlEngine.DUCKDB - SELECT 1: Success!`
   - `mf validate-configs` → ERRORS: 0
   - `mf list metrics` が 3 件（発展課題を有効化すると 5 件）

### Phase 5: v1 との結果パリティ検証

- モデル・テスト件数: v1 README の「146 / 146 PASS」に対応する v2 の実測値を記録し、README を実測値に更新する（v2 はサマリー表記が `N models | M tests` 形式で、ephemeral は no-op として数える）。
- 主要マートの行数・合計値: `dim_customers` / `dim_products` / `dim_dates` / `fct_orders` / `fct_order_items` の件数と `sum(total_amount)` を v1 と突き合わせる。
- メトリクス値: README のクエリ例をすべて実行し、v1 の結果と一致することを確認する。
  - `mf query --metrics revenue --group-by metric_time__month`
  - `mf query --metrics revenue,order_count --group-by customer__customer_tenure_segment --order -revenue`
  - `mf query --metrics revenue --group-by metric_time__month --where "{{ Dimension('order__order_status') }} = 'delivered'"`
  - `mf query --metrics revenue --group-by metric_time__month,customer__region --limit 24`
  - `mf query --metrics avg_order_value --group-by metric_time__month`
  - `mf query --metrics revenue,order_count --group-by customer__prefecture --explain`
  - 発展課題: `mf query --metrics item_revenue --group-by product__category_name --order -item_revenue --limit 10`
- `mf list dimensions --metrics revenue` が 9 件のままであること（発展課題を有効化しても変わらないという本文の説明の根拠）。

### Phase 6: v2 の機能を README に取り込む

- `dbt lint` / `dbt format`（内蔵。`.sqlfluff` をそのまま解釈）。第4章と同様、本文の掲載形に合わせている箇所は lint を通さない方針を注記し、実測のエラー・警告件数を書く。
- `dbt docs generate` / `dbt docs serve --port 7071 --no-open`（v1 の `--no-browser` は v2 で `--no-open`、既定ポートは 8580）。
- `dbt sl` については「dbt platform 前提のため本ハンズオンでは使わない」ことを明記する（事実 #3）。ここは付録Aで最も誤解されやすい点。
- `dbt parse` 時の semantic manifest validation スキップ警告について、`mf validate-configs` で代替する旨と抑止用の環境変数を注記する。

### Phase 7: ドキュメント整備

- `appendixA/README.md` を v2 + DuckDB + `mf` 前提に更新する。第4章の README を作り直したときと同じ構成に揃える。
  - 冒頭に「dbt v1 + PostgreSQL 版との違い」表（dbt / データプラットフォーム / 必要なもの / Python 仮想環境 / Lint / メトリクスの CLI）
  - 環境構築を「DuckDB データベースの作成 → uv で mf をインストール → dbt deps → dbt build」に差し替え
  - Phase 1〜3 と発展課題の流れは維持し、コマンドだけ v2 / DuckDB / mf に読み替え
  - トラブルシューティングを DuckDB 版に差し替え（`docker compose ps` → ファイルパスと単一ライタ制約、`Catalog Error` 系、YAML 変更後の `dbt parse`）
  - リファレンスのディレクトリツリーを方針 A の構成に更新
- ルート `README.md` の更新（第4章のときと同じ 3 箇所）。
  - ハンズオン一覧の付録A 行を「DuckDB（dbt v2 内蔵アダプタ）+ MetricFlow」「ローカル」に
  - 「Docker を使う章（第 5 章・付録 A）」を「第 5 章」だけに
  - 「dbt のバージョンについて」に付録A も dbt v2 を使う旨を追記（ただし `mf` のため uv は必要、と第4章との差を明示）

---

## 4. 成果物のディレクトリ構成（予定・方針 A）

```
appendixA/
├── README.md                       # v2 + DuckDB + mf 前提に更新
├── dbt_v2_migration_plan.md        # 本ファイル
├── duckdb-init/                    # 新規: DuckDB 用初期化 SQL
│   ├── 01_ddl.sql                  # chapter4/duckdb-init から流用（DDL 完全一致）
│   ├── 02_sample_data_master.sql   # appendixA/init-scripts から移植
│   ├── 03_sample_data_products.sql # 同上
│   ├── 04_sample_data_orders.sql   # 同上（DISABLE/ENABLE TRIGGER 2 箇所を削除）
│   └── 05_category_path.sql        # chapter4/duckdb-init から流用
└── dbt_project/
    ├── .gitignore                  # 新規（target / logs / dbt_packages / *.duckdb など）
    ├── .sqlfluff                   # dialect = duckdb（templater = dbt は維持）
    ├── dbt_project.yml             # flags 追加、static_analysis: baseline
    ├── profiles.yml                # duckdb アダプタ
    ├── packages.yml                # dbt_utils 1.4.1（変更なし）
    ├── pyproject.toml              # dbt-metricflow[dbt-duckdb] のみ（mf 用）
    ├── dbt_demo.duckdb             # duckdb-init から生成（Git 管理外）
    └── models/
        ├── staging/zakka_mall/     # 変更なし（方言差分の確認のみ）
        └── dimensional/
            ├── models.yml          # ★ テスト + time spine + semantic_model + metrics を統合
            ├── dim_customers.sql
            ├── dim_products.sql
            ├── dim_dates.sql
            ├── fct_orders.sql
            └── fct_order_items.sql
```

（削除: `compose.yml` / `pg-config.json` / `init-scripts/` / `models/semantic_layer/` / `.python-version`）

---

## 5. リスクと未確定事項

| # | 内容 | 対応方針 |
| --- | --- | --- |
| 1 | 新 spec の細部（`derived_semantics` の書式、`fill_nulls_with` などのオプション、`saved_queries`）は未検証 | Phase 3 で実際に `dbt parse` + `mf validate-configs` を回して確定する。公式リファレンスは [Migrate to the latest YAML spec](https://docs.getdbt.com/docs/build/latest-metrics-spec) |
| 2 | ~~derived メトリクスが `mf` でロードできない~~ → **解決**（事実 #6） | `input_metrics:` を使えば動作する。付録Aは ratio のみなので本体の変更は不要 |
| 3 | `mf` と v2 の組み合わせはバージョン整合を利用者側が管理する構成（公式も「self-hosted はバージョン管理を自分で行う」と明記） | README に検証済みバージョン（dbt 2.0.4 / dbt-metricflow 0.15.0 / DuckDB 1.5.5）を明記する |
| 4 | 本文（書籍）のディレクトリツリー・YAML 掲載形と v2 版の構成が乖離する | README の「v1 版との違い」節で対応表を示す。第4章の v2 版と同じ扱い |
| 5 | DuckDB は単一プロセスしか書き込めないため、`mf` と `dbt` の同時実行や `duckdb` 対話セッションの開きっぱなしで衝突する | トラブルシューティングに明記する（第4章 README と同じ） |
| 6 | 付録A のサンプルデータは第4章と別物のため、行数・金額の期待値を新たに測り直す必要がある | Phase 5 で v1（PostgreSQL）と v2（DuckDB）を実測比較して記録する |
| 7 | `dbt sl` が将来ローカル実行に対応した場合、`mf` 前提の手順が古くなる | README に「2026/09 時点」と明記し、`dbt sl` を採用しない理由を残す |

---

## 6. 実施結果（2026-09-18）

Phase 0〜7 を実施し、`appendixA/dbt_project` が dbt 2.0.4 + DuckDB 1.5.5 + dbt-metricflow 0.15.0 で完走する状態になった。YAML 配置は方針 A（`dimensional/models.yml` に統合、`semantic_layer/` 廃止）を採用。

| Phase | 状態 | 補足 |
| --- | --- | --- |
| 0 出発点 | 完了 | `.gitignore` を新規作成 |
| 1 DuckDB 基盤 | 完了 | `duckdb-init/` を作成（01・05 は chapter4 から流用、02〜04 は appendixA 版を移植。`04` の DISABLE/ENABLE TRIGGER 2 箇所を削除）。`compose.yml` / `pg-config.json` / `init-scripts/` / `.python-version` を削除 |
| 2 プロジェクト設定 | 完了 | `profiles.yml` を duckdb に、`pyproject.toml` を `dbt-metricflow[dbt-duckdb]` のみに、`.sqlfluff` を `dialect = duckdb` に、`dbt_project.yml` に `flags` と `+static_analysis: baseline` を追加 |
| 3 セマンティクス書き換え | 完了 | `sem_*.yml` 4 本を `dimensional/models.yml` の各モデルエントリへ統合し、`models/semantic_layer/` を削除 |
| 4 ビルド | 完了 | `dbt build` は **146 total / 146 success**（12 models + 134 tests）。SQL 方言の修正は**不要だった**（`::date` / `interval` / `date_trunc` は DuckDB でそのまま動作） |
| 5 パリティ検証 | 完了 | 下表 |
| 6 v2 機能 | 完了 | `dbt lint` は 1 error（ST02）+ 4 warnings（RF04）。`dbt format` 差分なし。`dbt docs generate` 成功 |
| 7 ドキュメント | 完了 | `appendixA/README.md` を全面更新、ルート `README.md` の 6 箇所を更新 |

### v1 との結果パリティ

| 指標 | v1 README の記載 | v2 実測 |
| --- | --- | --- |
| `dbt build` | 146 / 146 PASS（view 7 + table 5 + テスト 134） | 146 total / 146 success（12 models + 134 tests） |
| `mf list metrics` | 3 件 | 3 件（`revenue` / `order_count` / `avg_order_value`） |
| `mf list dimensions --metrics revenue` | 9 件 | 9 件 |
| `mf list entities --metrics revenue` | — | `customer` / `order` |
| `mf validate-configs` | 記載なし | ERRORS 0（7 カテゴリすべて成功） |
| `mf health-checks` | 記載なし | `✅ SqlEngine.DUCKDB - SELECT 1: Success!` |
| 発展課題（`fct_order_items` 有効化） | metrics 3 → 5、dimensions は 9 のまま | 同じ（5 件 / 9 件、`item_revenue` の商品カテゴリ別クエリも成功） |
| `fct_orders` の売上合計 | — | 175 行 / 10,379,292。`mf` のセグメント別合計と一致 |

### 予想と違った点

- `semantic_model:` の `enabled:` は**必須フィールド**だった（省略すると `YAML error: semantic_model: missing field ` + "`enabled`"）。公式ドキュメントでは optional と読める。
- SQL 方言の修正が 1 件も要らなかった（第4章では `at time zone 'UTC'` の明示が必要だった。付録A は snapshot を使わず TIMESTAMPTZ 由来の派生カラムも無いため）。
- `mf` の依存として dbt-core 1.11.12 / dbt-duckdb 1.11.0 が入るが、`mf` は v2 が生成した `target/semantic_manifest.json` を読むだけなので、Python 版 dbt でパースし直す必要はなかった。

### 残っている課題

- `dbt sl` がローカル実行に対応した場合、`mf` 前提の手順は見直しが必要。
- 本文（書籍）掲載の YAML はレガシー spec のままなので、v2 版との対応は README の「v2 の新 spec への書き換え」表で補っている。
