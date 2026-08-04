{{ config(
    materialized='incremental',
    table_type='iceberg',
    format='parquet',
    incremental_strategy='append',
    partitioned_by=['day(ordered_at)'],
    on_schema_change='append_new_columns'
) }}

select
    order_id,
    customer_id,
    cast(from_iso8601_timestamp(ordered_at) as timestamp(6)) as ordered_at,
    store_id,
    subtotal,
    tax_paid,
    order_total,
    coupon_discount
from {{ ref('stg_orders') }}

{% if is_incremental() %}
where cast(from_iso8601_timestamp(ordered_at) as timestamp(6)) > (select max(ordered_at) from {{ this }})
{% endif %}
