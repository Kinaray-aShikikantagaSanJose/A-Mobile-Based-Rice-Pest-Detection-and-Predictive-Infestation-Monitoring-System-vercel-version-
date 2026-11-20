"""Directional spread, land type suggestion and the guide (no database needed)."""
import os
import unittest
from datetime import date

os.environ.setdefault("DATABASE_URL", "postgresql+psycopg2://user:pass@localhost:5432/unused")

from app import guide, insights, land, levels  # noqa: E402

END = date(2026, 11, 15)  # Week 2 = Nov 9-15, Week 1 = Nov 2-8


def pt(day: str, lat: float, lng: float, pest: str = "Rice Bug") -> dict:
    return {"created_at": f"{day}T08:00:00+08:00", "lat": lat, "lng": lng, "pest": pest}


class SpreadTest(unittest.TestCase):
    def test_moves_northeast_with_label_dates_and_counts(self):
        week1 = [pt("2026-11-03", 10.70, 122.00), pt("2026-11-04", 10.71, 122.01), pt("2026-11-05", 10.70, 122.01)]
        week2 = [pt("2026-11-10", 10.75, 122.05), pt("2026-11-11", 10.76, 122.06),
                 pt("2026-11-12", 10.75, 122.06), pt("2026-11-14", 10.76, 122.05)]
        out = insights.spread(week1 + week2, END, 7, min_records=3)
        item = out["pests"][0]
        self.assertEqual(item["status"], "moved")
        self.assertEqual(item["direction"], "NE")
        self.assertEqual(item["records"], [3, 4])
        self.assertEqual(item["records_used"], 7)
        self.assertEqual(
            item["message"],
            "Reported cases moved toward the northeast between Week 1 (Nov 2-8) and Week 2 (Nov 9-15).",
        )
        self.assertIn("7 records used (3 in Week 1, 4 in Week 2)", item["detail"])
        self.assertEqual(out["note"], "Based on reported cases only. It shows observed movement, not a forecast.")

    def test_too_few_records_shows_not_enough_data(self):
        pts = [pt("2026-11-03", 10.7, 122.0), pt("2026-11-10", 10.8, 122.1), pt("2026-11-11", 10.8, 122.1),
               pt("2026-11-12", 10.8, 122.1)]
        item = insights.spread(pts, END, 7, min_records=3)["pests"][0]
        self.assertEqual(item["status"], "insufficient")
        self.assertEqual(item["message"], "Not enough data to show direction.")
        self.assertIsNone(item["direction"])

    def test_points_outside_both_windows_are_ignored(self):
        pts = [pt("2026-10-20", 10.7, 122.0), pt("2026-11-16", 10.7, 122.0)]
        self.assertEqual(insights.spread(pts, END, 7)["pests"], [])

    def test_same_place_is_not_a_direction(self):
        pts = [pt(d, 10.7, 122.0) for d in ("2026-11-02", "2026-11-03", "2026-11-04",
                                            "2026-11-10", "2026-11-11", "2026-11-12")]
        item = insights.spread(pts, END, 7, min_records=3)["pests"][0]
        self.assertEqual(item["status"], "still")
        self.assertIsNone(item["direction"])

    def test_compass_points(self):
        self.assertEqual(insights.compass(0)[0], "N")
        self.assertEqual(insights.compass(44)[0], "NE")
        self.assertEqual(insights.compass(91)[0], "E")
        self.assertEqual(insights.compass(225)[0], "SW")
        self.assertEqual(insights.compass(350)[0], "N")


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
