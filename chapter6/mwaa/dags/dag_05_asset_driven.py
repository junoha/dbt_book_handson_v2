"""発展例: Asset を用いた複数 DAG の連携

1 ファイルに以下 3 つの DAG を定義する:
- dag_05_ingest_transactions: トランザクション系ソース (raw_orders, raw_items) を S3 にアップロードし、各テーブルに対応する Asset を更新
- dag_05_ingest_master: マスタ系ソース (raw_customers, raw_products) を S3 にアップロードし、各テーブルに対応する Asset を更新
- dag_05_run_dbt: 4 つの Asset すべての更新を待って dbt を実行 (AND 条件)

dag_04_typical_workflow が単一 DAG で全ソースを逐次処理するのに対し、
本構成ではソースごとの更新頻度差と疎結合を Asset によって表現する。

前提: dag_01_generate_raw_data の DDL タスクを事前に成功させ、
Athena のデータベース・テーブルを作成しておく必要がある。
"""
import os
from datetime import timedelta
from pathlib import Path

import boto3
from airflow.sdk import Asset, dag, get_current_context, task

from raw_data_generator import build_raw_csvs

DATABASE = 'jaffle_shop_ch6_raw'
BUCKET = os.environ.get('AIRFLOW__CUSTOM__S3_BUCKET_ATHENA', '')

RUNBOOK_URL = 'https://wiki.example.com/runbooks/dag_05_asset_driven'

# Asset 定義: 各ソーステーブルの S3 location に対応。
# タスクが成功したときにイベントが発火し、購読している DAG が起動される。
raw_orders_asset = Asset(f's3://{BUCKET}/{DATABASE}/raw_orders/')
raw_items_asset = Asset(f's3://{BUCKET}/{DATABASE}/raw_items/')
raw_customers_asset = Asset(f's3://{BUCKET}/{DATABASE}/raw_customers/')
raw_products_asset = Asset(f's3://{BUCKET}/{DATABASE}/raw_products/')


def on_failure(context):
    """タスク失敗時の通知。本来はここで Slack 等へ通知する処理を実装する。"""
    ti = context['task_instance']
    print(f'[ALERT] Task failed: dag_id={ti.dag_id}, task_id={ti.task_id}, '
          f'run_id={context["run_id"]}, runbook={RUNBOOK_URL}')


def dbt_bash_command(dbt_command: str) -> str:
    return f"""
    set -e;
    source $DBT_VENV_PATH/bin/activate;
    cp -R $AIRFLOW_HOME/dags/dbt_project/. $PWD;
    {dbt_command}
    """


env = {'DBT_TARGET': 'prod', 'DBT_USE_COLORS': 'False'}
bash_args = {'env': env, 'append_env': True}

common_default_args = {
    'on_failure_callback': on_failure,
    'execution_timeout': timedelta(minutes=10),
    'retries': 1,
}


def _upload_tables(table_names: list[str]) -> None:
    """指定されたテーブルのデータを生成し S3 にアップロードする共通処理。"""
    context = get_current_context()
    run_time = context['data_interval_end']
    loaded_at_ms = int(run_time.timestamp() * 1000)
    today_utc = run_time.date()
    seed_dir = Path(os.environ['AIRFLOW_HOME']) / 'dags' / 'jafgen_data'
    csvs = build_raw_csvs(seed_dir, loaded_at_ms, today_utc)
    s3 = boto3.client('s3')
    for name in table_names:
        key = f'{DATABASE}/{name}/{name}.csv'
        s3.put_object(Bucket=BUCKET, Key=key, Body=csvs[name])
        print(f's3://{BUCKET}/{key}')


# トランザクション系ソース (raw_orders, raw_items): 更新頻度が高く、毎時実行を想定
@dag(schedule='0 * * * *', default_args=common_default_args)
def dag_05_ingest_transactions():

    @task(outlets=[raw_orders_asset, raw_items_asset])
    def upload_transactions():
        _upload_tables(['raw_orders', 'raw_items'])

    upload_transactions()


dag_05_ingest_transactions()


# マスタ系ソース (raw_customers, raw_products): 更新頻度が低く、日次実行を想定
@dag(schedule='0 3 * * *', default_args=common_default_args)
def dag_05_ingest_master():

    @task(outlets=[raw_customers_asset, raw_products_asset])
    def upload_master():
        _upload_tables(['raw_customers', 'raw_products'])

    upload_master()


dag_05_ingest_master()


# dbt を実行する DAG: 4 つの Asset すべての更新を待って起動する (AND 条件)。
# トランザクション系が毎時、マスタ系が日次で更新されるため、実質的には日次で起動される。
@dag(
    schedule=[
        raw_orders_asset, raw_items_asset,
        raw_customers_asset, raw_products_asset,
    ],
    default_args=common_default_args,
)
def dag_05_run_dbt():

    @task.bash(**bash_args)
    def dbt_source_freshness():
        return dbt_bash_command('dbt source freshness')

    @task.bash(**bash_args)
    def dbt_build():
        return dbt_bash_command('dbt build --exclude-resource-type unit_test')

    dbt_source_freshness() >> dbt_build()


dag_05_run_dbt()
