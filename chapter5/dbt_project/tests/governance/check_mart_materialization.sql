-- Singular test: マートレイヤーのマテリアライゼーションチェック
-- dbt_project_evaluator の int_all_graph_resources を参照し、
-- 自プロジェクトの marts レイヤーのモデルが table で
-- マテリアライズされていることを検証する

with mart_models as (
    select
        resource_name,
        model_type,
        materialized
    from {{ ref('dbt_project_evaluator', 'int_all_graph_resources') }}
    where
        resource_type = 'model'
        and not is_excluded
        and model_type = 'marts'
        and materialized != 'table'
        and package_name = '{{ project_name }}'
),

materialization_violations as (
    select
        resource_name,
        model_type,
        materialized,
        'Mart models must be materialized as table, but found: ' || materialized as violation_reason
    from mart_models
)

select *
from materialization_violations
