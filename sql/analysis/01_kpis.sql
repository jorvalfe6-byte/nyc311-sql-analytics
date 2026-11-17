-- =====================================================================
-- 01_kpis.sql — Executive summary for the whole period.
-- Grain: 1 row. Resolution statistics use only requests with a valid
-- closing time (closed, and not before creation).
-- =====================================================================
SELECT COUNT(*)                                                      AS requests,
       COUNT(DISTINCT created_date)                                  AS days_covered,
       ROUND(COUNT(*)::NUMERIC / COUNT(DISTINCT created_date))       AS requests_per_day,
       COUNT(DISTINCT agency)                                        AS agencies,
       COUNT(DISTINCT complaint_type)                                AS complaint_types,
       ROUND(100.0 * AVG(is_open::INT), 2)                           AS pct_open,
       ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY resolution_hours)::NUMERIC, 1) AS median_hours,
       ROUND(PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY resolution_hours)::NUMERIC, 1) AS p90_hours
FROM mart.fact_request;
