-- ==============================================================================
-- Palay Patrol - Supabase schema (run once in Supabase > SQL Editor)
-- ==============================================================================
-- The original system used two local PostgreSQL databases:
--   rice_pest_db2  (users, otps)
--   rice_pest_geo  (scans, treatments, ... + users_fdw, a postgres_fdw foreign
--                   table that read rice_pest_db2.users)
-- A Supabase project has one database, so both sets of tables live together
-- in the public schema here, and users_fdw becomes a plain view of users. The
-- API code keeps using the name users_fdw unchanged.
--
-- This file already contains every migration up to
-- rice-pest-api/sql/011_land_type_and_treatment_feedback.sql, so none of the
-- old sql/0xx files need to be run on Supabase.
--
-- Safe to run again (everything is IF NOT EXISTS / idempotent).
-- After it, run the reference data:
--   SQL/01_level_criteria_data.sql
--   SQL/02_treatment_library_data.sql
-- and optionally the demo data (SQL/03_..., SQL/04_...).
-- ==============================================================================

-- Dates and "today" follow the farmers' local time (the API also sets this per
-- connection; this covers Supabase's transaction pooler and the SQL editor).
ALTER DATABASE postgres SET timezone TO 'Asia/Manila';

-- PostGIS lives in Supabase's "extensions" schema, which is on the default
-- search_path, so geometry / ST_* resolve without a schema prefix.
CREATE EXTENSION IF NOT EXISTS postgis WITH SCHEMA extensions;

-- ------------------------------------------------------------------------------
-- Accounts (was rice_pest_db2)
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS users (
    id SERIAL PRIMARY KEY,
    email VARCHAR(255) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    full_name VARCHAR(255) NOT NULL,
    role VARCHAR(50) NOT NULL DEFAULT 'farmer',
    region VARCHAR(100),
    barangay VARCHAR(100) NOT NULL DEFAULT '',
    phone VARCHAR(30) NOT NULL DEFAULT '',
    is_verified BOOLEAN NOT NULL DEFAULT FALSE,
    status VARCHAR(20) NOT NULL DEFAULT 'pending',
    coverage_barangays TEXT NOT NULL DEFAULT '',
    reviewed_by VARCHAR(255),
    reviewed_at TIMESTAMPTZ,
    avatar_path VARCHAR(255),
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'users_status_chk') THEN
        ALTER TABLE users ADD CONSTRAINT users_status_chk
            CHECK (status IN ('pending', 'approved', 'rejected'));
    END IF;
END
$$;

CREATE INDEX IF NOT EXISTS idx_users_email ON users(email);
CREATE INDEX IF NOT EXISTS idx_users_role_status ON users(role, status);

