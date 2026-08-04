"""第 2 章ハンズオン用 raw データロードスクリプト。

処理の流れ:
    1. Jaffle Shop の raw CSV を jaffle-data/ にダウンロード (既に存在する場合はスキップ)
    2. CloudFormation スタック `dbt-book-ch2` の Outputs から S3 バケット名・
        IAM ロール ARN・Workgroup 名を取得
    3. jaffle-data/ 配下の CSV を s3://<バケット>/raw/ にアップロード
    4. Redshift Data API で CREATE SCHEMA / DROP TABLE / CREATE TABLE / COPY を
        一括発行し、raw_customers / raw_orders / raw_items テーブルを作成
    5. ステートメントの完了を待機

前提:
    - CloudFormation スタック (redshift-serverless.yaml) がデプロイ済みであること
    - 環境変数 AWS_PROFILE が dbt-book など適切なプロファイルを指していること
        (デフォルトプロファイルを使う場合は AWS_PROFILE 未設定で OK)

実行方法 (chapter2-completed ディレクトリ直下から)::

    uv run python utils/load_raw_data.py
"""

from __future__ import annotations

import sys
import time
import urllib.request
from pathlib import Path

# このスクリプトを直接実行した場合でも `_common` を import できるよう、
# utils/ ディレクトリを sys.path に追加する。
_UTILS_DIR = Path(__file__).resolve().parent
if str(_UTILS_DIR) not in sys.path:
    sys.path.insert(0, str(_UTILS_DIR))

from _common import (  # noqa: E402
    ensure_default_region,
    get_stack_outputs,
    green,
    make_client,
    print_step,
    red,
)

# ---------------------------------------------------------------------------
# 定数
# ---------------------------------------------------------------------------

STACK_NAME = "dbt-book-ch2"
SCHEMA_NAME = "jaffle_shop_ch2_raw"

CH2_DIR = _UTILS_DIR.parent
DATA_DIR = CH2_DIR / "jaffle-data"

JAFFLE_BASE_URL = "https://raw.githubusercontent.com/dbt-labs/jaffle-shop/main/seeds/jaffle-data"
CSV_FILES = ("raw_customers.csv", "raw_orders.csv", "raw_items.csv")

# CREATE TABLE 定義 (COPY で読み込む raw テーブルのスキーマ)。
TABLE_DDLS: dict[str, str] = {
    "raw_customers": (
        "CREATE TABLE {schema}.raw_customers ("
        "  id   VARCHAR(36),"
        "  name VARCHAR(200)"
        ")"
    ),
    "raw_orders": (
        "CREATE TABLE {schema}.raw_orders ("
        "  id          VARCHAR(36),"
        "  customer    VARCHAR(36),"
        "  ordered_at  TIMESTAMP,"
        "  store_id    VARCHAR(36),"
        "  subtotal    INTEGER,"
        "  tax_paid    INTEGER,"
        "  order_total INTEGER"
        ")"
    ),
    "raw_items": (
        "CREATE TABLE {schema}.raw_items ("
        "  id       VARCHAR(36),"
        "  order_id VARCHAR(36),"
        "  sku      VARCHAR(20)"
        ")"
    ),
}

# COPY コマンドテンプレート。TIMEFORMAT は raw_orders のみで必要。
COPY_TEMPLATE = (
    "COPY {schema}.{table} "
    "FROM 's3://{bucket}/raw/{table}.csv' "
    "IAM_ROLE '{role_arn}' "
    "FORMAT AS CSV "
    "IGNOREHEADER 1"
)
COPY_TEMPLATE_ORDERS = COPY_TEMPLATE + " TIMEFORMAT 'auto'"


# ---------------------------------------------------------------------------
# 個別ステップ
# ---------------------------------------------------------------------------


def download_csv_files() -> None:
    """Jaffle Shop の raw CSV を jaffle-data/ にダウンロードする。既存はスキップ。"""
    print_step("Jaffle Shop の CSV を準備")
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    for fname in CSV_FILES:
        dest = DATA_DIR / fname
        if dest.exists():
            print(f"  {fname} 既存 (スキップ)")
            continue
        url = f"{JAFFLE_BASE_URL}/{fname}"
        print(f"  {fname} を取得中: {url}")
        with urllib.request.urlopen(url) as resp, dest.open("wb") as f:
            f.write(resp.read())


def upload_csv_files(s3, bucket: str) -> None:
    """jaffle-data/*.csv を s3://<bucket>/raw/ にアップロードする。"""
    print_step(f"CSV を s3://{bucket}/raw/ にアップロード")
    for fname in CSV_FILES:
        src = DATA_DIR / fname
        key = f"raw/{fname}"
        print(f"  {fname} -> s3://{bucket}/{key}")
        s3.upload_file(str(src), bucket, key)


