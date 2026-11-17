-- =====================================================================
-- 06_resolution_time.sql — How long requests take to close.
-- Grain: 1 row per agency (part A) and per complaint type (part B).
-- Median and p90 of closed - created, in hours, over requests with a valid
-- closing time. The share still open is over ALL requests of the group:
-- a closing time that has not happened yet cannot enter a percentile, so
-- the percentiles of slow groups are biased downwards by the open ones.
-- =====================================================================

-- A. By agency
SELECT agency,
       COUNT(*)                                                                         AS requests,
       ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY resolution_hours)::NUMERIC, 1) AS median_hours,
       ROUND(PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY resolution_hours)::NUMERIC, 1) AS p90_hours,
       ROUND(100.0 * AVG(is_open::INT), 2)                                              AS pct_open
FROM mart.fact_request
GROUP BY agency
HAVING COUNT(*) >= 1000
ORDER BY median_hours DESC;

-- B. By complaint type: the 15 slowest among those with 2,000+ requests
SELECT complaint_type,
       COUNT(*)                                                                         AS requests,
       ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY resolution_hours)::NUMERIC, 1) AS median_hours,
       ROUND(PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY resolution_hours)::NUMERIC, 1) AS p90_hours,
       ROUND(100.0 * AVG(is_open::INT), 2)                                              AS pct_open,
       RANK() OVER (ORDER BY PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY resolution_hours) DESC) AS slowest_rank
FROM mart.fact_request
GROUP BY complaint_type
HAVING COUNT(*) >= 2000
ORDER BY median_hours DESC
LIMIT 15;
