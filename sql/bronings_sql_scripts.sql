-- Bronings University Hospital Group - SQL Server (T-SQL) scripts
-- Part 1: load and clean (vw_*_Clean views)  |  Part 2: 12 investigation queries

/* =====================================================================
   Bronings University Hospital Group — Phase 4 SQL Investigation
   Script : 00_load_and_clean.sql
   Author : Lucky Ukeni, Advanced Healthcare Data Analyst
   Purpose: 1) Create BroningsDB and the five source tables
            2) Load the five CSV exports (only if rebuilding locally — Daniel has already loaded them)
            3) Create cleaned views that apply every Phase 3 DQ fix,
               so all 12 investigation queries run on validated data
   Notes  : - All raw columns load as NVARCHAR so nothing is lost on import
              (e.g. NHS Numbers keep their leading zero — DQ issue OP-05/IP-13).
            - Dates are converted with style 103 (dd/mm/yyyy, UK).
            - Change the file paths in section 2 to the folder holding the CSV files.
   ===================================================================== */

/* Daniel Walsh has already loaded the five tables into:
     Server   : BRONINGS-SQL01\SQLEXPRESS   (Windows Authentication)
     Database : BroningsAnalytics
   >>> If you are working on Daniel's server, SKIP sections 1 and 2 and run from section 3.
   >>> Sections 1–2 are only for rebuilding the database locally from the CSV files. */
IF DB_ID('BroningsAnalytics') IS NULL CREATE DATABASE BroningsAnalytics;
GO
USE BroningsAnalytics;
GO

/* ---------------------------------------------------------------------
   1. RAW TABLES — one column per CSV field, all text
   --------------------------------------------------------------------- */
DROP TABLE IF EXISTS dbo.OutpatientAppointments, dbo.InpatientAdmissions,
                     dbo.EDAttendances, dbo.TheatreUtilisation, dbo.WorkforceStaffing;

CREATE TABLE dbo.OutpatientAppointments (
    Appointment_ID NVARCHAR(20), NHS_Number NVARCHAR(20), Patient_Surname NVARCHAR(50),
    Patient_DOB NVARCHAR(20), Specialty_Code NVARCHAR(10), Consultant_Code NVARCHAR(10),
    Clinic_Code NVARCHAR(10), Appointment_Date NVARCHAR(20), Appointment_Time NVARCHAR(10),
    Attendance_Status NVARCHAR(20), Waiting_Days NVARCHAR(10), RTT_Status NVARCHAR(10),
    RTT_Weeks NVARCHAR(10), Referral_Source NVARCHAR(10), Postcode NVARCHAR(10));

CREATE TABLE dbo.InpatientAdmissions (
    Episode_ID NVARCHAR(20), NHS_Number NVARCHAR(20), Patient_Surname NVARCHAR(50),
    Patient_DOB NVARCHAR(20), Admission_Date NVARCHAR(30), Admission_Type NVARCHAR(20),
    Ward_Code NVARCHAR(10), Specialty_Code NVARCHAR(10), Discharge_Date NVARCHAR(30),
    Discharge_Method NVARCHAR(20), Length_of_Stay NVARCHAR(10), Readmission_Flag NVARCHAR(5),
    HRG_Code NVARCHAR(10), Bed_Days NVARCHAR(10), Consultant_Code NVARCHAR(10),
    ICD10_Code NVARCHAR(10), OPCS4_Code NVARCHAR(10));

CREATE TABLE dbo.EDAttendances (
    Attendance_ID NVARCHAR(20), NHS_Number NVARCHAR(20), Patient_Surname NVARCHAR(50),
    Patient_DOB NVARCHAR(20), Arrival_Date NVARCHAR(20), Arrival_Time NVARCHAR(10),
    Triage_Category NVARCHAR(5), Seen_by_Clinician_Time NVARCHAR(10), Departure_Time NVARCHAR(10),
    Departure_Code NVARCHAR(10), Four_Hour_Breach NVARCHAR(5), Total_ED_Time_Minutes NVARCHAR(10),
    Chief_Complaint NVARCHAR(100), Specialty_Referred NVARCHAR(10));

CREATE TABLE dbo.TheatreUtilisation (
    Week_Ending NVARCHAR(20), Theatre_ID NVARCHAR(20), Sessions_Available NVARCHAR(5),
    Sessions_Used NVARCHAR(5), Utilisation_Pct NVARCHAR(10), Cases_Planned NVARCHAR(5),
    Cases_Completed NVARCHAR(5), Cancellations_Trust NVARCHAR(5), Cancellations_Patient NVARCHAR(5),
    Overrun_Minutes NVARCHAR(10), Specialty_Code NVARCHAR(10));

CREATE TABLE dbo.WorkforceStaffing (
    Shift_ID NVARCHAR(20), Staff_ID NVARCHAR(20), Staff_Grade NVARCHAR(10), Ward_Code NVARCHAR(10),
    Shift_Date NVARCHAR(20), Shift_Type NVARCHAR(10), Hours_Rostered NVARCHAR(10),
    Hours_Worked NVARCHAR(10), Agency_Flag NVARCHAR(5), Absence_Flag NVARCHAR(5),
    Overtime_Hours NVARCHAR(10), Specialty_Code NVARCHAR(10));
GO

/* ---------------------------------------------------------------------
   2. LOAD THE CSVs  (SQL Server 2017+; FORMAT='CSV' handles quoted fields)
      Alternative: SSMS > right-click database > Tasks > Import Flat File
   --------------------------------------------------------------------- */
