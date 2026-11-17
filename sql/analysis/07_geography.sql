-- =====================================================================
-- 07_geography.sql — Boroughs and ZIP codes.
-- Part A grain: 1 row per borough. Part B: 1 row per ZIP (top 15) with the
-- cumulative share. Part C: concentration summary.
-- =====================================================================

-- A. Boroughs
SELECT borough, COUNT(*) AS requests,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct,
       ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY resolution_hours)::NUMERIC, 1) AS median_hours
FROM mart.fact_request
GROUP BY borough
ORDER BY requests DESC;

-- B. Busiest ZIP codes (valid ones only)
SELECT RANK() OVER (ORDER BY COUNT(*) DESC) AS rank, zip,
       MODE() WITHIN GROUP (ORDER BY borough COLLATE "C") AS borough,
       COUNT(*) AS requests,
       ROUND(100.0 * SUM(COUNT(*)) OVER (ORDER BY COUNT(*) DESC, zip COLLATE "C") / SUM(COUNT(*)) OVER (), 1) AS cumulative_pct
FROM mart.fact_request
WHERE zip IS NOT NULL
GROUP BY zip
ORDER BY requests DESC, zip COLLATE "C"
LIMIT 15;

-- C. Concentration: share of requests made by the busiest ZIPs
SELECT * FROM mart.dash_concentration;
