-- =====================================================================
-- 01_schema.sql — Relational model for NYC 311 service requests (PostgreSQL 14+)
--
-- Layers:
--   staging : 1:1 copy of the CSV files, everything TEXT. Never fails on types.
--   core    : typed model with PK, FK and CHECK. Keeps EVERY request.
--   mart    : analytical views; this is where validity rules live.
--   audit   : log of every load.
--   powerbi : star schema for Power BI (created by 05_powerbi_views.sql).
--
-- Timestamps carry no time zone (they are local to New York City), so
-- TIMESTAMP is used, not TIMESTAMPTZ.
-- =====================================================================

SET client_min_messages = warning;  -- silences the DROP ... CASCADE notices

DROP SCHEMA IF EXISTS powerbi CASCADE;
DROP SCHEMA IF EXISTS mart    CASCADE;
DROP SCHEMA IF EXISTS core    CASCADE;
DROP SCHEMA IF EXISTS staging CASCADE;
DROP SCHEMA IF EXISTS audit   CASCADE;

CREATE SCHEMA staging;
CREATE SCHEMA core;
CREATE SCHEMA mart;
CREATE SCHEMA audit;

CREATE TABLE audit.load_log (
    load_id        BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    table_name     TEXT        NOT NULL,
    rows_staged    BIGINT      NOT NULL,
    rows_loaded    BIGINT      NOT NULL,
    rows_rejected  BIGINT      GENERATED ALWAYS AS (rows_staged - rows_loaded) STORED,
    loaded_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- staging: same columns as the CSV files, all text
CREATE TABLE staging.requests (
    unique_key TEXT, created_date TEXT, closed_date TEXT,
    agency TEXT, agency_name TEXT, complaint_type TEXT, descriptor TEXT,
    location_type TEXT, incident_zip TEXT, borough TEXT, status TEXT,
    open_data_channel_type TEXT, latitude TEXT, longitude TEXT
);

-- core -----------------------------------------------------------------
CREATE TABLE core.agency (
    agency       TEXT PRIMARY KEY,
    agency_name  TEXT NOT NULL
);

CREATE TABLE core.request (
    unique_key      BIGINT    PRIMARY KEY,
    created_at      TIMESTAMP NOT NULL,
    closed_at       TIMESTAMP,
    agency          TEXT      NOT NULL REFERENCES core.agency (agency) ON DELETE RESTRICT,
    complaint_type  TEXT      NOT NULL,
    descriptor      TEXT,
    location_type   TEXT,
    incident_zip    TEXT,
    borough         TEXT      NOT NULL CHECK (borough IN ('BRONX','BROOKLYN','MANHATTAN','QUEENS','STATEN ISLAND','Unspecified')),
    status          TEXT      NOT NULL,
    channel         TEXT      NOT NULL,
    latitude        DOUBLE PRECISION CHECK (latitude  BETWEEN -90  AND 90),
    longitude       DOUBLE PRECISION CHECK (longitude BETWEEN -180 AND 180)
);
