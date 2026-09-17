-- 顧客ディメンションの最新断面（snapshot の入力）
-- int_customers_with_address（顧客 + デフォルト住所）を入力に、
-- ビジネスに必要な変換処理を適用した「最新断面のみ」のテーブル。
-- このテーブルを dbt snapshot で SCD Type 2 化することで、
-- dim_customers（SCD Type 2 対応）の履歴管理を実現する。
--
-- Grain: 1 row per customer_id（最新状態のみ）
-- 役割: snapshot_dim_customers の入力
-- Business process: Customer relationship management
--
-- Note: このテーブルは snapshot の元データとして機能する。
-- サロゲートキーや SCD Type 2 フィールド（valid_from / valid_to / is_current）は持たない。
-- それらは dbt snapshot が自動的に付与する（dbt_scd_id / dbt_valid_from / dbt_valid_to）。
{{
  config(
    materialized='table',
    tags=['base_dim', 'customer']
  )
}}

select
    customer_id,
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
    -- snapshot の型一致のため timestamptz → timestamp へ。
    -- 変換先のタイムゾーンを明示しないと実行環境のローカル時刻で切り出されてしまうため UTC を指定する。
    cast(updated_at at time zone 'UTC' as timestamp) as updated_at
from {{ ref('int_customers_with_address') }}
where is_valid_record = true
