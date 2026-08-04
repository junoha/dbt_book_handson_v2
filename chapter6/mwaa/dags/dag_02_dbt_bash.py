from airflow.sdk import dag, task

def dbt_bash_command(dbt_command: str) -> str:
    """dbt プロジェクトのコピーなど共通の処理を含む bash コマンドを生成"""
    return f"""
    set -e;
    source $DBT_VENV_PATH/bin/activate;
    cp -R $AIRFLOW_HOME/dags/dbt_project/. $PWD;
    {dbt_command}
    """

# 環境変数 DBT_TARGET で profiles.yml の target を設定できます
# 環境変数 DBT_USE_COLORS を設定し Airflow UI 上でログを見やすくします
# 参照: https://github.com/dbt-labs/dbt-core/blob/v1.11.8/core/dbt/cli/params.py
env = {'DBT_TARGET': 'prod', 'DBT_USE_COLORS': 'False'}

@dag(
    default_args={'env': env, 'append_env': True}
)
def dag_02_dbt_bash():
    @task.bash
    def dbt_build():
        return dbt_bash_command('dbt build --exclude-resource-type unit_test')

    dbt_build()

dag_02_dbt_bash()
