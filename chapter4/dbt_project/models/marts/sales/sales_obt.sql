-- 包括的な売上分析用 One Big Table（OBT）
-- fct_order_items を軸に、fct_orders と各 dimension を結合し、
-- 派生セグメントを付与した分析用の幅広いテーブル。
-- Grain: 1 row per order_item_id
{{
  config(
    materialized='table',
    tags=['mart', 'sales', 'obt'],
    description='One Big Table for comprehensive sales analysis'
  )
}}

with
order_items as (
    select * from {{ ref('fct_order_items') }}
),

orders as (
    select * from {{ ref('fct_orders') }}
),

customers as (
    select * from {{ ref('dim_customers') }}
),

products as (
    select * from {{ ref('dim_products') }}
),

dates as (
    select * from {{ ref('dim_dates') }}
),

sales_obt as (
    select
        -- 注文情報
        fo.order_id,
        fo.order_date,
        fo.order_status,
        fo.order_size_segment,
        fo.subtotal,
        fo.tax_amount,
        fo.shipping_fee,
        fo.total_amount,

        -- 顧客情報（fct_order_items の customer_key に対応する SCD Type 2 の時点）
        dc.customer_id,
        dc.customer_name,
        dc.email,
        dc.customer_status,
        dc.customer_tenure_segment,
        dc.prefecture as customer_prefecture,
        dc.city as customer_city,
        dc.region as customer_region,
        dc.registration_date as customer_registration_date,

        -- 商品情報（fct_order_items の product_key に対応する SCD Type 2 の時点）
        dp.product_id,
        dp.product_name,
        dp.product_code,
        dp.sku,
        dp.unit_price as product_unit_price,
        dp.price_tier,
        dp.category_name,
        dp.supplier_name,
        dp.product_status,

        -- 注文明細情報
        foi.quantity,
        foi.unit_price as order_unit_price,
        foi.line_total,
        foi.quantity_type,

        -- 日付情報
        dd.year as order_year,
        dd.month as order_month,
        dd.quarter as order_quarter,
        dd.month_name,
        dd.quarter_name,
        dd.day_name as order_day_name,
        dd.weekday_flag,
        dd.fiscal_year,
        dd.fiscal_quarter,

        -- 計算フィールド
        1 as order_count,
        1 as order_item_count,

        -- 価格差分析
        foi.unit_price - dp.unit_price as price_difference,
        case
            when dp.unit_price > 0
                then round(((foi.unit_price - dp.unit_price) / dp.unit_price * 100)::numeric, 2)
            else 0
        end as price_change_percent,

        -- 注文金額セグメント
        case
            when fo.total_amount >= 30000 then 'High'
            when fo.total_amount >= 10000 then 'Medium'
            else 'Low'
        end as order_value_segment,

        -- 購入パターン
        case
            when foi.quantity > 3 then 'Bulk'
            when foi.quantity > 1 then 'Multiple'
            else 'Single'
        end as purchase_pattern

    from order_items as foi
    inner join orders as fo on foi.order_id = fo.order_id
    inner join customers as dc on foi.customer_key = dc.customer_key
    inner join products as dp on foi.product_key = dp.product_key
    inner join dates as dd on foi.date_key = dd.date_key
)

select * from sales_obt
