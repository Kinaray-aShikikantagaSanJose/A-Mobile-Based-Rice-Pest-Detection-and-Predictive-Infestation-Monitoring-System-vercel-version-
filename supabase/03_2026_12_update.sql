-- ==============================================================================
-- Palay Patrol - update 2026-12 (run after 01_schema.sql and 02_antique_locations.sql)
-- ==============================================================================
--   A. Image relevance check (separate from pest detection)
--   B. Review workflow: reviewer notes, recommendations from the approved
--      treatment library (kept apart from treatments actually applied)
--   C. Land type corrections (who changed it, when)
--   D. Infestation thresholds: provisional until an agriculturist confirms them
--   E. Constraints and indexes for the treatment chain and paged lists
--
-- Safe to run more than once. Nothing is deleted or reset; older rows keep
-- working (new columns have defaults, new CHECKs on old tables are NOT VALID
-- so existing data is never rejected). The API checks for every new column
-- and keeps working (with the new features off) until this file has run.
-- ==============================================================================

-- ------------------------------------------------------------------------------
-- A. Image relevance
-- ------------------------------------------------------------------------------
-- image_relevance:
--   ''                  checked before this update (unknown)
--   relevant            the photo shows plants/field, or the model found a pest
--   possibly_unrelated  the photo does not look like a crop photo; a
--                       technician checks it. Never closed as "no pests found"
--                       and never deleted automatically.
-- It is a screening aid, not a verdict: details in detection_metadata.relevance.
ALTER TABLE scans ADD COLUMN IF NOT EXISTS image_relevance VARCHAR(20) NOT NULL DEFAULT '';

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'scans_image_relevance_chk') THEN
        ALTER TABLE scans ADD CONSTRAINT scans_image_relevance_chk
            CHECK (image_relevance IN ('', 'relevant', 'possibly_unrelated')) NOT VALID;
    END IF;
END
$$;

CREATE INDEX IF NOT EXISTS idx_scans_image_relevance ON scans(image_relevance)
    WHERE image_relevance = 'possibly_unrelated';

-- ------------------------------------------------------------------------------
-- B. Reviews and recommendations
-- ------------------------------------------------------------------------------
-- The reviewer's own note about the decision (what was checked and why).
-- It is separate from the diagnosis and the guidance the farmer receives.
ALTER TABLE scan_reviews ADD COLUMN IF NOT EXISTS reviewer_note TEXT NOT NULL DEFAULT '';

-- Options a reviewer recommends from the APPROVED treatment library for one
-- observation. What the farmer actually did stays in `treatments`.
CREATE TABLE IF NOT EXISTS scan_recommendations (
    id SERIAL PRIMARY KEY,
    scan_id INTEGER NOT NULL REFERENCES scans(id) ON DELETE CASCADE,
    library_id INTEGER NOT NULL REFERENCES treatment_library(id) ON DELETE RESTRICT,
    recommended_by VARCHAR(255) NOT NULL,
    recommended_by_role VARCHAR(20) NOT NULL,
    review_id INTEGER REFERENCES scan_reviews(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT scan_recommendations_uq UNIQUE (scan_id, library_id),
    CONSTRAINT scan_recommendations_role_chk CHECK (recommended_by_role IN ('technician', 'agriculturist'))
);

CREATE INDEX IF NOT EXISTS idx_scan_recommendations_scan ON scan_recommendations(scan_id);
CREATE INDEX IF NOT EXISTS idx_scan_recommendations_library ON scan_recommendations(library_id);

-- ------------------------------------------------------------------------------
-- C. Land type corrections
-- ------------------------------------------------------------------------------
-- land_type is chosen by the person who submits the observation. A technician
-- (coverage area) or agriculturist may correct it; these record who and when.
-- The 100 m elevation hint (app/land.py) is provisional pending expert review.
ALTER TABLE scans ADD COLUMN IF NOT EXISTS land_type_updated_by VARCHAR(255);
ALTER TABLE scans ADD COLUMN IF NOT EXISTS land_type_updated_at TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS idx_scans_land_type ON scans(land_type);

-- ------------------------------------------------------------------------------
-- D. Provisional infestation thresholds
-- ------------------------------------------------------------------------------
-- Every threshold starts as provisional. An agriculturist marks a row as
-- confirmed only after checking it against a source (stored here); editing
-- the numbers makes it provisional again (enforced by the API).
ALTER TABLE level_criteria ADD COLUMN IF NOT EXISTS provisional BOOLEAN NOT NULL DEFAULT TRUE;
ALTER TABLE level_criteria ADD COLUMN IF NOT EXISTS source_reference TEXT NOT NULL DEFAULT '';
ALTER TABLE level_criteria ADD COLUMN IF NOT EXISTS confirmed_by VARCHAR(255);
ALTER TABLE level_criteria ADD COLUMN IF NOT EXISTS confirmed_at TIMESTAMPTZ;

-- ------------------------------------------------------------------------------
-- E. Constraints and indexes
-- ------------------------------------------------------------------------------
DO $$
BEGIN
    -- The follow-up check can't be due before the treatment was applied.
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'treatments_follow_up_order_chk') THEN
        ALTER TABLE treatments ADD CONSTRAINT treatments_follow_up_order_chk
            CHECK (follow_up_due IS NULL OR follow_up_due >= (applied_at AT TIME ZONE 'Asia/Manila')::date)
            NOT VALID;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'scan_reviews_action_chk') THEN
        ALTER TABLE scan_reviews ADD CONSTRAINT scan_reviews_action_chk
            CHECK (action IN ('validated', 'returned', 'escalated', 'land_type_changed')) NOT VALID;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'scans_report_type_chk') THEN
        ALTER TABLE scans ADD CONSTRAINT scans_report_type_chk
            CHECK (report_type IN ('pest', 'disease')) NOT VALID;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'scans_level_chk') THEN
        ALTER TABLE scans ADD CONSTRAINT scans_level_chk
            CHECK (infestation_level IS NULL OR infestation_level IN ('LOW', 'MEDIUM', 'HIGH')) NOT VALID;
    END IF;
END
$$;

-- Paged lists are ordered newest first with the id as tie-breaker.
CREATE INDEX IF NOT EXISTS idx_scans_created ON scans(created_at DESC, id DESC);
CREATE INDEX IF NOT EXISTS idx_scans_status_created ON scans(validation_status, created_at DESC, id DESC);
CREATE INDEX IF NOT EXISTS idx_treatments_applied ON treatments(applied_at DESC, id DESC);
CREATE INDEX IF NOT EXISTS idx_treatments_library ON treatments(library_id);
CREATE INDEX IF NOT EXISTS idx_scan_reviews_reviewer ON scan_reviews(reviewer, created_at DESC, id DESC);
CREATE INDEX IF NOT EXISTS idx_users_created ON users(created_at DESC, id DESC);

-- ------------------------------------------------------------------------------
-- Security: same rule as the other tables (no access through Supabase's REST API)
-- ------------------------------------------------------------------------------
ALTER TABLE scan_recommendations ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
        REVOKE ALL ON scan_recommendations FROM anon, authenticated;
        REVOKE ALL ON SEQUENCE scan_recommendations_id_seq FROM anon, authenticated;
    END IF;
END
$$;
