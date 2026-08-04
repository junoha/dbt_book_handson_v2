/*
EC サイト「ZakkaMall」OLTP データベース - 第5章データ品質管理用
*/

-- スキーマを作成
CREATE SCHEMA IF NOT EXISTS zakka_mall;

-- 初期スキーマの指定
SELECT pg_catalog.set_config('search_path', 'zakka_mall, pg_catalog', false); 

-- 拡張機能の有効化
CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA zakka_mall;

-- dbt_userに権限を付与
GRANT ALL PRIVILEGES ON SCHEMA zakka_mall TO dbt_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA zakka_mall GRANT ALL ON TABLES TO dbt_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA zakka_mall GRANT ALL ON SEQUENCES TO dbt_user;

-- PostgreSQL の enum 利用時に dbt unit test にてエラーとなるため status は VARCHAR とする

-- 顧客テーブル
CREATE TABLE customer (
    customer_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    customer_name VARCHAR(100) NOT NULL,
    email VARCHAR(255) NOT NULL UNIQUE,
    phone VARCHAR(20),
    registration_date DATE NOT NULL DEFAULT CURRENT_DATE,
    status VARCHAR(20) NOT NULL DEFAULT 'active',
    birth_date DATE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 商品カテゴリテーブル
CREATE TABLE product_category (
    category_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    category_name VARCHAR(100) NOT NULL,
    parent_category_id BIGINT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    FOREIGN KEY (parent_category_id) REFERENCES product_category(category_id)
);

-- 商品テーブル
CREATE TABLE product (
    product_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    product_name VARCHAR(200) NOT NULL,
    category_id BIGINT NOT NULL,
    price DECIMAL(10,2) NOT NULL,
    cost DECIMAL(10,2),
    stock_quantity INTEGER NOT NULL DEFAULT 0,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    FOREIGN KEY (category_id) REFERENCES product_category(category_id)
);

-- 注文テーブル
CREATE TABLE order_header (
    order_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    customer_id BIGINT NOT NULL,
    order_date DATE NOT NULL DEFAULT CURRENT_DATE,
    order_status VARCHAR(20) NOT NULL DEFAULT 'pending',
    total_amount DECIMAL(12,2) NOT NULL,
    shipping_fee DECIMAL(8,2) DEFAULT 0,
    tax_amount DECIMAL(10,2) DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    FOREIGN KEY (customer_id) REFERENCES customer(customer_id)
);

-- 注文明細テーブル
CREATE TABLE order_detail (
    order_detail_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    order_id BIGINT NOT NULL,
    product_id BIGINT NOT NULL,
    quantity INTEGER NOT NULL,
    unit_price DECIMAL(10,2) NOT NULL,
    line_total DECIMAL(12,2) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    FOREIGN KEY (order_id) REFERENCES order_header(order_id),
    FOREIGN KEY (product_id) REFERENCES product(product_id)
);

-- 支払いテーブル
CREATE TABLE payment (
    payment_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    order_id BIGINT NOT NULL,
    payment_date DATE,
    payment_amount DECIMAL(12,2) NOT NULL,
    payment_status VARCHAR(20) NOT NULL DEFAULT 'pending',
    payment_method VARCHAR(50),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    FOREIGN KEY (order_id) REFERENCES order_header(order_id)
);

-- インデックス作成
CREATE INDEX idx_customer_email ON customer(email);
CREATE INDEX idx_customer_status ON customer(status);
CREATE INDEX idx_customer_registration_date ON customer(registration_date);
CREATE INDEX idx_product_category ON product(category_id);
CREATE INDEX idx_product_active ON product(is_active);
CREATE INDEX idx_order_detail_order ON order_detail(order_id);
CREATE INDEX idx_order_detail_product ON order_detail(product_id);
CREATE INDEX idx_payment_order ON payment(order_id);

-- B-tree複数値検索最適化を活用した複合インデックス
-- アクティブな顧客の状態と登録日での効率的な検索用
CREATE INDEX idx_customer_status_date ON customer(status, registration_date) 
WHERE status = 'active';

-- 注文の顧客別・状態別検索用（データ品質チェックで頻用）
CREATE INDEX idx_order_customer_status ON order_header(customer_id, order_status);

-- 注文日と状態での範囲検索用（時系列分析用）
CREATE INDEX idx_order_date_status ON order_header(order_date, order_status);

-- 支払い状態別の効率的な検索用
CREATE INDEX idx_payment_status ON payment(payment_status) 
WHERE payment_status IN ('pending', 'failed');