def _run_redshift_statement(
    redshift_data,
    workgroup: str,
    database: str,
    sql: str,
    poll_interval: float = 3.0,
) -> None:
    """Redshift Data API で SQL を実行し、FINISHED になるまでポーリングする。"""
    resp = redshift_data.execute_statement(
        WorkgroupName=workgroup,
        Database=database,
        Sql=sql,
    )
    statement_id = resp["Id"]
    print(f"  StatementId: {statement_id}")

    while True:
        desc = redshift_data.describe_statement(Id=statement_id)
        status = desc["Status"]
        if status == "FINISHED":
            return
        if status in ("FAILED", "ABORTED"):
            error = desc.get("Error", "") or ""
            print(red(f"  Redshift Data API がエラーで終了しました: {status}"))
            if error:
                print(red(f"    {error}"))
            raise SystemExit(1)
        # PICKED / STARTED / SUBMITTED などは進行中
        time.sleep(poll_interval)


def load_raw_tables(
    redshift_data,
    workgroup: str,
    database: str,
    bucket: str,
    role_arn: str,
) -> None:
    """CREATE SCHEMA / DROP TABLE / CREATE TABLE / COPY をまとめて実行する。

    Redshift Data API は 1 リクエストあたり単一の SQL 文しか受け付けないため、
    テーブルごとに 3 ステートメント (DROP + CREATE + COPY) を順に発行する。
    """
    print_step("Redshift Data API で CREATE + COPY を発行")

    # スキーマ作成 (存在すればスキップ)
    _run_redshift_statement(
        redshift_data,
        workgroup,
        database,
        f"CREATE SCHEMA IF NOT EXISTS {SCHEMA_NAME}",
    )
    print(green(f"  スキーマ {SCHEMA_NAME} を準備しました"))

    # 各テーブルの再作成 + COPY
    for table, ddl_template in TABLE_DDLS.items():
        print(f"  テーブル {table} を再作成中...")
        # DROP TABLE IF EXISTS
        _run_redshift_statement(
            redshift_data,
            workgroup,
            database,
            f"DROP TABLE IF EXISTS {SCHEMA_NAME}.{table}",
        )
        # CREATE TABLE
        _run_redshift_statement(
            redshift_data,
            workgroup,
            database,
            ddl_template.format(schema=SCHEMA_NAME),
        )
        # COPY
        copy_template = COPY_TEMPLATE_ORDERS if table == "raw_orders" else COPY_TEMPLATE
        copy_sql = copy_template.format(
            schema=SCHEMA_NAME,
            table=table,
            bucket=bucket,
            role_arn=role_arn,
        )
        _run_redshift_statement(redshift_data, workgroup, database, copy_sql)
        print(green(f"  {SCHEMA_NAME}.{table} をロードしました"))


# ---------------------------------------------------------------------------
# エントリポイント
# ---------------------------------------------------------------------------


def main() -> int:
    region = ensure_default_region()

    cfn = make_client("cloudformation")
    s3 = make_client("s3")
    redshift_data = make_client("redshift-data")

    print("=" * 52)
    print("第 2 章 raw データロード")
    print(f"  スタック: {STACK_NAME}")
    print(f"  リージョン: {region}")
    print(f"  スキーマ: {SCHEMA_NAME}")
    print("=" * 52)

    print_step("CloudFormation スタックの Outputs を取得")
    outputs = get_stack_outputs(cfn, STACK_NAME)
    bucket = outputs["LandingBucketName"]
    role_arn = outputs["RedshiftS3RoleArn"]
    workgroup = outputs["RedshiftWorkgroupName"]
    database = outputs["RedshiftDatabaseName"]
    print(f"  S3 バケット: {bucket}")
    print(f"  Redshift S3 ロール: {role_arn}")
    print(f"  Workgroup: {workgroup}")
    print(f"  データベース: {database}")

    download_csv_files()
    upload_csv_files(s3, bucket)
    load_raw_tables(redshift_data, workgroup, database, bucket, role_arn)

    print()
    print("=" * 52)
    print(green("raw データのロードが完了しました。"))
    print(f"  {SCHEMA_NAME}.raw_customers")
    print(f"  {SCHEMA_NAME}.raw_orders")
    print(f"  {SCHEMA_NAME}.raw_items")
    print("=" * 52)
    return 0


if __name__ == "__main__":
    sys.exit(main())
