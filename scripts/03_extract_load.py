import pyodbc

SERVER_NAME = 'MSI'
DB_NAME = 'Ecommerce_DWH'

def get_connection():
    drivers = [d for d in pyodbc.drivers() if 'SQL Server' in d]
    driver = drivers[-1] if drivers else 'SQL Server'
    conn_str = f'DRIVER={{{driver}}};SERVER={SERVER_NAME};DATABASE={DB_NAME};Trusted_Connection=yes;TrustServerCertificate=yes;'
    return pyodbc.connect(conn_str, autocommit=True)

def extract_incremental_to_stg(cursor, table_name):
    # 1. Lấy mốc watermark cũ
    cursor.execute("SELECT last_extracted_at FROM audit.etl_watermark WHERE table_name = ?", table_name)
    last_time = cursor.fetchone()[0]

    # 2. Làm sạch bảng Staging và chỉ nạp dữ liệu mới hơn mốc watermark
    cursor.execute(f"TRUNCATE TABLE stg.{table_name};")
    cursor.execute(f"""
        INSERT INTO stg.{table_name}
        SELECT * FROM source_oltp.{table_name}
        WHERE updated_at > ?
    """, last_time)
    
    cursor.execute(f"SELECT COUNT(*) FROM stg.{table_name};")
    rows = cursor.fetchone()[0]
    print(f"[EXTRACT] Bảng stg.{table_name}: Nạp thành công {rows} dòng mới (updated_at > {last_time}).")

    # 3. Cập nhật mốc watermark mới
    if rows > 0:
        cursor.execute(f"""
            UPDATE audit.etl_watermark 
            SET last_extracted_at = (SELECT MAX(updated_at) FROM stg.{table_name})
            WHERE table_name = ?
        """, table_name)

def run_pipeline():
    with get_connection() as conn:
        cur = conn.cursor()
        print("\n=== BẮT ĐẦU CHẠY DATA PIPELINE ===")
        
        # Bước 1: Incremental Extract từ Source -> Staging
        extract_incremental_to_stg(cur, 'customers')
        extract_incremental_to_stg(cur, 'orders')

        # Bước 2: Transform & Load vào tầng Core (SCD2 & Merge)
        print("[TRANSFORM] Đang chạy core.sp_load_dim_customers (SCD Type 2)...")
        cur.execute("EXEC core.sp_load_dim_customers;")
        
        print("[TRANSFORM] Đang chạy core.sp_load_fact_orders (MERGE Upsert)...")
        cur.execute("EXEC core.sp_load_fact_orders;")

        # Bước 3: Kiểm tra đối soát dữ liệu (Reconciliation)
        print("[QUALITY CHECK] Đang đối soát tổng đơn & doanh thu Nguồn vs Đích...")
        cur.execute("EXEC audit.sp_reconcile_data;")

        # Bước 4: Tổng hợp báo cáo tầng Data Mart
        print("[DATA MART] Đang làm mới báo cáo mart.sp_refresh_daily_revenue...")
        cur.execute("EXEC mart.sp_refresh_daily_revenue;")
        
        print("=== HOÀN TẤT PIPELINE THÀNH CÔNG 100%! ===\n")

if __name__ == "__main__":
    run_pipeline()