{{
  config(
    materialized='view',
    tags=['staging', 'customer']
  )
}}

with source as (
    select * from {{ source('zakka_mall', 'customer') }}
),

cleaned as (
    select
        customer_id,
        phone,
        registration_date,
        -- ENUM 型は dbt v2 の DuckDB アダプタが扱えないため varchar に正規化する
        cast(status as varchar) as customer_status,
        created_at,
        updated_at,
        trim(customer_name) as customer_name,
        lower(trim(email)) as email,

        -- 計算フィールド
        case
            when registration_date >= current_date - interval '30 days' then 'new'
            when registration_date >= current_date - interval '365 days' then 'existing'
            else 'long_term'
        end as customer_tenure_segment,

        -- データ品質フラグ
        case
            when customer_name is null or trim(customer_name) = '' then false
            when email is null or trim(email) = '' then false
            when email not like '%@%' then false
            else true
        end as is_valid_record

    from source
)

select * from cleaned
