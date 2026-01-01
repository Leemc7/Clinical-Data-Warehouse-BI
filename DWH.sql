-- ================================
-- Create DWH database
-- ================================
DROP DATABASE IF EXISTS dwh; -- Remove existing DWH database if it exists to start clean
CREATE DATABASE dwh;         -- Create new DWH database
USE dwh;                     -- Switch context to the new DWH database

-- ================================
-- Drop dimension tables if they exist
-- ================================
DROP TABLE IF EXISTS dwh.dim_date;                -- Drop date dimension table
DROP TABLE IF EXISTS dwh.dim_concepts;            -- Drop concepts dimension table
DROP TABLE IF EXISTS dwh.dim_provider;            -- Drop provider dimension table
DROP TABLE IF EXISTS dwh.dim_admissions;          -- Drop admissions dimension table
DROP TABLE IF EXISTS dwh.dim_patients;            -- Drop patients dimension table
DROP TABLE IF EXISTS dwh.dim_junk_disorder_event; -- Drop junk dimension table

-- ================================
-- Create and populate dimension tables
-- ================================

-- Patient dimension: basic demographic data
CREATE TABLE dwh.dim_patients (
  patient_id INT PRIMARY KEY,    -- Unique identifier for patient
  gender VARCHAR(10),            -- Gender (e.g., Male/Female)
  dod DATE                       -- Date of death (if applicable)
);
INSERT INTO dwh.dim_patients
SELECT DISTINCT patient_id, gender, dod
FROM stage_area.dim_patients;

-- Admission dimension: hospitalization details
CREATE TABLE dwh.dim_admissions (
  admission_id INT PRIMARY KEY,      -- Unique admission ID
  patient_id INT,                    -- Foreign key to patient
  admission_type VARCHAR(50),        -- Type of admission (e.g., EMERGENCY)
  admittime DATETIME,                -- Admission datetime
  dischtime DATETIME,                -- Discharge datetime
  insurance VARCHAR(50)              -- Insurance provider
);
INSERT INTO dwh.dim_admissions (admission_id, patient_id, admission_type, admittime, dischtime, insurance)
SELECT DISTINCT admission_id, patient_id, admission_type, admittime, dischtime, insurance
FROM stage_area.dim_admissions;

-- Provider dimension: care units and time frames
CREATE TABLE dwh.dim_provider (
  provider_id INT PRIMARY KEY,       -- Unique provider ID
  patient_id INT,                    -- Foreign key to patient
  admission_id INT,                  -- Foreign key to admission
  careunit_id VARCHAR(50),           -- Unit providing care
  intime DATETIME,                   -- Time patient entered the unit
  outtime DATETIME                   -- Time patient left the unit
);
INSERT INTO dwh.dim_provider (provider_id, patient_id, admission_id, careunit_id, intime, outtime)
SELECT DISTINCT provider_id, patient_id, admission_id, careunit_id, intime, outtime
FROM stage_area.dim_provider;

-- Clinical concepts dimension: medical terms and codes
CREATE TABLE dwh.dim_concepts (
  clinical_concept_id INT PRIMARY KEY,   -- Unique clinical concept ID
  concept_type VARCHAR(200),             -- Type of concept (e.g., lab, symptom)
  concept_name VARCHAR(2500),            -- Human-readable name
  code VARCHAR(200),                     -- Coding system value (e.g., LOINC, ICD)
  description TEXT                       -- Additional explanation of concept
);
INSERT INTO dwh.dim_concepts
SELECT DISTINCT clinical_concept_id, concept_type, concept_name, code, description
FROM stage_area.dim_concepts;