CREATE TABLE IF NOT EXISTS otps (
    id SERIAL PRIMARY KEY,
    email VARCHAR(255) NOT NULL,
    otp_code VARCHAR(10) NOT NULL,
    expires_at TIMESTAMPTZ NOT NULL,
    attempts INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_otps_email ON otps(email);

-- Was a postgres_fdw foreign table pointing at rice_pest_db2.users.
-- security_invoker: the view obeys the permissions of whoever queries it.
CREATE OR REPLACE VIEW users_fdw WITH (security_invoker = true) AS
SELECT id, email, password_hash, full_name, role, region, barangay, phone,
       is_verified, status, coverage_barangays, reviewed_by, reviewed_at,
       avatar_path, created_at
FROM users;

-- ------------------------------------------------------------------------------
-- Observations and field data (was rice_pest_geo)
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS scans (
    id SERIAL PRIMARY KEY,
    user_email VARCHAR(255) NOT NULL,
    image_filename VARCHAR(255) NOT NULL,          -- object key in the "scans" storage bucket
    notes TEXT DEFAULT '',
    geom extensions.GEOMETRY(Point, 4326),
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    total_count INTEGER NOT NULL DEFAULT 0,
    dominant_class VARCHAR(100) NOT NULL DEFAULT '',
    density REAL NOT NULL DEFAULT 0,
    severity VARCHAR(20) NOT NULL DEFAULT '',
    crop_phase VARCHAR(50) NOT NULL DEFAULT '',
    symptoms TEXT NOT NULL DEFAULT '',
    trap_type VARCHAR(50) NOT NULL DEFAULT '',
    monitoring_method TEXT NOT NULL DEFAULT '',
    target_pest TEXT NOT NULL DEFAULT '',
    target_sex TEXT NOT NULL DEFAULT '',
    diagnosis TEXT NOT NULL DEFAULT '',
    guidance TEXT NOT NULL DEFAULT '',
    validation_status VARCHAR(20) NOT NULL DEFAULT 'pending',
    corrected_count INTEGER,
    validated_by VARCHAR(255),
    validated_at TIMESTAMPTZ,
    client_uuid VARCHAR(64),
    report_type VARCHAR(10) NOT NULL DEFAULT 'pest',
    municipality VARCHAR(100) NOT NULL DEFAULT '',
    barangay VARCHAR(100) NOT NULL DEFAULT '',
    submitted_by_role VARCHAR(20) NOT NULL DEFAULT 'farmer',
    ai_status VARCHAR(10) NOT NULL DEFAULT 'skipped',
    ai_pest VARCHAR(50),
    ai_confidence REAL,
    ai_count INTEGER,
    ai_countable BOOLEAN NOT NULL DEFAULT FALSE,
    ai_detections JSONB NOT NULL DEFAULT '[]',
    ai_message TEXT NOT NULL DEFAULT '',
    confirmed_pest VARCHAR(50),
    confirmed_count INTEGER,
    countable BOOLEAN,
    infestation_level VARCHAR(10),
    suggested_level VARCHAR(10),
    damage_indicators TEXT[] NOT NULL DEFAULT '{}',
    return_reason TEXT NOT NULL DEFAULT '',
    escalation_reason TEXT NOT NULL DEFAULT '',
    follow_up_of INTEGER,
    resubmission_of INTEGER,
    land_type VARCHAR(30) NOT NULL DEFAULT '',  -- upland | rainfed_lowland | irrigated_lowland
    elevation_m REAL
);

CREATE INDEX IF NOT EXISTS idx_scans_geom ON scans USING GIST(geom);
CREATE INDEX IF NOT EXISTS idx_scans_validation ON scans(validation_status);
CREATE INDEX IF NOT EXISTS idx_scans_email ON scans(user_email);
CREATE INDEX IF NOT EXISTS idx_scans_queue ON scans(validation_status, report_type, municipality, created_at);
-- A retried upload (slow signal) must not create a second observation.
CREATE UNIQUE INDEX IF NOT EXISTS idx_scans_client_uuid ON scans(client_uuid) WHERE client_uuid IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_scans_follow_up_of ON scans(follow_up_of);
CREATE INDEX IF NOT EXISTS idx_scans_resubmission_of ON scans(resubmission_of);

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'scans_land_type_chk') THEN
        ALTER TABLE scans ADD CONSTRAINT scans_land_type_chk
            CHECK (land_type IN ('', 'upland', 'rainfed_lowland', 'irrigated_lowland'));
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'scans_resubmission_fk') THEN
        ALTER TABLE scans ADD CONSTRAINT scans_resubmission_fk
            FOREIGN KEY (resubmission_of) REFERENCES scans(id) ON DELETE SET NULL;
    END IF;
END
$$;

CREATE TABLE IF NOT EXISTS treatment_library (
    id SERIAL PRIMARY KEY,
    pest VARCHAR(100) NOT NULL,
    title VARCHAR(200) NOT NULL,
    recommendation TEXT NOT NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'draft',
    option_type VARCHAR(20) NOT NULL DEFAULT 'cultural',
    crop_stages TEXT[] NOT NULL DEFAULT '{}',   -- empty = every stage
    levels TEXT[] NOT NULL DEFAULT '{}',        -- empty = every level
    source_reference TEXT NOT NULL DEFAULT '',
    created_by VARCHAR(255) NOT NULL DEFAULT '',
    updated_by VARCHAR(255) NOT NULL DEFAULT '',
    approved_by VARCHAR(255),
    approved_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT treatment_library_status_chk CHECK (status IN ('draft', 'approved')),
    CONSTRAINT treatment_library_type_chk CHECK (option_type IN ('cultural', 'biological', 'ecological', 'chemical'))
);

CREATE INDEX IF NOT EXISTS idx_treatment_library_pest ON treatment_library(pest, status);

