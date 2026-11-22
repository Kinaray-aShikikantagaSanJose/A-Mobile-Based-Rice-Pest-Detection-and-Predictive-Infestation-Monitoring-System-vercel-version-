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
-- old sql/0xx files need to be run on Supabase. Section 2026-11 at the end
-- adds languages, activity logs, record deletion (RLS), AI "no pests found"
-- results and the Antique province/municipality/barangay tables.
--
-- Safe to run again (everything is IF NOT EXISTS / idempotent), including on
-- a database where an older version of this file already ran.
-- After it, run:
--   supabase/02_antique_locations.sql   (18 municipalities, 590 barangays)
--   SQL/01_level_criteria_data.sql      (fresh database only)
--   SQL/02_treatment_library_data.sql   (fresh database only)
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
-- Created here only on a fresh database; the 2026-11 section below redefines
-- it with the newer columns (re-running the old column list would fail with
-- "cannot drop columns from view").
DO $$
BEGIN
    IF to_regclass('public.users_fdw') IS NULL THEN
        CREATE VIEW users_fdw WITH (security_invoker = true) AS
        SELECT id, email, password_hash, full_name, role, region, barangay, phone,
               is_verified, status, coverage_barangays, reviewed_by, reviewed_at,
               avatar_path, created_at
        FROM users;
    END IF;
END
$$;

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

-- ==============================================================================
-- 2026-11 update
--   A. Language preference (English / Filipino / Kinaray-a)
--   B. Antique locations: provinces, municipalities, barangays (PSGC + PostGIS)
--   C. AI pest detection results ("no_pests_found" etc.)
--   D. Role permissions and record deletion (row level security)
--   E. User sessions and activity logs
-- Every statement is idempotent. Nothing here deletes existing data.
-- ==============================================================================

-- ------------------------------------------------------------------------------
-- A. Language preference
-- ------------------------------------------------------------------------------
-- en = English, fil = Filipino, krj = Kinaray-a (ISO 639-3). The apps keep the
-- choice on the device too, so it also works offline and before signing in.
ALTER TABLE users ADD COLUMN IF NOT EXISTS preferred_language VARCHAR(5) NOT NULL DEFAULT 'en';

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'users_language_chk') THEN
        ALTER TABLE users ADD CONSTRAINT users_language_chk
            CHECK (preferred_language IN ('en', 'fil', 'krj'));
    END IF;
END
$$;

