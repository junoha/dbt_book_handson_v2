-- 顧客分析マート（RFM 分析）
-- dim_customers × fct_orders × fct_order_items を顧客単位に集計し、
-- RFM スコア・セグメント・顧客価値を付与する。
-- Grain: 1 row per customer_id（SCD Type 2 の全期間を集約した顧客単位）
--
-- Note: dim_customers は SCD Type 2 のため、同じ customer_id に対して
-- 複数のバージョン（valid_from / valid_to の期間違い）が存在する。
-- このマートでは customer_id 単位で集約するため、dim_customers からは
-- customer_id ごとに最新バージョンの属性を取得する。
{{
  config(
    materialized='table',
    tags=['mart', 'marketing', 'customer']
  )
}}

with
-- dim_customers から現在有効なバージョンの属性を取得
-- snapshots.yml で dbt_valid_to_current: '9999-12-31' を設定しているため、
-- 現在有効な行は valid_to で判定できる（NULL 比較が不要）
customers as (
    select
        customer_id,
        customer_name,
        email,
        customer_status,
        customer_tenure_segment,
        prefecture,
        region,
        registration_date
    from {{ ref('dim_customers') }}
    where valid_to = cast('9999-12-31' as timestamptz)
),

order_metrics as (
    select
        customer_id,

        -- 購買日付メトリクス
        min(order_date) as first_order_date,
        max(order_date) as last_order_date,
        cast('{{ var("analysis_as_of_date") }}' as date) - max(order_date)
            as days_since_last_order,

        -- 注文・金額メトリクス
        count(distinct order_id) as total_orders,
        sum(total_amount) as total_spent,
        avg(total_amount) as avg_order_value

    from {{ ref('fct_orders') }}
    group by customer_id
),

item_metrics as (
    select
        customer_id,

        -- 購入商品メトリクス
        count(distinct product_id) as unique_products_purchased,
        sum(quantity) as total_items_purchased

    from {{ ref('fct_order_items') }}
    group by customer_id
),

customer_metrics as (
    select
        dc.customer_id,
        dc.customer_name,
        dc.email,
        dc.customer_status,
        dc.customer_tenure_segment,
        dc.prefecture,
        dc.region,
        dc.registration_date,

        om.first_order_date,
        om.last_order_date,
        om.days_since_last_order,

        coalesce(om.total_orders, 0) as total_orders,
        coalesce(om.total_spent, 0) as total_spent,
        om.avg_order_value,

        coalesce(im.unique_products_purchased, 0) as unique_products_purchased,
        coalesce(im.total_items_purchased, 0) as total_items_purchased

    from customers as dc
    left join order_metrics as om on dc.customer_id = om.customer_id
    left join item_metrics as im on dc.customer_id = im.customer_id
),

with_rfm_scores as (
    select
        *,

        -- Recency Score (1-5, 5 が最近)
        case
            when days_since_last_order <= 30 then 5
            when days_since_last_order <= 60 then 4
            when days_since_last_order <= 90 then 3
            when days_since_last_order <= 180 then 2
            else 1
        end as recency_score,

        -- Frequency Score (1-5, 5 が最頻繁)
        case
            when total_orders >= 10 then 5
            when total_orders >= 5 then 4
            when total_orders >= 3 then 3
            when total_orders >= 2 then 2
            else 1
        end as frequency_score,

        -- Monetary Score (1-5, 5 が最高額)
        case
            when total_spent >= 100000 then 5
            when total_spent >= 50000 then 4
            when total_spent >= 20000 then 3
            when total_spent >= 10000 then 2
            else 1
        end as monetary_score

    from customer_metrics
),

with_customer_segments as (
    select
        *,

        -- RFM スコアを結合した 3 桁コード
        concat(recency_score, frequency_score, monetary_score) as rfm_score,

        -- 顧客セグメント
        case
            when recency_score >= 4 and frequency_score >= 4 and monetary_score >= 4 then 'Champions'
            when recency_score >= 3 and frequency_score >= 3 and monetary_score >= 3 then 'Loyal Customers'
            when recency_score >= 4 and frequency_score <= 2 then 'New Customers'
            when recency_score <= 2 and frequency_score >= 3 then 'At Risk'
            when recency_score <= 2 and frequency_score <= 2 then 'Lost Customers'
            else 'Potential Loyalists'
        end as customer_segment,

        -- 顧客価値
        case
            when total_spent >= {{ var('high_value_customer_threshold') }} then 'High Value'
            when total_spent >= {{ var('high_value_customer_threshold') }} / 2 then 'Medium Value'
            else 'Low Value'
        end as customer_value_segment

    from with_rfm_scores
)

select * from with_customer_segments
