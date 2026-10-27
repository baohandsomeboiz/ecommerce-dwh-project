USE Ecommerce_DWH;
GO

CREATE OR ALTER PROCEDURE mart.sp_refresh_daily_revenue
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @rows INT = 0;
    BEGIN TRY
        BEGIN TRANSACTION;

        -- Chỉ tính lại doanh thu của những ngày có đơn hàng mới/thay đổi trong batch
        DELETE FROM mart.daily_revenue
        WHERE report_date IN (SELECT DISTINCT order_date FROM stg.orders);

        INSERT INTO mart.daily_revenue (report_date, city, membership_tier, total_orders, net_revenue)
        SELECT 
            f.order_date AS report_date,
            ISNULL(d.city, N'Unknown') AS city,
            ISNULL(d.membership_tier, 'Unknown') AS membership_tier,
            COUNT(f.order_id) AS total_orders,
            SUM(f.total_amount) AS net_revenue
        FROM core.fact_orders f
        LEFT JOIN core.dim_customers d ON f.customer_sk = d.customer_sk
        WHERE f.status = 'COMPLETED'
          AND f.order_date IN (SELECT DISTINCT order_date FROM stg.orders)
        GROUP BY f.order_date, d.city, d.membership_tier;

        SET @rows = @@ROWCOUNT;
        COMMIT TRANSACTION;

        INSERT INTO audit.pipeline_logs (step_name, rows_affected, status, message)
        VALUES ('sp_refresh_daily_revenue', @rows, 'SUCCESS', N'Cập nhật bảng Mart thành công');
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        INSERT INTO audit.pipeline_logs (step_name, rows_affected, status, message)
        VALUES ('sp_refresh_daily_revenue', 0, 'FAILED', ERROR_MESSAGE());
        THROW;
    END CATCH
END;
GO