/*
EC サイト「ZakkaMall」OLTP データベース
*/

-- スキーマを作成
CREATE SCHEMA IF NOT EXISTS zakka_mall;

-- 初期スキーマの指定
SET search_path = 'zakka_mall'; -- noqa: 

-- 拡張機能の有効化
CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA zakka_mall;
CREATE EXTENSION IF NOT EXISTS "ltree" WITH SCHEMA zakka_mall;

-- dbt_userに権限を付与
GRANT ALL PRIVILEGES ON SCHEMA zakka_mall TO dbt_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA zakka_mall GRANT ALL ON TABLES TO dbt_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA zakka_mall GRANT ALL ON SEQUENCES TO dbt_user;

-- ENUM 型の作成
CREATE TYPE customer_status_enum AS ENUM ('active', 'inactive', 'suspended');
CREATE TYPE address_type_enum AS ENUM ('shipping', 'billing', 'both');
CREATE TYPE supplier_status_enum AS ENUM ('active', 'inactive', 'pending');
CREATE TYPE product_status_enum AS ENUM ('active', 'inactive', 'discontinued');
CREATE TYPE order_status_enum AS ENUM ('pending', 'processing', 'shipped', 'delivered', 'cancelled', 'refunded');
CREATE TYPE payment_method_enum AS ENUM ('credit_card', 'bank_transfer', 'cash_on_delivery', 'digital_wallet');
CREATE TYPE payment_status_enum AS ENUM ('pending', 'completed', 'failed', 'refunded');
CREATE TYPE shipment_status_enum AS ENUM ('preparing', 'shipped', 'in_transit', 'delivered', 'returned');

-- テーブル作成
CREATE TABLE customer (
    customer_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
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
    address_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    customer_id BIGINT NOT NULL,
    address_type address_type_enum NOT NULL,
    postal_code VARCHAR(10) NOT NULL,
    prefecture VARCHAR(20) NOT NULL,
    city VARCHAR(50) NOT NULL,
    address_line1 VARCHAR(100) NOT NULL,
    address_line2 VARCHAR(100),
    is_default BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT fk_customer_address_customer FOREIGN KEY (customer_id) REFERENCES customer(customer_id)
);

CREATE TABLE category (
    category_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    category_name VARCHAR(100) NOT NULL,
    category_code VARCHAR(20) NOT NULL UNIQUE,
    parent_category_id BIGINT,
    description TEXT,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    category_path LTREE,
    CONSTRAINT fk_category_parent FOREIGN KEY (parent_category_id) REFERENCES category(category_id)
);

CREATE TABLE supplier (
    supplier_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    supplier_name VARCHAR(100) NOT NULL,
    supplier_code VARCHAR(20) NOT NULL UNIQUE,
    contact_email VARCHAR(255),
    contact_phone VARCHAR(20),
    address TEXT,
    status supplier_status_enum NOT NULL DEFAULT 'active',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    contact_details JSONB
);

CREATE TABLE product (
    product_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
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
    specifications JSONB,
    CONSTRAINT fk_product_category FOREIGN KEY (category_id) REFERENCES category(category_id),
    CONSTRAINT fk_product_supplier FOREIGN KEY (supplier_id) REFERENCES supplier(supplier_id)
);

CREATE TABLE inventory (
    inventory_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    product_id BIGINT NOT NULL UNIQUE,
    quantity_on_hand INTEGER NOT NULL DEFAULT 0 CHECK (quantity_on_hand >= 0),
    quantity_reserved INTEGER NOT NULL DEFAULT 0 CHECK (quantity_reserved >= 0),
    reorder_level INTEGER NOT NULL DEFAULT 0 CHECK (reorder_level >= 0),
    reorder_quantity INTEGER NOT NULL DEFAULT 0 CHECK (reorder_quantity >= 0),
    last_updated TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT fk_inventory_product FOREIGN KEY (product_id) REFERENCES product(product_id),
    CONSTRAINT ck_inventory_quantities CHECK (quantity_on_hand >= quantity_reserved)
);

