/*
v1 版（PostgreSQL）の init-scripts/04_quality_issues_data.sql から生成した DuckDB 版。
PostgreSQL 版との違いは次の 1 点のみ。
  - search_path の指定を SET search_path に置き換え、SET TimeZone = 'UTC' を追加
    （PostgreSQL コンテナと同じ解釈で CURRENT_DATE 相対のデータを取り込むため）
*/
/*
データ品質問題のサンプルデータ追加投入
異常検知やデータ品質テストのデモンストレーション用

このファイルで投入するデータは、どの行が問題かを名前から判別できないようにしている。
ZakkaMall の商品・顧客として自然な名前を使い、問題の所在は SQL コメントにのみ残す。
読者はテスト結果から問題行を突き止める流れになる。

02_master_data.sql / 03_transaction_data.sql と同様、マスタを投入してから
トランザクションを投入する。ID は以下の順で採番される。
  customer : 02 で 10 件投入済みのため 11 から
  product  : 02 で 15 件投入済みのため 16 から
  order    : 03 で 12 件投入済みのため 13 から
*/

SET search_path = 'zakka_mall';
SET TimeZone = 'UTC';

-- ============================================================
-- マスタデータの追加
-- ============================================================

-- 更新が長期間止まっている顧客（データ鮮度の調査対象）
INSERT INTO customer (customer_name, email, phone, registration_date, status, birth_date, created_at, updated_at) VALUES
('中村健太', 'nakamura@example.com', '090-0000-0001', (CURRENT_DATE - INTERVAL '3 years')::date, 'active', '1980-01-01',
    CURRENT_TIMESTAMP - INTERVAL '10 days', CURRENT_TIMESTAMP - INTERVAL '10 days'),
('小林美咲', 'kobayashi@example.com', '090-0000-0002', (CURRENT_DATE - INTERVAL '3 years')::date + 31, 'active', '1985-02-01',
    CURRENT_TIMESTAMP - INTERVAL '15 days', CURRENT_TIMESTAMP - INTERVAL '15 days');

-- 同姓同名の顧客（名寄せが必要かどうかの判断対象）
-- 02_master_data.sql の田中太郎・佐藤花子と合わせて、顧客名の重複は 3 グループになる
INSERT INTO customer (customer_name, email, phone, registration_date, status, birth_date) VALUES
('松本大輔', 'matsumoto@example.com', '090-1111-1111', (CURRENT_DATE - INTERVAL '11 months')::date, 'active', '1990-01-01'),
('松本大輔', 'matsumoto.d@example.com', '090-1111-1112', (CURRENT_DATE - INTERVAL '11 months')::date + 1, 'active', '1990-01-01'), -- 同姓同名
('井上あかり', 'inoue@example.com', '090-2222-2222', (CURRENT_DATE - INTERVAL '11 months')::date + 2, 'active', '1991-02-02');

-- 原価の登録漏れ（完全性の欠損。cost が null のため利益率が算出できない）
INSERT INTO product (product_name, category_id, price, cost, stock_quantity, is_active) VALUES
('コンパクトソファ 2人掛け', 5, 10000.00, null, 10, true),
('サイドテーブル 円形', 6, 15000.00, null, 15, true),
('ダイニングチェア 布張り', 7, 20000.00, null, 20, true),
('鋳物ホーロー鍋 20cm', 8, 25000.00, null, 25, true),
('マグカップ 陶器 2個組', 9, 30000.00, null, 30, true);

-- 統計的な外れ値（分布から大きく外れた値。入力ミスか実データかの判断対象）
INSERT INTO product (product_name, category_id, price, cost, stock_quantity, is_active) VALUES
('カウチソファ レザー 3人掛け', 5, 9999999.99, 5000000.00, 1, true), -- 価格の外れ値
('折りたたみテーブル 木製', 6, 1000.00, 500.00, 999999, true), -- 在庫数の外れ値
('スツール 丸型', 7, 100.00, 10000.00, 10, true); -- 原価が販売価格を上回る

-- ============================================================
-- トランザクションデータの追加
-- ============================================================

