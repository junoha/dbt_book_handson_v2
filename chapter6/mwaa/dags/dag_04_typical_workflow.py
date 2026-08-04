import os
from datetime import timedelta
from pathlib import Path

import boto3
from airflow.sdk import dag, get_current_context, task

from raw_data_generator import build_raw_csvs

DATABASE = 'jaffle_shop_ch6_raw'
BUCKET = os.environ.get('AIRFLOW__CUSTOM__S3_BUCKET_ATHENA', '')

RUNBOOK_URL = 'https://wiki.example.com/runbooks/dag_04_typical_workflow'


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


@dag(
    schedule='0 * * * *',
    default_args={
        'on_failure_callback': on_failure,
        'execution_timeout': timedelta(minutes=10),
        'retries': 1,
    },
)
def dag_04_typical_workflow():

    @task
    def ingest_raw_data():
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

    @task.bash(**bash_args)
    def dbt_source_freshness():
        return dbt_bash_command('dbt source freshness')

    @task.bash(**bash_args)
    def dbt_build():
        return dbt_bash_command('dbt build --exclude-resource-type unit_test')

    ingest_raw_data() >> dbt_source_freshness() >> dbt_build()

dag_04_typical_workflow()
