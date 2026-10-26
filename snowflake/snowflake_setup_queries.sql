/* =====================================================================
   Bronings University Hospital Group — Phase 6
   Script : 02_snowflake_setup.sql   (Snowflake SQL — run in a Snowsight worksheet)
   Author : Lucky Ukeni, Advanced Healthcare Data Analyst
   Purpose: 1) Warehouse, database BRONINGS_ANALYTICS, schema HOSPITAL_OPERATIONS
            2) Load the five CSV exports into raw tables (all VARCHAR — nothing lost)
            3) Cleaned views that apply the Phase 3 DQ fixes and the Phase 5
               KPI Framework definitions, so Power BI and Tableau show the SAME
               numbers as the Excel and SQL Server work
            4) KPI_TARGETS reference table that drives the RAG scorecard
   Run order: sections 1 → 2 → (export from SQL Server + upload) → 3 → 4 → 5
   Source  : Per Daniel Walsh, the five tables are migrated FROM SQL Server
             (BRONINGS-SQL01\SQLEXPRESS, BroningsAnalytics) INTO Snowflake.
             Power BI and Tableau then connect to Snowflake ONLY — never to SQL Server.
   ===================================================================== */

/* ---------------------------------------------------------------------
   1. COMPUTE, DATABASE, SCHEMA
      X-Small + 60-second auto-suspend keeps the 30-day trial credits safe.
   --------------------------------------------------------------------- */
USE ROLE ACCOUNTADMIN;

CREATE WAREHOUSE IF NOT EXISTS BRONINGS_WH
  WAREHOUSE_SIZE = 'XSMALL'
  AUTO_SUSPEND = 60
  AUTO_RESUME = TRUE
  INITIALLY_SUSPENDED = TRUE
  COMMENT = 'Bronings analytics — Power BI / Tableau';

-- Daniel has already created these; IF NOT EXISTS leaves his objects untouched.
CREATE DATABASE IF NOT EXISTS BRONINGS_ANALYTICS;
CREATE SCHEMA   IF NOT EXISTS BRONINGS_ANALYTICS.HOSPITAL_OPERATIONS;

USE WAREHOUSE BRONINGS_WH;
USE SCHEMA BRONINGS_ANALYTICS.HOSPITAL_OPERATIONS;

/* ---------------------------------------------------------------------
   2. FILE FORMAT, STAGE AND RAW TABLES
      EMPTY_FIELD_AS_NULL turns blank CSV cells into NULL on load.
      Every column is VARCHAR so NHS Numbers keep their leading zero
      (188 numbers start with 0 — DQ issues OP-05 / IP-13).
   --------------------------------------------------------------------- */
CREATE OR REPLACE FILE FORMAT CSV_UK
  TYPE = CSV
  FIELD_DELIMITER = ','
  SKIP_HEADER = 1
  FIELD_OPTIONALLY_ENCLOSED_BY = '"'
  EMPTY_FIELD_AS_NULL = TRUE
  TRIM_SPACE = TRUE
  ENCODING = 'UTF8';

CREATE OR REPLACE STAGE BRONINGS_STAGE FILE_FORMAT = CSV_UK;

CREATE OR REPLACE TABLE OUTPATIENT_APPOINTMENTS (
  APPOINTMENT_ID VARCHAR, NHS_NUMBER VARCHAR, PATIENT_SURNAME VARCHAR, PATIENT_DOB VARCHAR,
  SPECIALTY_CODE VARCHAR, CONSULTANT_CODE VARCHAR, CLINIC_CODE VARCHAR, APPOINTMENT_DATE VARCHAR,
  APPOINTMENT_TIME VARCHAR, ATTENDANCE_STATUS VARCHAR, WAITING_DAYS VARCHAR, RTT_STATUS VARCHAR,
  RTT_WEEKS VARCHAR, REFERRAL_SOURCE VARCHAR, POSTCODE VARCHAR);

