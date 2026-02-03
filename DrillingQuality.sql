-- MSSQL for the Drilling Quality
-- Date: 20-8-2025
-- Author: Brent Buffham - brent.buffham@actiondb.com.au
-- Description: Blast hole actual drill locations and pen rates SurfaceManager
-- Shows all planned holes with NULL drilling data when undrilled, duplicates when drilled multiple times

SELECT
    d.Name AS DrillPlan_Name,
    ph.HoleName AS Planned_HoleName,
    dh.HoleName AS Drilled_HoleName,
    
    -- Composite unique identifier: DrillPlan.Id + HoleName
    CONCAT(CAST(d.Id AS VARCHAR(50)), '-', ph.HoleName) AS Planned_Hole_UniqueID,
    CASE 
        WHEN dh.HoleName IS NOT NULL 
        THEN CONCAT(CAST(d.Id AS VARCHAR(50)), '-', dh.HoleName)
        ELSE NULL 
    END AS Drilled_Hole_UniqueID,
    
    -- Hole drilling attempt sequence (1st, 2nd, 3rd drilling of same hole)
    ROW_NUMBER() OVER (PARTITION BY d.Id, ph.HoleName ORDER BY dh.EndHoleTime ASC) AS Hole_Attempt_Number,
    
    dh.DrillBitDiameter,
    dh.DrillBitChange,
    dh.GpsQuality,
    dh.Comment,
    
    -- Designed coordinates (note: X/Y swapped for coordinate system transformation)
    ph.RawStartPointY AS Designed_Collar_X,
    ph.RawStartPointX AS Designed_Collar_Y,
    ph.RawStartPointZ AS Designed_Collar_Z,
    ph.RawEndPointY   AS Designed_Toe_X,
    ph.RawEndPointX   AS Designed_Toe_Y,
    ph.RawEndPointZ   AS Designed_Toe_Z,
    
    -- Actual coordinates (note: X/Y swapped for coordinate system transformation)
    dh.RawStartPointY AS Actual_Collar_X,
    dh.RawStartPointX AS Actual_Collar_Y,
    dh.RawStartPointZ AS Actual_Collar_Z,
    dh.RawEndPointY   AS Actual_Toe_X,
    dh.RawEndPointX   AS Actual_Toe_Y,
    dh.RawEndPointZ   AS Actual_Toe_Z,
    
    -- Calculated metrics (NULL when not drilled)
    -- Actual drilled hole length in meters using 3D distance formula
    CASE 
        WHEN dh.HoleName IS NOT NULL 
        THEN ROUND(SQRT(
            POWER(dh.RawEndPointX - dh.RawStartPointX, 2) + 
            POWER(dh.RawEndPointY - dh.RawStartPointY, 2) + 
            POWER(dh.RawStartPointZ - dh.RawEndPointZ, 2)
        ), 3) 
        ELSE NULL 
    END AS Calculated_Drilled_Length,
    
    dh.OperatorName,
    r.Name AS Rig_Name,
    dh.StartHoleTime,
    dh.EndHoleTime,
    
    -- Total drilling time converted from seconds to hours
    CASE 
        WHEN dh.HoleName IS NOT NULL 
        THEN ROUND(CAST(DATEDIFF(SECOND, dh.StartHoleTime, dh.EndHoleTime) AS FLOAT) / 3600, 3) 
        ELSE NULL 
    END AS Calculated_Drilled_Hours,
    
    -- Hole status
    CASE 
        WHEN dh.HoleName IS NULL THEN 'Undrilled'
        WHEN dh.Status = 0 THEN 'Unspecified'
        WHEN dh.Status = 1 THEN 'Undrilled'
        WHEN dh.Status = 2 THEN 'Success_Drilled'
        WHEN dh.Status = 3 THEN 'Fail'
        WHEN dh.Status = 4 THEN 'Others'
        WHEN dh.Status = 5 THEN 'Aborted'
        WHEN dh.Status = 6 THEN 'Redrilled'
        ELSE 'Unknown'
    END AS Calculated_Hole_Status,
    
    -- Date validation - Check for 1984 timestamp issues
    CASE
        WHEN dh.HoleName IS NULL THEN 'Not_Drilled'
        WHEN dh.StartHoleTime = CONVERT(DATETIME, '1984-01-01 00:00:00.000') 
        THEN 'Invalid_1984_Date' 
        ELSE 'Valid_Date' 
    END AS Timestamp_1984_Check,
    
    -- Penetration rate: meters per hour (excludes setup/delay time, only active drilling)
    CASE 
        WHEN dh.HoleName IS NOT NULL
             AND dh.StartHoleTime != CONVERT(DATETIME, '1984-01-01 00:00:00.000') 
             AND DATEDIFF(SECOND, dh.StartHoleTime, dh.EndHoleTime) > 0
             AND dh.EndHoleTime > dh.StartHoleTime
        THEN ROUND(
            SQRT(
                POWER(dh.RawEndPointX - dh.RawStartPointX, 2) + 
                POWER(dh.RawEndPointY - dh.RawStartPointY, 2) + 
                POWER(dh.RawStartPointZ - dh.RawEndPointZ, 2)
            ) / (CAST(DATEDIFF(SECOND, dh.StartHoleTime, dh.EndHoleTime) AS FLOAT) / 3600), 
            3
        )
        ELSE NULL
    END AS Calculated_Meters_Per_Hour_Excl_Delays,
    
    -- DEVIATION METRICS: Measure accuracy of drilling vs planned design
    -- Collar deviation calculations (NULL when not drilled)
    -- Horizontal distance between planned and actual collar positions (critical for blast pattern)
    CASE 
        WHEN dh.HoleName IS NOT NULL 
        THEN ROUND(SQRT(
            POWER(dh.RawStartPointX - ph.RawStartPointX, 2) + 
            POWER(dh.RawStartPointY - ph.RawStartPointY, 2)
        ), 3) 
        ELSE NULL 
    END AS Collar_Deviation_XY_Meters,
    
    -- Vertical distance between planned and actual collar elevations (affects bench control)
    CASE 
        WHEN dh.HoleName IS NOT NULL 
        THEN ROUND(ABS(dh.RawStartPointZ - ph.RawStartPointZ), 3) 
        ELSE NULL 
    END AS Collar_Deviation_Z_Meters,
    
    -- Total 3D distance between planned and actual collar positions
    CASE 
        WHEN dh.HoleName IS NOT NULL 
        THEN ROUND(SQRT(
            POWER(dh.RawStartPointX - ph.RawStartPointX, 2) + 
            POWER(dh.RawStartPointY - ph.RawStartPointY, 2) + 
            POWER(dh.RawStartPointZ - ph.RawStartPointZ, 2)
        ), 3) 
        ELSE NULL 
    END AS Collar_Deviation_3D_Meters,
    
    -- Toe deviation calculations (NULL when not drilled)
    -- Horizontal distance between planned and actual toe positions (affects burden/spacing at depth)
    CASE 
        WHEN dh.HoleName IS NOT NULL 
        THEN ROUND(SQRT(
            POWER(dh.RawEndPointX - ph.RawEndPointX, 2) + 
            POWER(dh.RawEndPointY - ph.RawEndPointY, 2)
        ), 3) 
        ELSE NULL 
    END AS Toe_Deviation_XY_Meters,
    
    -- Vertical distance between planned and actual toe elevations (affects grade control)
    CASE 
        WHEN dh.HoleName IS NOT NULL 
        THEN ROUND(ABS(dh.RawEndPointZ - ph.RawEndPointZ), 3) 
        ELSE NULL 
    END AS Toe_Deviation_Z_Meters,
    
    -- Total 3D distance between planned and actual toe positions
    CASE 
        WHEN dh.HoleName IS NOT NULL 
        THEN ROUND(SQRT(
            POWER(dh.RawEndPointX - ph.RawEndPointX, 2) + 
            POWER(dh.RawEndPointY - ph.RawEndPointY, 2) + 
            POWER(dh.RawEndPointZ - ph.RawEndPointZ, 2)
        ), 3) 
        ELSE NULL 
    END AS Toe_Deviation_3D_Meters,
    
    -- GPS Quality assessment (1=Bad, 2=Marginal, 3=Good per Surface Manager documentation)
    CASE 
        WHEN dh.HoleName IS NULL THEN 'Not_Drilled'
        WHEN dh.GpsQuality = 3 THEN 'Good'
        WHEN dh.GpsQuality = 2 THEN 'Marginal' 
        WHEN dh.GpsQuality = 1 THEN 'Bad'
        ELSE 'Unknown'
    END AS GPS_Quality_Status,
    
    -- Simplified Hole Quality Rating (1-10 scale: 1=High Confidence, 10=Low Confidence)
    -- Bad GPS = automatic 10, otherwise based on 3D collar and toe deviations
    CASE 
        WHEN dh.HoleName IS NULL THEN NULL
        WHEN dh.GpsQuality = 1 THEN 10  -- Bad GPS = automatic 10
        ELSE 
            CASE 
                -- Collar ≤300mm AND Toe ≤300mm = 1
                WHEN SQRT(POWER(dh.RawStartPointX - ph.RawStartPointX, 2) + 
                          POWER(dh.RawStartPointY - ph.RawStartPointY, 2) + 
                          POWER(dh.RawStartPointZ - ph.RawStartPointZ, 2)) <= 0.3 
                     AND SQRT(POWER(dh.RawEndPointX - ph.RawEndPointX, 2) + 
                               POWER(dh.RawEndPointY - ph.RawEndPointY, 2) + 
                               POWER(dh.RawEndPointZ - ph.RawEndPointZ, 2)) <= 0.3 THEN 1
                
                -- Collar ≤300mm AND Toe ≤400mm = 2
                WHEN SQRT(POWER(dh.RawStartPointX - ph.RawStartPointX, 2) + 
                          POWER(dh.RawStartPointY - ph.RawStartPointY, 2) + 
                          POWER(dh.RawStartPointZ - ph.RawStartPointZ, 2)) <= 0.3 
                     AND SQRT(POWER(dh.RawEndPointX - ph.RawEndPointX, 2) + 
                               POWER(dh.RawEndPointY - ph.RawEndPointY, 2) + 
                               POWER(dh.RawEndPointZ - ph.RawEndPointZ, 2)) <= 0.4 THEN 2
                
                -- Collar ≤300mm AND Toe ≤500mm = 3
                WHEN SQRT(POWER(dh.RawStartPointX - ph.RawStartPointX, 2) + 
                          POWER(dh.RawStartPointY - ph.RawStartPointY, 2) + 
                          POWER(dh.RawStartPointZ - ph.RawStartPointZ, 2)) <= 0.3 
                     AND SQRT(POWER(dh.RawEndPointX - ph.RawEndPointX, 2) + 
                               POWER(dh.RawEndPointY - ph.RawEndPointY, 2) + 
                               POWER(dh.RawEndPointZ - ph.RawEndPointZ, 2)) <= 0.5 THEN 3
                
                -- Collar ≤400mm AND Toe ≤600mm = 4
                WHEN SQRT(POWER(dh.RawStartPointX - ph.RawStartPointX, 2) + 
                          POWER(dh.RawStartPointY - ph.RawStartPointY, 2) + 
                          POWER(dh.RawStartPointZ - ph.RawStartPointZ, 2)) <= 0.4 
                     AND SQRT(POWER(dh.RawEndPointX - ph.RawEndPointX, 2) + 
                               POWER(dh.RawEndPointY - ph.RawEndPointY, 2) + 
                               POWER(dh.RawEndPointZ - ph.RawEndPointZ, 2)) <= 0.6 THEN 4
                
                -- Collar ≤500mm AND Toe ≤500mm = 5
                WHEN SQRT(POWER(dh.RawStartPointX - ph.RawStartPointX, 2) + 
                          POWER(dh.RawStartPointY - ph.RawStartPointY, 2) + 
                          POWER(dh.RawStartPointZ - ph.RawStartPointZ, 2)) <= 0.5 
                     AND SQRT(POWER(dh.RawEndPointX - ph.RawEndPointX, 2) + 
                               POWER(dh.RawEndPointY - ph.RawEndPointY, 2) + 
                               POWER(dh.RawEndPointZ - ph.RawEndPointZ, 2)) <= 0.5 THEN 5
                
                -- Collar ≤600mm AND Toe ≤600mm = 6
                WHEN SQRT(POWER(dh.RawStartPointX - ph.RawStartPointX, 2) + 
                          POWER(dh.RawStartPointY - ph.RawStartPointY, 2) + 
                          POWER(dh.RawStartPointZ - ph.RawStartPointZ, 2)) <= 0.6 
                     AND SQRT(POWER(dh.RawEndPointX - ph.RawEndPointX, 2) + 
                               POWER(dh.RawEndPointY - ph.RawEndPointY, 2) + 
                               POWER(dh.RawEndPointZ - ph.RawEndPointZ, 2)) <= 0.6 THEN 6
                
                -- Collar ≤700mm AND Toe ≤700mm = 7
                WHEN SQRT(POWER(dh.RawStartPointX - ph.RawStartPointX, 2) + 
                          POWER(dh.RawStartPointY - ph.RawStartPointY, 2) + 
                          POWER(dh.RawStartPointZ - ph.RawStartPointZ, 2)) <= 0.7 
                     AND SQRT(POWER(dh.RawEndPointX - ph.RawEndPointX, 2) + 
                               POWER(dh.RawEndPointY - ph.RawEndPointY, 2) + 
                               POWER(dh.RawEndPointZ - ph.RawEndPointZ, 2)) <= 0.7 THEN 7
                
                -- Collar ≤800mm AND Toe ≤800mm = 8
                WHEN SQRT(POWER(dh.RawStartPointX - ph.RawStartPointX, 2) + 
                          POWER(dh.RawStartPointY - ph.RawStartPointY, 2) + 
                          POWER(dh.RawStartPointZ - ph.RawStartPointZ, 2)) <= 0.8 
                     AND SQRT(POWER(dh.RawEndPointX - ph.RawEndPointX, 2) + 
                               POWER(dh.RawEndPointY - ph.RawEndPointY, 2) + 
                               POWER(dh.RawEndPointZ - ph.RawEndPointZ, 2)) <= 0.8 THEN 8
                
                -- Collar ≤900mm AND Toe ≤900mm = 9
                WHEN SQRT(POWER(dh.RawStartPointX - ph.RawStartPointX, 2) + 
                          POWER(dh.RawStartPointY - ph.RawStartPointY, 2) + 
                          POWER(dh.RawStartPointZ - ph.RawStartPointZ, 2)) <= 0.9 
                     AND SQRT(POWER(dh.RawEndPointX - ph.RawEndPointX, 2) + 
                               POWER(dh.RawEndPointY - ph.RawEndPointY, 2) + 
                               POWER(dh.RawEndPointZ - ph.RawEndPointZ, 2)) <= 0.9 THEN 9
                
                -- Everything else = 10
                ELSE 10
            END
    END AS Hole_Quality_Rating

FROM SurfaceManager.dbo.PlannedHole ph
    INNER JOIN SurfaceManager.dbo.DrillPlan d ON ph.DrillPlanId = d.Id 
    LEFT JOIN SurfaceManager.dbo.DrilledHole dh ON dh.DrillPlanId = d.Id AND dh.HoleName = ph.HoleName  -- Composite key JOIN
    LEFT JOIN SurfaceManager.dbo.Rig r ON dh.RigSerialNumber = r.SerialNumber

WHERE 
    d.Name LIKE '1290-1833%' --or d.Name LIKE '1240-1774%' or d.Name LIKE '1240-1783%' or d.Name LIKE '1240-1710%'
    --additional filters if needed
    -- AND (dh.Status IN (2, 6) OR dh.Status IS NULL) -- Include successful, redrilled, and undrilled holes
    -- AND (dh.EndHoleTime > '2025-10-18') --OR dh.StartHoleTime IS NULL) -- Recent or undrilled holes
	 --AND (CAST(dh.HoleName AS INT) BETWEEN 99 AND 150) -- Filter holes between 0 and 51
	 --AND r.Name LIKE 'DR0036'

ORDER BY
    d.Name DESC, 
    ph.HoleName,
    dh.EndHoleTime DESC;
