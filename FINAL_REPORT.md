# 📊 Executive Report & Data Model Validation
## Retail Sales Performance & Customer Segmentation Project

---

## 📌 Executive Summary

This report presents the final synthesis of the **Retail Sales Performance & Customer Segmentation** capstone project. Utilizing transactional records from the **UCI Online Retail dataset** (covering transactions from December 2010 to December 2011), we established a robust data engineering pipeline in **PostgreSQL** and an interactive analytics suite in **Power BI**.

The dataset initially contained **541,909 raw transaction lines**. Following standard data warehouse cleaning procedures (removing anonymous guest orders without CustomerIDs, cancelled invoices starting with 'C', negative quantities/prices, and exact duplicate rows), the dataset was transformed into a clean analytical fact layer consisting of **392,692 line items across 18,532 orders and 4,338 unique identified customers**, representing **$8,887,208.89** in total revenue.

---

## 1. 🔍 Data Model Validation Checklist (SQL vs. Power BI)

To ensure strict data model integrity, financial fidelity, and accuracy between the PostgreSQL database and the Power BI DAX semantic engine, a systematic validation was performed across all core KPIs and customer segments.

| Metric / Segment | Direct SQL Query Benchmark | Power BI DAX Measure Value | Status | Variance / Notes |
| :--- | :--- | :--- | :---: | :--- |
| **Total Revenue** | `$8,887,208.89` | `$8,887,209` | `MATCH` | Exact match (0.00% variance) |
| **Total Orders** | `18,532` | `18,532` | `MATCH` | Exact count of distinct orders |
| **Total Unique Customers** | `4,338` | `4,338` | `MATCH` | Exact count of unique customer IDs |
| **Average Order Value (AOV)**| `$479.56` | `$479.56` | `MATCH` | `Total Revenue / Total Orders` |
| **Repeat Purchase Rate** | `65.51%` | `65.51%` | `MATCH` | Customers with >1 orders |
| **Champions Segment Count** | `957` customers | `957` customers | `MATCH` | R: 4-5, F: 4-5, M: 4-5 |
| **Champions Revenue** | `$5,791,640.74` | `$5,791,641` | `MATCH` | **65.17%** of total revenue |
| **Loyal Customers Count** | `764` customers | `764` customers | `MATCH` | R: 3-5, F: 3-5, M: 3-5 |
| **Loyal Customers Revenue** | `$1,396,513.16` | `$1,396,513` | `MATCH` | **15.71%** of total revenue |
| **At Risk Segment Count** | `643` customers | `643` customers | `MATCH` | High past spend, low recency |
| **At Risk Segment Revenue** | `$798,052.51` | `$798,053` | `MATCH` | **8.98%** of total revenue |
| **Lost Segment Count** | `1,236` customers | `1,236` customers | `MATCH` | Churned low-value buyers |
| **Needs Attention Count** | `419` customers | `419` customers | `MATCH` | Moderate recency/frequency |
| **New Customers Count** | `319` customers | `319` customers | `MATCH` | Recent first-time buyers |

---

## 2. 💡 Key Business Insights Discovered

### Insight 1: Extreme Revenue Concentration in "Champions" (Pareto Rule)
- **Finding:** The **Champions** segment comprises only **22.06%** of total customers (957 out of 4,338) but accounts for **65.17%** ($5.79M) of total company revenue.
- **Strategic Impact:** The company relies heavily on a core tier of ultra-high-value wholesale buyers. Introducing a dedicated VIP Loyalty / Account Manager program for this top quintile is essential for revenue retention.

### Insight 2: Substantial Churn Risk in "At Risk" High-Value Customers
- **Finding:** **643 customers** who generated **$798,052.51** in historical revenue are currently classified as **At Risk** (they have not made a purchase in over 90–120 days).
- **Strategic Impact:** Because these customers previously demonstrated high spending capacity, re-engaging them via targeted email campaigns, exclusive discount incentives, or personalized product recommendations yields a significantly higher ROI than acquiring new cold customers.

### Insight 3: Q4 Holiday Seasonality Spike
- **Finding:** Monthly revenue climbs steadily from **$550K/month** in early Q1–Q3 to a massive peak of **$1,161,817.38** in November 2011 (a **+111% increase** over average monthly baseline).
- **Strategic Impact:** Supply chain inventory purchasing and warehouse staffing must be scaled up starting in August/September to avoid stockouts during the October–December peak season.

### Insight 4: Geographic Market Dominance
- **Finding:** The **United Kingdom** represents **81.5%** ($7.30M) of total revenue, followed by Germany ($228K) and France ($197K).
- **Strategic Impact:** International expansion across continental Europe remains an untapped growth lever. Streamlining cross-border shipping and multi-currency pricing can drive international revenue share from 18.5% to 30%+.

---

## 3. ⚠️ Dataset Limitations

1. **Single-Retailer Scope:** The dataset represents transactions from a single UK-based non-store online retailer specializing in gift items. Findings may not generalize to traditional brick-and-mortar retail or enterprise B2B SaaS.
2. **1-Year Time Horizon:** The data spans December 1, 2010 to December 9, 2011 (~12.3 months). This limited timeframe restricts multi-year longitudinal trend analysis and long-term cohort retention modeling beyond 12 months.
3. **High Proportion of Unidentified Customers (24.9%):** 135,080 transaction rows lacked CustomerIDs (guest checkout). While appropriately segregated into a separate staging channel, guest purchase patterns cannot be tracked in customer RFM profiles.
4. **Lack of Operational Cost Data:** Unit costs, shipping fees, and marketing acquisition costs (CAC) were absent, limiting financial analysis to gross top-line revenue rather than net profit margin.

---

## 4. 🚀 Strategic Recommendations & Next Steps

1. **Predictive Churn Scoring & Machine Learning Integration:**
   - Extend the SQL RFM model by training a Python Machine Learning classification model (e.g., XGBoost / Random Forest) to predict individual customer churn probability 30 days in advance based on purchase frequency velocity.

2. **Automated Marketing Campaign Triggers:**
   - Integrate Power BI / PostgreSQL segment views with CRM automation tools (e.g., HubSpot / Klaviyo) to trigger automated email flows:
     - *Champions:* Exclusive preview of new seasonal product launches.
     - *At Risk:* Win-back campaign with a 15% discount code valid for 14 days.
     - *New Customers:* 3-part onboarding email sequence highlighting best-selling product categories.

3. **Customer Lifetime Value (CLV) Forecasting:**
   - Implement BG/NBD (Beta-Geometric/Negative Binomial Distribution) statistical models in Python to predict future transaction counts and customer lifetime value over 12–36 month horizons.

4. **Product Association & Basket Analysis (Market Basket Analysis):**
   - Run Apriori / FP-Growth algorithms on `order_items` to identify high-affinity product pairs (e.g., "Customers who bought Regency Cakestand also bought Teacups") for cross-selling widgets on the web store.
