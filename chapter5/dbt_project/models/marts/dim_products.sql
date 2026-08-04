{{
  config(
    materialized='table',
    tags=['mart', 'product']
  )
}}

with

products as (
    select * from {{ ref('stg_zakka_mall__products') }}
),

categories as (
    select * from {{ ref('stg_zakka_mall__product_categories') }}
),

order_details as (
    select * from {{ ref('stg_zakka_mall__order_details') }}
),

orders as (
    select * from {{ ref('stg_zakka_mall__orders') }}
),

product_sales as (
    -- 販売実績の集計。total_profit は「販売時点の単価 (od.unit_price) - 現在の原価 (p.cost)」で
    -- 計算するため、商品マスタ (p) を inner join している。価格改定後に過去の販売分が
    -- 巻き戻って再計算されないよう、売上・利益ともに order_details.unit_price を基準にする。
    select
        od.product_id,
        sum(od.quantity) as total_sold_quantity,
        sum(od.line_total)::numeric(15, 2) as total_revenue,
        count(distinct o.order_id) as total_orders,
        sum(
            case
                when p.cost is not null
                    then (od.unit_price - p.cost) * od.quantity
                else 0
            end
        )::numeric(15, 2) as total_profit
    from order_details as od
    inner join orders as o on od.order_id = o.order_id
    inner join {{ ref('stg_zakka_mall__products') }} as p on od.product_id = p.product_id
    where o.order_status not in ('cancelled', 'refunded')
    group by od.product_id
),

final as (
    select
        p.product_id,
        p.product_name,
        c.category_name,
        p.price,
        p.cost,
        p.profit_margin,
        p.stock_quantity,
        p.is_active,

        -- 販売実績
        coalesce(ps.total_sold_quantity, 0) as total_sold_quantity,
        coalesce(ps.total_revenue, 0)::numeric(15, 2) as total_revenue,
        coalesce(ps.total_orders, 0) as total_orders,

        -- 利益（unit_price は販売時点・cost は現時点ベース）: 詳細は product_sales CTE のコメントを参照
        coalesce(ps.total_profit, 0)::numeric(15, 2) as total_profit

    from products as p
    left join categories as c on p.category_id = c.category_id
    left join product_sales as ps on p.product_id = ps.product_id
)

select * from final
