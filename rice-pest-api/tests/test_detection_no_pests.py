"""Detection pipeline with the deployed model (models/rice_pest_yolo26s.onnx):
model loading and its class contract, the separate image-relevance screen,
the "no pests found" decision, and the guard on unverified class labels.
No database needed.

"No pests found" must never be given to a photo with pests, a poor photo, a
failed run, or a photo that may not show a field at all."""
import os
import unittest
from unittest.mock import patch

os.environ.setdefault("DATABASE_URL", "postgresql+psycopg2://user:pass@localhost:5432/unused")

import numpy as np  # noqa: E402
from PIL import Image, ImageOps  # noqa: E402

from app import detector  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PEST_PHOTOS = ["brown_planthopper.jpg", "green_leafhopper.jpg", "rice_bug.jpg", "rice_stem_borer.jpg",
               "rice_bug_odor.jpg", "bore_holes_frass.jpg"]
FIELD_PHOTOS = ["hopperburn.jpg", "deadhearts.jpg", "whiteheads.jpg", "stunted_plants.jpg", "tungro_discoloration.jpg"]


def _texture(colour_range, seed=3) -> Image.Image:
    """A sharp, evenly lit 1024x768 picture (random texture in a colour range)."""
    rnd = np.random.default_rng(seed)
    lo, hi = colour_range
    a = rnd.integers(lo, hi, size=(768, 1024, 3), dtype=np.uint8)
    return Image.fromarray(a, "RGB")


def _grey() -> Image.Image:
    rnd = np.random.default_rng(3)
    g = rnd.integers(60, 200, size=(768, 1024), dtype=np.uint8)
    return Image.fromarray(np.stack([g, g, g], axis=2), "RGB")


def _green() -> Image.Image:
    """Leaf-like texture: green channel high, red/blue lower."""
    rnd = np.random.default_rng(5)
    r = rnd.integers(30, 90, size=(768, 1024), dtype=np.uint8)
    g = rnd.integers(110, 200, size=(768, 1024), dtype=np.uint8)
    b = rnd.integers(20, 70, size=(768, 1024), dtype=np.uint8)
    return Image.fromarray(np.stack([r, g, b], axis=2), "RGB")


def _photo(name: str) -> Image.Image:
    img = ImageOps.exif_transpose(Image.open(os.path.join(ROOT, "guide_photos", name))).convert("RGB")
    img.thumbnail((detector.MAX_IMAGE_SIDE, detector.MAX_IMAGE_SIDE))
    return img


def _nothing(_session, _img):
    return np.zeros((0, 4)), np.zeros(0), np.zeros(0, dtype=int), 0.02


def _one_box(pest: str, conf: float = 0.9):
    """The same confident box in the photo and its mirror image."""
    k = detector.CLASSES.index(pest)

    def run(_session, img):
        w, h = img.size
        box = np.array([[w * 0.4, h * 0.4, w * 0.5, h * 0.5]])
        return box, np.array([conf]), np.array([k]), conf
    return run


class ModelContract(unittest.TestCase):
    def test_deployed_model_loads_with_the_expected_classes(self):
        st = detector.status()
        self.assertTrue(st["available"], st["error"])
        self.assertEqual(st["model"], "rice_pest_yolo26s.onnx")
        self.assertIn("YOLO26s", st["info"]["description"])
        self.assertEqual(st["info"]["end2end"], "False")

    def test_a_model_with_other_classes_is_refused(self):
        class FakeSession:
            def get_modelmeta(self):
                return type("M", (), {"custom_metadata_map": {"names": "{0: 'a', 1: 'b', 2: 'c', 3: 'd'}"}})()

            def get_inputs(self):
                return [type("I", (), {"shape": [1, 3, 640, 640]})()]

            def get_outputs(self):
                return [type("O", (), {"shape": [1, 8, 8400]})()]

        with self.assertRaises(ValueError):
            detector._check_model(FakeSession())

    def test_failed_model_is_failed_but_still_screened(self):
        with patch.object(detector, "_get_session", return_value=None):
            r = detector.analyze(_photo("whiteheads.jpg"))
        self.assertEqual((r["status"], r["result"]), ("failed", "failed"))
        self.assertEqual(r["relevance"], detector.RELEVANT)


