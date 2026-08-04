"""Step 3: raw_orders に coupon_discount 列を追加し、新規注文を追加する。
dbtモデルファイルも Step 3 版に更新する。

Usage:
    uv run python utils/simulate_updates_step3.py
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

    orders_csv = jaffle_dir / "raw_orders.csv"

    # --- raw_orders に coupon_discount 列を追加 ---
    print_step("raw_orders.csv に coupon_discount 列を追加")
    random.seed(123)

    rows = []
    with open(orders_csv, newline="") as f:
        reader = csv.reader(f)
        header = next(reader)
        if "coupon_discount" not in header:
            header = header + ["coupon_discount"]
        for row in reader:
            if len(row) < 8:
                row = row + [""]
            rows.append(row)

    # 新規注文を20件追加（coupon_discount 付き）
    last_ordered_at = max(r[2] for r in rows)
    base = datetime.fromisoformat(last_ordered_at) + timedelta(hours=1)
    customers_list = list({r[1] for r in rows})
    stores_list = list({r[3] for r in rows})

    new_rows = []
    for i in range(20):
        ordered_at = (base + timedelta(hours=i)).isoformat(timespec="seconds")
        subtotal = random.randint(500, 2000)
        tax = int(subtotal * 0.06)
        total = subtotal + tax
        discount = random.randint(subtotal // 10, subtotal // 3)
        new_rows.append([
            str(uuid.uuid4()),
            random.choice(customers_list),
            ordered_at,
            random.choice(stores_list),
            str(subtotal), str(tax), str(total),
            str(discount),
        ])
    rows.extend(new_rows)

    with open(orders_csv, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(header)
        writer.writerows(rows)

    print(f"  既存行: coupon_discount 列を空欄で追加")
    print(f"  新規行 (coupon_discount 付き): {len(new_rows)}件")

    # --- S3 にアップロード ---
    print_step("S3 にアップロード")
    s3_upload_file(orders_csv, bucket, "raw-data/raw_orders/raw_orders.csv")
    print("  -> Done")

    # --- raw_orders テーブル定義を再作成 ---
    print_step("raw_orders テーブルを coupon_discount 列込みで再作成")
    run_ddl("DROP TABLE IF EXISTS jaffle_shop_iceberg.raw_orders", wg)
    run_ddl(f"""
        CREATE EXTERNAL TABLE jaffle_shop_iceberg.raw_orders (
            id STRING,
            customer STRING,
            ordered_at STRING,
            store_id STRING,
            subtotal STRING,
            tax_paid STRING,
            order_total STRING,
            coupon_discount STRING
        )
        ROW FORMAT SERDE 'org.apache.hadoop.hive.serde2.OpenCSVSerde'
        WITH SERDEPROPERTIES ('separatorChar' = ',', 'quoteChar' = '"', 'escapeChar' = '\\\\')
        STORED AS TEXTFILE
        LOCATION 's3://{bucket}/raw-data/raw_orders/'
        TBLPROPERTIES ('skip.header.line.count'='1')
    """, wg)
    print("  -> raw_orders 再作成完了")

    # --- dbt モデルファイルを Step 3 版に更新 ---
    print_step("dbt モデルファイルを Step 3 版に更新")
    copy_model_files(
        STEPS_DIR / "step3",
        {
            "stg_orders.sql": MODELS_STAGING / "stg_orders.sql",
            "orders.sql": MODELS_MARTS / "orders.sql",
        },
    )

    print("\nDone!")


if __name__ == "__main__":
    main()
