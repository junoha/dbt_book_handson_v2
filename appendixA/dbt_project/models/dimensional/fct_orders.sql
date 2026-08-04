-- 注文ファクトテーブル
--
-- Grain: 1 row per order_id
-- Business process: EC サイトでの注文確定
--
-- 付録 A は Semantic Layer の紹介に集中するため、第 4 章で扱った intermediate 層や SCD Type 2
-- は採用せず、staging の注文ヘッダーを基点に dim_dates と最新断面で JOIN する
-- シンプル構成とする。dim_customers とはこのモデルでは JOIN せず、semantic layer 側の
-- `sem_orders.yml` で `customer_id` を foreign entity として宣言し、MetricFlow が
-- クエリ時に dim_customers と自動 JOIN する（`order_id` は primary entity）。
{{
  config(
    materialized='table',
    tags=['dimensional', 'fact']
  )
}}

with orders as (
    select * from {{ ref('stg_zakka_mall__orders') }}
),

dates as (
    select * from {{ ref('dim_dates') }}
),

order_facts as (
    select
        -- ナチュラルキー
        o.order_id,
        o.order_number,
        o.order_date,
        o.customer_id,

        -- ディメンションキー
        dd.date_key,

        -- 注文メジャー
        o.subtotal,
        o.tax_amount,
        o.shipping_fee,
        o.total_amount,

        -- 注文属性（categorical dimension）
        o.order_status,
        o.order_size_segment,

        -- 計算メジャー
        1 as order_count,

        -- メタデータ
        o.created_at,
        o.updated_at

    from orders as o
    inner join dates as dd on o.order_date = dd.date_key
    where o.is_valid_record = true
)

select * from order_facts
