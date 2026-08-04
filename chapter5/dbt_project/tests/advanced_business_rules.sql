-- 高度なビジネスルール検証: 注文と支払いの整合性
-- 複数テーブルにまたがる複雑なロジックのテスト
--
-- order_status の取りうる値（_zakka_mall__sources.yml の accepted_values と一致）:
--   pending / processing / shipped / delivered / cancelled / refunded
-- 「支払いが完了しているべき状態」は出荷以降（shipped / delivered）として扱う。

-- 意図的に warn としている
{{ config(severity='warn') }}

with order_payment_summary as (
    select
        o.order_id,
        o.total_amount as order_total,
        o.order_status,
        coalesce(sum(p.payment_amount), 0) as payment_total,
        count(p.payment_id) as payment_count
    from {{ ref('fct_orders') }} as o
    left join {{ ref('stg_zakka_mall__payments') }} as p
        on o.order_id = p.order_id
    group by o.order_id, o.total_amount, o.order_status
),

inconsistencies as (
    select
        *,
        case
            -- 出荷以降の注文は支払い完了しているはず（金額不一致）
            when order_status in ('shipped', 'delivered')
                and abs(order_total - payment_total) > 1
                then 'payment_amount_mismatch'
            -- 出荷以降の注文に支払いレコードが 1 件もない
            when order_status in ('shipped', 'delivered')
                and payment_count = 0
                then 'missing_payment'
            -- 受付・処理中なのに過払い
            when order_status in ('pending', 'processing')
                and payment_total > order_total
                then 'overpayment'
            -- キャンセル注文に支払いが残っている（返金処理が必要なケース）
            when order_status = 'cancelled'
                and payment_total > 0
                then 'payment_for_cancelled_order'
        end as inconsistency_type
    from order_payment_summary
)

select
    order_id,
    order_total,
    payment_total,
    order_status,
    payment_count,
    inconsistency_type
from inconsistencies
where inconsistency_type is not null
