/*
EC サイト「ZakkaMall」OLTP データベース（DuckDB 版）

v1 版（PostgreSQL）の init-scripts/01_ddl.sql を DuckDB へ移植したもの。
DuckDB に存在しない機能は以下のように置き換えている。

  - GENERATED ALWAYS AS IDENTITY  -> CREATE SEQUENCE + DEFAULT nextval(...)
  - LTREE                         -> VARCHAR（05_category_path.sql で値を生成）
  - JSONB                         -> JSON
  - トリガー / plpgsql 関数        -> 削除（updated_at の自動更新は行われない）
  - インデックス / GIST / 部分索引 -> 削除（列指向のため不要）
  - CREATE EXTENSION / GRANT      -> 削除
  - FOREIGN KEY                   -> 削除（理由は下記）

DuckDB は外部キーで参照されている親行を UPDATE できない（値を変えない列の更新でも
Constraint Error になる）。本章では add_sample_data_changes マクロで customer / product /
order を UPDATE して SCD Type 2 の挙動を確認するため、外部キー制約は付けていない。
参照整合性そのものはサンプルデータ側で担保している。
*/

-- スキーマを作成
CREATE SCHEMA IF NOT EXISTS zakka_mall;

-- 初期スキーマの指定
SET search_path = 'zakka_mall';

-- PostgreSQL コンテナ（TZ=UTC）と同じ解釈で日付リテラルを取り込むため UTC に固定する。
-- ローカルのタイムゾーンのままだと registration_date::timestamptz が時差分ずれる。
SET TimeZone = 'UTC';

-- ENUM 型の作成
CREATE TYPE customer_status_enum AS ENUM ('active', 'inactive', 'suspended');
CREATE TYPE address_type_enum AS ENUM ('shipping', 'billing', 'both');
CREATE TYPE supplier_status_enum AS ENUM ('active', 'inactive', 'pending');
CREATE TYPE product_status_enum AS ENUM ('active', 'inactive', 'discontinued');
CREATE TYPE order_status_enum AS ENUM ('pending', 'processing', 'shipped', 'delivered', 'cancelled', 'refunded');
CREATE TYPE payment_method_enum AS ENUM ('credit_card', 'bank_transfer', 'cash_on_delivery', 'digital_wallet');
CREATE TYPE payment_status_enum AS ENUM ('pending', 'completed', 'failed', 'refunded');
CREATE TYPE shipment_status_enum AS ENUM ('preparing', 'shipped', 'in_transit', 'delivered', 'returned');

-- 代理キー用シーケンス（PostgreSQL 版の IDENTITY 列に相当）
CREATE SEQUENCE seq_customer_id START 1;
CREATE SEQUENCE seq_customer_address_id START 1;
CREATE SEQUENCE seq_category_id START 1;
CREATE SEQUENCE seq_supplier_id START 1;
CREATE SEQUENCE seq_product_id START 1;
CREATE SEQUENCE seq_inventory_id START 1;
CREATE SEQUENCE seq_order_id START 1;
CREATE SEQUENCE seq_order_item_id START 1;
CREATE SEQUENCE seq_payment_id START 1;
CREATE SEQUENCE seq_shipment_id START 1;

-- テーブル作成
CREATE TABLE customer (
    customer_id BIGINT PRIMARY KEY DEFAULT nextval('seq_customer_id'),
    customer_name VARCHAR(100) NOT NULL,
    email VARCHAR(255) NOT NULL UNIQUE,
    phone VARCHAR(20),
    registration_date DATE NOT NULL DEFAULT CURRENT_DATE,
    status customer_status_enum NOT NULL DEFAULT 'active',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    external_id UUID DEFAULT gen_random_uuid()
);

