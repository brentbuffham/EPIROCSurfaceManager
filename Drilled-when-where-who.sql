-- MSSQL
-- Return the Drilled Holes from the Database along with who drilled them on which machine and when.
-- SurfaceManager Rev16 
-- 2025
SELECT 
       dp.[Name] AS 'Drill Pattern'
      ,[HoleId]
      ,[RigSerialNumber]
	  ,rg.[Name] AS 'Drill Name'
      ,[DrillBitDiameter] As 'Diameter'
      ,[StartHoleTime]
      ,[EndHoleTime]
	  ,SQRT(POWER([RawEndPointY] - [RawStartPointY], 2) + POWER([RawEndPointX] - [RawStartPointX], 2) + POWER([RawEndPointZ] - [RawStartPointZ], 2)) AS LengthDrilled
      ,([AveragePenetrationRateInMetersPerMinute]* 60) AS 'Av Inst Pen m/hr'
--      ,[SequenceNumber]
--      ,[NumberOfStops]
--      ,[Status]
--      ,[StartLogTime]
      ,[OperatorName]
--      ,[GpsQuality]
--      ,[TowerAngle]
      ,[DrillBitId] AS 'D=Drill R=Redrill'
--      ,[DrilledInRock]
--      ,[HoleName]
      ,[RawStartPointY] AS 'Collar X'
	  ,[RawStartPointX] AS 'Collar Y'
      ,[RawStartPointZ] AS 'Collar Z'
      ,[RawEndPointX] AS 'Collar X'
      ,[RawEndPointY] AS 'Collar Y'
      ,[RawEndPointZ] AS 'Collar Z'
      ,[IsEdited]
      ,dh.[Comment]
--      ,[StartHoleTime_Timezone]
--      ,[EndHoleTime_Timezone]
FROM [SurfaceManager].[dbo].[DrilledHole] dh
LEFT JOIN [SurfaceManager].[dbo].[DrillPlan] dp ON dh.DrillPlanId = dp.Id 
LEFT JOIN [SurfaceManager].[dbo].[Rig] rg ON dh.RigSerialNumber = rg.SerialNumber
WHERE dp.[Name] LIKE '1200%'
ORDER BY rg.[Name], dh.OperatorName, StartHoleTime DESC
