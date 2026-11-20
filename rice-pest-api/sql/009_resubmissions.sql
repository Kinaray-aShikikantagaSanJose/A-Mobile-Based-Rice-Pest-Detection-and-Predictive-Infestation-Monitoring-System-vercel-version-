-- =====================================================
-- 009: retakes of returned photos  -  run on rice_pest_geo as postgres
-- =====================================================
-- When a technician returns an observation (photo unclear), the farmer's new
-- photo is linked to the returned one and goes through the whole process
-- again (AI for pest reports, then technician review). Safe to run more than once.

ALTER TABLE scans ADD COLUMN IF NOT EXISTS resubmission_of INTEGER;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'scans_resubmission_fk') THEN
        ALTER TABLE scans ADD CONSTRAINT scans_resubmission_fk
            FOREIGN KEY (resubmission_of) REFERENCES scans(id) ON DELETE SET NULL;
    END IF;
END
$$;

CREATE INDEX IF NOT EXISTS idx_scans_resubmission_of ON scans(resubmission_of);
