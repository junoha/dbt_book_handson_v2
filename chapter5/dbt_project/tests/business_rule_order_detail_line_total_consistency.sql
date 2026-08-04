-- Singular Test: 注文明細の行合計値整合性検証
-- 
-- ビジネスルール:
-- 注文明細の line_total は quantity * unit_price と一致する必要がある
-- 不正な計算や手動入力エラーを検出する

select
    order_detail_id,
    order_id,
    product_id,
    quantity,
    unit_price,
    line_total,
    quantity * unit_price as calculated_line_total,
    abs(line_total - (quantity * unit_price)) as difference
from {{ ref('stg_zakka_mall__order_details') }}
where abs(line_total - (quantity * unit_price)) > 0.01  -- 浮動小数点の誤差を考慮
