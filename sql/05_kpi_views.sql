-- ===============================================================================
-- Phase 5 — Sales KPI & Product Performance Analytical Views (Power BI Layer)
-- Project: Retail Sales Performance & Customer Segmentation
-- Dialect: PostgreSQL
-- ===============================================================================

-- -------------------------------------------------------------------------------
-- 1. View: v_kpi_summary
-- Intended Use: Top-level scorecard cards in Power BI executive dashboard
-- -------------------------------------------------------------------------------
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
    ROUND(
        COUNT(CASE WHEN coc.total_orders > 1 THEN 1 END) * 100.0 / 
        NULLIF(COUNT(DISTINCT sf.customer_id), 0), 2
    ) AS repeat_purchase_rate_pct
FROM sales_fact sf
LEFT JOIN customer_order_counts coc ON sf.customer_id = coc.customer_id;

-- -------------------------------------------------------------------------------
-- 2. View: v_top_bottom_products
-- Intended Use: Product leaderboard tables & horizontal bar charts
-- -------------------------------------------------------------------------------
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

-- -------------------------------------------------------------------------------
-- 3. View: v_sales_by_country_month
-- Intended Use: Time-series revenue trend by country & geo map visuals
-- -------------------------------------------------------------------------------
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

-- -------------------------------------------------------------------------------
-- 4. View: v_cohort_retention
-- Intended Use: Cohort analysis heatmap (Customer First Purchase Month vs Monthly Revenue)
-- -------------------------------------------------------------------------------
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

-- -------------------------------------------------------------------------------
-- 5. View: v_growth_metrics
-- Intended Use: Executive MoM and YoY financial growth analysis
-- -------------------------------------------------------------------------------
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
