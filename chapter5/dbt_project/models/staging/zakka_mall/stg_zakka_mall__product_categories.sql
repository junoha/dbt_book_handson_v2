{{
  config(
    materialized='view',
    tags=['staging', 'product']
  )
}}

with

source as (
    select * from {{ source('zakka_mall', 'product_category') }}
),

renamed as (
    select
        -- ids
        category_id,
        parent_category_id,

        -- strings
        category_name,

        -- timestamps
        created_at,
        updated_at

    from source
)

select * from renamed