CREATE OR REPLACE TABLE INPATIENT_ADMISSIONS (
  EPISODE_ID VARCHAR, NHS_NUMBER VARCHAR, PATIENT_SURNAME VARCHAR, PATIENT_DOB VARCHAR,
  ADMISSION_DATE VARCHAR, ADMISSION_TYPE VARCHAR, WARD_CODE VARCHAR, SPECIALTY_CODE VARCHAR,
  DISCHARGE_DATE VARCHAR, DISCHARGE_METHOD VARCHAR, LENGTH_OF_STAY VARCHAR, READMISSION_FLAG VARCHAR,
  HRG_CODE VARCHAR, BED_DAYS VARCHAR, CONSULTANT_CODE VARCHAR, ICD10_CODE VARCHAR, OPCS4_CODE VARCHAR);

CREATE OR REPLACE TABLE ED_ATTENDANCES (
  ATTENDANCE_ID VARCHAR, NHS_NUMBER VARCHAR, PATIENT_SURNAME VARCHAR, PATIENT_DOB VARCHAR,
  ARRIVAL_DATE VARCHAR, ARRIVAL_TIME VARCHAR, TRIAGE_CATEGORY VARCHAR, SEEN_BY_CLINICIAN_TIME VARCHAR,
  DEPARTURE_TIME VARCHAR, DEPARTURE_CODE VARCHAR, FOUR_HOUR_BREACH VARCHAR, TOTAL_ED_TIME_MINUTES VARCHAR,
  CHIEF_COMPLAINT VARCHAR, SPECIALTY_REFERRED VARCHAR);

CREATE OR REPLACE TABLE THEATRE_UTILISATION (
  WEEK_ENDING VARCHAR, THEATRE_ID VARCHAR, SESSIONS_AVAILABLE VARCHAR, SESSIONS_USED VARCHAR,
  UTILISATION_PCT VARCHAR, CASES_PLANNED VARCHAR, CASES_COMPLETED VARCHAR, CANCELLATIONS_TRUST VARCHAR,
  CANCELLATIONS_PATIENT VARCHAR, OVERRUN_MINUTES VARCHAR, SPECIALTY_CODE VARCHAR);

CREATE OR REPLACE TABLE WORKFORCE_STAFFING (
  SHIFT_ID VARCHAR, STAFF_ID VARCHAR, STAFF_GRADE VARCHAR, WARD_CODE VARCHAR, SHIFT_DATE VARCHAR,
  SHIFT_TYPE VARCHAR, HOURS_ROSTERED VARCHAR, HOURS_WORKED VARCHAR, AGENCY_FLAG VARCHAR,
  ABSENCE_FLAG VARCHAR, OVERTIME_HOURS VARCHAR, SPECIALTY_CODE VARCHAR);

/* ---------------------------------------------------------------------
   >>> EXPORT FROM SQL SERVER, THEN UPLOAD TO THE STAGE <<<
   Step A — export each SQL Server table to a comma-separated file.
            Run in a Windows command prompt (bcp ships with SQL Server).
            -c = text, -t, = comma delimiter, -T = Windows authentication.
            No field in these tables contains a comma, so no quoting is needed.

   bcp BroningsAnalytics.dbo.OutpatientAppointments out C:\Bronings\Export\03_outpatient_appointments.csv -c -t, -T -S BRONINGS-SQL01\SQLEXPRESS
   bcp BroningsAnalytics.dbo.InpatientAdmissions    out C:\Bronings\Export\04_inpatient_admissions.csv    -c -t, -T -S BRONINGS-SQL01\SQLEXPRESS
   bcp BroningsAnalytics.dbo.EDAttendances          out C:\Bronings\Export\05_ed_attendances.csv          -c -t, -T -S BRONINGS-SQL01\SQLEXPRESS
   bcp BroningsAnalytics.dbo.TheatreUtilisation     out C:\Bronings\Export\06_theatre_utilisation.csv     -c -t, -T -S BRONINGS-SQL01\SQLEXPRESS
   bcp BroningsAnalytics.dbo.WorkforceStaffing      out C:\Bronings\Export\07_workforce_staffing.csv      -c -t, -T -S BRONINGS-SQL01\SQLEXPRESS

   IMPORTANT: bcp files have NO header row. If you load bcp files, run the
   ALTER below so the first data row is not skipped. (If you use the SSMS
   Export Wizard with "column names in first row" ticked, or the original
   CSVs, leave SKIP_HEADER = 1.)

   ALTER FILE FORMAT CSV_UK SET SKIP_HEADER = 0;

   Step B — upload the five files to the stage.
   Snowsight: Data > Databases > BRONINGS_ANALYTICS > HOSPITAL_OPERATIONS
              > Stages > BRONINGS_STAGE > "+ Files" > select all five.
   (SnowSQL alternative: PUT file://C:/Bronings/Export/*.csv @BRONINGS_STAGE;)
   Check they arrived:
   --------------------------------------------------------------------- */
