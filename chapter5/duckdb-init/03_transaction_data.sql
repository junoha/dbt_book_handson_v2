/*
v1 版（PostgreSQL）の init-scripts/03_transaction_data.sql から生成した DuckDB 版。
PostgreSQL 版との違いは次の 1 点のみ。
  - search_path の指定を SET search_path に置き換え、SET TimeZone = 'UTC' を追加
    （PostgreSQL コンテナと同じ解釈で CURRENT_DATE 相対のデータを取り込むため）
*/
/*
トランザクションデータの投入 - 第5章データ品質管理用

日付はすべて CURRENT_DATE 相対で指定する。読者がいつ環境を構築しても、
Source Freshness や月次トレンド分析が同じ結果になるようにするため。

created_at / updated_at には明示的な時刻を持たせる。省略すると DEFAULT NOW()
により全行がコンテナ起動時刻になり、時間帯の異常検知テストが
実行時刻に依存してしまう。
*/

SET search_path = 'zakka_mall';
SET TimeZone = 'UTC';

-- 注文データ（品質問題を含む）
-- 月次トレンド分析（tests/seasonal_business_patterns.sql）は同じ月を複数年で比較するため、
-- 2 年前・1 年前の同月にもデータを配置している。
-- ZakkaMall は毎年この月に夏のセールを実施しており、例年は月商 15 万円前後で安定している想定とする
-- 当月（04_quality_issues_data.sql で投入）はこの水準を大きく下回るため、
-- 月次トレンドの異常として検知される
INSERT INTO order_header (
    customer_id, order_date, order_status, total_amount, shipping_fee, tax_amount, created_at, updated_at
) VALUES
-- 正常データ（2 年前の同月。セール月のため月商 14.8 万円）
(1, (CURRENT_DATE - INTERVAL '24 months')::date, 'delivered', 89800.00, 800.00, 8980.00,
    (CURRENT_DATE - INTERVAL '24 months')::date + TIME '10:15:00', (CURRENT_DATE - INTERVAL '24 months')::date + TIME '10:15:00'),
(2, (CURRENT_DATE - INTERVAL '24 months')::date + 3, 'delivered', 58200.00, 1200.00, 5820.00,
    (CURRENT_DATE - INTERVAL '24 months')::date + 3 + TIME '14:40:00', (CURRENT_DATE - INTERVAL '24 months')::date + 3 + TIME '14:40:00'),

-- 正常データ（1 年前の同月。セール月のため月商 16.2 万円）
(3, (CURRENT_DATE - INTERVAL '12 months')::date, 'delivered', 94500.00, 600.00, 9450.00,
    (CURRENT_DATE - INTERVAL '12 months')::date + TIME '11:05:00', (CURRENT_DATE - INTERVAL '12 months')::date + TIME '11:05:00'),
(5, (CURRENT_DATE - INTERVAL '12 months')::date + 5, 'shipped', 67500.00, 500.00, 6750.00,
    (CURRENT_DATE - INTERVAL '12 months')::date + 5 + TIME '16:20:00', (CURRENT_DATE - INTERVAL '12 months')::date + 5 + TIME '16:20:00'),

-- 正常データ（直近数か月）
(2, (CURRENT_DATE - INTERVAL '5 months')::date, 'delivered', 4500.00, 300.00, 450.00,
    (CURRENT_DATE - INTERVAL '5 months')::date + TIME '13:30:00', (CURRENT_DATE - INTERVAL '5 months')::date + TIME '13:30:00'),

-- 品質問題のあるデータ
(6, (CURRENT_DATE - INTERVAL '4 months')::date, 'pending', 12800.00, 400.00, 1280.00,
    (CURRENT_DATE - INTERVAL '4 months')::date + TIME '09:45:00', (CURRENT_DATE - INTERVAL '4 months')::date + TIME '09:45:00'), -- 支払いが完了しないまま放置された注文
(1, (CURRENT_DATE + INTERVAL '180 days')::date, 'delivered', 3200.00, 200.00, 320.00,
    (CURRENT_DATE - INTERVAL '3 months')::date + TIME '15:10:00', (CURRENT_DATE - INTERVAL '3 months')::date + TIME '15:10:00'), -- 未来の注文日（実行日 +180 日で常に未来）
(9, (CURRENT_DATE - INTERVAL '3 months')::date + 2, 'delivered', -1500.00, 300.00, -150.00,
    (CURRENT_DATE - INTERVAL '3 months')::date + 2 + TIME '12:00:00', (CURRENT_DATE - INTERVAL '3 months')::date + 2 + TIME '12:00:00'), -- 負の金額
