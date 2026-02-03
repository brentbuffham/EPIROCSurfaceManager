-- =============================================================================
-- MWD Two-Stage Aggregation (Raw → 200mm → 1m) with Effective Cycle Time
-- =============================================================================
-- NOTES:
-- 1. Raw MWD data is typically at ~30-100mm resolution
-- 2. First aggregation: to 200mm intervals (0.2m bins)
-- 3. Second aggregation: to 1m intervals
-- 4. Cycle Time: Time from hole start to next hole start within same Pattern/Rig
-- =============================================================================
-- SCHEMA REFERENCE (Surface Manager 2.19):
-- MwdHole: StartLogTime, EndLogTime (hole-level timestamps)
-- MwdSample: Time (sample-level timestamp), Depth, PenetrationRate, etc.
-- =============================================================================

WITH RawMWD AS (
  SELECT 
      dp.[Name] AS DrillPlan,
      dh.HoleId,
      rig.[Name] AS Rig,
      mwdh.RigSerialNumber,  -- Carry through for HoleAttemptId
      
      -- Raw depth in metres
      mwds.Depth AS RawDepth_m,
      
      -- 200mm (0.2m) bin assignment: FLOOR(Depth / 0.2) * 0.2
      FLOOR(mwds.Depth / 0.2) * 0.2 AS DepthBin_200mm,
      
      -- 1m bin assignment (for grouping)
      FLOOR(mwds.Depth) AS DepthBin_1m,
      
      -- Actual depth for averaging
      mwds.Depth AS ActualDepth_m,

      -- Bit diameter - no default, use actual value
      dh.DrillBitDiameter AS BitDiameter_mm,

      -- Raw MWD measurements
      mwds.PercussionPressure,
      mwds.FeederPressure,
      mwds.PenetrationRate,

      -- Converted penetration rates
      (mwds.PenetrationRate * 1000.0 / 60.0) AS PenRate_mm_per_s,
      (mwds.PenetrationRate / 60.0) AS PenRate_m_per_s,

      -- Heuristic calculations at raw level
      CASE 
        WHEN mwds.PenetrationRate = 0 THEN NULL
        ELSE mwds.PercussionPressure / (mwds.PenetrationRate * 1000.0 / 60.0)
      END AS Hardness1_Ns_per_mm,

      CASE 
        WHEN mwds.PenetrationRate = 0 THEN NULL
        ELSE (ISNULL(mwds.PercussionPressure, 0) + ISNULL(mwds.FeederPressure, 0)) / (mwds.PenetrationRate * 1000.0 / 60.0)
      END AS Hardness2_Ns_per_mm,

      CASE 
        WHEN mwds.PenetrationRate = 0 THEN NULL
        ELSE mwds.PercussionPressure / (mwds.PenetrationRate / 60.0)
      END AS SpecificEn_J_per_m3,

      CASE 
        WHEN mwds.PenetrationRate = 0 THEN NULL
        ELSE (mwds.PercussionPressure / (mwds.PenetrationRate / 60.0)) * 0.5
      END AS ProxyUCS,

      CASE 
        WHEN mwds.PenetrationRate = 0 THEN NULL
        ELSE LOG(NULLIF((ISNULL(mwds.PercussionPressure, 0) + ISNULL(mwds.FeederPressure, 0)) / (mwds.PenetrationRate * 1000.0 / 60.0), 0))
      END AS LogHardness2,

      -- Coordinate data for interpolation
      dh.RawStartPointX, dh.RawStartPointY, dh.RawStartPointZ,
      dh.RawEndPointX, dh.RawEndPointY, dh.RawEndPointZ,
      SQRT(
        POWER(dh.RawEndPointY - dh.RawStartPointY, 2) + 
        POWER(dh.RawEndPointX - dh.RawStartPointX, 2) + 
        POWER(dh.RawEndPointZ - dh.RawStartPointZ, 2)
      ) AS L,
      
      -- =========================================================================
      -- TIMESTAMP FOR CYCLE TIME (from Surface Manager schema)
      -- MwdHole: StartLogTime, EndLogTime
      -- MwdSample: Time (sample timestamp)
      -- =========================================================================
      mwdh.StartLogTime AS HoleStartTime,
      mwdh.EndLogTime AS HoleEndTime

  FROM [SurfaceManager].[dbo].[MwdHole] mwdh
  LEFT JOIN [SurfaceManager].[dbo].[Rig] rig ON rig.[SerialNumber] = mwdh.[RigSerialNumber]
  LEFT JOIN [SurfaceManager].[dbo].[DrillPlan] dp ON mwdh.DrillPlanId = dp.Id
  LEFT JOIN [SurfaceManager].[dbo].[MwdSample] mwds ON mwdh.Id = mwds.MwdHoleId
  INNER JOIN [SurfaceManager].[dbo].[DrilledHole] dh 
      ON dh.DrillPlanId = mwdh.DrillPlanId 
      AND dh.HoleId = mwdh.HoleId
      AND dh.RigSerialNumber = mwdh.RigSerialNumber
      AND CONVERT(VARCHAR(19), mwdh.StartLogTime, 120) = CONVERT(VARCHAR(19), dh.StartHoleTime, 120)
  -- BLAST NAME FILTER - ADJUST AS NEEDED
  WHERE dp.[Name] LIKE '1160-3231%'-- OR dp.[NAME] LIKE '1220-1712' 
),

