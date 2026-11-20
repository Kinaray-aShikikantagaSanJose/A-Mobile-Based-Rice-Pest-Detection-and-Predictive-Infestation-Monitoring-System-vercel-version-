-- =====================================================
-- 010: profile pictures  -  run on rice_pest_db2 as postgres
-- =====================================================
-- The file name of each account's picture (stored in uploads/avatars/).
-- NULL = no picture: the apps show the person's initials. Safe to run more than once.
-- Until this runs, everything else works; uploading a picture answers 503.

ALTER TABLE users ADD COLUMN IF NOT EXISTS avatar_path VARCHAR(255);