-- ------------------------------------------------------------------------------
-- B. Antique locations (PSGC codes are 10-digit strings, e.g. 0600616001)
-- ------------------------------------------------------------------------------
-- Filled by supabase/02_antique_locations.sql (generated from the merged
-- GeoJSON, supabase/antique_barangays.geojson). The apps do their GPS lookups
-- offline from the same GeoJSON; these tables let the database answer the same
-- question (palay_locate) and join reports to official codes.
CREATE TABLE IF NOT EXISTS provinces (
    psgc CHAR(10) PRIMARY KEY CHECK (psgc ~ '^[0-9]{10}$'),
    name VARCHAR(100) NOT NULL,
    region_psgc CHAR(10) NOT NULL CHECK (region_psgc ~ '^[0-9]{10}$'),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS municipalities (
    psgc CHAR(10) PRIMARY KEY CHECK (psgc ~ '^[0-9]{10}$'),
    name VARCHAR(100) NOT NULL,
    province_psgc CHAR(10) NOT NULL REFERENCES provinces(psgc) ON DELETE CASCADE,
    geom extensions.GEOMETRY(MultiPolygon, 4326),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS barangays (
    psgc CHAR(10) PRIMARY KEY CHECK (psgc ~ '^[0-9]{10}$'),
    name VARCHAR(150) NOT NULL,
    municipality_psgc CHAR(10) NOT NULL REFERENCES municipalities(psgc) ON DELETE CASCADE,
    geom extensions.GEOMETRY(MultiPolygon, 4326) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_municipalities_name ON municipalities(province_psgc, lower(name));
CREATE INDEX IF NOT EXISTS idx_municipalities_geom ON municipalities USING GIST(geom);
-- Barangay names repeat across municipalities ("Poblacion"), never within one.
CREATE UNIQUE INDEX IF NOT EXISTS idx_barangays_name ON barangays(municipality_psgc, lower(name));
CREATE INDEX IF NOT EXISTS idx_barangays_geom ON barangays USING GIST(geom);

-- The barangay at a GPS point (no row when it is outside Antique).
-- The source maps are simplified one municipality at a time, so along
-- municipal borders neighbouring polygons overlap slightly or leave thin gaps:
--   * inside several polygons -> the one the point is deepest inside;
--   * inside none, but within p_max_gap_m metres of one -> that nearest one,
--     with match_type 'nearest' (the apps ask the person to confirm it).
-- Same rules as the apps' offline lookup and the API (app/geo.py).
DROP FUNCTION IF EXISTS palay_locate(DOUBLE PRECISION, DOUBLE PRECISION);
DROP FUNCTION IF EXISTS palay_locate(DOUBLE PRECISION, DOUBLE PRECISION, DOUBLE PRECISION);
CREATE FUNCTION palay_locate(p_lat DOUBLE PRECISION, p_lng DOUBLE PRECISION,
                             p_max_gap_m DOUBLE PRECISION DEFAULT 300)
RETURNS TABLE (barangay_psgc CHAR(10), barangay VARCHAR, municipality_psgc CHAR(10),
               municipality VARCHAR, province_psgc CHAR(10), match_type TEXT,
               distance_m DOUBLE PRECISION)
LANGUAGE sql STABLE
SET search_path = public, extensions, pg_temp
AS $$
    WITH pt AS (
        SELECT ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326) AS g
        WHERE p_lat BETWEEN -90 AND 90 AND p_lng BETWEEN -180 AND 180
    ),
    inside AS (
        SELECT b.psgc, b.name, m.psgc AS m_psgc, m.name AS m_name, m.province_psgc,
               'inside'::TEXT AS match_type, 0::DOUBLE PRECISION AS distance_m
        FROM pt, barangays b
        JOIN municipalities m ON m.psgc = b.municipality_psgc
        WHERE ST_Covers(b.geom, pt.g)
        ORDER BY ST_Distance(ST_Boundary(b.geom), pt.g) DESC, b.psgc
        LIMIT 1
    ),
    nearest AS (
        SELECT b.psgc, b.name, m.psgc AS m_psgc, m.name AS m_name, m.province_psgc,
               'nearest'::TEXT AS match_type,
               ST_Distance(b.geom::geography, pt.g::geography) AS distance_m
        FROM pt, barangays b
        JOIN municipalities m ON m.psgc = b.municipality_psgc
        WHERE NOT EXISTS (SELECT 1 FROM inside)
          AND b.geom && ST_Expand(pt.g, 0.02)
          AND ST_DWithin(b.geom::geography, pt.g::geography, p_max_gap_m)
        ORDER BY distance_m, b.psgc
        LIMIT 1
    )
    SELECT psgc, name, m_psgc, m_name, province_psgc, match_type, distance_m FROM inside
    UNION ALL
    SELECT psgc, name, m_psgc, m_name, province_psgc, match_type, distance_m FROM nearest
$$;

-- Where a person lives / farms, as official codes. The names stay in
-- users.region (municipality) and users.barangay, which the API already uses.
-- location_source: 'manual' (typed or picked) or 'gps' (found from the phone's
-- location and confirmed by the person). No foreign key on purpose: an account
-- must still save if 02_antique_locations.sql has not been run yet.
ALTER TABLE users ADD COLUMN IF NOT EXISTS municipality_psgc VARCHAR(10);
ALTER TABLE users ADD COLUMN IF NOT EXISTS barangay_psgc VARCHAR(10);
ALTER TABLE users ADD COLUMN IF NOT EXISTS location_source VARCHAR(10) NOT NULL DEFAULT 'manual';
ALTER TABLE users ADD COLUMN IF NOT EXISTS location_updated_at TIMESTAMPTZ;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'users_location_source_chk') THEN
        ALTER TABLE users ADD CONSTRAINT users_location_source_chk
            CHECK (location_source IN ('manual', 'gps'));
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'users_psgc_chk') THEN
        ALTER TABLE users ADD CONSTRAINT users_psgc_chk
            CHECK ((municipality_psgc IS NULL OR municipality_psgc ~ '^[0-9]{10}$')
               AND (barangay_psgc IS NULL OR barangay_psgc ~ '^[0-9]{10}$'));
    END IF;
