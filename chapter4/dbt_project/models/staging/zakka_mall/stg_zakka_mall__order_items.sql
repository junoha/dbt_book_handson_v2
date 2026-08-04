{{
  config(
    materialized='view',
    tags=['staging', 'order']
  )
}}

with source as (
    select * from {{ source('zakka_mall', 'order_item') }}
),

cleaned as (
    select
        order_item_id,
        order_id,
        product_id,
        quantity,
        unit_price,
        line_total,
        created_at,
        item_metadata,

        -- 計算フィールド
        case
            when quantity > 1 then 'multiple'
            else 'single'
        end as quantity_type,

        -- データ品質フラグ
        -- Note: line_total = quantity * unit_price の整合性は
        -- PostgreSQL の GENERATED ALWAYS AS で物理保証されているため、ここでは検証しない。
        -- staging では DB 制約に頼れないビジネスルール（数量・単価が正の値か）のみを検証する。
        case
            when quantity <= 0 then false
            when unit_price <= 0 then false
            else true
        end as is_valid_record

    from source
)

select * from cleaned
