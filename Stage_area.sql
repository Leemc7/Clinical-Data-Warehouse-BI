-- ============================================
-- Create database for staging area
-- ============================================
DROP DATABASE IF EXISTS stage_area;  -- Drop the existing staging area database if it exists to start fresh
CREATE DATABASE stage_area;          -- Create a new database named 'stage_area' to serve as staging layer
USE stage_area;                      -- Set the active schema to 'stage_area'

-- ============================================
-- Drop existing tables if they exist (cleanup)
-- ============================================
-- These DROP statements clean up any previous tables before recreating them
DROP TABLE IF EXISTS stage_area.fact_disorder_events;       -- Fact table for clinical disorder-related events
DROP TABLE IF EXISTS stage_area.omr_filtered;               -- Temporary table for filtered OMR measurements
DROP TABLE IF EXISTS stage_area.dim_date;                   -- Dimension table for calendar attributes
DROP TABLE IF EXISTS stage_area.dim_concepts;               -- Clinical concepts: labs and diagnoses
DROP TABLE IF EXISTS stage_area.dim_provider;               -- Care unit movement (transfers) and timings
DROP TABLE IF EXISTS stage_area.dim_admissions;             -- Hospital admission details
DROP TABLE IF EXISTS stage_area.dim_patients;               -- Basic patient demographics
DROP TABLE IF EXISTS stage_area.dim_junk_disorder_event;    -- Junk dimension: source type, unit, careunit

-- ============================================
-- Dimension Table: dim_patients
-- ============================================
-- Load basic patient information: ID, gender, and date of death
CREATE TABLE stage_area.dim_patients AS
SELECT
  subject_id AS patient_id,   -- Primary identifier for patients
  gender,                     -- Gender: M or F
  dod                        -- Date of death, if applicable
FROM mimic4.patients;

-- ============================================
-- Dimension Table: dim_admissions
-- ============================================
-- Load admission data, replace nulls with default boundary values
CREATE TABLE stage_area.dim_admissions AS
SELECT
  subject_id AS patient_id,   -- Patient foreign key
  hadm_id AS admission_id,    -- Unique admission ID
  admission_type,             -- Type of admission (e.g., elective, emergency)
  CASE
    WHEN admittime IS NULL OR TRIM(admittime) = '' THEN '1900-01-01 00:00:00'
    ELSE CAST(admittime AS DATETIME)
  END AS admittime,           -- Standardized admission time
  CASE
    WHEN dischtime IS NULL OR TRIM(dischtime) = '' THEN '2999-12-31 23:59:59'
    ELSE CAST(dischtime AS DATETIME)
  END AS dischtime,           -- Standardized discharge time
  insurance                   -- Insurance plan associated with the admission
FROM mimic4.admissions;

-- ============================================
-- Dimension Table: dim_provider
-- ============================================
-- Create a surrogate key for provider records based on unit stay periods
CREATE TABLE stage_area.dim_provider AS
SELECT
  ROW_NUMBER() OVER () AS provider_id, -- Auto-generated surrogate key
  subject_id AS patient_id,            -- Foreign key to patient
  hadm_id AS admission_id,             -- Foreign key to admission
  careunit AS careunit_id,             -- Unit where the patient was treated
  CASE
    WHEN intime IS NULL OR TRIM(intime) = '' THEN '1900-01-01 00:00:00'
    ELSE CAST(intime AS DATETIME)
  END AS intime,                       -- Time patient entered the unit
  CASE
    WHEN outtime IS NULL OR TRIM(outtime) = '' THEN '2999-12-31 23:59:59'
    ELSE CAST(outtime AS DATETIME)
  END AS outtime                       -- Time patient left the unit
FROM mimic4.transfers;

-- ============================================
-- Dimension Table: dim_concepts
-- ============================================
-- Create clinical concept dimension: includes labs and diagnoses
CREATE TABLE stage_area.dim_concepts (
  clinical_concept_id INT AUTO_INCREMENT PRIMARY KEY, -- Unique identifier for each concept
  concept_type VARCHAR(200),      -- Type: 'Lab' or 'Diagnosis'
  concept_name VARCHAR(2500),     -- Human-readable name
  code VARCHAR(200),              -- Source system code (itemid or ICD)
  description TEXT                -- Full explanation or label
);

-- Insert relevant lab concepts from d_labitems
INSERT INTO stage_area.dim_concepts (concept_type, concept_name, code, description)
SELECT 
  'Lab',
  label,
  CAST(itemid AS CHAR),
  label
FROM mimic4.d_labitems
WHERE LOWER(label) LIKE '%sodium%' OR LOWER(label) LIKE '%potassium%' 
   OR LOWER(label) LIKE '%bicarbonate%' OR LOWER(label) LIKE '%chloride%' 
   OR LOWER(label) LIKE '%ph%' OR LOWER(label) LIKE '%base excess%' 
   OR LOWER(label) LIKE '%anion gap%';   -- Focus on electrolyte-related labs

