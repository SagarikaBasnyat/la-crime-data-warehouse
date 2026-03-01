-- ============================================================
-- Portfolio-Style Star Schema
-- ============================================================
-- Builds a PostgreSQL star schema from Raw.la_crime_raw and loads dimensions + fact.
-- Includes UNKNOWN members to prevent NULL foreign keys.

CREATE SCHEMA IF NOT EXISTS "Analytics";

-- -------------------------
-- 0) DROP OLD TABLES
-- -------------------------
DROP TABLE IF EXISTS "Analytics".fact_crime CASCADE;

DROP TABLE IF EXISTS "Analytics".dim_date CASCADE;
DROP TABLE IF EXISTS "Analytics".dim_area CASCADE;
DROP TABLE IF EXISTS "Analytics".dim_crime CASCADE;
DROP TABLE IF EXISTS "Analytics".dim_premis CASCADE;
DROP TABLE IF EXISTS "Analytics".dim_weapon CASCADE;
DROP TABLE IF EXISTS "Analytics".dim_status CASCADE;
DROP TABLE IF EXISTS "Analytics".dim_age_group CASCADE;

-- -------------------------
-- 1) CREATE DIMENSIONS
-- -------------------------

-- Date dimension
CREATE TABLE "Analytics".dim_date (
  date_key SERIAL PRIMARY KEY,
  date_occ DATE UNIQUE,
  year INT,
  month INT,
  day INT,
  day_of_week INT
);

-- Area dimension (keeping composite unique for safety)
CREATE TABLE "Analytics".dim_area (
  area_key SERIAL PRIMARY KEY,
  area INT,
  area_name TEXT,
  rpt_dist_no INT,
  UNIQUE (area, area_name, rpt_dist_no)
);

-- Crime dimension (v2: unique by code only)
CREATE TABLE "Analytics".dim_crime (
  crime_key SERIAL PRIMARY KEY,
  crm_cd INT UNIQUE,
  crm_cd_desc TEXT
);

-- Premise dimension (v2: unique by code only)
CREATE TABLE "Analytics".dim_premis (
  premis_key SERIAL PRIMARY KEY,
  premis_cd INT UNIQUE,
  premis_desc TEXT
);

-- Weapon dimension (v2: unique by code only)
CREATE TABLE "Analytics".dim_weapon (
  weapon_key SERIAL PRIMARY KEY,
  weapon_used_cd INT UNIQUE,
  weapon_desc TEXT
);

-- Status dimension (v2: unique by status only)
CREATE TABLE "Analytics".dim_status (
  status_key SERIAL PRIMARY KEY,
  status TEXT UNIQUE,
  status_desc TEXT
);

-- Age group dimension
CREATE TABLE "Analytics".dim_age_group (
  age_group_key SERIAL PRIMARY KEY,
  age_group_label TEXT UNIQUE,
  age_min INT,
  age_max INT
);

INSERT INTO "Analytics".dim_age_group (age_group_label, age_min, age_max) VALUES
('0-17', 0, 17),
('18-24', 18, 24),
('25-34', 25, 34),
('35-44', 35, 44),
('45-54', 45, 54),
('55-64', 55, 64),
('65+', 65, 200);

-- -------------------------
-- 2) POPULATE DIMENSIONS
-- -------------------------

-- dim_date
INSERT INTO "Analytics".dim_date (date_occ, year, month, day, day_of_week)
SELECT DISTINCT
  to_date(split_part(r.date_occ, ' ', 1), 'MM/DD/YYYY') AS date_occ,
  EXTRACT(YEAR FROM to_date(split_part(r.date_occ, ' ', 1), 'MM/DD/YYYY'))::INT AS year,
  EXTRACT(MONTH FROM to_date(split_part(r.date_occ, ' ', 1), 'MM/DD/YYYY'))::INT AS month,
  EXTRACT(DAY FROM to_date(split_part(r.date_occ, ' ', 1), 'MM/DD/YYYY'))::INT AS day,
  EXTRACT(DOW FROM to_date(split_part(r.date_occ, ' ', 1), 'MM/DD/YYYY'))::INT AS day_of_week
FROM "Raw".la_crime_raw r
WHERE r.date_occ IS NOT NULL
ON CONFLICT (date_occ) DO NOTHING;

-- dim_area
INSERT INTO "Analytics".dim_area (area, area_name, rpt_dist_no)
SELECT DISTINCT area, area_name, rpt_dist_no
FROM "Raw".la_crime_raw
WHERE area IS NOT NULL
ON CONFLICT (area, area_name, rpt_dist_no) DO NOTHING;

