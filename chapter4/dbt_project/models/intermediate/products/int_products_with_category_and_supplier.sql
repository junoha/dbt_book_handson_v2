-- 商品にカテゴリと仕入先を平坦化した intermediate モデル
-- dim_products の前段として、多段の参照関係（商品 → カテゴリ階層、商品 → 仕入先）を
-- 1 つのテーブルにフラット化する。
--
-- Grain: 1 row per product_id
-- 想定利用マート: dim_products
-- マテリアライゼーション: ephemeral（dbt_project.yml のデフォルト）
--
-- ベストプラクティス的役割: 構造の簡素化
--   （https://docs.getdbt.com/best-practices/how-we-structure/3-intermediate の "Use cases" 節）
--   - 4〜6 エンティティの結合を intermediate で処理し、マートの JOIN 数を減らす

with
products as (
    select * from {{ ref('stg_zakka_mall__products') }}
),

categories as (
    select * from {{ ref('stg_zakka_mall__categories') }}
),

suppliers as (
    select * from {{ ref('stg_zakka_mall__suppliers') }}
),

enriched as (
    select
        -- 商品プロファイル
        p.product_id,
        p.product_name,
        p.product_code,
        p.sku,
        p.unit_price,
        p.description,
        p.product_status,
        p.price_tier,
        p.created_at,
        p.updated_at,
        p.is_valid_record,

        -- カテゴリ情報（LTREE 階層を含む）
        p.category_id,
        c.category_code,
        c.category_name,
        c.parent_category_id,
        c.category_path,
        c.is_active as category_is_active,

        -- 仕入先情報
        p.supplier_id,
        s.supplier_code,
        s.supplier_name,
        s.contact_email as supplier_contact_email,
        s.contact_phone as supplier_contact_phone,
        s.supplier_status,

        -- 結合有効性フラグ（カテゴリや仕入先が見つからない場合を検知）
        case
            when c.category_id is null then false
            when s.supplier_id is null then false
            else true
        end as has_valid_references

    from products as p
    left join categories as c on p.category_id = c.category_id
    left join suppliers as s on p.supplier_id = s.supplier_id
)

select * from enriched
