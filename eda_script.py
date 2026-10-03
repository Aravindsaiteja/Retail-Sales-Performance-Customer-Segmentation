import pandas as pd
import numpy as np
import matplotlib.pyplot as plt
import seaborn as sns
import os

# Set style
sns.set_theme(style="whitegrid")
plt.rcParams['font.sans-serif'] = 'DejaVu Sans'
plt.rcParams['axes.edgecolor'] = '#cccccc'
plt.rcParams['axes.linewidth'] = 0.8

os.makedirs('eda_charts', exist_ok=True)

print("Loading raw Excel dataset...")
df = pd.read_excel('Online Retail.xlsx')
raw_len = len(df)

# Data Quality Audit
missing_cust = df['CustomerID'].isnull().sum()
cancelled = df['InvoiceNo'].astype(str).str.startswith('C').sum()
neg_qty = (df['Quantity'] <= 0).sum()
neg_price = (df['UnitPrice'] <= 0).sum()
duplicates = df.duplicated().sum()

print("=== DATA QUALITY AUDIT ===")
print(f"Raw Rows: {raw_len:,}")
print(f"Missing CustomerID: {missing_cust:,} ({missing_cust/raw_len*100:.2f}%)")
print(f"Cancelled Invoices (C...): {cancelled:,} ({cancelled/raw_len*100:.2f}%)")
print(f"Non-positive Quantity (<=0): {neg_qty:,} ({neg_qty/raw_len*100:.2f}%)")
print(f"Non-positive Price (<=0): {neg_price:,} ({neg_price/raw_len*100:.2f}%)")
print(f"Duplicate Rows: {duplicates:,} ({duplicates/raw_len*100:.2f}%)")

# Data Cleaning
clean_df = df.copy()
clean_df = clean_df.dropna(subset=['CustomerID'])
clean_df = clean_df[~clean_df['InvoiceNo'].astype(str).str.startswith('C')]
clean_df = clean_df[(clean_df['Quantity'] > 0) & (clean_df['UnitPrice'] > 0)]
clean_df = clean_df.drop_duplicates()

clean_df['CustomerID'] = clean_df['CustomerID'].astype(int)
clean_df['InvoiceDate'] = pd.to_datetime(clean_df['InvoiceDate'])
clean_df['LineRevenue'] = clean_df['Quantity'] * clean_df['UnitPrice']

print("\n=== CLEANED DATASET SUMMARY ===")
print(f"Clean Rows: {len(clean_df):,}")
print(f"Clean Orders: {clean_df['InvoiceNo'].nunique():,}")
print(f"Clean Customers: {clean_df['CustomerID'].nunique():,}")
print(f"Clean Products: {clean_df['StockCode'].nunique():,}")
print(f"Total Revenue: ${clean_df['LineRevenue'].sum():,.2f}")
print(f"Average Order Value: ${clean_df.groupby('InvoiceNo')['LineRevenue'].sum().mean():,.2f}")
print(f"Date Range: {clean_df['InvoiceDate'].min()} to {clean_df['InvoiceDate'].max()}")

# Export cleaned CSV
clean_df.to_csv('cleaned_online_retail.csv', index=False)
print("Saved cleaned dataset to cleaned_online_retail.csv")

# --- EDA & VISUALIZATIONS ---

# 1. Monthly Revenue Trend
clean_df['YearMonth'] = clean_df['InvoiceDate'].dt.to_period('M')
monthly_rev = clean_df.groupby('YearMonth')['LineRevenue'].sum().reset_index()
monthly_rev['YearMonth_Str'] = monthly_rev['YearMonth'].astype(str)

plt.figure(figsize=(12, 6))
ax = sns.lineplot(data=monthly_rev, x='YearMonth_Str', y='LineRevenue', marker='o', color='#1A365D', linewidth=2.5, markersize=8)
plt.title('Total Revenue Trend Over Time (Dec 2010 - Dec 2011)', fontsize=14, fontweight='bold', pad=15)
plt.xlabel('Month', fontsize=11, labelpad=10)
plt.ylabel('Revenue ($)', fontsize=11, labelpad=10)
plt.xticks(rotation=45)
ax.yaxis.set_major_formatter('${x:,.0f}')
plt.tight_layout()
plt.savefig('eda_charts/monthly_revenue_trend.png', dpi=300)
plt.close()

# 2. Top 10 Products by Revenue
top_products = clean_df.groupby('Description')['LineRevenue'].sum().nlargest(10).reset_index()

