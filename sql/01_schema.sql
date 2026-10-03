-- ===============================================================================
-- Phase 2 — Database Design & Schema Creation
-- Project: Retail Sales Performance & Customer Segmentation
-- Dialect: PostgreSQL / MySQL Compatible DDL
-- ===============================================================================

-- Drop existing tables in reverse dependency order
DROP TABLE IF EXISTS order_items CASCADE;
DROP TABLE IF EXISTS orders CASCADE;
DROP TABLE IF EXISTS products CASCADE;
DROP TABLE IF EXISTS customers CASCADE;
DROP TABLE IF EXISTS date_dim CASCADE;

-- -------------------------------------------------------------------------------
-- 1. Customers Table (Dimension)
-- -------------------------------------------------------------------------------
CREATE TABLE customers (
    customer_id INTEGER PRIMARY KEY,
    country VARCHAR(100) NOT NULL,
    first_order_date TIMESTAMP NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- -------------------------------------------------------------------------------
-- 2. Products Table (Dimension)
-- -------------------------------------------------------------------------------
CREATE TABLE products (
    product_id VARCHAR(50) PRIMARY KEY,
    description TEXT,
    unit_price NUMERIC(10, 2) NOT NULL CHECK (unit_price > 0),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- -------------------------------------------------------------------------------
-- 3. Orders Table (Header/Transaction Dimension)
-- -------------------------------------------------------------------------------
CREATE TABLE orders (
    order_id VARCHAR(50) PRIMARY KEY,
    customer_id INTEGER NOT NULL,
    order_date TIMESTAMP NOT NULL,
    country VARCHAR(100) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_orders_customer 
        FOREIGN KEY (customer_id) 
        REFERENCES customers(customer_id) 
        ON DELETE CASCADE
);

-- -------------------------------------------------------------------------------
-- 4. Order Items Table (Transactional Fact Line Items)
-- -------------------------------------------------------------------------------
CREATE TABLE order_items (
    order_item_id BIGSERIAL PRIMARY KEY,
    order_id VARCHAR(50) NOT NULL,
    product_id VARCHAR(50) NOT NULL,
    quantity INTEGER NOT NULL CHECK (quantity > 0),
    unit_price NUMERIC(10, 2) NOT NULL CHECK (unit_price > 0),
    line_revenue NUMERIC(12, 2) NOT NULL CHECK (line_revenue > 0),
    CONSTRAINT fk_items_order 
        FOREIGN KEY (order_id) 
        REFERENCES orders(order_id) 
        ON DELETE CASCADE,
    CONSTRAINT fk_items_product 
        FOREIGN KEY (product_id) 
        REFERENCES products(product_id) 
        ON DELETE RESTRICT
);

-- -------------------------------------------------------------------------------
-- 5. Performance Indexes
-- -------------------------------------------------------------------------------
CREATE INDEX idx_orders_customer_id ON orders(customer_id);
CREATE INDEX idx_orders_order_date ON orders(order_date);
CREATE INDEX idx_order_items_order_id ON order_items(order_id);
CREATE INDEX idx_order_items_product_id ON order_items(product_id);
CREATE INDEX idx_order_items_order_product ON order_items(order_id, product_id);
