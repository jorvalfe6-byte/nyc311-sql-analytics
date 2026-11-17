-- =====================================================================
-- 03_weekday_hour.sql — Demand across the 168 hours of the week.
-- Grain: 1 row per weekday and hour. Average requests per calendar day of
-- that weekday (normalised, so a weekday that occurs 53 times is not
-- favoured), and an index against the busiest cell.
-- =====================================================================
WITH days AS (
    SELECT iso_dow, COUNT(DISTINCT created_date) AS n_days FROM mart.fact_request GROUP BY iso_dow
),
cell AS (
    SELECT f.iso_dow, f.created_hour, COUNT(*)::NUMERIC / d.n_days AS per_day
    FROM mart.fact_request AS f JOIN days AS d USING (iso_dow)
    GROUP BY f.iso_dow, f.created_hour, d.n_days
)
SELECT iso_dow, created_hour, ROUND(per_day) AS requests_per_day,
       ROUND(100 * per_day / MAX(per_day) OVER ()) AS index_vs_peak,
       RANK() OVER (ORDER BY per_day DESC)         AS busiest_rank
FROM cell
ORDER BY iso_dow, created_hour;