CREATE TABLE "order" (
    order_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    customer_id BIGINT NOT NULL,
    order_number VARCHAR(50) NOT NULL UNIQUE,
    order_date DATE NOT NULL DEFAULT CURRENT_DATE,
    order_status order_status_enum NOT NULL DEFAULT 'pending',
    subtotal NUMERIC(10,2) NOT NULL CHECK (subtotal >= 0),
    tax_amount NUMERIC(10,2) NOT NULL CHECK (tax_amount >= 0),
    shipping_fee NUMERIC(10,2) NOT NULL CHECK (shipping_fee >= 0),
    total_amount NUMERIC(10,2) GENERATED ALWAYS AS (subtotal + tax_amount + shipping_fee) STORED,
    shipping_address_id BIGINT NOT NULL,
    billing_address_id BIGINT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    order_metadata JSONB,
    CONSTRAINT fk_order_customer FOREIGN KEY (customer_id) REFERENCES customer(customer_id),
    CONSTRAINT fk_order_shipping_address FOREIGN KEY (shipping_address_id) REFERENCES customer_address(address_id),
    CONSTRAINT fk_order_billing_address FOREIGN KEY (billing_address_id) REFERENCES customer_address(address_id)
);

CREATE TABLE order_item (
    order_item_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    order_id BIGINT NOT NULL,
    product_id BIGINT NOT NULL,
    quantity INTEGER NOT NULL CHECK (quantity > 0),
    unit_price NUMERIC(10,2) NOT NULL CHECK (unit_price >= 0),
    line_total NUMERIC(10,2) GENERATED ALWAYS AS (quantity * unit_price) STORED,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    item_metadata JSONB,
    CONSTRAINT fk_order_item_order FOREIGN KEY (order_id) REFERENCES "order"(order_id),
    CONSTRAINT fk_order_item_product FOREIGN KEY (product_id) REFERENCES product(product_id)
);

CREATE TABLE payment (
    payment_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    order_id BIGINT NOT NULL,
    payment_method payment_method_enum NOT NULL,
    payment_status payment_status_enum NOT NULL DEFAULT 'pending',
    payment_amount NUMERIC(10,2) NOT NULL CHECK (payment_amount >= 0),
    payment_date DATE,
    transaction_id VARCHAR(100),
    gateway_response JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT fk_payment_order FOREIGN KEY (order_id) REFERENCES "order"(order_id)
);

CREATE TABLE shipment (
    shipment_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    order_id BIGINT NOT NULL,
    tracking_number VARCHAR(100),
    carrier VARCHAR(50),
    shipment_status shipment_status_enum NOT NULL DEFAULT 'preparing',
    shipped_date DATE,
    estimated_delivery_date DATE,
    actual_delivery_date DATE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    tracking_details JSONB,
    CONSTRAINT fk_shipment_order FOREIGN KEY (order_id) REFERENCES "order"(order_id),
    CONSTRAINT ck_shipment_dates CHECK (
        (shipped_date IS NULL OR estimated_delivery_date IS NULL OR shipped_date <= estimated_delivery_date) AND
        (shipped_date IS NULL OR actual_delivery_date IS NULL OR shipped_date <= actual_delivery_date)
    )
);

-- インデックスの作成

-- customer テーブル
CREATE INDEX idx_customer_email ON customer(email);

-- customer_address テーブル
CREATE INDEX idx_customer_address_customer_id ON customer_address(customer_id);
CREATE INDEX idx_customer_address_postal_code ON customer_address(postal_code);

-- category テーブル
CREATE INDEX idx_category_code ON category(category_code);
CREATE INDEX idx_category_parent ON category(parent_category_id);
CREATE INDEX idx_category_path_gist ON category USING GIST(category_path);

