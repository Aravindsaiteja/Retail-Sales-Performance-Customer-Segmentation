import sqlite3
import pandas as pd
import numpy as np

print("Loading cleaned CSV into SQLite in-memory database to test SQL transformations...")
df = pd.read_csv('cleaned_online_retail.csv')
df['InvoiceDate'] = pd.to_datetime(df['InvoiceDate'])

conn = sqlite3.connect(':memory:')

# 1. Load staging table
df.to_sql('stg_online_retail', conn, if_exists='replace', index=False)

cursor = conn.cursor()

# 2. Execute Schema Creation
cursor.executescript("""
DROP TABLE IF EXISTS order_items;
DROP TABLE IF EXISTS orders;
DROP TABLE IF EXISTS products;
DROP TABLE IF EXISTS customers;
DROP TABLE IF EXISTS date_dim;

CREATE TABLE customers (
    customer_id INTEGER PRIMARY KEY,
    country TEXT NOT NULL,
    first_order_date TIMESTAMP
);

CREATE TABLE products (
    product_id TEXT PRIMARY KEY,
    description TEXT,
    unit_price REAL NOT NULL
);

CREATE TABLE orders (
    order_id TEXT PRIMARY KEY,
    customer_id INTEGER NOT NULL,
    order_date TIMESTAMP NOT NULL,
    country TEXT NOT NULL,
    FOREIGN KEY (customer_id) REFERENCES customers(customer_id)
);

CREATE TABLE order_items (
    order_item_id INTEGER PRIMARY KEY AUTOINCREMENT,
    order_id TEXT NOT NULL,
    product_id TEXT NOT NULL,
    quantity INTEGER NOT NULL CHECK (quantity > 0),
    unit_price REAL NOT NULL CHECK (unit_price > 0),
    line_revenue REAL NOT NULL,
    FOREIGN KEY (order_id) REFERENCES orders(order_id),
    FOREIGN KEY (product_id) REFERENCES products(product_id)
);

-- Populating normalized tables
INSERT INTO customers (customer_id, country, first_order_date)
SELECT CustomerID, Country, MIN(InvoiceDate)
FROM stg_online_retail
GROUP BY CustomerID;

INSERT INTO products (product_id, description, unit_price)
SELECT StockCode, Description, MAX(UnitPrice)
FROM stg_online_retail
GROUP BY StockCode;

INSERT INTO orders (order_id, customer_id, order_date, country)
SELECT InvoiceNo, CustomerID, MIN(InvoiceDate), Country
FROM stg_online_retail
GROUP BY InvoiceNo, CustomerID, Country;

INSERT INTO order_items (order_id, product_id, quantity, unit_price, line_revenue)
SELECT InvoiceNo, StockCode, Quantity, UnitPrice, (Quantity * UnitPrice)
FROM stg_online_retail;
""")

print("Normalized tables created and populated!")

# 3. Create Views
cursor.executescript("""
DROP VIEW IF EXISTS clean_orders;
CREATE VIEW clean_orders AS
SELECT o.order_id, o.customer_id, o.order_date, o.country
FROM orders o
WHERE o.customer_id IS NOT NULL;

DROP VIEW IF EXISTS sales_fact;
CREATE VIEW sales_fact AS
SELECT 
    oi.order_item_id,
    oi.order_id,
    o.customer_id,
    oi.product_id,
    p.description,
    o.order_date,
    strftime('%Y-%m', o.order_date) AS year_month,
    o.country,
    oi.quantity,
    oi.unit_price,
    oi.line_revenue
FROM order_items oi
JOIN orders o ON oi.order_id = o.order_id
JOIN products p ON oi.product_id = p.product_id;
""")

print("Views `clean_orders` and `sales_fact` created successfully!")

# 4. Test Validation Queries
res_cust = cursor.execute("SELECT COUNT(*) FROM customers").fetchone()[0]
res_prod = cursor.execute("SELECT COUNT(*) FROM products").fetchone()[0]
res_orders = cursor.execute("SELECT COUNT(*) FROM orders").fetchone()[0]
res_items = cursor.execute("SELECT COUNT(*) FROM order_items").fetchone()[0]
res_rev = cursor.execute("SELECT SUM(line_revenue) FROM order_items").fetchone()[0]

print(f"Validation Row Counts:\n - Customers: {res_cust:,}\n - Products: {res_prod:,}\n - Orders: {res_orders:,}\n - Order Items: {res_items:,}\n - Total Revenue: ${res_rev:,.2f}")

# 5. Test RFM CTE Query
rfm_df = pd.read_sql_query("""
WITH max_d AS (
    SELECT MAX(order_date) AS max_date FROM sales_fact
),
cust_rfm AS (
    SELECT 
        customer_id,
        CAST(julianday((SELECT max_date FROM max_d)) - julianday(MAX(order_date)) AS INTEGER) AS recency,
        COUNT(DISTINCT order_id) AS frequency,
        SUM(line_revenue) AS monetary
    FROM sales_fact
    GROUP BY customer_id
),
scored_rfm AS (
    SELECT 
        customer_id,
        recency,
        frequency,
        monetary,
        NTILE(5) OVER (ORDER BY recency DESC) AS r_score,
        NTILE(5) OVER (ORDER BY frequency ASC) AS f_score,
        NTILE(5) OVER (ORDER BY monetary ASC) AS m_score
    FROM cust_rfm
),
segmented AS (
    SELECT 
        customer_id,
        recency,
        frequency,
        monetary,
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
        END AS segment
    FROM scored_rfm
)
SELECT 
    segment,
    COUNT(customer_id) AS customer_count,
    ROUND(SUM(monetary), 2) AS total_revenue,
    ROUND(AVG(monetary), 2) AS avg_revenue
FROM segmented
GROUP BY segment
ORDER BY total_revenue DESC;
""", conn)

print("\n=== SQL RFM SEGMENTATION RESULTS ===")
print(rfm_df.to_string(index=False))

conn.close()
print("\nSQL Pipeline Validation Test Passed!")
