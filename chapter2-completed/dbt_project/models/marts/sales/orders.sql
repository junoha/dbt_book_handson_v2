with orders as (
    select * from {{ ref('stg_jaffle_shop__orders') }}
),

items as (
    select * from {{ ref('stg_jaffle_shop__items') }}
),

order_items_summary as (
    -- 注文ごとに商品数とカテゴリ別（jaffle/beverage）件数を集計
    select
        order_id,
        count(order_item_id) as item_count,
        count(
            case when product_id like 'JAF-%' then 1 end
        ) as jaffle_count,
        count(
            case when product_id like 'BEV-%' then 1 end
        ) as beverage_count
    from items
    group by order_id
),

final as (
    -- ordersに集計結果を結合し、集計がない注文はcoalesceで0埋め
    -- store_idはstagingでは保持しているが、本マートでは選択しない
    select
        orders.order_id,
        orders.customer_id,
        orders.ordered_at,
        orders.subtotal,
        orders.tax_paid,
        orders.order_total,
        coalesce(order_items_summary.item_count, 0) as item_count,
        coalesce(order_items_summary.jaffle_count, 0) as jaffle_count,
        coalesce(order_items_summary.beverage_count, 0) as beverage_count
    from orders
    left join order_items_summary
        on orders.order_id = order_items_summary.order_id
)

select * from final
