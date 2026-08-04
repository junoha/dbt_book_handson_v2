{{
  config(
    materialized='view',
    tags=['staging', 'product']
  )
}}

with

source as (
    select * from {{ source('zakka_mall', 'product') }}
),

renamed as (
    select
        -- ids
        product_id,
        category_id,

        -- strings
        product_name,

        -- numerics
        price,
        cost,
        stock_quantity,

        -- booleans
        is_active,

        -- timestamps
        created_at,
        updated_at,

        -- calculated fields
        case
            when cost is not null and cost > 0 and price > 0
                then round(((price - cost) / price * 100)::numeric(10, 2), 2)
            when (cost is null or cost = 0) and price > 0
                then 100.00::numeric(10, 2)
            when (price is null or price = 0) and cost > 0
                then -100.00::numeric(10, 2)
            else null
        end as profit_margin

    from source
)

select * from renamed