-- =============================================================================
-- STAGE 1: Aggregate to 200mm intervals
-- =============================================================================
MWD_200mm AS (
  SELECT
    Rig,
    RigSerialNumber,
    DrillPlan,
    HoleId,
    DepthBin_200mm,
    DepthBin_1m,
    BitDiameter_mm,
    HoleStartTime,
    HoleEndTime,

    -- Coordinate interpolation at actual average depth (more accurate)
    AVG(
      CASE 
        WHEN L = 0 THEN RawStartPointY
        ELSE RawStartPointY + (ActualDepth_m / L) * (RawEndPointY - RawStartPointY)
      END
    ) AS mwdX_200mm,

    AVG(
      CASE 
        WHEN L = 0 THEN RawStartPointX
        ELSE RawStartPointX + (ActualDepth_m / L) * (RawEndPointX - RawStartPointX)
      END
    ) AS mwdY_200mm,

    AVG(
      CASE 
        WHEN L = 0 THEN RawStartPointZ
        ELSE RawStartPointZ + (ActualDepth_m / L) * (RawEndPointZ - RawStartPointZ)
      END
    ) AS mwdZ_200mm,

    -- Aggregated measurements at 200mm
    COUNT(*) AS SampleCount_200mm,
    AVG(ActualDepth_m) AS Avg_Depth_200mm,
    MIN(ActualDepth_m) AS Min_Depth_200mm,
    MAX(ActualDepth_m) AS Max_Depth_200mm,
    AVG(PercussionPressure) AS Avg_PercussionPressure_200mm,
    AVG(FeederPressure) AS Avg_FeederPressure_200mm,
    AVG(PenetrationRate) AS Avg_PenetrationRate_m_per_min_200mm,

    -- Hardness indices at 200mm
    AVG(Hardness1_Ns_per_mm) AS Hardness1_200mm,
    MAX(Hardness1_Ns_per_mm) AS Max_Hardness1_200mm,
    STDEV(Hardness1_Ns_per_mm) AS StdDev_Hardness1_200mm,
    EXP(AVG(LOG(NULLIF(Hardness1_Ns_per_mm, 0)))) AS Smoothed_Hardness1_200mm,
    
    AVG(Hardness2_Ns_per_mm) AS Hardness2_200mm,
    MAX(Hardness2_Ns_per_mm) AS Max_Hardness2_200mm,
    STDEV(Hardness2_Ns_per_mm) AS StdDev_Hardness2_200mm,
    AVG(LogHardness2) AS Avg_LogHardness2_200mm,
    EXP(AVG(LogHardness2)) AS Smoothed_Hardness2_200mm,

    -- Specific energy at 200mm
    AVG(SpecificEn_J_per_m3) AS SpecificEnergy_200mm,
    MAX(SpecificEn_J_per_m3) AS Max_SpecificEnergy_200mm,
    STDEV(SpecificEn_J_per_m3) AS StdDev_SpecificEnergy_200mm,
    EXP(AVG(LOG(NULLIF(SpecificEn_J_per_m3, 0)))) AS Smoothed_SpecificEnergy_200mm,

    -- ProxyUCS at 200mm
    AVG(ProxyUCS) AS ProxyUCS_200mm,
    MAX(ProxyUCS) AS Max_ProxyUCS_200mm,
    STDEV(ProxyUCS) AS StdDev_ProxyUCS_200mm,
    EXP(AVG(LOG(NULLIF(ProxyUCS, 0)))) AS Smoothed_ProxyUCS_200mm

  FROM RawMWD
  GROUP BY DrillPlan, HoleId, Rig, RigSerialNumber, DepthBin_200mm, DepthBin_1m, BitDiameter_mm, HoleStartTime, HoleEndTime
),

