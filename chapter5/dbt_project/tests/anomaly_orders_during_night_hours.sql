-- Singular Test: 深夜時間帯の注文比率異常検知
--
-- ビジネスルール:
-- ZakkaMall は 24 時間注文を受け付けているが、業務実態として
-- 深夜 2〜6 時の注文は全体に占める割合が小さいはず。
-- この時間帯の注文が全体の 10% を超えた場合は次のような異常を疑う。
--   - Bot による不正注文
--   - created_at のタイムゾーン不整合や時刻データ破損
--   - 海外からの想定外トラフィック流入
--
-- 注: 本テストはデータの「鮮度（freshness）」ではなく
-- 「時刻分布の異常」を検証するものであり、ファイル名も
-- anomaly_ プレフィックスで明示している（旧名は
-- data_freshness_orders_within_business_hours.sql）。

-- 意図的に warn としている。
{{ config(severity='warn') }}

with hourly_order_stats as (
    select
        extract(hour from created_at) as order_hour,
        count(*) as order_count,
        sum(total_amount) as total_sales
    from {{ ref('stg_zakka_mall__orders') }}
    where created_at is not null
    group by extract(hour from created_at)
),

total_orders as (
    select count(*) as total_count
    from {{ ref('stg_zakka_mall__orders') }}
    where created_at is not null
),

night_orders as (
    select
        sum(order_count) as night_order_count,
        sum(total_sales) as night_total_sales
    from hourly_order_stats
    where order_hour between 2 and 6  -- 深夜 2〜6 時
)

select
    'NIGHT_ORDER_ANOMALY' as test_type,
    night_order_count,
    night_total_sales,
    (select total_count from total_orders) as total_order_count,
    round(
        night_order_count::decimal / (select total_count from total_orders)::decimal * 100,
        2
    ) as night_order_percentage,
    case
        when night_order_count::decimal / (select total_count from total_orders)::decimal > 0.1 then 'ANOMALY_DETECTED'
        else 'NORMAL'
    end as anomaly_status
from night_orders
where night_order_count::decimal / (select total_count from total_orders)::decimal > 0.1  -- 10% を超える場合に異常と判定
