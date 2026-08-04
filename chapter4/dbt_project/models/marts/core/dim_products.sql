-- 商品ディメンション（SCD Type 2 対応）
-- snapshot_dim_products（base_dim_products の履歴）を参照し、
-- dbt が自動生成したメタデータ（dbt_scd_id / dbt_valid_from / dbt_valid_to）を
-- ビジネス向けの命名（product_key / valid_from / valid_to）に整形する。
--
-- Grain: 1 row per product_id per validity period
-- Business process: Product catalog management
--
-- 各行は「ある商品のある期間（valid_from から valid_to まで）の属性スナップショット」。
-- 現在有効なレコードは valid_to = '9999-12-31'（snapshot の dbt_valid_to_current 設定による）。
-- fct 側からは `on fct.product_id = dim.product_id
-- and fct.order_date >= dim.valid_from::date and fct.order_date < dim.valid_to::date`
-- の半開区間で時点マッチ JOIN を行う（境界日の重複マッチを防ぐため BETWEEN は使わない）。
{{
  config(
    materialized='table',
    tags=['dim', 'product', 'scd2']
  )
}}

select
    -- キー
    dbt_scd_id as product_key,         -- サロゲートキー（snapshot 自動生成のハッシュ）
    product_id,                        -- ナチュラルキー

    -- 業務属性
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

    -- ソース側のタイムスタンプ
    updated_at,

    -- SCD Type 2 の有効期間（dbt snapshot が自動管理）
    dbt_valid_from as valid_from,
    dbt_valid_to as valid_to
from {{ ref('snapshot_dim_products') }}