BULK INSERT dbo.OutpatientAppointments FROM 'C:\Bronings\Data\03_outpatient_appointments.csv'
    WITH (FORMAT = 'CSV', FIRSTROW = 2, CODEPAGE = '65001', TABLOCK);
BULK INSERT dbo.InpatientAdmissions    FROM 'C:\Bronings\Data\04_inpatient_admissions.csv'
    WITH (FORMAT = 'CSV', FIRSTROW = 2, CODEPAGE = '65001', TABLOCK);
BULK INSERT dbo.EDAttendances          FROM 'C:\Bronings\Data\05_ed_attendances.csv'
    WITH (FORMAT = 'CSV', FIRSTROW = 2, CODEPAGE = '65001', TABLOCK);
BULK INSERT dbo.TheatreUtilisation     FROM 'C:\Bronings\Data\06_theatre_utilisation.csv'
    WITH (FORMAT = 'CSV', FIRSTROW = 2, CODEPAGE = '65001', TABLOCK);
BULK INSERT dbo.WorkforceStaffing      FROM 'C:\Bronings\Data\07_workforce_staffing.csv'
    WITH (FORMAT = 'CSV', FIRSTROW = 2, CODEPAGE = '65001', TABLOCK);
GO

-- Row-count check: expect 580 / 1206 / 969 / 208 / 1560
SELECT 'OutpatientAppointments' AS TableName, COUNT(*) AS Row_Count FROM dbo.OutpatientAppointments
UNION ALL SELECT 'InpatientAdmissions', COUNT(*) FROM dbo.InpatientAdmissions
UNION ALL SELECT 'EDAttendances',       COUNT(*) FROM dbo.EDAttendances
UNION ALL SELECT 'TheatreUtilisation',  COUNT(*) FROM dbo.TheatreUtilisation
UNION ALL SELECT 'WorkforceStaffing',   COUNT(*) FROM dbo.WorkforceStaffing;
GO

/* ---------------------------------------------------------------------
   3. CLEANED VIEWS — apply the Phase 3 DQ Issue Log fixes
      Blank strings become NULL via NULLIF(TRIM(x),'') BEFORE any conversion:
      in SQL Server CONVERT('' AS date) = 1900-01-01 and CONVERT('' AS int) = 0.
   --------------------------------------------------------------------- */

-- 3a. Outpatients: GEN->GM (OP-06), 'attended'->ATT and 'N/A' excluded (OP-01),
--     text Waiting_Days recovered from RTT_Weeks x 7 (OP-02), negative waits nulled (OP-03),
--     blank RTT_Status treated as OPEN (Task 10). 'N/A' status set to NULL, row kept.
CREATE OR ALTER VIEW dbo.vw_Outpatient_Clean AS
SELECT
    Appointment_ID,
    NULLIF(TRIM(NHS_Number), '')                                      AS NHS_Number,
    Patient_Surname,
    TRY_CONVERT(date, Patient_DOB, 103)                               AS Patient_DOB,
    CASE WHEN Specialty_Code = 'GEN' THEN 'GM' ELSE Specialty_Code END AS Specialty_Code,
    NULLIF(TRIM(Consultant_Code), '')                                 AS Consultant_Code,
    Clinic_Code,
    CASE WHEN Clinic_Code IN ('CL-OLD', 'CL-DEP') THEN 1 ELSE 0 END    AS Retired_Clinic_Flag,
    TRY_CONVERT(date, Appointment_Date, 103)                          AS Appointment_Date,
    TRY_CONVERT(time, NULLIF(TRIM(Appointment_Time), ''))             AS Appointment_Time,   -- 'TBC' -> NULL
    CASE WHEN LOWER(TRIM(Attendance_Status)) = 'attended' THEN 'ATT'
         WHEN TRIM(Attendance_Status) IN ('N/A', '') THEN NULL          -- invalid: excluded from DNA maths,
         ELSE UPPER(TRIM(Attendance_Status)) END                      AS Attendance_Status,   -- pathway kept for RTT
    CASE WHEN TRY_CONVERT(int, Waiting_Days) >= 0 THEN TRY_CONVERT(int, Waiting_Days)
         WHEN TRY_CONVERT(int, Waiting_Days) IS NULL
              THEN CAST(ROUND(TRY_CONVERT(decimal(6,1), NULLIF(TRIM(RTT_Weeks), '')) * 7, 0) AS int)
         ELSE NULL END                                                AS Waiting_Days,        -- negative -> NULL
    COALESCE(NULLIF(UPPER(TRIM(RTT_Status)), ''), 'OPEN')             AS RTT_Status,
    TRY_CONVERT(decimal(6,1), NULLIF(TRIM(RTT_Weeks), ''))            AS RTT_Weeks,
    Referral_Source,
    NULLIF(TRIM(Postcode), '')                                        AS Postcode
FROM dbo.OutpatientAppointments;
GO

