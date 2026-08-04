{{
  config(
    materialized='view',
    tags=['staging', 'payment']
  )
}}

with source as (
    select * from {{ source('zakka_mall', 'payment') }}
),

cleaned as (
    select
        payment_id,
        order_id,
        payment_method,
        payment_status,
        payment_amount,
        payment_date,
        transaction_id,
        gateway_response,
        created_at,
        updated_at,

        -- 決済成否フラグ
        case
            when payment_status = 'completed' then true
            else false
        end as is_completed,

        case
            when payment_status = 'failed' then true
            else false
        end as is_failed,

        case
            when payment_status = 'refunded' then true
            else false
        end as is_refunded,

        -- 決済種別（現金系 vs その他）
        case
            when payment_method in ('cash_on_delivery') then 'cash'
            else 'non_cash'
        end as payment_category,

        -- データ品質フラグ
        case
            when payment_amount < 0 then false
            when payment_status = 'completed' and payment_date is null then false
            else true
        end as is_valid_record

    from source
)

select * from cleaned