-- 時系列での異常値を作成（Elementary の anomaly detection 用）
-- dbt_project.yml の elementary_training_period_days: 14 / elementary_detection_period_days: 2 に合わせ、
-- 学習期間（16〜3 日前）に通常パターンを、検知期間（2〜1 日前）に急増を配置する
INSERT INTO order_header (
    customer_id, order_date, order_status, total_amount, shipping_fee, tax_amount, created_at, updated_at
) VALUES
-- 学習期間：通常の注文パターン（1 日あたり 2 件、1 万円前後）
(1, (CURRENT_DATE - INTERVAL '16 days')::date, 'delivered', 12000.00, 400.00, 1200.00,
    (CURRENT_DATE - INTERVAL '16 days')::date + TIME '10:30:00', (CURRENT_DATE - INTERVAL '16 days')::date + TIME '10:30:00'),
(3, (CURRENT_DATE - INTERVAL '16 days')::date, 'delivered', 8500.00, 300.00, 850.00,
    (CURRENT_DATE - INTERVAL '16 days')::date + TIME '15:45:00', (CURRENT_DATE - INTERVAL '16 days')::date + TIME '15:45:00'),

(2, (CURRENT_DATE - INTERVAL '14 days')::date, 'delivered', 15000.00, 500.00, 1500.00,
    (CURRENT_DATE - INTERVAL '14 days')::date + TIME '11:20:00', (CURRENT_DATE - INTERVAL '14 days')::date + TIME '11:20:00'),
(5, (CURRENT_DATE - INTERVAL '14 days')::date, 'delivered', 9800.00, 350.00, 980.00,
    (CURRENT_DATE - INTERVAL '14 days')::date + TIME '16:10:00', (CURRENT_DATE - INTERVAL '14 days')::date + TIME '16:10:00'),

(6, (CURRENT_DATE - INTERVAL '12 days')::date, 'delivered', 11200.00, 400.00, 1120.00,
    (CURRENT_DATE - INTERVAL '12 days')::date + TIME '09:55:00', (CURRENT_DATE - INTERVAL '12 days')::date + TIME '09:55:00'),
(8, (CURRENT_DATE - INTERVAL '12 days')::date, 'delivered', 13500.00, 450.00, 1350.00,
    (CURRENT_DATE - INTERVAL '12 days')::date + TIME '14:05:00', (CURRENT_DATE - INTERVAL '12 days')::date + TIME '14:05:00'),

(1, (CURRENT_DATE - INTERVAL '10 days')::date, 'delivered', 16800.00, 500.00, 1680.00,
    (CURRENT_DATE - INTERVAL '10 days')::date + TIME '13:15:00', (CURRENT_DATE - INTERVAL '10 days')::date + TIME '13:15:00'),
(10, (CURRENT_DATE - INTERVAL '10 days')::date, 'delivered', 7200.00, 250.00, 720.00,
    (CURRENT_DATE - INTERVAL '10 days')::date + TIME '03:40:00', (CURRENT_DATE - INTERVAL '10 days')::date + TIME '03:40:00'), -- 深夜の受注

(3, (CURRENT_DATE - INTERVAL '8 days')::date, 'delivered', 10500.00, 350.00, 1050.00,
    (CURRENT_DATE - INTERVAL '8 days')::date + TIME '10:50:00', (CURRENT_DATE - INTERVAL '8 days')::date + TIME '10:50:00'),
(11, (CURRENT_DATE - INTERVAL '8 days')::date, 'delivered', 14200.00, 450.00, 1420.00,
    (CURRENT_DATE - INTERVAL '8 days')::date + TIME '17:25:00', (CURRENT_DATE - INTERVAL '8 days')::date + TIME '17:25:00'),

(2, (CURRENT_DATE - INTERVAL '6 days')::date, 'delivered', 12800.00, 400.00, 1280.00,
    (CURRENT_DATE - INTERVAL '6 days')::date + TIME '12:35:00', (CURRENT_DATE - INTERVAL '6 days')::date + TIME '12:35:00'),
(12, (CURRENT_DATE - INTERVAL '6 days')::date, 'delivered', 9100.00, 300.00, 910.00,
    (CURRENT_DATE - INTERVAL '6 days')::date + TIME '11:00:00', (CURRENT_DATE - INTERVAL '6 days')::date + TIME '11:00:00'),

(5, (CURRENT_DATE - INTERVAL '4 days')::date, 'delivered', 13200.00, 450.00, 1320.00,
    (CURRENT_DATE - INTERVAL '4 days')::date + TIME '14:20:00', (CURRENT_DATE - INTERVAL '4 days')::date + TIME '14:20:00'),