plt.figure(figsize=(10, 6))
ax = sns.barplot(data=top_products, y='Description', x='LineRevenue', hue='Description', palette='Blues_r', legend=False)
plt.title('Top 10 Products by Revenue', fontsize=14, fontweight='bold', pad=15)
plt.xlabel('Total Revenue ($)', fontsize=11, labelpad=10)
plt.ylabel('Product Description', fontsize=11, labelpad=10)
ax.xaxis.set_major_formatter('${x:,.0f}')
plt.tight_layout()
plt.savefig('eda_charts/top_10_products.png', dpi=300)
plt.close()

# 3. Revenue by Country
country_rev = clean_df.groupby('Country')['LineRevenue'].sum().nlargest(10).reset_index()

plt.figure(figsize=(10, 6))
ax = sns.barplot(data=country_rev, y='Country', x='LineRevenue', hue='Country', palette='viridis', legend=False)
plt.title('Top 10 Countries by Revenue', fontsize=14, fontweight='bold', pad=15)
plt.xlabel('Total Revenue ($)', fontsize=11, labelpad=10)
plt.ylabel('Country', fontsize=11, labelpad=10)
ax.xaxis.set_major_formatter('${x:,.0f}')
plt.tight_layout()
plt.savefig('eda_charts/revenue_by_country.png', dpi=300)
plt.close()

# 4. Distribution of Order Values
order_values = clean_df.groupby('InvoiceNo')['LineRevenue'].sum()

plt.figure(figsize=(10, 6))
sns.histplot(order_values[order_values < 1000], bins=50, kde=True, color='#2B6CB0')
plt.title('Distribution of Order Values (Orders < $1,000)', fontsize=14, fontweight='bold', pad=15)
plt.xlabel('Order Value ($)', fontsize=11, labelpad=10)
plt.ylabel('Frequency', fontsize=11, labelpad=10)
plt.tight_layout()
plt.savefig('eda_charts/order_value_distribution.png', dpi=300)
plt.close()

# 5. RFM Benchmarks
max_date = clean_df['InvoiceDate'].max() + pd.Timedelta(days=1)
rfm = clean_df.groupby('CustomerID').agg({
    'InvoiceDate': lambda x: (max_date - x.max()).days,
    'InvoiceNo': 'nunique',
    'LineRevenue': 'sum'
}).reset_index()

rfm.columns = ['CustomerID', 'Recency', 'Frequency', 'Monetary']

rfm['R_Score'] = pd.qcut(rfm['Recency'], 5, labels=[5, 4, 3, 2, 1])
rfm['F_Score'] = pd.qcut(rfm['Frequency'].rank(method='first'), 5, labels=[1, 2, 3, 4, 5])
rfm['M_Score'] = pd.qcut(rfm['Monetary'], 5, labels=[1, 2, 3, 4, 5])

def rfm_segment(row):
    r, f, m = int(row['R_Score']), int(row['F_Score']), int(row['M_Score'])
    if r >= 4 and f >= 4 and m >= 4:
        return 'Champions'
    elif r >= 3 and f >= 3 and m >= 3:
        return 'Loyal Customers'
    elif r >= 4 and f <= 2:
        return 'New Customers'
    elif r == 3 and f <= 3:
        return 'Needs Attention'
    elif r <= 2 and f >= 3:
        return 'At Risk'
    else:
        return 'Lost'

rfm['Segment'] = rfm.apply(rfm_segment, axis=1)
segment_summary = rfm.groupby('Segment').agg(
    Customer_Count=('CustomerID', 'count'),
    Total_Revenue=('Monetary', 'sum'),
    Avg_Revenue=('Monetary', 'mean')
).reset_index()

print("\n=== RFM SEGMENT SUMMARY (BENCHMARK) ===")
print(segment_summary.to_string(index=False))

plt.figure(figsize=(10, 6))
ax = sns.barplot(data=segment_summary, x='Segment', y='Customer_Count', hue='Segment', palette='Set2', legend=False)
plt.title('Customer Count by RFM Segment', fontsize=14, fontweight='bold', pad=15)
plt.xlabel('Customer Segment', fontsize=11, labelpad=10)
plt.ylabel('Customer Count', fontsize=11, labelpad=10)
plt.tight_layout()
plt.savefig('eda_charts/rfm_segments.png', dpi=300)
plt.close()

print("\nEDA and Visualizations completed successfully!")
