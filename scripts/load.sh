#!/usr/bin/env bash
# Full load: schema → staging → core → marts → dashboard views → Power BI views → checks.
# Usage:
#   export PGHOST=localhost PGUSER=postgres PGDATABASE=nyc311
#   ./scripts/load.sh            # reads ./data by default
#   ./scripts/load.sh /path/to/csv
#   SAMPLE=1 ./scripts/load.sh   # expects the 24,000-row sample (used by CI)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DATA_DIR="${1:-$ROOT/data}"
PSQL=(psql -X -q -v ON_ERROR_STOP=1)

shopt -s nullglob
files=("$DATA_DIR"/*-nyc311.csv)
if (( ${#files[@]} == 0 )); then
    echo "No *-nyc311.csv files in $DATA_DIR" >&2
    echo "Run ./scripts/download_data.sh first." >&2
    exit 1
fi

echo "→ schema";  "${PSQL[@]}" -f "$ROOT/sql/01_schema.sql"
echo "→ staging (${#files[@]} files)"
for f in "${files[@]}"; do
    echo "   $(basename "$f")"
    # inside the -c string Git Bash does not translate paths for a native Windows psql
    path="$f"; command -v cygpath >/dev/null 2>&1 && path="$(cygpath -m "$f")"
    "${PSQL[@]}" -c "\copy staging.requests FROM '$path' WITH (FORMAT csv, HEADER true)"
done
echo "→ core";      "${PSQL[@]}" -f "$ROOT/sql/02_transform.sql"
echo "→ marts";     "${PSQL[@]}" -f "$ROOT/sql/03_marts.sql"
echo "→ dashboard"; "${PSQL[@]}" -f "$ROOT/sql/04_dashboard_views.sql"
echo "→ power bi";  "${PSQL[@]}" -f "$ROOT/sql/05_powerbi_views.sql"
echo "→ power bi extract"; "${PSQL[@]}" -f "$ROOT/sql/06_powerbi_extract.sql"
echo "→ checks"
checks="$("${PSQL[@]}" -v sample="${SAMPLE:-0}" -f "$ROOT/sql/analysis/00_data_quality.sql")"
echo "$checks"
if grep -q 'REVIEW' <<<"$checks"; then
    echo "Some data-quality checks say REVIEW: the load does not match the expected dataset." >&2
    exit 1
fi
echo "Done."