(13, (CURRENT_DATE - INTERVAL '4 days')::date, 'delivered', 11500.00, 400.00, 1150.00,
    (CURRENT_DATE - INTERVAL '4 days')::date + TIME '04:50:00', (CURRENT_DATE - INTERVAL '4 days')::date + TIME '04:50:00'), -- 深夜の受注

-- 検知期間：直近 2 日で注文金額が 10 倍以上に急増（Elementary の volume / dimension anomalies が検知する対象）
(1, (CURRENT_DATE - INTERVAL '2 days')::date, 'delivered', 150000.00, 2000.00, 15000.00,
    (CURRENT_DATE - INTERVAL '2 days')::date + TIME '10:10:00', (CURRENT_DATE - INTERVAL '2 days')::date + TIME '10:10:00'),
(2, (CURRENT_DATE - INTERVAL '2 days')::date, 'delivered', 180000.00, 2500.00, 18000.00,
    (CURRENT_DATE - INTERVAL '2 days')::date + TIME '11:45:00', (CURRENT_DATE - INTERVAL '2 days')::date + TIME '11:45:00'),
(3, (CURRENT_DATE - INTERVAL '2 days')::date, 'delivered', 165000.00, 2100.00, 16500.00,
    (CURRENT_DATE - INTERVAL '2 days')::date + TIME '15:30:00', (CURRENT_DATE - INTERVAL '2 days')::date + TIME '15:30:00'),
(6, (CURRENT_DATE - INTERVAL '2 days')::date, 'delivered', 175000.00, 2200.00, 17500.00,
    (CURRENT_DATE - INTERVAL '2 days')::date + TIME '16:55:00', (CURRENT_DATE - INTERVAL '2 days')::date + TIME '16:55:00'),

(1, (CURRENT_DATE - INTERVAL '1 day')::date, 'delivered', 190000.00, 2800.00, 19000.00,
    (CURRENT_DATE - INTERVAL '1 day')::date + TIME '09:35:00', (CURRENT_DATE - INTERVAL '1 day')::date + TIME '09:35:00'),
(2, (CURRENT_DATE - INTERVAL '1 day')::date, 'delivered', 210000.00, 3200.00, 21000.00,
    (CURRENT_DATE - INTERVAL '1 day')::date + TIME '13:50:00', (CURRENT_DATE - INTERVAL '1 day')::date + TIME '13:50:00'),
(8, (CURRENT_DATE - INTERVAL '1 day')::date, 'delivered', 195000.00, 2900.00, 19500.00,
    (CURRENT_DATE - INTERVAL '1 day')::date + TIME '18:05:00', (CURRENT_DATE - INTERVAL '1 day')::date + TIME '18:05:00'),

-- 当日の注文。updated_at を 2 時間 30 分前にすることで、Source Freshness の
-- warn_after: 2 hour を超え error_after: 4 hour には達しない状態を作る。
-- 閾値のほぼ中央に置いているのは、コンテナを起動したまま時間が経っても
-- WARN の状態が続くようにするため（3 時間前だと 1 時間後に ERROR に変わる）
(3, CURRENT_DATE, 'processing', 18500.00, 550.00, 1850.00,
    CURRENT_TIMESTAMP - INTERVAL '2 hours 30 minutes', CURRENT_TIMESTAMP - INTERVAL '2 hours 30 minutes');

