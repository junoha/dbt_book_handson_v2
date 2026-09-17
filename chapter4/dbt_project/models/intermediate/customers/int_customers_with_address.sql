-- 顧客にデフォルト住所を平坦化した intermediate モデル
-- dim_customers の前段として、1 対多の住所関係をデフォルト住所 1 件に絞り込む。
--
-- Grain: 1 row per customer_id
-- 想定利用マート: dim_customers
-- マテリアライゼーション: ephemeral（dbt_project.yml のデフォルト）
--
-- ベストプラクティス的役割: base model 的なパターン
--   （https://docs.getdbt.com/best-practices/how-we-structure/2-staging の "Other considerations" 節）
--   - 1 対多の結合を事前に行うことで、下流のディメンションが SCD Type 2
--     フィールド生成などの本来の責務に専念できる
with
customers as (
    select * from {{ ref('stg_zakka_mall__customers') }}
),

addresses as (
    select * from {{ ref('stg_zakka_mall__customer_addresses') }}
),

-- デフォルト住所のみに絞り込み（顧客 1 人に対して 1 件）
default_addresses as (
    select
        customer_id,
        address_id,
        address_type,
        postal_code,
        prefecture,
        city,
        address_line1,
        address_line2,
        full_address,
        region
    from addresses
    where
        is_default = true
        and is_valid_record = true
),

enriched as (
    select
        -- 顧客プロファイル
        c.customer_id,
        c.customer_name,
        c.email,
        c.phone,
        c.registration_date,
        c.customer_status,
        c.customer_tenure_segment,
        c.created_at,
        c.updated_at,
        c.is_valid_record,

        -- デフォルト住所（存在しない顧客は NULL）
        a.address_id as default_address_id,
        a.address_type as default_address_type,
        a.postal_code as default_postal_code,
        a.prefecture,
        a.city,
        a.address_line1,
        a.address_line2,
        a.full_address,
        a.region,

        -- 住所有無フラグ（配送・請求に利用可能か）
        case
            when a.address_id is null then false
            else true
        end as has_default_address

    from customers as c
    left join default_addresses as a on c.customer_id = a.customer_id
)

select * from enriched
