-- 商品ディメンション（最新断面のみ）
--
-- Grain: 1 row per product_id（最新の属性を保持）
-- Business process: Product catalog management
--
-- 付録 A は Semantic Layer の紹介に集中するため、第 4 章で扱った SCD Type 2（dbt snapshot）
-- と intermediate 層は採用せず、staging 3 テーブル（products / categories / suppliers）を
-- 直接結合して最新断面のみを保持するシンプル構成とする。
-- semantic layer 側の `sem_products.yml` では、この dim_products の `product_id` を
-- primary entity として参照する。
{{
  config(
    materialized='table',
    tags=['dimensional', 'dimension']
  )
}}

with products as (
    select * from {{ ref('stg_zakka_mall__products') }}
),

categories as (
    select * from {{ ref('stg_zakka_mall__categories') }}
),

suppliers as (
    select * from {{ ref('stg_zakka_mall__suppliers') }}
),

dim_products as (
    select
        -- ナチュラルキー（semantic layer の product entity として利用）
        p.product_id,

        -- 業務属性
        p.product_name,
        p.product_code,
        p.sku,
        p.unit_price,
        p.description,
        p.product_status,
        p.price_tier,

        -- カテゴリ情報
        c.category_id,
        c.category_code,
        c.category_name,
        c.category_path,

        -- 仕入先情報
        s.supplier_id,
        s.supplier_code,
        s.supplier_name,
        s.supplier_status,

        -- メタデータ
        p.updated_at,
        current_timestamp as dbt_created_at
    from products as p
    left join categories as c
        on p.category_id = c.category_id
    left join suppliers as s
        on p.supplier_id = s.supplier_id
    where p.is_valid_record = true
)

select * from dim_products