END
$$;

CREATE INDEX IF NOT EXISTS idx_users_barangay_psgc ON users(barangay_psgc);

-- Where an observation's GPS point falls (found by the API from the same
-- GeoJSON). scans.municipality / scans.barangay keep the submitter's saved
-- area and are never overwritten by GPS.
--   location_status: 'inside' (in an Antique barangay), 'outside_antique',
--   'no_gps' (no location sent) or '' (recorded before this update).
ALTER TABLE scans ADD COLUMN IF NOT EXISTS gps_barangay_psgc VARCHAR(10);
ALTER TABLE scans ADD COLUMN IF NOT EXISTS gps_municipality_psgc VARCHAR(10);
ALTER TABLE scans ADD COLUMN IF NOT EXISTS gps_accuracy_m REAL;
ALTER TABLE scans ADD COLUMN IF NOT EXISTS location_status VARCHAR(20) NOT NULL DEFAULT '';

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'scans_location_status_chk') THEN
        ALTER TABLE scans ADD CONSTRAINT scans_location_status_chk
            CHECK (location_status IN ('', 'inside', 'outside_antique', 'no_gps'));
    END IF;
END
$$;

CREATE INDEX IF NOT EXISTS idx_scans_gps_barangay ON scans(gps_barangay_psgc);

-- users_fdw (the view the API reads accounts through) gains the new columns.
-- New columns go at the end so CREATE OR REPLACE VIEW keeps working.
CREATE OR REPLACE VIEW users_fdw WITH (security_invoker = true) AS
SELECT id, email, password_hash, full_name, role, region, barangay, phone,
       is_verified, status, coverage_barangays, reviewed_by, reviewed_at,
       avatar_path, created_at, preferred_language, municipality_psgc, barangay_psgc
FROM users;

-- ------------------------------------------------------------------------------
-- C. AI pest detection results
-- ------------------------------------------------------------------------------
-- detection_result:
--   pests_found     the model named a pest
--   no_pests_found  the model ran on a clear photo and confidently found no
--                   insect at all; the photo is then deleted from Storage
--                   (image_deleted_at) and the observation is closed with
--                   validation_status 'no_pests'
--   uncertain       possible insects, or the photo was too dark/blurry to judge
--   failed          the model could not run
--   skipped         disease reports (no model) and older records
-- Failed or uncertain results are never treated as pest-free.
-- detection_metadata: model file, thresholds, highest score seen, photo size
-- and quality measurements, and when/whether the photo was deleted.
ALTER TABLE scans ADD COLUMN IF NOT EXISTS detection_result VARCHAR(20) NOT NULL DEFAULT '';
ALTER TABLE scans ADD COLUMN IF NOT EXISTS detection_metadata JSONB NOT NULL DEFAULT '{}';
ALTER TABLE scans ADD COLUMN IF NOT EXISTS image_deleted_at TIMESTAMPTZ;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'scans_detection_result_chk') THEN
        ALTER TABLE scans ADD CONSTRAINT scans_detection_result_chk
            CHECK (detection_result IN ('', 'pests_found', 'no_pests_found', 'uncertain', 'failed', 'skipped'));
    END IF;
    -- NOT VALID: checks new and changed rows without failing on old data.
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'scans_validation_status_chk') THEN
        ALTER TABLE scans ADD CONSTRAINT scans_validation_status_chk
            CHECK (validation_status IN ('pending', 'validated', 'returned', 'escalated', 'no_pests')) NOT VALID;
    END IF;