-- 3b. Inpatients: duplicates removed (IP-01, keep first ward), GEN->GM, Admission_Type standardised,
--     text discharge dates converted (IP-05), LOS recalculated from dates (IP-10)
CREATE OR ALTER VIEW dbo.vw_Inpatient_Clean AS
WITH dedup AS (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY Episode_ID ORDER BY Ward_Code) AS rn
    FROM dbo.InpatientAdmissions
), typed AS (
    SELECT
        Episode_ID,
        NULLIF(TRIM(NHS_Number), '')                                       AS NHS_Number,
        Patient_Surname,
        TRY_CONVERT(date, Patient_DOB, 103)                                AS Patient_DOB,
        TRY_CONVERT(date, Admission_Date, 103)                             AS Admission_Date,
        CASE UPPER(TRIM(Admission_Type)) WHEN 'ELECTIVE' THEN 'ELEC'
                                         WHEN 'EMERGENCY' THEN 'EMER'
                                         ELSE UPPER(TRIM(Admission_Type)) END AS Admission_Type,
        Ward_Code,
        CASE WHEN Specialty_Code = 'GEN' THEN 'GM' ELSE Specialty_Code END  AS Specialty_Code,
        -- NULLIF first: CONVERT('' AS date) silently returns 1900-01-01 in SQL Server
        COALESCE(TRY_CONVERT(date, NULLIF(TRIM(Discharge_Date), ''), 103),
                 TRY_CONVERT(date, NULLIF(TRIM(Discharge_Date), ''), 107),  -- 'October 9 2024'
                 TRY_CAST(NULLIF(TRIM(Discharge_Date), '') AS date))       AS Discharge_Date,
        NULLIF(TRIM(Discharge_Method), '')                                 AS Discharge_Method,
        NULLIF(TRIM(Readmission_Flag), '')                                 AS Readmission_Flag,
        NULLIF(TRIM(HRG_Code), '')                                         AS HRG_Code,
        TRY_CONVERT(int, NULLIF(TRIM(Bed_Days), ''))                       AS Bed_Days,   -- '' would become 0
        NULLIF(TRIM(Consultant_Code), '')                                  AS Consultant_Code,
        NULLIF(TRIM(ICD10_Code), '')                                       AS ICD10_Code,
        NULLIF(TRIM(OPCS4_Code), '')                                       AS OPCS4_Code
    FROM dedup WHERE rn = 1
)
SELECT *, DATEDIFF(day, Admission_Date, Discharge_Date) AS Length_of_Stay   -- NULL for open episodes
FROM typed;
GO

-- 3c. ED: duplicates removed (ED-01), 12-hour times converted (ED-05),
--     ED minutes and 4-hour breach recalculated from times (ED-02/03/04)
CREATE OR ALTER VIEW dbo.vw_ED_Clean AS
WITH dedup AS (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY Attendance_ID ORDER BY Arrival_Time) AS rn
    FROM dbo.EDAttendances
), typed AS (
    SELECT
        Attendance_ID,
        NULLIF(TRIM(NHS_Number), '')                     AS NHS_Number,
        Patient_Surname,
        TRY_CONVERT(date, Patient_DOB, 103)              AS Patient_DOB,
        TRY_CONVERT(date, Arrival_Date, 103)             AS Arrival_Date,
        TRY_CONVERT(time, Arrival_Time)                  AS Arrival_Time,     -- handles '3:53 PM'
        TRY_CONVERT(int, Triage_Category)                AS Triage_Category,
        CASE WHEN TRY_CONVERT(int, Triage_Category) BETWEEN 1 AND 5 THEN 1 ELSE 0 END AS Valid_Triage_Flag,
        TRY_CONVERT(time, NULLIF(Seen_by_Clinician_Time, '')) AS Seen_Time,
        TRY_CONVERT(time, NULLIF(Departure_Time, ''))    AS Departure_Time,
        Departure_Code,
        UPPER(TRIM(Chief_Complaint))                     AS Chief_Complaint,
        CASE WHEN Specialty_Referred = 'N/A' THEN 'NONE'
             WHEN Specialty_Referred = 'GEN' THEN 'GM' ELSE Specialty_Referred END AS Specialty_Referred
    FROM dedup WHERE rn = 1
)
SELECT *,
       -- minutes from arrival to departure; +1440 handles crossing midnight
       CASE WHEN Departure_Time IS NULL THEN NULL
            ELSE (DATEDIFF(minute, Arrival_Time, Departure_Time) + 1440) % 1440 END AS ED_Minutes,
       CASE WHEN Departure_Time IS NULL THEN NULL
            WHEN (DATEDIFF(minute, Arrival_Time, Departure_Time) + 1440) % 1440 > 240 THEN 'Y'
            ELSE 'N' END                                                          AS Four_Hour_Breach
FROM typed;
GO