LIST @BRONINGS_STAGE;

/* ---------------------------------------------------------------------
   3. LOAD — PATTERN matches the file whether or not it was gzipped
   --------------------------------------------------------------------- */
COPY INTO OUTPATIENT_APPOINTMENTS FROM @BRONINGS_STAGE PATTERN = '.*03_outpatient_appointments.*' ON_ERROR = 'ABORT_STATEMENT';
COPY INTO INPATIENT_ADMISSIONS    FROM @BRONINGS_STAGE PATTERN = '.*04_inpatient_admissions.*'    ON_ERROR = 'ABORT_STATEMENT';
COPY INTO ED_ATTENDANCES          FROM @BRONINGS_STAGE PATTERN = '.*05_ed_attendances.*'          ON_ERROR = 'ABORT_STATEMENT';
COPY INTO THEATRE_UTILISATION     FROM @BRONINGS_STAGE PATTERN = '.*06_theatre_utilisation.*'     ON_ERROR = 'ABORT_STATEMENT';
COPY INTO WORKFORCE_STAFFING      FROM @BRONINGS_STAGE PATTERN = '.*07_workforce_staffing.*'      ON_ERROR = 'ABORT_STATEMENT';

-- Evidence screenshot: expect 580 / 1206 / 969 / 208 / 1560
SELECT 'OUTPATIENT_APPOINTMENTS' AS TABLE_NAME, COUNT(*) AS ROW_COUNT FROM OUTPATIENT_APPOINTMENTS
UNION ALL SELECT 'INPATIENT_ADMISSIONS', COUNT(*) FROM INPATIENT_ADMISSIONS
UNION ALL SELECT 'ED_ATTENDANCES',       COUNT(*) FROM ED_ATTENDANCES
UNION ALL SELECT 'THEATRE_UTILISATION',  COUNT(*) FROM THEATRE_UTILISATION
UNION ALL SELECT 'WORKFORCE_STAFFING',   COUNT(*) FROM WORKFORCE_STAFFING;

/* ---------------------------------------------------------------------
   4. CLEANED VIEWS — the ONLY objects Power BI and Tableau connect to
   --------------------------------------------------------------------- */

