{{
  config(
    materialized='view',
    tags=['staging', 'master']
  )
}}

with source as (
    select * from {{ source('zakka_mall', 'category') }}
),

cleaned as (
    select
        category_id,
        category_code,
        category_name,
        parent_category_id,
        description,
        is_active,
        category_path,
        created_at,
        updated_at,

        -- データ品質フラグ
        case
            when category_name is null or trim(category_name) = '' then false
            when category_code is null or trim(category_code) = '' then false
            else true
        end as is_valid_record

    from source
)

select * from cleaned
