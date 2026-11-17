-- =====================================================================
-- 05_powerbi_views.sql — Star schema for Power BI, schema "powerbi".
-- Plain views over mart.fact_request: nothing is copied, nothing to refresh
-- on the database side. Connect Power BI to this schema only.
--
-- Grain of powerbi.fact_request: ONE 311 SERVICE REQUEST (one row per
-- unique_key). Facts are never aggregated here; measures live in the model.
--
-- Keys are small integers assigned in alphabetical order (collation "C"),
-- so they are the same on every load of the same data.
--
-- Relationships (all many-to-one, single direction, dimension → fact):
--   dim_date.date_key           → fact_request.created_date_key  (active)
--   dim_date.date_key           → fact_request.closed_date_key   (inactive, use USERELATIONSHIP)
--   dim_agency.agency_key       → fact_request.agency_key
--   dim_complaint_type.complaint_type_key → fact_request.complaint_type_key
--   dim_location.location_key   → fact_request.location_key
--   dim_channel.channel_key     → fact_request.channel_key
--
-- Suggested measures: Requests = COUNTROWS(fact_request);
--   Median resolution (h) = MEDIAN(fact_request[resolution_hours]);
--   % open = DIVIDE(SUM(fact_request[is_open]), COUNTROWS(fact_request)).
-- resolution_hours is NULL when the request is open, has no closing date or its
-- closing time is before its creation time, so averages and medians ignore those rows.
-- =====================================================================
\set ON_ERROR_STOP on
SET client_min_messages = warning;

DROP SCHEMA IF EXISTS powerbi CASCADE;
CREATE SCHEMA powerbi;

-- Calendar: every day from the first creation or closing date to the last one,
-- with no gaps. Closing dates can fall after the creation period, and a few
-- (records closed before they were created) fall before it.
CREATE VIEW powerbi.dim_date AS
WITH span AS (
    SELECT LEAST(MIN(created_date), MIN(closed_at::DATE) FILTER (WHERE NOT is_open)) AS d0,
           GREATEST(MAX(created_date), MAX(closed_at::DATE) FILTER (WHERE NOT is_open)) AS d1
    FROM mart.fact_request
)
SELECT TO_CHAR(d, 'YYYYMMDD')::INT           AS date_key,
       d::DATE                               AS date,
       EXTRACT(YEAR FROM d)::SMALLINT        AS year,
       EXTRACT(QUARTER FROM d)::SMALLINT     AS quarter,
       EXTRACT(MONTH FROM d)::SMALLINT       AS month,
       TO_CHAR(d, 'Mon')                     AS month_name,
       TO_CHAR(d, 'YYYY-MM')                 AS year_month,
       EXTRACT(ISODOW FROM d)::SMALLINT      AS iso_dow,        -- 1 = Monday
       TO_CHAR(d, 'Dy')                      AS day_name,
       EXTRACT(ISODOW FROM d) >= 6           AS is_weekend,
       CASE WHEN EXTRACT(MONTH FROM d) IN (12, 1, 2) THEN 'Winter'
            WHEN EXTRACT(MONTH FROM d) IN (3, 4, 5)  THEN 'Spring'
            WHEN EXTRACT(MONTH FROM d) IN (6, 7, 8)  THEN 'Summer'
            ELSE 'Autumn' END               AS season
FROM span, GENERATE_SERIES(span.d0, span.d1, INTERVAL '1 day') AS g(d);

CREATE VIEW powerbi.dim_agency AS
SELECT ROW_NUMBER() OVER (ORDER BY agency COLLATE "C")::SMALLINT AS agency_key,
       agency, agency_name
FROM core.agency;

CREATE VIEW powerbi.dim_complaint_type AS
SELECT ROW_NUMBER() OVER (ORDER BY complaint_type COLLATE "C")::SMALLINT AS complaint_type_key,
       complaint_type
FROM (SELECT DISTINCT complaint_type FROM mart.fact_request) AS t;

CREATE VIEW powerbi.dim_channel AS
SELECT ROW_NUMBER() OVER (ORDER BY channel COLLATE "C")::SMALLINT AS channel_key,
       channel
FROM (SELECT DISTINCT channel FROM mart.fact_request) AS t;

-- One row per borough and valid ZIP. A request without a valid ZIP points to
-- the row (borough, 'Unknown'), so no fact row loses its location.
CREATE VIEW powerbi.dim_location AS
SELECT ROW_NUMBER() OVER (ORDER BY borough COLLATE "C", zip COLLATE "C")::INT AS location_key,
       borough, zip
FROM (SELECT DISTINCT borough, COALESCE(zip, 'Unknown') AS zip FROM mart.fact_request) AS t;

CREATE VIEW powerbi.fact_request AS
SELECT f.unique_key                                   AS request_id,
       TO_CHAR(f.created_date, 'YYYYMMDD')::INT       AS created_date_key,
       CASE WHEN NOT f.is_open THEN TO_CHAR(f.closed_at::DATE, 'YYYYMMDD')::INT END AS closed_date_key,   -- NULL while open or if the closing date is missing
       f.created_hour,
       a.agency_key,
       c.complaint_type_key,
       l.location_key,
       ch.channel_key,
       f.status,
       f.is_open::INT::SMALLINT                            AS is_open,
       f.resolution_hours,                                                 -- NULL if open or closed before created
       f.closed_before_created::INT::SMALLINT              AS closed_before_created,
       f.closed_without_date::INT::SMALLINT                AS closed_without_date,
       f.possible_duplicate::INT::SMALLINT                 AS possible_duplicate,
       ROUND(f.latitude::NUMERIC, 4)                  AS latitude,         -- ~11 m, enough for a map
       ROUND(f.longitude::NUMERIC, 4)                 AS longitude
FROM mart.fact_request AS f
JOIN powerbi.dim_agency         AS a  ON a.agency = f.agency
JOIN powerbi.dim_complaint_type AS c  ON c.complaint_type = f.complaint_type
JOIN powerbi.dim_channel        AS ch ON ch.channel = f.channel
JOIN powerbi.dim_location       AS l  ON l.borough = f.borough AND l.zip = COALESCE(f.zip, 'Unknown');
