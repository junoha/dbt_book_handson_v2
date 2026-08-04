-- Singular test: モデルドキュメンテーションチェック
-- dbt_project_evaluator の int_all_graph_resources を参照し、
-- 自プロジェクト（zakkamall_data_quality）の description が未記載のモデルを検出する
--
-- fct_undocumented_models を直接使うと Elementary 等の依存パッケージの
-- モデルも検出対象になるため、package_name でフィルタリングしている

with undocumented as (
    select
        resource_name,
        model_type,
        package_name
    from {{ ref('dbt_project_evaluator', 'int_all_graph_resources') }}
    where
        resource_type = 'model'
        and not is_excluded
        and not is_described
        and package_name = '{{ project_name }}'
),

violations as (
    select
        resource_name,
        model_type,
        'Model must have description in YAML' as violation_reason
    from undocumented
)

select *
from violations
