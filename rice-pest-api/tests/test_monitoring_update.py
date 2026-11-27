"""2026-12 update, no database needed: directional spread (reliable locations,
barangay names, custom ranges), treatment outcome rules, server-side
sorting/paging, filters, monitoring criteria (provisional thresholds),
reviewer notes, translations and the guide."""
import os
import re
import string
import unittest
from datetime import date

os.environ.setdefault("DATABASE_URL", "postgresql+psycopg2://user:pass@localhost:5432/unused")
os.environ.setdefault("JWT_SECRET_KEY", "unit-test-key-that-is-never-used-anywhere-else-0123456789")

from app import geo, guide, i18n, insights, levels, observations as obs  # noqa: E402

END = date(2026, 11, 15)  # Period 2 = Nov 9-15, Period 1 = Nov 2-8 (7-day windows)
SJB_MAYBATO_NORTE, SJB_SAN_ANGEL, SJB_ATABAY = "0600613023", "0600613027", "0600613001"


def interior(psgc: str) -> tuple:
    """A point well inside a barangay (searched on a grid, deepest point wins)."""
    b = geo._load()["by_psgc"][psgc]
    x0, y0, x1, y1 = b.bbox
    best = None
    for i in range(1, 20):
        for j in range(1, 20):
            lng, lat = x0 + (x1 - x0) * i / 20, y0 + (y1 - y0) * j / 20
            hit = geo.locate(lat, lng)
            if hit.get("match") == "inside" and hit["psgc"] == psgc and (best is None or hit["depth_m"] > best[0]):
                best = (hit["depth_m"], lat, lng)
    return best[1], best[2]


def pt(day: str, lat: float, lng: float, pest: str = "Rice Bug", **extra) -> dict:
    return {"created_at": f"{day}T08:00:00+08:00", "lat": lat, "lng": lng, "pest": pest,
            "location_status": "inside", **extra}


def near(lat, lng, k):
    """Small offsets (a few metres) so cases are not all on one point."""
    return lat + 0.00003 * k, lng + 0.00003 * k


class SpreadTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.maybato = interior(SJB_MAYBATO_NORTE)
        cls.san_angel = interior(SJB_SAN_ANGEL)
        cls.atabay = interior(SJB_ATABAY)

    def cases(self, days, place):
        return [pt(d, *near(*place, k)) for k, d in enumerate(days)]

    def test_moved_names_both_barangays(self):
        pts = self.cases(["2026-11-03", "2026-11-04", "2026-11-05"], self.maybato) + \
            self.cases(["2026-11-10", "2026-11-11", "2026-11-12", "2026-11-14"], self.san_angel)
        out = insights.spread(pts, END, 7, min_records=3)
        item = out["pests"][0]
        self.assertEqual(item["status"], "moved")
        self.assertEqual(item["records"], [3, 4])
        self.assertEqual(item["from_place"]["barangay"], "Maybato Norte")
        self.assertEqual(item["to_place"]["barangay"], "San Angel")
        self.assertEqual(item["direction"], insights.compass(item["bearing"])[0])
        self.assertEqual(item["summary"],
                         f"{i18n.render('dir.' + item['direction'])} — from Brgy. Maybato Norte to Brgy. San Angel")
        self.assertIn("Period 1 (Nov 2-8, 2026)", item["message"])
        self.assertIn("3 cases in Period 1", item["detail"])
        self.assertEqual(out["period"], {"start": "2026-11-02", "end": "2026-11-15", "label": "Nov 2-15, 2026"})
        self.assertEqual((out["cases_used"], out["cases_excluded"]), (7, 0))

    def test_centre_in_a_barangay_without_cases_cannot_be_named(self):
        # Period 2 cases split between Atabay and Maybato Norte: their average
        # point lies between them, in a barangay where no case was reported.
        pts = self.cases(["2026-11-03", "2026-11-04", "2026-11-05"], self.san_angel) + \
            self.cases(["2026-11-10", "2026-11-11"], self.atabay) + \
            self.cases(["2026-11-12", "2026-11-13"], self.maybato)
        item = insights.spread(pts, END, 7, min_records=3)["pests"][0]
        self.assertIsNotNone(item["from_place"])
        if item["to_place"] is not None:  # only named if a case is actually there
            self.assertIn(item["to_place"]["barangay"], item["to_barangays"])
        if item["status"] == "moved" and item["to_place"] is None:
            self.assertTrue(item["summary"].endswith("the barangays cannot be determined"))

    def test_unreliable_locations_are_excluded_and_counted(self):
        good = self.cases(["2026-11-03", "2026-11-04", "2026-11-05", "2026-11-10", "2026-11-11"], self.maybato)
        bad = [
            pt("2026-11-12", 10.7202, 122.5621),                                  # Iloilo City
            pt("2026-11-12", *self.maybato, gps_accuracy_m=geo.MAX_ACCURACY_M + 1),  # poor accuracy
            pt("2026-11-13", *self.maybato, location_status="outside_antique"),
            pt("2026-11-13", None, None),
        ]
        out = insights.spread(good + bad, END, 7, min_records=3)
        item = out["pests"][0]
        self.assertEqual(item["status"], "insufficient")            # only 2 reliable cases in period 2
        self.assertEqual(item["records"], [3, 2])
        self.assertEqual(item["excluded"], 4)
        self.assertEqual(item["summary"], "Cannot be determined")
        self.assertIsNone(item["direction"])
        self.assertIsNone(item["to_place"])

    def test_custom_range_is_split_in_two_halves(self):
        w = insights.spread_windows(date(2026, 10, 1), date(2026, 10, 31), 7)
        self.assertEqual(w, (date(2026, 10, 1), date(2026, 10, 15), date(2026, 10, 16), date(2026, 10, 31)))
        out = insights.spread([], date(2026, 10, 31), 7, start=date(2026, 10, 1))
        self.assertTrue(out["custom_range"])
        self.assertEqual([x["days"] for x in out["windows"]], [15, 16])

    def test_same_place_is_not_a_direction(self):
        pts = self.cases(["2026-11-02", "2026-11-03", "2026-11-04", "2026-11-10", "2026-11-11", "2026-11-12"],
                         self.san_angel)
        item = insights.spread(pts, END, 7, min_records=3)["pests"][0]
        self.assertEqual(item["status"], "still")
        self.assertIsNone(item["direction"])
        self.assertEqual(item["summary"], "No clear movement — around Brgy. San Angel")

    def test_points_outside_both_windows_are_ignored(self):
        pts = [pt("2026-10-20", *self.maybato), pt("2026-11-16", *self.maybato)]
        self.assertEqual(insights.spread(pts, END, 7)["pests"], [])

    def test_translated_text(self):
        pts = self.cases(["2026-11-03", "2026-11-04", "2026-11-05"], self.maybato) + \
            self.cases(["2026-11-10", "2026-11-11", "2026-11-12"], self.san_angel)
        item = insights.spread(pts, END, 7, min_records=3, lang="krj")["pests"][0]
        self.assertIn("halin sa Brgy. Maybato Norte pakadto sa Brgy. San Angel", item["summary"])
        self.assertIn("Panahon 1", item["message"])
        out = insights.spread(pts[:2], END, 7, lang="fil")
        self.assertTrue(out["note"].startswith("Batay lamang"))

    def test_compass_points(self):
        self.assertEqual(insights.compass(0)[0], "N")
        self.assertEqual(insights.compass(44)[0], "NE")
        self.assertEqual(insights.compass(91)[0], "E")
        self.assertEqual(insights.compass(225)[0], "SW")
        self.assertEqual(insights.compass(350)[0], "N")


