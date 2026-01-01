-- ================================
-- USE DWH schema
-- ================================
USE dwh;  
-- Set the active database schema to 'dwh' which represents the data warehouse layer

-- ================================
-- Compare row counts between Stage and DWH layers
-- ================================
-- This section compares the number of records in each dimension and fact table 
-- between the staging layer and the DWH layer. It helps detect missing or extra records.

SELECT
    'dim_patients' AS table_name,  -- Name of the dimension table
    (SELECT COUNT(*) FROM stage_area.dim_patients) AS stage_count,  -- Number of records in staging
    (SELECT COUNT(*) FROM dwh.dim_patients) AS dwh_count,           -- Number of records in DWH
    ( (SELECT COUNT(*) FROM stage_area.dim_patients) - (SELECT COUNT(*) FROM dwh.dim_patients) ) AS diff_rows  -- Difference between them

UNION ALL
SELECT
    'dim_admissions', 
    (SELECT COUNT(*) FROM stage_area.dim_admissions), 
    (SELECT COUNT(*) FROM dwh.dim_admissions), 
    ( (SELECT COUNT(*) FROM stage_area.dim_admissions) - (SELECT COUNT(*) FROM dwh.dim_admissions) )

UNION ALL
SELECT
    'dim_concepts',
    (SELECT COUNT(*) FROM stage_area.dim_concepts),
    (SELECT COUNT(*) FROM dwh.dim_concepts),
    ( (SELECT COUNT(*) FROM stage_area.dim_concepts) - (SELECT COUNT(*) FROM dwh.dim_concepts) )

UNION ALL
SELECT
    'dim_date',
    (SELECT COUNT(*) FROM stage_area.dim_date),
    (SELECT COUNT(*) FROM dwh.dim_date),
    ( (SELECT COUNT(*) FROM stage_area.dim_date) - (SELECT COUNT(*) FROM dwh.dim_date) )

UNION ALL
SELECT
    'dim_provider',
    (SELECT COUNT(*) FROM stage_area.dim_provider),
    (SELECT COUNT(*) FROM dwh.dim_provider),
    ( (SELECT COUNT(*) FROM stage_area.dim_provider) - (SELECT COUNT(*) FROM dwh.dim_provider) )

UNION ALL
SELECT
    'dim_junk_disorder_event',
    (SELECT COUNT(*) FROM stage_area.dim_junk_disorder_event),
    (SELECT COUNT(*) FROM dwh.dim_junk_disorder_event),
    ( (SELECT COUNT(*) FROM stage_area.dim_junk_disorder_event) - (SELECT COUNT(*) FROM dwh.dim_junk_disorder_event) )

UNION ALL
SELECT
    'fact_disorder_events',
    (SELECT COUNT(*) FROM stage_area.fact_disorder_events),
    (SELECT COUNT(*) FROM dwh.fact_disorder_events),
    ( (SELECT COUNT(*) FROM stage_area.fact_disorder_events) - (SELECT COUNT(*) FROM dwh.fact_disorder_events) );

-- ================================
-- Total consistency checks between facts and aggregation
-- ================================
-- This checks if the total number of events in the fact table
-- matches the sum of events in the aggregated summary table (per admission)

SELECT
    'Fact vs Agg Total' AS check_name,  -- Label for the check
    (SELECT COUNT(*) FROM dwh.fact_disorder_events) AS fact_total_events,  -- Total raw events
    (SELECT SUM(total_events) FROM dwh.agg_disorders_per_admission) AS agg_total_events,  -- Sum of aggregated events
    ( (SELECT COUNT(*) FROM dwh.fact_disorder_events) - (SELECT SUM(total_events) FROM dwh.agg_disorders_per_admission) ) AS diff_events;  -- Difference (should be 0)

-- ================================
-- Orphan checks
-- ================================
-- These queries look for records in the fact table that reference non-existing dimension records.
-- If any of these return results, there's a referential integrity issue.

SELECT
    'Orphan patients' AS issue,  -- Fact rows without matching patient_id in dim_patients
    COUNT(*) AS num_records
FROM dwh.fact_disorder_events f
LEFT JOIN dwh.dim_patients p USING(patient_id)
WHERE p.patient_id IS NULL

UNION ALL
SELECT
    'Orphan admissions',  -- Fact rows without admission_id match
    COUNT(*) 
FROM dwh.fact_disorder_events f
LEFT JOIN dwh.dim_admissions a USING(admission_id)
WHERE a.admission_id IS NULL

UNION ALL
SELECT
    'Orphan concepts',  -- Fact rows without clinical_concept_id match
    COUNT(*) 
FROM dwh.fact_disorder_events f
LEFT JOIN dwh.dim_concepts c USING(clinical_concept_id)
WHERE c.clinical_concept_id IS NULL

UNION ALL
SELECT
    'Orphan dates',  -- Fact rows without corresponding datetime in dim_date
    COUNT(*) 
FROM dwh.fact_disorder_events f
LEFT JOIN dwh.dim_date d USING(event_datetime)
WHERE d.event_datetime IS NULL

UNION ALL
SELECT
    'Orphan junk_id',  -- Fact rows with missing junk dimension match
    COUNT(*) 
FROM dwh.fact_disorder_events f
LEFT JOIN dwh.dim_junk_disorder_event j USING(junk_id)
WHERE j.junk_id IS NULL;

-- ================================
-- Duplicate checks in Dimensions
-- ================================
-- These queries detect duplicate primary keys in dimension tables.
-- Each dimension key (e.g., patient_id, admission_id) should be unique.

SELECT
    'Duplicate patients' AS issue,
    COUNT(*) AS num_dupes
FROM (
    SELECT patient_id
    FROM dwh.dim_patients
    GROUP BY patient_id
    HAVING COUNT(*) > 1  -- More than one record with the same patient_id
) sub

UNION ALL
SELECT
    'Duplicate admissions',
    COUNT(*) 
FROM (
    SELECT admission_id
    FROM dwh.dim_admissions
    GROUP BY admission_id
    HAVING COUNT(*) > 1
) sub

UNION ALL
SELECT
    'Duplicate concepts',
    COUNT(*) 
FROM (
    SELECT clinical_concept_id
    FROM dwh.dim_concepts
    GROUP BY clinical_concept_id
    HAVING COUNT(*) > 1
) sub

UNION ALL
SELECT
    'Duplicate dates',
    COUNT(*) 
FROM (
    SELECT event_datetime
    FROM dwh.dim_date
    GROUP BY event_datetime
    HAVING COUNT(*) > 1
) sub

UNION ALL
SELECT
    'Duplicate junk',
    COUNT(*) 
FROM (
    SELECT junk_id
    FROM dwh.dim_junk_disorder_event
    GROUP BY junk_id
    HAVING COUNT(*) > 1
) sub;