-- =============================================================================
-- STAGE 2: Aggregate 200mm intervals to 1m intervals
-- =============================================================================
MWD_1m AS (
  SELECT
    Rig,
    RigSerialNumber,
    DrillPlan,
    HoleId,
    DepthBin_1m AS DepthInterval_m,
    BitDiameter_mm,
    HoleStartTime,
    HoleEndTime,

    -- Coordinates (averaged from 200mm level, based on actual sample depths)
    AVG(mwdX_200mm) AS mwdX,
    AVG(mwdY_200mm) AS mwdY,
    AVG(mwdZ_200mm) AS mwdZ,

    -- Count of 200mm bins (should be up to 5 per 1m)
    COUNT(*) AS Bins_200mm_Count,
    SUM(SampleCount_200mm) AS TotalSampleCount,
    
    -- Actual depth statistics (more realistic than bin number)
    AVG(Avg_Depth_200mm) AS Avg_Depth_m,
    MIN(Min_Depth_200mm) AS From_Depth_m,
    MAX(Max_Depth_200mm) AS To_Depth_m,

    -- Aggregated measurements at 1m (from 200mm averages)
    AVG(Avg_PercussionPressure_200mm) AS Avg_PercussionPressure,
    AVG(Avg_FeederPressure_200mm) AS Avg_FeederPressure,
    AVG(Avg_PenetrationRate_m_per_min_200mm) AS Avg_PenetrationRate_m_per_min,
    ROUND(AVG(Avg_PenetrationRate_m_per_min_200mm) * 60, 2) AS Avg_PenetrationRate_m_per_hr,

    -- Hardness1 at 1m level
    AVG(Hardness1_200mm) AS Hardness1_Index_Ns_per_mm,
    MAX(Max_Hardness1_200mm) AS Max_Hardness1_Index_Ns_per_mm,
    -- Pooled standard deviation approximation
    SQRT(AVG(POWER(StdDev_Hardness1_200mm, 2))) AS StdDev_Hardness1_Index,
    EXP(AVG(LOG(NULLIF(Smoothed_Hardness1_200mm, 0)))) AS Smoothed_Hardness1_Index_Ns_per_mm,

    -- Hardness2 at 1m level
    AVG(Hardness2_200mm) AS Hardness2_Index_Ns_per_mm,
    MAX(Max_Hardness2_200mm) AS Max_Hardness2_Index_Ns_per_mm,
    SQRT(AVG(POWER(StdDev_Hardness2_200mm, 2))) AS StdDev_Hardness2_Index,
    EXP(AVG(Avg_LogHardness2_200mm)) AS Smoothed_Hardness2_Index_Ns_per_mm,

    -- Specific Energy at 1m level
    AVG(SpecificEnergy_200mm) AS Specific_Energy_J_per_m3,
    MAX(Max_SpecificEnergy_200mm) AS Max_Specific_Energy_J_per_m3,
    SQRT(AVG(POWER(StdDev_SpecificEnergy_200mm, 2))) AS StdDev_Specific_Energy_J,
    EXP(AVG(LOG(NULLIF(Smoothed_SpecificEnergy_200mm, 0)))) AS Smoothed_Specific_Energy_J_per_m3,

    -- ProxyUCS at 1m level
    AVG(ProxyUCS_200mm) AS ProxyUCS_MPa,
    MAX(Max_ProxyUCS_200mm) AS Max_ProxyUCS_MPa,
    SQRT(AVG(POWER(StdDev_ProxyUCS_200mm, 2))) AS StdDev_ProxyUCS_MPa,
    EXP(AVG(LOG(NULLIF(Smoothed_ProxyUCS_200mm, 0)))) AS Smoothed_ProxyUCS_MPa

  FROM MWD_200mm
  GROUP BY DrillPlan, HoleId, Rig, RigSerialNumber, DepthBin_1m, BitDiameter_mm, HoleStartTime, HoleEndTime
),

