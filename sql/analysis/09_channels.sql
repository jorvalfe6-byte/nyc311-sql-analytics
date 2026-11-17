-- =====================================================================
-- 09_channels.sql — How people reach 311.
-- Part A grain: 1 row per channel. Part B: channel mix of the 8 biggest
-- agencies, as a share of each agency requests.
-- =====================================================================

-- A. Overall
SELECT channel, COUNT(*) AS requests,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct,
       ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY resolution_hours)::NUMERIC, 1) AS median_hours
FROM mart.fact_request
GROUP BY channel
ORDER BY requests DESC;

-- B. By agency
WITH top AS (
    SELECT agency FROM mart.fact_request GROUP BY agency ORDER BY COUNT(*) DESC LIMIT 8
)
SELECT agency,
       ROUND(100.0 * AVG((channel = 'PHONE')::INT), 1)   AS pct_phone,
       ROUND(100.0 * AVG((channel = 'ONLINE')::INT), 1)  AS pct_online,
       ROUND(100.0 * AVG((channel = 'MOBILE')::INT), 1)  AS pct_mobile,
       ROUND(100.0 * AVG((channel = 'UNKNOWN')::INT), 1) AS pct_unknown
FROM mart.fact_request
WHERE agency IN (SELECT agency FROM top)
GROUP BY agency
ORDER BY pct_phone DESC;
