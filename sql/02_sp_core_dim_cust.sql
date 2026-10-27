USE Ecommerce_DWH;
GO

CREATE OR ALTER PROCEDURE core.sp_load_dim_customers
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @rows INT = 0;
    BEGIN TRY
        BEGIN TRANSACTION;

        -- Bước 1: Đóng các dòng lịch sử cũ nếu khách đổi Thành phố hoặc Hạng thẻ
        UPDATE d
        SET d.valid_to = s.updated_at,
            d.is_current = 0
        FROM core.dim_customers d
        INNER JOIN stg.customers s ON d.customer_id = s.customer_id
        WHERE d.is_current = 1
          AND (d.city <> s.city OR d.membership_tier <> s.membership_tier);

        -- Bước 2: Chèn khách hàng mới HOẶC dòng trạng thái mới cho khách vừa đóng
        INSERT INTO core.dim_customers (customer_id, full_name, city, membership_tier, valid_from, valid_to, is_current)
        SELECT 
            s.customer_id, s.full_name, s.city, s.membership_tier,
            s.updated_at AS valid_from,
            '9999-12-31 23:59:59' AS valid_to,
            1 AS is_current
        FROM stg.customers s
        LEFT JOIN core.dim_customers d 
            ON s.customer_id = d.customer_id AND d.is_current = 1
        WHERE d.customer_id IS NULL;

        SET @rows = @@ROWCOUNT;
        COMMIT TRANSACTION;

        INSERT INTO audit.pipeline_logs (step_name, rows_affected, status, message)
        VALUES ('sp_load_dim_customers', @rows, 'SUCCESS', N'Cập nhật SCD Type 2 thành công');
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        INSERT INTO audit.pipeline_logs (step_name, rows_affected, status, message)
        VALUES ('sp_load_dim_customers', 0, 'FAILED', ERROR_MESSAGE());
        THROW;
    END CATCH
END;
GO