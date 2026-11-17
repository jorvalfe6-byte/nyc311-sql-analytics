#!/usr/bin/env bash
# Downloads NYC 311 service requests created in one calendar year (default
# 2024) from NYC Open Data (Socrata dataset erm2-nwe9), one CSV per month.
# Public SODA API, no account or token needed. Needs Python 3 (standard
# library only). Pages of 50,000 rows, stable order by unique_key.
# Usage: ./scripts/download_data.sh [year] [destination_dir]   (default ./data)
#   SAMPLE=1  downloads only the first 2,000 requests of each month (used by CI)
#   FORCE=1   downloads again files that already exist
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
YEAR="${1:-2024}"
DEST="${2:-$ROOT/data}"
mkdir -p "$DEST"

# 'python3' on Windows can be a Microsoft Store stub: take the first one that runs
PY=""
for c in python3 python py; do
    if command -v "$c" >/dev/null 2>&1 && "$c" -c "" >/dev/null 2>&1; then PY="$c"; break; fi
done
[[ -n "$PY" ]] || { echo "Python 3 not found" >&2; exit 1; }

"$PY" -I - "$YEAR" "$DEST" "${SAMPLE:-0}" "${FORCE:-0}" <<'PY'
import csv, io, json, os, sys, time, urllib.parse, urllib.request
from concurrent.futures import ThreadPoolExecutor

year, dest, sample, force = int(sys.argv[1]), sys.argv[2], sys.argv[3] == "1", sys.argv[4] == "1"
URL = "https://data.cityofnewyork.us/resource/erm2-nwe9"
COLS = ("unique_key,created_date,closed_date,agency,agency_name,complaint_type,descriptor,"
        "location_type,incident_zip,borough,status,open_data_channel_type,latitude,longitude")
PAGE = 2000 if sample else 50000

def get(url, params):
    q = urllib.parse.urlencode(params)
    for attempt in range(1, 6):
        try:
            with urllib.request.urlopen(f"{url}?{q}", timeout=180) as r:
                return r.read()
        except OSError as e:
            if attempt == 5:
                sys.exit(f"Download failed: {e}")
            time.sleep(3 * attempt)

def month(m):
    lo = f"{year}-{m:02d}-01T00:00:00"
    hi = f"{year + (m == 12)}-{(m % 12) + 1:02d}-01T00:00:00"
    out = os.path.join(dest, f"{year}{m:02d}-nyc311.csv")
    if os.path.exists(out) and not force:
        print(f"-> {year}{m:02d} already there, skipped", flush=True)
        return
    where = f"created_date >= '{lo}' AND created_date < '{hi}'"
    expected = int(json.loads(get(URL + ".json", {"$select": "count(*)", "$where": where}))[0]["count"])
    got, offset = 0, 0
    tmp = out + ".part"
    with open(tmp, "wb") as f:
        while True:
            body = get(URL + ".csv", {"$select": COLS, "$where": where, "$order": "unique_key",
                                      "$limit": PAGE, "$offset": offset})
            rows = list(csv.reader(io.StringIO(body.decode("utf-8"))))
            n = len(rows) - 1                      # minus the header
            if offset == 0:
                f.write(body)
            elif n > 0:
                f.write(body.split(b"\n", 1)[1])   # the header only once
            got += max(n, 0)
            offset += PAGE
            if n < PAGE or sample:
                break
    os.replace(tmp, out)
    note = "" if (sample or got == expected) else f"  (WARNING: the API said {expected} at the start)"
    print(f"-> {year}{m:02d}: {got} rows{note}", flush=True)

# 4 months at a time: the API is slow per request but accepts parallel ones
with ThreadPoolExecutor(4) as ex:
    list(ex.map(month, range(1, 13)))
PY
echo "Done: 12 CSV files in $DEST"
