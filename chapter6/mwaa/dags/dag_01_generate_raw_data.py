import os
from pathlib import Path

import boto3
from airflow.providers.amazon.aws.operators.athena import AthenaOperator
from airflow.sdk import dag, get_current_context, task

from raw_data_generator import CREATE_TABLE_TEMPLATE, TABLE_SCHEMAS, build_raw_csvs

DATABASE = 'jaffle_shop_ch6_raw'
BUCKET = os.environ.get('AIRFLOW__CUSTOM__S3_BUCKET_ATHENA', '')
WORKGROUP = os.environ.get('AIRFLOW__CUSTOM__ATHENA_WORK_GROUP', '')

CREATE_DATABASE_QUERY = f'CREATE DATABASE IF NOT EXISTS {DATABASE}'


def _create_table_ddl(table: str) -> str:
    """TABLE_SCHEMAS から Athena の CREATE EXTERNAL TABLE 文を生成する。"""
    columns = ',\n'.join(f'  {name} {dtype}' for name, dtype in TABLE_SCHEMAS[table])
    return CREATE_TABLE_TEMPLATE.format(
        table=table, columns=columns, bucket=BUCKET, database=DATABASE,
    )


ATHENA_ARGS = {
    'database': DATABASE,
    'workgroup': WORKGROUP,
    'sleep_time': 1,
}


@dag()
def dag_01_generate_raw_data():
    create_database = AthenaOperator(
        task_id='create_database',
        query=CREATE_DATABASE_QUERY,
        database='default',
        workgroup=WORKGROUP,
        sleep_time=1,
    )

    create_table_customers = AthenaOperator(
        task_id='create_table_customers',
        query=_create_table_ddl('raw_customers'),
        **ATHENA_ARGS,
    )

    create_table_orders = AthenaOperator(
        task_id='create_table_orders',
        query=_create_table_ddl('raw_orders'),
        **ATHENA_ARGS,
    )

    create_table_items = AthenaOperator(
        task_id='create_table_items',
        query=_create_table_ddl('raw_items'),
        **ATHENA_ARGS,
    )

    create_table_products = AthenaOperator(
        task_id='create_table_products',
        query=_create_table_ddl('raw_products'),
        **ATHENA_ARGS,
    )

    @task
    def upload_raw_data():
        context = get_current_context()
        run_time = context['data_interval_end']
        loaded_at_ms = int(run_time.timestamp() * 1000)
        today_utc = run_time.date()
        seed_dir = Path(os.environ['AIRFLOW_HOME']) / 'dags' / 'jafgen_data'
        csvs = build_raw_csvs(seed_dir, loaded_at_ms, today_utc)
        s3 = boto3.client('s3')
        for name, body in csvs.items():
            key = f'{DATABASE}/{name}/{name}.csv'
            s3.put_object(Bucket=BUCKET, Key=key, Body=body)
            print(f's3://{BUCKET}/{key}')

    create_database >> [
        create_table_customers,
        create_table_orders,
        create_table_items,
        create_table_products,
    ] >> upload_raw_data()

dag_01_generate_raw_data()
