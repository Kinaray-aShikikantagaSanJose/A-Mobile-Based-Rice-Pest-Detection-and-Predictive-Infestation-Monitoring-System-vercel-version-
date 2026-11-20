-- =====================================================
-- 008: observation workflow  -  run on rice_pest_geo as postgres
--      (run 008_accounts.sql on rice_pest_db2 first)
-- =====================================================
-- Server-side AI results, technician review (confirm / correct / return /
-- escalate + infestation level), disease reports, treatment options and
-- follow-ups linked to treatments, in-app notifications, and per-pest
-- level thresholds. Run BEFORE restarting the API. Safe to run more than once.

-- ---- users_fdw: mirror the new rice_pest_db2.users columns
ALTER FOREIGN TABLE users_fdw ADD COLUMN IF NOT EXISTS phone VARCHAR(30);
ALTER FOREIGN TABLE users_fdw ADD COLUMN IF NOT EXISTS barangay VARCHAR(100);
ALTER FOREIGN TABLE users_fdw ADD COLUMN IF NOT EXISTS coverage_barangays TEXT;
ALTER FOREIGN TABLE users_fdw ADD COLUMN IF NOT EXISTS status VARCHAR(20);

-- ---- observations
-- Sent by the phone so a retried upload never creates a duplicate.
ALTER TABLE scans ADD COLUMN IF NOT EXISTS client_uuid VARCHAR(64);
CREATE UNIQUE INDEX IF NOT EXISTS idx_scans_client_uuid ON scans(client_uuid) WHERE client_uuid IS NOT NULL;
ALTER TABLE scans ADD COLUMN IF NOT EXISTS report_type VARCHAR(10) NOT NULL DEFAULT 'pest';   -- pest | disease
-- Where the submitter is registered, captured at upload: decides whose queue it lands in.
ALTER TABLE scans ADD COLUMN IF NOT EXISTS municipality VARCHAR(100) NOT NULL DEFAULT '';
ALTER TABLE scans ADD COLUMN IF NOT EXISTS barangay VARCHAR(100) NOT NULL DEFAULT '';
ALTER TABLE scans ADD COLUMN IF NOT EXISTS submitted_by_role VARCHAR(20) NOT NULL DEFAULT 'farmer';
-- AI (pest reports only; never for disease reports)
ALTER TABLE scans ADD COLUMN IF NOT EXISTS ai_status VARCHAR(10) NOT NULL DEFAULT 'skipped';  -- done | failed | skipped
ALTER TABLE scans ADD COLUMN IF NOT EXISTS ai_pest VARCHAR(50);
ALTER TABLE scans ADD COLUMN IF NOT EXISTS ai_confidence REAL;
ALTER TABLE scans ADD COLUMN IF NOT EXISTS ai_count INTEGER;                                  -- NULL = not countable
ALTER TABLE scans ADD COLUMN IF NOT EXISTS ai_countable BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE scans ADD COLUMN IF NOT EXISTS ai_detections JSONB NOT NULL DEFAULT '[]';
ALTER TABLE scans ADD COLUMN IF NOT EXISTS ai_message TEXT NOT NULL DEFAULT '';
-- Technician / agriculturist decision
ALTER TABLE scans ADD COLUMN IF NOT EXISTS confirmed_pest VARCHAR(50);                         -- one of the four, or 'other'
ALTER TABLE scans ADD COLUMN IF NOT EXISTS confirmed_count INTEGER;                            -- NULL = not countable
ALTER TABLE scans ADD COLUMN IF NOT EXISTS countable BOOLEAN;
ALTER TABLE scans ADD COLUMN IF NOT EXISTS infestation_level VARCHAR(10);                      -- LOW | MEDIUM | HIGH
ALTER TABLE scans ADD COLUMN IF NOT EXISTS suggested_level VARCHAR(10);
ALTER TABLE scans ADD COLUMN IF NOT EXISTS damage_indicators TEXT[] NOT NULL DEFAULT '{}';
ALTER TABLE scans ADD COLUMN IF NOT EXISTS return_reason TEXT NOT NULL DEFAULT '';
ALTER TABLE scans ADD COLUMN IF NOT EXISTS escalation_reason TEXT NOT NULL DEFAULT '';
ALTER TABLE scans ADD COLUMN IF NOT EXISTS guidance TEXT NOT NULL DEFAULT '';
-- A follow-up observation points at the treatment it checks on (FK added below).
ALTER TABLE scans ADD COLUMN IF NOT EXISTS follow_up_of INTEGER;

