from cosmos import DbtDag, ExecutionConfig, ProfileConfig, ProjectConfig, RenderConfig
from cosmos.constants import SourceRenderingBehavior
import os
from pathlib import Path

AIRFLOW_HOME = Path(os.getenv('AIRFLOW_HOME'))
DBT_PROJECT_DIR = AIRFLOW_HOME / 'dags' / 'dbt_project'
DBT_VENV_PATH = Path(os.getenv('DBT_VENV_PATH'))

project_config = ProjectConfig(
    dbt_project_path=DBT_PROJECT_DIR
)

profile_config = ProfileConfig(
    profile_name='jaffle_shop',
    target_name='prod',
    profiles_yml_filepath=DBT_PROJECT_DIR / 'profiles.yml'
)

render_config = RenderConfig(
    should_detach_multiple_parents_tests=True,
    source_rendering_behavior=SourceRenderingBehavior.WITH_TESTS_OR_FRESHNESS,
)

execution_config = ExecutionConfig(
    dbt_executable_path=DBT_VENV_PATH / 'bin' / 'dbt'
)

dag_03_dbt_cosmos = DbtDag(
    # Airflow DAG のパラメータ
    dag_id='dag_03_dbt_cosmos',

    # Cosmos のパラメータ
    project_config=project_config,
    profile_config=profile_config,
    render_config=render_config,
    execution_config=execution_config,
)
