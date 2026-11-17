-- =====================================================================
-- 10_data_quality_issues.sql — Data-quality problems, with numbers.
-- Part A grain: 1 row per issue. Part B: which agencies produce the
-- requests closed before they were created. Part C: status vs closing date.
-- =====================================================================

-- A. Issues over all requests
SELECT issue, requests, pct FROM mart.dash_quality ORDER BY ord;

-- B. Agencies behind the "closed before created" records
SELECT agency, COUNT(*) FILTER (WHERE closed_before_created) AS closed_before_created,
       COUNT(*) AS requests,
       ROUND(100.0 * AVG(closed_before_created::INT), 3) AS pct
FROM mart.fact_request
GROUP BY agency
HAVING COUNT(*) FILTER (WHERE closed_before_created) > 0
ORDER BY closed_before_created DESC;

-- C. Status vs closing date: how the two columns disagree
SELECT status, COUNT(*) AS requests,
       COUNT(*) FILTER (WHERE closed_at IS NOT NULL) AS with_closed_date,
       COUNT(*) FILTER (WHERE closed_at IS NULL)     AS without_closed_date
FROM mart.fact_request
GROUP BY status
ORDER BY requests DESC;
