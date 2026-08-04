-- 意図的に warn としている
{{ config(severity='warn', tags=['operational_monitoring']) }}

-- 運用段階での包括的監視テスト

-- 1. データ鮮度の包括チェック
--
-- `loaded_at_field` 相当として `updated_at`（ロード時刻）を用いる。
-- 本書 `Source Freshness チェックによる鮮度監視` 節で説明している通り、
-- 鮮度判定はイベント時刻（`order_date` / `payment_date` 等）ではなく
-- 「データがウェアハウスに到着した時刻」(`updated_at`) を見ることで、
-- 単純な遅延到着や取り込み失敗を確実に検出できる。
with freshness_check as (
    select
        'table::customer' as target_table_name,
        max(updated_at) as latest_timestamp,
        extract(epoch from (current_timestamp - max(updated_at)))
        / 3600 as hours_old
    from {{ source('zakka_mall', 'customer') }}

    union all

    select
        'table::order_header' as target_table_name,
        max(updated_at) as latest_timestamp,
        extract(epoch from (current_timestamp - max(updated_at)))
        / 3600 as hours_old
    from {{ source('zakka_mall', 'order_header') }}

    union all

    select
        'table::payment' as target_table_name,
        max(updated_at) as latest_timestamp,
        extract(epoch from (current_timestamp - max(updated_at)))
        / 3600 as hours_old
    from {{ source('zakka_mall', 'payment') }}
),

-- 2. データボリューム異常チェック
volume_check as (
    select
        'daily_orders' as metric_name,
        date_trunc('day', order_date) as metric_date,
        count(*) as daily_count
    from {{ source('zakka_mall', 'order_header') }}
    where order_date >= current_date - interval '7 days'
    group by date_trunc('day', order_date)
),

volume_anomalies as (
    select
        metric_name,
        metric_date,
        daily_count,
        avg(daily_count) over (
            order by metric_date
            rows between 6 preceding and 1 preceding
        ) as avg_previous_6_days,
        case
            when daily_count < avg(daily_count) over (
                order by metric_date
                rows between 6 preceding and 1 preceding
            ) * {{ var('volume_drop_threshold') }} then 'VOLUME_DROP'
            when daily_count > avg(daily_count) over (
                order by metric_date
                rows between 6 preceding and 1 preceding
            ) * {{ var('volume_spike_threshold') }} then 'VOLUME_SPIKE'
            else 'NORMAL'
        end as anomaly_status
    from volume_check
),

-- 3. ビジネスルール違反チェック
business_rule_violations as (
    select
        'negative_amounts' as violation_type,
        count(*) as violation_count
    from {{ source('zakka_mall', 'order_header') }}
    where total_amount < 0

    union all

    select
        'future_orders' as violation_type,
        count(*) as violation_count
    from {{ source('zakka_mall', 'order_header') }}
    where order_date > current_date

    union all

    select
        'payment_amount_mismatch' as violation_type,
        count(*) as violation_count
    from {{ source('zakka_mall', 'order_header') }} as oh
    inner join
        {{ source('zakka_mall', 'payment') }} as p
        on oh.order_id = p.order_id
    where
        abs(oh.total_amount - p.payment_amount)
        > {{ var('payment_mismatch_threshold') }}
        and p.payment_status = 'completed'

    union all

    select
        'excessive_order_amounts' as violation_type,
        count(*) as violation_count
    from {{ source('zakka_mall', 'order_header') }}
    where total_amount > {{ var('max_order_amount') }}
),

-- 4. データ品質劣化チェック
quality_degradation as (
    select
        'customer_email_nulls' as quality_metric,
        count(case when email is null then 1 end)
        * 100.0
        / count(*) as null_percentage
    from {{ source('zakka_mall', 'customer') }}

    union all

    select
        'product_price_nulls' as quality_metric,
        count(case when price is null then 1 end)
        * 100.0
        / count(*) as null_percentage
    from {{ source('zakka_mall', 'product') }}
),

-- 統合結果
monitoring_results as (
    select
        'FRESHNESS_VIOLATION' as issue_type,
        target_table_name as detail,
        hours_old as metric_value,
        case
            when
                hours_old > {{ var('freshness_critical_hours') }}
                then 'CRITICAL' else
                'WARNING'
        end
            as severity
    from freshness_check
    where hours_old > {{ var('freshness_warning_hours') }}

    union all

    select
        'VOLUME_ANOMALY' as issue_type,
        metric_name as detail,
        daily_count as metric_value,
        case
            when anomaly_status = 'VOLUME_DROP' then 'CRITICAL' else 'WARNING'
        end as severity
    from volume_anomalies
    where
        anomaly_status != 'NORMAL'
        and metric_date = current_date - interval '1 day'  -- 昨日のデータをチェック

    union all

    select
        'BUSINESS_RULE_VIOLATION' as issue_type,
        violation_type as detail,
        violation_count as metric_value,
        case when violation_count > 0 then 'CRITICAL' else 'OK' end as severity
    from business_rule_violations
    where violation_count > 0

    union all

    select
        'QUALITY_DEGRADATION' as issue_type,
        quality_metric as detail,
        null_percentage as metric_value,
        case
            when
                null_percentage > {{ var('quality_critical_percent') }}
                then 'CRITICAL' else
                'WARNING'
        end
            as severity
    from quality_degradation
    where null_percentage > {{ var('quality_warning_percent') }}
)

-- 問題が検出された場合のみ結果を返す（テスト失敗）
select
    issue_type,
    detail,
    metric_value,
    severity,
    current_timestamp as detected_at
from monitoring_results
where severity in ('CRITICAL', 'WARNING')
