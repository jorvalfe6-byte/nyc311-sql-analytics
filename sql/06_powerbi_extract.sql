-- =====================================================================
-- 06_powerbi_extract.sql — Aggregated extract read by the Power BI report.
--
-- The powerbi schema (05) keeps one row per request, which is right for a
-- live connection to PostgreSQL but far too big for a CSV in a Git repo
-- (3.4 million rows). This schema pre-aggregates the facts at the finest
-- grain the report needs; every measure is a sum of these columns, so
-- totals stay exact at any level. Medians cannot be rebuilt from sums, so the
-- report shows "% resolved within 24 h / 7 days" instead; the medians quoted
-- in the README come from sql/analysis.
-- scripts/export_powerbi.sh writes each view to powerbi/data/*.csv.
--
--   fact_monthly   grain: month x agency x complaint type x borough x channel
--   fact_hourly    grain: created date x created hour x borough
--   fact_zip       grain: month x borough/ZIP
--   fact_grid      grain: ~440 m map cell (same grid as the dashboard)
--   dim_*          the dimensions of the powerbi schema, calendar cut to 2024
-- =====================================================================
\set ON_ERROR_STOP on
SET client_min_messages = warning;

DROP SCHEMA IF EXISTS powerbi_extract CASCADE;
CREATE SCHEMA powerbi_extract;

CREATE VIEW powerbi_extract.fact_monthly AS
SELECT f.created_month                                            AS month_date,
       a.agency_key,
       c.complaint_type_key,
       f.borough,
       ch.channel_key,
       COUNT(*)                                                   AS requests,
       COUNT(*) FILTER (WHERE f.is_open)                          AS open_requests,
       COUNT(*) FILTER (WHERE f.has_resolution)                   AS resolved,
       ROUND(SUM(f.resolution_hours) FILTER (WHERE f.has_resolution), 2) AS resolution_hours_sum,
       COUNT(*) FILTER (WHERE f.has_resolution AND f.resolution_hours <= 24)  AS resolved_24h,
       COUNT(*) FILTER (WHERE f.has_resolution AND f.resolution_hours <= 168) AS resolved_7d,
       COUNT(*) FILTER (WHERE f.possible_duplicate)               AS possible_duplicates
FROM mart.fact_request AS f
JOIN powerbi.dim_agency         AS a  ON a.agency = f.agency
JOIN powerbi.dim_complaint_type AS c  ON c.complaint_type = f.complaint_type
JOIN powerbi.dim_channel        AS ch ON ch.channel = f.channel
GROUP BY 1, 2, 3, 4, 5;

CREATE VIEW powerbi_extract.fact_hourly AS
SELECT created_date, created_hour, borough, COUNT(*) AS requests
FROM mart.fact_request
GROUP BY 1, 2, 3;

CREATE VIEW powerbi_extract.fact_zip AS
SELECT f.created_month AS month_date, l.location_key, f.borough, COUNT(*) AS requests
FROM mart.fact_request AS f
JOIN powerbi.dim_location AS l ON l.borough = f.borough AND l.zip = COALESCE(f.zip, 'Unknown')
GROUP BY 1, 2, 3;

-- Cell centre of a 0.004° grid (about 440 m north-south), like the dashboard map.
CREATE VIEW powerbi_extract.fact_grid AS
WITH cells AS (
    SELECT ROUND((FLOOR(latitude  / 0.004) * 0.004 + 0.002)::NUMERIC, 4) AS cell_lat,
           ROUND((FLOOR(longitude / 0.004) * 0.004 + 0.002)::NUMERIC, 4) AS cell_lng,
           borough
    FROM mart.fact_request
    WHERE latitude IS NOT NULL AND longitude IS NOT NULL AND NOT coords_outside_nyc
)
SELECT cell_lat || ',' || cell_lng                AS cell,
       cell_lat,
       cell_lng,
       MODE() WITHIN GROUP (ORDER BY borough)     AS borough,   -- most common borough in the cell
       COUNT(*)                                   AS requests
FROM cells
GROUP BY cell_lat, cell_lng;

CREATE VIEW powerbi_extract.dim_date AS
SELECT date, month, month_name, iso_dow, day_name,
       CASE WHEN is_weekend THEN 'Weekend' ELSE 'Weekday' END AS day_type,
       season
FROM powerbi.dim_date
WHERE date BETWEEN DATE '2024-01-01' AND DATE '2024-12-31';

CREATE VIEW powerbi_extract.dim_agency AS SELECT * FROM powerbi.dim_agency;
CREATE VIEW powerbi_extract.dim_complaint_type AS SELECT * FROM powerbi.dim_complaint_type;
CREATE VIEW powerbi_extract.dim_channel AS SELECT * FROM powerbi.dim_channel;
CREATE VIEW powerbi_extract.dim_location AS SELECT * FROM powerbi.dim_location;
CREATE VIEW powerbi_extract.dim_borough AS
SELECT DISTINCT borough FROM powerbi.dim_location;

-- Control: each aggregated fact adds up to every request in core.
DO $$
DECLARE n BIGINT := (SELECT COUNT(*) FROM core.request);
BEGIN
    IF (SELECT SUM(requests) FROM powerbi_extract.fact_monthly) <> n
       OR (SELECT SUM(requests) FROM powerbi_extract.fact_hourly) <> n
       OR (SELECT SUM(requests) FROM powerbi_extract.fact_zip) <> n THEN
        RAISE EXCEPTION 'powerbi_extract: the aggregated facts do not add up to core.request';
    END IF;
END $$;
