import pyodbc

SERVER_NAME = 'MSI'
DB_NAME = 'Ecommerce_DWH'

def get_connection():
    # Tự động chọn SQL Server Driver có sẵn trên máy của bạn
    drivers = [d for d in pyodbc.drivers() if 'SQL Server' in d]
    driver = drivers[-1] if drivers else 'SQL Server'
    conn_str = f'DRIVER={{{driver}}};SERVER={SERVER_NAME};DATABASE={DB_NAME};Trusted_Connection=yes;TrustServerCertificate=yes;'
    return pyodbc.connect(conn_str, autocommit=True)

def generate_initial_data(cursor):
    print("Đang sinh 10.000 khách hàng và 100.000 đơn hàng vào source_oltp...")
    cursor.execute("""
    SET NOCOUNT ON;
    ;WITH Nums AS (
        SELECT TOP (10000) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS n
        FROM sys.all_objects a CROSS JOIN sys.all_objects b
    )
    INSERT INTO source_oltp.customers (customer_id, full_name, city, membership_tier, updated_at)
    SELECT 
        n, CONCAT(N'Khách hàng ', n),
        CHOOSE((n % 5) + 1, N'Hà Nội', N'TP.HCM', N'Đà Nẵng', N'Cần Thơ', N'Hải Phòng'),
        CHOOSE((n % 3) + 1, 'Silver', 'Gold', 'Platinum'),
        DATEADD(DAY, -(n % 25), '2026-10-01 08:00:00')
    FROM Nums;

    ;WITH Nums AS (
        SELECT TOP (100000) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS n
        FROM sys.all_objects a CROSS JOIN sys.all_objects b
    )
    INSERT INTO source_oltp.orders (order_id, customer_id, order_date, status, total_amount, updated_at)
    SELECT 
        n, (n % 10000) + 1,
        DATEADD(DAY, (n % 25), '2026-10-01'),
        CHOOSE((n % 4) + 1, 'COMPLETED', 'COMPLETED', 'PENDING', 'CANCELLED'),
        CAST(((n % 50) + 1) * 150000 AS DECIMAL(12,2)),
        DATEADD(MINUTE, (n % 1440), CAST(DATEADD(DAY, (n % 25), '2026-10-01') AS DATETIME2))
    FROM Nums;
    """)
    print("-> Hoàn tất sinh 10.000 khách hàng & 100.000 đơn hàng gốc!")

def simulate_daily_changes(cursor):
    print("Đang giả lập thay đổi dữ liệu ngày mới (Update khách hàng, Update đơn hàng & Thêm đơn mới)...")
    cursor.execute("""
        SET NOCOUNT ON;
        -- 1. Khách hàng số 1 đổi hạng thẻ lên Diamond (Test SCD Type 2)
        UPDATE source_oltp.customers 
        SET membership_tier = 'Diamond', updated_at = SYSDATETIME() 
        WHERE customer_id = 1;

        -- 2. Đơn hàng số 3 chuyển từ PENDING sang COMPLETED (Test MERGE Upsert)
        UPDATE source_oltp.orders 
        SET status = 'COMPLETED', updated_at = SYSDATETIME() 
        WHERE order_id = 3;

        -- 3. Phát sinh 1 đơn hàng mới
        DECLARE @next_id INT = (SELECT ISNULL(MAX(order_id), 0) + 1 FROM source_oltp.orders);
        INSERT INTO source_oltp.orders (order_id, customer_id, order_date, status, total_amount, updated_at)
        VALUES (@next_id, 1, CAST(SYSDATETIME() AS DATE), 'COMPLETED', 3500000, SYSDATETIME());
    """)
    print("-> Hoàn tất giả lập dữ liệu thay đổi (1 khách đổi hạng thẻ, 1 đơn đổi trạng thái, 1 đơn mới)!")

if __name__ == "__main__":
    with get_connection() as conn:
        cur = conn.cursor()
        cur.execute("SELECT COUNT(*) FROM source_oltp.customers")
        if cur.fetchone()[0] == 0:
            generate_initial_data(cur)
        else:
            simulate_daily_changes(cur)