-- 商品ディメンションの最新断面（snapshot の入力）
-- int_products_with_category_and_supplier（商品 + カテゴリ + 仕入先）を入力に、
-- ビジネスに必要な変換処理を適用した「最新断面のみ」のテーブル。
-- このテーブルを dbt snapshot で SCD Type 2 化することで、
-- dim_products（SCD Type 2 対応）の履歴管理を実現する。
--
-- Grain: 1 row per product_id（最新状態のみ）
-- 役割: snapshot_dim_products の入力
-- Business process: Product catalog management
--
-- Note: このテーブルは snapshot の元データとして機能する。
-- サロゲートキーや SCD Type 2 フィールド（valid_from / valid_to / is_current）は持たない。
-- それらは dbt snapshot が自動的に付与する（dbt_scd_id / dbt_valid_from / dbt_valid_to）。
{{
  config(
    materialized='table',
    tags=['base_dim', 'product']
  )
}}

select
    product_id,
    product_name,
    product_code,
    sku,
    unit_price,
    description,
    product_status,
    price_tier,

    -- カテゴリ情報（intermediate で結合済み）
    category_id,
    category_code,
    category_name,
    category_path,

    -- 仕入先情報（intermediate で結合済み）
    supplier_id,
    supplier_code,
    supplier_name,
    supplier_status,

    cast(updated_at as timestamp) as updated_at  -- snapshot の型一致のため timestamptz → timestamp へ
from {{ ref('int_products_with_category_and_supplier') }}
where is_valid_record = true
