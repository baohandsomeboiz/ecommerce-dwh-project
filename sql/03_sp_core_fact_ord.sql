USE Ecommerce_DWH;
GO

CREATE OR ALTER PROCEDURE core.sp_load_fact_orders
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @rows INT = 0;
    BEGIN TRY
        BEGIN TRANSACTION;

        -- Khử trùng tại Staging bằng ROW_NUMBER trước khi MERGE vào Fact
        ;WITH dedup_orders AS (
            SELECT 
                o.order_id, d.customer_sk, o.customer_id, o.order_date, 
                o.status, o.total_amount, o.updated_at,
                ROW_NUMBER() OVER (PARTITION BY o.order_id ORDER BY o.updated_at DESC) AS rn
            FROM stg.orders o
            LEFT JOIN core.dim_customers d 
                ON o.customer_id = d.customer_id AND d.is_current = 1
        )
        MERGE INTO core.fact_orders AS target
        USING (SELECT * FROM dedup_orders WHERE rn = 1) AS source
        ON (target.order_id = source.order_id AND target.order_date = source.order_date)
        WHEN MATCHED THEN
            UPDATE SET 
                target.customer_sk = source.customer_sk,
                target.status = source.status,
                target.total_amount = source.total_amount,
                target.updated_at = source.updated_at
        WHEN NOT MATCHED THEN
            INSERT (order_id, customer_sk, customer_id, order_date, status, total_amount, updated_at)
            VALUES (source.order_id, source.customer_sk, source.customer_id, source.order_date, source.status, source.total_amount, source.updated_at);

        SET @rows = @@ROWCOUNT;
        COMMIT TRANSACTION;

        INSERT INTO audit.pipeline_logs (step_name, rows_affected, status, message)
        VALUES ('sp_load_fact_orders', @rows, 'SUCCESS', N'Merge Fact Orders thành công');
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        INSERT INTO audit.pipeline_logs (step_name, rows_affected, status, message)
        VALUES ('sp_load_fact_orders', 0, 'FAILED', ERROR_MESSAGE());
        THROW;
    END CATCH
END;
GO