-- 4a. Outpatients: GEN->GM; 'attended'->ATT; 'N/A'->NULL (row kept for RTT);
--     text Waiting_Days recovered from RTT_Weeks x 7; negative waits -> NULL;
--     blank RTT_Status -> OPEN. Flags make DAX / Tableau measures simple sums.
CREATE OR REPLACE VIEW VW_OUTPATIENT AS
WITH b AS (
  SELECT
    APPOINTMENT_ID,
    NHS_NUMBER,                                                     -- kept as text
    PATIENT_SURNAME,
    TRY_TO_DATE(PATIENT_DOB, 'DD/MM/YYYY')                         AS PATIENT_DOB,
    IFF(SPECIALTY_CODE = 'GEN', 'GM', SPECIALTY_CODE)              AS SPECIALTY_CODE,
    CONSULTANT_CODE,
    CLINIC_CODE,
    TRY_TO_DATE(APPOINTMENT_DATE, 'DD/MM/YYYY')                    AS APPOINTMENT_DATE,
    CASE WHEN LOWER(ATTENDANCE_STATUS) = 'attended' THEN 'ATT'
         WHEN ATTENDANCE_STATUS = 'N/A' THEN NULL
         ELSE UPPER(ATTENDANCE_STATUS) END                         AS ATTENDANCE_STATUS,
    CASE WHEN TRY_TO_NUMBER(WAITING_DAYS) >= 0 THEN TRY_TO_NUMBER(WAITING_DAYS)
         WHEN TRY_TO_NUMBER(WAITING_DAYS) IS NULL
              THEN ROUND(TRY_TO_DECIMAL(RTT_WEEKS, 6, 1) * 7)
         END                                                       AS WAITING_DAYS,
    -- blank status -> OPEN (Task 10); but a pathway with no recorded RTT clock
    -- (APT-100200: negative wait, no RTT_Weeks) cannot be measured -> NULL
    IFF(TRY_TO_DECIMAL(RTT_WEEKS, 6, 1) IS NULL, NULL,
        COALESCE(UPPER(RTT_STATUS), 'OPEN'))                       AS RTT_STATUS,
    TRY_TO_DECIMAL(RTT_WEEKS, 6, 1)                                AS RTT_WEEKS,
    REFERRAL_SOURCE
  FROM OUTPATIENT_APPOINTMENTS
)
SELECT b.*,
  DATE_TRUNC('WEEK', APPOINTMENT_DATE)                                       AS WEEK_START,
  IFF(ATTENDANCE_STATUS IN ('ATT','DNA','CAN','REF'), 1, 0)                  AS IS_VALID_STATUS,   -- DNA denominator
  IFF(ATTENDANCE_STATUS = 'DNA', 1, 0)                                       AS IS_DNA,
  IFF(RTT_STATUS = 'OPEN' AND RTT_WEEKS IS NOT NULL, 1, 0)                   AS IS_OPEN_PATHWAY,
  IFF(RTT_STATUS = 'OPEN' AND RTT_WEEKS <= 18, 1, 0)                         AS IS_WITHIN_18_WEEKS,
  IFF(RTT_STATUS = 'OPEN' AND RTT_WEEKS > 52, 1, 0)                          AS IS_OVER_52_WEEKS
FROM b;

