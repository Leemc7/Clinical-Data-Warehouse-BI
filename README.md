# 🏥 Clinical Data Warehouse & BI System  
**Dimensional Data Warehouse and Business Intelligence Project (MIMIC-IV)**
---

## 📦 Project Description

This project implements a **clinical Data Warehouse (DWH)** designed to support  
**Business Intelligence (BI)** and advanced analytics for the study of  
**acid–base and electrolyte disorders** in hospitalized ICU patients.

The system integrates heterogeneous clinical data from the **MIMIC-IV database**  
into a **Kimball-style dimensional model**, enabling reliable analytical queries,  
dashboards, and a scalable foundation for future machine learning applications.

---

## 🎯 Project Goals

- 🏗️ Design and implement a **clinical Data Warehouse**
- 🔄 Integrate multiple clinical data sources into a unified analytical schema
- 📊 Enable BI reporting, KPIs, and exploratory clinical analysis
- 🧹 Ensure high **data quality, consistency, and referential integrity**
- 🚀 Create a scalable data layer for advanced analytics and ML

---

## 🗂️ Data Sources

The project is based on the **MIMIC-IV** clinical database and includes:

- Patients  
- Admissions  
- Transfers (ICU and care units)  
- Laboratory events (labevents, d_labitems)  
- Diagnoses (ICD codes)  
- OMR (bedside measurements)

---

## 🏛️ Data Architecture

The solution follows a **multi-layer architecture**:

1. **Source Layer**  
   Raw clinical data extracted from MIMIC-IV

2. **Staging Area (area_stage)**  
   - Landing zone for raw data  
   - Data cleansing and normalization  
   - Type conversion and missing value handling  
   - Preparation for dimensional modeling  

3. **Data Warehouse (DWH)**  
   - Dimensional (Star Schema) design  
   - Fact and Dimension tables  
   - Optimized for analytical workloads  

---

## 🧱 Dimensional Model (Kimball)

### 🔹 Grain
- **Hospital admission level**
- Each fact record represents a clinical event within a specific admission

### 🔹 Fact Table
- **fact_disorder_events**
  - Unified clinical events from labs, diagnoses, and OMR
  - Supports longitudinal and cross-sectional analysis

### 🔹 Dimension Tables
- **dim_patients** – demographic information  
- **dim_admissions** – admission-level attributes  
- **dim_provider** – ICU/unit transfers  
- **dim_concepts** – unified clinical concepts  
- **dim_date** – time dimension with derived attributes  
- **dim_junk_disorder_event** – compact metadata dimension  
  (event source, measurement unit, care unit)

---

## 🔄 ETL / ELT Process

- SQL-based transformations using **MariaDB** and **DBeaver**
- Data cleansing and standardization:
  - Handling missing or invalid timestamps
  - Normalizing clinical concept identifiers
  - Converting textual values to numeric measurements
- Referential integrity enforcement
- Automatic completion of the date dimension
- Clear separation between staging and final DWH layers

---

## 📊 Data Aggregation

To improve analytical performance, an aggregation table was created:

- **admission_per_disorders_agg**
  - Aggregates clinical events per admission
  - Pre-calculated metrics:
    - Total number of clinical events
    - Number of unique clinical concepts
    - Number of data sources per admission

This table enables fast BI queries and dashboarding.

---

## ✅ Data Quality Assurance

Quality checks implemented across the pipeline include:

- Row count validation between staging and DWH
- Orphan record detection and cleanup
- Duplicate detection in dimension tables
- Referential integrity validation (foreign keys)
- Consistency checks between fact and aggregation tables

---

## 📈 Business Intelligence Use Cases

The Data Warehouse enables:

- Epidemiological analysis of acid–base and electrolyte disorders  
- Identification of clinical risk factors  
- Monitoring disorder progression during hospitalization  
- Outcome analysis (length of stay, ICU utilization, mortality)  
- BI dashboards and KPI reporting  
- Foundation for future **machine learning and predictive analytics**

---

## 🛠 Technologies Used

- **Databases & DWH**: MariaDB, Snowflake  
- **ETL & SQL**: SQL, DBeaver  
- **BI & Visualization**: Power BI, Excel  
- **Data Modeling**: Kimball dimensional modeling  
- **Source Data**: MIMIC-IV  

---

## 🚀 Future Enhancements

- Integration of additional clinical variables  
  (vital signs, fluid balance, renal function)
- Advanced missing-data imputation and anomaly detection
- Machine learning models for early risk prediction
- Integration with real-time clinical decision support systems

---

## 👤 Author

Developed by: **Leemc7**
