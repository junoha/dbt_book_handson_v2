-- 意図的に warn としている
{{ config(severity='warn', tags=['operational_monitoring']) }}

-- 高度な異常検知テスト

-- 統計的外れ値検出（注文金額）
with order_amount_outliers as (
  {{ detect_statistical_outliers('total_amount', source('zakka_mall', 'order_header'), var('outlier_threshold')) }}
),

-- データ鮮度チェック
freshness_violations as (
  {{ check_data_freshness('order_date', source('zakka_mall', 'order_header'), var('freshness_threshold_hours')) }}
),

-- 日次異常パターン検知
daily_anomalies as (
  {{ detect_daily_anomalies('total_amount', 'order_date', source('zakka_mall', 'order_header'), 50) }}
),

-- 季節性を考慮した異常検知
seasonal_anomalies as (
  {{ detect_seasonal_anomalies('1', 'order_date', source('zakka_mall', 'order_header'), 30) }}
),

-- 統合異常レポート
anomaly_report as (
  select
    'STATISTICAL_OUTLIER' as anomaly_type,
    'order_amount' as metric_name,
    order_id::text as entity_id,
    total_amount as metric_value,
    z_score as anomaly_score,
    current_timestamp as detected_at
  from order_amount_outliers
  
  union all
  
  select
    'FRESHNESS_VIOLATION' as anomaly_type,
    'data_freshness' as metric_name,
    'order_header' as entity_id,
    hours_since_last_update as metric_value,
    null as anomaly_score,
    current_timestamp as detected_at
  from freshness_violations
  
  union all
  
  select
    'DAILY_ANOMALY' as anomaly_type,
    'daily_volume' as metric_name,
    metric_date::text as entity_id,
    daily_value as metric_value,
    percent_change as anomaly_score,
    current_timestamp as detected_at
  from daily_anomalies
  
  union all
  
  select
    'SEASONAL_ANOMALY' as anomaly_type,
    'weekly_pattern' as metric_name,
    metric_date::text as entity_id,
    daily_value as metric_value,
    z_score as anomaly_score,
    current_timestamp as detected_at
  from seasonal_anomalies
)

-- 異常が検出された場合のみ結果を返す
select
  anomaly_type,
  metric_name,
  entity_id,
  metric_value,
  anomaly_score,
  detected_at,
  case 
    when anomaly_type = 'FRESHNESS_VIOLATION' and metric_value > {{ var('critical_freshness_threshold_hours') }} then 'CRITICAL'
    when anomaly_type = 'STATISTICAL_OUTLIER' and anomaly_score > 5 then 'CRITICAL'
    when anomaly_type = 'DAILY_ANOMALY' and anomaly_score > 100 then 'HIGH'
    when anomaly_type = 'SEASONAL_ANOMALY' and anomaly_score > 3 then 'HIGH'
    else 'MEDIUM'
  end as severity_level
from anomaly_report
where 
  (anomaly_type = 'STATISTICAL_OUTLIER' and anomaly_score > {{ var('outlier_threshold') }})
  or (anomaly_type = 'FRESHNESS_VIOLATION' and metric_value > {{ var('freshness_threshold_hours') }})
  or (anomaly_type = 'DAILY_ANOMALY' and anomaly_score > 50)
  or (anomaly_type = 'SEASONAL_ANOMALY' and anomaly_score > 2)
