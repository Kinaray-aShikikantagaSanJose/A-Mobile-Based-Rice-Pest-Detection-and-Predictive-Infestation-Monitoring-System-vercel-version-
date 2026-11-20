-- =====================================================
-- 011: land type, treatment feedback rule, "model result" wording
--      run on rice_pest_geo as postgres
-- =====================================================
-- Safe to run more than once. Until it runs, the API keeps working:
--  * observations are saved without a land type (the field is not stored),
--  * staff can't re-allow a treatment or change a follow-up date (503),
--  * old review notes keep the "AI result" wording.

-- ---- land type of the field (required for new observations; '' = recorded before this field existed)
ALTER TABLE scans ADD COLUMN IF NOT EXISTS land_type VARCHAR(30) NOT NULL DEFAULT '';
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'scans_land_type_chk') THEN
        ALTER TABLE scans ADD CONSTRAINT scans_land_type_chk
            CHECK (land_type IN ('', 'upland', 'rainfed_lowland', 'irrigated_lowland'));
    END IF;
END
$$;
-- Elevation (m) the phone looked up for the suggestion, when it did; NULL = none.
ALTER TABLE scans ADD COLUMN IF NOT EXISTS elevation_m REAL;

-- ---- treatment feedback rule
-- A treatment the farmer applied AND reported back on (a follow-up observation)
-- is not recommended to that farmer again, unless a technician or
-- agriculturist re-allows it here.
ALTER TABLE treatments ADD COLUMN IF NOT EXISTS recommend_again BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE treatments ADD COLUMN IF NOT EXISTS recommend_again_by VARCHAR(255);
-- Who last changed follow_up_due (NULL = the automatic 7 days after applying).
ALTER TABLE treatments ADD COLUMN IF NOT EXISTS follow_up_set_by VARCHAR(255);

-- ---- audit log wording: "AI result" is now "model result"
UPDATE scan_reviews
SET note = replace(note, 'confirmed the AI result', 'confirmed the model result')
WHERE note LIKE '%confirmed the AI result%';
