-- ==============================================================================
-- 00_full_database_schema_and_seed.sql
-- Master Database Schema and Seed Reference for Rice Pest Monitoring System
-- Architected for PostgreSQL with PostGIS & Foreign Data Wrapper (FDW)
-- ==============================================================================

/*
DATABASE ARCHITECTURE OVERVIEW:
--------------------------------
The backend system utilizes two interconnected PostgreSQL databases:

1. `rice_pest_db2` (Authentication & Identity Service)
   - Handles user registration, verification, role assignment, and OTP auth.
   - Tables:
     * `users`: Account profiles (Farmer, Technician, Agriculturist) with coverage barangays.
     * `otps`: Time-limited one-time password security tokens with attempt throttling.

2. `rice_pest_geo` (Geospatial & Field Analytics Engine)
   - Extends PostgreSQL with PostGIS for spatial queries and hotspot density mapping.
   - Integrates `users_fdw` foreign table to read authentication records from `rice_pest_db2`.
   - Tables:
     * `scans`: Mobile geotagged sticky trap and field observation uploads with AI & review metadata.
     * `treatments`: Farmer-applied interventions linked to scans with effectiveness tracking.
     * `treatment_library`: Agriculturist-curated and approved IPM recommendation encyclopedia.
     * `level_criteria`: Economic threshold levels (LOW/MEDIUM/HIGH) per pest and crop stage.
     * `scan_reviews`: Detailed audit trail of technician validations, corrections, and referrals.
     * `notifications`: Real-time push notification queue and status alerts for mobile users.
*/

-- ==============================================================================
-- PART 1: SCHEMA DEFINITIONS FOR RICE_PEST_DB2
-- ==============================================================================

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'user') THEN
        CREATE ROLE "user" LOGIN PASSWORD '7789';
    END IF;
END $$;
ALTER ROLE "user" WITH PASSWORD '7789';

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

GRANT USAGE ON SCHEMA public TO "user";
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO "user";
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO "user";


-- ==============================================================================
-- PART 2: SCHEMA DEFINITIONS FOR RICE_PEST_GEO
-- ==============================================================================

CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS postgres_fdw;

CREATE TABLE IF NOT EXISTS scans (
    id SERIAL PRIMARY KEY,
    user_email VARCHAR(255) NOT NULL,
    image_filename VARCHAR(255) NOT NULL,
    notes TEXT DEFAULT '',
    geom GEOMETRY(Point, 4326),
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
    land_type VARCHAR(30) NOT NULL DEFAULT '',  -- upland | rainfed_lowland | irrigated_lowland ('' = before 011)
    elevation_m REAL
);

CREATE INDEX IF NOT EXISTS idx_scans_geom ON scans USING GIST(geom);
CREATE INDEX IF NOT EXISTS idx_scans_validation ON scans(validation_status);
CREATE INDEX IF NOT EXISTS idx_scans_email ON scans(user_email);
CREATE INDEX IF NOT EXISTS idx_scans_queue ON scans(validation_status, report_type, municipality, created_at);

CREATE TABLE IF NOT EXISTS treatment_library (
    id SERIAL PRIMARY KEY,
    pest VARCHAR(100) NOT NULL,
    title VARCHAR(200) NOT NULL,
    recommendation TEXT NOT NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'draft',
    option_type VARCHAR(20) NOT NULL DEFAULT 'cultural',
    crop_stages TEXT[] NOT NULL DEFAULT '{}',
    levels TEXT[] NOT NULL DEFAULT '{}',
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
    option_type VARCHAR(20) NOT NULL DEFAULT 'own',
    follow_up_due DATE,
    recommend_again BOOLEAN NOT NULL DEFAULT FALSE,
    recommend_again_by VARCHAR(255),
    follow_up_set_by VARCHAR(255)
);

CREATE INDEX IF NOT EXISTS idx_treatments_scan_id ON treatments(scan_id);

CREATE TABLE IF NOT EXISTS level_criteria (
    id SERIAL PRIMARY KEY,
    pest VARCHAR(50) NOT NULL,
    crop_stage VARCHAR(20) NOT NULL DEFAULT '',
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

GRANT USAGE ON SCHEMA public TO "user";
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO "user";
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO "user";
