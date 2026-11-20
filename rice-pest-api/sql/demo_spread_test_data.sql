-- =====================================================
-- OPTIONAL demo data for the directional spread (and heatmap)
-- run on rice_pest_geo as postgres, AFTER 011_land_type_and_treatment_feedback.sql
-- =====================================================
-- Adds 11 validated TEST observations dated relative to today, so the hotspot
-- map shows:
--   * Rice Bug: an arrow toward the northeast between Week 1 and Week 2
--     (4 records, then 5 records), Sibalom area;
--   * Brown Planthopper: "Not enough data to show direction." (2 records only).
-- They also appear in records, summaries and exports while present, so
-- remove them after the demo with the DELETE at the bottom.
-- All rows use the email demo-spread@palaypatrol.test.

INSERT INTO scans (user_email, image_filename, notes, geom, created_at, report_type, crop_phase,
                   municipality, barangay, submitted_by_role, validation_status, confirmed_pest,
                   confirmed_count, countable, infestation_level, validated_by, validated_at,
                   land_type, ai_status)
SELECT 'demo-spread@palaypatrol.test', 'demo.jpg', 'DEMO record for the directional spread',
       ST_SetSRID(ST_MakePoint(d.lng, d.lat), 4326),
       (CURRENT_DATE - d.days_ago) + TIME '09:00', 'pest', d.stage,
       'Sibalom', d.brgy, 'farmer', 'validated', d.pest, d.cnt, TRUE, d.lvl,
       'demo-spread@palaypatrol.test', (CURRENT_DATE - d.days_ago) + TIME '15:00',
       d.land, 'skipped'
FROM (VALUES
    -- Rice Bug, Week 1 (7-13 days ago): around 10.780, 122.000
    (10.781, 121.998, 12, 'rice_bug', 6,  'LOW',    'Reproductive', 'Demo A', 'irrigated_lowland'),
    (10.777, 122.003, 11, 'rice_bug', 9,  'MEDIUM', 'Reproductive', 'Demo A', 'irrigated_lowland'),
    (10.783, 122.004,  9, 'rice_bug', 4,  'LOW',    'Reproductive', 'Demo A', 'rainfed_lowland'),
    (10.779, 121.996,  8, 'rice_bug', 11, 'MEDIUM', 'Reproductive', 'Demo A', 'irrigated_lowland'),
    -- Rice Bug, Week 2 (0-6 days ago): around 10.820, 122.045 (about 6.6 km to the northeast)
    (10.821, 122.043,  5, 'rice_bug', 14, 'MEDIUM', 'Ripening',     'Demo B', 'irrigated_lowland'),
    (10.818, 122.048,  4, 'rice_bug', 22, 'HIGH',   'Ripening',     'Demo B', 'irrigated_lowland'),
    (10.823, 122.046,  3, 'rice_bug', 17, 'HIGH',   'Ripening',     'Demo B', 'rainfed_lowland'),
    (10.817, 122.041,  2, 'rice_bug', 8,  'MEDIUM', 'Ripening',     'Demo B', 'irrigated_lowland'),
    (10.822, 122.050,  1, 'rice_bug', 12, 'MEDIUM', 'Ripening',     'Demo B', 'upland'),
    -- Brown Planthopper: one record per week, below the minimum of 3
    (10.770, 121.990, 10, 'brown_planthopper', 30, 'MEDIUM', 'Reproductive', 'Demo A', 'irrigated_lowland'),
    (10.775, 121.995,  3, 'brown_planthopper', 45, 'HIGH',   'Ripening',     'Demo A', 'irrigated_lowland')
) AS d(lat, lng, days_ago, pest, cnt, lvl, stage, brgy, land);

-- ---- remove the demo rows afterwards:
-- DELETE FROM scans WHERE user_email = 'demo-spread@palaypatrol.test';
