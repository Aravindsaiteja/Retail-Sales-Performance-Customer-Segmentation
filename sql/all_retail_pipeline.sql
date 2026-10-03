-- ===============================================================================
-- Retail Sales Performance & Customer Segmentation — Master SQL Pipeline
-- ===============================================================================
-- Project: SQL + Power BI Capstone Project
-- Dialect: PostgreSQL / MySQL Standard Compliant
-- Author: Lead Analytics Engineer
--
-- Description:
--   This master script builds the entire data warehouse layer:
--   1. Phase 2: Relational Schema DDL & Constraints
--   2. Phase 3: Data Cleaning, Transformations, `sales_fact`, and `date_dim`
--   3. Phase 4: Customer RFM Segmentation & Scoring Logic
--   4. Phase 5: Power BI Analytical Views (KPIs, Product Performance, Cohorts, Growth)
-- ===============================================================================

BEGIN;

-- ===============================================================================
-- PHASE 2: RELATIONAL SCHEMA DDL
-- ===============================================================================

DROP TABLE IF EXISTS order_items CASCADE;
DROP TABLE IF EXISTS orders CASCADE;
DROP TABLE IF EXISTS products CASCADE;
DROP TABLE IF EXISTS customers CASCADE;
DROP TABLE IF EXISTS date_dim CASCADE;

