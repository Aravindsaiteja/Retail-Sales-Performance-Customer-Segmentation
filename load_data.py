"""
===============================================================================
Retail Sales Performance & Customer Segmentation — Data Loading Script
===============================================================================
Description:
    This script loads the cleaned transactional dataset (`cleaned_online_retail.csv`)
    into a normalized relational PostgreSQL database (or SQLite fallback for testing).

Tables Populated:
    1. customers     (customer_id, country, first_order_date)
    2. products      (product_id, description, unit_price)
    3. orders        (order_id, customer_id, order_date, country)
    4. order_items   (order_id, product_id, quantity, unit_price, line_revenue)

Requirements:
    pip install pandas sqlalchemy psycopg2-binary
"""

import os
import sys
import pandas as pd
from sqlalchemy import create_engine, text

# --- Configuration ---
# Default PostgreSQL Connection String (Update credentials as required)
DB_USER = os.getenv("DB_USER", "postgres")
DB_PASS = os.getenv("DB_PASS", "postgres")
DB_HOST = os.getenv("DB_HOST", "localhost")
DB_PORT = os.getenv("DB_PORT", "5432")
DB_NAME = os.getenv("DB_NAME", "retail_dw")

CSV_FILE = "cleaned_online_retail.csv"

def get_engine():
    """Create and return SQLAlchemy engine for PostgreSQL or SQLite fallback."""
    pg_url = f"postgresql://{DB_USER}:{DB_PASS}@{DB_HOST}:{DB_PORT}/{DB_NAME}"
    try:
        engine = create_engine(pg_url)
        with engine.connect() as conn:
            conn.execute(text("SELECT 1"))
        print(f"[INFO] Successfully connected to PostgreSQL at {DB_HOST}:{DB_PORT}/{DB_NAME}")
        return engine, "postgresql"
    except Exception as e:
        print(f"[WARNING] PostgreSQL connection failed ({e}). Falling back to SQLite local database `retail_dw.db`...")
        sqlite_engine = create_engine("sqlite:///retail_dw.db")
        return sqlite_engine, "sqlite"

def main():
    if not os.path.exists(CSV_FILE):
        print(f"[ERROR] Cleaned CSV file `{CSV_FILE}` not found. Run Phase 1 script first!")
        sys.exit(1)

    print(f"[INFO] Loading cleaned data from `{CSV_FILE}`...")
    df = pd.read_csv(CSV_FILE)
    df['InvoiceDate'] = pd.to_datetime(df['InvoiceDate'])

    engine, db_type = get_engine()

    # Step 1: Ensure Schema Exists
    schema_file = os.path.join("sql", "01_schema.sql")
    if os.path.exists(schema_file):
        print(f"[INFO] Executing schema DDL from `{schema_file}`...")
        with open(schema_file, "r") as f:
            ddl_sql = f.read()
        with engine.connect() as conn:
            # Handle PostgreSQL vs SQLite syntax compatibility if needed
            if db_type == "sqlite":
                ddl_sql = ddl_sql.replace("BIGSERIAL", "INTEGER").replace("TIMESTAMP", "DATETIME")
            for statement in ddl_sql.split(";"):
                stmt = statement.strip()
                if stmt:
                    conn.execute(text(stmt))
            conn.commit()
        print("[INFO] Schema DDL executed successfully.")

    # Step 2: Prepare Normalized Dataframes
    print("[INFO] Normalizing dataset into relational tables...")

    # Customers Table
    df_customers = df[['CustomerID', 'Country', 'InvoiceDate']].groupby('CustomerID').agg({
        'Country': 'first',
        'InvoiceDate': 'min'
    }).reset_index()
    df_customers.columns = ['customer_id', 'country', 'first_order_date']

    # Products Table
    df_products = df[['StockCode', 'Description', 'UnitPrice']].groupby('StockCode').agg({
        'Description': 'first',
        'UnitPrice': 'max'
    }).reset_index()
    df_products.columns = ['product_id', 'description', 'unit_price']

    # Orders Table
    df_orders = df[['InvoiceNo', 'CustomerID', 'InvoiceDate', 'Country']].groupby(['InvoiceNo', 'CustomerID', 'Country']).agg({
        'InvoiceDate': 'min'
    }).reset_index()
    df_orders = df_orders[['InvoiceNo', 'CustomerID', 'InvoiceDate', 'Country']]
    df_orders.columns = ['order_id', 'customer_id', 'order_date', 'country']

    # Order Items Table
    df_items = df[['InvoiceNo', 'StockCode', 'Quantity', 'UnitPrice', 'LineRevenue']].copy()
    df_items.columns = ['order_id', 'product_id', 'quantity', 'unit_price', 'line_revenue']

    # Step 3: Load Data into DB
    with engine.begin() as conn:
        print("[INFO] Inserting records into `customers` table...")
        df_customers.to_sql('customers', conn, if_exists='append', index=False)

        print("[INFO] Inserting records into `products` table...")
        df_products.to_sql('products', conn, if_exists='append', index=False)

        print("[INFO] Inserting records into `orders` table...")
        df_orders.to_sql('orders', conn, if_exists='append', index=False)

        print("[INFO] Inserting records into `order_items` table...")
        df_items.to_sql('order_items', conn, if_exists='append', index=False)

    print("\n[SUCCESS] All normalized tables successfully populated!")
    print(f"Summary:")
    print(f" - Customers:   {len(df_customers):,}")
    print(f" - Products:    {len(df_products):,}")
    print(f" - Orders:      {len(df_orders):,}")
    print(f" - Order Items: {len(df_items):,}")

if __name__ == "__main__":
    main()