END
$$;

-- Older records get the matching result once.
UPDATE scans SET detection_result = CASE
        WHEN report_type <> 'pest' OR ai_status = 'skipped' THEN 'skipped'
        WHEN ai_status = 'failed' THEN 'failed'
        WHEN ai_pest IS NOT NULL THEN 'pests_found'
        ELSE 'uncertain'
    END
WHERE detection_result = '';

CREATE INDEX IF NOT EXISTS idx_scans_detection_result ON scans(detection_result);

-- ------------------------------------------------------------------------------
-- D. Role permissions and record deletion
-- ------------------------------------------------------------------------------
-- Which role may do what. The API reads this table (and falls back to the same
-- defaults when it is missing); the delete policy below checks it too.
CREATE TABLE IF NOT EXISTS role_permissions (
    role VARCHAR(20) NOT NULL,
    permission VARCHAR(50) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (role, permission),
    CONSTRAINT role_permissions_role_chk CHECK (role IN ('farmer', 'technician', 'agriculturist'))
);

-- records.delete: agriculturists (anywhere) and agricultural technicians
-- (their coverage area and their own submissions). Farmers never delete.
INSERT INTO role_permissions (role, permission) VALUES
    ('agriculturist', 'records.delete'),
    ('technician', 'records.delete'),
    ('agriculturist', 'activity_logs.view')
ON CONFLICT DO NOTHING;