-- dim_crime (v2: pick most common description per crm_cd)
INSERT INTO "Analytics".dim_crime (crm_cd, crm_cd_desc)
SELECT crm_cd, crm_cd_desc
FROM (
  SELECT
    crm_cd,
    crm_cd_desc,
    ROW_NUMBER() OVER (
      PARTITION BY crm_cd
      ORDER BY COUNT(*) DESC, crm_cd_desc
    ) AS rn
  FROM "Raw".la_crime_raw
  WHERE crm_cd IS NOT NULL
  GROUP BY crm_cd, crm_cd_desc
) t
WHERE rn = 1
ON CONFLICT (crm_cd) DO NOTHING;

-- dim_premis (v2: pick most common description per premis_cd)
INSERT INTO "Analytics".dim_premis (premis_cd, premis_desc)
SELECT premis_cd, premis_desc
FROM (
  SELECT
    premis_cd,
    premis_desc,
    ROW_NUMBER() OVER (
      PARTITION BY premis_cd
      ORDER BY COUNT(*) DESC, premis_desc
    ) AS rn
  FROM "Raw".la_crime_raw
  WHERE premis_cd IS NOT NULL
  GROUP BY premis_cd, premis_desc
) t
WHERE rn = 1
ON CONFLICT (premis_cd) DO NOTHING;

-- dim_weapon (v2: pick most common description per weapon_used_cd)
INSERT INTO "Analytics".dim_weapon (weapon_used_cd, weapon_desc)
SELECT weapon_used_cd, weapon_desc
FROM (
  SELECT
    weapon_used_cd,
    weapon_desc,
    ROW_NUMBER() OVER (
      PARTITION BY weapon_used_cd
      ORDER BY COUNT(*) DESC, weapon_desc
    ) AS rn
  FROM "Raw".la_crime_raw
  WHERE weapon_used_cd IS NOT NULL
  GROUP BY weapon_used_cd, weapon_desc
) t
WHERE rn = 1
ON CONFLICT (weapon_used_cd) DO NOTHING;

-- dim_status (v2: normalize status; pick most common desc)
INSERT INTO "Analytics".dim_status (status, status_desc)
SELECT status, status_desc
FROM (
  SELECT
    TRIM(UPPER(status)) AS status,
    status_desc,
    ROW_NUMBER() OVER (
      PARTITION BY TRIM(UPPER(status))
      ORDER BY COUNT(*) DESC, status_desc
    ) AS rn
  FROM "Raw".la_crime_raw
  WHERE status IS NOT NULL
  GROUP BY TRIM(UPPER(status)), status_desc
) t
WHERE rn = 1
ON CONFLICT (status) DO NOTHING;

-- -------------------------
-- 3) ADD UNKNOWN MEMBERS
-- -------------------------
INSERT INTO "Analytics".dim_crime (crm_cd, crm_cd_desc)
VALUES (-1, 'UNKNOWN / NOT PROVIDED')
ON CONFLICT (crm_cd) DO NOTHING;

INSERT INTO "Analytics".dim_premis (premis_cd, premis_desc)
VALUES (-1, 'UNKNOWN / NOT PROVIDED')
ON CONFLICT (premis_cd) DO NOTHING;

INSERT INTO "Analytics".dim_weapon (weapon_used_cd, weapon_desc)
VALUES (-1, 'UNKNOWN / NOT PROVIDED')
ON CONFLICT (weapon_used_cd) DO NOTHING;

INSERT INTO "Analytics".dim_status (status, status_desc)
VALUES ('UNK', 'UNKNOWN / NOT PROVIDED')
ON CONFLICT (status) DO NOTHING;

INSERT INTO "Analytics".dim_age_group (age_group_label, age_min, age_max)
VALUES ('UNKNOWN / NOT PROVIDED', -1, -1)
ON CONFLICT (age_group_label) DO NOTHING;

-- -------------------------
-- 4) CREATE FACT TABLE
-- -------------------------
CREATE TABLE "Analytics".fact_crime (
  dr_no BIGINT PRIMARY KEY,

  date_key INT REFERENCES "Analytics".dim_date(date_key),
  area_key INT REFERENCES "Analytics".dim_area(area_key),
  crime_key INT REFERENCES "Analytics".dim_crime(crime_key),
  premis_key INT REFERENCES "Analytics".dim_premis(premis_key),
  weapon_key INT REFERENCES "Analytics".dim_weapon(weapon_key),
  status_key INT REFERENCES "Analytics".dim_status(status_key),
  age_group_key INT REFERENCES "Analytics".dim_age_group(age_group_key),

  time_occ INT,
  vict_age INT,
  vict_sex TEXT,
  vict_descent TEXT,
  lat DOUBLE PRECISION,
  lon DOUBLE PRECISION,

  crm_cd_1 INT,
  crm_cd_2 INT,
  crm_cd_3 INT,
  crm_cd_4 INT
);
-- -------------------------
-- 5) POPULATE FACT TABLE
-- -------------------------
INSERT INTO "Analytics".fact_crime (
  dr_no, date_key, area_key, crime_key, premis_key, weapon_key, status_key, age_group_key,
  time_occ, vict_age, vict_sex, vict_descent, lat, lon,
  crm_cd_1, crm_cd_2, crm_cd_3, crm_cd_4
)
SELECT
  r.dr_no,
  d.date_key,
  a.area_key,
  c.crime_key,
  p.premis_key,
  w.weapon_key,
  s.status_key,
  ag.age_group_key,
  r.time_occ,
  r.vict_age,
  r.vict_sex,
  r.vict_descent,
  r.lat,
  r.lon,
  r.crm_cd_1,
  r.crm_cd_2,
  r.crm_cd_3,
  r.crm_cd_4