(3, (CURRENT_DATE - INTERVAL '2 months')::date, 'cancelled', 0.00, 0.00, 0.00,
    (CURRENT_DATE - INTERVAL '2 months')::date + TIME '03:25:00', (CURRENT_DATE - INTERVAL '2 months')::date + TIME '03:25:00'), -- ゼロ金額のキャンセル注文（深夜の受注）
(10, (CURRENT_DATE - INTERVAL '2 months')::date + 10, 'delivered', 1800.00, null, 180.00,
    (CURRENT_DATE - INTERVAL '2 months')::date + 10 + TIME '17:50:00', (CURRENT_DATE - INTERVAL '2 months')::date + 10 + TIME '17:50:00'), -- 送料が null

-- データ不整合（合計金額が明細と合わない）
(2, (CURRENT_DATE - INTERVAL '1 month')::date, 'delivered', 5000.00, 300.00, 500.00,
    (CURRENT_DATE - INTERVAL '1 month')::date + TIME '10:35:00', (CURRENT_DATE - INTERVAL '1 month')::date + TIME '10:35:00'), -- 実際の明細合計と異なる
(4, (CURRENT_DATE - INTERVAL '1 month')::date + 5, 'processing', 15000.00, 500.00, 1500.00,
    (CURRENT_DATE - INTERVAL '1 month')::date + 5 + TIME '04:15:00', (CURRENT_DATE - INTERVAL '1 month')::date + 5 + TIME '04:15:00'); -- 実際の明細合計と異なる（深夜の受注）

-- 注文明細データ
-- product_id は実在する複数の商品に分散させる。特定商品に集中すると
-- 商品別の売上・利益分析が一部の商品だけで成立してしまう
INSERT INTO order_detail (order_id, product_id, quantity, unit_price, line_total, created_at) VALUES
-- 正常データ（注文 ID 1-5 に対応）
(1, 1, 1, 89800.00, 89800.00, (CURRENT_DATE - INTERVAL '24 months')::date + TIME '10:15:00'),
(2, 2, 2, 29100.00, 58200.00, (CURRENT_DATE - INTERVAL '24 months')::date + 3 + TIME '14:40:00'),
(3, 3, 1, 94500.00, 94500.00, (CURRENT_DATE - INTERVAL '12 months')::date + TIME '11:05:00'),
(4, 4, 1, 45000.00, 45000.00, (CURRENT_DATE - INTERVAL '12 months')::date + 5 + TIME '16:20:00'),
(4, 5, 1, 22500.00, 22500.00, (CURRENT_DATE - INTERVAL '12 months')::date + 5 + TIME '16:20:00'),
(5, 5, 1, 4500.00, 4500.00, (CURRENT_DATE - INTERVAL '5 months')::date + TIME '13:30:00'),

-- 品質問題のあるデータ
(6, 4, 1, 12800.00, 12800.00, (CURRENT_DATE - INTERVAL '4 months')::date + TIME '09:45:00'),
(7, 8, -2, 3200.00, -6400.00, (CURRENT_DATE - INTERVAL '3 months')::date + TIME '15:10:00'), -- 負の数量
(8, 7, 1, -1500.00, -1500.00, (CURRENT_DATE - INTERVAL '3 months')::date + 2 + TIME '12:00:00'), -- 負の単価
(9, 9, 0, 1800.00, 0.00, (CURRENT_DATE - INTERVAL '2 months')::date + TIME '03:25:00'), -- ゼロ数量
(10, 12, 1, 1800.00, 1800.00, (CURRENT_DATE - INTERVAL '2 months')::date + 10 + TIME '17:50:00'), -- 単価が商品マスタの価格と一致しない

-- データ不整合の明細
(11, 13, 2, 2500.00, 5000.00, (CURRENT_DATE - INTERVAL '1 month')::date + TIME '10:35:00'), -- 合計 5000 円（ヘッダーと一致）
(12, 14, 3, 5000.00, 15000.00, (CURRENT_DATE - INTERVAL '1 month')::date + 5 + TIME '04:15:00'); -- 合計 15000 円（ヘッダーと一致）

