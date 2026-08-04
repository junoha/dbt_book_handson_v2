with

orders as (

    select * from {{ ref('stg_jaffle_shop__orders') }}

),

order_items as (

    select * from {{ ref('stg_jaffle_shop__order_items') }}

),

products as (

    select * from {{ ref('stg_jaffle_shop__products') }}

),

order_items_joined as (

    -- 旧 order_items mart 相当: 明細に商品属性を enrich する
    select
        order_items.order_item_id,
        order_items.order_id,
        order_items.product_id,

        products.product_price,
        products.is_food_item,
        products.is_drink_item

    from order_items

    left join products
        on order_items.product_id = products.product_id

),

order_items_summary as (

    select
        order_id,

        sum(product_price) as order_items_subtotal,
        count(order_item_id) as count_order_items,
        sum(case when is_food_item then 1 else 0 end) as count_food_items,
        sum(case when is_drink_item then 1 else 0 end) as count_drink_items

    from order_items_joined

    group by 1

),

compute_booleans as (

    select
        orders.order_id,
        orders.customer_id,
        orders.location_id,
        orders.ordered_at,
        orders.subtotal,
        orders.tax_paid,
        orders.order_total,

        order_items_summary.order_items_subtotal,
        order_items_summary.count_order_items,
        order_items_summary.count_food_items,
        order_items_summary.count_drink_items,
        order_items_summary.count_food_items > 0 as is_food_order,
        order_items_summary.count_drink_items > 0 as is_drink_order

    from orders

    left join order_items_summary
        on orders.order_id = order_items_summary.order_id

),

customer_order_count as (

    select
        *,

        row_number() over (
            partition by customer_id
            order by ordered_at asc
        ) as customer_order_number

    from compute_booleans

)

select * from customer_order_count
