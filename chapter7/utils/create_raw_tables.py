"""raw_customers, raw_orders の Hive 形式テーブルを Glue Data Catalog に作成する。

Usage:
    uv run python utils/create_raw_tables.py
"""

from _common import print_step, require_env, run_ddl


def main() -> None:
    env = require_env("CH7_S3_BUCKET_NAME", "ATHENA_WORKGROUP")
    bucket = env["CH7_S3_BUCKET_NAME"]
    wg = env["ATHENA_WORKGROUP"]

    print_step("既存テーブルを削除")
    run_ddl("DROP TABLE IF EXISTS jaffle_shop_iceberg.raw_customers", wg)
    run_ddl("DROP TABLE IF EXISTS jaffle_shop_iceberg.raw_orders", wg)

    print_step("raw_customers テーブルを作成")
    run_ddl(f"""
        CREATE EXTERNAL TABLE jaffle_shop_iceberg.raw_customers (
            id STRING,
            name STRING
        )
        ROW FORMAT SERDE 'org.apache.hadoop.hive.serde2.OpenCSVSerde'
        WITH SERDEPROPERTIES ('separatorChar' = ',', 'quoteChar' = '"', 'escapeChar' = '\\\\')
        STORED AS TEXTFILE
        LOCATION 's3://{bucket}/raw-data/raw_customers/'
        TBLPROPERTIES ('skip.header.line.count'='1')
    """, wg)
    print("  -> created raw_customers")

    print_step("raw_orders テーブルを作成")
    run_ddl(f"""
        CREATE EXTERNAL TABLE jaffle_shop_iceberg.raw_orders (
            id STRING,
            customer STRING,
            ordered_at STRING,
            store_id STRING,
            subtotal STRING,
            tax_paid STRING,
            order_total STRING
        )
        ROW FORMAT SERDE 'org.apache.hadoop.hive.serde2.OpenCSVSerde'
        WITH SERDEPROPERTIES ('separatorChar' = ',', 'quoteChar' = '"', 'escapeChar' = '\\\\')
        STORED AS TEXTFILE
        LOCATION 's3://{bucket}/raw-data/raw_orders/'
        TBLPROPERTIES ('skip.header.line.count'='1')
    """, wg)
    print("  -> created raw_orders")

    print("\nDone!")


if __name__ == "__main__":
    main()
