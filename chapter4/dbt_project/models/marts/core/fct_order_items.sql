-- 注文明細ファクトテーブル
-- stg_zakka_mall__order_items と stg_zakka_mall__orders を結合し、
-- ディメンションキー（customer_key / product_key / date_key）を付与した明細粒度のファクト。
-- Grain: 1 row per order_item_id
-- Business process: EC サイトでの注文明細の確定
{{
  config(
    materialized='table',
    tags=['fct', 'order_items']
  )
}}

with order_item_facts as (
    select
        oi.order_item_id,
        oi.order_id,
        oi.product_id,
        o.order_date,
        o.customer_id,

        -- ディメンションキー
        dc.customer_key,
        dp.product_key,
        dd.date_key,

        -- メジャー
        oi.quantity,
        oi.unit_price,
        oi.line_total,

        -- 明細レベルの属性
        oi.quantity_type,

        -- 計算メジャー
        1 as order_item_count,

        -- メタデータ
        oi.created_at

    from
        {{ ref('stg_zakka_mall__order_items') }} as oi
    inner join {{ ref('stg_zakka_mall__orders') }} as o on oi.order_id = o.order_id
    left join {{ ref('dim_customers') }} as dc
        on
            o.customer_id = dc.customer_id
            and o.order_date >= dc.valid_from::date
            and o.order_date < dc.valid_to::date
    left join {{ ref('dim_products') }} as dp
        on
            oi.product_id = dp.product_id
            and o.order_date >= dp.valid_from::date
            and o.order_date < dp.valid_to::date
    inner join {{ ref('dim_dates') }} as dd on o.order_date = dd.date_key
    where
        oi.is_valid_record = true and o.is_valid_record = true
)

select * from order_item_facts
