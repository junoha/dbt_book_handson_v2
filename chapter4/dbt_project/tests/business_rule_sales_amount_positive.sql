-- 売上金額が負の値でないことを確認するテスト
select
    order_id,
    total_amount
from {{ ref('sales_obt') }}
where total_amount < 0