-- 3d. Theatres: 'Theatre One' -> T3 (TH-03), utilisation recalculated, sessions used capped,
--     week-ending dates corrected to Sunday (TH-05)
CREATE OR ALTER VIEW dbo.vw_Theatre_Clean AS
WITH typed AS (
    SELECT
        TRY_CONVERT(date, Week_Ending, 103)                         AS Week_Ending_Raw,
        CASE WHEN Theatre_ID = 'Theatre One' THEN 'T3' ELSE Theatre_ID END AS Theatre_ID,
        TRY_CONVERT(int, Sessions_Available)                        AS Sessions_Available,
        TRY_CONVERT(int, Sessions_Used)                             AS Sessions_Used,
        TRY_CONVERT(decimal(5,1), Utilisation_Pct)                  AS Utilisation_Pct_Reported,
        TRY_CONVERT(int, Cases_Planned)                             AS Cases_Planned,
        TRY_CONVERT(int, Cases_Completed)                           AS Cases_Completed,
        TRY_CONVERT(int, NULLIF(Cancellations_Trust, ''))           AS Cancellations_Trust,
        TRY_CONVERT(int, NULLIF(Cancellations_Patient, ''))         AS Cancellations_Patient,
        TRY_CONVERT(int, Overrun_Minutes)                           AS Overrun_Minutes,
        CASE WHEN Specialty_Code = 'GEN' THEN 'GM' ELSE Specialty_Code END AS Specialty_Code
    FROM dbo.TheatreUtilisation
)
SELECT *,
       -- move a non-Sunday week ending back to the previous Sunday (date-setting independent)
       DATEADD(day, -(DATEDIFF(day, '19000107', Week_Ending_Raw) % 7), Week_Ending_Raw) AS Week_Ending,
       CASE WHEN Sessions_Used > Sessions_Available THEN Sessions_Available ELSE Sessions_Used END AS Sessions_Used_Capped,
       CASE WHEN Sessions_Used > Sessions_Available THEN 1 ELSE 0 END AS Over_Capacity_Flag,
       CAST(100.0 * Sessions_Used / NULLIF(Sessions_Available, 0) AS decimal(5,1)) AS Utilisation_Pct_Calculated
FROM typed;
GO

-- 3e. Workforce: ST-99 test records removed (WF-02), GEN->GM, shift types and grades standardised
CREATE OR ALTER VIEW dbo.vw_Workforce_Clean AS
SELECT
    Shift_ID,
    NULLIF(TRIM(Staff_ID), '')                                   AS Staff_ID,
    Staff_Grade,                                                 -- 'Doctor' kept; cannot map without ESR
    Ward_Code,
    TRY_CONVERT(date, Shift_Date, 103)                           AS Shift_Date,
    CASE Shift_Type WHEN 'D' THEN 'DAY' WHEN 'N' THEN 'NIGHT' WHEN 'L' THEN 'LONG' ELSE Shift_Type END AS Shift_Type,
    TRY_CONVERT(decimal(4,1), NULLIF(TRIM(Hours_Rostered), ''))                    AS Hours_Rostered,
    TRY_CONVERT(decimal(4,1), NULLIF(TRIM(Hours_Worked), ''))                      AS Hours_Worked,
    NULLIF(TRIM(Agency_Flag), '')                                AS Agency_Flag,      -- NULL = unknown (WF-01)
    NULLIF(TRIM(Absence_Flag), '')                               AS Absence_Flag,
    TRY_CONVERT(decimal(4,1), NULLIF(TRIM(Overtime_Hours), ''))                    AS Overtime_Hours,
    CASE WHEN Specialty_Code = 'GEN' THEN 'GM' ELSE Specialty_Code END AS Specialty_Code
FROM dbo.WorkforceStaffing
WHERE Staff_ID NOT LIKE 'ST-99%' OR Staff_ID IS NULL OR Staff_ID = '';
GO

-- Validation: cleaned row counts. Expect 580 / 1200 / 960 / 208 / 1536
SELECT 'vw_Outpatient_Clean' AS ViewName, COUNT(*) AS Row_Count FROM dbo.vw_Outpatient_Clean
UNION ALL SELECT 'vw_Inpatient_Clean', COUNT(*) FROM dbo.vw_Inpatient_Clean
UNION ALL SELECT 'vw_ED_Clean',        COUNT(*) FROM dbo.vw_ED_Clean
UNION ALL SELECT 'vw_Theatre_Clean',   COUNT(*) FROM dbo.vw_Theatre_Clean
UNION ALL SELECT 'vw_Workforce_Clean', COUNT(*) FROM dbo.vw_Workforce_Clean;
GO


/* =====================================================================
   Bronings University Hospital Group — Phase 4 SQL Investigation
   Script : 01_investigation_queries.sql
   Author : Lucky Ukeni, Advanced Healthcare Data Analyst
   Server : BRONINGS-SQL01\SQLEXPRESS   Database: BroningsAnalytics
   Prereq : Run section 3 of 00_load_and_clean.sql first. It creates the
            vw_*_Clean views, which apply the Phase 3 DQ Issue Log fixes
            (GEN->GM, duplicates removed, status values standardised, etc.).
            Every query below reads from those views, so its figures match
            the Phase 3 Excel analysis.
   Conventions: one query per numbered block; CTE names describe their
            content; percentages rounded to 2 dp; money in £.
   ===================================================================== */
USE BroningsAnalytics;
GO

/* =====================================================================
   QUERY 1 — RTT BREACH BY SPECIALTY   (most urgent — NHS England week 1)
   Question : Which specialties have patients waiting > 18 weeks on OPEN
              pathways? Show open pathways, breaches and compliance %.
   Logic    : Incomplete (OPEN) pathways only — the NHS RTT standard.
              Breach = RTT_Weeks > 18. Target = 92%.
              Pathways with no recorded RTT_Weeks are excluded (1 row).
   ===================================================================== */
WITH open_pathways AS (
    SELECT Specialty_Code, RTT_Weeks
    FROM dbo.vw_Outpatient_Clean
    WHERE RTT_Status = 'OPEN'
      AND RTT_Weeks IS NOT NULL
)
SELECT
    Specialty_Code,
    COUNT(*)                                                      AS Open_Pathways,
    SUM(CASE WHEN RTT_Weeks > 18 THEN 1 ELSE 0 END)               AS Patients_Breaching,
    CAST(100.0 * SUM(CASE WHEN RTT_Weeks <= 18 THEN 1 ELSE 0 END)
         / COUNT(*) AS decimal(5,2))                              AS Compliance_Pct,
    CASE WHEN 100.0 * SUM(CASE WHEN RTT_Weeks <= 18 THEN 1 ELSE 0 END) / COUNT(*) >= 92 THEN 'Green'
         WHEN 100.0 * SUM(CASE WHEN RTT_Weeks <= 18 THEN 1 ELSE 0 END) / COUNT(*) >= 85 THEN 'Amber'
         ELSE 'Red' END                                           AS RAG_vs_92pct
