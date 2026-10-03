-- ===============================================================================
-- Phase 2 — Data Load Validation Queries
-- Project: Retail Sales Performance & Customer Segmentation
-- ===============================================================================

-- 1. Confirm Row Counts per Table
SELECT 'customers' AS table_name, COUNT(*) AS row_count FROM customers
UNION ALL
SELECT 'products' AS table_name, COUNT(*) AS row_count FROM products
UNION ALL
SELECT 'orders' AS table_name, COUNT(*) AS row_count FROM orders
UNION ALL
SELECT 'order_items' AS table_name, COUNT(*) AS row_count FROM order_items;

-- 2. Check for Orphaned Foreign Keys in Orders (Orders without valid customer)
SELECT COUNT(*) AS orphaned_orders_count
FROM orders o
LEFT JOIN customers c ON o.customer_id = c.customer_id
WHERE c.customer_id IS NULL;

-- 3. Check for Orphaned Foreign Keys in Order Items (Line items without valid order or product)
SELECT 
    SUM(CASE WHEN o.order_id IS NULL THEN 1 ELSE 0 END) AS invalid_order_refs,
    SUM(CASE WHEN p.product_id IS NULL THEN 1 ELSE 0 END) AS invalid_product_refs
FROM order_items oi
LEFT JOIN orders o ON oi.order_id = o.order_id
LEFT JOIN products p ON oi.product_id = p.product_id;

-- 4. Check for Duplicate Line Items (Same order_id and product_id pair)
SELECT order_id, product_id, COUNT(*) AS duplicate_count
FROM order_items
GROUP BY order_id, product_id
HAVING COUNT(*) > 1;

-- 5. Revenue Integrity Validation (Sum of line revenues)
SELECT 
    COUNT(DISTINCT o.order_id) AS total_orders,
    COUNT(DISTINCT o.customer_id) AS total_customers,
    SUM(oi.line_revenue) AS total_revenue,
    AVG(oi.line_revenue) AS avg_line_item_value
FROM orders o
JOIN order_items oi ON o.order_id = oi.order_id;
