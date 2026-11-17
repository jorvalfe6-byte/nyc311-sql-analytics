-- =====================================================================
-- 08_density_grid.sql — Where requests happen, on a lat/long grid.
-- Grain: 1 row (summary of the grid). Each cell is 0.004 deg lat x 0.005 deg
-- lng (about 440 x 420 m). Only requests with coordinates inside the NYC
-- box. The shares show how concentrated the activity is.
-- =====================================================================
WITH cell AS (
    SELECT FLOOR(latitude / 0.004)::INT AS iy, FLOOR(longitude / 0.005)::INT AS ix, COUNT(*) AS requests
    FROM mart.fact_request
    WHERE NOT missing_coords AND NOT coords_outside_nyc
    GROUP BY 1, 2
)
SELECT COUNT(*)                                                                    AS cells,
       SUM(requests)                                                               AS requests_mapped,
       MAX(requests)                                                               AS busiest_cell,
       ROUND(100.0 * SUM(requests) FILTER (WHERE rk <= CEIL(0.01 * n)) / SUM(requests), 1) AS pct_in_top1pct_cells,
       ROUND(100.0 * SUM(requests) FILTER (WHERE rk <= CEIL(0.10 * n)) / SUM(requests), 1) AS pct_in_top10pct_cells
FROM (SELECT requests, RANK() OVER (ORDER BY requests DESC) AS rk, COUNT(*) OVER () AS n FROM cell) AS c;
