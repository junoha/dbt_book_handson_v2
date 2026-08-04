-- 顧客ディメンション（SCD Type 2 対応）
-- snapshot_dim_customers（base_dim_customers の履歴）を参照し、
-- dbt が自動生成したメタデータ（dbt_scd_id / dbt_valid_from / dbt_valid_to）を
-- ビジネス向けの命名（customer_key / valid_from / valid_to）に整形する。
--
-- Grain: 1 row per customer_id per validity period
-- Business process: Customer relationship management
--
-- 各行は「ある顧客のある期間（valid_from から valid_to まで）の属性スナップショット」。
-- 現在有効なレコードは valid_to = '9999-12-31'（snapshot の dbt_valid_to_current 設定による）。
-- fct 側からは `on fct.customer_id = dim.customer_id
-- and fct.order_date >= dim.valid_from::date and fct.order_date < dim.valid_to::date`
-- の半開区間で時点マッチ JOIN を行う（境界日の重複マッチを防ぐため BETWEEN は使わない）。
{{
  config(
    materialized='table',
    tags=['dim', 'customer', 'scd2']
  )
}}

select
    -- キー
    dbt_scd_id as customer_key,        -- サロゲートキー（snapshot 自動生成のハッシュ）
    customer_id,                       -- ナチュラルキー（同じ customer_id でも期間ごとに複数レコード）

    -- 業務属性
    customer_name,
    email,
    phone,
    registration_date,
    customer_status,
    customer_tenure_segment,
    prefecture,
    city,
    region,
    full_address,
    has_default_address,

    -- ソース側のタイムスタンプ
    updated_at,

    -- SCD Type 2 の有効期間（dbt snapshot が自動管理）
    dbt_valid_from as valid_from,      -- このバージョンが有効になった時刻
    dbt_valid_to as valid_to           -- このバージョンが無効になった時刻（現在有効なら '9999-12-31'）
from {{ ref('snapshot_dim_customers') }}
