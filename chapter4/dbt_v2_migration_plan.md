# 第4章 dbt v2 版ハンズオン構築計画

`chapter4/dbt_project`（dbt v1 = Python 版 dbt Core + PostgreSQL）を、dbt v2（Rust エンジン、旧 Fusion）+ DuckDB のプロジェクトとして再構築するための計画と実施記録。

本リポジトリは v2 化専用のフォークのため、v2 版のプロジェクトを `dbt_project/` にそのまま置いている（v1 版は元リポジトリ側にある）。

作成日: 2026-09-16 / 対象 dbt バージョン: 2.0.4

---

## 1. 前提として確認した事実

事前に手元環境と公式ドキュメントで検証した結果を先に置く。ここが計画の分岐点になっている。

| 確認項目 | 結果 |
| --- | --- |
| ローカルの dbt v2 | `dbt 2.0.4`（Homebrew の `/opt/homebrew/bin/dbt`）が導入済み |
| 用語 | dbt Core = **v1**（Python）、Fusion = **v2**（Rust）。ドキュメント上は「dbt v1 / v2」表記に統一されている |
| v2 のサポートアダプタ | Snowflake / BigQuery / Databricks / Redshift（Preview）、Apache Spark / DuckDB（Beta, CLI のみ） |
| **PostgreSQL** | **正式サポート外**。`DBT_ALLOW_EXPERIMENTAL_ADAPTERS=true` で読み込みは通るが、現行 `profiles.yml` に対し `dbt debug` が **SIGSEGV（exit 139）で異常終了**。ハンズオン基盤としては採用不可 |
| dbt_utils | v2 互換（公式に `dbt_utils` / `audit_helper` / `dbt_external_tables` / `dbt_project_evaluator` は対応済みと明記）。`require-dbt-version` 由来の `dbt1065` 警告は既知の誤検知 |
| Python パッケージ | v2 は自己完結バイナリ。ADBC ドライバを CDN から取得してキャッシュするため、`dbt-core` / `dbt-postgres` の pip 依存は不要になる |

### 採用するデータプラットフォーム: DuckDB

理由:

- v2 で公式サポートされているローカル完結型アダプタは DuckDB のみ。
- Docker / PostgreSQL / pgAdmin が不要になり、ハンズオンの初期セットアップが軽くなる。
- DuckDB は PostgreSQL 互換寄りの方言で、既存モデル SQL の書き換え量が小さい（後述 §5）。

代替案（採用しない）: DuckDB の `postgres` 拡張で既存 PostgreSQL を `ATTACH` し、raw データだけ既存 Docker を流用する。init-scripts の移植が不要になる利点はあるが、Docker 依存が残り、拡張分の説明コストも増えるため今回は採らない。§2 Phase 1 の移植量が想定を超えた場合のフォールバックとして保持する。

---

## 2. 構築フェーズ

### Phase 0: 出発点を作る

1. v1 版の `chapter4/dbt_project` を出発点にする（`.venv` / `target` / `logs` / `dbt_packages` は持ち込まない）。
2. v1 側の deprecation を先に潰す。v2 は非推奨機能を一切許容しないため、autofix を最初に通す。

```bash
cd chapter4/dbt_project
uvx --from git+https://github.com/dbt-labs/dbt-autofix.git dbt-autofix deprecations
git diff   # 変更内容を必ずレビューする（autofix 自体が壊すケースがある）
```

3. **`dbt login` は行わない**（ハンズオンを簡潔に保つため、dbt platform アカウント不要で完結させる）。

> [!IMPORTANT]
> 未ログインだと静的解析は `baseline` に固定される。`baseline` では検出結果がすべて警告扱いになり、`strict` が前提となる機能（カラムレベルリネージ、プロジェクト全体の ref 検証、カラム単位の型解決、LSP のカラム定義ジャンプ）は使えない。本ハンズオンはこれらを対象外とする。

**完了条件**: autofix の差分を把握し、意図しない変換が無いことを確認済み。

### Phase 1: DuckDB 基盤の整備

