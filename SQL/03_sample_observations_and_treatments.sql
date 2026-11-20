-- ==============================================================================
-- 03_sample_observations_and_treatments.sql
-- Seed Data: Field Observations, Reviews, Treatments, and Notifications
-- Target Database: rice_pest_geo
-- Location Context: Province of Antique (San Jose, Sibalom, Hamtic, Laua-an, Patnongon)
-- ==============================================================================

-- 1. Link Treatments to Existing Validated Scans
INSERT INTO treatments (
    scan_id, submitted_by, treatment, applied_at, pre_count, created_at, option_type, follow_up_due, library_id
)
SELECT
    5, 'tejaresalleah@sac.edu.ph',
    'Alternate Wetting and Drying (Intermittent Irrigation) - Drained field for 4 days to suppress BPH nymph population',
    CURRENT_TIMESTAMP - INTERVAL '4 days', 10, CURRENT_TIMESTAMP - INTERVAL '4 days', 'cultural', CURRENT_DATE + INTERVAL '3 days',
    (SELECT id FROM treatment_library WHERE pest = 'brown_planthopper' AND option_type = 'cultural' LIMIT 1)
WHERE EXISTS (SELECT 1 FROM scans WHERE id = 5)
  AND NOT EXISTS (SELECT 1 FROM treatments WHERE scan_id = 5);

INSERT INTO treatments (
    scan_id, submitted_by, treatment, applied_at, pre_count, created_at, option_type, follow_up_due, library_id
)
SELECT
    3, 'tejaresalleah@sac.edu.ph',
    'Conserved predatory wolf spiders and established flowering nectar strips along bunds',
    CURRENT_TIMESTAMP - INTERVAL '7 days', 5, CURRENT_TIMESTAMP - INTERVAL '7 days', 'biological', CURRENT_DATE,
    (SELECT id FROM treatment_library WHERE pest = 'brown_planthopper' AND option_type = 'biological' LIMIT 1)
WHERE EXISTS (SELECT 1 FROM scans WHERE id = 3)
  AND NOT EXISTS (SELECT 1 FROM treatments WHERE scan_id = 3);

INSERT INTO treatments (
    scan_id, submitted_by, treatment, applied_at, pre_count, created_at, option_type, follow_up_due, library_id
)
SELECT
    6, 'tejaresalleah@sac.edu.ph',
    'Deployed kerosene light traps along field borders and maintained shallow water level',
    CURRENT_TIMESTAMP - INTERVAL '2 days', 8, CURRENT_TIMESTAMP - INTERVAL '2 days', 'ecological', CURRENT_DATE + INTERVAL '5 days',
    (SELECT id FROM treatment_library WHERE pest = 'brown_planthopper' AND option_type = 'ecological' LIMIT 1)
WHERE EXISTS (SELECT 1 FROM scans WHERE id = 6)
  AND NOT EXISTS (SELECT 1 FROM treatments WHERE scan_id = 6);