-- 上で投入した注文の明細（order_id 13〜34）
-- 商品を広く分散させる。特定商品に集中すると商品別の売上・利益分析が成立しない
INSERT INTO order_detail (order_id, product_id, quantity, unit_price, line_total, created_at) VALUES
(13, 1, 1, 12000.00, 12000.00, (CURRENT_DATE - INTERVAL '16 days')::date + TIME '10:30:00'),
(14, 5, 1, 8500.00, 8500.00, (CURRENT_DATE - INTERVAL '16 days')::date + TIME '15:45:00'),
(15, 2, 1, 15000.00, 15000.00, (CURRENT_DATE - INTERVAL '14 days')::date + TIME '11:20:00'),
(16, 8, 2, 4900.00, 9800.00, (CURRENT_DATE - INTERVAL '14 days')::date + TIME '16:10:00'),
(17, 3, 1, 11200.00, 11200.00, (CURRENT_DATE - INTERVAL '12 days')::date + TIME '09:55:00'),
(18, 4, 1, 13500.00, 13500.00, (CURRENT_DATE - INTERVAL '12 days')::date + TIME '14:05:00'),
(19, 16, 1, 16800.00, 16800.00, (CURRENT_DATE - INTERVAL '10 days')::date + TIME '13:15:00'),
(20, 12, 6, 1200.00, 7200.00, (CURRENT_DATE - INTERVAL '10 days')::date + TIME '03:40:00'),
(21, 9, 3, 3500.00, 10500.00, (CURRENT_DATE - INTERVAL '8 days')::date + TIME '10:50:00'),
(22, 17, 1, 14200.00, 14200.00, (CURRENT_DATE - INTERVAL '8 days')::date + TIME '17:25:00'),
(23, 18, 1, 12800.00, 12800.00, (CURRENT_DATE - INTERVAL '6 days')::date + TIME '12:35:00'),
-- order_id 24 は明細を投入しない（受注登録時に明細連携が失敗した想定）
(25, 19, 1, 13200.00, 13200.00, (CURRENT_DATE - INTERVAL '4 days')::date + TIME '14:20:00'),
(26, 20, 1, 11500.00, 11500.00, (CURRENT_DATE - INTERVAL '4 days')::date + TIME '04:50:00'),
(27, 21, 1, 150000.00, 150000.00, (CURRENT_DATE - INTERVAL '2 days')::date + TIME '10:10:00'),
(28, 1, 2, 90000.00, 180000.00, (CURRENT_DATE - INTERVAL '2 days')::date + TIME '11:45:00'),
(29, 2, 1, 165000.00, 165000.00, (CURRENT_DATE - INTERVAL '2 days')::date + TIME '15:30:00'),
-- order_id 30 は明細を投入しない（同上）
(31, 3, 1, 190000.00, 190000.00, (CURRENT_DATE - INTERVAL '1 day')::date + TIME '09:35:00'),
(32, 22, 1, 210000.00, 210000.00, (CURRENT_DATE - INTERVAL '1 day')::date + TIME '13:50:00'),
(33, 23, 1, 195000.00, 195000.00, (CURRENT_DATE - INTERVAL '1 day')::date + TIME '18:05:00'),
-- order_id 34 は明細を投入しない（当日受注のため未連携）
-- 明細側の最新行も 2 時間 30 分前にして Source Freshness の対象にする
(13, 6, 1, 2800.00, 2800.00, CURRENT_TIMESTAMP - INTERVAL '2 hours 30 minutes'); -- 後日追加された明細

-- 上で投入した注文への支払い（order_id 13〜34）
-- payment_amount は order_header.total_amount と一致させる。
-- 一貫性の検証がこの 2 つの差を見るため、不整合は 03_transaction_data.sql の
-- 意図した 2 件だけに絞っている
INSERT INTO payment (order_id, payment_date, payment_amount, payment_status, payment_method, created_at, updated_at) VALUES
(13, (CURRENT_DATE - INTERVAL '16 days')::date, 12000.00, 'completed', 'credit_card',
    (CURRENT_DATE - INTERVAL '16 days')::date + TIME '10:35:00', (CURRENT_DATE - INTERVAL '16 days')::date + TIME '10:35:00'),
(14, (CURRENT_DATE - INTERVAL '16 days')::date, 8500.00, 'completed', 'digital_wallet',
    (CURRENT_DATE - INTERVAL '16 days')::date + TIME '15:50:00', (CURRENT_DATE - INTERVAL '16 days')::date + TIME '15:50:00'),
(15, (CURRENT_DATE - INTERVAL '14 days')::date, 15000.00, 'completed', 'credit_card',
    (CURRENT_DATE - INTERVAL '14 days')::date + TIME '11:25:00', (CURRENT_DATE - INTERVAL '14 days')::date + TIME '11:25:00'),
(16, (CURRENT_DATE - INTERVAL '14 days')::date, 9800.00, 'completed', 'bank_transfer',
    (CURRENT_DATE - INTERVAL '14 days')::date + TIME '16:15:00', (CURRENT_DATE - INTERVAL '14 days')::date + TIME '16:15:00'),
(17, (CURRENT_DATE - INTERVAL '12 days')::date, 11200.00, 'completed', 'credit_card',
    (CURRENT_DATE - INTERVAL '12 days')::date + TIME '10:00:00', (CURRENT_DATE - INTERVAL '12 days')::date + TIME '10:00:00'),
(18, (CURRENT_DATE - INTERVAL '12 days')::date, 13500.00, 'completed', 'digital_wallet',
    (CURRENT_DATE - INTERVAL '12 days')::date + TIME '14:10:00', (CURRENT_DATE - INTERVAL '12 days')::date + TIME '14:10:00'),
