-- 目的:
--   ステージングモデル stg_jaffle_shop__orders の金額カラム (subtotal / tax_paid / order_total) が
--   負の値を取らないことを検証する。
--   本プロジェクトでは返金処理などの負値を許容する業務ルールがなく、
--   負の金額は業務上の想定から外れるため、検出する必要がある。
--
-- 違反行の定義:
--   subtotal / tax_paid / order_total のいずれかが負である行。1 行でもヒットすると fail。

select
    order_id,
    subtotal,
    tax_paid,
    order_total

from {{ ref('stg_jaffle_shop__orders') }}

where subtotal < 0
   or tax_paid < 0
   or order_total < 0
