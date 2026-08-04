{{
  config(
    materialized='view',
    tags=['staging', 'order']
  )
}}

with source as (
    select * from {{ source('zakka_mall', 'order') }}
),

cleaned as (
    select
        order_id,
        customer_id,
        order_number,
        order_date,
        order_status,
        subtotal,
        tax_amount,
        shipping_fee,
        total_amount,
        shipping_address_id,
        billing_address_id,
        created_at,
        updated_at,
        order_metadata,

        -- 時間ディメンション
        extract(year from order_date) as order_year,
        extract(month from order_date) as order_month,
        extract(day from order_date) as order_day,
        extract(dow from order_date) as order_day_of_week,
        extract(quarter from order_date) as order_quarter,

        -- 曜日名
        case extract(dow from order_date)
            when 0 then '日曜日'
            when 1 then '月曜日'
            when 2 then '火曜日'
            when 3 then '水曜日'
            when 4 then '木曜日'
            when 5 then '金曜日'
            when 6 then '土曜日'
        end as order_day_name,

        -- 注文金額区分
        case
            when total_amount < 3000 then 'small'
            when total_amount < 10000 then 'medium'
            when total_amount < 30000 then 'large'
            else 'extra_large'
        end as order_size_segment,

        -- データ品質フラグ
        -- Note: total_amount = subtotal + tax_amount + shipping_fee の整合性は
        -- PostgreSQL の GENERATED ALWAYS AS で物理保証されているため、ここでは検証しない。
        -- order と order_item 間の整合性（subtotal = sum(line_total)）は
        -- tests/cross_table_order_subtotal_consistency.sql で別途検証する。
        case
            when total_amount <= 0 then false
            else true
        end as is_valid_record

    from source
)

select * from cleaned
