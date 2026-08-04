{{ config(
    materialized='table',
    file_format='iceberg'
) }}

select
    order_id,
    customer_id,
    ordered_at,
    order_total
from {{ ref('jaffle_shop_iceberg', 'orders') }}
