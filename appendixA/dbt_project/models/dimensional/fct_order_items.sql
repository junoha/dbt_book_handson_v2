-- 注文明細ファクトテーブル
--
-- Grain: 1 row per order_item_id（注文明細単位）
-- Business process: EC サイトでの注文明細
--
-- 付録 A の sem_orders.yml からは直接参照していないが、商品粒度のメトリクス
-- （例: 商品別の売上数量など）を将来 Semantic Layer で扱う際の入力となる。
{{
  config(
    materialized='table',
    tags=['dimensional', 'fact']
  )
}}

with order_items as (
    select * from {{ ref('stg_zakka_mall__order_items') }}
),

orders as (
    select * from {{ ref('stg_zakka_mall__orders') }}
),

dates as (
    select * from {{ ref('dim_dates') }}
),

order_item_facts as (
    select
        -- ナチュラルキー
        oi.order_item_id,
        oi.order_id,
        oi.product_id,
        o.customer_id,
        o.order_date,

        -- ディメンションキー
        dd.date_key,

        -- メジャー
        oi.quantity,
        oi.unit_price,
        oi.line_total,

        -- 明細属性
        oi.quantity_type,

        -- 計算メジャー
        1 as order_item_count,

        -- メタデータ
        oi.created_at

    from order_items as oi
    inner join orders as o on oi.order_id = o.order_id
    inner join dates as dd on o.order_date = dd.date_key
    where oi.is_valid_record = true and o.is_valid_record = true
)

select * from order_item_facts
