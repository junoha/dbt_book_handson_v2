-- 注文ヘッダーに明細レベルの集計値を roll-up した intermediate モデル
-- ファクトテーブル（fct_orders）の前段として、明細の集計を注文単位に集約する。
--
-- Grain: 1 row per order_id（注文単位）
-- 想定利用マート: fct_orders
-- マテリアライゼーション: ephemeral（dbt_project.yml のデフォルト）
--
-- ベストプラクティス的役割: Re-grain（roll-up）
--   - OLTP の明細粒度を注文粒度に roll-up
--   - 下流モデルで明細を展開して集計するときに行が膨らむ問題を防ぐ
with
orders as (
    select * from {{ ref('stg_zakka_mall__orders') }}
),

order_items as (
    select * from {{ ref('stg_zakka_mall__order_items') }}
),

-- 注文単位に明細情報を集約
items_aggregated as (
    select
        order_id,
        count(*) as item_count,
        sum(quantity) as total_quantity,
        sum(line_total) as items_total,
        min(unit_price) as min_item_price,
        max(unit_price) as max_item_price,
        avg(unit_price) as avg_item_price
    from order_items
    where is_valid_record = true
    group by order_id
),

-- 注文ヘッダーと集約済み明細を結合
enriched as (
    select
        -- 注文ヘッダー情報
        o.order_id,
        o.customer_id,
        o.order_number,
        o.order_date,
        o.order_status,
        o.subtotal,
        o.tax_amount,
        o.shipping_fee,
        o.total_amount,
        o.shipping_address_id,
        o.billing_address_id,
        o.created_at,
        o.updated_at,
        o.order_metadata,
        o.order_year,
        o.order_month,
        o.order_day,
        o.order_day_of_week,
        o.order_quarter,
        o.order_day_name,
        o.order_size_segment,
        o.is_valid_record as is_valid_order,

        -- 明細からの集約値
        coalesce(i.item_count, 0) as item_count,
        coalesce(i.total_quantity, 0) as total_quantity,
        coalesce(i.items_total, 0) as items_total,
        i.min_item_price,
        i.max_item_price,
        i.avg_item_price,

        -- データ品質チェック（注文ヘッダーの合計と明細合計の整合性）
        case
            when i.items_total is null then null  -- 明細がない注文
            when abs(o.subtotal - i.items_total) < 0.01 then true
            else false
        end as is_total_consistent

    from orders as o
    left join items_aggregated as i on o.order_id = i.order_id
)

select * from enriched
