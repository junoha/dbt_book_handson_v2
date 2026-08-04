-- オペレーション分析マート
-- fct_orders を軸に dim_customers / dim_dates を結合し、
-- 注文処理の効率・配送パフォーマンス・決済成功率を可視化するマート。
-- Grain: 1 row per order_id
-- Business process: EC サイトでの注文処理・決済・配送のオペレーション分析
{{
  config(
    materialized='table',
    tags=['mart', 'operations', 'order_processing']
  )
}}

with
orders as (
    select * from {{ ref('fct_orders') }}
),

customers as (
    -- fct_orders が持つ customer_key で結合する。fct 構築時に期間マッチ
    -- （注文日が valid_from 〜 valid_to に入るバージョンの選択）を解決済みのため、
    -- 下流では customer_key の等値結合だけで注文時点の属性が得られる
    select * from {{ ref('dim_customers') }}
),

dates as (
    select * from {{ ref('dim_dates') }}
),

order_processing_detail as (
    select
        -- 注文識別子（fct_orders から）
        fo.order_id,
        fo.order_number,
        fo.order_date,
        fo.customer_id,

        -- ディメンションキー（fct_orders に既に付与されている）
        fo.customer_key,
        fo.date_key,

        -- 顧客属性（オペレーション分析で使う粒度）
        dc.customer_name,
        dc.region as customer_region,
        dc.prefecture as customer_prefecture,

        -- 日付属性
        dd.year,
        dd.month,
        dd.quarter,
        dd.weekday_flag,

        -- 注文ステータス
        fo.order_status,
        fo.fulfillment_status,

        -- 決済メトリクス
        fo.payment_count,
        fo.total_paid_amount,
        fo.has_completed_payment,
        fo.has_failed_payment,
        fo.has_refunded_payment,
        fo.primary_payment_method,

        -- 配送メトリクス
        fo.shipment_count,
        fo.earliest_shipped_date,
        fo.latest_delivery_date,
        fo.has_delivered_shipment,
        fo.has_returned_shipment,
        fo.has_delayed_shipment,
        fo.avg_delivery_lead_time_days,

        -- リードタイムメトリクス
        fo.order_to_delivery_lead_time_days,
        fo.order_to_shipment_lead_time_days,

        -- 注文金額
        fo.total_amount,

        -- リードタイム分類
        case
            when fo.order_to_delivery_lead_time_days is null then 'not_delivered'
            when fo.order_to_delivery_lead_time_days <= 3 then 'fast'
            when fo.order_to_delivery_lead_time_days <= 7 then 'standard'
            when fo.order_to_delivery_lead_time_days <= 14 then 'slow'
            else 'very_slow'
        end as delivery_speed_category,

        -- オペレーション問題フラグ（返送・遅延・決済失敗のいずれか）
        case
            when fo.has_returned_shipment or fo.has_delayed_shipment or fo.has_failed_payment then true
            else false
        end as has_operational_issue

    from orders as fo
    left join customers as dc on fo.customer_key = dc.customer_key
    inner join dates as dd on fo.date_key = dd.date_key
)

select * from order_processing_detail