-- =============================================================================
-- HOLE-LEVEL SUMMARY for Cycle Time Calculation
-- Get one row per hole with its start time
-- =============================================================================
HoleDistinct AS (
  -- First get distinct holes (fix for ROW_NUMBER + DISTINCT issue)
  SELECT DISTINCT
    DrillPlan,
    Rig,
    RigSerialNumber,
    HoleId,
    BitDiameter_mm,
    HoleStartTime,
    HoleEndTime,
    MAX(DepthInterval_m) + 1 AS HoleDepth_m  -- Approximate total depth (max bin + 1)
  FROM MWD_1m
  GROUP BY DrillPlan, Rig, RigSerialNumber, HoleId, BitDiameter_mm, HoleStartTime, HoleEndTime
),

HoleSummary AS (
  SELECT
    DrillPlan,
    Rig,
    RigSerialNumber,
    HoleId,
    BitDiameter_mm,
    HoleStartTime,
    HoleEndTime,
    HoleDepth_m,
    -- Sequence per Rig within Pattern (1, 2, 3... per drill)
    ROW_NUMBER() OVER (
      PARTITION BY DrillPlan, Rig 
      ORDER BY HoleStartTime ASC
    ) AS RigHoleSequence,
    -- Combined Sequence: DrillID numeric (4 digits) + sequence (5 digits)
    -- DR0094 hole 1 = 0094 * 100000 + 1 = 9400001
    -- DR0077 hole 3 = 0077 * 100000 + 3 = 7700003
    CAST(
      CAST(SUBSTRING(Rig, 3, 4) AS INT) * 100000 
      + ROW_NUMBER() OVER (PARTITION BY DrillPlan, Rig ORDER BY HoleStartTime ASC)
    AS BIGINT) AS CombinedSequence
  FROM HoleDistinct
),

-- =============================================================================
-- CYCLE TIME CALCULATION
-- Time from start of current hole to start of next hole (within same Pattern/Rig)
-- =============================================================================
HoleCycleTime AS (
  SELECT
    hs.DrillPlan,
    hs.Rig,
    hs.RigSerialNumber,
    hs.HoleId,
    hs.BitDiameter_mm,
    hs.HoleStartTime,
    hs.HoleEndTime,
    hs.HoleDepth_m,
    hs.RigHoleSequence,
    hs.CombinedSequence,
    
    -- Drilling duration for this hole (EndLogTime - StartLogTime)
    DATEDIFF(SECOND, hs.HoleStartTime, hs.HoleEndTime) / 60.0 AS DrillingTime_Minutes,
    DATEDIFF(SECOND, hs.HoleStartTime, hs.HoleEndTime) AS DrillingTime_Seconds,
    
    -- Get the next hole's start time within the same Pattern and Rig
    LEAD(hs.HoleStartTime) OVER (
      PARTITION BY hs.DrillPlan, hs.Rig 
      ORDER BY hs.HoleStartTime ASC
    ) AS NextHoleStartTime,
    
    -- Calculate cycle time in minutes (current hole start to next hole start)
    DATEDIFF(SECOND, 
      hs.HoleStartTime, 
      LEAD(hs.HoleStartTime) OVER (
        PARTITION BY hs.DrillPlan, hs.Rig 
        ORDER BY hs.HoleStartTime ASC
      )
    ) / 60.0 AS CycleTime_Minutes,
    
    -- Calculate cycle time in seconds
    DATEDIFF(SECOND, 
      hs.HoleStartTime, 
      LEAD(hs.HoleStartTime) OVER (
        PARTITION BY hs.DrillPlan, hs.Rig 
        ORDER BY hs.HoleStartTime ASC
      )
    ) AS CycleTime_Seconds,
    
    -- Non-drilling time (tramming, positioning, etc.) = Cycle Time - Drilling Time
    DATEDIFF(SECOND, 
      hs.HoleStartTime, 
      LEAD(hs.HoleStartTime) OVER (
        PARTITION BY hs.DrillPlan, hs.Rig 
        ORDER BY hs.HoleStartTime ASC
      )
    ) / 60.0 
    - DATEDIFF(SECOND, hs.HoleStartTime, hs.HoleEndTime) / 60.0 AS NonDrillingTime_Minutes,
    
    -- =======================================================================
    -- ROP METRICS (Rate of Penetration / Productivity)
    -- =======================================================================
    -- Drilling ROP: meters drilled / drilling time (pure drilling efficiency)
    CASE 
      WHEN DATEDIFF(SECOND, hs.HoleStartTime, hs.HoleEndTime) > 0 
      THEN hs.HoleDepth_m / (DATEDIFF(SECOND, hs.HoleStartTime, hs.HoleEndTime) / 3600.0)
      ELSE NULL 
    END AS DrillingROP_m_per_hr,
    
    -- Cycle ROP: meters drilled / cycle time (overall productivity including tramming)
    CASE 
      WHEN DATEDIFF(SECOND, 
             hs.HoleStartTime, 
             LEAD(hs.HoleStartTime) OVER (
               PARTITION BY hs.DrillPlan, hs.Rig 
               ORDER BY hs.HoleStartTime ASC
             )
           ) > 0 
      THEN hs.HoleDepth_m / (
             DATEDIFF(SECOND, 
               hs.HoleStartTime, 
               LEAD(hs.HoleStartTime) OVER (
                 PARTITION BY hs.DrillPlan, hs.Rig 
                 ORDER BY hs.HoleStartTime ASC
               )
             ) / 3600.0
           )
      ELSE NULL 
    END AS CycleROP_m_per_hr

  FROM HoleSummary hs
),

