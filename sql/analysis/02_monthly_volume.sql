-- =====================================================================
-- 02_monthly_volume.sql — Monthly demand.
-- Grain: 1 row per month. Calendar from generate_series so a month with no
-- requests would still appear; LAG for month-over-month, 3-month moving
-- average, RANK of the busiest months.
-- =====================================================================
WITH calendar AS (
    SELECT d::DATE AS month
    FROM GENERATE_SERIES((SELECT MIN(created_month) FROM mart.fact_request),
                         (SELECT MAX(created_month) FROM mart.fact_request), INTERVAL '1 month') AS g(d)
),
m AS (
    SELECT c.month, COUNT(f.unique_key) AS requests
    FROM calendar AS c LEFT JOIN mart.fact_request AS f ON f.created_month = c.month
    GROUP BY c.month
)
SELECT month, requests,
       requests - LAG(requests) OVER (ORDER BY month)                                   AS change_vs_prev,
       ROUND(100.0 * (requests - LAG(requests) OVER (ORDER BY month))
             / NULLIF(LAG(requests) OVER (ORDER BY month), 0), 1)                       AS pct_change,
       ROUND(AVG(requests) OVER (ORDER BY month ROWS BETWEEN 2 PRECEDING AND CURRENT ROW)) AS ma3,
       RANK() OVER (ORDER BY requests DESC)                                             AS busiest_rank
FROM m
ORDER BY month;
