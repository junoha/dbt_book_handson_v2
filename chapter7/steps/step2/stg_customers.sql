{{ config(
    materialized='table',
    table_type='iceberg',
    format='parquet'
) }}

select
    id as customer_id,
    name as customer_name,
    coalesce(gdpr_deleted, false) as gdpr_deleted
from {{ source('raw', 'raw_customers') }}