-- =============================================================================
-- GET FIRST (MIN) DEPTH COORDINATES FOR UNIQUE HOLE ATTEMPT IDENTIFIER
-- =============================================================================
FirstDepthCoords AS (
  SELECT
    Rig,
    RigSerialNumber,
    DrillPlan,
    HoleId,
    BitDiameter_mm,
    mwdX AS FirstDepth_mwdX,
    mwdY AS FirstDepth_mwdY,
    mwdZ AS FirstDepth_mwdZ
  FROM (
    SELECT
      Rig,
      RigSerialNumber,
      DrillPlan,
      HoleId,
      BitDiameter_mm,
      DepthInterval_m,
      mwdX,
      mwdY,
      mwdZ,
      ROW_NUMBER() OVER (
        PARTITION BY DrillPlan, Rig, HoleId, BitDiameter_mm 
        ORDER BY DepthInterval_m ASC
      ) AS rn
    FROM MWD_1m
  ) ranked
  WHERE rn = 1
)

-- =============================================================================
-- FINAL OUTPUT: 1m Aggregated MWD Data with Cycle Time
-- =============================================================================
SELECT
    -- =========================================================================
    -- UNIQUE HOLE ATTEMPT IDENTIFIER (first column)
    -- Format: Rig-RigSerial-DrillPlan-HoleId-Diameter-X-Y-Z (first depth coords * 1000)
    -- =========================================================================
    CONCAT(
        m.Rig, '-',
        m.RigSerialNumber, '-',
        m.DrillPlan, '-',
        RIGHT('00000' + CAST(m.HoleId AS VARCHAR(5)), 5), '-',
        RIGHT('0000' + CAST(m.BitDiameter_mm AS VARCHAR(4)), 4), '-',
        CAST(CAST(fd.FirstDepth_mwdX * 1000 AS BIGINT) AS VARCHAR(20)), '-',
        CAST(CAST(fd.FirstDepth_mwdY * 1000 AS BIGINT) AS VARCHAR(20)), '-',
        CAST(CAST(fd.FirstDepth_mwdZ * 1000 AS BIGINT) AS VARCHAR(20))
    ) AS HoleAttemptId,
    
    m.Rig,
    m.RigSerialNumber,
    m.DrillPlan,
    m.HoleId,
    m.DepthInterval_m,
    m.BitDiameter_mm,
    
    -- Actual depth statistics (more accurate for spatial representation)
    m.Avg_Depth_m,
    m.From_Depth_m,
    m.To_Depth_m,
    
    m.mwdX,
    m.mwdY,
    m.mwdZ,
    
    -- Sample counts for QC
    m.Bins_200mm_Count,
    m.TotalSampleCount,
    
    -- Core MWD measurements
    m.Avg_PercussionPressure,
    m.Avg_FeederPressure,
    m.Avg_PenetrationRate_m_per_min,
    m.Avg_PenetrationRate_m_per_hr,
    
    -- Hardness indices
    m.Hardness1_Index_Ns_per_mm,
    m.Max_Hardness1_Index_Ns_per_mm,
    m.StdDev_Hardness1_Index,
    m.Smoothed_Hardness1_Index_Ns_per_mm,
    m.Hardness2_Index_Ns_per_mm,
    m.Max_Hardness2_Index_Ns_per_mm,
    m.StdDev_Hardness2_Index,
    m.Smoothed_Hardness2_Index_Ns_per_mm,
    
    -- Specific Energy
    m.Specific_Energy_J_per_m3,
    m.Max_Specific_Energy_J_per_m3,
    m.StdDev_Specific_Energy_J,
    m.Smoothed_Specific_Energy_J_per_m3,
    
    -- ProxyUCS
    m.ProxyUCS_MPa,
    m.Max_ProxyUCS_MPa,
    m.StdDev_ProxyUCS_MPa,
    m.Smoothed_ProxyUCS_MPa,
    
    -- =========================================================================
    -- CYCLE TIME METRICS (at hole level, repeated for each depth interval)
    -- =========================================================================
    ct.RigHoleSequence,
    ct.CombinedSequence,
    ct.HoleDepth_m,
    ct.HoleStartTime,
    ct.HoleEndTime,
    ct.DrillingTime_Minutes,
    ct.DrillingTime_Seconds,
    ct.NextHoleStartTime,
    ct.CycleTime_Minutes,
    ct.CycleTime_Seconds,
    ct.NonDrillingTime_Minutes,
    
    -- ROP Metrics
    ct.DrillingROP_m_per_hr,   -- Meters/hour during actual drilling
    ct.CycleROP_m_per_hr       -- Meters/hour including tramming (productivity)