`chapter4/init-scripts/*.sql`（DDL 326 行 + データ 1,315 行）を DuckDB 用に移植して `chapter4/duckdb-init/` を作る。データ INSERT はほぼそのまま流用でき、手を入れるのは DDL のみ。

| 移植対象 | 対応 |
| --- | --- |
| `CREATE EXTENSION uuid-ossp` / `ltree` | 削除（実際に使っているのは `gen_random_uuid()` のみで、DuckDB に組み込み済み） |
| `GRANT` / `ALTER DEFAULT PRIVILEGES` | 削除（DuckDB に権限モデルは無い） |
| `BIGINT GENERATED ALWAYS AS IDENTITY` (7 テーブル) | `CREATE SEQUENCE` + `DEFAULT nextval('...')` に置換。INSERT 文が ID 列を省略しているため必須 |
| `CREATE TYPE ... AS ENUM` (8 種) | DuckDB も対応。そのまま流用 |
| `TIMESTAMPTZ` / `NOW()` / `CURRENT_DATE` / `CHECK` | そのまま流用可 |
| `CREATE INDEX` (22 本) | 削除（DuckDB では不要。列指向のため効果が薄い） |
| `SET search_path = 'zakka_mall'` | DuckDB も対応。または INSERT をスキーマ修飾に書き換え |

初期化手順（README に載せる形）:

```bash
cd chapter4
cat duckdb-init/*.sql | duckdb dbt_project/dbt_demo.duckdb
```

> データベースファイル名は `dbt_demo.duckdb` にする。DuckDB はファイル名がカタログ名になるため、
> `zakka_mall.duckdb` にするとスキーマ名 `zakka_mall` と衝突して参照できなくなる。

`profiles.yml` を DuckDB に差し替える:

```yaml
dbt_book_ch4_v2_project:
  target: dev
  outputs:
    dev:
      type: duckdb
      path: dbt_demo.duckdb
      schema: analytics
      threads: 4
```

**完了条件**: `dbt debug` が接続テストまで成功し、`zakka_mall` スキーマに 9 テーブル分のデータが入っている。

### Phase 2: プロジェクト設定の v2 化

- `dbt_project.yml`
  - `+static_analysis: baseline` を明示（v2 の既定値。未ログインのため `strict` は使わない）。
  - behavior-change flag の opt-out（`flags:`）があれば削除。現行プロジェクトには無いことを確認する。
  - `clean-targets` の見直し（v2 の `dbt clean` はリソースパスとプロジェクト外を削除しない仕様に変更）。
- `packages.yml`: `dbt_utils 1.4.1` を維持。`dbt deps` で `dbt1065` 警告が出ても無害。
- `pyproject.toml` / `uv.lock`: `dbt-core` / `dbt-postgres` / `sqlfluff-templater-dbt` を除去。データ投入用に `duckdb` だけ残すか、DuckDB CLI 前提にして pyproject 自体を廃止するかを決める。
- Lint: `sqlfluff` → v2 内蔵の `dbt lint` / `dbt format` に置換。`.sqlfluff` の設定とルールコード（`CP01`、`RF03` など）はそのまま解釈される。
- YAML: トップレベルの独立アンカーは `anchors:` キー配下へ移動が必要（現行 YAML に該当箇所があるか要確認）。自己参照アンカーは v2 で不可。

**完了条件**: `dbt deps` と `dbt parse` がエラーなしで完了。

### Phase 3: 段階的にビルドを通す

v2 は v1 でコンパイル時／実行時まで露出しなかったエラーを **parse 時点で** 出す（存在しないマクロ・var・generic test、設定キーの誤記、重複 docs ブロックなど）。以下を順に通し、都度エラーを分類して潰す。

```bash
dbt deps
dbt parse
dbt compile
dbt build
```

エラー分類の方針（`migrating-dbt-core-to-fusion` スキルの 4 分類に準拠）:

