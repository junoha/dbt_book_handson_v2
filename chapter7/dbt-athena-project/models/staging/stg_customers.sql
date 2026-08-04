{{ config(
    materialized='table',
    table_type='iceberg',
    format='parquet'
) }}

select
    id as customer_id,
    name as customer_name
from {{ source('raw', 'raw_customers') }}
