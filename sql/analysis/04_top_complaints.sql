-- =====================================================================
-- 04_top_complaints.sql — Which complaint types dominate.
-- Grain: 1 row per complaint type (top 25). The running share shows how few
-- types carry most of the volume.
-- =====================================================================
SELECT RANK() OVER (ORDER BY COUNT(*) DESC)                              AS rank,
       complaint_type,
       COUNT(*)                                                          AS requests,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)                AS pct,
       ROUND(100.0 * SUM(COUNT(*)) OVER (ORDER BY COUNT(*) DESC, complaint_type COLLATE "C")
             / SUM(COUNT(*)) OVER (), 1)                                 AS cumulative_pct
FROM mart.fact_request
GROUP BY complaint_type
ORDER BY requests DESC, complaint_type COLLATE "C"
LIMIT 25;