- **A: 自動修正可** — 設定内のクォートのネスト等。
- **B: 要承認の修正** — `config.get()`/`config.require()` が `meta` を読まなくなった件（`config.meta_get()` / `config.meta_require()` へ）、未使用 YAML エントリ、パッケージバージョン競合（`dbt8999`）、`--models` → `--select`。
- **C: 判断が必要** — ハードコードされた FQN の扱い、`analyses/` の存続。
- **D: v2 側の修正待ち** — エンジン欠落・クラッシュ。該当時は `github.com/dbt-labs/dbt-fusion/issues` を確認し、回避策のリスクを明示してから採否を決める。

**完了条件**: `dbt build` が完走。残った Category D は課題として文書化。

### Phase 4: SQL 方言差分の解消

既存モデル 30 ファイルで使われている PostgreSQL 依存箇所。ほとんどは DuckDB でそのまま動く想定だが、Phase 3 の静的解析出力で個別に検証する。

| 使用箇所 | 件数 | 想定リスク |
| --- | --- | --- |
| `coalesce` | 36 | 低 |
| `extract(...)` | 25 | 低（DuckDB 互換） |
| `CURRENT_DATE` | 24 | 低 |
| `interval` | 4 | 中（リテラル記法差） |
| `to_char` | 3 | **中〜高**（DuckDB は `strftime` 推奨。書式文字列の差異あり） |
| `dbt_utils.date_spine` | 3 | 中（`dim_dates` の 2020-2030 生成。dispatch 先の挙動確認が必要） |
| `percentile` | 1 | 中（`percentile_cont` の構文差） |
| `date_trunc` | 1 | 低 |
| `::` キャスト | 多数 | 低 |

加えて要検証:

- **ephemeral マテリアライゼーション** — `intermediate` 層 4 モデルが依存。v2 での CTE インライン化挙動（`--inject-ephemeral-ctes` は非推奨フラグ化）。
- **snapshot** — `snapshots.yml` の `hard_deletes: invalidate`、`dbt_valid_to_current: "cast('9999-12-31' as timestamp)"`、`strategy: timestamp` が v2 + DuckDB で機能するか。第4章の SCD Type 2 の中核なので最優先で検証する。
- **`add_sample_data_changes` マクロ** — 生 SQL の `UPDATE zakka_mall.customer ...` を `run_query` 経由で実行している。DuckDB 用に書き換え（ENUM 値の扱い、`updated_at = NOW()`）。
- **singular test 2 本** — `tests/` 配下が `baseline` 静的解析で警告なく通るか。

**完了条件**: `dbt build` が完走し、snapshot の SCD Type 2 が想定どおり履歴を持つ。

### Phase 5: v1 との結果パリティ検証

「移行しても結果が変わらない」ことを示すのがこの章の説明価値になる。

1. v1 側（PostgreSQL）で `dbt build` を実行して基準を作る。
2. v2 側（DuckDB）で `dbt build`。
3. 主要マート（`dim_customers` / `dim_products` / `fct_orders` / `fct_order_items` / `sales_obt` / `sales_summary` / `customer_analysis` / `product_performance` / `order_processing`）について行数と集計値を比較。
4. 差分が出た場合は、方言差・型差（`numeric` の精度、タイムゾーン）・snapshot の実行タイミングのどれに起因するかを切り分ける。

**完了条件**: 全マートで行数一致、金額系の合計値が一致（または差分の原因を説明済み）。

### Phase 6: v2 の新機能を章の内容として取り込む

移植だけで終わらせず、v2 で新しく使えるものを盛り込む。

- **静的解析（`baseline`）** — ウェアハウスに触れずに SQL エラーを検出。`strict` との違いは説明のみに留める（ログイン必須のため実演しない）。
- **dbt Docs v2** — `dbt docs generate` で Parquet アーティファクト＋静的サイトを一括生成、`dbt docs serve` でプレビュー。
- **`dbt lint` / `dbt format`** — sqlfluff 互換の内蔵リンタ。
- **`dbt freshness`（Beta）** — source だけでなくモデルにも鮮度しきい値を設定できる。
- **dbt Information Schema** — `--generate-info-schema` で `target/info_schema/v1/` にメタデータを出力。
- **LSP / VS Code 拡張** — 補完・インラインエラー・CTE プレビュー（未ログインでも使える範囲）。