-- Statuses are now: pending | validated | returned | escalated
UPDATE scans SET validation_status = 'escalated' WHERE validation_status = 'referred';
UPDATE scans SET validation_status = 'validated' WHERE validation_status = 'corrected';
UPDATE scans SET report_type = 'disease' WHERE monitoring_method = 'Disease Report' AND report_type = 'pest';

CREATE INDEX IF NOT EXISTS idx_scans_queue ON scans(validation_status, report_type, municipality, created_at);

-- ---- treatment library: pest x crop stage x infestation level, grouped by type
ALTER TABLE treatment_library ADD COLUMN IF NOT EXISTS option_type VARCHAR(20) NOT NULL DEFAULT 'cultural';
ALTER TABLE treatment_library ADD COLUMN IF NOT EXISTS crop_stages TEXT[] NOT NULL DEFAULT '{}';  -- empty = every stage
ALTER TABLE treatment_library ADD COLUMN IF NOT EXISTS levels TEXT[] NOT NULL DEFAULT '{}';       -- empty = every level
ALTER TABLE treatment_library ADD COLUMN IF NOT EXISTS source_reference TEXT NOT NULL DEFAULT '';
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'treatment_library_type_chk') THEN
        ALTER TABLE treatment_library ADD CONSTRAINT treatment_library_type_chk
            CHECK (option_type IN ('cultural', 'biological', 'ecological', 'chemical'));
    END IF;
END
$$;

-- ---- treatments the farmer applied
ALTER TABLE treatments ADD COLUMN IF NOT EXISTS client_uuid VARCHAR(64);
CREATE UNIQUE INDEX IF NOT EXISTS idx_treatments_client_uuid ON treatments(client_uuid) WHERE client_uuid IS NOT NULL;
ALTER TABLE treatments ADD COLUMN IF NOT EXISTS library_id INTEGER REFERENCES treatment_library(id) ON DELETE SET NULL;
ALTER TABLE treatments ADD COLUMN IF NOT EXISTS option_type VARCHAR(20) NOT NULL DEFAULT 'own';  -- library type or 'own'
ALTER TABLE treatments ADD COLUMN IF NOT EXISTS follow_up_due DATE;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'scans_follow_up_fk') THEN
        ALTER TABLE scans ADD CONSTRAINT scans_follow_up_fk
            FOREIGN KEY (follow_up_of) REFERENCES treatments(id) ON DELETE SET NULL;
    END IF;
END
$$;
CREATE INDEX IF NOT EXISTS idx_scans_follow_up_of ON scans(follow_up_of);

-- ---- review history: what each decision changed
ALTER TABLE scan_reviews ADD COLUMN IF NOT EXISTS pest VARCHAR(50);
ALTER TABLE scan_reviews ADD COLUMN IF NOT EXISTS countable BOOLEAN;
ALTER TABLE scan_reviews ADD COLUMN IF NOT EXISTS level VARCHAR(10);
ALTER TABLE scan_reviews ADD COLUMN IF NOT EXISTS indicators TEXT[] NOT NULL DEFAULT '{}';
ALTER TABLE scan_reviews ADD COLUMN IF NOT EXISTS note TEXT NOT NULL DEFAULT '';

-- ---- infestation level thresholds (count per observation), per pest and crop stage
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
-- Placeholder starting values ('placeholder' shows a warning on the dashboard
-- until an agriculturist replaces them with values from their reference).
INSERT INTO level_criteria (pest, crop_stage, medium_from, high_from, updated_by)
SELECT p, '', 10, 25, 'placeholder'
FROM unnest(ARRAY['brown_planthopper', 'green_leafhopper', 'rice_bug', 'rice_stem_borer']) AS p
ON CONFLICT (pest, crop_stage) DO NOTHING;
-- Replaced by level_criteria (the dashboard no longer computes levels itself).
DROP TABLE IF EXISTS infestation_criteria;

-- ---- in-app notifications (the badge on the farmer's home screen)
CREATE TABLE IF NOT EXISTS notifications (
    id SERIAL PRIMARY KEY,
    user_email VARCHAR(255) NOT NULL,
    scan_id INTEGER REFERENCES scans(id) ON DELETE CASCADE,
    kind VARCHAR(30) NOT NULL,                    -- validated | returned | guidance | escalated
    title VARCHAR(200) NOT NULL,
    body TEXT NOT NULL DEFAULT '',
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    read_at TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS idx_notifications_user ON notifications(user_email, read_at);

-- ---- the API connects as "user"
GRANT SELECT, INSERT, UPDATE, DELETE ON level_criteria, notifications TO "user";
GRANT USAGE, SELECT ON SEQUENCE level_criteria_id_seq, notifications_id_seq TO "user";
GRANT SELECT, INSERT, UPDATE, DELETE ON users_fdw TO "user";
