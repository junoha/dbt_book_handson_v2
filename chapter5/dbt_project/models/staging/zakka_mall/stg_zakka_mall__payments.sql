{{
  config(
    materialized='view',
    tags=['staging', 'payment']
  )
}}

with

source as (
    select * from {{ source('zakka_mall', 'payment') }}
),

renamed as (
    select
        -- ids
        payment_id,
        order_id,

        -- strings
        payment_status,
        payment_method,

        -- dates
        payment_date,

        -- numerics
        payment_amount,

        -- timestamps
        created_at,
        updated_at

    from source
)

select * from renamed