class OutcomeTest(unittest.TestCase):
    def test_level_change_decides_first(self):
        self.assertEqual(insights._outcome("HIGH", "LOW", 10, 12), ("improved", "confirmed level"))
        self.assertEqual(insights._outcome("LOW", "MEDIUM", 10, 2), ("worsened", "confirmed level"))

    def test_same_level_uses_counts_only_when_both_countable(self):
        self.assertEqual(insights._outcome("MEDIUM", "MEDIUM", 10, 5)[0], "improved")
        self.assertEqual(insights._outcome("MEDIUM", "MEDIUM", 10, 15)[0], "worsened")
        self.assertEqual(insights._outcome("MEDIUM", "MEDIUM", 10, 9)[0], "no change")
        self.assertEqual(insights._outcome("MEDIUM", "MEDIUM", None, None)[0], "no change")

    def test_missing_level_is_not_comparable(self):
        self.assertEqual(insights._outcome(None, "LOW", 10, 1)[0], "not comparable")


class PagingAndFilterTest(unittest.TestCase):
    rows = [
        {"id": i, "created_at": f"2026-11-{1 + i % 5:02d}T08:00:00", "level": ("LOW", "HIGH", None)[i % 3],
         "municipality": ("Sibalom", "Hamtic")[i % 2], "barangay": "", "pest": "Rice Bug", "status": "validated",
         "land_type": ("", "upland")[i % 2], "image_relevance": ("relevant", "possibly_unrelated")[i % 2],
         "crop_stage": "Ripening"}
        for i in range(1, 24)
    ]

    def test_pages_cover_every_row_once_in_a_stable_order(self):
        for sort in ("-created_at", "created_at", "level", "-municipality", "nonsense"):
            ordered = insights.sort_rows(self.rows, sort)
            pages = [insights.page(ordered, 5, o) for o in range(0, 25, 5)]
            ids = [r["id"] for p in pages for r in p]
            self.assertEqual(sorted(ids), sorted(r["id"] for r in self.rows), sort)
            self.assertEqual(ids, [r["id"] for r in insights.sort_rows(self.rows, sort)], sort)

    def test_relevance_and_not_recorded_land_filters(self):
        self.assertTrue(all(r["image_relevance"] == "possibly_unrelated"
                            for r in insights.filter_scans(self.rows, relevance="possibly_unrelated")))
        self.assertTrue(all(r["land_type"] == "" for r in insights.filter_scans(self.rows, land_type="not_recorded")))
        self.assertEqual(len(insights.filter_scans(self.rows, land_type="upland")), 12)


