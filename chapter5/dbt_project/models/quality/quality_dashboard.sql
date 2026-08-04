{{
  config(
    tags=['quality', 'dashboard']
  )
}}

-- データ品質ダッシュボード用の統合ビュー
with quality_metrics as (
    -- quality_assessment の品質スコアをテーブル・ディメンション単位で取得
    select
        table_name,
        quality_dimension,
        quality_score as score
    from {{ ref('quality_assessment') }}
),

aggregated_scores as (
    -- テーブル単位で品質スコアを集計し、ディメンション別の件数を算出
    select
        table_name,
        avg(score) as overall_quality_score,
        count(case when score >= 95 then 1 end) as excellent_dimensions,
        count(case when score >= 80 and score < 95 then 1 end) as good_dimensions,
        count(case when score < 80 then 1 end) as poor_dimensions,
        count(*) as total_dimensions
    from quality_metrics
    group by table_name
),

quality_scores as (
    -- 集計結果にグレード判定を付与
    select
        table_name,
        excellent_dimensions,
        good_dimensions,
        poor_dimensions,
        total_dimensions,
        round(overall_quality_score, 2) as overall_quality_score,
        case
            when overall_quality_score >= 95 then 'EXCELLENT'
            when overall_quality_score >= 80 then 'GOOD'
            when overall_quality_score >= 60 then 'FAIR'
            else 'POOR'
        end as quality_grade
    from aggregated_scores
),

quality_pass_rates as (
    select
        table_name,
        count(*) as total_assessments,
        count(case when quality_status = 'PASS' then 1 end) as passed_assessments,
        count(case when quality_status = 'FAIL' then 1 end) as failed_assessments,
        round(count(case when quality_status = 'PASS' then 1 end)::numeric / count(*)::numeric * 100, 2) as pass_rate,
        min(quality_score) as min_quality_score,
        max(quality_score) as max_quality_score
    from {{ ref('quality_assessment') }}
    group by table_name
),

business_priority as (
    select
        data_asset as table_name,
        business_impact,
        data_contamination,
        action_priority,
        execution_priority
    from {{ ref('business_impact_matrix') }}
),

quality_dashboard as (
    select
        qs.table_name,
        qs.overall_quality_score,
        qs.quality_grade,
        qpr.pass_rate,
        qpr.total_assessments,
        qpr.passed_assessments,
        qpr.failed_assessments,
        qs.excellent_dimensions,
        qs.good_dimensions,
        qs.poor_dimensions,
        qs.total_dimensions,
        qpr.min_quality_score,
        qpr.max_quality_score,
        coalesce(bp.business_impact, 'UNKNOWN') as business_impact,
        coalesce(bp.data_contamination, 'UNKNOWN') as data_contamination,
        coalesce(bp.action_priority, 'ASSESS') as action_priority,
        coalesce(bp.execution_priority, 99) as execution_priority,
        case
            when qpr.failed_assessments = 0 then '🟢 All Checks Passing'
            when qpr.failed_assessments <= 2 then '🟡 Minor Issues'
            else '🔴 Critical Issues'
        end as status_indicator
    from quality_scores as qs
    left join quality_pass_rates as qpr on qs.table_name = qpr.table_name
    left join business_priority as bp on qs.table_name = bp.table_name
)

select
    table_name,
    quality_grade,
    status_indicator,
    overall_quality_score,
    pass_rate,
    total_assessments,
    passed_assessments,
    failed_assessments,
    excellent_dimensions,
    good_dimensions,
    poor_dimensions,
    total_dimensions,
    business_impact,
    data_contamination,
    action_priority,
    execution_priority,
    min_quality_score,
    max_quality_score,
    current_timestamp as dashboard_refresh_time
from quality_dashboard
order by execution_priority asc, overall_quality_score desc
