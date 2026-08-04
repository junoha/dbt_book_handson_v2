-- 顧客ディメンション（最新断面のみ）
--
-- Grain: 1 row per customer_id（最新の属性を保持）
-- Business process: Customer relationship management
--
-- 付録 A は Semantic Layer の紹介に集中するため、第 4 章で扱った SCD Type 2（dbt snapshot）
-- は採用せず、最新断面のみを保持するシンプル構成とする。
-- semantic layer 側の `sem_customers.yml` では、この dim_customers の `customer_id` を
-- primary entity として参照する（第 4 章のようなサロゲートキー customer_key は持たない）。
{{
  config(
    materialized='table',
    tags=['dimensional', 'dimension']
  )
}}

with customers as (
    select * from {{ ref('stg_zakka_mall__customers') }}
),

customer_addresses as (
    select * from {{ ref('stg_zakka_mall__customer_addresses') }}
),

default_addresses as (
    -- 1 顧客 1 行に揃えるため、デフォルト住所のみを採用
    select
        customer_id,
        prefecture,
        city,
        region,
        full_address
    from customer_addresses
    where is_default = true
),

dim_customers as (
    select
        -- ナチュラルキー（semantic layer の customer entity として利用）
        c.customer_id,

        -- 業務属性
        c.customer_name,
        c.email,
        c.phone,
        c.registration_date,
        c.customer_status,
        c.customer_tenure_segment,

        -- 住所情報（デフォルト住所が無い顧客もいるため left join）
        a.prefecture,
        a.city,
        a.region,
        a.full_address,

        -- メタデータ
        c.updated_at,
        current_timestamp as dbt_created_at
    from customers as c
    left join default_addresses as a
        on c.customer_id = a.customer_id
    where c.is_valid_record = true
)

select * from dim_customers