class Relevance(unittest.TestCase):
    def test_field_photos_are_relevant(self):
        for name in FIELD_PHOTOS:
            with self.subTest(name):
                self.assertEqual(detector.image_relevance(_photo(name))["status"], detector.RELEVANT)

    def test_unrelated_looking_photos_are_flagged_not_rejected(self):
        for name, img in (("grey wall", _grey()), ("black frame", Image.new("RGB", (900, 700), (5, 5, 5))),
                          ("skin tones", _texture((150, 220))), ("blue", Image.new("RGB", (900, 700), (40, 90, 200)))):
            with self.subTest(name):
                rel = detector.image_relevance(img)
                self.assertEqual(rel["status"], detector.POSSIBLY_UNRELATED)
                self.assertTrue(rel["provisional"])

    def test_pest_evidence_counts_as_relevant(self):
        self.assertEqual(detector.image_relevance(_grey(), pest_evidence=True)["basis"], "pest_detected")


@unittest.skipUnless(detector.status()["available"], "ONNX model or onnxruntime not available")
class NoPestsDecision(unittest.TestCase):
    def test_pest_photos_are_never_pest_free(self):
        for name in PEST_PHOTOS:
            with self.subTest(name):
                r = detector.analyze(_photo(name))
                self.assertNotEqual(r["result"], "no_pests_found")
                self.assertIn(r["result"], ("pests_found", "uncertain"))
                self.assertIn("max_score", r["metadata"])
                self.assertEqual(r["metadata"]["model"], "rice_pest_yolo26s.onnx")

    def test_dark_blurry_or_small_photos_are_uncertain_not_pest_free(self):
        dark = Image.new("RGB", (1024, 768), (8, 10, 8))
        flat = Image.new("RGB", (1024, 768), (90, 140, 60))      # no detail at all = "blurry"
        small = _green().resize((320, 240))
        for name, img in (("dark", dark), ("flat", flat), ("small", small)):
            with self.subTest(name):
                r = detector.analyze(img)
                self.assertEqual(r["result"], "uncertain")
                self.assertIsNone(r["count"])

    def test_clear_field_photo_with_nothing_detected_is_pest_free(self):
        with patch.object(detector, "_run", side_effect=_nothing):
            r = detector.analyze(_green())
        self.assertEqual((r["result"], r["count"], r["pest"]), ("no_pests_found", 0, None))
        self.assertEqual(r["metadata"]["max_score"], 0.02)
        self.assertEqual(r["relevance"], detector.RELEVANT)

    def test_unrelated_photo_with_nothing_detected_is_not_pest_free(self):
        # Same "nothing detected" signal, but the photo shows no plants: the
        # answer is "a technician checks it", never "no pests".
        with patch.object(detector, "_run", side_effect=_nothing):
            r = detector.analyze(_grey())
        self.assertEqual(r["result"], "uncertain")
        self.assertEqual(r["relevance"], detector.POSSIBLY_UNRELATED)
        self.assertEqual(r["message"], detector.UNRELATED_MESSAGE)

    def test_weak_signal_is_uncertain(self):
        with patch.object(detector, "_run", side_effect=lambda s, im: (
                np.zeros((0, 4)), np.zeros(0), np.zeros(0, dtype=int), detector.NO_PEST_MAX_SCORE + 0.01)):
            r = detector.analyze(_green())
        self.assertEqual(r["result"], "uncertain")


class UnverifiedLabels(unittest.TestCase):
    def setUp(self):
        self.session = patch.object(detector, "_get_session", return_value=object())
        self.session.start()

    def tearDown(self):
        self.session.stop()

    def test_unverified_class_is_never_named(self):
        for pest in ("rice_bug", "rice_stem_borer"):
            with self.subTest(pest), patch.object(detector, "_run", side_effect=_one_box(pest)):
                r = detector.analyze(_green())
            self.assertEqual((r["result"], r["pest"], r["count"]), ("uncertain", None, None))
            self.assertEqual(r["message"], detector.UNVERIFIED_MESSAGE)
            self.assertEqual(r["metadata"]["unverified_class"], pest)
            self.assertEqual(len(r["detections"]), 1)            # boxes kept for the technician
            self.assertEqual(r["relevance"], detector.RELEVANT)

    def test_verified_class_is_named(self):
        with patch.object(detector, "_run", side_effect=_one_box("green_leafhopper")):
            r = detector.analyze(_green())
        self.assertEqual((r["result"], r["pest"]), ("pests_found", "green_leafhopper"))

    def test_guard_can_be_lifted_after_the_labels_are_checked(self):
        with patch.object(detector, "UNVERIFIED_CLASSES", frozenset()), \
                patch.object(detector, "_run", side_effect=_one_box("rice_bug")):
            r = detector.analyze(_green())
        self.assertEqual((r["result"], r["pest"]), ("pests_found", "rice_bug"))


if __name__ == "__main__":
    unittest.main()