-- 支払いデータ（品質問題を含む）
-- payment_amount は原則として order_header.total_amount と一致させる。
-- 一貫性の検証（tests/cross_table_order_payment_amount_consistency.sql）が
-- この 2 つの差を見るため、不整合は意図した箇所だけに絞る
INSERT INTO payment (order_id, payment_date, payment_amount, payment_status, payment_method, created_at, updated_at) VALUES
-- 正常データ
(1, (CURRENT_DATE - INTERVAL '24 months')::date, 89800.00, 'completed', 'credit_card',
    (CURRENT_DATE - INTERVAL '24 months')::date + TIME '10:20:00', (CURRENT_DATE - INTERVAL '24 months')::date + TIME '10:20:00'),
(2, (CURRENT_DATE - INTERVAL '24 months')::date + 3, 58200.00, 'completed', 'bank_transfer',
    (CURRENT_DATE - INTERVAL '24 months')::date + 3 + TIME '14:45:00', (CURRENT_DATE - INTERVAL '24 months')::date + 3 + TIME '14:45:00'),
(3, (CURRENT_DATE - INTERVAL '12 months')::date, 94500.00, 'pending', 'credit_card',
    (CURRENT_DATE - INTERVAL '12 months')::date + TIME '11:10:00', (CURRENT_DATE - INTERVAL '12 months')::date + TIME '11:10:00'),
(4, (CURRENT_DATE - INTERVAL '12 months')::date + 5, 67500.00, 'completed', 'digital_wallet',
    (CURRENT_DATE - INTERVAL '12 months')::date + 5 + TIME '16:25:00', (CURRENT_DATE - INTERVAL '12 months')::date + 5 + TIME '16:25:00'),
(5, (CURRENT_DATE - INTERVAL '5 months')::date, 4500.00, 'completed', 'cash_on_delivery',
    (CURRENT_DATE - INTERVAL '5 months')::date + TIME '13:35:00', (CURRENT_DATE - INTERVAL '5 months')::date + TIME '13:35:00'),

-- 品質問題のあるデータ
(1, (CURRENT_DATE - INTERVAL '4 months')::date, 89800.00, 'completed', 'credit_card',
    (CURRENT_DATE - INTERVAL '4 months')::date + TIME '09:50:00', (CURRENT_DATE - INTERVAL '4 months')::date + TIME '09:50:00'), -- 同一注文への二重支払い
(7, (CURRENT_DATE + INTERVAL '180 days')::date, 3200.00, 'completed', 'credit_card',
    (CURRENT_DATE - INTERVAL '3 months')::date + TIME '15:15:00', (CURRENT_DATE - INTERVAL '3 months')::date + TIME '15:15:00'), -- 未来の支払日
(8, (CURRENT_DATE - INTERVAL '3 months')::date + 2, -1500.00, 'failed', 'credit_card',
    (CURRENT_DATE - INTERVAL '3 months')::date + 2 + TIME '12:05:00', (CURRENT_DATE - INTERVAL '3 months')::date + 2 + TIME '12:05:00'), -- 負の支払金額
(1, (CURRENT_DATE - INTERVAL '24 months')::date, 89800.00, 'completed', 'unknown_method',
    (CURRENT_DATE - INTERVAL '24 months')::date + TIME '10:25:00', (CURRENT_DATE - INTERVAL '24 months')::date + TIME '10:25:00'), -- 不正な支払方法
(2, (CURRENT_DATE - INTERVAL '24 months')::date + 3, 100000.00, 'completed', 'credit_card',
    (CURRENT_DATE - INTERVAL '24 months')::date + 3 + TIME '14:50:00', (CURRENT_DATE - INTERVAL '24 months')::date + 3 + TIME '14:50:00'), -- 注文金額と一致しない

-- 支払い状況の不整合
(9, null, 0.00, 'pending', null,
    (CURRENT_DATE - INTERVAL '2 months')::date + TIME '03:30:00', (CURRENT_DATE - INTERVAL '2 months')::date + TIME '03:30:00'), -- 支払日が null だが金額もゼロ
(10, (CURRENT_DATE - INTERVAL '2 months')::date + 10, 2280.00, 'completed', 'credit_card',
    (CURRENT_DATE - INTERVAL '2 months')::date + 10 + TIME '17:55:00', (CURRENT_DATE - INTERVAL '2 months')::date + 10 + TIME '17:55:00'); -- 注文金額と支払金額が一致しない

-- 在庫更新（一部商品の在庫を意図的に不整合にする）
UPDATE product SET stock_quantity = stock_quantity - 1 WHERE product_id = 1; -- 注文分を減算
UPDATE product SET stock_quantity = stock_quantity - 1 WHERE product_id = 2;
UPDATE product SET stock_quantity = stock_quantity - 1 WHERE product_id = 3;
-- product_id = 4, 5 は在庫更新を忘れた想定（データ不整合）