FROM MWD_1m m
LEFT JOIN HoleCycleTime ct 
    ON m.DrillPlan = ct.DrillPlan 
    AND m.Rig = ct.Rig 
    AND m.HoleId = ct.HoleId
    AND m.BitDiameter_mm = ct.BitDiameter_mm
LEFT JOIN FirstDepthCoords fd
    ON m.DrillPlan = fd.DrillPlan 
    AND m.Rig = fd.Rig 
    AND m.HoleId = fd.HoleId
    AND m.BitDiameter_mm = fd.BitDiameter_mm

ORDER BY m.DrillPlan, m.Rig, ct.RigHoleSequence, m.DepthInterval_m;


-- =============================================================================
-- OPTIONAL: Hole-Level Summary with Cycle Time Only
-- =============================================================================
-- Uncomment below if you want a separate summary at hole level only
/*
SELECT
    CONCAT(
        ct.Rig, '-',
        ct.RigSerialNumber, '-',
        ct.DrillPlan, '-',
        RIGHT('00000' + CAST(ct.HoleId AS VARCHAR(5)), 5), '-',
        RIGHT('0000' + CAST(ct.BitDiameter_mm AS VARCHAR(4)), 4), '-',
        CAST(CAST(fd.FirstDepth_mwdX * 1000 AS BIGINT) AS VARCHAR(20)), '-',
        CAST(CAST(fd.FirstDepth_mwdY * 1000 AS BIGINT) AS VARCHAR(20)), '-',
        CAST(CAST(fd.FirstDepth_mwdZ * 1000 AS BIGINT) AS VARCHAR(20))
    ) AS HoleAttemptId,
    ct.DrillPlan,
    ct.Rig,
    ct.RigSerialNumber,
    ct.HoleId,
    ct.BitDiameter_mm,
    ct.RigHoleSequence,
    ct.CombinedSequence,
    ct.HoleDepth_m,
    ct.HoleStartTime,
    ct.HoleEndTime,
    ct.NextHoleStartTime,
    ct.DrillingTime_Minutes,
    ct.CycleTime_Minutes,
    ct.NonDrillingTime_Minutes,
    ct.DrillingROP_m_per_hr,
    ct.CycleROP_m_per_hr,
    -- Pattern-Rig level stats
    AVG(ct.CycleTime_Minutes) OVER (PARTITION BY ct.DrillPlan, ct.Rig) AS Avg_CycleTime_Minutes_ByRig,
    AVG(ct.DrillingROP_m_per_hr) OVER (PARTITION BY ct.DrillPlan, ct.Rig) AS Avg_DrillingROP_ByRig,
    AVG(ct.CycleROP_m_per_hr) OVER (PARTITION BY ct.DrillPlan, ct.Rig) AS Avg_CycleROP_ByRig
FROM HoleCycleTime ct
LEFT JOIN FirstDepthCoords fd
    ON ct.DrillPlan = fd.DrillPlan 
    AND ct.Rig = fd.Rig 
    AND ct.HoleId = fd.HoleId
    AND ct.BitDiameter_mm = fd.BitDiameter_mm
WHERE ct.CycleTime_Minutes IS NOT NULL  -- Exclude last hole in sequence
ORDER BY ct.DrillPlan, ct.Rig, ct.RigHoleSequence;
*/