-- Insert diagnosis concepts from ICD mapping table
INSERT INTO stage_area.dim_concepts (concept_type, concept_name, code, description)
SELECT 
  'Diagnosis',
  long_title,
  icd_code,
  long_title
FROM mimic4.d_icd_diagnoses
WHERE LOWER(long_title) LIKE '%hypo%' OR LOWER(long_title) LIKE '%hyper%' 
   OR LOWER(long_title) LIKE '%acidosis%' OR LOWER(long_title) LIKE '%alkalosis%' 
   OR LOWER(long_title) LIKE '%electrolyte%' OR LOWER(long_title) LIKE '%sodium%' 
   OR LOWER(long_title) LIKE '%potassium%' OR LOWER(long_title) LIKE '%bicarbonate%' 
   OR LOWER(long_title) LIKE '%ph%';  -- Match electrolyte-related diagnosis terms

-- Insert fallback record to handle unknown concepts
INSERT INTO stage_area.dim_concepts (concept_type, concept_name, code, description)
VALUES ('Unknown', 'Unknown concept', 'UNKNOWN', 'No matching concept found'); -- For unmatched cases

-- ============================================
-- Dimension Table: dim_date
-- ============================================
-- Calendar dimension based on event timestamps
CREATE TABLE stage_area.dim_date (
  event_datetime DATETIME PRIMARY KEY, -- Exact timestamp of event
  month INT,                           -- Month number (1–12)
  year INT,                            -- Year (e.g., 2025)
  day_of_week INT,                     -- Day of week (1=Monday)
  day_name VARCHAR(10),                -- Day name (e.g., Monday)
  month_name VARCHAR(10),              -- Month name (e.g., January)
  is_weekend BOOLEAN                   -- TRUE if event occurred on weekend
);

-- ============================================
-- OMR Table: omr_filtered
-- ============================================
-- Filter relevant OMR records with electrolyte-related results
CREATE TABLE stage_area.omr_filtered AS
SELECT *
FROM mimic4.omr
WHERE LOWER(result_name) LIKE '%sodium%' OR LOWER(result_name) LIKE '%potassium%'
   OR LOWER(result_name) LIKE '%bicarbonate%' OR LOWER(result_name) LIKE '%chloride%'
   OR LOWER(result_name) LIKE '%anion gap%' OR LOWER(result_name) LIKE '%ph%';

-- Add numeric field for parsing result_value safely
ALTER TABLE stage_area.omr_filtered
ADD COLUMN result_value_numeric FLOAT;

-- Populate the numeric field where values are valid floats
UPDATE stage_area.omr_filtered
SET result_value_numeric = CAST(result_value AS DECIMAL(10,2))
WHERE result_value REGEXP '^[0-9]+(\.[0-9]+)?$';

-- ============================================
-- Fact Table: fact_disorder_events
-- ============================================
-- Central fact table: stores clinical events across sources (lab, diagnosis, omr)
CREATE TABLE stage_area.fact_disorder_events (
  disorder_event_id INT AUTO_INCREMENT PRIMARY KEY,  -- Unique event ID
  patient_id INT NOT NULL,                           -- FK to dim_patients
  admission_id INT,                                  -- FK to dim_admissions
  event_datetime DATETIME,                           -- Event timestamp
  careunit_id VARCHAR(50),                           -- Care unit
  clinical_concept_id INT,                           -- FK to dim_concepts
  measurement_value VARCHAR(100),                    -- Raw measurement value
  measurement_unit VARCHAR(20),                      -- Measurement unit (if available)
  event_source_type VARCHAR(20),                     -- Source: lab, omr, diagnosis
  event_date DATETIME,                               -- Date portion of event
  junk_id INT,                                       -- FK to dim_junk_disorder_event
  provider_id INT                                    -- FK to dim_provider
);

-- Insert laboratory events from labevents table
INSERT INTO stage_area.fact_disorder_events
(patient_id, admission_id, event_datetime, clinical_concept_id, measurement_value, measurement_unit, event_source_type, event_date)
SELECT 
  le.subject_id,
  le.hadm_id,
  le.charttime,
  dc.clinical_concept_id,
  le.valuenum,
  le.valueuom,
  'lab',
  le.charttime
FROM mimic4.labevents le
LEFT JOIN stage_area.dim_concepts dc 
  ON CAST(le.itemid AS CHAR) = dc.code AND dc.concept_type = 'Lab'
WHERE le.subject_id IS NOT NULL
  AND le.hadm_id IS NOT NULL
  AND le.charttime IS NOT NULL;

