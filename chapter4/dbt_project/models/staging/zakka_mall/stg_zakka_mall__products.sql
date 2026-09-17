{{
  config(
    materialized='view',
    tags=['staging', 'product']
  )
}}

with source as (
    select * from {{ source('zakka_mall', 'product') }}
),

cleaned as (
    select
        product_id,
        product_code,
        sku,
        category_id,
        supplier_id,
        unit_price,
        description,
        -- ENUM 型は dbt v2 の DuckDB アダプタが扱えないため varchar に正規化する
        cast(status as varchar) as product_status,
        created_at,
        updated_at,
        specifications,
        trim(product_name) as product_name,

        -- 価格帯区分
        case
            when unit_price < 1000 then 'low'
            when unit_price < 5000 then 'medium'
            when unit_price < 20000 then 'high'
            else 'premium'
        end as price_tier,

        -- データ品質フラグ
        case
            when product_name is null or trim(product_name) = '' then false
            when unit_price is null or unit_price <= 0 then false
            else true
        end as is_valid_record

    from source
)

select * from cleaned
