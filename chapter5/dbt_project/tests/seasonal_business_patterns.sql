-- Singular Test: 季節性ビジネスパターンの検証
-- 売上の季節変動が想定範囲内かをチェックする。
-- アルゴリズム:
--   過去 2 年間の月次売上から「月ごとの平均・標準偏差」を計算し、
--   現在月の売上が Z スコア ±3（≒ 99.7% 信頼区間外）に入った場合に異常と判定する。

-- 意図的に warn としている
{{ config(severity='warn') }}

with monthly_sales as (
    select
        extract(year from order_date) as year,
        extract(month from order_date) as month,
        count(*) as order_count,
        sum(total_amount) as total_sales
    from {{ ref('fct_orders') }}
    where order_date >= current_date - interval '2 years'
    group by extract(year from order_date), extract(month from order_date)
),

seasonal_stats as (
    -- 比較の基準となる過去の統計。現在月そのものは除外する。
    -- 現在月を含めると、その月の売上が平均と標準偏差の両方を押し上げてしまい、
    -- Z スコアの絶対値に (n-1)/sqrt(n) という上限がかかる。
    -- 同月の観測が n 件のとき n=3 なら上限 1.155、n=10 でも 2.846 にとどまり、
    -- 閾値 3 を数学的に超えられなくなる（売上をいくら大きくしても検知できない）
    select
        month,
        avg(total_sales) as avg_monthly_sales,
        stddev(total_sales) as stddev_monthly_sales,
        min(total_sales) as min_monthly_sales,
        max(total_sales) as max_monthly_sales
    from monthly_sales
    where not (
        year = extract(year from current_date)
        and month = extract(month from current_date)
    )
    group by month
),

current_month_sales as (
    select
        extract(month from current_date) as current_month,
        sum(total_amount) as current_sales
    from {{ ref('fct_orders') }}
    where
        extract(year from order_date) = extract(year from current_date)
        and extract(month from order_date) = extract(month from current_date)
),

anomaly_check as (
    select
        cms.current_month,
        cms.current_sales,
        ss.avg_monthly_sales,
        ss.stddev_monthly_sales,
        (cms.current_sales - ss.avg_monthly_sales) / nullif(ss.stddev_monthly_sales, 0) as z_score
    from current_month_sales as cms
    inner join seasonal_stats as ss on cms.current_month = ss.month
)

select
    current_month,
    current_sales,
    avg_monthly_sales,
    z_score,
    case
        when z_score > 3 then 'unusually_high_sales'
        when z_score < -3 then 'unusually_low_sales'
    end as anomaly_type
from anomaly_check
where z_score > 3 or z_score < -3
