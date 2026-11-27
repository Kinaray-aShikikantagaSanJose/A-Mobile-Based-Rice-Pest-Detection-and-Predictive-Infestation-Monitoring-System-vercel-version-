"""Directional spread, land type suggestion and the guide (no database needed)."""
import os
import unittest

os.environ.setdefault("DATABASE_URL", "postgresql+psycopg2://user:pass@localhost:5432/unused")

from app import guide, insights, land, levels  # noqa: E402

# Directional spread tests moved to tests/test_monitoring_update.py (new rules: reliable
# locations only, barangay names, custom ranges, translated text).


class LandTypeTest(unittest.TestCase):
    def test_suggestion(self):
        self.assertEqual(land.suggest(land.UPLAND_MIN_ELEVATION_M + 50)["suggested"], "upland")
        low = land.suggest(5)
        self.assertIsNone(low["suggested"])  # rainfed vs irrigated: the person decides
        self.assertEqual(low["group"], "lowland")
        self.assertIsNone(land.suggest(None)["group"])

    def test_filter_by_land_type(self):
        rows = [{"pest": "Rice Bug", "level": "LOW", "municipality": "Sibalom", "crop_stage": "Ripening",
                 "land_type": lt} for lt in ("upland", "irrigated_lowland")]
        self.assertEqual(len(insights.filter_scans(rows, land_type="upland")), 1)
        self.assertEqual(len(insights.filter_scans(rows)), 2)

    def test_labels(self):
        self.assertEqual(land.label("rainfed_lowland"), "Rainfed lowland")
        self.assertEqual(land.label(""), "Not recorded")


class GuideTest(unittest.TestCase):
    def test_covers_the_four_model_classes(self):
        self.assertEqual([p["key"] for p in guide.PESTS], list(levels.SUPPORTED_PESTS))

    def test_symptoms_match_the_reviewer_checklist(self):
        for pest in levels.SUPPORTED_PESTS:
            listed = [s["indicator"] for s in guide.SYMPTOMS if s["pest"] == pest]
            self.assertEqual(listed, levels.DAMAGE_INDICATORS[pest], pest)

    def test_stages_are_app_stages(self):
        for entry in guide.PESTS + guide.SYMPTOMS:
            self.assertTrue(entry["stages"])
            self.assertTrue(set(entry["stages"]) <= set(levels.CROP_STAGES), entry["key"])


if __name__ == "__main__":
    unittest.main()
