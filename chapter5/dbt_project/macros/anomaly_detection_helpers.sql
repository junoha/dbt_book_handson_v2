-- 異常検知支援マクロ集

-- 統計的外れ値検出（Z-score方式）
{% macro detect_statistical_outliers(column_name, table_name, z_threshold=3) %}
  with stats as (
    select
      avg({{ column_name }}) as mean_value,
      stddev({{ column_name }}) as std_value
    from {{ table_name }}
    where {{ column_name }} is not null
  ),
  outliers as (
    select
      *,
      abs(({{ column_name }} - stats.mean_value) / nullif(stats.std_value, 0)) as z_score
    from {{ table_name }}
    cross join stats
    where {{ column_name }} is not null
  )
  select *
  from outliers
  where z_score > {{ z_threshold }}
{% endmacro %}

-- データ鮮度チェック（カスタム閾値）
{% macro check_data_freshness(timestamp_column, table_name, hours_threshold=24) %}
  select
    max({{ timestamp_column }}) as latest_timestamp,
    {{ dbt.current_timestamp() }} as current_timestamp,
    extract(epoch from ({{ dbt.current_timestamp() }} - max({{ timestamp_column }}))) / 3600 as hours_since_last_update
  from {{ table_name }}
  having extract(epoch from ({{ dbt.current_timestamp() }} - max({{ timestamp_column }}))) / 3600 > {{ hours_threshold }}
{% endmacro %}

-- 異常パターン検知（前日比較）
{% macro detect_daily_anomalies(metric_column, timestamp_column, table_name, threshold_percent=50) %}
  with daily_metrics as (
    select
      date_trunc('day', {{ timestamp_column }}) as metric_date,
      sum({{ metric_column }}) as daily_value
    from {{ table_name }}
    group by date_trunc('day', {{ timestamp_column }})
  ),
  with_previous as (
    select
      *,
      lag(daily_value) over (order by metric_date) as previous_day_value
    from daily_metrics
  )
  select
    metric_date,
    daily_value,
    previous_day_value,
    case 
      when previous_day_value > 0 then 
        abs((daily_value - previous_day_value) / previous_day_value * 100)
      else null
    end as percent_change
  from with_previous
  where 
    previous_day_value is not null
    and case 
      when previous_day_value > 0 then 
        abs((daily_value - previous_day_value) / previous_day_value * 100)
      else 0
    end > {{ threshold_percent }}
{% endmacro %}

-- 季節性を考慮した異常検知
{% macro detect_seasonal_anomalies(metric_column, timestamp_column, table_name, day_of_week_threshold=30) %}
  with weekly_patterns as (
    select
      extract(dow from {{ timestamp_column }}) as day_of_week,
      date_trunc('day', {{ timestamp_column }}) as metric_date,
      sum({{ metric_column }}) as daily_value
    from {{ table_name }}
    group by 
      extract(dow from {{ timestamp_column }}),
      date_trunc('day', {{ timestamp_column }})
  ),
  dow_stats as (
    select
      day_of_week,
      avg(daily_value) as avg_value,
      stddev(daily_value) as std_value
    from weekly_patterns
    group by day_of_week
  )
  select
    wp.metric_date,
    wp.day_of_week,
    wp.daily_value,
    ds.avg_value as expected_value,
    abs(wp.daily_value - ds.avg_value) / nullif(ds.std_value, 0) as z_score
  from weekly_patterns wp
  join dow_stats ds on wp.day_of_week = ds.day_of_week
  where abs(wp.daily_value - ds.avg_value) / nullif(ds.std_value, 0) > 2
{% endmacro %}