-- Date dimension: enriched time attributes
CREATE TABLE dwh.dim_date (
  event_datetime DATETIME NOT NULL PRIMARY KEY, -- Exact datetime of the event
  month INT,                                    -- Month number (1–12)
  year INT,                                     -- Year of the event
  day_of_week INT,                              -- Numeric weekday (1=Monday)
  day_name VARCHAR(10),                         -- Name of the day (e.g., Monday)
  month_name VARCHAR(10),                       -- Month name (e.g., January)
  is_weekend BOOLEAN                            -- Boolean flag for weekend
);
INSERT INTO dwh.dim_date
SELECT DISTINCT event_datetime, month, year, day_of_week, day_name, month_name, is_weekend
FROM stage_area.dim_date;

-- Junk dimension: miscellaneous categorical flags or units
CREATE TABLE dwh.dim_junk_disorder_event (
  junk_id INT PRIMARY KEY,                 -- Surrogate key
  event_source_type VARCHAR(20),          -- Source type (e.g., system, manual)
  measurement_unit VARCHAR(20),           -- Unit of measurement (e.g., mg/dL)
  careunit_id VARCHAR(50)                 -- Related care unit
);
INSERT INTO dwh.dim_junk_disorder_event
SELECT DISTINCT junk_id, event_source_type, measurement_unit, careunit_id
FROM stage_area.dim_junk_disorder_event;

-- ================================
-- Fact Table: disorder events
-- ================================
CREATE TABLE dwh.fact_disorder_events (
  disorder_event_id INT AUTO_INCREMENT PRIMARY KEY, -- Unique event identifier
  patient_id INT NOT NULL,                          -- Foreign key to patient
  admission_id INT,                                 -- Foreign key to admission
  event_datetime DATETIME,                          -- Timestamp of the event
  careunit_id VARCHAR(50),                          -- Care unit where event occurred
  clinical_concept_id INT,                          -- Foreign key to clinical concept
  measurement_value VARCHAR(100),                   -- Recorded value (e.g., 7.2)
  measurement_unit VARCHAR(20),                     -- Unit (e.g., mmol/L)
  event_source_type VARCHAR(20),                    -- Event origin (e.g., system)
  junk_id INT,                                      -- Foreign key to junk dimension
  provider_id INT                                   -- Foreign key to provider
);
INSERT INTO dwh.fact_disorder_events (
  patient_id, admission_id, event_datetime, careunit_id, clinical_concept_id, 
  measurement_value, measurement_unit, event_source_type, junk_id, provider_id
)
SELECT DISTINCT 
  patient_id, admission_id, event_datetime, careunit_id, clinical_concept_id,
  measurement_value, measurement_unit, event_source_type, junk_id, provider_id
FROM stage_area.fact_disorder_events;

-- ================================
-- Final Fixes: complete date & concept data
-- ================================
-- Ensure all event datetimes in fact table are represented in dim_date
INSERT INTO dwh.dim_date (event_datetime, month, year, day_of_week, day_name, month_name, is_weekend)
SELECT DISTINCT
    f.event_datetime,
    MONTH(f.event_datetime),
    YEAR(f.event_datetime),
    WEEKDAY(f.event_datetime) + 1,
    DAYNAME(f.event_datetime),
    MONTHNAME(f.event_datetime),
    DAYOFWEEK(f.event_datetime) IN (1, 7)
FROM dwh.fact_disorder_events f
LEFT JOIN dwh.dim_date d ON f.event_datetime = d.event_datetime
WHERE f.event_datetime IS NOT NULL AND d.event_datetime IS NULL;

-- Insert 'Unknown concept' if it appears in staging but not in DWH
INSERT INTO dwh.dim_concepts (clinical_concept_id, concept_type, concept_name, code, description)
SELECT clinical_concept_id, concept_type, concept_name, code, description
FROM stage_area.dim_concepts
WHERE concept_name = 'Unknown concept'
  AND NOT EXISTS (
    SELECT 1 FROM dwh.dim_concepts WHERE concept_name = 'Unknown concept'
  );

-- ================================
-- Cleanup: remove orphan records from fact table
-- ================================
-- Delete events with patient_id not in dim_patients
DELETE f FROM dwh.fact_disorder_events f
LEFT JOIN dwh.dim_patients p ON f.patient_id = p.patient_id
WHERE p.patient_id IS NULL;

