-- DrawDB visualization copy of the Rice Pest Monitoring System schema.
--
-- This file combines rice_pest_db2 and rice_pest_geo into one diagram so
-- DrawDB can display their relationships. Relationships from account/user
-- columns to users.email are logical links from the application's FDW/email
-- joins; PostgreSQL cannot enforce these foreign keys across the two
-- production databases. This diagram copy is not a production migration.
--
-- Agriculturists and technicians are users distinguished by users.role.
-- They author treatment-library entries and criteria, and review/validate
-- scans. Farmers submit scans and record applied treatments.

CREATE TABLE users (
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
    reviewed_by VARCHAR(255) REFERENCES users(email),
    reviewed_at TIMESTAMPTZ,
    avatar_path VARCHAR(255),
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE otps (
    id SERIAL PRIMARY KEY,
    email VARCHAR(255) NOT NULL,
    otp_code VARCHAR(10) NOT NULL,
    expires_at TIMESTAMPTZ NOT NULL,
    attempts INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE scans (
    id SERIAL PRIMARY KEY,
    user_email VARCHAR(255) NOT NULL REFERENCES users(email),
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
    validated_by VARCHAR(255) REFERENCES users(email),
    validated_at TIMESTAMPTZ,
    client_uuid VARCHAR(64) UNIQUE,
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
    resubmission_of INTEGER REFERENCES scans(id) ON DELETE SET NULL,
    land_type VARCHAR(30) NOT NULL DEFAULT '',
    elevation_m REAL
);

CREATE TABLE treatment_library (
    id SERIAL PRIMARY KEY,
    pest VARCHAR(100) NOT NULL,
    title VARCHAR(200) NOT NULL,
    recommendation TEXT NOT NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'draft',
    option_type VARCHAR(20) NOT NULL DEFAULT 'cultural',
    crop_stages TEXT[] NOT NULL DEFAULT '{}',
    levels TEXT[] NOT NULL DEFAULT '{}',
    source_reference TEXT NOT NULL DEFAULT '',
    created_by VARCHAR(255) REFERENCES users(email),
    updated_by VARCHAR(255) REFERENCES users(email),
    approved_by VARCHAR(255) REFERENCES users(email),
    approved_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT treatment_library_status_chk CHECK (status IN ('draft', 'approved')),
    CONSTRAINT treatment_library_type_chk CHECK (option_type IN ('cultural', 'biological', 'ecological', 'chemical'))
);

CREATE TABLE treatments (
    id SERIAL PRIMARY KEY,
    scan_id INTEGER NOT NULL REFERENCES scans(id) ON DELETE CASCADE,
    submitted_by VARCHAR(255) REFERENCES users(email),
    treatment TEXT NOT NULL,
    applied_at TIMESTAMPTZ NOT NULL,
    pre_count INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    client_uuid VARCHAR(64) UNIQUE,
    library_id INTEGER REFERENCES treatment_library(id) ON DELETE SET NULL,
    option_type VARCHAR(20) NOT NULL DEFAULT 'own',
    follow_up_due DATE,
    recommend_again BOOLEAN NOT NULL DEFAULT FALSE,
    recommend_again_by VARCHAR(255),
    follow_up_set_by VARCHAR(255)
);

CREATE TABLE level_criteria (
    id SERIAL PRIMARY KEY,
    pest VARCHAR(50) NOT NULL,
    crop_stage VARCHAR(20) NOT NULL DEFAULT '',
    medium_from REAL NOT NULL,
    high_from REAL NOT NULL,
    updated_by VARCHAR(255) REFERENCES users(email),
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT level_criteria_uq UNIQUE (pest, crop_stage),
    CONSTRAINT level_criteria_order_chk CHECK (medium_from < high_from)
);

CREATE TABLE scan_reviews (
    id SERIAL PRIMARY KEY,
    scan_id INTEGER NOT NULL REFERENCES scans(id) ON DELETE CASCADE,
    reviewer VARCHAR(255) NOT NULL REFERENCES users(email),
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

CREATE TABLE notifications (
    id SERIAL PRIMARY KEY,
    user_email VARCHAR(255) NOT NULL REFERENCES users(email),
    scan_id INTEGER REFERENCES scans(id) ON DELETE CASCADE,
    kind VARCHAR(30) NOT NULL,
    title VARCHAR(200) NOT NULL,
    body TEXT NOT NULL DEFAULT '',
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    read_at TIMESTAMPTZ
);

ALTER TABLE scans
    ADD CONSTRAINT scans_follow_up_fk
    FOREIGN KEY (follow_up_of) REFERENCES treatments(id) ON DELETE SET NULL;
