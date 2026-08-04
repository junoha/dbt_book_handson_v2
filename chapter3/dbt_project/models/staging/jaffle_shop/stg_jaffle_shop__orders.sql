with

source as (

    select * from {{ source('jaffle_shop', 'raw_orders') }}

),

renamed as (

    select

        ---------- ids
        id as order_id,
        customer as customer_id,
        store_id as location_id,

        ---------- numerics
        subtotal,
        tax_paid,
        order_total,

        ---------- timestamps (ソースで timestamp 型として定義済み)
        ordered_at

    from source

)

select * from renamed
