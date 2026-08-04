-- 注文に支払いと配送の情報を結合した intermediate モデル
-- fct_orders の拡張やオペレーション分析マート（order_processing）の前段として、
-- 注文ごとの決済ステータス・配送ステータス・リードタイムを一元化する。
--
-- Grain: 1 row per order_id
-- 想定利用マート: fct_orders、marts/operations/order_processing
-- マテリアライゼーション: ephemeral（dbt_project.yml のデフォルト）
--
-- ベストプラクティス的役割: Re-grain + 構造簡素化
--   （https://docs.getdbt.com/best-practices/how-we-structure/3-intermediate の "Use cases" 節）
--   - 1 注文に対して支払いや配送が複数発生しうる（分割決済、複数発送）ので
--     注文粒度に集約して後段のマートの JOIN を簡素化
with
orders as (
    select * from {{ ref('stg_zakka_mall__orders') }}
),

payments as (
    select * from {{ ref('stg_zakka_mall__payments') }}
),

shipments as (
    select * from {{ ref('stg_zakka_mall__shipments') }}
),

-- 支払いを注文単位に集約（1 注文に複数決済がある場合を考慮）
payment_summary as (
    select
        order_id,
        count(*) as payment_count,
        sum(payment_amount) as total_paid_amount,
        max(case when is_completed then payment_date end) as latest_completed_payment_date,
        -- いずれかが completed なら成功
        max(case when is_completed then 1 else 0 end)::boolean as has_completed_payment,
        -- いずれかが failed なら決済失敗あり
        max(case when is_failed then 1 else 0 end)::boolean as has_failed_payment,
        -- いずれかが refunded なら返金あり
        max(case when is_refunded then 1 else 0 end)::boolean as has_refunded_payment,
        -- 代表的な支払い方法（集約時は最初の payment_method を採用）
        min(payment_method) as primary_payment_method
    from payments
    where is_valid_record = true
    group by order_id
),

-- 配送を注文単位に集約（1 注文に複数発送がある場合を考慮）
shipment_summary as (
    select
        order_id,
        count(*) as shipment_count,
        min(shipped_date) as earliest_shipped_date,
        max(actual_delivery_date) as latest_delivery_date,
        -- いずれかが delivered なら配達完了
        max(case when is_delivered then 1 else 0 end)::boolean as has_delivered_shipment,
        -- いずれかが returned なら返送あり
        max(case when is_returned then 1 else 0 end)::boolean as has_returned_shipment,
        -- いずれかが delayed なら遅延あり
        max(case when is_delayed then 1 else 0 end)::boolean as has_delayed_shipment,
        avg(delivery_lead_time_days) as avg_delivery_lead_time_days
    from shipments
    where is_valid_record = true
    group by order_id
),

-- 注文ヘッダー + 支払い集約 + 配送集約
enriched as (
    select
        -- 注文ヘッダー
        o.order_id,
        o.customer_id,
        o.order_number,
        o.order_date,
        o.order_status,
        o.total_amount,

        -- 支払い集約
        coalesce(p.payment_count, 0) as payment_count,
        coalesce(p.total_paid_amount, 0) as total_paid_amount,
        p.latest_completed_payment_date,
        coalesce(p.has_completed_payment, false) as has_completed_payment,
        coalesce(p.has_failed_payment, false) as has_failed_payment,
        coalesce(p.has_refunded_payment, false) as has_refunded_payment,
        p.primary_payment_method,

        -- 配送集約
        coalesce(s.shipment_count, 0) as shipment_count,
        s.earliest_shipped_date,
        s.latest_delivery_date,
        coalesce(s.has_delivered_shipment, false) as has_delivered_shipment,
        coalesce(s.has_returned_shipment, false) as has_returned_shipment,
        coalesce(s.has_delayed_shipment, false) as has_delayed_shipment,
        s.avg_delivery_lead_time_days,

        -- 注文フルフィルメントリードタイム（注文日 → 配達日）
        case
            when s.latest_delivery_date is not null
                then s.latest_delivery_date - o.order_date
            else null
        end as order_to_delivery_lead_time_days,

        -- 出荷までのリードタイム（注文日 → 出荷日）
        case
            when s.earliest_shipped_date is not null
                then s.earliest_shipped_date - o.order_date
            else null
        end as order_to_shipment_lead_time_days,

        -- 総合フルフィルメントステータス
        case
            when coalesce(s.has_returned_shipment, false) then 'returned'
            when coalesce(s.has_delivered_shipment, false) and coalesce(p.has_completed_payment, false) then 'completed'
            when coalesce(s.has_delivered_shipment, false) then 'delivered_without_payment'
            when coalesce(p.has_completed_payment, false) then 'paid_not_shipped'
            when coalesce(p.has_failed_payment, false) then 'payment_failed'
            else 'pending'
        end as fulfillment_status

    from orders as o
    left join payment_summary as p on o.order_id = p.order_id
    left join shipment_summary as s on o.order_id = s.order_id
    where o.is_valid_record = true
)

select * from enriched
