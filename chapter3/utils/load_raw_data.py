from __future__ import annotations

import csv
import io
import os
import sys
import time
from datetime import date, datetime, timezone
from pathlib import Path

import boto3

REPO_ROOT = Path(__file__).resolve().parent.parent
JAFFLE_DATA_DIR = REPO_ROOT / 'jaffle-data'

DATABASE = 'jaffle_shop_ch3_raw'

CREATE_TABLE_TEMPLATE = """
CREATE EXTERNAL TABLE IF NOT EXISTS {table} (
{columns}
)
ROW FORMAT SERDE 'org.apache.hadoop.hive.serde2.OpenCSVSerde'
WITH SERDEPROPERTIES (
  'separatorChar' = ',',
  'quoteChar' = '"',
  'escapeChar' = '\\\\'
)
LOCATION 's3://{bucket}/{database}/{table}/'
TBLPROPERTIES ('skip.header.line.count' = '1')
"""

TABLE_SCHEMAS: dict[str, list[tuple[str, str]]] = {
    'raw_customers': [
        ('id', 'string'),
        ('name', 'string'),
        ('loaded_at', 'timestamp'),
    ],
    'raw_orders': [
        ('id', 'string'),
        ('customer', 'string'),
        ('ordered_at', 'timestamp'),
        ('store_id', 'string'),
        ('subtotal', 'bigint'),
        ('tax_paid', 'bigint'),
        ('order_total', 'bigint'),
        ('loaded_at', 'timestamp'),
    ],
    'raw_items': [
        ('id', 'string'),
        ('order_id', 'string'),
        ('sku', 'string'),
        ('loaded_at', 'timestamp'),
    ],
    'raw_products': [
        ('sku', 'string'),
        ('name', 'string'),
        ('type', 'string'),
        ('price', 'bigint'),
        ('description', 'string'),
        ('loaded_at', 'timestamp'),
    ],
}


def _require_env(key: str) -> str:
    value = os.environ.get(key)
    if not value:
        print(
            f'error: environment variable {key} is required',
            file=sys.stderr,
        )
        sys.exit(1)
    return value


def _iso_to_unix_ms(iso: str) -> int:
    dt = datetime.fromisoformat(iso)
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return int(dt.timestamp() * 1000)


def _load_raw_customers_csv(src: Path, loaded_at_ms: int) -> bytes:
    buf = io.StringIO()
    writer = csv.writer(buf)
    writer.writerow(['id', 'name', 'loaded_at'])
    with src.open('r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        for row in reader:
            writer.writerow([row['id'], row['name'], loaded_at_ms])
    return buf.getvalue().encode('utf-8')


def _load_raw_products_csv(src: Path, loaded_at_ms: int) -> bytes:
    buf = io.StringIO()
    writer = csv.writer(buf)
    writer.writerow(['sku', 'name', 'type', 'price', 'description', 'loaded_at'])
    with src.open('r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        for row in reader:
            writer.writerow([
                row['sku'],
                row['name'],
                row['type'],
                row['price'],
                row['description'],
                loaded_at_ms,
            ])
    return buf.getvalue().encode('utf-8')


def _load_raw_items_csv(src: Path, loaded_at_ms: int) -> bytes:
    buf = io.StringIO()
    writer = csv.writer(buf)
    writer.writerow(['id', 'order_id', 'sku', 'loaded_at'])
    with src.open('r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        for row in reader:
            writer.writerow([
                row['id'],
                row['order_id'],
                row['sku'],
                loaded_at_ms,
            ])
    return buf.getvalue().encode('utf-8')


def _load_raw_orders_csv(
    src: Path, loaded_at_ms: int, today_utc: date,
) -> bytes:
    """ordered_at に (today_utc 00:00 UTC - 2019-09-01 00:00 UTC) の日数を加算して loaded_at を付与する。"""
    shift_ms = (today_utc - date(2019, 9, 1)).days * 86400 * 1000

    buf = io.StringIO()
    writer = csv.writer(buf)
    writer.writerow([
        'id', 'customer', 'ordered_at', 'store_id',
        'subtotal', 'tax_paid', 'order_total', 'loaded_at',
    ])
    with src.open('r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        for row in reader:
            shifted_ms = _iso_to_unix_ms(row['ordered_at']) + shift_ms
            writer.writerow([
                row['id'], row['customer'], shifted_ms, row['store_id'],
                row['subtotal'], row['tax_paid'], row['order_total'],
                loaded_at_ms,
            ])
    return buf.getvalue().encode('utf-8')


def _run_athena_query(
    athena, query: str, database: str, workgroup: str,
) -> None:
    """Athena クエリを発行し SUCCEEDED になるまで 1 秒間隔でポーリングする。"""
    resp = athena.start_query_execution(
        QueryString=query,
        QueryExecutionContext={'Database': database},
        WorkGroup=workgroup,
    )
    qid = resp['QueryExecutionId']
    while True:
        state = athena.get_query_execution(
            QueryExecutionId=qid,
        )['QueryExecution']['Status']['State']
        if state == 'SUCCEEDED':
            return
        if state in ('FAILED', 'CANCELLED'):
            raise RuntimeError(f'Athena query {state}: {qid}')
        time.sleep(1)


def main() -> None:
    bucket = _require_env('S3_BUCKET_ATHENA')
    workgroup = 'dbt-book-ch3-athena-workgroup'

    loaded_at_ms = int(time.time() * 1000)
    today_utc = datetime.now(timezone.utc).date()

    athena = boto3.client('athena')
    s3 = boto3.client('s3')

    _run_athena_query(
        athena, f'CREATE DATABASE IF NOT EXISTS {DATABASE}', 'default', workgroup,
    )

    for table, schema in TABLE_SCHEMAS.items():
        columns = ',\n'.join(f'  {name} {dtype}' for name, dtype in schema)
        ddl = CREATE_TABLE_TEMPLATE.format(
            table=table, columns=columns, bucket=bucket, database=DATABASE,
        )
        _run_athena_query(athena, ddl, DATABASE, workgroup)

    loaders = {
        'raw_customers': lambda: _load_raw_customers_csv(
            JAFFLE_DATA_DIR / 'raw_customers.csv', loaded_at_ms,
        ),
        'raw_orders': lambda: _load_raw_orders_csv(
            JAFFLE_DATA_DIR / 'raw_orders.csv', loaded_at_ms, today_utc,
        ),
        'raw_items': lambda: _load_raw_items_csv(
            JAFFLE_DATA_DIR / 'raw_items.csv', loaded_at_ms,
        ),
        'raw_products': lambda: _load_raw_products_csv(
            JAFFLE_DATA_DIR / 'raw_products.csv', loaded_at_ms,
        ),
    }
    for table, loader in loaders.items():
        s3.put_object(
            Bucket=bucket,
            Key=f'{DATABASE}/{table}/{table}.csv',
            Body=loader(),
        )


if __name__ == '__main__':
    main()
