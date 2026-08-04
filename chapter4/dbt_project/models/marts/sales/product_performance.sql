-- 商品パフォーマンス分析マート
-- dim_products × fct_order_items を商品単位に集計し、
-- ランキング・ABC 分析・ライフサイクル分類を付与する。
-- Grain: 1 row per product_id（SCD Type 2 の全期間を集約した商品単位）
--
-- Note: dim_products は SCD Type 2 のため、同じ product_id に対して
-- 複数のバージョン（valid_from / valid_to の期間違い）が存在する。
-- このマートでは product_id 単位で集約するため、dim_products からは
-- product_id をキーに属性情報を取得するだけでよい。
-- fct_order_items は既に product_key（SCD Type 2 のバージョン別キー）で
-- JOIN されているため、注文時点の属性は fct 側に既に反映されている。
{{
  config(
    materialized='table',
    tags=['mart', 'sales', 'product']
  )
}}

with
-- dim_products から現在有効なバージョンの属性を取得
-- snapshots.yml で dbt_valid_to_current: '9999-12-31' を設定しているため、
-- 現在有効な行は valid_to で判定できる（NULL 比較が不要）
products as (
    select
        product_id,
        product_name,
        product_code,
        sku,
        unit_price,
        price_tier,
        category_name,
        supplier_name,
        product_status
    from {{ ref('dim_products') }}
    where valid_to = cast('9999-12-31' as timestamptz)
),

order_items as (
    select * from {{ ref('fct_order_items') }}
),

product_metrics as (
    select
        dp.product_id,
        dp.product_name,
        dp.product_code,
        dp.sku,
        dp.unit_price,
        dp.price_tier,
        dp.category_name,
        dp.supplier_name,
        dp.product_status,

        -- 売上メトリクス
        count(distinct foi.order_id) as order_count,
        coalesce(sum(foi.quantity), 0) as total_quantity_sold,
        coalesce(sum(foi.line_total), 0) as total_sales,
        avg(foi.unit_price) as avg_selling_price,

        -- 顧客メトリクス
        count(distinct foi.customer_id) as unique_customers,

        -- 時間メトリクス
        min(foi.order_date) as first_sale_date,
        max(foi.order_date) as last_sale_date,
        cast('{{ var("analysis_as_of_date") }}' as date) - max(foi.order_date)
            as days_since_last_sale

    from products as dp
    left join order_items as foi on dp.product_id = foi.product_id
    group by
        dp.product_id,
        dp.product_name,
        dp.product_code,
        dp.sku,
        dp.unit_price,
        dp.price_tier,
        dp.category_name,
        dp.supplier_name,
        dp.product_status
),

with_rankings as (
    select
        *,

        -- ランキング
        row_number() over (order by total_sales desc) as sales_rank,
        row_number() over (order by total_quantity_sold desc) as quantity_rank,
        row_number() over (order by unique_customers desc) as customer_rank,

        -- パーセンタイル
        percent_rank() over (order by total_sales) as sales_percentile,

        -- ABC 分析
        case
            when percent_rank() over (order by total_sales desc) <= 0.2 then 'A'
            when percent_rank() over (order by total_sales desc) <= 0.5 then 'B'
            else 'C'
        end as abc_category,

        -- 商品ライフサイクル
        case
            when days_since_last_sale <= 30 then 'Active'
            when days_since_last_sale <= 90 then 'Declining'
            when days_since_last_sale <= 180 then 'At Risk'
            else 'Inactive'
        end as product_lifecycle_stage

    from product_metrics
)

select * from with_rankings
