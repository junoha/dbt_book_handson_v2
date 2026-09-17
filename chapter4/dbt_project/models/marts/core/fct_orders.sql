-- 注文ファクトテーブル
-- int_orders_with_items（明細集約）と int_orders_with_payment_shipment（支払い・配送）を
-- 結合し、ディメンションキーを付与した注文粒度のファクト。
-- Grain: 1 row per order_id
-- Business process: EC サイトでの注文確定
{{
  config(
    materialized='table',
    tags=['fct', 'orders']
  )
}}

with
orders_with_items as (
    select * from {{ ref('int_orders_with_items') }}
),

orders_with_payment_shipment as (
    select * from {{ ref('int_orders_with_payment_shipment') }}
),

customers as (
    select * from {{ ref('dim_customers') }}
),

dates as (
    select * from {{ ref('dim_dates') }}
),

order_facts as (
    select
        oi.order_id,
        oi.order_number,
        oi.order_date,
        oi.customer_id,

        -- ディメンションキー
        dc.customer_key,
        dd.date_key,

        -- 注文メジャー（ヘッダー）
        oi.subtotal,
        oi.tax_amount,
        oi.shipping_fee,
        oi.total_amount,

        -- 明細集約メジャー（int_orders_with_items より）
        oi.item_count,
        oi.total_quantity,
        oi.items_total,
        oi.min_item_price,
        oi.max_item_price,
        oi.avg_item_price,

        -- 支払い・配送サマリ（int_orders_with_payment_shipment より）
        ps.payment_count,
        ps.total_paid_amount,
        ps.has_completed_payment,
        ps.has_failed_payment,
        ps.has_refunded_payment,
        ps.primary_payment_method,
        ps.shipment_count,
        ps.earliest_shipped_date,
        ps.latest_delivery_date,
        ps.has_delivered_shipment,
        ps.has_returned_shipment,
        ps.has_delayed_shipment,
        ps.avg_delivery_lead_time_days,
        ps.order_to_delivery_lead_time_days,
        ps.order_to_shipment_lead_time_days,
        ps.fulfillment_status,

        -- 注文属性
        oi.order_status,
        oi.order_size_segment,

        -- 計算メジャー
        1 as order_count,

        -- データ品質
        oi.is_total_consistent,

        -- メタデータ
        oi.created_at,
        oi.updated_at

    from orders_with_items as oi
    left join orders_with_payment_shipment as ps on oi.order_id = ps.order_id
    left join customers as dc
        on
            oi.customer_id = dc.customer_id
            and oi.order_date >= dc.valid_from::date
            and oi.order_date < dc.valid_to::date
    inner join dates as dd on oi.order_date = dd.date_key
    where oi.is_valid_order = true
)

select * from order_facts