FROM open_pathways
GROUP BY Specialty_Code
ORDER BY Compliance_Pct ASC;          -- worst first
GO

/* =====================================================================
   QUERY 2 — CONSULTANT CANCELLATION RATE (ranked within specialty)
   Question : Which consultants have the highest Trust-initiated
              cancellation rate?
   Logic    : TheatreUtilisation has no consultant field, so this uses
              outpatient appointments, where CAN = cancelled by the Trust
              (glossary). Rate = CAN / all valid appointments.
              RANK() restarts for each specialty (window function);
              a second RANK() gives the Trust-wide position.
              Blank Consultant_Code (5 rows) excluded.
   ===================================================================== */
WITH consultant_activity AS (
    SELECT
        Specialty_Code,
        Consultant_Code,
        COUNT(*)                                               AS Total_Appointments,
        SUM(CASE WHEN Attendance_Status = 'CAN' THEN 1 ELSE 0 END) AS Trust_Cancellations
    FROM dbo.vw_Outpatient_Clean
    WHERE Consultant_Code IS NOT NULL
      AND Attendance_Status IN ('ATT', 'DNA', 'CAN', 'REF')
    GROUP BY Specialty_Code, Consultant_Code
)
SELECT
    Specialty_Code,
    Consultant_Code,
    Total_Appointments,
    Trust_Cancellations,
    CAST(100.0 * Trust_Cancellations / Total_Appointments AS decimal(5,2)) AS Cancellation_Rate_Pct,
    RANK() OVER (PARTITION BY Specialty_Code
                 ORDER BY 1.0 * Trust_Cancellations / Total_Appointments DESC) AS Rank_In_Specialty,
    RANK() OVER (ORDER BY 1.0 * Trust_Cancellations / Total_Appointments DESC) AS Rank_Trust_Wide
FROM consultant_activity
ORDER BY Rank_Trust_Wide, Specialty_Code;
GO

/* =====================================================================
   QUERY 3 — CLINIC DNA RATE
   Question : Which clinics have the highest DNA rate?
   Logic    : NHS England definition — DNA / (ATT + DNA + REF);
              Trust cancellations (CAN) are not in the denominator.
              Non-standard status values are excluded ('attended' is
              already mapped to ATT in the view; 'N/A' removed).
              Retired clinics (CL-OLD, CL-DEP) are shown but flagged.
   ===================================================================== */
SELECT
    Clinic_Code,
    MAX(Retired_Clinic_Flag)                                       AS Retired_Clinic,
    COUNT(*)                                                       AS Total_Appointments,      -- incl. CAN
    SUM(CASE WHEN Attendance_Status IN ('ATT','DNA','REF') THEN 1 ELSE 0 END) AS Booked_Excl_CAN,
    SUM(CASE WHEN Attendance_Status = 'DNA' THEN 1 ELSE 0 END)     AS DNA_Count,
    CAST(100.0 * SUM(CASE WHEN Attendance_Status = 'DNA' THEN 1 ELSE 0 END)
         / NULLIF(SUM(CASE WHEN Attendance_Status IN ('ATT','DNA','REF') THEN 1 ELSE 0 END), 0)
         AS decimal(5,2))                                          AS DNA_Rate_Pct
FROM dbo.vw_Outpatient_Clean
WHERE Attendance_Status IN ('ATT', 'DNA', 'CAN', 'REF')          -- valid codes only
GROUP BY Clinic_Code
ORDER BY DNA_Rate_Pct DESC;
GO

/* =====================================================================
   QUERY 4 — WARD OCCUPANCY BY WEEK
   Question : For each ward, how many patients are in a bed on each
              week-ending date? Which wards regularly exceed 10?
   Logic    : A recursive CTE builds a calendar of Sundays covering the
              admissions period. A patient is "in a bed" on a date if
              Admission_Date <= date AND (Discharge_Date IS NULL OR
              Discharge_Date > date). Open episodes (no discharge date)
              count as occupied — see caveat in the report.
   ===================================================================== */
WITH calendar AS (
    SELECT CAST('2024-10-06' AS date) AS Census_Date          -- first Sunday in the period
    UNION ALL
    SELECT DATEADD(week, 1, Census_Date)
    FROM calendar
    WHERE Census_Date < '2025-03-23'                          -- last Sunday with admissions
), weekly_census AS (
    SELECT
        c.Census_Date,
        i.Ward_Code,
        COUNT(i.Episode_ID) AS Patients_In_Bed
    FROM calendar c
    JOIN dbo.vw_Inpatient_Clean i
      ON i.Admission_Date <= c.Census_Date
     AND (i.Discharge_Date IS NULL OR i.Discharge_Date > c.Census_Date)
    GROUP BY c.Census_Date, i.Ward_Code
)
SELECT
    Ward_Code,
    COUNT(*)                                                    AS Weeks_With_Patients,
    AVG(1.0 * Patients_In_Bed)                                  AS Avg_Concurrent_Patients,
    MAX(Patients_In_Bed)                                        AS Peak_Concurrent_Patients,
    SUM(CASE WHEN Patients_In_Bed > 10 THEN 1 ELSE 0 END)       AS Weeks_Over_10,
    CAST(100.0 * SUM(CASE WHEN Patients_In_Bed > 10 THEN 1 ELSE 0 END) / 25 AS decimal(5,1)) AS Pct_Weeks_Over_10