(19, (CURRENT_DATE - INTERVAL '10 days')::date, 16800.00, 'completed', 'credit_card',
    (CURRENT_DATE - INTERVAL '10 days')::date + TIME '13:20:00', (CURRENT_DATE - INTERVAL '10 days')::date + TIME '13:20:00'),
(20, (CURRENT_DATE - INTERVAL '10 days')::date, 7200.00, 'completed', 'cash_on_delivery',
    (CURRENT_DATE - INTERVAL '10 days')::date + TIME '03:45:00', (CURRENT_DATE - INTERVAL '10 days')::date + TIME '03:45:00'),
(21, (CURRENT_DATE - INTERVAL '8 days')::date, 10500.00, 'completed', 'credit_card',
    (CURRENT_DATE - INTERVAL '8 days')::date + TIME '10:55:00', (CURRENT_DATE - INTERVAL '8 days')::date + TIME '10:55:00'),
-- order_id 22 は支払いレコードを投入しない（決済連携が失敗した想定）
(23, (CURRENT_DATE - INTERVAL '6 days')::date, 12800.00, 'completed', 'credit_card',
    (CURRENT_DATE - INTERVAL '6 days')::date + TIME '12:40:00', (CURRENT_DATE - INTERVAL '6 days')::date + TIME '12:40:00'),
(24, (CURRENT_DATE - INTERVAL '6 days')::date, 9100.00, 'completed', 'digital_wallet',
    (CURRENT_DATE - INTERVAL '6 days')::date + TIME '11:05:00', (CURRENT_DATE - INTERVAL '6 days')::date + TIME '11:05:00'),
(25, (CURRENT_DATE - INTERVAL '4 days')::date, 13200.00, 'completed', 'credit_card',
    (CURRENT_DATE - INTERVAL '4 days')::date + TIME '14:25:00', (CURRENT_DATE - INTERVAL '4 days')::date + TIME '14:25:00'),
-- order_id 26 は支払いレコードを投入しない（同上）
(27, (CURRENT_DATE - INTERVAL '2 days')::date, 150000.00, 'completed', 'bank_transfer',
    (CURRENT_DATE - INTERVAL '2 days')::date + TIME '10:15:00', (CURRENT_DATE - INTERVAL '2 days')::date + TIME '10:15:00'),
(28, (CURRENT_DATE - INTERVAL '2 days')::date, 180000.00, 'completed', 'credit_card',
    (CURRENT_DATE - INTERVAL '2 days')::date + TIME '11:50:00', (CURRENT_DATE - INTERVAL '2 days')::date + TIME '11:50:00'),
(29, (CURRENT_DATE - INTERVAL '2 days')::date, 165000.00, 'completed', 'bank_transfer',
    (CURRENT_DATE - INTERVAL '2 days')::date + TIME '15:35:00', (CURRENT_DATE - INTERVAL '2 days')::date + TIME '15:35:00'),
(30, (CURRENT_DATE - INTERVAL '2 days')::date, 175000.00, 'completed', 'credit_card',
    (CURRENT_DATE - INTERVAL '2 days')::date + TIME '17:00:00', (CURRENT_DATE - INTERVAL '2 days')::date + TIME '17:00:00'),
(31, (CURRENT_DATE - INTERVAL '1 day')::date, 190000.00, 'completed', 'credit_card',
    (CURRENT_DATE - INTERVAL '1 day')::date + TIME '09:40:00', (CURRENT_DATE - INTERVAL '1 day')::date + TIME '09:40:00'),
(32, (CURRENT_DATE - INTERVAL '1 day')::date, 210000.00, 'completed', 'bank_transfer',
    (CURRENT_DATE - INTERVAL '1 day')::date + TIME '13:55:00', (CURRENT_DATE - INTERVAL '1 day')::date + TIME '13:55:00'),
-- order_id 33 は支払いレコードを投入しない（同上）
-- 支払い側の最新行は 4 時間 30 分前にする。payment は warn_after: 3 hour /
-- error_after: 6 hour なので、閾値のほぼ中央に置くことで WARN の状態が続く
(34, CURRENT_DATE, 18500.00, 'pending', 'credit_card',
    CURRENT_TIMESTAMP - INTERVAL '4 hours 30 minutes', CURRENT_TIMESTAMP - INTERVAL '4 hours 30 minutes');
