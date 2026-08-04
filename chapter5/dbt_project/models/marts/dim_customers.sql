{{
  config(
    materialized='table',
    tags=['mart', 'customer']
  )
}}

with

customers as (
    select * from {{ ref('stg_zakka_mall__customers') }}
),

orders as (
    select * from {{ ref('stg_zakka_mall__orders') }}
),

payments as (
    select * from {{ ref('stg_zakka_mall__payments') }}
),

customer_orders as (
    select
        customer_id,
        min(order_date) as first_order_date,
        max(order_date) as last_order_date,
        count(order_id) as total_orders,
        sum(total_amount)::numeric(15, 2) as total_amount,
        avg(total_amount)::numeric(15, 2) as avg_order_amount
    from orders
    where order_status not in ('cancelled', 'refunded')
    group by customer_id
),

customer_payments as (
    -- Customer Lifetime Value (LTV) の母数となる「完了済み支払い」を集計する。
    -- customer_orders と揃えてキャンセル・返金注文を除外することで、
    -- 「実際に売上として確定した支払い」だけを LTV に算入する。
    select
        o.customer_id,
        sum(case when p.payment_status = 'completed' then p.payment_amount else 0 end) as total_paid_amount
    from orders as o
    left join payments as p on o.order_id = p.order_id
    where o.order_status not in ('cancelled', 'refunded')
    group by o.customer_id
),

final as (
    select
        c.customer_id,
        c.customer_name,
        c.email,
        c.phone,
        c.registration_date,
        c.status,
        c.birth_date,
        c.age,

        -- 注文関連指標
        coalesce(co.first_order_date, null) as first_order_date,
        coalesce(co.last_order_date, null) as last_order_date,
        coalesce(co.total_orders, 0) as total_orders,
        coalesce(co.total_amount, 0)::numeric(15, 2) as total_amount,
        coalesce(co.avg_order_amount, 0)::numeric(15, 2) as avg_order_amount,

        -- 顧客生涯価値（実際の支払金額ベース）
        coalesce(cp.total_paid_amount, 0)::numeric(15, 2) as customer_lifetime_value

    from customers as c
    left join customer_orders as co on c.customer_id = co.customer_id
    left join customer_payments as cp on c.customer_id = cp.customer_id
)

select * from final
