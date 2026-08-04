{{
  config(
    materialized='table',
    tags=['mart', 'core', 'sales']
  )
}}

with order_metrics as (
    -- 注文ヘッダー粒度の集計
    select
        date_key,
        count(distinct order_id) as order_count,
        count(distinct customer_id) as customer_count,
        sum(total_amount) as total_sales,
        avg(total_amount) as avg_order_value,
        sum(subtotal) as subtotal,
        sum(tax_amount) as tax_amount,
        sum(shipping_fee) as shipping_fee
    from {{ ref('fct_orders') }}
    group by date_key
),

item_metrics as (
    -- 注文明細粒度の集計
    select
        date_key,
        count(distinct product_id) as unique_products_sold,
        sum(quantity) as total_quantity_sold,
        sum(line_total) as total_product_sales
    from {{ ref('fct_order_items') }}
    group by date_key
),

daily_sales as (
    select
        dd.date_key,
        dd.year,
        dd.month,
        dd.quarter,
        dd.month_name,
        dd.quarter_name,
        dd.weekday_flag,

        -- 売上メトリクス（注文ヘッダー粒度）
        coalesce(om.order_count, 0) as order_count,
        coalesce(om.customer_count, 0) as customer_count,
        coalesce(om.total_sales, 0) as total_sales,
        om.avg_order_value,
        coalesce(om.subtotal, 0) as subtotal,
        coalesce(om.tax_amount, 0) as tax_amount,
        coalesce(om.shipping_fee, 0) as shipping_fee,

        -- 商品メトリクス（注文明細粒度）
        coalesce(im.unique_products_sold, 0) as unique_products_sold,
        coalesce(im.total_quantity_sold, 0) as total_quantity_sold,
        coalesce(im.total_product_sales, 0) as total_product_sales

    from
        {{ ref('dim_dates') }} as dd
    inner join order_metrics as om on dd.date_key = om.date_key
    left join item_metrics as im on dd.date_key = im.date_key
),

with_calculations as (
    select
        *,
        -- 前日比計算
        lag(total_sales) over (order by date_key) as prev_day_sales,
        total_sales - lag(total_sales) over (order by date_key) as sales_change,

        -- 移動平均
        avg(total_sales) over (
            order by date_key
            rows between 6 preceding and current row
        ) as sales_7day_avg,

        avg(total_sales) over (
            order by date_key
            rows between 29 preceding and current row
        ) as sales_30day_avg

    from daily_sales
)

select * from with_calculations
