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
        case
            when line_total != (quantity * unit_price) then false
            when quantity <= 0 then false
            when unit_price <= 0 then false
            else true
        end as is_valid_record

    from source
)

select * from cleaned