CREATE TABLE IF NOT EXISTS treatments (
    id SERIAL PRIMARY KEY,
    scan_id INTEGER NOT NULL REFERENCES scans(id) ON DELETE CASCADE,
    submitted_by VARCHAR(255) NOT NULL DEFAULT '',
    treatment TEXT NOT NULL,
    applied_at TIMESTAMPTZ NOT NULL,
    pre_count INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    client_uuid VARCHAR(64),
    library_id INTEGER REFERENCES treatment_library(id) ON DELETE SET NULL,
    option_type VARCHAR(20) NOT NULL DEFAULT 'own',  -- library type or 'own'
    follow_up_due DATE,
    recommend_again BOOLEAN NOT NULL DEFAULT FALSE,
    recommend_again_by VARCHAR(255),
    follow_up_set_by VARCHAR(255)
);

CREATE INDEX IF NOT EXISTS idx_treatments_scan_id ON treatments(scan_id);
CREATE UNIQUE INDEX IF NOT EXISTS idx_treatments_client_uuid ON treatments(client_uuid) WHERE client_uuid IS NOT NULL;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'scans_follow_up_fk') THEN
        ALTER TABLE scans ADD CONSTRAINT scans_follow_up_fk
            FOREIGN KEY (follow_up_of) REFERENCES treatments(id) ON DELETE SET NULL;
    END IF;
END
$$;

CREATE TABLE IF NOT EXISTS level_criteria (
    id SERIAL PRIMARY KEY,
    pest VARCHAR(50) NOT NULL,
    crop_stage VARCHAR(20) NOT NULL DEFAULT '',   -- '' = any stage
    medium_from REAL NOT NULL,
    high_from REAL NOT NULL,
    updated_by VARCHAR(255) NOT NULL DEFAULT '',
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT level_criteria_uq UNIQUE (pest, crop_stage),
    CONSTRAINT level_criteria_order_chk CHECK (medium_from < high_from)
);

CREATE TABLE IF NOT EXISTS scan_reviews (
    id SERIAL PRIMARY KEY,
    scan_id INTEGER NOT NULL REFERENCES scans(id) ON DELETE CASCADE,
    reviewer VARCHAR(255) NOT NULL,
    reviewer_role VARCHAR(50) NOT NULL,
    action VARCHAR(20) NOT NULL,
    corrected_count INTEGER,
    diagnosis TEXT NOT NULL DEFAULT '',
    guidance TEXT NOT NULL DEFAULT '',
    library_id INTEGER REFERENCES treatment_library(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    pest VARCHAR(50),
    countable BOOLEAN,
    level VARCHAR(10),
    indicators TEXT[] NOT NULL DEFAULT '{}',
    note TEXT NOT NULL DEFAULT ''
);

CREATE INDEX IF NOT EXISTS idx_scan_reviews_scan_id ON scan_reviews(scan_id);

CREATE TABLE IF NOT EXISTS notifications (
    id SERIAL PRIMARY KEY,
    user_email VARCHAR(255) NOT NULL,
    scan_id INTEGER REFERENCES scans(id) ON DELETE CASCADE,
    kind VARCHAR(30) NOT NULL,
    title VARCHAR(200) NOT NULL,
    body TEXT NOT NULL DEFAULT '',
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    read_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_notifications_user ON notifications(user_email, read_at);

-- ------------------------------------------------------------------------------
-- Security: keep every table private to the API
-- ------------------------------------------------------------------------------
-- Supabase publishes the public schema through its auto-generated REST API to
-- anyone holding the project's anon key. The Palay Patrol apps never use that
-- API (they talk only to the FastAPI server, which connects as postgres and is
-- not affected by these rules), so row level security is switched on with no
-- policies: the REST API can read or change nothing, e.g. no password hashes.
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE otps ENABLE ROW LEVEL SECURITY;
ALTER TABLE scans ENABLE ROW LEVEL SECURITY;
ALTER TABLE treatment_library ENABLE ROW LEVEL SECURITY;
ALTER TABLE treatments ENABLE ROW LEVEL SECURITY;
ALTER TABLE level_criteria ENABLE ROW LEVEL SECURITY;
ALTER TABLE scan_reviews ENABLE ROW LEVEL SECURITY;
ALTER TABLE notifications ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON users, otps, users_fdw, scans, treatment_library, treatments,
              level_criteria, scan_reviews, notifications
    FROM anon, authenticated;

-- ------------------------------------------------------------------------------
-- Storage: private buckets for photos (the API reads/writes them with the
-- service_role key and serves them after its own permission checks)
-- ------------------------------------------------------------------------------
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES
    ('scans',   'scans',   false, 15728640, ARRAY['image/jpeg']),
    ('avatars', 'avatars', false,  8388608, ARRAY['image/jpeg'])
ON CONFLICT (id) DO NOTHING;
