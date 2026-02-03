# EPIROC Surface Manager SQL Repository

A curated collection of SQL queries and scripts for the **Epiroc Surface Manager Database**, designed to save time and effort by providing ready-to-use database connections and pre-constructed SQL queries for common mining operations analysis.

<img width="339" height="342" alt="image" src="https://github.com/user-attachments/assets/1bf1c2bd-c1f8-4a33-9b43-c196a82fa8e5" />

## About

This repository provides SQL scripts for querying the Epiroc Surface Manager Database (Version 2.19 Rev. 16), enabling mining professionals to quickly extract and analyze drilling operations data without having to write complex queries from scratch.

Surface Manager is Epiroc's fleet management system for surface drilling operations, capturing detailed drilling performance, MWD (Measurement While Drilling) data, hole positioning, operator metrics, and rig status information.

### 📚 Documentation (PDFs)

The repository includes official Epiroc documentation for reference:
- **`Surface Manager 2.19 Rev. 16 Release Notes.pdf`** - Latest version release information
- **`Surface Manager database.pdf`** - Database schema and structure documentation
- **`SurfaceManager.en.pdf`** - Surface Manager user guide
- **`SurfaceManagerServer.en.pdf`** - Surface Manager Server administration guide

## Key Features

### Database Schema Coverage
Queries leverage the following Surface Manager tables:
- `DrilledHole` - Actual drilled hole data
- `PlannedHole` - Designed hole specifications
- `DrillPlan` - Drill pattern/blast design information
- `Rig` - Drilling rig details
- `MwdHole` - MWD hole-level metadata
- `MwdSample` - Raw MWD sample data

### Common Use Cases
- ✅ **Production Reporting** - Track meters drilled, drilling times, and rig utilization
- ✅ **Quality Control** - Measure drilling accuracy vs design (collar/toe deviations)
- ✅ **Operator Performance** - Analyze operator efficiency and penetration rates
- ✅ **Data Validation** - Identify GPS quality issues, timestamp anomalies, and duplicate holes
- ✅ **Geotechnical Analysis** - Extract MWD data for rock hardness and strength profiling
- ✅ **Cycle Time Analysis** - Calculate effective drilling cycle times

### Data Quality Features
All queries include considerations for:
- GPS quality assessment (1=Bad, 2=Marginal, 3=Good)
- 1984 timestamp detection (common data logging error)
- Null value handling
- Coordinate system transformations (X/Y axis swapping)
- Multiple drilling attempt tracking

## Getting Started

### Prerequisites
- Access to an Epiroc Surface Manager database (MS SQL Server)
- SQL Server Management Studio (SSMS) or compatible SQL client
- Appropriate database permissions (SELECT on SurfaceManager schema)

### Usage
1. Clone this repository or download individual SQL files
2. Open the SQL script in your SQL client
3. Modify the filter parameters in the WHERE clauses:
   - **Drill Pattern names** (e.g., `WHERE d.Name LIKE '1200%'`)
   - **Date ranges** (e.g., `@StartDate` and `@EndDate` parameters)
   - **Hole IDs, Rig names, or other identifiers** as needed
4. Execute the query against your Surface Manager database
5. Export results to CSV/Excel for further analysis or reporting

### Example Modification
```sql
-- Original filter in DrillingQuality.sql
WHERE d.Name LIKE 'DP11-134-333%'

-- Change to your drill pattern:
WHERE d.Name LIKE 'YourPattern%'
```

## Important Notes

### Coordinate System
The queries include X/Y axis swapping for coordinate system transformations:
- `RawStartPointY` → `Collar_X`
- `RawStartPointX` → `Collar_Y`

Adjust these mappings if your coordinate system differs.

### Timestamp Issues
Surface Manager databases sometimes contain erroneous 1984-01-01 timestamps. Queries include detection logic:
```sql
WHEN dh.StartHoleTime = CONVERT(DATETIME, '1984-01-01 00:00:00.000') 
THEN 'Invalid_1984_Date'
```

## Links to File Specifications
[EPIROC File Format - Part 1](https://buymeacoffee.com/brentbuffham/epiroc-surface-manager-file-format-specification)

[EPIROC File Format - Part 2](https://buymeacoffee.com/brentbuffham/iredes)

## Standards Reference

File specifications are based on the IREDES (International Rock Excavation Data Exchange Standard) maintained by the IREDES Initiative. 
The official XML schema (DrillRig.xsd) defines the DRPPlan format used for drill plan exchange.

### Schema Version: V 1.3

**Namespace:** [http://www.iredes.org/xml/DrillRig](http://www.iredes.org/xml/DrillRig)

**IR Namespace:** [http://www.iredes.org/xml](http://www.iredes.org/xml)

**Official Documentation:** [iredes.org/irdocs](iredes.org/irdocs)


## Contributing

Contributions welcome! If you've developed additional useful queries for Surface Manager databases, please:
1. Fork this repository
2. Add your SQL script with clear comments
3. Update the README with query description
4. Submit a pull request

## Author

**Brent Buffham**  

## License

This repository is provided as-is for use with Epiroc Surface Manager databases. Please ensure you have appropriate permissions to access and query your organization's Surface Manager database.

## Version Compatibility

Scripts are developed and tested against:
- **Epiroc Surface Manager 2.19 Rev. 16**
- **Microsoft SQL Server**

Database schema may vary between Surface Manager versions. Refer to the included PDF documentation for your specific version.

---

*Saving people time and effort by leveraging database connections and using already constructed SQL queries.*