FROM weekly_census
GROUP BY Ward_Code
ORDER BY Weeks_Over_10 DESC, Peak_Concurrent_Patients DESC
OPTION (MAXRECURSION 100);
GO

/* =====================================================================
   QUERY 5 — DEPARTMENTAL WAITING TIMES (open RTT pathways)
   Question : Average, median and maximum waiting days by specialty.
   Logic    : Waiting_Days from the view (text values recovered from
              RTT_Weeks x 7; negative values nulled). PERCENTILE_CONT is
              a window function in SQL Server, so it is calculated in a
              CTE and collapsed with MAX() in the outer query.
   ===================================================================== */
WITH open_waits AS (
    SELECT
        Specialty_Code,
        Waiting_Days,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY Waiting_Days)
            OVER (PARTITION BY Specialty_Code) AS Median_Days
    FROM dbo.vw_Outpatient_Clean
    WHERE RTT_Status = 'OPEN'
      AND Waiting_Days IS NOT NULL
)
SELECT
    Specialty_Code,
    COUNT(*)                                   AS Open_Pathways,
    CAST(AVG(1.0 * Waiting_Days) AS decimal(6,1)) AS Avg_Waiting_Days,
    CAST(MAX(Median_Days) AS decimal(6,1))     AS Median_Waiting_Days,
    MAX(Waiting_Days)                          AS Max_Waiting_Days,
    CAST(MAX(Waiting_Days) / 7.0 AS decimal(5,1)) AS Max_Waiting_Weeks
FROM open_waits
GROUP BY Specialty_Code
ORDER BY Avg_Waiting_Days DESC;
GO

/* =====================================================================
   QUERY 6 — DUPLICATE PATIENT RECORDS (repeat NHS Numbers)
   Question : Which NHS Numbers appear more than once, and are the
              demographics consistent across their appointments?
   Logic    : Repeat appointments are normal; the risk is the SAME NHS
              Number carrying DIFFERENT surnames or dates of birth, which
              suggests a mis-keyed number or a merged record.
   ===================================================================== */
WITH repeat_patients AS (
    SELECT
        NHS_Number,
        COUNT(*)                         AS Appointment_Count,
        COUNT(DISTINCT Patient_Surname)  AS Distinct_Surnames,
        COUNT(DISTINCT Patient_DOB)      AS Distinct_DOBs,
        MIN(Patient_Surname)             AS Surname_Example,
        MAX(Patient_Surname)             AS Surname_Example_2
    FROM dbo.vw_Outpatient_Clean
    WHERE NHS_Number IS NOT NULL
    GROUP BY NHS_Number
    HAVING COUNT(*) > 1
)
SELECT
    NHS_Number,
    Surname_Example                                         AS Surname,
    Appointment_Count,
    Distinct_Surnames,
    Distinct_DOBs,
    CASE WHEN Distinct_Surnames = 1 AND Distinct_DOBs = 1 THEN 'Consistent'
         ELSE 'INCONSISTENT - investigate' END             AS Demographic_Check
FROM repeat_patients
ORDER BY Demographic_Check DESC, Appointment_Count DESC;

-- Summary line for the report
SELECT
    COUNT(*)                                                         AS NHS_Numbers_Repeated,
    SUM(CASE WHEN Distinct_Surnames > 1 OR Distinct_DOBs > 1 THEN 1 ELSE 0 END) AS Inconsistent_Demographics
FROM (SELECT NHS_Number, COUNT(DISTINCT Patient_Surname) AS Distinct_Surnames,
             COUNT(DISTINCT Patient_DOB) AS Distinct_DOBs
      FROM dbo.vw_Outpatient_Clean WHERE NHS_Number IS NOT NULL
      GROUP BY NHS_Number HAVING COUNT(*) > 1) x;
GO

/* =====================================================================
   QUERY 7 — LOST REFERRALS
   Question : Which patients have an OPEN RTT pathway but no inpatient
              admission or ED attendance in the same period?
   Logic    : NOT EXISTS anti-joins on NHS_Number. "Same period" = on or
              after 01/01/2025 (the outpatient extract covers Q1 2025).
   Caveat   : DQ issue XS-01 — no outpatient NHS Number appears in the
              inpatient or ED files at all, so this query cannot separate
              genuine lost referrals from a system-linkage failure.
   ===================================================================== */
WITH open_referrals AS (
    SELECT Appointment_ID, NHS_Number, Patient_Surname, Specialty_Code,
           Appointment_Date, RTT_Weeks
    FROM dbo.vw_Outpatient_Clean
    WHERE RTT_Status = 'OPEN'
      AND NHS_Number IS NOT NULL
)
SELECT o.*
FROM open_referrals o
WHERE NOT EXISTS (SELECT 1 FROM dbo.vw_Inpatient_Clean i
                  WHERE i.NHS_Number = o.NHS_Number
                    AND i.Admission_Date >= '2025-01-01')
  AND NOT EXISTS (SELECT 1 FROM dbo.vw_ED_Clean e
                  WHERE e.NHS_Number = o.NHS_Number
                    AND e.Arrival_Date >= '2025-01-01')
