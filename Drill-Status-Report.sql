-- Report to see all drills and there Status, meters drilled, etc.

--------------------SQL REPORT CODE -------------------------------------------------

DECLARE @StartDate DATETIME = '2025-10-20 06:00';
DECLARE @EndDate DATETIME = '2025-10-21 06:00';
 
-- 1. CTE: Count 1984 StartHoleTimes (if EndHoleTime is within date range)
WITH Count1984 AS (
    SELECT 
        RigSerialNumber,
        DATEPART(wk, EndHoleTime) AS WeekNumber,
        COUNT(*) AS Count1984StartTimes
    FROM [SurfaceManager].[dbo].[DrilledHole]
    WHERE 
        YEAR(StartHoleTime) = 1984
        AND EndHoleTime BETWEEN @StartDate AND @EndDate
    GROUP BY RigSerialNumber, DATEPART(wk, EndHoleTime)
),
 
-- 2. CTE: Top Operator per Rig + Week (excluding NULLs)
TopOperators AS (
    SELECT
        RigSerialNumber,
        DATEPART(wk, EndHoleTime) AS WeekNumber,
        OperatorName,
        ROW_NUMBER() OVER (
            PARTITION BY RigSerialNumber, DATEPART(wk, EndHoleTime)
            ORDER BY COUNT(*) DESC
        ) AS rn
    FROM [SurfaceManager].[dbo].[DrilledHole]
    WHERE 
        EndHoleTime BETWEEN @StartDate AND @EndDate
        AND OperatorName IS NOT NULL
    GROUP BY RigSerialNumber, DATEPART(wk, EndHoleTime), OperatorName
),
 
-- 3. CTE: Aggregate all needed metrics per Rig + Week
MainAgg AS (
    SELECT
        dh.RigSerialNumber,
        DATEPART(wk, dh.EndHoleTime) AS WeekNumber,
        r.[Name] AS RigName,
 
        COUNT(CASE WHEN dh.DrillBitDiameter < 1 THEN 1 END) AS CountDiameterLT1,
        COUNT(CASE WHEN dh.OperatorName IS NULL THEN 1 END) AS CountNullOperator,
        COUNT(CASE WHEN dh.GpsQuality < 3 THEN 1 END) AS CountGpsQualityLT3,
 
        SUM(SQRT(
            POWER(dh.EndPointX - dh.StartPointX, 2) +
            POWER(dh.EndPointY - dh.StartPointY, 2) +
            POWER(dh.EndPointZ - dh.StartPointZ, 2)
        )) AS TotalDrillMeters
 
    FROM [SurfaceManager].[dbo].[DrilledHole] dh
    JOIN [SurfaceManager].[dbo].[Rig] r 
        ON dh.RigSerialNumber = r.SerialNumber
    WHERE dh.EndHoleTime BETWEEN @StartDate AND @EndDate
    GROUP BY dh.RigSerialNumber, DATEPART(wk, dh.EndHoleTime), r.[Name]
)
 
-- 4. Final SELECT joins metrics + top operator + 1984 timestamp count
SELECT
    @StartDate AS [Date Search Start],
    @EndDate AS [Date Search End],
    ma.WeekNumber AS [Calendar Week Number],
    ma.RigName AS [Rig Name],
    ISNULL(topOp.OperatorName, 'N/A') AS [Most Common Operator],
 
    ma.CountDiameterLT1 AS [Count of diameter < 1],
    ma.CountNullOperator AS [Count of Null Operator],
    ma.CountGpsQualityLT3 AS [Count of GPS Quality < 3],
    ma.TotalDrillMeters AS [Total Drill Meters],
 
    ISNULL(c1984.Count1984StartTimes, 0) AS [Count of 1984 Timestamps],

	ma.RigSerialNumber AS [SN#]
 
FROM MainAgg ma
LEFT JOIN TopOperators topOp
    ON ma.RigSerialNumber = topOp.RigSerialNumber
    AND ma.WeekNumber = topOp.WeekNumber
    AND topOp.rn = 1
 
LEFT JOIN Count1984 c1984
    ON ma.RigSerialNumber = c1984.RigSerialNumber
    AND ma.WeekNumber = c1984.WeekNumber
 
ORDER BY ma.WeekNumber, ma.RigName;
 
