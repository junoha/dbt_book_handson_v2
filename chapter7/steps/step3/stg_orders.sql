{{ config(materialized='view') }}

select
    id as order_id,
    customer as customer_id,
    ordered_at,
    store_id,
    cast(subtotal as integer) as subtotal,
    cast(tax_paid as integer) as tax_paid,
    cast(order_total as integer) as order_total,
    cast(nullif(coupon_discount, '') as integer) as coupon_discount
from {{ source('raw', 'raw_orders') }}