-- Insert diagnosis events using ICD codes
INSERT INTO stage_area.fact_disorder_events
(patient_id, admission_id, event_datetime, clinical_concept_id, measurement_value, measurement_unit, event_source_type, event_date)
SELECT 
  d.subject_id,
  d.hadm_id,
  COALESCE(a.admittime, '1900-01-01 00:00:00'),
  dc.clinical_concept_id,
  NULL,
  NULL,
  'diagnosis',
  NULL
FROM mimic4.diagnoses_icd d
LEFT JOIN stage_area.dim_admissions a ON d.hadm_id = a.admission_id
LEFT JOIN stage_area.dim_concepts dc 
  ON d.icd_code = dc.code AND dc.concept_type = 'Diagnosis'
WHERE d.subject_id IS NOT NULL
  AND d.hadm_id IS NOT NULL;

-- Insert OMR events (unstructured lab results)
INSERT INTO stage_area.fact_disorder_events
(patient_id, admission_id, event_datetime, clinical_concept_id, measurement_value, measurement_unit, event_source_type, event_date)
SELECT 
  o.subject_id,
  NULL,
  o.chartdate,
  dc.clinical_concept_id,
  o.result_value_numeric,
  NULL,
  'omr',
  o.chartdate
FROM stage_area.omr_filtered o
LEFT JOIN stage_area.dim_concepts dc 
  ON TRIM(LOWER(o.result_name)) = TRIM(LOWER(dc.concept_name)) AND dc.concept_type = 'Lab'
WHERE o.subject_id IS NOT NULL
  AND o.chartdate IS NOT NULL;

-- Fill missing concept IDs with default 'Unknown' concept
UPDATE stage_area.fact_disorder_events
SET clinical_concept_id = (
  SELECT clinical_concept_id FROM stage_area.dim_concepts
  WHERE concept_name = 'Unknown concept'
  LIMIT 1
)
WHERE clinical_concept_id IS NULL;

-- ============================================
-- Add careunit_id from transfers
-- ============================================
-- Backfill careunit_id into fact table using time-based join
UPDATE stage_area.fact_disorder_events f
LEFT JOIN (
  SELECT subject_id, hadm_id, careunit, intime, outtime
  FROM mimic4.transfers
) t
  ON f.patient_id = t.subject_id
  AND f.admission_id = t.hadm_id
  AND f.event_datetime BETWEEN t.intime AND t.outtime
SET f.careunit_id = t.careunit;

-- ============================================
-- Link provider_id from dim_provider
-- ============================================
-- Join fact table to dim_provider using time-window logic
UPDATE stage_area.fact_disorder_events f
JOIN stage_area.dim_provider s
  ON f.patient_id = s.patient_id
  AND f.admission_id = s.admission_id
  AND f.event_datetime BETWEEN s.intime AND s.outtime
SET f.provider_id = s.provider_id;

-- ============================================
-- Create Junk Dimension
-- ============================================
-- Create a dimension for unstructured fields: source, unit, careunit
CREATE TABLE stage_area.dim_junk_disorder_event (
  junk_id INT AUTO_INCREMENT PRIMARY KEY,
  event_source_type VARCHAR(20),     -- Source system: lab, omr, diagnosis
  measurement_unit VARCHAR(20),      -- Measurement unit
  careunit_id VARCHAR(50)            -- Care unit where event occurred
);

-- Populate Junk Dimension with unique combinations
INSERT INTO stage_area.dim_junk_disorder_event (event_source_type, measurement_unit, careunit_id)
SELECT DISTINCT
  event_source_type,
  measurement_unit,
  careunit_id
FROM stage_area.fact_disorder_events;

-- Link junk_id to fact table using matching rules
UPDATE stage_area.fact_disorder_events f
JOIN stage_area.dim_junk_disorder_event j
  ON f.event_source_type = j.event_source_type
  AND ((f.measurement_unit IS NULL AND j.measurement_unit IS NULL) OR f.measurement_unit = j.measurement_unit)
  AND ((f.careunit_id IS NULL AND j.careunit_id IS NULL) OR f.careunit_id = j.careunit_id)
SET f.junk_id = j.junk_id;

-- ============================================
-- Fill dim_date from fact table event timestamps
-- ============================================
-- Enrich dim_date with unique event_datetime values from fact table
INSERT INTO stage_area.dim_date (event_datetime, month, year, day_of_week, day_name, month_name, is_weekend)
SELECT DISTINCT
    f.event_datetime,
    MONTH(f.event_datetime),
    YEAR(f.event_datetime),
    WEEKDAY(f.event_datetime) + 1, -- Convert 0-based weekday to 1-based
    DAYNAME(f.event_datetime),
    MONTHNAME(f.event_datetime),
    DAYOFWEEK(f.event_datetime) IN (1, 7) -- 1=Sunday, 7=Saturday
FROM stage_area.fact_disorder_events f
LEFT JOIN stage_area.dim_date d ON f.event_datetime = d.event_datetime
WHERE d.event_datetime IS NULL
  AND f.event_datetime IS NOT NULL;
