-- =====================================================================
-- 04_dashboard_views.sql — Compact views that feed the dashboard.
-- Each one is the short version of a query in sql/analysis/.
-- scripts/export_dashboard.sh dumps them to docs/data/dashboard.json.
-- =====================================================================
\set ON_ERROR_STOP on
SET client_min_messages = warning;

DROP VIEW IF EXISTS mart.dash_kpis, mart.dash_monthly, mart.dash_heat, mart.dash_top_complaints,
                    mart.dash_slowest, mart.dash_season_heat, mart.dash_season_swing, mart.dash_agency,
                    mart.dash_borough, mart.dash_zip, mart.dash_concentration, mart.dash_map,
                    mart.dash_channel_month, mart.dash_channel, mart.dash_quality CASCADE;

-- KPIs (see analysis/01)
CREATE VIEW mart.dash_kpis AS
WITH top1 AS (
    SELECT complaint_type, COUNT(*) AS n FROM mart.fact_request GROUP BY 1 ORDER BY n DESC, complaint_type COLLATE "C" LIMIT 1
)
SELECT COUNT(*)                                                         AS requests,
       ROUND(COUNT(*)::NUMERIC / COUNT(DISTINCT created_date))          AS requests_per_day,
       COUNT(DISTINCT agency)                                           AS agencies,
       COUNT(DISTINCT complaint_type)                                   AS complaint_types,
       ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY resolution_hours)::NUMERIC, 1) AS median_hours,
       ROUND(PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY resolution_hours)::NUMERIC, 1) AS p90_hours,
       ROUND(100.0 * AVG(is_open::INT), 2)                              AS pct_open,
       (SELECT complaint_type FROM top1)                                AS top_complaint,
       ROUND(100.0 * (SELECT n FROM top1) / COUNT(*), 1)                AS top_complaint_pct,
       MIN(created_date)                                                AS first_day,
       MAX(created_date)                                                AS last_day,
       COUNT(*) FILTER (WHERE NOT has_resolution AND NOT is_open)       AS excluded_from_resolution
FROM mart.fact_request;

-- Monthly series (see analysis/02)
CREATE VIEW mart.dash_monthly AS
WITH m AS (
    SELECT created_month AS month, COUNT(*) AS requests,
           ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY resolution_hours)::NUMERIC, 1) AS median_hours,
           ROUND(100.0 * AVG(is_open::INT), 2) AS pct_open
    FROM mart.fact_request GROUP BY created_month
)
SELECT month, requests,
       ROUND(AVG(requests) OVER (ORDER BY month ROWS BETWEEN 2 PRECEDING AND CURRENT ROW)) AS requests_ma3,
       median_hours, pct_open
FROM m;

-- Weekday x hour heatmap (see analysis/03)
CREATE VIEW mart.dash_heat AS
WITH days AS (
    SELECT iso_dow, COUNT(DISTINCT created_date) AS n_days FROM mart.fact_request GROUP BY iso_dow
)
SELECT f.iso_dow AS dow, f.created_hour AS hour, ROUND(COUNT(*)::NUMERIC / d.n_days) AS requests_per_day
FROM mart.fact_request AS f JOIN days AS d USING (iso_dow)
GROUP BY f.iso_dow, f.created_hour, d.n_days;

-- Top complaint types with their resolution time (see analysis/04 and 06)
CREATE VIEW mart.dash_top_complaints AS
SELECT RANK() OVER (ORDER BY COUNT(*) DESC) AS rank, complaint_type, COUNT(*) AS requests,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct,
       ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY resolution_hours)::NUMERIC, 1) AS median_hours,
       ROUND(PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY resolution_hours)::NUMERIC, 1) AS p90_hours,
       ROUND(100.0 * AVG(is_open::INT), 2) AS pct_open
FROM mart.fact_request
GROUP BY complaint_type
ORDER BY requests DESC, complaint_type COLLATE "C"      -- explicit collation: tie-breaks must not depend on the server locale
LIMIT 15;

-- Slowest complaint types among those with at least 2,000 requests (see analysis/06)
CREATE VIEW mart.dash_slowest AS
SELECT RANK() OVER (ORDER BY PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY resolution_hours) DESC) AS rank,
       complaint_type, COUNT(*) AS requests,
       ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY resolution_hours)::NUMERIC, 1) AS median_hours,
       ROUND(PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY resolution_hours)::NUMERIC, 1) AS p90_hours,
       ROUND(100.0 * AVG(is_open::INT), 2) AS pct_open
