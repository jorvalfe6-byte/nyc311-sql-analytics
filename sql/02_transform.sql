-- =====================================================================
-- 02_transform.sql — staging → core, in a single transaction.
-- Idempotent: empties core and reloads it. Every table leaves a row in
-- audit.load_log (rows read vs. rows loaded).
--
-- Cleaning decisions (all counted, none silent):
--   * Duplicated unique_key rows would be collapsed to one (the check
--     expects 0: the API returns each request once).
--   * Empty strings become NULL. closed_date is NULL while a request is open.
--   * Timestamps are truncated to the second.
--   * An empty borough becomes 'Unspecified' (the city's own label).
--   * Nothing is dropped for being implausible (closed before created, bad
--     ZIP, no coordinates): the mart flags those, core keeps the raw fact.
-- =====================================================================
\set ON_ERROR_STOP on

BEGIN;

TRUNCATE core.request, core.agency CASCADE;
SET LOCAL work_mem = '256MB';

INSERT INTO core.agency (agency, agency_name)
SELECT agency, MODE() WITHIN GROUP (ORDER BY TRIM(agency_name) COLLATE "C")   -- fixed collation: ties must not depend on the server locale
FROM staging.requests
WHERE NULLIF(TRIM(agency), '') IS NOT NULL
GROUP BY agency;

INSERT INTO audit.load_log (table_name, rows_staged, rows_loaded)
SELECT 'core.agency',
       (SELECT COUNT(DISTINCT agency) FROM staging.requests),
       (SELECT COUNT(*) FROM core.agency);

INSERT INTO core.request (unique_key, created_at, closed_at, agency, complaint_type, descriptor,
                          location_type, incident_zip, borough, status, channel, latitude, longitude)
SELECT DISTINCT ON (unique_key::BIGINT)
       unique_key::BIGINT,
       DATE_TRUNC('second', created_date::TIMESTAMP),
       DATE_TRUNC('second', NULLIF(closed_date, '')::TIMESTAMP),
       agency,
       TRIM(complaint_type),
       NULLIF(TRIM(descriptor), ''),
       NULLIF(TRIM(location_type), ''),
       NULLIF(TRIM(incident_zip), ''),
       COALESCE(NULLIF(TRIM(borough), ''), 'Unspecified'),
       status,
       open_data_channel_type,
       NULLIF(latitude,  '')::DOUBLE PRECISION,
       NULLIF(longitude, '')::DOUBLE PRECISION
FROM staging.requests
ORDER BY unique_key::BIGINT, created_date;

INSERT INTO audit.load_log (table_name, rows_staged, rows_loaded)
SELECT 'core.request', (SELECT COUNT(*) FROM staging.requests), (SELECT COUNT(*) FROM core.request);

COMMIT;

CREATE INDEX IF NOT EXISTS ix_request_created_at ON core.request (created_at);
CREATE INDEX IF NOT EXISTS ix_request_agency     ON core.request (agency);

ANALYZE;
