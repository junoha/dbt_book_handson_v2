{{
  config(
    materialized='view',
    tags=['staging', 'shipment']
  )
}}

with source as (
    select * from {{ source('zakka_mall', 'shipment') }}
),

cleaned as (
    select
        shipment_id,
        order_id,
        tracking_number,
        carrier,
        -- ENUM 型は dbt v2 の DuckDB アダプタが扱えないため varchar に正規化する
        cast(shipment_status as varchar) as shipment_status,
        shipped_date,
        estimated_delivery_date,
        actual_delivery_date,
        created_at,
        updated_at,
        tracking_details,

        -- 配送完了フラグ
        case
            when shipment_status = 'delivered' then true
            else false
        end as is_delivered,

        case
            when shipment_status = 'returned' then true
            else false
        end as is_returned,

        -- リードタイム（shipped_date から actual_delivery_date までの日数）
        case
            when shipped_date is not null and actual_delivery_date is not null
                then actual_delivery_date - shipped_date
            else null
        end as delivery_lead_time_days,

        -- 配送遅延フラグ（予定日より遅れたか）
        case
            when actual_delivery_date is not null and estimated_delivery_date is not null
                then actual_delivery_date > estimated_delivery_date
            else null
        end as is_delayed,

        -- データ品質フラグ
        case
            when shipment_status = 'delivered' and actual_delivery_date is null then false
            when shipped_date is not null and actual_delivery_date is not null and shipped_date > actual_delivery_date then false
            else true
        end as is_valid_record

    from source
)

select * from cleaned
