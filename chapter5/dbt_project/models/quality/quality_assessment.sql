{{
  config(
    tags=['quality', 'assessment']
  )
}}

-- データ品質アセスメント: DMBOK ベースの品質ディメンション評価
with completeness_checks as (
    -- customers テーブルの完全性チェック
    {{ calculate_completeness('customer_id', ref('stg_zakka_mall__customers')) }}
    union all

    {{ calculate_completeness('email', ref('stg_zakka_mall__customers')) }}
    union all

    -- orders テーブルの完全性チェック
    {{ calculate_completeness('order_id', ref('stg_zakka_mall__orders')) }}
    union all

    {{ calculate_completeness('customer_id', ref('stg_zakka_mall__orders')) }}
    union all

    -- products テーブルの完全性チェック
    {{ calculate_completeness('product_id', ref('stg_zakka_mall__products')) }}
    union all

    {{ calculate_completeness('price', ref('stg_zakka_mall__products')) }}
    union all

    -- order_details テーブルの完全性チェック
    {{ calculate_completeness('order_detail_id', ref('stg_zakka_mall__order_details')) }}
    union all

    {{ calculate_completeness('order_id', ref('stg_zakka_mall__order_details')) }}
    union all

    {{ calculate_completeness('quantity', ref('stg_zakka_mall__order_details')) }}
    union all

    {{ calculate_completeness('line_total', ref('stg_zakka_mall__order_details')) }}
),

uniqueness_checks as (
    -- 一意性チェック
    {{ calculate_uniqueness('customer_id', ref('stg_zakka_mall__customers')) }}
    union all

    -- customer_id と email は主キー・ユニーク制約により構造上必ず 100% になる。
    -- 実務で問題になるのは制約のかかっていない項目の重複なので、顧客名も測定対象に含める
    {{ calculate_uniqueness('customer_name', ref('stg_zakka_mall__customers')) }}
    union all

    {{ calculate_uniqueness('email', ref('stg_zakka_mall__customers')) }}
    union all

    {{ calculate_uniqueness('order_id', ref('stg_zakka_mall__orders')) }}
    union all

    {{ calculate_uniqueness('product_id', ref('stg_zakka_mall__products')) }}
    union all

    {{ calculate_uniqueness('order_detail_id', ref('stg_zakka_mall__order_details')) }}
),

validity_checks as (
    -- 妥当性チェック
    {{ calculate_validity('email', ref('stg_zakka_mall__customers'), "email like '%@%'") }}
    union all

    {{ calculate_validity('price', ref('stg_zakka_mall__products'), "price > " ~ var('min_product_price')) }}
    union all

    {{ calculate_validity('age', ref('stg_zakka_mall__customers'), "age between 0 and " ~ var('max_customer_age')) }}
    union all

    -- order_details の数量妥当性（business_impact.csv の key_field=quantity と整合）
    {{ calculate_validity('quantity', ref('stg_zakka_mall__order_details'), "quantity > 0") }}
    union all

    -- order_details の明細合計が正の値であること
    {{ calculate_validity('line_total', ref('stg_zakka_mall__order_details'), "line_total > 0") }}
),

consistency_checks as (
-- 一貫性チェック（クロステーブル検証）
    {{ calculate_consistency(
        'customer_id',
        ref('stg_zakka_mall__customers'),
        ref('stg_zakka_mall__orders')
    ) }}
    union all

    -- order_details.order_id は orders.order_id を参照する
    {{ calculate_consistency(
        'order_id',
        ref('stg_zakka_mall__orders'),
        ref('stg_zakka_mall__order_details')
    ) }}
    union all

    -- 注文金額と支払金額の突合。同じ金額が注文側と支払側の 2 か所に
    -- 保持されているため、両者が一致しているかを一貫性として測定する
    {{ calculate_amount_consistency(
        'payment_amount',
        ref('stg_zakka_mall__orders'),
        ref('stg_zakka_mall__payments'),
        'order_id',
        'total_amount',
        'payment_amount'
    ) }}
)

-- 全ての品質チェック結果を統合
select
    column_name,
    table_name,
    quality_dimension,
    total_records,
    quality_status,
    coalesce(non_null_records, unique_records, valid_records, consistent_records) as quality_records,
    coalesce(completeness_percentage, uniqueness_percentage, validity_percentage, consistency_percentage) as quality_score,
    current_timestamp as assessment_timestamp
from (
    select
        column_name, table_name, quality_dimension, total_records, quality_status,
        non_null_records, null::bigint as unique_records, null::bigint as valid_records, null::bigint as consistent_records,
        completeness_percentage, null::numeric as uniqueness_percentage, null::numeric as validity_percentage, null::numeric as consistency_percentage
    from completeness_checks

    union all

    select
        column_name, table_name, quality_dimension, total_records, quality_status,
        null::bigint as non_null_records, unique_records, null::bigint as valid_records, null::bigint as consistent_records,
        null::numeric as completeness_percentage, uniqueness_percentage, null::numeric as validity_percentage, null::numeric as consistency_percentage
    from uniqueness_checks

    union all

    select
        column_name, table_name, quality_dimension, total_records, quality_status,
        null::bigint as non_null_records, null::bigint as unique_records, valid_records, null::bigint as consistent_records,
        null::numeric as completeness_percentage, null::numeric as uniqueness_percentage, validity_percentage, null::numeric as consistency_percentage
    from validity_checks

    union all

    select
        column_name, table_name, quality_dimension, total_records, quality_status,
        null::bigint as non_null_records, null::bigint as unique_records, null::bigint as valid_records, consistent_records,
        null::numeric as completeness_percentage, null::numeric as uniqueness_percentage, null::numeric as validity_percentage, consistency_percentage
    from consistency_checks
) as all_checks

order by table_name, quality_dimension, column_name
