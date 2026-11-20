-- =====================================================
-- 007: web dashboard features  -  run on rice_pest_geo as postgres
-- =====================================================
-- Treatment reference library, infestation criteria (LOW/MEDIUM/HIGH
-- thresholds), per-scan review history, and farmer guidance on scans.
-- Run BEFORE restarting the API: /sync/scans/{id}/validate now writes to
-- scan_reviews. Safe to run more than once.

ALTER TABLE scans ADD COLUMN IF NOT EXISTS guidance TEXT NOT NULL DEFAULT '';

CREATE TABLE IF NOT EXISTS treatment_library (
    id SERIAL PRIMARY KEY,
    pest VARCHAR(100) NOT NULL,
    title VARCHAR(200) NOT NULL,
    recommendation TEXT NOT NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'draft',      -- draft | approved
    created_by VARCHAR(255) NOT NULL DEFAULT '',
    updated_by VARCHAR(255) NOT NULL DEFAULT '',
    approved_by VARCHAR(255),
    approved_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT treatment_library_status_chk CHECK (status IN ('draft', 'approved'))
);

CREATE TABLE IF NOT EXISTS infestation_criteria (
    id SERIAL PRIMARY KEY,
    pest VARCHAR(100) NOT NULL UNIQUE,                -- '' = default for every pest
    metric VARCHAR(20) NOT NULL DEFAULT 'density',    -- density (pests/m2) | count
    medium_from REAL NOT NULL,                        -- value where MEDIUM starts
    high_from REAL NOT NULL,                          -- value where HIGH starts
    updated_by VARCHAR(255) NOT NULL DEFAULT '',
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT infestation_criteria_metric_chk CHECK (metric IN ('density', 'count')),
    CONSTRAINT infestation_criteria_order_chk CHECK (medium_from < high_from)
);

-- Default = the mobile app's rule (density < 5 LOW, 5-15 MEDIUM, above HIGH).
INSERT INTO infestation_criteria (pest, metric, medium_from, high_from, updated_by)
VALUES ('', 'density', 5, 15, 'system')
ON CONFLICT (pest) DO NOTHING;

CREATE TABLE IF NOT EXISTS scan_reviews (
    id SERIAL PRIMARY KEY,
    scan_id INTEGER NOT NULL REFERENCES scans(id) ON DELETE CASCADE,
    reviewer VARCHAR(255) NOT NULL,
    reviewer_role VARCHAR(50) NOT NULL,
    action VARCHAR(20) NOT NULL,                      -- validated | corrected | referred | diagnosis
    corrected_count INTEGER,
    diagnosis TEXT NOT NULL DEFAULT '',
    guidance TEXT NOT NULL DEFAULT '',
    library_id INTEGER REFERENCES treatment_library(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_scan_reviews_scan_id ON scan_reviews(scan_id);

-- History for scans reviewed before this table existed (one row per scan).
INSERT INTO scan_reviews (scan_id, reviewer, reviewer_role, action, corrected_count, diagnosis, created_at)
SELECT s.id, COALESCE(s.validated_by, ''), 'technician', s.validation_status,
       s.corrected_count, COALESCE(s.diagnosis, ''), s.validated_at
FROM scans s
WHERE s.validated_at IS NOT NULL
  AND s.validation_status IN ('validated', 'corrected', 'referred')
  AND NOT EXISTS (SELECT 1 FROM scan_reviews r WHERE r.scan_id = s.id);

-- The API connects as "user".
GRANT SELECT, INSERT, UPDATE, DELETE ON treatment_library, infestation_criteria, scan_reviews TO "user";
GRANT USAGE, SELECT ON SEQUENCE treatment_library_id_seq, infestation_criteria_id_seq, scan_reviews_id_seq TO "user";
