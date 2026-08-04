with customers as (
    select * from {{ ref('stg_jaffle_shop__customers') }}
),

orders as (
    select * from {{ ref('orders') }}
),

customer_orders as (
    -- 顧客ごとに注文実績（初回・最新日、注文回数、金額、カテゴリ別件数）を集計
    select
        customer_id,
        min(ordered_at) as first_order_date,
        max(ordered_at) as most_recent_order_date,
        count(order_id) as number_of_orders,
        sum(order_total) as total_amount,
        sum(item_count) as total_items_ordered,
        sum(jaffle_count) as jaffle_items,
        sum(beverage_count) as beverage_items
    from orders
    group by customer_id
),

final as (
    -- customersに集計結果を結合し、集計がない顧客はcoalesceで0埋め
    select
        customers.customer_id,
        customers.customer_name,
        customer_orders.first_order_date,
        customer_orders.most_recent_order_date,
        coalesce(customer_orders.number_of_orders, 0) as number_of_orders,
        coalesce(customer_orders.total_amount, 0) as customer_lifetime_value,
        coalesce(customer_orders.total_items_ordered, 0) as total_items_ordered,
        coalesce(customer_orders.jaffle_items, 0) as jaffle_items,
        coalesce(customer_orders.beverage_items, 0) as beverage_items
    from customers
    left join customer_orders
        on customers.customer_id = customer_orders.customer_id
)

select * from final
