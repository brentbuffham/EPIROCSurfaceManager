-- SINGLE HOLE MWD - All Samples
-- Check raw sample spacing for this hole in the MWD records
-- useful for seeing if data on any particular hole is bad.
SELECT 
    HoleId,
    Depth,
	Time,
	MwdHoleID,
	StartLogTime,
    LEAD(Depth) OVER (PARTITION BY HoleId ORDER BY Depth) - Depth AS SampleSpacing_m
FROM [SurfaceManager].[dbo].[MwdSample] mwds
JOIN [SurfaceManager].[dbo].[MwdHole] mwdh ON mwdh.Id = mwds.MwdHoleId
JOIN [SurfaceManager].[dbo].[DrillPlan] dp ON mwdh.DrillPlanId = dp.Id
WHERE dp.[Name] LIKE 'DRILLPATTERN%' AND mwdh.HoleId = 39
ORDER BY Depth;