CREATE TABLE customer_address (
    address_id BIGINT PRIMARY KEY DEFAULT nextval('seq_customer_address_id'),
    customer_id BIGINT NOT NULL,
    address_type address_type_enum NOT NULL,
    postal_code VARCHAR(10) NOT NULL,
    prefecture VARCHAR(20) NOT NULL,
    city VARCHAR(50) NOT NULL,
    address_line1 VARCHAR(100) NOT NULL,
    address_line2 VARCHAR(100),
    is_default BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- category_path は PostgreSQL 版では LTREE 型 + トリガーで自動生成していたが、
-- DuckDB にはどちらも無いため VARCHAR とし、05_category_path.sql で値を埋める。
CREATE TABLE category (
    category_id BIGINT PRIMARY KEY DEFAULT nextval('seq_category_id'),
    category_name VARCHAR(100) NOT NULL,
    category_code VARCHAR(20) NOT NULL UNIQUE,
    parent_category_id BIGINT,
    description TEXT,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    category_path VARCHAR
);

CREATE TABLE supplier (
    supplier_id BIGINT PRIMARY KEY DEFAULT nextval('seq_supplier_id'),
    supplier_name VARCHAR(100) NOT NULL,
    supplier_code VARCHAR(20) NOT NULL UNIQUE,
    contact_email VARCHAR(255),
    contact_phone VARCHAR(20),
    address TEXT,
    status supplier_status_enum NOT NULL DEFAULT 'active',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    contact_details JSON
);

CREATE TABLE product (
    product_id BIGINT PRIMARY KEY DEFAULT nextval('seq_product_id'),
    product_name VARCHAR(200) NOT NULL,
    product_code VARCHAR(50) NOT NULL UNIQUE,
    sku VARCHAR(50) NOT NULL UNIQUE,
    category_id BIGINT NOT NULL,
    supplier_id BIGINT NOT NULL,
    unit_price NUMERIC(10,2) NOT NULL CHECK (unit_price >= 0),
    description TEXT,
    status product_status_enum NOT NULL DEFAULT 'active',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    specifications JSON
);

CREATE TABLE inventory (
    inventory_id BIGINT PRIMARY KEY DEFAULT nextval('seq_inventory_id'),
    product_id BIGINT NOT NULL UNIQUE,
    quantity_on_hand INTEGER NOT NULL DEFAULT 0 CHECK (quantity_on_hand >= 0),
    quantity_reserved INTEGER NOT NULL DEFAULT 0 CHECK (quantity_reserved >= 0),
    reorder_level INTEGER NOT NULL DEFAULT 0 CHECK (reorder_level >= 0),
    reorder_quantity INTEGER NOT NULL DEFAULT 0 CHECK (reorder_quantity >= 0),
    last_updated TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT ck_inventory_quantities CHECK (quantity_on_hand >= quantity_reserved)
);

-- total_amount は DuckDB でも生成列で表現できるが、STORED は未対応のため VIRTUAL（既定）にする
CREATE TABLE "order" (
    order_id BIGINT PRIMARY KEY DEFAULT nextval('seq_order_id'),
    customer_id BIGINT NOT NULL,
    order_number VARCHAR(50) NOT NULL UNIQUE,
    order_date DATE NOT NULL DEFAULT CURRENT_DATE,
    order_status order_status_enum NOT NULL DEFAULT 'pending',
    subtotal NUMERIC(10,2) NOT NULL CHECK (subtotal >= 0),
    tax_amount NUMERIC(10,2) NOT NULL CHECK (tax_amount >= 0),
    shipping_fee NUMERIC(10,2) NOT NULL CHECK (shipping_fee >= 0),
    total_amount NUMERIC(10,2) GENERATED ALWAYS AS (subtotal + tax_amount + shipping_fee),
    shipping_address_id BIGINT NOT NULL,
    billing_address_id BIGINT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    order_metadata JSON
);

CREATE TABLE order_item (
    order_item_id BIGINT PRIMARY KEY DEFAULT nextval('seq_order_item_id'),
    order_id BIGINT NOT NULL,
    product_id BIGINT NOT NULL,
    quantity INTEGER NOT NULL CHECK (quantity > 0),
    unit_price NUMERIC(10,2) NOT NULL CHECK (unit_price >= 0),
    line_total NUMERIC(10,2) GENERATED ALWAYS AS (quantity * unit_price),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    item_metadata JSON
);

CREATE TABLE payment (
    payment_id BIGINT PRIMARY KEY DEFAULT nextval('seq_payment_id'),
    order_id BIGINT NOT NULL,
    payment_method payment_method_enum NOT NULL,
    payment_status payment_status_enum NOT NULL DEFAULT 'pending',
    payment_amount NUMERIC(10,2) NOT NULL CHECK (payment_amount >= 0),
    payment_date DATE,
    transaction_id VARCHAR(100),
    gateway_response JSON,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE shipment (
    shipment_id BIGINT PRIMARY KEY DEFAULT nextval('seq_shipment_id'),
    order_id BIGINT NOT NULL,
    tracking_number VARCHAR(100),
    carrier VARCHAR(50),
    shipment_status shipment_status_enum NOT NULL DEFAULT 'preparing',
    shipped_date DATE,
    estimated_delivery_date DATE,
    actual_delivery_date DATE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    tracking_details JSON,
    CONSTRAINT ck_shipment_dates CHECK (
        (shipped_date IS NULL OR estimated_delivery_date IS NULL OR shipped_date <= estimated_delivery_date) AND
        (shipped_date IS NULL OR actual_delivery_date IS NULL OR shipped_date <= actual_delivery_date)
    )
);