class CriteriaAndReviewTest(unittest.TestCase):
    thresholds = {("rice_bug", ""): {"medium_from": 4, "high_from": 10, "provisional": True},
                  ("rice_bug", "Ripening"): {"medium_from": 4, "high_from": 10, "provisional": False}}

    def test_provisional_threshold_is_flagged(self):
        r = levels.suggest(self.thresholds, "rice_bug", "Vegetative", 12, [])
        self.assertEqual(r["level"], "HIGH")
        self.assertTrue(r["provisional"])
        self.assertIn("provisional", r["reasons"][-1])
        confirmed = levels.suggest(self.thresholds, "rice_bug", "Ripening", 5, [])
        self.assertFalse(confirmed["provisional"])

    def test_reasons_are_translated(self):
        r = levels.suggest(self.thresholds, "rice_bug", "Ripening", 5,
                           ["Empty or unfilled grains"], lang="fil")
        self.assertTrue(r["reasons"][0].startswith("Bilang 5: KATAMTAMAN"))
        self.assertIn("Ipa o hindi napunong butil", r["reasons"][1])
        self.assertEqual(r["level"], "HIGH")

    def test_meaningful_reviewer_note(self):
        for bad in ("", "ok", "..........", "aaaaaaaaaaaa", "good"):
            self.assertFalse(obs.meaningful(bad), bad)
        self.assertTrue(obs.meaningful("Counted 6 bugs on two panicles"))

    def test_queue_labels_reuse_statuses(self):
        self.assertEqual(obs.queue_of("pending"), "not_validated")
        self.assertEqual(obs.queue_of("escalated"), "to_be_validated")
        self.assertIsNone(obs.queue_of("validated"))
        self.assertEqual(obs.QUEUE_LABELS["not_validated"], "Not Validated")


class TranslationTest(unittest.TestCase):
    def fields(self, s):
        return {f for _, f, _, _ in string.Formatter().parse(s) if f}

    def test_every_message_has_all_languages_and_placeholders(self):
        for key, entry in i18n.MESSAGES.items():
            for lang in i18n.LANGUAGES:
                self.assertTrue(entry.get(lang), f"{key} {lang}")
                self.assertEqual(self.fields(entry[lang]), self.fields(entry["en"]), f"{key} {lang}")

    def test_every_label_has_filipino_and_kinaray_a(self):
        for text_, entry in i18n.LABELS.items():
            self.assertTrue(entry.get("fil") and entry.get("krj"), text_)

    def test_request_language_precedence(self):
        class Req:
            headers = {"x-palay-language": "fil"}
        self.assertEqual(i18n.request_language(Req(), {"language": "krj"}, "en"), "en")
        self.assertEqual(i18n.request_language(Req(), {"language": "krj"}), "fil")
        self.assertEqual(i18n.request_language(None, {"language": "krj"}), "krj")
        self.assertEqual(i18n.request_language(None, None, "xx"), "en")

    def test_unknown_label_is_kept(self):
        self.assertEqual(i18n.t("Something new", "krj"), "Something new")


class GuideTest(unittest.TestCase):
    def test_model_detected_and_observed_are_separate(self):
        g = guide.content("en")
        self.assertEqual([p["key"] for p in g["model_detected"]], list(levels.SUPPORTED_PESTS))
        self.assertTrue(all(p["detected_by"] == "model" for p in g["model_detected"]))
        self.assertTrue(all(s["detected_by"] == "people" for s in g["observed_symptoms"]))
        self.assertEqual([c["model_label"] for c in g["model_classes"]],
                         ["brown-planthopper", "green-leafhopper", "rice-bug", "stem-borer"])
        self.assertEqual(g["translation_status"], "source")

    def test_translated_guide_is_marked_unreviewed(self):
        g = guide.content("krj")
        self.assertEqual(g["translation_status"], "machine_assisted_unreviewed")
        self.assertTrue(g["translation_note"])
        # Every visible string differs from English or is a deliberate term.
        self.assertNotEqual(g["model_detected"][0]["signs"][0], guide.PESTS[0]["signs"][0])
        self.assertEqual(len(g["glossary"]), len(guide.GLOSSARY))

    def test_no_expert_review_is_claimed(self):
        text_ = " ".join(str(v) for v in guide.content("fil").values())
        self.assertIsNone(re.search(r"expert[- ]reviewed", text_, re.I))


if __name__ == "__main__":
    unittest.main()
