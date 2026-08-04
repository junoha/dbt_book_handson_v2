{{
  config(
    materialized='view',
    tags=['staging', 'master']
  )
}}

with source as (
    select * from {{ source('zakka_mall', 'supplier') }}
),

cleaned as (
    select
        supplier_id,
        supplier_code,
        supplier_name,
        contact_email,
        contact_phone,
        address,
        status as supplier_status,
        created_at,
        updated_at,

        -- データ品質フラグ
        case
            when supplier_name is null or trim(supplier_name) = '' then false
            when supplier_code is null or trim(supplier_code) = '' then false
            else true
        end as is_valid_record

    from source
)

select * from cleaned