FROM "Raw".la_crime_raw r
LEFT JOIN "Analytics".dim_date d
  ON d.date_occ = to_date(split_part(r.date_occ, ' ', 1), 'MM/DD/YYYY')

LEFT JOIN "Analytics".dim_area a
  ON a.area = r.area
 AND a.area_name = r.area_name
 AND a.rpt_dist_no = r.rpt_dist_no

LEFT JOIN "Analytics".dim_crime c
  ON c.crm_cd = r.crm_cd
  OR (r.crm_cd IS NULL AND c.crm_cd = -1)

LEFT JOIN "Analytics".dim_premis p
  ON p.premis_cd = r.premis_cd
  OR (r.premis_cd IS NULL AND p.premis_cd = -1)

LEFT JOIN "Analytics".dim_weapon w
  ON w.weapon_used_cd = r.weapon_used_cd
  OR (r.weapon_used_cd IS NULL AND w.weapon_used_cd = -1)

LEFT JOIN "Analytics".dim_status s
  ON s.status = TRIM(UPPER(r.status))
  OR (r.status IS NULL AND s.status = 'UNK')

LEFT JOIN "Analytics".dim_age_group ag
  ON (
      r.vict_age IS NOT NULL
      AND r.vict_age >= ag.age_min
      AND r.vict_age <= ag.age_max
     )
  OR (
      (r.vict_age IS NULL OR r.vict_age < 0 OR r.vict_age > 200)
      AND ag.age_group_label = 'UNKNOWN / NOT PROVIDED'
  )
ON CONFLICT (dr_no) DO NOTHING;
-- -------------------------
-- 6) INDEXES
-- -------------------------
CREATE INDEX IF NOT EXISTS idx_fact_date_key   ON "Analytics".fact_crime(date_key);
CREATE INDEX IF NOT EXISTS idx_fact_area_key   ON "Analytics".fact_crime(area_key);
CREATE INDEX IF NOT EXISTS idx_fact_crime_key  ON "Analytics".fact_crime(crime_key);
CREATE INDEX IF NOT EXISTS idx_fact_premis_key ON "Analytics".fact_crime(premis_key);
CREATE INDEX IF NOT EXISTS idx_fact_weapon_key ON "Analytics".fact_crime(weapon_key);
CREATE INDEX IF NOT EXISTS idx_fact_status_key ON "Analytics".fact_crime(status_key);
CREATE INDEX IF NOT EXISTS idx_fact_age_group_key ON "Analytics".fact_crime(age_group_key);

-- -------------------------
-- 7) QUICK CHECKS
-- -------------------------
SELECT COUNT(*) AS raw_rows  FROM "Raw".la_crime_raw;
SELECT COUNT(*) AS fact_rows FROM "Analytics".fact_crime;
-- -------------------------
-- 8) NULL CHECKS
-- -------------------------
SELECT
  COUNT(*) FILTER (WHERE date_key IS NULL)       AS date_null,
  COUNT(*) FILTER (WHERE area_key IS NULL)       AS area_null,
  COUNT(*) FILTER (WHERE crime_key IS NULL)      AS crime_null,
  COUNT(*) FILTER (WHERE premis_key IS NULL)     AS premis_null,
  COUNT(*) FILTER (WHERE weapon_key IS NULL)     AS weapon_null,
  COUNT(*) FILTER (WHERE status_key IS NULL)     AS status_null,
  COUNT(*) FILTER (WHERE age_group_key IS NULL)  AS age_group_null
FROM "Analytics".fact_crime;

-- -------------------------
-- 9) DATA QUALITY VALIDATION
-- -------------------------
SELECT  
COUNT(*) AS rows_mapped_to_unknown_age  
FROM "Analytics".fact_crime f  
JOIN "Analytics".dim_age_group ag 
  ON f.age_group_key = ag.age_group_key  
WHERE ag.age_group_label = 'UNKNOWN / NOT PROVIDED';

