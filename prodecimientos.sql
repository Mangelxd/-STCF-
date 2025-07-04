ALTER PROCEDURE [dbo].[M_Filtrar_POR_DOCNum]
    @DocNum INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT 
        ofdata.ItemCode AS PartNumber,
        ofdata.ItemName AS Descripcion,
        ofdata.CantidadPendiente,
        stock.BinCode AS Ubicacion,
        ofdata.Project
    FROM (
        SELECT 
            T0.ItemCode,
            T0.ItemName,
            SUM(T2.PlannedQty) AS CantidadPendiente,
            MAX(T3.Project) AS Project
        FROM SBO_M_ES_10.dbo.OITM T0  
        LEFT JOIN SBO_M_ES_10.dbo.WOR1 T2 ON T0.ItemCode = T2.ItemCode
        LEFT JOIN SBO_M_ES_10.dbo.OWOR T3 ON T2.DocEntry = T3.DocEntry
        WHERE T3.Status != 'C' AND T3.DocNum = @DocNum
        GROUP BY 
            T0.ItemCode,
            T0.ItemName
    ) AS ofdata
    LEFT JOIN (
        SELECT
            T0.ItemCode,
            T2.BinCode
        FROM SBO_M_ES_10.dbo.OITM T0
        LEFT JOIN SBO_M_ES_10.dbo.OITW T3 ON T0.ItemCode = T3.ItemCode AND T3.OnHand > 0
        LEFT JOIN SBO_M_ES_10.dbo.OIBQ T1 ON T0.ItemCode = T1.ItemCode AND T3.WhsCode = T1.WhsCode
        LEFT JOIN SBO_M_ES_10.dbo.OBIN T2 ON T1.BinAbs = T2.AbsEntry
        WHERE T3.OnHand > 0 AND ISNULL(T1.OnHandQty, T3.OnHand) > 0
    ) AS stock ON ofdata.ItemCode = stock.ItemCode
END
ALTER PROCEDURE [dbo].[Actualizar_M_BK_ResgistroTrazabilidad]
    @DocNum INT
AS
BEGIN
    SET NOCOUNT ON;

    IF OBJECT_ID('tempdb..#TempResultados') IS NOT NULL DROP TABLE #TempResultados;

    CREATE TABLE #TempResultados (
        PartNumber NVARCHAR(50),
        Descripcion NVARCHAR(200),
        CantidadPendiente INT,
        Ubicacion NVARCHAR(100),
        Project NVARCHAR(50),
        DocNum INT
    );

    INSERT INTO #TempResultados (PartNumber, Descripcion, CantidadPendiente, Ubicacion, Project)
    EXEC dbo.M_Filtrar_POR_DOCNum @DocNum;

    UPDATE #TempResultados SET DocNum = @DocNum;

    INSERT INTO dbo.M_BK_ResgistroTrazabilidad (
        PartNumber,
        Descripcion,
        CantidadPendiente,
        CantidadNecesaria,
        Ubicacion,
        UltimaActualizacion,
        Lote,
        Observacion,
        DocNum,
        Project
    )
    SELECT t1.PartNumber, t1.Descripcion, t1.CantidadPendiente, t1.CantidadPendiente, t1.Ubicacion,
           GETDATE(), NULL, NULL, t1.DocNum, t1.Project
    FROM #TempResultados t1
    INNER JOIN (
        SELECT PartNumber, DocNum, MIN(ISNULL(Ubicacion, 'ZZZ')) AS UbicacionMin
        FROM #TempResultados
        GROUP BY PartNumber, DocNum
    ) t2
        ON t1.PartNumber = t2.PartNumber 
        AND t1.DocNum = t2.DocNum 
        AND ISNULL(t1.Ubicacion, 'ZZZ') = t2.UbicacionMin
    LEFT JOIN dbo.M_BK_ResgistroTrazabilidad t3
        ON t3.PartNumber = t1.PartNumber AND t3.DocNum = t1.DocNum AND ISNULL(t3.Ubicacion, '') = ISNULL(t1.Ubicacion, '')
    WHERE t3.PartNumber IS NULL;

    WITH Numerados AS (
        SELECT 
            Id,
            DocNum,
            ROW_NUMBER() OVER (PARTITION BY DocNum ORDER BY Id) AS rn
        FROM dbo.M_BK_ResgistroTrazabilidad
        WHERE DocNum = @DocNum
    )
    UPDATE d
    SET DocNumSecuencial = CAST(d.DocNum AS VARCHAR) + ';' + CAST(n.rn AS VARCHAR)
    FROM dbo.M_BK_ResgistroTrazabilidad d
    JOIN Numerados n ON d.Id = n.Id;
END
