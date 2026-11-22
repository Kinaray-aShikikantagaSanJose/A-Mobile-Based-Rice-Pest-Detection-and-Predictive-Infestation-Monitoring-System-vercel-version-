"""The "no pests found" decision (app/detector.py) must never mark a photo
with pests, a poor photo, or a failed run as pest-free. Uses the real model
(models/rice_pest.onnx) and the guide photos; no database needed."""
import os
import unittest
from unittest.mock import patch

os.environ.setdefault("DATABASE_URL", "postgresql+psycopg2://user:pass@localhost:5432/unused")

from PIL import Image, ImageOps  # noqa: E402

from app import detector  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PEST_PHOTOS = ["brown_planthopper.jpg", "green_leafhopper.jpg", "rice_bug.jpg", "rice_stem_borer.jpg",
               "rice_bug_odor.jpg", "bore_holes_frass.jpg"]


def _clear() -> Image.Image:
    """A sharp, evenly lit 1024x768 picture (random texture)."""
    import random

    rnd = random.Random(3)
    img = Image.new("RGB", (1024, 768))
    img.putdata([(rnd.randrange(60, 200),) * 3 for _ in range(1024 * 768)])
    return img


def _photo(name: str) -> Image.Image:
    img = ImageOps.exif_transpose(Image.open(os.path.join(ROOT, "guide_photos", name))).convert("RGB")
    img.thumbnail((detector.MAX_IMAGE_SIDE, detector.MAX_IMAGE_SIDE))
    return img


@unittest.skipUnless(detector.status()["available"], "ONNX model or onnxruntime not available")
class NoPestsDecision(unittest.TestCase):
    def test_pest_photos_are_never_pest_free(self):
        for name in PEST_PHOTOS:
            with self.subTest(name):
                r = detector.analyze(_photo(name))
                self.assertNotEqual(r["result"], "no_pests_found")
                self.assertIn(r["result"], ("pests_found", "uncertain"))
                self.assertIn("max_score", r["metadata"])

    def test_dark_blurry_or_small_photos_are_uncertain_not_pest_free(self):
        dark = Image.new("RGB", (1024, 768), (8, 10, 8))
        flat = Image.new("RGB", (1024, 768), (120, 140, 110))      # no detail at all = "blurry"
        small = _clear().resize((320, 240))
        for name, img in (("dark", dark), ("flat", flat), ("small", small)):
            with self.subTest(name):
                r = detector.analyze(img)
                self.assertEqual(r["result"], "uncertain")
                self.assertIsNone(r["count"])

    def test_clear_photo_with_nothing_detected_is_pest_free(self):
        img = _clear()
        with patch.object(detector, "_run", side_effect=lambda s, im: (
                __import__("numpy").zeros((0, 4)), __import__("numpy").zeros(0),
                __import__("numpy").zeros(0, dtype=int), 0.02)):
            r = detector.analyze(img)
        self.assertEqual((r["result"], r["count"], r["pest"]), ("no_pests_found", 0, None))
        self.assertEqual(r["metadata"]["max_score"], 0.02)
        self.assertIsNone(r["metadata"]["quality_issue"])

    def test_weak_signal_is_uncertain(self):
        img = _clear()
        np = __import__("numpy")
        with patch.object(detector, "_run", side_effect=lambda s, im: (
                np.zeros((0, 4)), np.zeros(0), np.zeros(0, dtype=int), detector.NO_PEST_MAX_SCORE + 0.01)):
            r = detector.analyze(img)
        self.assertEqual(r["result"], "uncertain")

    def test_failed_model_is_failed(self):
        with patch.object(detector, "_get_session", return_value=None):
            r = detector.analyze(_photo("whiteheads.jpg"))
        self.assertEqual((r["status"], r["result"]), ("failed", "failed"))


if __name__ == "__main__":
    unittest.main()