-- supplier テーブル
CREATE INDEX idx_supplier_code ON supplier(supplier_code);

-- product テーブル
CREATE INDEX idx_product_code ON product(product_code);
CREATE INDEX idx_product_sku ON product(sku);
CREATE INDEX idx_product_category ON product(category_id);
CREATE INDEX idx_product_supplier ON product(supplier_id);

-- inventory テーブル
CREATE INDEX idx_inventory_product ON inventory(product_id);
CREATE INDEX idx_inventory_low_stock ON inventory(product_id) WHERE quantity_on_hand <= reorder_level;

-- order テーブル
CREATE INDEX idx_order_customer ON "order"(customer_id);
CREATE INDEX idx_order_number ON "order"(order_number);

-- order_item テーブル
CREATE INDEX idx_order_item_order ON order_item(order_id);
CREATE INDEX idx_order_item_product ON order_item(product_id);

-- payment テーブル
CREATE INDEX idx_payment_order ON payment(order_id);
CREATE INDEX idx_payment_method ON payment(payment_method);
CREATE INDEX idx_payment_transaction_id ON payment(transaction_id);

-- shipment テーブル
CREATE INDEX idx_shipment_order ON shipment(order_id);
CREATE INDEX idx_shipment_tracking_number ON shipment(tracking_number);

-- 更新日時の自動更新トリガー関数
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 各テーブルに更新日時トリガーを適用
CREATE TRIGGER trigger_customer_updated_at
    BEFORE UPDATE ON customer
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER trigger_customer_address_updated_at
    BEFORE UPDATE ON customer_address
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER trigger_category_updated_at
    BEFORE UPDATE ON category
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER trigger_supplier_updated_at
    BEFORE UPDATE ON supplier
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER trigger_product_updated_at
    BEFORE UPDATE ON product
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER trigger_order_updated_at
    BEFORE UPDATE ON "order"
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER trigger_payment_updated_at
    BEFORE UPDATE ON payment
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER trigger_shipment_updated_at
    BEFORE UPDATE ON shipment
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- カテゴリパス自動更新トリガー関数
CREATE OR REPLACE FUNCTION update_category_path()
RETURNS TRIGGER AS $$
DECLARE
    parent_path LTREE;
BEGIN
    IF NEW.parent_category_id IS NULL THEN
        NEW.category_path = NEW.category_code::LTREE;
    ELSE
        SELECT category_path INTO parent_path 
        FROM category 
        WHERE category_id = NEW.parent_category_id;
        
        IF parent_path IS NOT NULL THEN
            NEW.category_path = parent_path || NEW.category_code::LTREE;
        ELSE
            NEW.category_path = NEW.category_code::LTREE;
        END IF;
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_category_path
    BEFORE INSERT OR UPDATE ON category
    FOR EACH ROW EXECUTE FUNCTION update_category_path();

-- 在庫更新トリガー関数
CREATE OR REPLACE FUNCTION update_inventory_timestamp()
RETURNS TRIGGER AS $$
BEGIN
    NEW.last_updated = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_inventory_updated
    BEFORE UPDATE ON inventory
    FOR EACH ROW EXECUTE FUNCTION update_inventory_timestamp();

-- 顧客のデフォルト住所制約（1人につき1つのデフォルト住所のみ）
CREATE UNIQUE INDEX idx_customer_address_unique_default 
ON customer_address(customer_id) 
WHERE is_default = TRUE;

-- 注文番号の自動生成関数
CREATE OR REPLACE FUNCTION generate_order_number()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.order_number IS NULL THEN
        NEW.order_number = 'ORD-' || TO_CHAR(NEW.order_date, 'YYYYMMDD') || '-' || 
                          LPAD(NEW.order_id::TEXT, 6, '0');
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_order_number
    BEFORE INSERT ON "order"
    FOR EACH ROW EXECUTE FUNCTION generate_order_number();

