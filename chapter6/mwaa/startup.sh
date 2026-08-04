#!/bin/sh

export DBT_VENV_PATH="${AIRFLOW_HOME}/dbt_venv"

python3 -m venv "${DBT_VENV_PATH}"

${DBT_VENV_PATH}/bin/pip install \
    dbt-core==1.11.8 \
    dbt-athena==1.10.0