FROM mart.fact_request
GROUP BY complaint_type
HAVING COUNT(*) >= 2000
ORDER BY median_hours DESC, complaint_type COLLATE "C"
LIMIT 10;

-- Complaint type x month, for the 12 biggest types (see analysis/05)
CREATE VIEW mart.dash_season_heat AS
WITH top AS (
    SELECT complaint_type, RANK() OVER (ORDER BY COUNT(*) DESC, complaint_type COLLATE "C") AS rank
    FROM mart.fact_request GROUP BY complaint_type ORDER BY COUNT(*) DESC, complaint_type COLLATE "C" LIMIT 12
)
SELECT t.rank, f.complaint_type, EXTRACT(MONTH FROM f.created_month)::INT AS month, COUNT(*) AS requests
FROM mart.fact_request AS f JOIN top AS t USING (complaint_type)
GROUP BY t.rank, f.complaint_type, f.created_month;

-- Biggest seasonal swings: requests per day in summer vs winter (see analysis/05)
CREATE VIEW mart.dash_season_swing AS
WITH days AS (
    SELECT season, COUNT(DISTINCT created_date) AS n_days FROM mart.fact_request GROUP BY season
),
t AS (
    SELECT f.complaint_type,
           COUNT(*) FILTER (WHERE f.season = 'Summer')::NUMERIC / (SELECT n_days FROM days WHERE season = 'Summer') AS summer_per_day,
           COUNT(*) FILTER (WHERE f.season = 'Winter')::NUMERIC / (SELECT n_days FROM days WHERE season = 'Winter') AS winter_per_day,
           COUNT(*) AS requests
    FROM mart.fact_request AS f GROUP BY f.complaint_type HAVING COUNT(*) >= 10000
),
r AS (
    SELECT *, summer_per_day / NULLIF(winter_per_day, 0) AS ratio,
           ROW_NUMBER() OVER (ORDER BY summer_per_day / NULLIF(winter_per_day, 0) DESC NULLS LAST, complaint_type COLLATE "C") AS up_rank,
           ROW_NUMBER() OVER (ORDER BY summer_per_day / NULLIF(winter_per_day, 0) ASC  NULLS LAST, complaint_type COLLATE "C") AS down_rank
    FROM t
)
SELECT complaint_type, requests,
       ROUND(summer_per_day, 1) AS summer_per_day, ROUND(winter_per_day, 1) AS winter_per_day,
       ROUND(ratio, 2) AS ratio,
       CASE WHEN up_rank <= 6 THEN 'summer' ELSE 'winter' END AS leans
FROM r WHERE up_rank <= 6 OR down_rank <= 6;

-- Agencies: volume and resolution (see analysis/06)
CREATE VIEW mart.dash_agency AS
SELECT RANK() OVER (ORDER BY COUNT(*) DESC) AS rank, f.agency, a.agency_name, COUNT(*) AS requests,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct,
       ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY f.resolution_hours)::NUMERIC, 1) AS median_hours,
       ROUND(PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY f.resolution_hours)::NUMERIC, 1) AS p90_hours,
       ROUND(100.0 * AVG(f.is_open::INT), 2) AS pct_open
FROM mart.fact_request AS f JOIN core.agency AS a USING (agency)
GROUP BY f.agency, a.agency_name
ORDER BY requests DESC, f.agency COLLATE "C"
LIMIT 12;

-- Boroughs (see analysis/07)
CREATE VIEW mart.dash_borough AS
WITH b AS (
    SELECT borough, COUNT(*) AS requests,
           ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY resolution_hours)::NUMERIC, 1) AS median_hours,
           ROUND(100.0 * AVG(is_open::INT), 2) AS pct_open
    FROM mart.fact_request GROUP BY borough
),
top AS (
    SELECT DISTINCT ON (borough) borough, complaint_type AS top_complaint
    FROM (SELECT borough, complaint_type, COUNT(*) AS n FROM mart.fact_request GROUP BY 1, 2) AS x
    ORDER BY borough, n DESC, complaint_type COLLATE "C"
)
SELECT RANK() OVER (ORDER BY b.requests DESC) AS rank, b.borough, b.requests,
       ROUND(100.0 * b.requests / SUM(b.requests) OVER (), 1) AS pct,
       b.median_hours, b.pct_open, t.top_complaint
