#!/usr/bin/env bash
# Writes every view in the powerbi_extract schema (aggregated, see
# sql/06_powerbi_extract.sql) to powerbi/data/<view>.csv.
# The Power BI report reads those CSV files, so it opens without PostgreSQL.
# Usage:
#   export PGHOST=localhost PGUSER=postgres PGDATABASE=nyc311
#   ./scripts/export_powerbi.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/powerbi/data"
mkdir -p "$OUT"
# Windows psql does not understand /c/... paths: convert them when cygpath exists
OUT_PSQL="$OUT"; command -v cygpath >/dev/null && OUT_PSQL="$(cygpath -m "$OUT")"
PSQL=(psql -X -q -v ON_ERROR_STOP=1)

views="$("${PSQL[@]}" -At -c "SELECT table_name FROM information_schema.views WHERE table_schema = 'powerbi_extract' ORDER BY 1")"
[[ -n "$views" ]] || { echo "No views in the powerbi_extract schema: run the load first." >&2; exit 1; }
for v in $views; do
    v="${v%$'\r'}"   # psql on Windows ends lines with CRLF
    echo "→ $v.csv"
    "${PSQL[@]}" -c "\copy (SELECT * FROM powerbi_extract.$v ORDER BY 1) TO '$OUT_PSQL/$v.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')"
done
echo "Done: CSV files in $OUT"
