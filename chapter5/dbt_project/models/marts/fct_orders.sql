{{
  config(
    materialized='table',
    tags=['mart', 'order']
  )
}}

with

orders as (
    select * from {{ ref('stg_zakka_mall__orders') }}
),

customers as (
    select * from {{ ref('stg_zakka_mall__customers') }}
),

payments as (
    select * from {{ ref('stg_zakka_mall__payments') }}
),

order_details as (
    select * from {{ ref('stg_zakka_mall__order_details') }}
),

order_summary as (
    select
        order_id,
        count(order_detail_id) as item_count,
        -- DuckDB の sum(integer) は decimal(38, 0) を返すため、
        -- contract の data_type (bigint) に合わせて明示的にキャストする
        cast(sum(quantity) as bigint) as total_quantity
    from order_details
    group by order_id
),

payment_summary as (
    select
        order_id,
        -- ビジネス優先度に基づく支払いステータス
        case
            when count(case when payment_status = 'completed' then 1 end) > 0 then 'completed'
            when count(case when payment_status = 'failed' then 1 end) > 0 then 'failed'
            when count(case when payment_status = 'refunded' then 1 end) > 0 then 'refunded'
            else 'pending'
        end as payment_status,
        -- 最新の支払い方法（最新の支払い日に基づく）
        (array_agg(payment_method order by payment_date desc nulls last))[1] as payment_method,
        -- 最新の支払い日
        max(payment_date) as payment_date
    from payments
    group by order_id
),

final as (
    select
        o.order_id,
        o.customer_id,
        c.customer_name,
        o.order_date,
        o.order_status,
        o.total_amount,
        o.shipping_fee,
        o.tax_amount,

        -- 支払い情報
        ps.payment_status,
        ps.payment_method,
        ps.payment_date,

        -- 注文詳細サマリー
        coalesce(os.item_count, 0) as item_count,
        coalesce(os.total_quantity, 0) as total_quantity

    from orders as o
    left join customers as c on o.customer_id = c.customer_id
    left join payment_summary as ps on o.order_id = ps.order_id
    left join order_summary as os on o.order_id = os.order_id
)

select * from final
