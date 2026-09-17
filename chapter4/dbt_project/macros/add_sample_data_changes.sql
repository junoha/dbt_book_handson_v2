{% macro add_sample_data_changes() %}
  {#
    SCD Type 2 の履歴管理の挙動確認用サンプルデータ更新マクロ。

    顧客・商品・注文の一部を UPDATE / INSERT し、base_dim 再ビルド →
    dbt snapshot → dbt run の流れで dim_customers / dim_products /
    fct_orders に新旧バージョンが履歴として保持される様子を確認できる。

    本章は base_dim_* → snapshot_dim_* → dim_* → fct_* の 4 段で
    SCD Type 2 を実装しているため、属性変更前の注文は当時の属性で、
    属性変更後の注文は新しい属性で結合される（期間マッチ JOIN）。
    詳しくは chapter4/README.md の「SCD Type 2（履歴管理）の確認」を参照。

    DuckDB 版の注意:
    PostgreSQL 版では BEFORE UPDATE トリガーが updated_at を自動更新していたが、
    DuckDB にトリガーは無いため各 UPDATE で updated_at = NOW() を明示している。
    snapshot は strategy: timestamp で updated_at を見るため、これが無いと変更が検知されない。

    使用方法:
    dbt run-operation add_sample_data_changes
    dbt run --select base_dim_customers base_dim_products
    dbt snapshot
    dbt run --select marts.core
  #}

  {% set sql_statements = [
    "-- 既存顧客の情報更新（メールアドレス変更、ステータス変更）
    UPDATE zakka_mall.customer 
     SET 
         email = 'tanaka.taro.new@example.com',
         status = 'inactive',
         updated_at = NOW()
     WHERE customer_id = 1",
    
    "UPDATE zakka_mall.customer 
     SET 
         phone = '090-9999-9999',
         status = 'suspended',
         updated_at = NOW()
     WHERE customer_id = 2",
    
    "-- 既存商品の価格変更
    UPDATE zakka_mall.product 
     SET 
         unit_price = 1200.00,
         status = 'active',
         updated_at = NOW()
     WHERE product_id = 1",
    
    "UPDATE zakka_mall.product 
     SET 
         unit_price = 2800.00,
         status = 'discontinued',
         updated_at = NOW()
     WHERE product_id = 3",
    
    "-- 既存注文のステータス更新
    UPDATE zakka_mall.\"order\" 
     SET 
         order_status = 'shipped',
         updated_at = NOW()
     WHERE order_id = 1",
    
    "UPDATE zakka_mall.\"order\" 
     SET 
         order_status = 'delivered',
         shipping_fee = 800.00,
         updated_at = NOW()
     WHERE order_id = 2",
    
    "-- 新規顧客の追加 (customer_id : 51, 52)
    INSERT INTO zakka_mall.customer (customer_name, email, phone, registration_date, status)
     VALUES 
         ('新規太郎', 'shinki.taro@example.com', '080-1111-2222', CURRENT_DATE, 'active'),
         ('新規花子', 'shinki.hanako@example.com', '080-3333-4444', CURRENT_DATE, 'active')",
    
    "-- 新規顧客の住所追加 (address_id : 52, 53)
    INSERT INTO zakka_mall.customer_address (customer_id, address_type, postal_code, prefecture, city, address_line1, is_default)
     VALUES 
         (51, 'both', '100-0001', '東京都', '千代田区', '千代田1-1-1', true),
         (52, 'both', '150-0001', '東京都', '渋谷区', '渋谷2-2-2', true)",
    
    "-- 新規商品の追加 (product_id : 49, 50)
    INSERT INTO zakka_mall.product (product_name, product_code, sku, category_id, supplier_id, unit_price, description, status)
     VALUES 
         ('新商品A', 'NEW001', 'SKU-NEW001', 1, 1, 1500.00, '新しく追加された商品A', 'active'),
         ('新商品B', 'NEW002', 'SKU-NEW002', 2, 2, 2500.00, '新しく追加された商品B', 'active')",
    
    "-- 新規商品の在庫追加 (inventory_id : 49, 50)
    INSERT INTO zakka_mall.inventory (product_id, quantity_on_hand, reorder_level, reorder_quantity)
     VALUES 
         (49, 100, 10, 50),
         (50, 50, 5, 25)",
    
    "-- 新規注文の追加（order_id はシーケンスで自動採番される）
    -- snapshot 実行後の日付にすることで、SCD Type 2 の新規バージョンと期間マッチで結合する
    -- customer_id = 1 は属性を更新した既存顧客。過去の注文が旧バージョンと、
    -- この注文が新バージョンと結合されることで期間マッチの両面が確認できる
    INSERT INTO zakka_mall.\"order\" (customer_id, order_number, order_date, order_status, subtotal, tax_amount, shipping_fee, shipping_address_id, billing_address_id)
     VALUES
         (1, 'PENDING-1', CURRENT_DATE, 'processing', 2400.00, 240.00, 500.00, 1, 1),
         (51, 'PENDING-2', CURRENT_DATE, 'pending', 1500.00, 150.00, 500.00, 52, 52),
         (52, 'PENDING-3', CURRENT_DATE, 'processing', 2500.00, 250.00, 500.00, 53, 53)",

    "-- 注文番号の採番
    -- PostgreSQL 版では BEFORE INSERT トリガー generate_order_number が
    -- 'ORD-{注文日}-{order_id を 6 桁ゼロ埋め}' を自動生成していた。
    -- DuckDB にトリガーは無いため、採番済みの order_id を使って後から更新する。
    -- order_number は UNIQUE 制約があるため、INSERT 時の仮値は行ごとに変えている。
    UPDATE zakka_mall.\"order\"
     SET order_number = 'ORD-' || strftime(order_date, '%Y%m%d') || '-' || lpad(order_id::varchar, 6, '0')
     WHERE order_number LIKE 'PENDING-%'",

    "-- 新規注文明細の追加
    -- order_id はサブクエリで引く。ハードコードするとサンプルデータの件数を
    -- 変えたときに既存の注文へ明細が付いてしまうため
    -- customer_id = 1 の明細は価格改定した product_id = 1 を指定し、
    -- 商品ディメンションでも新バージョン（改定後の単価）と結合されることを示す
    INSERT INTO zakka_mall.order_item (order_id, product_id, quantity, unit_price)
     VALUES 
         ((SELECT order_id FROM zakka_mall.\"order\" WHERE customer_id = 1 AND order_date = CURRENT_DATE), 1, 2, 1200.00),
         ((SELECT order_id FROM zakka_mall.\"order\" WHERE customer_id = 51 AND order_date = CURRENT_DATE), 49, 1, 1500.00),
         ((SELECT order_id FROM zakka_mall.\"order\" WHERE customer_id = 52 AND order_date = CURRENT_DATE), 50, 1, 2500.00)",
    
    "-- 新規支払い情報の追加
    INSERT INTO zakka_mall.payment (order_id, payment_method, payment_status, payment_amount, payment_date)
     VALUES
         ((SELECT order_id FROM zakka_mall.\"order\" WHERE customer_id = 1 AND order_date = CURRENT_DATE), 'credit_card', 'completed', 3140.00, CURRENT_DATE),
         ((SELECT order_id FROM zakka_mall.\"order\" WHERE customer_id = 51 AND order_date = CURRENT_DATE), 'credit_card', 'completed', 2150.00, CURRENT_DATE),
         ((SELECT order_id FROM zakka_mall.\"order\" WHERE customer_id = 52 AND order_date = CURRENT_DATE), 'bank_transfer', 'pending', 3250.00, NULL)",

    "-- 新規配送情報の追加
    INSERT INTO zakka_mall.shipment (order_id, tracking_number, carrier, shipment_status, estimated_delivery_date)
     VALUES 
         ((SELECT order_id FROM zakka_mall.\"order\" WHERE customer_id = 1 AND order_date = CURRENT_DATE), 'TRK-' || strftime(CURRENT_DATE, '%Y%m%d') || '-003', 'ヤマト運輸', 'preparing', CURRENT_DATE + 3),
         ((SELECT order_id FROM zakka_mall.\"order\" WHERE customer_id = 51 AND order_date = CURRENT_DATE), 'TRK-' || strftime(CURRENT_DATE, '%Y%m%d') || '-001', 'ヤマト運輸', 'preparing', CURRENT_DATE + 4),
         ((SELECT order_id FROM zakka_mall.\"order\" WHERE customer_id = 52 AND order_date = CURRENT_DATE), 'TRK-' || strftime(CURRENT_DATE, '%Y%m%d') || '-002', '佐川急便', 'preparing', CURRENT_DATE + 5)"
  ] %}
  
    {% if execute %}
        {{ log("=== 履歴管理確認用データの追加を開始します ===", info=true) }}
    
        {% for sql_statement in sql_statements %}
            {% set result = run_query(sql_statement) %}
            {{ log("✓ SQL実行完了: " ~ sql_statement[:50] ~ "...", info=true) }}
        {% endfor %}
    
        {{ log("=== データ追加が完了しました ===", info=true) }}
    
    {% endif %}

{% endmacro %}
