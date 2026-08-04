-- 目的:
--   マートモデル orders の order_total が subtotal + tax_paid と一致することを検証する。
--   本プロジェクトでは「order_total は税込合計」と定義しており、subtotal (税抜) と
--   tax_paid (消費税) の和に一致することを業務ルールとして要求する。

-- 違反行の定義:
--   order_total と (subtotal + tax_paid) の差が 0 でない行。1 行でもヒットすると fail。

select
    order_id,
    subtotal,
    tax_paid,
    order_total,
    order_total - (subtotal + tax_paid) as diff

from {{ ref('orders') }}

where order_total <> subtotal + tax_paid
