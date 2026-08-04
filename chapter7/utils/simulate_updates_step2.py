"""Step 2: ソースデータに gdpr_deleted 列を追加し、新規注文を追加する。
dbtモデルファイルも Step 2 版に更新する。

Usage:
    uv run python utils/simulate_updates_step2.py
"""

import csv
import random
import uuid
from datetime import datetime, timedelta
from pathlib import Path

from _common import (
    HANDSON_DIR,
    MODELS_MARTS,
    MODELS_STAGING,
    STEPS_DIR,
    copy_model_files,
    print_step,
    require_env,
    run_ddl,
    s3_upload_file,
)


def main() -> None:
    env = require_env("CH7_S3_BUCKET_NAME", "ATHENA_WORKGROUP")
    bucket = env["CH7_S3_BUCKET_NAME"]
    wg = env["ATHENA_WORKGROUP"]

    jaffle_dir = HANDSON_DIR / "jaffle-data"
    if not jaffle_dir.is_dir():
        raise SystemExit("Error: jaffle-data directory not found.")

    # --- raw_customers に gdpr_deleted 列を追加 ---
    print_step("raw_customers.csv に gdpr_deleted 列を追加")
    random.seed(42)
    customers_csv = jaffle_dir / "raw_customers.csv"
    rows = []
    with open(customers_csv, newline="") as f:
        reader = csv.reader(f)
        header = next(reader)
        if "gdpr_deleted" not in header:
            header = header + ["gdpr_deleted"]
        for row in reader:
            flag = "true" if random.random() < 0.01 else "false"
            rows.append(row[:2] + [flag])

    with open(customers_csv, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(header)
        writer.writerows(rows)

    deleted = sum(1 for r in rows if r[-1] == "true")
    print(f"  gdpr_deleted=true にした顧客: {deleted}件 / 全{len(rows)}件")

    # --- raw_orders に新規注文を20件追加 ---
    print_step("raw_orders.csv に新規注文を20件追加")
    random.seed(42)
    orders_csv = jaffle_dir / "raw_orders.csv"

    with open(orders_csv, newline="") as f:
        reader = csv.reader(f)
        header = next(reader)
        last_ordered_at = None
        customers_set: set[str] = set()
        stores_set: set[str] = set()
        for row in reader:
            ts = row[2]
            if last_ordered_at is None or ts > last_ordered_at:
                last_ordered_at = ts
            customers_set.add(row[1])
            stores_set.add(row[3])

    print(f"  既存の最新注文: {last_ordered_at}")
    base = datetime.fromisoformat(last_ordered_at) + timedelta(hours=1)
    customers_list = list(customers_set)
    stores_list = list(stores_set)

    new_rows = []
    for i in range(20):
        ordered_at = (base + timedelta(hours=i)).isoformat(timespec="seconds")
        subtotal = random.randint(500, 2000)
        tax = int(subtotal * 0.06)
        total = subtotal + tax
        new_rows.append([
            str(uuid.uuid4()),
            random.choice(customers_list),
            ordered_at,
            random.choice(stores_list),
            subtotal, tax, total,
        ])

    with open(orders_csv, "a", newline="") as f:
        writer = csv.writer(f)
        for row in new_rows:
            writer.writerow(row)

    print(f"  新規注文を追加: {len(new_rows)}件")

    # --- S3 にアップロード ---
    print_step("S3 にアップロード")
    s3_upload_file(customers_csv, bucket, "raw-data/raw_customers/raw_customers.csv")
    s3_upload_file(orders_csv, bucket, "raw-data/raw_orders/raw_orders.csv")
    print("  -> Done")

    # --- raw_customers のテーブル定義を再作成 ---
    print_step("raw_customers テーブルを gdpr_deleted 列込みで再作成")
    run_ddl("DROP TABLE IF EXISTS jaffle_shop_iceberg.raw_customers", wg)
    run_ddl(f"""
        CREATE EXTERNAL TABLE jaffle_shop_iceberg.raw_customers (
            id STRING,
            name STRING,
            gdpr_deleted BOOLEAN
        )
        ROW FORMAT SERDE 'org.apache.hadoop.hive.serde2.OpenCSVSerde'
        WITH SERDEPROPERTIES ('separatorChar' = ',', 'quoteChar' = '"', 'escapeChar' = '\\\\')
        STORED AS TEXTFILE
        LOCATION 's3://{bucket}/raw-data/raw_customers/'
        TBLPROPERTIES ('skip.header.line.count'='1')
    """, wg)
    print("  -> raw_customers 再作成完了")

    # --- dbt モデルファイルを Step 2 版に更新 ---
    print_step("dbt モデルファイルを Step 2 版に更新")
    copy_model_files(
        STEPS_DIR / "step2",
        {
            "stg_customers.sql": MODELS_STAGING / "stg_customers.sql",
            "customer_orders.sql": MODELS_MARTS / "customer_orders.sql",
        },
    )

    print("\nDone!")


if __name__ == "__main__":
    main()
