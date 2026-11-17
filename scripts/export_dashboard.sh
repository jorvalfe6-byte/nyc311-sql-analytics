#!/usr/bin/env bash
# Dumps the mart.dash_* views to the single JSON the dashboard reads.
# Only aggregates leave the database: no individual request is published.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/docs/data/dashboard.json"
mkdir -p "$(dirname "$OUT")"

psql -X -q -At -v ON_ERROR_STOP=1 > "$OUT" <<'SQL'
SELECT json_build_object(
    -- date of the load, not of the export: exporting twice gives the same file
    'generated',      (SELECT to_char(MAX(loaded_at), 'YYYY-MM-DD') FROM audit.load_log),
    'kpis',           (SELECT row_to_json(k) FROM mart.dash_kpis k),
    'monthly',        (SELECT json_agg(m ORDER BY month)                                   FROM mart.dash_monthly m),
    'heat',           (SELECT json_agg(h ORDER BY dow, hour)                               FROM mart.dash_heat h),
    'top_complaints', (SELECT json_agg(t ORDER BY rank, complaint_type COLLATE "C")        FROM mart.dash_top_complaints t),
    'slowest',        (SELECT json_agg(s ORDER BY rank, complaint_type COLLATE "C")        FROM mart.dash_slowest s),
    'season_heat',    (SELECT json_agg(s ORDER BY rank, month)                             FROM mart.dash_season_heat s),
    'season_swing',   (SELECT json_agg(s ORDER BY leans DESC, ratio DESC, complaint_type COLLATE "C") FROM mart.dash_season_swing s),
    'agency',         (SELECT json_agg(a ORDER BY rank, agency COLLATE "C")                FROM mart.dash_agency a),
    'borough',        (SELECT json_agg(b ORDER BY rank, borough COLLATE "C")               FROM mart.dash_borough b),
    'zip',            (SELECT json_agg(z ORDER BY rank, zip COLLATE "C")                   FROM mart.dash_zip z),
    'concentration',  (SELECT row_to_json(c) FROM mart.dash_concentration c),
    -- compact: [lat, lng, requests] per cell
    'map',            (SELECT json_agg(json_build_array(m.lat, m.lng, m.requests) ORDER BY m.lat, m.lng) FROM mart.dash_map m),
    'channel_month',  (SELECT json_agg(c ORDER BY month, channel COLLATE "C")              FROM mart.dash_channel_month c),
    'channel',        (SELECT json_agg(c ORDER BY requests DESC, channel COLLATE "C")      FROM mart.dash_channel c),
    'quality',        (SELECT json_agg(q ORDER BY ord)                                     FROM mart.dash_quality q)
);
SQL

echo "→ $OUT ($(wc -c < "$OUT") bytes)"
