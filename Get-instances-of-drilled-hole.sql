-- Check how many holes are drilled as a particular hole.
-- useful for checking if a hole that does not have MWD Data exists.
SELECT 
    HoleId,
    RigSerialNumber,
    DrillBitDiameter,
    StartHoleTime,
    EndHoleTime,
    StartLogTime,
    RawStartPointX,
    RawStartPointY,
    RawStartPointZ
FROM [SurfaceManager].[dbo].[DrilledHole] dh
JOIN [SurfaceManager].[dbo].[DrillPlan] dp ON dh.DrillPlanId = dp.Id
WHERE dp.[Name] LIKE 'DRILLPATTERN%' AND dh.HoleId = '39'
ORDER BY StartHoleTime;
