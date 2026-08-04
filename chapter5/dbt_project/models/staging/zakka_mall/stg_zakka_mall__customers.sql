{{
  config(
    materialized='view',
    tags=['staging', 'customer']
  )
}}

with

source as (
    select * from {{ source('zakka_mall', 'customer') }}
),

renamed as (
    select
        -- ids
        customer_id,

        -- strings
        customer_name,
        email,
        phone,
        status,

        -- dates
        registration_date,
        birth_date,

        -- timestamps
        created_at,
        updated_at,

        -- calculated fields
        case
            when birth_date is not null
                then cast(extract(year from age({{ book_current_date() }}, birth_date)) as bigint)
        end as age

    from source
)

select * from renamed
