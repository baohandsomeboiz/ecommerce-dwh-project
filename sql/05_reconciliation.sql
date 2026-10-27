USE Ecommerce_DWH;
GO

CREATE OR ALTER PROCEDURE audit.sp_reconcile_data
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @src_cnt INT, @dwh_cnt INT;
    DECLARE @src_sum DECIMAL(18,2), @dwh_sum DECIMAL(18,2);

    SELECT @src_cnt = COUNT(*), @src_sum = ISNULL(SUM(total_amount), 0) FROM source_oltp.orders;
    SELECT @dwh_cnt = COUNT(*), @dwh_sum = ISNULL(SUM(total_amount), 0) FROM core.fact_orders;

    IF (@src_cnt = @dwh_cnt) AND (@src_sum = @dwh_sum)
    BEGIN
        INSERT INTO audit.pipeline_logs (step_name, rows_affected, status, message)
        VALUES ('sp_reconcile_data', @dwh_cnt, 'PASSED', CONCAT(N'Khớp 100% (Tổng đơn: ', @dwh_cnt, N', Tổng tiền: ', @dwh_sum, ')'));
    END
    ELSE
    BEGIN
        DECLARE @err NVARCHAR(400) = CONCAT(N'LỆCH SỐ LIỆU! Nguồn: ', @src_cnt, N' đơn (', @src_sum, N') vs DWH: ', @dwh_cnt, N' đơn (', @dwh_sum, ')');
        INSERT INTO audit.pipeline_logs (step_name, rows_affected, status, message)
        VALUES ('sp_reconcile_data', 0, 'FAILED', @err);
        RAISERROR(@err, 16, 1);
    END
END;
GO