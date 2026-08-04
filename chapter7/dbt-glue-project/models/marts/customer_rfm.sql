{{ config(
    materialized='table',
    file_format='iceberg'
) }}

with customer_aggregates as (
    select
        customer_id,
        datediff(
            (select max(ordered_at) from {{ ref('rfm_input') }}),
            max(ordered_at)
        ) as recency,
        count(*) as frequency,
        sum(order_total) as monetary
    from {{ ref('rfm_input') }}
    group by customer_id
)

select
    customer_id,
    recency,
    frequency,
    monetary,
    -- recency は小さいほど良いので降順で評価する
    ntile(5) over (order by recency desc) as r_score,
    ntile(5) over (order by frequency)     as f_score,
    ntile(5) over (order by monetary)      as m_score
from customer_aggregates