-- 4b. Inpatients: duplicates removed (keep lowest ward); GEN->GM; admission types
--     standardised; text discharge dates converted; LOS recalculated from dates;
--     blank Readmission_Flag back-filled with the 30-day rule (Framework KPI 11).
CREATE OR REPLACE VIEW VW_INPATIENT AS
WITH d AS (
  SELECT *
  FROM INPATIENT_ADMISSIONS
  QUALIFY ROW_NUMBER() OVER (PARTITION BY EPISODE_ID ORDER BY WARD_CODE) = 1
), t AS (
  SELECT
    EPISODE_ID, NHS_NUMBER, PATIENT_SURNAME,
    TRY_TO_DATE(ADMISSION_DATE, 'DD/MM/YYYY')                          AS ADMISSION_DATE,
    CASE UPPER(ADMISSION_TYPE) WHEN 'ELECTIVE' THEN 'ELEC'
                               WHEN 'EMERGENCY' THEN 'EMER'
                               ELSE UPPER(ADMISSION_TYPE) END          AS ADMISSION_TYPE,
    WARD_CODE,
    IFF(SPECIALTY_CODE = 'GEN', 'GM', SPECIALTY_CODE)                  AS SPECIALTY_CODE,
    COALESCE(
      TRY_TO_DATE(DISCHARGE_DATE, 'DD/MM/YYYY'),
      -- 3 rows stored as 'October 9 2024' (DQ issue IP-05)
      TRY_TO_DATE(SPLIT_PART(DISCHARGE_DATE, ' ', 3) || '-' ||
                  LPAD(DECODE(SPLIT_PART(DISCHARGE_DATE, ' ', 1),
                       'January',1,'February',2,'March',3,'April',4,'May',5,'June',6,'July',7,
                       'August',8,'September',9,'October',10,'November',11,'December',12)::VARCHAR, 2, '0') || '-' ||
                  LPAD(SPLIT_PART(DISCHARGE_DATE, ' ', 2), 2, '0'), 'YYYY-MM-DD')
    )                                                                  AS DISCHARGE_DATE,
    DISCHARGE_METHOD, READMISSION_FLAG AS READMISSION_FLAG_ORIGINAL, HRG_CODE, CONSULTANT_CODE
  FROM d
), prev AS (
  -- latest earlier discharge for the same patient, used to back-fill blank flags
  SELECT a.EPISODE_ID, MAX(p.DISCHARGE_DATE) AS PREV_DISCHARGE
  FROM t a
  JOIN t p ON p.NHS_NUMBER = a.NHS_NUMBER
          AND p.EPISODE_ID <> a.EPISODE_ID
          AND p.DISCHARGE_DATE <= a.ADMISSION_DATE
  GROUP BY a.EPISODE_ID
)
SELECT
  t.*,
  DATEDIFF('day', t.ADMISSION_DATE, t.DISCHARGE_DATE)                        AS LENGTH_OF_STAY,
  -- READMISSION_FLAG = original EHR flag, with the 44 blanks back-filled by the
  -- 30-day rule (Framework KPI 11). The untouched value is READMISSION_FLAG_ORIGINAL.
  COALESCE(t.READMISSION_FLAG_ORIGINAL,
           IFF(DATEDIFF('day', prev.PREV_DISCHARGE, t.ADMISSION_DATE) <= 30, 'Y', 'N')) AS READMISSION_FLAG,
  IFF(t.HRG_CODE IS NULL, 1, 0)                                              AS IS_HRG_BLANK,
  IFF(t.WARD_CODE = 'W-08', 1, 0)                                            AS IS_CLOSED_WARD,
  DATE_TRUNC('MONTH', t.ADMISSION_DATE)                                      AS ADMISSION_MONTH
FROM t
LEFT JOIN prev ON prev.EPISODE_ID = t.EPISODE_ID;

-- 4c. Daily bed census (midnight) by ward — feeds the bed occupancy chart.
--     Open episodes (no discharge date) count as occupied; W-08 excluded.
CREATE OR REPLACE VIEW VW_BED_CENSUS AS
WITH days AS (
  SELECT DATEADD('day', SEQ4(), '2024-10-01'::DATE) AS CENSUS_DATE
  FROM TABLE(GENERATOR(ROWCOUNT => 182))                      -- 01/10/2024 – 31/03/2025
)
SELECT d.CENSUS_DATE, i.WARD_CODE, COUNT(i.EPISODE_ID) AS PATIENTS_IN_BED
FROM days d
JOIN VW_INPATIENT i
  ON i.ADMISSION_DATE <= d.CENSUS_DATE
 AND (i.DISCHARGE_DATE IS NULL OR i.DISCHARGE_DATE > d.CENSUS_DATE)
WHERE i.IS_CLOSED_WARD = 0
GROUP BY d.CENSUS_DATE, i.WARD_CODE;

