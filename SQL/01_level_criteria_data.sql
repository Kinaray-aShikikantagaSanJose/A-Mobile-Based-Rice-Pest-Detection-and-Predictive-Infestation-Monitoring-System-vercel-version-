-- ==============================================================================
-- 01_level_criteria_data.sql
-- Seed Data: Infestation Level Criteria & Action Thresholds
-- Target Database: rice_pest_geo
-- Reference: IRRI Rice Knowledge Bank & PhilRice Integrated Pest Management (IPM)
-- ==============================================================================

DELETE FROM level_criteria WHERE updated_by = 'placeholder';

INSERT INTO level_criteria (pest, crop_stage, medium_from, high_from, updated_by, updated_at)
VALUES
    -- 1. Brown Planthopper (Nilaparvata lugens)
    ('brown_planthopper', '', 8.0, 20.0, 'PhilRice/IRRI IPM Standard', CURRENT_TIMESTAMP),
    ('brown_planthopper', 'Vegetative', 6.0, 15.0, 'PhilRice/IRRI IPM Standard', CURRENT_TIMESTAMP),
    ('brown_planthopper', 'Reproductive', 10.0, 25.0, 'PhilRice/IRRI IPM Standard', CURRENT_TIMESTAMP),
    ('brown_planthopper', 'Ripening', 15.0, 35.0, 'PhilRice/IRRI IPM Standard', CURRENT_TIMESTAMP),

    -- 2. Green Leafhopper (Nephotettix virescens)
    ('green_leafhopper', '', 4.0, 10.0, 'PhilRice/IRRI IPM Standard', CURRENT_TIMESTAMP),
    ('green_leafhopper', 'Vegetative', 2.0, 5.0, 'PhilRice/IRRI IPM Standard', CURRENT_TIMESTAMP),
    ('green_leafhopper', 'Reproductive', 5.0, 12.0, 'PhilRice/IRRI IPM Standard', CURRENT_TIMESTAMP),
    ('green_leafhopper', 'Ripening', 8.0, 18.0, 'PhilRice/IRRI IPM Standard', CURRENT_TIMESTAMP),

    -- 3. Rice Bug (Leptocorisa oratorius)
    ('rice_bug', '', 4.0, 10.0, 'PhilRice/IRRI IPM Standard', CURRENT_TIMESTAMP),
    ('rice_bug', 'Vegetative', 6.0, 15.0, 'PhilRice/IRRI IPM Standard', CURRENT_TIMESTAMP),
    ('rice_bug', 'Reproductive', 3.0, 8.0, 'PhilRice/IRRI IPM Standard', CURRENT_TIMESTAMP),
    ('rice_bug', 'Ripening', 4.0, 10.0, 'PhilRice/IRRI IPM Standard', CURRENT_TIMESTAMP),

    -- 4. Rice Stem Borer (Scirpophaga incertulas / Chilo suppressalis)
    ('rice_stem_borer', '', 4.0, 10.0, 'PhilRice/IRRI IPM Standard', CURRENT_TIMESTAMP),
    ('rice_stem_borer', 'Vegetative', 3.0, 8.0, 'PhilRice/IRRI IPM Standard', CURRENT_TIMESTAMP),
    ('rice_stem_borer', 'Reproductive', 2.0, 6.0, 'PhilRice/IRRI IPM Standard', CURRENT_TIMESTAMP),
    ('rice_stem_borer', 'Ripening', 5.0, 12.0, 'PhilRice/IRRI IPM Standard', CURRENT_TIMESTAMP)
ON CONFLICT (pest, crop_stage) DO UPDATE
SET
    medium_from = EXCLUDED.medium_from,
    high_from = EXCLUDED.high_from,
    updated_by = EXCLUDED.updated_by,
    updated_at = CURRENT_TIMESTAMP;
