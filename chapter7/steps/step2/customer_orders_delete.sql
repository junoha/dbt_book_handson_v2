{{ config(
    materialized='incremental',
    table_type='iceberg',
    format='parquet',
    incremental_strategy='merge',
    unique_key='customer_id',
    delete_condition="src.gdpr_deleted = true",
    on_schema_change='append_new_columns'
) }}

with order_summary as (
    select
        customer_id,
        count(*) as order_count,
        sum(order_total) as total_amount,
        min(ordered_at) as first_order_at,
        max(ordered_at) as last_order_at
    from {{ ref('orders') }}
    group by customer_id
)

select
    c.customer_id,
    c.customer_name,
    c.gdpr_deleted,
    coalesce(o.order_count, 0) as order_count,
    coalesce(o.total_amount, 0) as total_amount,
    o.first_order_at,
    o.last_order_at
from {{ ref('stg_customers') }} c
left join order_summary o on c.customer_id = o.customer_id