対象外（`dbt login` が必要なため）: カラムレベルリネージ、`--static-analysis strict`、LSP のカラム定義ジャンプ・型チェック。

### Phase 7: ドキュメント整備

- `chapter4/dbt_project/README.md`: v2 前提のセットアップ手順（dbt インストール、DuckDB 初期化、ビルド）。アカウント登録は不要である旨と、その代わりに使えない機能を明記。
- `chapter4/README.md`: v1 版と v2 版の位置づけ、章内での読み分けを追記。
- v1 → v2 の差分早見表（コマンド、profiles、依存関係、Docker の有無）。

---

## 3. 成果物のディレクトリ構成（予定）

```
chapter4/
├── README.md                     # v1 / v2 両版への導線を追記
├── duckdb-init/                  # 新規: DuckDB 用初期化 SQL
│   ├── 01_ddl.sql
│   ├── 02_sample_data_master.sql
│   ├── 03_sample_data_products.sql
│   ├── 04_sample_data_orders.sql
│   └── 05_category_path.sql      # PostgreSQL 版のトリガー相当の後処理
├── dbt_project/                  # dbt v2 + DuckDB 版に置き換え
│   ├── README.md
│   ├── dbt_project.yml
│   ├── profiles.yml              # type: duckdb
│   ├── packages.yml
│   ├── .sqlfluff                 # dbt lint がそのまま解釈（dialect = duckdb）
│   ├── models/                   # staging / intermediate / marts（構成は v1 版と同一）
│   ├── macros/
│   ├── snapshots/
│   ├── tests/
│   └── dbt_demo.duckdb           # .gitignore 対象
└── dbt_v2_migration_plan.md      # 本ファイル
```

---

## 4. リスクと未確定事項

| # | 項目 | 影響 | 対応 |
| --- | --- | --- | --- |
| 1 | DuckDB アダプタが **Beta かつ CLI 限定** | 仕様変更・不具合の可能性 | バージョンを README に明記。dbt Platform 前提の記述はしない |
| 2 | snapshot（SCD Type 2）が v2 + DuckDB で期待通り動かない | 第4章の中核が崩れる | Phase 4 で最優先検証。動かない場合は Category D として issue を確認 |
| 3 | ephemeral マテリアライゼーションの挙動差 | intermediate 層 4 モデル | Phase 3 の `dbt compile` 出力を v1 と比較 |
| 4 | `to_char` / `percentile` / `interval` の方言差 | 集計結果のズレ | Phase 5 のパリティ検証で検出 |
| 5 | `dbt_utils.date_spine` の dispatch | `dim_dates` が生成できない | 動かない場合は `generate_series` ベースの自前実装に置換 |
| 6 | データ再現性（DuckDB へのデータ投入結果が PostgreSQL と一致するか） | パリティ検証の前提が崩れる | Phase 1 完了時に 9 テーブルの行数を突き合わせる |
| 7 | v2 のライセンス | 書籍としての案内 | 既定の `dbt` は v2 ライセンス、Apache 2.0 が必要なら `dbt OSS`（`dbt-core` パッケージ）と使い分ける旨を README に記載 |
| 8 | Docker 廃止による章構成の変更 | pgAdmin での確認手順が消える | DuckDB CLI または DuckDB UI での確認手順に差し替え |
| 9 | 未ログイン運用（`dbt login` しない） | `strict` 静的解析・カラムレベルリネージが使えない | 意図的な制約として README に明記。`baseline` でも SQL エラー検出は機能する |

---

## 5. 実施結果（2026-09-16）

Phase 0〜7 を実施し、`chapter4/dbt_project` が dbt 2.0.4 + DuckDB 1.5.5 で完走する状態になった。

