USE master;
GO
IF DB_ID('Ecommerce_DWH') IS NOT NULL
BEGIN
    ALTER DATABASE Ecommerce_DWH SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE Ecommerce_DWH;
END
GO

CREATE DATABASE Ecommerce_DWH;
GO
USE Ecommerce_DWH;
GO

-- Khởi tạo 5 tầng kiến trúc Data Warehouse
CREATE SCHEMA source_oltp; -- Giả lập Database của Backend
GO
CREATE SCHEMA stg;         -- Tầng Staging: Dữ liệu thô mới kéo về
GO
CREATE SCHEMA core;        -- Tầng Core: Star Schema (Fact & Dim)
GO
CREATE SCHEMA mart;        -- Tầng Data Mart: Phục vụ báo cáo BI
GO
CREATE SCHEMA audit;       -- Lưu Watermark, Log và kết quả đối soát
GO

-- Bảng lưu mốc thời gian phục vụ Incremental Load
CREATE TABLE audit.etl_watermark (
    table_name VARCHAR(50) PRIMARY KEY,
    last_extracted_at DATETIME2 NOT NULL
);

INSERT INTO audit.etl_watermark VALUES 
('customers', '1970-01-01 00:00:00'),
('orders', '1970-01-01 00:00:00');

-- Bảng lưu lịch sử chạy Pipeline & Đối soát
CREATE TABLE audit.pipeline_logs (
    log_id INT IDENTITY(1,1) PRIMARY KEY,
    step_name VARCHAR(100),
    rows_affected INT,
    status VARCHAR(20),
    message NVARCHAR(MAX),
    logged_at DATETIME2 DEFAULT SYSDATETIME()
);
GO