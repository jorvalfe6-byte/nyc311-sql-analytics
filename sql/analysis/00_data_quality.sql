-- =====================================================================
-- 00_data_quality.sql — Checks after every load.
-- Each row is one check: 'OK' when the value is inside [low, high],
-- 'REVIEW' otherwise. Run with  psql -v sample=0  (full year, default in
-- load.sh) or  -v sample=1  (the 24,000-row CI sample).
--
-- The source is a live dataset, updated daily: requests created in 2024 can
-- be corrected, closed or (rarely) added later. So the checks that depend
-- on the current state of the source are RANGES around what I measured on the
-- day of the load; the structural checks (no duplicates, nothing lost, keys
-- complete) are exact. If a range check says REVIEW, look at the data before
-- widening the range.
-- =====================================================================
\if :{?sample} \else \set sample 0 \endif

WITH checks AS (
    -- ---- completeness: nothing lost between layers (exact) ----
    SELECT 'rows staged (all 12 CSV files)' AS check_name,
           (SELECT COUNT(*) FROM staging.requests) AS value,
           CASE WHEN :sample = 1 THEN 24000   ELSE 3400000 END AS low,
           CASE WHEN :sample = 1 THEN 24000   ELSE 3500000 END AS high
    UNION ALL
    SELECT 'duplicate unique_key in the files',
           (SELECT COUNT(*) - COUNT(DISTINCT unique_key) FROM staging.requests), 0, 0
    UNION ALL
    SELECT 'requests loaded = rows staged',
           (SELECT COUNT(*) FROM core.request), (SELECT COUNT(*) FROM staging.requests), (SELECT COUNT(*) FROM staging.requests)
    UNION ALL
    SELECT 'rows rejected by the load',
           -- the whole load runs in one transaction, so it shares now()
           (SELECT COALESCE(SUM(rows_rejected), 0) FROM audit.load_log
            WHERE loaded_at = (SELECT MAX(loaded_at) FROM audit.load_log)), 0, 0
    UNION ALL
    SELECT 'mart rows = core rows',            (SELECT COUNT(*) FROM mart.fact_request), (SELECT COUNT(*) FROM core.request), (SELECT COUNT(*) FROM core.request)
    UNION ALL
    SELECT 'power bi fact rows = core rows',   (SELECT COUNT(*) FROM powerbi.fact_request), (SELECT COUNT(*) FROM core.request), (SELECT COUNT(*) FROM core.request)
    UNION ALL
    SELECT 'power bi fact: request_id is unique',
           (SELECT COUNT(*) - COUNT(DISTINCT request_id) FROM powerbi.fact_request), 0, 0
    -- ---- period and calendar ----
    UNION ALL
    SELECT 'months covered',                   (SELECT COUNT(DISTINCT created_month) FROM mart.fact_request), 12, 12
    UNION ALL
    SELECT 'requests created outside 2024',    (SELECT COUNT(*) FROM core.request WHERE created_at < DATE '2024-01-01' OR created_at >= DATE '2025-01-01'), 0, 0
    UNION ALL
    SELECT 'power bi calendar has no gaps',
           (SELECT COUNT(*) FROM powerbi.dim_date),
           (SELECT MAX(date) - MIN(date) + 1 FROM powerbi.dim_date), (SELECT MAX(date) - MIN(date) + 1 FROM powerbi.dim_date)
    UNION ALL
    SELECT 'power bi fact dates without a calendar row',
           (SELECT COUNT(*) FROM powerbi.fact_request AS f
            LEFT JOIN powerbi.dim_date AS d1 ON d1.date_key = f.created_date_key
            LEFT JOIN powerbi.dim_date AS d2 ON d2.date_key = f.closed_date_key
            WHERE d1.date_key IS NULL OR (f.closed_date_key IS NOT NULL AND d2.date_key IS NULL)), 0, 0
    -- ---- internal consistency of the marts (exact) ----
    UNION ALL
    SELECT 'resolution_hours is never negative',
           (SELECT COUNT(*) FROM mart.fact_request WHERE resolution_hours < 0), 0, 0
    UNION ALL
    SELECT 'open requests carry no resolution time',
           (SELECT COUNT(*) FROM mart.fact_request WHERE is_open AND resolution_hours IS NOT NULL), 0, 0
    UNION ALL
    SELECT 'open + closed-ok + closed-before-created + closed-without-date = all',
           (SELECT COUNT(*) FILTER (WHERE is_open) + COUNT(*) FILTER (WHERE has_resolution) + COUNT(*) FILTER (WHERE closed_before_created)
                   + COUNT(*) FILTER (WHERE closed_without_date) FROM mart.fact_request),
           (SELECT COUNT(*) FROM mart.fact_request), (SELECT COUNT(*) FROM mart.fact_request)
    UNION ALL
    SELECT 'valid ZIPs are 5 digits',
           (SELECT COUNT(*) FROM mart.fact_request WHERE zip IS NOT NULL AND zip !~ '^[0-9]{5}$'), 0, 0
    -- ---- data-quality measurements: ranges around what the full year showed ----
    UNION ALL
    SELECT 'closed before created (measured 79)', (SELECT COUNT(*) FROM mart.fact_request WHERE closed_before_created),
           CASE WHEN :sample = 1 THEN 0 ELSE 20 END, CASE WHEN :sample = 1 THEN 24000 ELSE 300 END
    UNION ALL
    SELECT 'status Closed but no closing date (measured 27,563)', (SELECT COUNT(*) FROM mart.fact_request WHERE closed_without_date),
           CASE WHEN :sample = 1 THEN 0 ELSE 5000 END, CASE WHEN :sample = 1 THEN 24000 ELSE 60000 END
    UNION ALL
    SELECT 'not closed but with a closing date (measured 2,988)', (SELECT COUNT(*) FROM mart.fact_request WHERE status_mismatch AND NOT closed_without_date),
           CASE WHEN :sample = 1 THEN 0 ELSE 500 END, CASE WHEN :sample = 1 THEN 24000 ELSE 10000 END
    UNION ALL
    SELECT 'no coordinates (measured 52,734)', (SELECT COUNT(*) FROM mart.fact_request WHERE missing_coords),
           CASE WHEN :sample = 1 THEN 0 ELSE 30000 END, CASE WHEN :sample = 1 THEN 24000 ELSE 80000 END
    UNION ALL
    SELECT 'coordinates outside the NYC box (measured 0)', (SELECT COUNT(*) FROM mart.fact_request WHERE coords_outside_nyc),
           CASE WHEN :sample = 1 THEN 0 ELSE 0 END, CASE WHEN :sample = 1 THEN 24000 ELSE 500 END
    UNION ALL
    SELECT 'no ZIP code (measured 34,340)', (SELECT COUNT(*) FROM mart.fact_request WHERE missing_zip),
           CASE WHEN :sample = 1 THEN 0 ELSE 15000 END, CASE WHEN :sample = 1 THEN 24000 ELSE 60000 END
    UNION ALL
    SELECT 'ZIP outside the city ranges (measured 1,796)', (SELECT COUNT(*) FROM mart.fact_request WHERE invalid_zip),
           CASE WHEN :sample = 1 THEN 0 ELSE 500 END, CASE WHEN :sample = 1 THEN 24000 ELSE 5000 END
    UNION ALL
    SELECT 'possible duplicates (measured 38,745)', (SELECT COUNT(*) FROM mart.fact_request WHERE possible_duplicate),
           CASE WHEN :sample = 1 THEN 0 ELSE 20000 END, CASE WHEN :sample = 1 THEN 24000 ELSE 70000 END
)
SELECT check_name,
       value,
       CASE WHEN low = high THEN low::TEXT ELSE low || ' to ' || high END AS expected,
       CASE WHEN value BETWEEN low AND high THEN 'OK' ELSE 'REVIEW' END   AS status
FROM checks;

-- Known characteristics of the dataset (not load errors); numbers in the README:
--   * The status column and the closing date disagree: some requests are
--     Closed with no closing date, a few are not closed but have one.
--   * A handful of requests have a closing time earlier than their creation time.
--   * About 1.5 % of requests have no coordinates and 1 % no ZIP code; a few
--     ZIP codes fall outside the city ranges. No coordinate falls outside NYC.
--   * Possible duplicates (same second, agency, type, descriptor and place)
--     are flagged, not removed.
