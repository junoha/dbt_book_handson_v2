-- Singular test: モデルの命名規則チェック
-- dbt_project_evaluator の int_all_graph_resources を参照し、
-- 自プロジェクト（zakkamall_data_quality）の命名規則に違反しているモデルを検出する
--
-- fct_model_naming_conventions を直接使うと Elementary 等の依存パッケージの
-- モデルも検出対象になるため、package_name でフィルタリングしている
--
-- severity は dbt_project_evaluator の stg_naming_convention_prefixes
-- （staging: stg_ / intermediate: int_ / dimension: dim_ / fact: fct_ 等）に
-- 合わせて error として扱う。公式命名規則に違反するモデルがあれば CI を止める。

{{ config(severity='error') }}

with project_models as (
    select
        resource_name,
        prefix,
        model_type
    from {{ ref('dbt_project_evaluator', 'int_all_graph_resources') }}
    where
        resource_type = 'model'
        and not is_excluded
        and package_name = '{{ project_name }}'
),

appropriate_prefixes as (
    select
        model_type,
        string_agg(prefix_value, ', ' order by prefix_value) as appropriate_prefixes
    from {{ ref('dbt_project_evaluator', 'stg_naming_convention_prefixes') }}
    group by model_type
),

violations as (
    select
        m.resource_name,
        m.prefix,
        m.model_type,
        p.appropriate_prefixes
    from project_models as m
    left join {{ ref('dbt_project_evaluator', 'stg_naming_convention_prefixes') }} as n
        on
            m.model_type = n.model_type
            and m.prefix = n.prefix_value
    left join appropriate_prefixes as p
        on m.model_type = p.model_type
    where n.prefix_value is null
)

select *
from violations
