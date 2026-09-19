/*
EC サイト「ZakkaMall」OLTP データベース（DuckDB 版）- 第5章データ品質管理用

v1 版（PostgreSQL）の init-scripts/01_ddl.sql を DuckDB へ移植したもの。
DuckDB に存在しない機能は以下のように置き換えている。

  - GENERATED ALWAYS AS IDENTITY  -> CREATE SEQUENCE + DEFAULT nextval(...)
  - インデックス / 部分索引        -> 削除（列指向のため不要）
  - CREATE EXTENSION / GRANT      -> 削除
  - FOREIGN KEY                   -> 削除（理由は下記）

DuckDB は外部キーで参照されている親行を UPDATE / DELETE できない（値を変えない列の
更新でも Constraint Error になる）。本章のケーススタディでは重複商品の削除や
サンプルデータの修正を行うため、外部キー制約は付けていない。
参照整合性そのものはサンプルデータ側で担保している。
*/

-- スキーマを作成
CREATE SCHEMA IF NOT EXISTS zakka_mall;

-- 初期スキーマの指定
SET search_path = 'zakka_mall';

-- PostgreSQL コンテナ（TZ=UTC）と同じ解釈で日付リテラルを取り込むため UTC に固定する。
-- ローカルのタイムゾーンのままだと CURRENT_DATE 相対のサンプルデータや
-- Source Freshness の判定が時差分ずれる。
SET TimeZone = 'UTC';

-- PostgreSQL の enum 利用時に dbt unit test にてエラーとなるため status は VARCHAR とする

-- 代理キー用シーケンス（PostgreSQL 版の IDENTITY 列に相当）
CREATE SEQUENCE seq_customer_id START 1;
CREATE SEQUENCE seq_category_id START 1;
CREATE SEQUENCE seq_product_id START 1;
CREATE SEQUENCE seq_order_id START 1;
CREATE SEQUENCE seq_order_detail_id START 1;
CREATE SEQUENCE seq_payment_id START 1;

-- 顧客テーブル
CREATE TABLE customer (
    customer_id BIGINT PRIMARY KEY DEFAULT nextval('seq_customer_id'),
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
    category_id BIGINT PRIMARY KEY DEFAULT nextval('seq_category_id'),
    category_name VARCHAR(100) NOT NULL,
    parent_category_id BIGINT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 商品テーブル
CREATE TABLE product (
    product_id BIGINT PRIMARY KEY DEFAULT nextval('seq_product_id'),
    product_name VARCHAR(200) NOT NULL,
    category_id BIGINT NOT NULL,
    price DECIMAL(10,2) NOT NULL,
    cost DECIMAL(10,2),
    stock_quantity INTEGER NOT NULL DEFAULT 0,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 注文テーブル
CREATE TABLE order_header (
    order_id BIGINT PRIMARY KEY DEFAULT nextval('seq_order_id'),
    customer_id BIGINT NOT NULL,
    order_date DATE NOT NULL DEFAULT CURRENT_DATE,
    order_status VARCHAR(20) NOT NULL DEFAULT 'pending',
    total_amount DECIMAL(12,2) NOT NULL,
    shipping_fee DECIMAL(8,2) DEFAULT 0,
    tax_amount DECIMAL(10,2) DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 注文明細テーブル
CREATE TABLE order_detail (
    order_detail_id BIGINT PRIMARY KEY DEFAULT nextval('seq_order_detail_id'),
    order_id BIGINT NOT NULL,
    product_id BIGINT NOT NULL,
    quantity INTEGER NOT NULL,
    unit_price DECIMAL(10,2) NOT NULL,
    line_total DECIMAL(12,2) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 支払いテーブル
CREATE TABLE payment (
    payment_id BIGINT PRIMARY KEY DEFAULT nextval('seq_payment_id'),
    order_id BIGINT NOT NULL,
    payment_date DATE,
    payment_amount DECIMAL(12,2) NOT NULL,
    payment_status VARCHAR(20) NOT NULL DEFAULT 'pending',
    payment_method VARCHAR(50),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
