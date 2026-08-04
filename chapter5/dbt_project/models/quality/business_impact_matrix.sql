{{
  config(
    tags=['quality', 'assessment', 'business_impact']
  )
}}

-- ビジネス影響度とデータ汚れ度合いのマトリックス
--
-- 静的な評価データは seeds/business_impact.csv に切り出し、
-- このモデルでは seed を参照して action_priority / execution_priority を算出する。
-- CSV 化により、ビジネスサイドのステークホルダーが GUI（Spreadsheet / GitHub 上のプレビュー）で
-- 直接編集できる運用になり、SQL リテラルとしてのエスケープも不要になる。
with business_impact_assessment as (
    select
        data_asset,
        business_entity,
        key_field,
        business_impact,
        data_contamination,
        business_justification,
        contamination_assessment,
        priority_rank
    from {{ ref('business_impact') }}
),

priority_matrix as (
    select
        *,
        case
            when business_impact = 'HIGH' and data_contamination = 'LOW' then 'MAINTAIN'
            when business_impact = 'HIGH' and data_contamination = 'MEDIUM' then 'IMPROVE'
            when business_impact = 'HIGH' and data_contamination = 'HIGH' then 'URGENT_FIX'
            when business_impact = 'MEDIUM' and data_contamination = 'LOW' then 'MONITOR'
            when business_impact = 'MEDIUM' and data_contamination = 'MEDIUM' then 'MONITOR'
            when business_impact = 'MEDIUM' and data_contamination = 'HIGH' then 'IMPROVE'
            when business_impact = 'LOW' and data_contamination = 'LOW' then 'MONITOR'
            when business_impact = 'LOW' and data_contamination = 'MEDIUM' then 'MONITOR'
            when business_impact = 'LOW' and data_contamination = 'HIGH' then 'CONSIDER_FIX'
        end as action_priority,
        case
            when business_impact = 'HIGH' and data_contamination = 'HIGH' then 1
            when business_impact = 'HIGH' and data_contamination = 'MEDIUM' then 2
            when business_impact = 'MEDIUM' and data_contamination = 'HIGH' then 3
            when business_impact = 'HIGH' and data_contamination = 'LOW' then 4
            when business_impact = 'MEDIUM' and data_contamination = 'MEDIUM' then 5
            else 6
        end as execution_priority
    from business_impact_assessment
)

select
    data_asset,
    business_entity,
    key_field,
    business_impact,
    data_contamination,
    action_priority,
    execution_priority,
    business_justification,
    contamination_assessment,
    current_timestamp as assessment_date
from priority_matrix
order by execution_priority, priority_rank