-- 4d. ED: duplicates removed; 12-hour AM/PM times parsed; minutes and 4-hour
--     breach recalculated from Arrival/Departure (Four_Hour_Breach NOT used).
CREATE OR REPLACE VIEW VW_ED AS
WITH d AS (
  SELECT *
  FROM ED_ATTENDANCES
  QUALIFY ROW_NUMBER() OVER (PARTITION BY ATTENDANCE_ID ORDER BY ARRIVAL_TIME) = 1
), p AS (
  SELECT d.*,
    TRY_TO_NUMBER(SPLIT_PART(ARRIVAL_TIME, ':', 1))                  AS ARR_H,
    TRY_TO_NUMBER(LEFT(SPLIT_PART(ARRIVAL_TIME, ':', 2), 2))         AS ARR_M,
    CASE WHEN ARRIVAL_TIME ILIKE '%PM' THEN 'PM'
         WHEN ARRIVAL_TIME ILIKE '%AM' THEN 'AM' END                 AS ARR_AMPM,
    TRY_TO_NUMBER(SPLIT_PART(DEPARTURE_TIME, ':', 1)) * 60
      + TRY_TO_NUMBER(LEFT(SPLIT_PART(DEPARTURE_TIME, ':', 2), 2))   AS DEP_MIN
  FROM d
), m AS (
  SELECT p.*,
    IFF(ARR_AMPM IS NULL, ARR_H * 60 + ARR_M,
        (MOD(ARR_H, 12) + IFF(ARR_AMPM = 'PM', 12, 0)) * 60 + ARR_M) AS ARR_MIN
  FROM p
)
SELECT
  ATTENDANCE_ID, NHS_NUMBER,
  TRY_TO_DATE(ARRIVAL_DATE, 'DD/MM/YYYY')                            AS ARRIVAL_DATE,
  DATE_TRUNC('WEEK', TRY_TO_DATE(ARRIVAL_DATE, 'DD/MM/YYYY'))        AS WEEK_START,
  TRY_TO_NUMBER(TRIAGE_CATEGORY)                                     AS TRIAGE_CATEGORY,
  IFF(TRY_TO_NUMBER(TRIAGE_CATEGORY) BETWEEN 1 AND 5, 1, 0)          AS IS_VALID_TRIAGE,
  DEPARTURE_CODE,
  IFF(DEP_MIN IS NULL, NULL, MOD(DEP_MIN - ARR_MIN + 1440, 1440))    AS ED_MINUTES,
  IFF(DEP_MIN IS NULL, NULL, IFF(MOD(DEP_MIN - ARR_MIN + 1440, 1440) > 240, 1, 0)) AS IS_4HR_BREACH,
  IFF(DEP_MIN IS NULL, 0, 1)                                         AS HAS_DEPARTURE,
  IFF(DEPARTURE_CODE = 'LWBS', 1, 0)                                 AS IS_LWBS,
  UPPER(CHIEF_COMPLAINT)                                             AS CHIEF_COMPLAINT
FROM m;

-- 4e. Theatres: 'Theatre One'->T3; week ending moved to Sunday; sessions capped;
--     both Framework measures pre-computed (TU-S sessions, TU-H hours).
CREATE OR REPLACE VIEW VW_THEATRE AS
WITH t AS (
  SELECT
    TRY_TO_DATE(WEEK_ENDING, 'DD/MM/YYYY')                  AS WE_RAW,
    IFF(THEATRE_ID = 'Theatre One', 'T3', THEATRE_ID)       AS THEATRE_ID,
    TRY_TO_NUMBER(SESSIONS_AVAILABLE)                       AS SESSIONS_AVAILABLE,
    TRY_TO_NUMBER(SESSIONS_USED)                            AS SESSIONS_USED,
    TRY_TO_NUMBER(CASES_PLANNED)                            AS CASES_PLANNED,
    TRY_TO_NUMBER(CASES_COMPLETED)                          AS CASES_COMPLETED,
    TRY_TO_NUMBER(CANCELLATIONS_TRUST)                      AS CANCELLATIONS_TRUST,
    TRY_TO_NUMBER(CANCELLATIONS_PATIENT)                    AS CANCELLATIONS_PATIENT,
    TRY_TO_NUMBER(OVERRUN_MINUTES)                          AS OVERRUN_MINUTES,
    IFF(SPECIALTY_CODE = 'GEN', 'GM', SPECIALTY_CODE)       AS SPECIALTY_CODE
  FROM THEATRE_UTILISATION
)
SELECT
  DATEADD('day', -MOD(DAYOFWEEKISO(WE_RAW), 7), WE_RAW)     AS WEEK_ENDING,   -- Sunday
  THEATRE_ID, SESSIONS_AVAILABLE, SESSIONS_USED,
  LEAST(SESSIONS_USED, SESSIONS_AVAILABLE)                  AS SESSIONS_USED_CAPPED,
  IFF(THEATRE_ID IN ('T1','T2','T3'), 1, 0)                 AS IS_ELECTIVE,
  CASES_PLANNED, CASES_COMPLETED, CANCELLATIONS_TRUST, CANCELLATIONS_PATIENT,
  OVERRUN_MINUTES, SPECIALTY_CODE,
  SESSIONS_USED * 240 + OVERRUN_MINUTES                     AS MINUTES_USED_INCL_OVERRUN,   -- TU-H numerator
  SESSIONS_AVAILABLE * 240                                  AS MINUTES_SCHEDULED            -- TU-H denominator
