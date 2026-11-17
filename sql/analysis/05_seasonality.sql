-- =====================================================================
-- 05_seasonality.sql — How complaint types shift with the seasons.
-- Grain: 1 row per complaint type with at least 10,000 requests.
-- Requests per day in each season (so seasons of different length compare)
-- and the summer/winter ratio. Winter = Dec-Feb of the calendar year.
-- =====================================================================
WITH days AS (
    SELECT season, COUNT(DISTINCT created_date) AS n_days FROM mart.fact_request GROUP BY season
),
t AS (
    SELECT f.complaint_type, f.season, COUNT(*)::NUMERIC / d.n_days AS per_day,
           SUM(COUNT(*)) OVER (PARTITION BY f.complaint_type) AS total
    FROM mart.fact_request AS f JOIN days AS d USING (season)
    GROUP BY f.complaint_type, f.season, d.n_days
)
SELECT complaint_type,
       ROUND(MAX(per_day) FILTER (WHERE season = 'Winter'), 1) AS winter_per_day,
       ROUND(MAX(per_day) FILTER (WHERE season = 'Spring'), 1) AS spring_per_day,
       ROUND(MAX(per_day) FILTER (WHERE season = 'Summer'), 1) AS summer_per_day,
       ROUND(MAX(per_day) FILTER (WHERE season = 'Autumn'), 1) AS autumn_per_day,
       ROUND(MAX(per_day) FILTER (WHERE season = 'Summer')
             / NULLIF(MAX(per_day) FILTER (WHERE season = 'Winter'), 0), 2) AS summer_over_winter
FROM t
WHERE total >= 10000
GROUP BY complaint_type
ORDER BY summer_over_winter DESC NULLS LAST;
