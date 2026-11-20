-- =====================================================
-- 005: scan monitoring + diagnosis fields  -  run on rice_pest_geo as postgres
-- =====================================================
-- Raw-SQL version of alembic/versions/005_add_monitoring_and_diagnosis_fields.py.
-- /sync/scans writes the first three and /sync/scans/queue reads diagnosis,
-- so uploads and the technician queue fail without them. Safe to run more than once.

ALTER TABLE scans ADD COLUMN IF NOT EXISTS monitoring_method TEXT NOT NULL DEFAULT '';
ALTER TABLE scans ADD COLUMN IF NOT EXISTS target_pest       TEXT NOT NULL DEFAULT '';
ALTER TABLE scans ADD COLUMN IF NOT EXISTS target_sex        TEXT NOT NULL DEFAULT '';
ALTER TABLE scans ADD COLUMN IF NOT EXISTS diagnosis         TEXT NOT NULL DEFAULT '';
