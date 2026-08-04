"""ハンズオン用 raw データ生成モジュール。

jafgen で生成された CSV (`raw_customers.csv`, `raw_orders.csv`, `raw_items.csv`,
`raw_products.csv`) を入力とし、Athena テーブル用の CSV バイト列を返す。
`loaded_at` カラムを付与し、`raw_orders.ordered_at` は「今日 UTC - 2019-09-01」の
日数分だけ前方にシフトする。

DAG からは公開関数 :func:`build_raw_csvs` を呼び出して、4 テーブル分の CSV バイト列を
取得する想定。chapter3 の ``utils/load_raw_data.py`` とロジックを揃えている。
"""
from __future__ import annotations

import csv
import io
from datetime import date, datetime, timezone
from pathlib import Path

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


def build_raw_csvs(
    seed_dir: Path, loaded_at_ms: int, today_utc: date,
) -> dict[str, bytes]:
    """jafgen 出力ディレクトリから 4 テーブル分の CSV バイト列を構築する。

    :param seed_dir: jafgen が生成した CSV が格納されたディレクトリ。
    :param loaded_at_ms: 全テーブルに付与する loaded_at（unix ミリ秒）。
    :param today_utc: raw_orders.ordered_at のシフト基準となる今日の UTC 日付。
    :returns: テーブル名をキーとした CSV バイト列の dict。
    """
    return {
        'raw_customers': _load_raw_customers_csv(
            seed_dir / 'raw_customers.csv', loaded_at_ms,
        ),
        'raw_orders': _load_raw_orders_csv(
            seed_dir / 'raw_orders.csv', loaded_at_ms, today_utc,
        ),
        'raw_items': _load_raw_items_csv(
            seed_dir / 'raw_items.csv', loaded_at_ms,
        ),
        'raw_products': _load_raw_products_csv(
            seed_dir / 'raw_products.csv', loaded_at_ms,
        ),
    }