ORDER BY o.RTT_Weeks DESC;

-- Summary by specialty
WITH open_referrals AS (
    SELECT NHS_Number, Specialty_Code FROM dbo.vw_Outpatient_Clean
    WHERE RTT_Status = 'OPEN' AND NHS_Number IS NOT NULL
)
SELECT Specialty_Code, COUNT(*) AS Possible_Lost_Referrals
FROM open_referrals o
WHERE NOT EXISTS (SELECT 1 FROM dbo.vw_Inpatient_Clean i WHERE i.NHS_Number = o.NHS_Number AND i.Admission_Date >= '2025-01-01')
  AND NOT EXISTS (SELECT 1 FROM dbo.vw_ED_Clean e WHERE e.NHS_Number = o.NHS_Number AND e.Arrival_Date >= '2025-01-01')
GROUP BY Specialty_Code
ORDER BY Possible_Lost_Referrals DESC;
GO

/* =====================================================================
   QUERY 8 — REVENUE LEAKAGE (blank HRG codes)
   Question : How many episodes have no HRG code, by specialty, and what
              revenue is at risk at £1,850 per episode?
   Logic    : Uses the de-duplicated view (6 duplicate Episode_IDs removed)
              so no episode is counted twice. ROLLUP adds a Trust total.
   ===================================================================== */
DECLARE @Tariff money = 1850;     -- average income per episode (Priya Chakrabarti)

SELECT
    COALESCE(Specialty_Code, 'TRUST TOTAL')                        AS Specialty_Code,
    COUNT(*)                                                       AS Total_Episodes,
    SUM(CASE WHEN HRG_Code IS NULL THEN 1 ELSE 0 END)              AS Blank_HRG_Episodes,
    CAST(100.0 * SUM(CASE WHEN HRG_Code IS NULL THEN 1 ELSE 0 END) / COUNT(*) AS decimal(5,2)) AS Pct_Uncoded,
    SUM(CASE WHEN HRG_Code IS NULL THEN 1 ELSE 0 END) * @Tariff    AS Revenue_At_Risk_GBP
FROM dbo.vw_Inpatient_Clean
GROUP BY ROLLUP (Specialty_Code)
ORDER BY GROUPING(Specialty_Code), Blank_HRG_Episodes DESC;
GO

/* =====================================================================
   QUERY 9 — SERVICES BEATING THE 8% DNA TARGET
   Question : Which specialties have a DNA rate below the 8% Trust target?
   Logic    : Same NHS definition as Query 3, aggregated by specialty.
              HAVING filters to the high performers; the CTE also reports
              the Trust average for comparison.
   ===================================================================== */
WITH specialty_dna AS (
    SELECT
        Specialty_Code,
        SUM(CASE WHEN Attendance_Status IN ('ATT','DNA','REF') THEN 1 ELSE 0 END) AS Booked,
        SUM(CASE WHEN Attendance_Status = 'DNA' THEN 1 ELSE 0 END)                AS DNA_Count
    FROM dbo.vw_Outpatient_Clean
    WHERE Attendance_Status IN ('ATT','DNA','CAN','REF')
    GROUP BY Specialty_Code
), trust AS (
    SELECT 100.0 * SUM(DNA_Count) / SUM(Booked) AS Trust_DNA_Pct FROM specialty_dna
)
SELECT
    s.Specialty_Code,
    s.Booked,
    s.DNA_Count,
    CAST(100.0 * s.DNA_Count / s.Booked AS decimal(5,2))   AS DNA_Rate_Pct,
    CAST(t.Trust_DNA_Pct AS decimal(5,2))                  AS Trust_DNA_Pct
FROM specialty_dna s CROSS JOIN trust t
WHERE 100.0 * s.DNA_Count / s.Booked < 8.0                 -- below the 8% Trust target
ORDER BY DNA_Rate_Pct ASC;
GO

/* =====================================================================
   QUERY 10 — READMISSION PATTERN (CTE)
   Question : Among episodes flagged as readmissions, which admission
              types and specialties have the most?
   Logic    : CTE isolates Readmission_Flag = 'Y' (existing EHR flags,
              duplicates removed). Second CTE gives each specialty's
              total episodes so a rate can be shown alongside the count.
              Note: 44 blank flags are NOT back-filled here (see report).
   ===================================================================== */
WITH readmissions AS (
    SELECT Episode_ID, Admission_Type, Specialty_Code
    FROM dbo.vw_Inpatient_Clean
    WHERE Readmission_Flag = 'Y'
), specialty_totals AS (
    SELECT Specialty_Code, Admission_Type, COUNT(*) AS Total_Episodes
    FROM dbo.vw_Inpatient_Clean
    GROUP BY Specialty_Code, Admission_Type
)
SELECT
    r.Admission_Type,
    r.Specialty_Code,
    COUNT(*)                                                     AS Readmissions,
    t.Total_Episodes,
    CAST(100.0 * COUNT(*) / t.Total_Episodes AS decimal(5,2))    AS Readmission_Rate_Pct,
    RANK() OVER (ORDER BY COUNT(*) DESC)                         AS Rank_By_Count
FROM readmissions r
JOIN specialty_totals t
  ON t.Specialty_Code = r.Specialty_Code AND t.Admission_Type = r.Admission_Type