FROM t;

-- 4f. Workforce: ST-99 test records removed; shift types standardised;
--     Working Time Regulations flag; month for trends.
CREATE OR REPLACE VIEW VW_WORKFORCE AS
SELECT
  SHIFT_ID, STAFF_ID, STAFF_GRADE, WARD_CODE,
  TRY_TO_DATE(SHIFT_DATE, 'DD/MM/YYYY')                     AS SHIFT_DATE,
  DATE_TRUNC('MONTH', TRY_TO_DATE(SHIFT_DATE, 'DD/MM/YYYY')) AS SHIFT_MONTH,
  DECODE(SHIFT_TYPE, 'D','DAY', 'N','NIGHT', 'L','LONG', SHIFT_TYPE) AS SHIFT_TYPE,
  TRY_TO_DECIMAL(HOURS_ROSTERED, 4, 1)                      AS HOURS_ROSTERED,
  TRY_TO_DECIMAL(HOURS_WORKED, 4, 1)                        AS HOURS_WORKED,
  AGENCY_FLAG,                                              -- NULL = unknown (blank)
  IFF(AGENCY_FLAG = 'Y', 1, 0)                              AS IS_AGENCY,
  IFF(AGENCY_FLAG IS NOT NULL, 1, 0)                        AS HAS_AGENCY_FLAG,
  IFF(TRY_TO_DECIMAL(HOURS_WORKED, 4, 1) > 13, 1, 0)        AS IS_WTR_BREACH,
  ABSENCE_FLAG,
  IFF(SPECIALTY_CODE = 'GEN', 'GM', SPECIALTY_CODE)         AS SPECIALTY_CODE
FROM WORKFORCE_STAFFING
WHERE STAFF_ID IS NULL OR STAFF_ID NOT LIKE 'ST-99%';