-- A copy of every deleted observation (who, when, why, and the main fields),
-- so the deletion can be audited and the apps can tell "deleted" from "never
-- existed". The photo itself is removed from Storage by the API.
CREATE TABLE IF NOT EXISTS deleted_records (
    scan_id INTEGER PRIMARY KEY,
    owner_email VARCHAR(255) NOT NULL,
    deleted_by VARCHAR(255) NOT NULL,
    deleted_by_role VARCHAR(20) NOT NULL,
    reason TEXT NOT NULL DEFAULT '',
    image_filename VARCHAR(255),
    snapshot JSONB NOT NULL DEFAULT '{}',
    deleted_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_deleted_records_owner ON deleted_records(owner_email, deleted_at DESC);

-- palay_rls_actor: a role without login and without BYPASSRLS. For a deletion
-- the API (connected as postgres) runs, inside one transaction:
--     SET LOCAL ROLE palay_rls_actor;
--     SELECT set_config('app.actor_email', '<signed-in email>', true);
--     DELETE FROM scans WHERE id = ... RETURNING ...;
--     RESET ROLE;
-- so the policies below decide in the database itself whether that account
-- may delete that row (on top of the API's own checks). Everything is
-- transaction-local, so it works with Supabase's transaction pooler.
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'palay_rls_actor') THEN
        CREATE ROLE palay_rls_actor NOLOGIN NOINHERIT;
    END IF;
END
$$;

-- The API's database user must be allowed to switch to the role.
GRANT palay_rls_actor TO postgres;
GRANT USAGE ON SCHEMA public TO palay_rls_actor;
GRANT SELECT, DELETE ON scans TO palay_rls_actor;

-- The signed-in account the API is acting for (set per transaction).
CREATE OR REPLACE FUNCTION palay_actor_email()
RETURNS TEXT
LANGUAGE sql STABLE
SET search_path = pg_catalog, pg_temp
AS $$
    SELECT lower(NULLIF(btrim(current_setting('app.actor_email', true)), ''))
$$;

-- True when the acting account may delete an observation with this area and
-- owner. SECURITY DEFINER: it reads users and role_permissions, which the
-- actor role cannot read itself. Same rules as the API:
--   * the account exists, is verified and approved;
--   * its role has 'records.delete' in role_permissions;
--   * agriculturists: any observation;
--   * technicians: their own submissions, and observations in their
--     municipality (and covered barangays, if any are set), using the
--     submitter's saved area when the observation has none.
CREATE OR REPLACE FUNCTION palay_can_delete_scan(p_municipality TEXT, p_barangay TEXT, p_owner_email TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    actor RECORD;
    v_area TEXT;
    v_brgy TEXT;
    v_cover TEXT[];
BEGIN
    SELECT email, role, status, is_verified, region, coverage_barangays
      INTO actor
      FROM users
     WHERE email = palay_actor_email();
    IF NOT FOUND OR actor.status <> 'approved' OR NOT actor.is_verified THEN
        RETURN FALSE;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM role_permissions
                   WHERE role = actor.role AND permission = 'records.delete') THEN
        RETURN FALSE;
    END IF;
    IF actor.role = 'agriculturist' THEN
        RETURN TRUE;
    END IF;
    IF actor.role <> 'technician' THEN
        RETURN FALSE;
    END IF;
    IF lower(p_owner_email) = actor.email THEN
        RETURN TRUE;
    END IF;
    SELECT COALESCE(NULLIF(btrim(p_municipality), ''), btrim(u.region), ''),
           COALESCE(NULLIF(btrim(p_barangay), ''), btrim(u.barangay), '')
      INTO v_area, v_brgy
      FROM (SELECT 1) one
      LEFT JOIN users u ON u.email = p_owner_email;
    IF btrim(COALESCE(actor.region, '')) = '' OR lower(v_area) <> lower(btrim(actor.region)) THEN
        RETURN FALSE;
    END IF;
    v_cover := ARRAY(SELECT lower(btrim(b))
                     FROM unnest(string_to_array(COALESCE(actor.coverage_barangays, ''), ',')) AS b
                     WHERE btrim(b) <> '');
    RETURN cardinality(v_cover) = 0 OR lower(v_brgy) = ANY (v_cover);
END
$$;

REVOKE ALL ON FUNCTION palay_can_delete_scan(TEXT, TEXT, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION palay_actor_email() FROM PUBLIC;
REVOKE ALL ON FUNCTION palay_locate(DOUBLE PRECISION, DOUBLE PRECISION, DOUBLE PRECISION) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION palay_can_delete_scan(TEXT, TEXT, TEXT) TO palay_rls_actor;
GRANT EXECUTE ON FUNCTION palay_actor_email() TO palay_rls_actor;

-- Supabase grants new functions to its REST API roles by default; these are
-- not meant for the REST API.
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
        REVOKE ALL ON FUNCTION palay_can_delete_scan(TEXT, TEXT, TEXT) FROM anon, authenticated;
        REVOKE ALL ON FUNCTION palay_actor_email() FROM anon, authenticated;
        REVOKE ALL ON FUNCTION palay_locate(DOUBLE PRECISION, DOUBLE PRECISION, DOUBLE PRECISION)
            FROM anon, authenticated;
    END IF;
END
$$;

-- The actor role sees and deletes only the rows it is allowed to delete.
-- (anon and authenticated still have no policy at all: no access.)
DROP POLICY IF EXISTS scans_actor_select ON scans;
CREATE POLICY scans_actor_select ON scans
    FOR SELECT TO palay_rls_actor
    USING (palay_can_delete_scan(municipality, barangay, user_email));

DROP POLICY IF EXISTS scans_actor_delete ON scans;
CREATE POLICY scans_actor_delete ON scans
    FOR DELETE TO palay_rls_actor
    USING (palay_can_delete_scan(municipality, barangay, user_email));

-- ------------------------------------------------------------------------------
-- E. User sessions and activity logs
-- ------------------------------------------------------------------------------
-- One row per sign-in. The API puts the session id in the tokens it issues,
-- moves last_seen_at forward while the session is used (at most every few
-- minutes) and closes the row on sign-out. Status shown on the dashboard:
--   ended   = signed out (ended_at set)
--   expired = not used for longer than the refresh token lasts
--   active  = otherwise
CREATE TABLE IF NOT EXISTS user_sessions (
    id UUID PRIMARY KEY,
    user_id INTEGER REFERENCES users(id) ON DELETE SET NULL,
    user_email VARCHAR(255) NOT NULL,
    user_role VARCHAR(20) NOT NULL DEFAULT '',
    client VARCHAR(20) NOT NULL DEFAULT '',          -- mobile | web | dashboard
    ip_address VARCHAR(64) NOT NULL DEFAULT '',
    user_agent VARCHAR(300) NOT NULL DEFAULT '',
    started_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_seen_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    ended_at TIMESTAMPTZ,
    end_reason VARCHAR(20),
    request_count INTEGER NOT NULL DEFAULT 0,
    CONSTRAINT user_sessions_end_reason_chk
        CHECK (end_reason IS NULL OR end_reason IN ('logout', 'expired', 'revoked', 'account_deleted'))
);

CREATE INDEX IF NOT EXISTS idx_user_sessions_email ON user_sessions(user_email, started_at DESC);
CREATE INDEX IF NOT EXISTS idx_user_sessions_open ON user_sessions(last_seen_at) WHERE ended_at IS NULL;

-- Sign-ins (also failed ones), sign-outs and important actions: observations
-- sent, reviews, deletions, profile and language changes, account changes made
-- on the dashboard, report exports. details holds action-specific data (never
-- passwords or codes).
CREATE TABLE IF NOT EXISTS user_activity_logs (
    id BIGSERIAL PRIMARY KEY,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    user_id INTEGER REFERENCES users(id) ON DELETE SET NULL,
    user_email VARCHAR(255) NOT NULL DEFAULT '',
    user_name VARCHAR(255) NOT NULL DEFAULT '',
    user_role VARCHAR(20) NOT NULL DEFAULT '',
    session_id UUID REFERENCES user_sessions(id) ON DELETE SET NULL,
    action_type VARCHAR(40) NOT NULL,
    target_type VARCHAR(30) NOT NULL DEFAULT '',
    target_id VARCHAR(64) NOT NULL DEFAULT '',
    outcome VARCHAR(10) NOT NULL DEFAULT 'success',
    client VARCHAR(20) NOT NULL DEFAULT '',
    ip_address VARCHAR(64) NOT NULL DEFAULT '',
    user_agent VARCHAR(300) NOT NULL DEFAULT '',
    details JSONB NOT NULL DEFAULT '{}',
    CONSTRAINT user_activity_outcome_chk CHECK (outcome IN ('success', 'failure'))
);

CREATE INDEX IF NOT EXISTS idx_activity_created ON user_activity_logs(created_at DESC, id DESC);
CREATE INDEX IF NOT EXISTS idx_activity_email ON user_activity_logs(user_email, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_activity_role ON user_activity_logs(user_role, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_activity_action ON user_activity_logs(action_type, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_activity_session ON user_activity_logs(session_id);

-- ------------------------------------------------------------------------------
-- Security for the new tables: same rule as above (RLS on, no policies for the
-- REST API roles; the API connects as postgres).
-- ------------------------------------------------------------------------------
ALTER TABLE provinces ENABLE ROW LEVEL SECURITY;
ALTER TABLE municipalities ENABLE ROW LEVEL SECURITY;
ALTER TABLE barangays ENABLE ROW LEVEL SECURITY;
ALTER TABLE role_permissions ENABLE ROW LEVEL SECURITY;
ALTER TABLE deleted_records ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_activity_logs ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
        REVOKE ALL ON provinces, municipalities, barangays, role_permissions, deleted_records,
                      user_sessions, user_activity_logs, users_fdw
            FROM anon, authenticated;
        REVOKE ALL ON SEQUENCE user_activity_logs_id_seq FROM anon, authenticated;
    END IF;
END
$$;