-- 1. Customers Table
CREATE TABLE customers (
    customer_id INTEGER PRIMARY KEY,
    country VARCHAR(100) NOT NULL,
    first_order_date TIMESTAMP NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 2. Products Table
CREATE TABLE products (
    product_id VARCHAR(50) PRIMARY KEY,
    description TEXT,
    unit_price NUMERIC(10, 2) NOT NULL CHECK (unit_price > 0),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 3. Orders Header Table
CREATE TABLE orders (
    order_id VARCHAR(50) PRIMARY KEY,
    customer_id INTEGER NOT NULL,
    order_date TIMESTAMP NOT NULL,
    country VARCHAR(100) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_orders_customer FOREIGN KEY (customer_id) REFERENCES customers(customer_id) ON DELETE CASCADE
);

-- 4. Order Line Items Table
CREATE TABLE order_items (
    order_item_id BIGSERIAL PRIMARY KEY,
    order_id VARCHAR(50) NOT NULL,
    product_id VARCHAR(50) NOT NULL,
    quantity INTEGER NOT NULL CHECK (quantity > 0),
    unit_price NUMERIC(10, 2) NOT NULL CHECK (unit_price > 0),
    line_revenue NUMERIC(12, 2) NOT NULL CHECK (line_revenue > 0),
    CONSTRAINT fk_items_order FOREIGN KEY (order_id) REFERENCES orders(order_id) ON DELETE CASCADE,
    CONSTRAINT fk_items_product FOREIGN KEY (product_id) REFERENCES products(product_id) ON DELETE RESTRICT
);

-- Performance Indexes
CREATE INDEX idx_orders_customer_id ON orders(customer_id);
CREATE INDEX idx_orders_order_date ON orders(order_date);
CREATE INDEX idx_order_items_order_id ON order_items(order_id);
CREATE INDEX idx_order_items_product_id ON order_items(product_id);


-- ===============================================================================
-- PHASE 3: TRANSFORMATIONS & FACT LAYER
-- ===============================================================================

-- 1. View: clean_orders
DROP VIEW IF EXISTS clean_orders CASCADE;
CREATE VIEW clean_orders AS
SELECT order_id, customer_id, order_date, country
FROM orders
WHERE customer_id IS NOT NULL AND order_id NOT LIKE 'C%';

-- 2. View: sales_fact
DROP VIEW IF EXISTS sales_fact CASCADE;
CREATE VIEW sales_fact AS
SELECT 
    oi.order_item_id,
    oi.order_id,
    o.customer_id,
    oi.product_id,
    p.description AS product_description,
    o.order_date,
    CAST(o.order_date AS DATE) AS full_date,
    TO_CHAR(o.order_date, 'YYYY-MM') AS year_month,
    EXTRACT(YEAR FROM o.order_date) AS year,
    EXTRACT(MONTH FROM o.order_date) AS month,
    o.country,
    oi.quantity,
    oi.unit_price,
    (oi.quantity * oi.unit_price) AS line_revenue
FROM order_items oi
JOIN orders o ON oi.order_id = o.order_id
JOIN products p ON oi.product_id = p.product_id
WHERE oi.quantity > 0 AND oi.unit_price > 0 AND o.customer_id IS NOT NULL;

-- 3. Table: date_dim
CREATE TABLE date_dim (
    date_key INT PRIMARY KEY,
    full_date DATE NOT NULL UNIQUE,
    year INT NOT NULL,
    quarter INT NOT NULL,
    quarter_name VARCHAR(10) NOT NULL,
    month INT NOT NULL,
    month_name VARCHAR(15) NOT NULL,
    year_month VARCHAR(7) NOT NULL,
    day_of_month INT NOT NULL,
    day_of_week INT NOT NULL,
    day_name VARCHAR(15) NOT NULL,
    is_weekend BOOLEAN NOT NULL
);

INSERT INTO date_dim (
    date_key, full_date, year, quarter, quarter_name, 
    month, month_name, year_month, day_of_month, day_of_week, day_name, is_weekend
)
SELECT 
    CAST(TO_CHAR(datum, 'YYYYMMDD') AS INT) AS date_key,
    datum AS full_date,
    EXTRACT(YEAR FROM datum) AS year,
    EXTRACT(QUARTER FROM datum) AS quarter,
    'Q' || EXTRACT(QUARTER FROM datum) AS quarter_name,
    EXTRACT(MONTH FROM datum) AS month,
    TO_CHAR(datum, 'Month') AS month_name,
    TO_CHAR(datum, 'YYYY-MM') AS year_month,
    EXTRACT(DAY FROM datum) AS day_of_month,
    EXTRACT(ISODOW FROM datum) AS day_of_week,
    TO_CHAR(datum, 'Day') AS day_name,
    CASE WHEN EXTRACT(ISODOW FROM datum) IN (6, 7) THEN TRUE ELSE FALSE END AS is_weekend
FROM generate_series('2010-01-01'::DATE, '2012-12-31'::DATE, '1 day'::INTERVAL) AS datum;


-- ===============================================================================
-- PHASE 4: RFM CUSTOMER SEGMENTATION
-- ===============================================================================

DROP VIEW IF EXISTS customer_segments CASCADE;
CREATE VIEW customer_segments AS
WITH max_dataset_date AS (
    SELECT MAX(order_date) AS max_date FROM sales_fact
),
customer_rfm_raw AS (
    SELECT 
        customer_id,
        country,
        MAX(order_date) AS last_order_date,
        CAST(EXTRACT(DAY FROM (SELECT max_date FROM max_dataset_date) - MAX(order_date)) AS INT) AS recency_days,
        COUNT(DISTINCT order_id) AS frequency_orders,
        SUM(line_revenue) AS monetary_value
    FROM sales_fact
    GROUP BY customer_id, country
),
rfm_scored AS (
    SELECT 
        customer_id,
        country,
        last_order_date,
        recency_days,
        frequency_orders,
        monetary_value,
        NTILE(5) OVER (ORDER BY recency_days DESC) AS r_score,
        NTILE(5) OVER (ORDER BY frequency_orders ASC) AS f_score,
        NTILE(5) OVER (ORDER BY monetary_value ASC) AS m_score
    FROM customer_rfm_raw
)
SELECT 
    customer_id,
    country,
    last_order_date,
    recency_days,
    frequency_orders,
    monetary_value,
    r_score,
    f_score,
    m_score,
    (r_score || f_score || m_score) AS rfm_code,
    CASE 
        WHEN r_score >= 4 AND f_score >= 4 AND m_score >= 4 THEN 'Champions'
        WHEN r_score >= 3 AND f_score >= 3 AND m_score >= 3 THEN 'Loyal Customers'
        WHEN r_score >= 4 AND f_score <= 2 THEN 'New Customers'
        WHEN r_score = 3 AND f_score <= 3 THEN 'Needs Attention'
        WHEN r_score <= 2 AND f_score >= 3 THEN 'At Risk'
        ELSE 'Lost'
    END AS segment_label
FROM rfm_scored;


-- ===============================================================================
-- PHASE 5: POWER BI ANALYTICAL VIEWS
-- ===============================================================================

-- 1. KPI Summary View
DROP VIEW IF EXISTS v_kpi_summary CASCADE;
CREATE VIEW v_kpi_summary AS
WITH customer_order_counts AS (
    SELECT customer_id, COUNT(DISTINCT order_id) AS total_orders
    FROM sales_fact
    GROUP BY customer_id
)
SELECT 
    ROUND(SUM(sf.line_revenue), 2) AS total_revenue,
    COUNT(DISTINCT sf.order_id) AS total_orders,
    ROUND(SUM(sf.line_revenue) / NULLIF(COUNT(DISTINCT sf.order_id), 0), 2) AS average_order_value,
    COUNT(DISTINCT sf.customer_id) AS total_unique_customers,
    COUNT(DISTINCT sf.product_id) AS total_active_skus,
    SUM(sf.quantity) AS total_items_sold,
    COUNT(CASE WHEN coc.total_orders > 1 THEN 1 END) AS repeat_customers_count,
    ROUND(COUNT(CASE WHEN coc.total_orders > 1 THEN 1 END) * 100.0 / NULLIF(COUNT(DISTINCT sf.customer_id), 0), 2) AS repeat_purchase_rate_pct
FROM sales_fact sf
LEFT JOIN customer_order_counts coc ON sf.customer_id = coc.customer_id;

-- 2. Top & Bottom Products View
DROP VIEW IF EXISTS v_top_bottom_products CASCADE;
CREATE VIEW v_top_bottom_products AS
WITH product_agg AS (
    SELECT 
        product_id,
        product_description,
        SUM(line_revenue) AS total_revenue,
        SUM(quantity) AS total_quantity_sold,
        COUNT(DISTINCT order_id) AS order_frequency,
        COUNT(DISTINCT customer_id) AS buyer_count
    FROM sales_fact
    GROUP BY product_id, product_description
),
ranked_products AS (
    SELECT 
        *,
        DENSE_RANK() OVER (ORDER BY total_revenue DESC) AS rank_rev_top,
        DENSE_RANK() OVER (ORDER BY total_revenue ASC) AS rank_rev_bottom,
        DENSE_RANK() OVER (ORDER BY total_quantity_sold DESC) AS rank_qty_top,
        DENSE_RANK() OVER (ORDER BY total_quantity_sold ASC) AS rank_qty_bottom
    FROM product_agg
)
SELECT 
    product_id,
    product_description,
    total_revenue,
    total_quantity_sold,
    order_frequency,
    buyer_count,
    rank_rev_top,
    rank_qty_top,
    CASE 
        WHEN rank_rev_top <= 10 THEN 'Top 10 Revenue'
        WHEN rank_rev_bottom <= 10 THEN 'Bottom 10 Revenue'
        ELSE 'Middle Tier'
    END AS revenue_tier
FROM ranked_products;

-- 3. Monthly Sales by Country
DROP VIEW IF EXISTS v_sales_by_country_month CASCADE;
CREATE VIEW v_sales_by_country_month AS
SELECT 
    country,
    TO_CHAR(order_date, 'YYYY-MM') AS year_month,
    EXTRACT(YEAR FROM order_date) AS year,
    EXTRACT(MONTH FROM order_date) AS month,
    COUNT(DISTINCT order_id) AS total_orders,
    COUNT(DISTINCT customer_id) AS active_customers,
    SUM(quantity) AS total_units_sold,
    ROUND(SUM(line_revenue), 2) AS total_revenue,
    ROUND(SUM(line_revenue) / NULLIF(COUNT(DISTINCT order_id), 0), 2) AS avg_order_value
FROM sales_fact
GROUP BY country, TO_CHAR(order_date, 'YYYY-MM'), EXTRACT(YEAR FROM order_date), EXTRACT(MONTH FROM order_date);

-- 4. Cohort Retention View
DROP VIEW IF EXISTS v_cohort_retention CASCADE;
CREATE VIEW v_cohort_retention AS
WITH customer_first_purchase AS (
    SELECT 
        customer_id,
        TO_CHAR(MIN(order_date), 'YYYY-MM') AS cohort_month,
        MIN(order_date) AS first_purchase_date
    FROM sales_fact
    GROUP BY customer_id
),
cohort_transactions AS (
    SELECT 
        sf.customer_id,
        fp.cohort_month,
        TO_CHAR(sf.order_date, 'YYYY-MM') AS transaction_month,
        (
            (EXTRACT(YEAR FROM sf.order_date) - EXTRACT(YEAR FROM fp.first_purchase_date)) * 12 +
            (EXTRACT(MONTH FROM sf.order_date) - EXTRACT(MONTH FROM fp.first_purchase_date))
        ) AS cohort_index,
        sf.line_revenue
    FROM sales_fact sf
    JOIN customer_first_purchase fp ON sf.customer_id = fp.customer_id
)
SELECT 
    cohort_month,
    cohort_index,
    COUNT(DISTINCT customer_id) AS active_cohort_customers,
    ROUND(SUM(line_revenue), 2) AS cohort_revenue
FROM cohort_transactions
GROUP BY cohort_month, cohort_index;

-- 5. Growth Metrics View
DROP VIEW IF EXISTS v_growth_metrics CASCADE;
CREATE VIEW v_growth_metrics AS
WITH monthly_rev AS (
    SELECT 
        TO_CHAR(order_date, 'YYYY-MM') AS year_month,
        EXTRACT(YEAR FROM order_date) AS year,
        EXTRACT(MONTH FROM order_date) AS month,
        SUM(line_revenue) AS monthly_revenue
    FROM sales_fact
    GROUP BY TO_CHAR(order_date, 'YYYY-MM'), EXTRACT(YEAR FROM order_date), EXTRACT(MONTH FROM order_date)
)
SELECT 
    mr.year_month,
    mr.year,
    mr.month,
    ROUND(mr.monthly_revenue, 2) AS current_month_revenue,
    ROUND(LAG(mr.monthly_revenue, 1) OVER (ORDER BY mr.year_month), 2) AS prev_month_revenue,
    ROUND(
        (mr.monthly_revenue - LAG(mr.monthly_revenue, 1) OVER (ORDER BY mr.year_month)) / 
        NULLIF(LAG(mr.monthly_revenue, 1) OVER (ORDER BY mr.year_month), 0) * 100.0, 2
    ) AS mom_growth_pct,
    ROUND(LAG(mr.monthly_revenue, 12) OVER (ORDER BY mr.year_month), 2) AS same_month_prev_year_revenue,
    ROUND(
        (mr.monthly_revenue - LAG(mr.monthly_revenue, 12) OVER (ORDER BY mr.year_month)) / 
        NULLIF(LAG(mr.monthly_revenue, 12) OVER (ORDER BY mr.year_month), 0) * 100.0, 2
    ) AS yoy_growth_pct
FROM monthly_rev mr;

COMMIT;

-- Pipeline Execution Notice
SELECT 'Master Retail Pipeline Built Successfully!' AS status_message;
