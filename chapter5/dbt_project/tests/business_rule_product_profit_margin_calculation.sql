-- Singular Test: 商品の利益率計算検証
--
-- ビジネスルール:
-- 商品の profit_margin は (price - cost) / price で計算される必要がある
-- ただし、price = 0 の場合は特別扱いとし、-100.0 を設定する
-- 計算エラーや手動入力ミスを検出する

select
    product_id,
    product_name,
    price,
    cost,
    profit_margin as recorded_profit_margin,
    case
        when price = 0 then -100.0
        else round((price - cost)::decimal / price::decimal, 3)
    end as calculated_profit_margin,
    case
        when price = 0 and profit_margin != -100.0 then 'ZERO_PRICE_ERROR'
        when price > 0 and abs(profit_margin - round((price - cost)::decimal / price::decimal, 3)) > 0.001 then 'CALCULATION_ERROR'
        else 'OK'
    end as validation_status
from {{ ref('stg_zakka_mall__products') }}
where
    (
        -- 0円商品で profit_margin が -100.0 でない場合
        (price = 0 and profit_margin != -100.0)
        or
        -- 通常商品で計算結果と記録値に差異がある場合（0.1%以上の差）
        (price > 0 and abs(profit_margin - round((price - cost)::decimal / price::decimal, 3)) > 0.001)
    )
