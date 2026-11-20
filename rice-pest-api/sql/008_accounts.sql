-- =====================================================
-- 008: account approval, contact details, technician coverage
--      run on rice_pest_db2 as postgres (run BEFORE 008_observation_workflow.sql)
-- =====================================================
-- Every new account waits for an agriculturist's approval. Safe to run more than once.

ALTER TABLE users ADD COLUMN IF NOT EXISTS phone VARCHAR(30) NOT NULL DEFAULT '';
ALTER TABLE users ADD COLUMN IF NOT EXISTS barangay VARCHAR(100) NOT NULL DEFAULT '';
-- Technicians: barangays they cover inside their municipality (comma-separated).
-- Empty = the whole municipality.
ALTER TABLE users ADD COLUMN IF NOT EXISTS coverage_barangays TEXT NOT NULL DEFAULT '';

-- Accounts that already exist stay usable: the column is added as 'approved',
-- then the default switches so new sign-ups start as 'pending'.
ALTER TABLE users ADD COLUMN IF NOT EXISTS status VARCHAR(20) NOT NULL DEFAULT 'approved';
ALTER TABLE users ALTER COLUMN status SET DEFAULT 'pending';
ALTER TABLE users ADD COLUMN IF NOT EXISTS reviewed_by VARCHAR(255);
ALTER TABLE users ADD COLUMN IF NOT EXISTS reviewed_at TIMESTAMPTZ;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'users_status_chk') THEN
        ALTER TABLE users ADD CONSTRAINT users_status_chk
            CHECK (status IN ('pending', 'approved', 'rejected'));
    END IF;
END
$$;
