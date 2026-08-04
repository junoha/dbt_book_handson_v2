-- Singular Test: 注文と支払いの金額整合性検証
--
-- ビジネスルール:
-- 注文の total_amount と 関連する支払いの payment_amount の合計は一致する必要がある
-- （完了した支払いのみを対象とする）
-- 支払い漏れや重複支払いを検出する

-- 意図的に warn としている
{{ config(severity='warn') }}

with order_payments as (
    select
        o.order_id,
        o.customer_id,
        o.total_amount as order_total,
        sum(
            case
                when p.payment_status = 'completed'
                    then p.payment_amount
                else 0
            end
        ) as completed_payments_total,
        count(
            case
                when p.payment_status = 'completed'
                    then p.payment_id
            end
        ) as completed_payment_count
    from {{ ref('stg_zakka_mall__orders') }} as o
    left join {{ ref('stg_zakka_mall__payments') }} as p
        on o.order_id = p.order_id
    where o.order_status not in ('cancelled', 'refunded')  -- キャンセル・返金注文は除外
    group by o.order_id, o.customer_id, o.total_amount
)

select
    order_id,
    customer_id,
    order_total,
    completed_payments_total,
    completed_payment_count,
    order_total - completed_payments_total as amount_difference,
    case
        when completed_payment_count = 0 then 'NO_PAYMENT'
        when completed_payments_total < order_total then 'UNDERPAID'
        when completed_payments_total > order_total then 'OVERPAID'
        else 'MATCHED'
    end as payment_status_analysis
from order_payments
where
    abs(order_total - completed_payments_total) > 0.01  -- 金額差異がある場合
    and order_total > 0  -- 0円注文は除外
