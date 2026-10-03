-- ===============================================================================
-- Phase 4 — RFM Customer Segmentation Layer
-- Project: Retail Sales Performance & Customer Segmentation
-- Dialect: PostgreSQL
-- ===============================================================================

/*
RFM SEGMENTATION RULE LOGIC:
----------------------------------------------------------------------------------
1. RECENCY (R): Days elapsed between customer's last order date and the max dataset date.
   - NTILE(5) OVER (ORDER BY recency DESC): Rank 5 = Most recent (Top 20%), Rank 1 = Oldest (Bottom 20%).

2. FREQUENCY (F): Total distinct completed orders per customer.
   - NTILE(5) OVER (ORDER BY frequency ASC): Rank 5 = Highest purchase frequency (Top 20%).

3. MONETARY (M): Total cumulative monetary expenditure per customer.
   - NTILE(5) OVER (ORDER BY monetary ASC): Rank 5 = Highest total spending (Top 20%).

SEGMENT MAPPING RULES:
----------------------------------------------------------------------------------
- Champions (R: 4-5, F: 4-5, M: 4-5): Best customers, bought recently, buy often, spend most.
- Loyal Customers (R: 3-5, F: 3-5, M: 3-5): Frequent buyers, high lifetime value, responsive to promos.
- New Customers (R: 4-5, F: 1-2): Bought recently, but low total orders. Opportunity to onboard.
- Needs Attention (R: 3, F: 1-3, M: 1-3): Average recency/frequency, at risk of slipping if neglected.
- At Risk (R: 1-2, F: 3-5): Spent heavily in the past, but haven't purchased recently. Re-engagement candidates.
- Lost (R: 1-2, F: 1-2): Low recency, frequency, and monetary. Churned or dormant customers.
*/

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

-- -------------------------------------------------------------------------------
-- RFM Summary Aggregation Query
-- -------------------------------------------------------------------------------
SELECT 
    segment_label,
    COUNT(customer_id) AS customer_count,
    ROUND(COUNT(customer_id) * 100.0 / SUM(COUNT(customer_id)) OVER (), 2) AS customer_share_pct,
    ROUND(SUM(monetary_value), 2) AS total_segment_revenue,
    ROUND(SUM(monetary_value) * 100.0 / SUM(SUM(monetary_value)) OVER (), 2) AS revenue_share_pct,
    ROUND(AVG(monetary_value), 2) AS avg_monetary_value,
    ROUND(AVG(recency_days), 1) AS avg_recency_days,
    ROUND(AVG(frequency_orders), 1) AS avg_frequency_orders
FROM customer_segments
GROUP BY segment_label
ORDER BY total_segment_revenue DESC;
