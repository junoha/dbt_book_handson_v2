{{
  config(
    materialized='view',
    tags=['staging', 'order']
  )
}}

with

source as (
    select * from {{ source('zakka_mall', 'order_detail') }}
),

renamed as (
    select
        -- ids
        order_detail_id,
        order_id,
        product_id,

        -- numerics
        quantity,
        unit_price,
        line_total,

        -- timestamps
        created_at

    from source
)

select * from renamed