GROUP BY r.Admission_Type, r.Specialty_Code, t.Total_Episodes
ORDER BY Readmissions DESC;

-- Roll-up by admission type only
SELECT Admission_Type, COUNT(*) AS Readmissions
FROM dbo.vw_Inpatient_Clean
WHERE Readmission_Flag = 'Y'
GROUP BY Admission_Type
ORDER BY Readmissions DESC;
GO

/* =====================================================================
   QUERY 11 — AGENCY SPEND BY WARD
   Question : Which wards have the most confirmed agency shifts, and what
              is the estimated cost at £385 per shift?
   Logic    : Confirmed agency only (Agency_Flag = 'Y'); blank flags and
              ST-99 test records excluded (the view already removes ST-99).
              Share of each ward's shifts shown for context.
   ===================================================================== */
DECLARE @AgencyRate money = 385;

WITH ward_shifts AS (
    SELECT
        Ward_Code,
        COUNT(*)                                              AS Total_Shifts,
        SUM(CASE WHEN Agency_Flag = 'Y' THEN 1 ELSE 0 END)    AS Agency_Shifts
    FROM dbo.vw_Workforce_Clean
    WHERE Agency_Flag IS NOT NULL                          -- exclude blank flags
    GROUP BY Ward_Code
)
SELECT
    Ward_Code,
    Total_Shifts,
    Agency_Shifts,
    CAST(100.0 * Agency_Shifts / Total_Shifts AS decimal(5,2)) AS Agency_Share_Pct,
    Agency_Shifts * @AgencyRate                                AS Est_Agency_Cost_GBP,
    RANK() OVER (ORDER BY Agency_Shifts DESC)                  AS Rank_By_Agency_Shifts
FROM ward_shifts
ORDER BY Agency_Shifts DESC;
GO

/* =====================================================================
   QUERY 12 — THEATRE CANCELLATION PATTERN
   Question : Is there a day-of-week or specialty pattern in theatre
              cancellations? Which week/specialty combinations are worst?
   Logic    : (a) Day of week — TheatreUtilisation is a WEEKLY summary
              (one row per theatre per week ending Sunday), so a true
              day-of-week pattern cannot be measured; part (a) proves this.
              (b) Specialty pattern — total and per-100-cases rates.
              (c) Top 10 week x specialty combinations (DENSE_RANK).
              Blank cancellation fields are treated as unknown (NULL), and
              ISNULL(...,0) is used only when summing.
   ===================================================================== */
-- (a) Day-of-week check
SELECT DATENAME(weekday, Week_Ending) AS Day_Name, COUNT(*) AS Theatre_Weeks
FROM dbo.vw_Theatre_Clean
GROUP BY DATENAME(weekday, Week_Ending);

-- (b) Specialty pattern
SELECT
    Specialty_Code,
    COUNT(*)                                                                AS Theatre_Weeks,
    SUM(Cases_Planned)                                                      AS Cases_Planned,
    SUM(ISNULL(Cancellations_Trust, 0))                                     AS Trust_Cancellations,
    SUM(ISNULL(Cancellations_Patient, 0))                                   AS Patient_Cancellations,
    SUM(ISNULL(Cancellations_Trust, 0) + ISNULL(Cancellations_Patient, 0))  AS Total_Cancellations,
    CAST(100.0 * SUM(ISNULL(Cancellations_Trust, 0) + ISNULL(Cancellations_Patient, 0))
         / SUM(Cases_Planned) AS decimal(5,2))                              AS Cancellations_Per_100_Cases,
    SUM(CASE WHEN Cancellations_Trust IS NULL OR Cancellations_Patient IS NULL THEN 1 ELSE 0 END) AS Weeks_With_Missing_Data
FROM dbo.vw_Theatre_Clean
GROUP BY Specialty_Code
ORDER BY Cancellations_Per_100_Cases DESC;

-- (c) Worst week x specialty combinations
WITH week_spec AS (
    SELECT
        Week_Ending,
        Specialty_Code,
        SUM(ISNULL(Cancellations_Trust, 0))                                    AS Trust_Cancellations,
        SUM(ISNULL(Cancellations_Trust, 0) + ISNULL(Cancellations_Patient, 0)) AS Total_Cancellations
    FROM dbo.vw_Theatre_Clean
    GROUP BY Week_Ending, Specialty_Code
)
SELECT TOP 10 WITH TIES
    Week_Ending,
    Specialty_Code,
    Trust_Cancellations,
    Total_Cancellations,
    DENSE_RANK() OVER (ORDER BY Total_Cancellations DESC) AS Cancellation_Rank
FROM week_spec
ORDER BY Total_Cancellations DESC, Week_Ending;

-- (d) Monthly trend — the closest available proxy for a time pattern
SELECT
    FORMAT(Week_Ending, 'yyyy-MM')                                         AS Month,
    SUM(ISNULL(Cancellations_Trust, 0))                                    AS Trust_Cancellations,
    SUM(ISNULL(Cancellations_Patient, 0))                                  AS Patient_Cancellations,
    CAST(100.0 * SUM(ISNULL(Cancellations_Trust, 0) + ISNULL(Cancellations_Patient, 0))
         / SUM(Cases_Planned) AS decimal(5,2))                             AS Cancellations_Per_100_Cases
FROM dbo.vw_Theatre_Clean
GROUP BY FORMAT(Week_Ending, 'yyyy-MM')
ORDER BY Month;
GO
