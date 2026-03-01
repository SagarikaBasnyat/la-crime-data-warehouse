# LA Crime Data Warehouse – Star Schema Implementation

## Project Overview

This project builds a dimensional star schema data warehouse using the Los Angeles Crime Dataset.  
The goal was to transform raw crime data into a structured analytics-ready model suitable for BI tools such as Power BI and Excel.

The project demonstrates:
- Dimensional modeling (Star Schema)
- Data cleaning & normalization
- Surrogate key generation
- Handling unknown/missing values
- Fact-to-dimension relationships
- Data quality validation
- Index optimization

---

## Architecture

Raw Layer:
- Raw.la_crime_raw

Analytics Layer:
- Analytics.dim_date
- Analytics.dim_area
- Analytics.dim_crime
- Analytics.dim_premis
- Analytics.dim_weapon
- Analytics.dim_status
- Analytics.dim_age_group
- Analytics.fact_crime

The model follows a classic **star schema design**, with `fact_crime` at the center and surrounding dimension tables.

---

## Fact Table

### fact_crime
Primary Key:
- dr_no

Foreign Keys:
- date_key
- area_key
- crime_key
- premis_key
- weapon_key
- status_key
- age_group_key

Additional Measures:
- time_occ
- vict_age
- vict_sex
- vict_descent
- lat
- lon
- crm_cd_1 – crm_cd_4

---

## Dimension Tables

### dim_date
- Date breakdown (year, month, day, day_of_week)

### dim_area
- Area ID, name, reporting district

### dim_crime
- Crime code and standardized description  
- Most common description selected per crime code

### dim_premis
- Premise code and description  
- Deduplicated and standardized

### dim_weapon
- Weapon code and description  
- Deduplicated per code

### dim_status
- Normalized status values (UPPER/TRIM applied)

### dim_age_group
- Custom age buckets:
  - 0–17
  - 18–24
  - 25–34
  - 35–44
  - 45–54
  - 55–64
  - 65+
  - UNKNOWN / NOT PROVIDED

---

## Data Engineering Techniques Used

- `ROW_NUMBER()` window functions to select dominant descriptions per code
- `ON CONFLICT DO NOTHING` for idempotent loads
- Surrogate keys using SERIAL
- Left joins with unknown-member mapping (-1 / 'UNK')
- Age band mapping logic
- Null handling & default dimension members
- Index creation for performance optimization
- Data validation queries for quality assurance

---

## Data Quality Validation

The script includes validation queries to ensure:

- Fact row count matches raw dataset
- No null foreign keys
- Unknown mappings are properly assigned
- Referential integrity maintained

---

## Business Intelligence Integration

The final star schema is designed to integrate directly with:

- Power BI
- Excel Pivot Tables
- Tableau
- Any SQL-based BI platform

The structure enables efficient reporting such as:
- Crime trends over time
- Area-level comparisons
- Weapon usage analysis
- Demographic crime distribution
- Weekend vs weekday behavior

---

## File Structure

- la_crime_star_schema.sql → Full ETL and warehouse creation script
- README.md → Project documentation

---

## Key Learning Outcomes

This project demonstrates:

✔ End-to-end warehouse creation  
✔ Dimensional modeling principles  
✔ Handling messy real-world public datasets  
✔ Preparing data for BI tools  
✔ Writing production-style SQL  

---

## Author

Sagarika Basnyat  
MS in Business Analytics – University of North Texas  