| Phase | 状態 | 結果 |
| --- | --- | --- |
| 0 出発点 | 完了 | dbt-autofix の変更は `flags: require_generic_test_arguments_property: true` の追加 1 件のみ。generic test は既に `arguments:` 形式だったため YAML 側の修正は不要 |
| 1 DuckDB 基盤 | 完了 | `duckdb-init/` を作成。9 テーブルすべてのデータ投入と `category_path` の生成を確認。`dbt debug` が All checks passed |
| 2 設定の v2 化 | 完了 | `pyproject.toml` / `.python-version` / `uv.lock` を廃止。sqlfluff → `dbt lint`、`.sqlfluff` の dialect を duckdb に変更 |
| 3 ビルド | 完了 | `dbt deps` / `parse` / `compile` / `build` すべて成功（25 models / 198 tests / 2 snapshots、ephemeral 4 件は no-op） |
| 4 方言差分 | 完了 | 下記の 6 点を修正。想定していた `to_char` / `percentile` / `interval` / `date_spine` はモデル側では修正不要だった |
| 5 パリティ検証 | 完了 | 12 リレーションすべてで行数・金額合計が v1（PostgreSQL）と完全一致 |
| 6 v2 機能 | 完了 | `dbt lint` / `dbt format` / `dbt docs generate` / `dbt freshness` / `--generate-info-schema` の動作を確認 |
| 7 ドキュメント | 完了 | `dbt_project/README.md` を作成、`chapter4/README.md` に導線を追加 |

### 実際に必要だった修正

| # | 事象 | 対応 |
| --- | --- | --- |
| 1 | DuckDB の ENUM 型で dbt v2 のアダプタが panic（`Dictionary(UInt8, Utf8) is not supported for DuckDB`）。snapshot 実行時に発生 | staging 層で 8 つの ENUM 列を `cast(... as varchar)` に正規化 |
| 2 | DuckDB は外部キーで参照されている親行を UPDATE できない（値を変えない列でも Constraint Error） | `duckdb-init/01_ddl.sql` から FOREIGN KEY 制約を削除。`add_sample_data_changes` が customer / product / order を UPDATE するため必須 |
| 3 | `postal_code !~ '正規表現'`（PostgreSQL 演算子）が静的解析で構文エラー | `not regexp_matches(postal_code, ...)` に変更 |
| 4 | DuckDB にトリガーが無く、`updated_at` の自動更新と注文番号の採番が行われない | `add_sample_data_changes` で `updated_at = NOW()` を明示し、注文番号は INSERT 後の UPDATE で採番。`to_char` → `strftime` |
| 5 | `profiles.yml` の `settings: TimeZone: UTC` が dbt 2.0.4 の DuckDB アダプタで**無視される**（`current_setting('TimeZone')` が `Asia/Tokyo` のまま） | `base_dim_customers` / `base_dim_products` で `cast(updated_at at time zone 'UTC' as timestamp)` と明示。これが無いと `dbt_valid_from` が 9 時間ずれる |
| 6 | DuckDB のカタログ名はファイル名から決まるため、`zakka_mall.duckdb` にするとスキーマ名 `zakka_mall` と衝突 | データベースファイルを `dbt_demo.duckdb` に。ソース定義の `database: dbt_demo` もそのまま使える |

### 予想と違った点

- `dbt_utils.date_spine`、ephemeral マテリアライゼーション、snapshot の `hard_deletes` / `dbt_valid_to_current`、`percentile_cont`、`interval`、`extract` はいずれも修正なしで動作した。
- 一方で ENUM と外部キーという、方言差ではなく **アダプタ / DuckDB 自体の制約** が主な障害だった。

### 残っている課題

- `dbt lint` が 12 errors / 9 warnings を報告する（`ST01` 不要な ELSE NULL、`RF04` 予約語の識別子利用、`ST06` ワイルドカードの位置）。これは v1 版から引き継いだ既存のスタイル問題で、移行に起因するものではない。`dbt lint --fix` で直すか、`.sqlfluff` の `exclude_rules` に加えるかは未決。
- DDL から外部キー制約と各種インデックスが消えたため、OLTP モデリングの説明としては v1 版より情報が減っている。書籍側でどう補足するかは未決。
- DuckDB アダプタは Beta。バージョンを上げたときに #1 / #5 の挙動が変わる可能性がある。
