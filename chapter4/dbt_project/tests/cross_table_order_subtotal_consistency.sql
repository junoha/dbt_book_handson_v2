-- 注文ヘッダーの subtotal（税抜小計）と、明細の line_total 合計が一致することを検証する singular data test
with item_subtotals as (
    select
        order_id,
        sum(line_total) as calculated_subtotal
    from {{ ref('stg_zakka_mall__order_items') }}
    where is_valid_record = true
    group by order_id
),

order_subtotals as (
    select
        order_id,
        subtotal as recorded_subtotal
    from {{ ref('stg_zakka_mall__orders') }}
    where is_valid_record = true
)

select
    o.order_id,
    i.calculated_subtotal,
    o.recorded_subtotal,
    abs(i.calculated_subtotal - o.recorded_subtotal) as difference
from order_subtotals as o
inner join item_subtotals as i on o.order_id = i.order_id
where abs(i.calculated_subtotal - o.recorded_subtotal) > 0.01