-- 4g. Finance (monthly) — feeds DAX measure 3 "YTD Variance".
--     ACTUAL  = confirmed agency shifts x £385 (Priya Chakrabarti's rate).
--     BUDGET  = target-based budget: 8% Trust target share of all shifts x £385.
--     Interim until Finance supplies the ledger budget; then replace BUDGET_GBP.
CREATE OR REPLACE VIEW VW_FINANCE_MONTHLY AS
SELECT
  SHIFT_MONTH                                         AS MONTH_START,
  COUNT(*)                                            AS TOTAL_SHIFTS,
  SUM(IS_AGENCY)                                      AS AGENCY_SHIFTS,
  SUM(IS_AGENCY) * 385                                AS ACTUAL_SPEND_GBP,
  ROUND(0.08 * COUNT(*) * 385)                        AS BUDGET_GBP
FROM VW_WORKFORCE
GROUP BY SHIFT_MONTH;

/* ---------------------------------------------------------------------
   5. KPI_TARGETS — drives the Executive Summary RAG scorecard
      Values from the signed-off 18-KPI Framework (v1.1).
      DIRECTION: 'HIGHER' = higher is better; 'LOWER' = lower is better.
   --------------------------------------------------------------------- */
CREATE OR REPLACE TABLE KPI_TARGETS (
  KPI_ID VARCHAR, KPI_NAME VARCHAR, PAGE VARCHAR, DIRECTION VARCHAR,
  TRUST_TARGET FLOAT, NHS_STANDARD FLOAT, AMBER_TOLERANCE FLOAT, OWNER VARCHAR);

INSERT INTO KPI_TARGETS VALUES
 ('K01','ED 4-hour compliance','Emergency Department','HIGHER',0.90,0.95,0.05,'Director of Operations'),
 ('K02','LWBS rate','Emergency Department','LOWER',0.05,0.05,0.01,'ED Clinical Lead'),
 ('K03','DNA rate','Outpatient Waiting','LOWER',0.08,0.10,0.02,'Performance Manager'),
 ('K04','RTT 18-week compliance','Outpatient Waiting','HIGHER',0.88,0.92,0.04,'Director of Operations'),
 ('K06','Patients waiting >52 weeks','Outpatient Waiting','LOWER',0,0,0,'Director of Operations'),
 ('K07','Theatre utilisation (sessions, T1-T3)','Capacity','HIGHER',0.85,0.85,0.05,'Theatres Manager'),
 ('K09','Bed occupancy','Capacity','LOWER',0.85,0.92,0.07,'Director of Operations'),
 ('K10','Average length of stay (days)','Capacity','LOWER',4.5,4.5,0.5,'Medical Director'),
 ('K11','30-day readmission rate','Capacity','LOWER',0.10,0.10,0.01,'Medical Director'),
 ('K12','HRG coding completeness','Finance','HIGHER',0.98,0.98,0.02,'Clinical Coding Manager'),
 ('K13','Agency share of shifts','Workforce','LOWER',0.08,0.032,0.02,'Finance Business Partner'),
 ('K17','DQMI score','Executive Summary','HIGHER',75,75,10,'Head of Analytics');

-- Final check — every view returns rows (screenshot for evidence)
SELECT 'VW_OUTPATIENT' AS VIEW_NAME, COUNT(*) AS ROWS_ FROM VW_OUTPATIENT       -- expect 580
UNION ALL SELECT 'VW_INPATIENT',  COUNT(*) FROM VW_INPATIENT                     -- expect 1200
UNION ALL SELECT 'VW_ED',         COUNT(*) FROM VW_ED                            -- expect 960
UNION ALL SELECT 'VW_THEATRE',    COUNT(*) FROM VW_THEATRE                       -- expect 208
UNION ALL SELECT 'VW_WORKFORCE',  COUNT(*) FROM VW_WORKFORCE                     -- expect 1536
UNION ALL SELECT 'VW_BED_CENSUS', COUNT(*) FROM VW_BED_CENSUS
UNION ALL SELECT 'VW_FINANCE_MONTHLY', COUNT(*) FROM VW_FINANCE_MONTHLY;                -- expect 3

-- Spot-check against the Framework baselines
SELECT
  (SELECT ROUND(100 * SUM(IS_DNA) / SUM(IS_VALID_STATUS), 1) FROM VW_OUTPATIENT)                     AS DNA_RATE_PCT,      -- 13.1
  (SELECT ROUND(100 * SUM(IS_WITHIN_18_WEEKS) / SUM(IS_OPEN_PATHWAY), 2) FROM VW_OUTPATIENT)         AS RTT18_PCT,         -- 41.98
  (SELECT ROUND(100 * COUNT_IF(READMISSION_FLAG = 'Y') / COUNT(*), 2) FROM VW_INPATIENT)             AS READMISSION_PCT,   -- 10.25
  (SELECT ROUND(100 * (1 - SUM(IS_4HR_BREACH) / SUM(HAS_DEPARTURE)), 1) FROM VW_ED)                  AS ED_4HR_PCT,        -- 83.1
  (SELECT ROUND(100 * SUM(SESSIONS_USED_CAPPED) / SUM(SESSIONS_AVAILABLE), 1)
     FROM VW_THEATRE WHERE IS_ELECTIVE = 1 AND SESSIONS_AVAILABLE > 0)                               AS TU_SESSIONS_PCT,   -- 65.5
  (SELECT ROUND(100 * (1 - SUM(IS_HRG_BLANK) / COUNT(*)), 2) FROM VW_INPATIENT)                      AS HRG_COMPLETE_PCT;  -- 97.67
