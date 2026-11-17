-- =====================================================================
-- 03_marts.sql — Semantic layer for analysis and dashboards.
--
-- Business definitions used across the project:
--   * Request    : one row of the 311 dataset (grain of fact_request).
--   * Open       : status <> 'Closed' (the city own label). The status and
--                  closed_date columns disagree for some requests, so every
--                  request falls in exactly one of four groups:
--                    - open                  : status is not Closed
--                    - closed_without_date   : Closed, but closed_date is empty
--                    - closed_before_created : Closed, closing time earlier
--                                              than creation time
--                    - has_resolution        : Closed with a usable closing time
--   * Resolution : hours between closed_at and created_at, only for the
--                  has_resolution group. The other groups keep their flag
--                  and are left out of resolution statistics, never deleted.
--   * Season     : Winter = Dec–Feb, Spring = Mar–May, Summer = Jun–Aug,
--                  Autumn = Sep–Nov (calendar year, so winter mixes the
--                  start and the end of 2024).
--   * Valid ZIP  : 5 digits inside the New York City ranges
--                  10001–10499 and 11004–11697. A ZIP outside them is
--                  flagged invalid_zip (a typo, a suburb or a placeholder).
--   * Valid point: latitude/longitude inside the NYC box
--                  (lat 40.45–40.95, lng -74.30 to -73.65). A point
--                  outside it is flagged coords_outside_nyc.
--   * Possible duplicate: same second, agency, complaint type, descriptor
--                  and coordinates as an earlier request. Flagged and
--                  counted, not removed: two neighbours can call about the
--                  same noise at the same second.
-- =====================================================================
\set ON_ERROR_STOP on
SET client_min_messages = warning;

DROP MATERIALIZED VIEW IF EXISTS mart.fact_request CASCADE;

CREATE MATERIALIZED VIEW mart.fact_request AS
WITH base AS (
    SELECT r.*,
           EXTRACT(EPOCH FROM r.closed_at - r.created_at) / 3600.0 AS hours_raw,
           (r.incident_zip ~ '^[0-9]{5}$'
            AND (r.incident_zip::INT BETWEEN 10001 AND 10499
              OR r.incident_zip::INT BETWEEN 11004 AND 11697))      AS zip_ok,
           (r.latitude BETWEEN 40.45 AND 40.95
            AND r.longitude BETWEEN -74.30 AND -73.65)              AS point_ok,
           ROW_NUMBER() OVER (PARTITION BY r.created_at, r.agency, r.complaint_type, r.descriptor,
                                           r.latitude, r.longitude
                              ORDER BY r.unique_key)                AS dup_n
    FROM core.request AS r
)
SELECT unique_key,
       created_at,
       closed_at,
       created_at::DATE                                    AS created_date,
       DATE_TRUNC('month', created_at)::DATE               AS created_month,
       EXTRACT(HOUR FROM created_at)::SMALLINT             AS created_hour,
       EXTRACT(ISODOW FROM created_at)::SMALLINT           AS iso_dow,            -- 1 = Monday
       EXTRACT(ISODOW FROM created_at) >= 6                AS is_weekend,
       CASE WHEN EXTRACT(MONTH FROM created_at) IN (12, 1, 2) THEN 'Winter'
            WHEN EXTRACT(MONTH FROM created_at) IN (3, 4, 5)  THEN 'Spring'
            WHEN EXTRACT(MONTH FROM created_at) IN (6, 7, 8)  THEN 'Summer'
            ELSE 'Autumn' END                              AS season,
       agency,
       complaint_type,
       borough,
       CASE WHEN zip_ok THEN incident_zip END              AS zip,
       channel,
       status,
       (status <> 'Closed')                                AS is_open,
       CASE WHEN status = 'Closed' AND closed_at IS NOT NULL AND hours_raw >= 0 THEN ROUND(hours_raw::NUMERIC, 3) END AS resolution_hours,
       (status = 'Closed' AND closed_at IS NOT NULL AND hours_raw >= 0) AS has_resolution,
       latitude,
       longitude,
       -- data-quality flags (explicit NULL handling: a NULL flag would silently drop rows)
       (status = 'Closed' AND closed_at IS NOT NULL AND hours_raw < 0) AS closed_before_created,
       (status = 'Closed' AND closed_at IS NULL)           AS closed_without_date,
       (latitude IS NULL OR longitude IS NULL)             AS missing_coords,
       (latitude IS NOT NULL AND longitude IS NOT NULL AND NOT point_ok) AS coords_outside_nyc,
       (incident_zip IS NULL)                              AS missing_zip,
       (incident_zip IS NOT NULL AND NOT zip_ok)           AS invalid_zip,
       (dup_n > 1)                                         AS possible_duplicate,
       ((status = 'Closed' AND closed_at IS NULL) OR (status <> 'Closed' AND closed_at IS NOT NULL)) AS status_mismatch   -- includes closed_without_date
FROM base;

CREATE UNIQUE INDEX ux_fact_request          ON mart.fact_request (unique_key);
CREATE INDEX ix_fact_request_month           ON mart.fact_request (created_month);
CREATE INDEX ix_fact_request_agency          ON mart.fact_request (agency);

ANALYZE mart.fact_request;
