{{
  config(
    materialized='view',
    tags=['staging', 'order']
  )
}}

with

source as (
    select * from {{ source('zakka_mall', 'order_header') }}
),

renamed as (
    select
        -- ids
        order_id,
        customer_id,

        -- strings
        order_status,

        -- dates
        order_date,

        -- numerics
        total_amount,
        shipping_fee,
        tax_amount,

        -- timestamps
        created_at,
        updated_at

    from source
)

select * from renamed
