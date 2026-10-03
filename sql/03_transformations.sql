-- ===============================================================================
-- Phase 3 — Data Cleaning & Transformation Layer
-- Project: Retail Sales Performance & Customer Segmentation
-- Dialect: PostgreSQL
-- ===============================================================================

-- -------------------------------------------------------------------------------
-- 1. View: clean_orders
-- Purpose: Excludes cancelled orders and any invalid transactions (null customer_id)
-- -------------------------------------------------------------------------------
DROP VIEW IF EXISTS clean_orders CASCADE;
CREATE VIEW clean_orders AS
SELECT 
    o.order_id,
    o.customer_id,
    o.order_date,
    o.country
FROM orders o
WHERE o.customer_id IS NOT NULL
  AND o.order_id NOT LIKE 'C%';

-- -------------------------------------------------------------------------------
-- 2. View: sales_fact
-- Purpose: Primary analytical fact view at the order item level with full details
-- -------------------------------------------------------------------------------
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
WHERE oi.quantity > 0 
  AND oi.unit_price > 0
  AND o.customer_id IS NOT NULL;

-- -------------------------------------------------------------------------------
-- 3. Table/View: date_dim
-- Purpose: Standard calendar dimension for slice-and-dice time intelligence
-- -------------------------------------------------------------------------------
DROP TABLE IF EXISTS date_dim CASCADE;
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

-- Populate date_dim spanning dataset timeline (2010 to 2012)
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
FROM generate_series(
    '2010-01-01'::DATE, 
    '2012-12-31'::DATE, 
    '1 day'::INTERVAL
) AS datum;

-- -------------------------------------------------------------------------------
-- 4. Analytical Transformation Queries
-- -------------------------------------------------------------------------------

-- 4.1 Monthly Revenue & Month-over-Month (MoM) Growth %
WITH monthly_sales AS (
    SELECT 
        TO_CHAR(order_date, 'YYYY-MM') AS year_month,
        SUM(line_revenue) AS monthly_revenue,
        COUNT(DISTINCT order_id) AS total_orders,
        COUNT(DISTINCT customer_id) AS active_customers
    FROM sales_fact
    GROUP BY TO_CHAR(order_date, 'YYYY-MM')
)
SELECT 
    year_month,
    monthly_revenue,
    LAG(monthly_revenue) OVER (ORDER BY year_month) AS prev_month_revenue,
    ROUND(
        (monthly_revenue - LAG(monthly_revenue) OVER (ORDER BY year_month)) / 
        NULLIF(LAG(monthly_revenue) OVER (ORDER BY year_month), 0) * 100.0, 2
    ) AS mom_growth_pct,
    total_orders,
    active_customers
FROM monthly_sales
ORDER BY year_month;

-- 4.2 Revenue and Order Distribution by Country
SELECT 
    country,
    COUNT(DISTINCT order_id) AS total_orders,
    COUNT(DISTINCT customer_id) AS total_customers,
    SUM(line_revenue) AS total_revenue,
    ROUND(SUM(line_revenue) * 100.0 / (SELECT SUM(line_revenue) FROM sales_fact), 2) AS revenue_share_pct
FROM sales_fact
GROUP BY country
ORDER BY total_revenue DESC;
