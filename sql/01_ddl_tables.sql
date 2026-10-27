USE Ecommerce_DWH;
GO

-- 1. TẦNG NGUỒN (SOURCE OLTP)
CREATE TABLE source_oltp.customers (
    customer_id INT PRIMARY KEY,
    full_name NVARCHAR(100),
    city NVARCHAR(50),
    membership_tier VARCHAR(20),
    updated_at DATETIME2
);

CREATE TABLE source_oltp.orders (
    order_id INT PRIMARY KEY,
    customer_id INT,
    order_date DATE,
    status VARCHAR(20),
    total_amount DECIMAL(12, 2),
    updated_at DATETIME2
);

-- 2. TẦNG STAGING (Cấu trúc giống hệt nguồn)
SELECT TOP 0 * INTO stg.customers FROM source_oltp.customers;
SELECT TOP 0 * INTO stg.orders FROM source_oltp.orders;

-- 3. TẦNG CORE (Star Schema + SCD Type 2 + Partitioning)
CREATE TABLE core.dim_customers (
    customer_sk INT IDENTITY(1,1) PRIMARY KEY,
    customer_id INT,
    full_name NVARCHAR(100),
    city NVARCHAR(50),
    membership_tier VARCHAR(20),
    valid_from DATETIME2,
    valid_to DATETIME2,
    is_current BIT
);

CREATE NONCLUSTERED INDEX idx_dim_cust_current 
ON core.dim_customers(customer_id) WHERE is_current = 1;

-- Thiết lập Partition theo tháng cho bảng Fact Orders
CREATE PARTITION FUNCTION pf_order_date (DATE)
AS RANGE RIGHT FOR VALUES ('2026-09-01', '2026-10-01', '2026-11-01');

CREATE PARTITION SCHEME ps_order_date
AS PARTITION pf_order_date ALL TO ([PRIMARY]);

CREATE TABLE core.fact_orders (
    order_id INT,
    customer_sk INT,
    customer_id INT,
    order_date DATE,
    status VARCHAR(20),
    total_amount DECIMAL(12, 2),
    updated_at DATETIME2,
    CONSTRAINT PK_fact_orders PRIMARY KEY (order_id, order_date)
) ON ps_order_date(order_date);

-- 4. TẦNG DATA MART (Báo cáo tổng hợp cho BI)
CREATE TABLE mart.daily_revenue (
    report_date DATE,
    city NVARCHAR(50),
    membership_tier VARCHAR(20),
    total_orders INT,
    net_revenue DECIMAL(15, 2),
    PRIMARY KEY (report_date, city, membership_tier)
);
GO