FROM b JOIN top AS t USING (borough)
ORDER BY b.requests DESC;

-- Busiest ZIP codes (see analysis/07)
CREATE VIEW mart.dash_zip AS
WITH z AS (
    SELECT zip, MODE() WITHIN GROUP (ORDER BY borough COLLATE "C") AS borough, COUNT(*) AS requests,
           ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY resolution_hours)::NUMERIC, 1) AS median_hours
    FROM mart.fact_request WHERE zip IS NOT NULL GROUP BY zip
)
SELECT RANK() OVER (ORDER BY requests DESC) AS rank, zip, borough, requests,
       ROUND(100.0 * requests / SUM(requests) OVER (), 2) AS pct, median_hours
FROM z
ORDER BY requests DESC, zip COLLATE "C"
LIMIT 12;

-- ZIP concentration (see analysis/07)
CREATE VIEW mart.dash_concentration AS
WITH p AS (
    SELECT requests, PERCENT_RANK() OVER (ORDER BY requests DESC) AS pr
    FROM (SELECT COUNT(*) AS requests FROM mart.fact_request WHERE zip IS NOT NULL GROUP BY zip) AS t
)
SELECT COUNT(*) AS zips,
       ROUND(100.0 * SUM(requests) FILTER (WHERE pr < 0.01) / SUM(requests), 1) AS pct_top1,
       ROUND(100.0 * SUM(requests) FILTER (WHERE pr < 0.10) / SUM(requests), 1) AS pct_top10,
       ROUND(100.0 * SUM(requests) FILTER (WHERE pr < 0.20) / SUM(requests), 1) AS pct_top20
FROM p;

-- Density map: requests with a valid point, grouped in cells of 0.004 deg lat x 0.005 deg lng
-- (about 440 m x 420 m). Cells with fewer than 25 requests are left out. (see analysis/08)
CREATE VIEW mart.dash_map AS
SELECT ROUND((FLOOR(latitude  / 0.004) * 0.004 + 0.002)::NUMERIC, 3) AS lat,
       ROUND((FLOOR(longitude / 0.005) * 0.005 + 0.0025)::NUMERIC, 4) AS lng,
       COUNT(*) AS requests
FROM mart.fact_request
WHERE NOT missing_coords AND NOT coords_outside_nyc
GROUP BY 1, 2
HAVING COUNT(*) >= 25;

-- Channel mix by month (see analysis/09)
CREATE VIEW mart.dash_channel_month AS
SELECT created_month AS month, channel,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (PARTITION BY created_month), 1) AS pct
FROM mart.fact_request GROUP BY created_month, channel;

CREATE VIEW mart.dash_channel AS
SELECT channel, COUNT(*) AS requests,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct,
       ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY resolution_hours)::NUMERIC, 1) AS median_hours
FROM mart.fact_request GROUP BY channel;

-- Data-quality issues, counted over all requests (see analysis/00 and 10)
CREATE VIEW mart.dash_quality AS
SELECT x.ord, x.issue, x.requests, ROUND(100.0 * x.requests / t.n, 2) AS pct
FROM (SELECT COUNT(*) AS n FROM mart.fact_request) AS t,
LATERAL (VALUES
    (1, 'Closed before it was created',             (SELECT COUNT(*) FROM mart.fact_request WHERE closed_before_created)),
    (2, 'Status Closed but no closing date',        (SELECT COUNT(*) FROM mart.fact_request WHERE closed_without_date)),
    (3, 'Not closed but with a closing date',       (SELECT COUNT(*) FROM mart.fact_request WHERE status_mismatch AND NOT closed_without_date)),
    (4, 'No coordinates',                           (SELECT COUNT(*) FROM mart.fact_request WHERE missing_coords)),
    (5, 'Coordinates outside New York City',        (SELECT COUNT(*) FROM mart.fact_request WHERE coords_outside_nyc)),
    (6, 'No ZIP code',                              (SELECT COUNT(*) FROM mart.fact_request WHERE missing_zip)),
    (7, 'ZIP code outside the city ranges',         (SELECT COUNT(*) FROM mart.fact_request WHERE invalid_zip)),
    (8, 'Possible duplicate of an earlier request', (SELECT COUNT(*) FROM mart.fact_request WHERE possible_duplicate))
) AS x(ord, issue, requests);