-- Delete events with admission_id not found in dim_admissions
DELETE f FROM dwh.fact_disorder_events f
LEFT JOIN dwh.dim_admissions a ON f.admission_id = a.admission_id
WHERE f.admission_id IS NOT NULL AND a.admission_id IS NULL;

-- Delete events with unknown clinical_concept_id
DELETE f FROM dwh.fact_disorder_events f
LEFT JOIN dwh.dim_concepts c ON f.clinical_concept_id = c.clinical_concept_id
WHERE f.clinical_concept_id IS NOT NULL AND c.clinical_concept_id IS NULL;

-- Delete events with unknown event_datetime
DELETE f FROM dwh.fact_disorder_events f
LEFT JOIN dwh.dim_date d ON f.event_datetime = d.event_datetime
WHERE f.event_datetime IS NOT NULL AND d.event_datetime IS NULL;

-- Delete events with missing junk_id
DELETE f FROM dwh.fact_disorder_events f
LEFT JOIN dwh.dim_junk_disorder_event j ON f.junk_id = j.junk_id
WHERE f.junk_id IS NOT NULL AND j.junk_id IS NULL;

-- Delete events with missing provider_id
DELETE f FROM dwh.fact_disorder_events f
LEFT JOIN dwh.dim_provider s ON f.provider_id = s.provider_id
WHERE f.provider_id IS NOT NULL AND s.provider_id IS NULL;

-- ================================
-- Foreign Keys: ensure referential integrity
-- ================================
ALTER TABLE dwh.fact_disorder_events
  ADD CONSTRAINT fk_patient FOREIGN KEY (patient_id) REFERENCES dwh.dim_patients(patient_id),
  ADD CONSTRAINT fk_admission FOREIGN KEY (admission_id) REFERENCES dwh.dim_admissions(admission_id),
  ADD CONSTRAINT fk_concept FOREIGN KEY (clinical_concept_id) REFERENCES dwh.dim_concepts(clinical_concept_id),
  ADD CONSTRAINT fk_date FOREIGN KEY (event_datetime) REFERENCES dwh.dim_date(event_datetime),
  ADD CONSTRAINT fk_junk FOREIGN KEY (junk_id) REFERENCES dwh.dim_junk_disorder_event(junk_id),
  ADD CONSTRAINT fk_provider FOREIGN KEY (provider_id) REFERENCES dwh.dim_provider(provider_id);

-- ================================
-- Indexes: optimize query performance
-- ================================
CREATE INDEX idx_fact_patient ON dwh.fact_disorder_events(patient_id);            -- Fast filter by patient
CREATE INDEX idx_fact_admission ON dwh.fact_disorder_events(admission_id);        -- Fast filter by admission
CREATE INDEX idx_fact_concept ON dwh.fact_disorder_events(clinical_concept_id);   -- Fast filter by concept
CREATE INDEX idx_fact_eventtime ON dwh.fact_disorder_events(event_datetime);      -- Fast time-based filtering
CREATE INDEX idx_fact_junk ON dwh.fact_disorder_events(junk_id);                  -- Fast filtering by junk data
CREATE INDEX idx_fact_provider ON dwh.fact_disorder_events(provider_id);          -- Fast filter by provider

-- ================================
-- Aggregation Table: summary of disorder events per admission
-- ================================
CREATE TABLE dwh.agg_disorders_per_admission AS
SELECT 
  admission_id,                                 -- Grouped by admission
  COUNT(*) AS total_events,                     -- Total number of disorder events
  COUNT(DISTINCT clinical_concept_id) AS unique_concepts,    -- Unique clinical concepts per admission
  COUNT(DISTINCT event_source_type) AS different_sources     -- Count of different data sources
FROM dwh.fact_disorder_events
GROUP BY admission_id;

-- ================================
-- Final check: list all tables created in the DWH
-- ================================
SHOW TABLES; -- Display all tables in the current database
