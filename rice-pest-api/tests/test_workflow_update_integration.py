"""End-to-end checks of the 2026-12 update against a real PostgreSQL + PostGIS
database prepared with supabase/01_schema.sql, 02_antique_locations.sql,
SQL/01-02 and supabase/03_2026_12_update.sql. Skipped unless
TEST_DATABASE_URL is set (a throwaway database; see
tests/test_feature_update_integration.py for the setup notes).

Covers: reviewer notes, recommendations kept apart from applied treatments,
review queues ("Not Validated" / "To Be Validated") and paging, land type
corrections and who may make them, server-side paging + exports with the
same filters and translated headers, treatment outcomes (a pest-free photo
is not proof), the image relevance flag, provisional thresholds, and
role checks done by the server.
"""
import csv
import io
import os
import unittest
import uuid
from unittest.mock import patch

os.environ.setdefault("DATABASE_URL", "postgresql+psycopg2://user:pass@localhost:5432/unused")
os.environ.setdefault("JWT_SECRET_KEY", "integration-test-key-that-is-never-used-anywhere-else")

from PIL import Image  # noqa: E402
from sqlalchemy import text as sql_text  # noqa: E402

try:  # shared app/DB loader (pytest puts tests/ on sys.path)
    import test_feature_update_integration as fi  # noqa: E402
except ImportError:  # pragma: no cover
    import tests.test_feature_update_integration as fi  # noqa: E402

TEST_DB = fi.TEST_DB
PASSWORD = fi.PASSWORD
RUN = uuid.uuid4().hex[:8]
NOTE = "Checked the photo: insects clearly visible on the leaves"


def _email(tag: str) -> str:
    return f"wf-{tag}.{RUN}@it-palaypatrol.ph"


def _grey_jpeg() -> bytes:
    img = Image.new("RGB", (900, 700), (128, 128, 128))
    out = io.BytesIO()
    img.save(out, "JPEG", quality=85)
    return out.getvalue()


def _ai(result: str = "uncertain", relevance: str = "relevant", pest=None, count=None, conf=None) -> dict:
    rel = {"status": relevance, "plant_fraction": 0.5 if relevance == "relevant" else 0.0,
           "basis": "plant_colour" if relevance == "relevant" else "little_plant_colour",
           "min_plant_fraction": 0.1, "provisional": True}
    meta = {"model": "rice_pest_yolo26s.onnx", "max_score": 0.03, "max_score_mirrored": 0.02,
            "image_width": 800, "image_height": 600, "quality_issue": None, "relevance": rel}
    return {"status": "done", "result": result, "pest": pest, "confidence": conf, "count": count,
            "countable": count is not None, "detections": [], "message": "", "metadata": meta,
            "relevance": relevance}


@unittest.skipUnless(TEST_DB, "TEST_DATABASE_URL not set (needs a throwaway PostgreSQL + PostGIS database)")
class WorkflowUpdateIntegration(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        fi._load_app()
        from sqlalchemy import text

        cls.text = text
        cls.client = fi.TestClient(fi.app, base_url="https://testserver")
        cls.files = {}
        cls.patches = [
            patch.object(fi.storage, "put", side_effect=lambda b, k, d, content_type="image/jpeg": cls.files.__setitem__((b, k), d)),
            patch.object(fi.storage, "get", side_effect=lambda b, k: cls.files.get((b, k))),
            patch.object(fi.storage, "delete", side_effect=lambda b, k: cls.files.pop((b, k), None) is not None or True),
        ]
        for p in cls.patches:
            p.start()
        with fi.engine.begin() as c:
            for tag, role, muni, brgy in (
                ("agri", "agriculturist", "San Jose de Buenavista", "Atabay"),
                ("techsib", "technician", "Sibalom", "Poblacion"),
                ("techham", "technician", "Hamtic", "Poblacion 1"),
                ("farmer", "farmer", "Sibalom", "Egaña"),
            ):
                c.execute(
                    text("INSERT INTO users (email, password_hash, full_name, role, region, barangay, phone, "
                         "status, is_verified) VALUES (:e, :h, :n, :r, :m, :b, '09171234567', 'approved', true)"),
                    {"e": _email(tag), "h": fi.hash_password(PASSWORD), "n": f"WF {tag}", "r": role, "m": muni,
                     "b": brgy},
                )
            cls.rice_bug_option = c.execute(text(
                "SELECT id FROM treatment_library WHERE pest = 'rice_bug' AND status = 'approved' ORDER BY id LIMIT 1"
            )).scalar()
            cls.draft_option = c.execute(text(
                "INSERT INTO treatment_library (pest, title, recommendation, status, option_type, source_reference) "
                "VALUES ('rice_bug', 'WF draft option', 'Not approved yet.', 'draft', 'cultural', 'test source') "
                "RETURNING id")).scalar()
        cls.sessions = {}

    @classmethod
    def tearDownClass(cls):
        for p in cls.patches:
            p.stop()
        fi.app.dependency_overrides.clear()

    # ---------------------------------------------------------------- helpers

    def s(self, tag: str) -> dict:
        if tag not in self.sessions:
            r = self.client.post("/auth/login", json={"email": _email(tag), "password": PASSWORD})
            self.assertEqual(r.status_code, 200, r.text)
            self.sessions[tag] = r.json()
        return self.sessions[tag]

    def h(self, tag: str, **extra) -> dict:
        return {"Authorization": f"Bearer {self.s(tag)['access_token']}", "X-Palay-Client": "test", **extra}

    def submit(self, tag="farmer", ai=None, report_type="pest", image=None, **fields) -> dict:
        data = {"client_uuid": uuid.uuid4().hex, "report_type": report_type, "crop_stage": "Reproductive",
                "created_at": "2026-11-20T08:00:00+08:00", "land_type": "irrigated_lowland", **fields}
        if report_type == "disease":
            data.setdefault("notes", "Brown spots on leaves")
        img = image or fi._jpeg()
        with patch.object(fi.detector, "analyze", return_value=ai or _ai()):
            r = self.client.post("/sync/scans", data=data, files={"image": ("p.jpg", img, "image/jpeg")},
                                 headers=self.h(tag))
        self.assertEqual(r.status_code, 200, r.text)
        return r.json()

    def validate(self, scan_id, tag="techsib", level="HIGH", count=8, **extra):
        body = {"action": "validate", "pest": "rice_bug", "count": count, "countable": True, "level": level,
                "reviewer_note": NOTE, **extra}
        return self.client.post(f"/sync/scans/{scan_id}/review", headers=self.h(tag), json=body)

    # ---------------------------------------------------------------- reviews and recommendations

    def test_reviewer_note_is_required_and_distinct(self):
        e = self.submit()
        r = self.validate(e["id"], reviewer_note="ok")
        self.assertEqual(r.status_code, 400)
        self.assertIn("reviewer note", r.json()["detail"])
        r = self.validate(e["id"], reviewer_note="Spray only in the morning please", guidance="Spray only in the morning please")
        self.assertEqual(r.status_code, 400)
        self.assertIn("not a copy", r.json()["detail"])
        r = self.validate(e["id"], guidance="Check again in a week.")
        self.assertEqual(r.status_code, 200, r.text)
        detail = self.client.get(f"/sync/scans/{e['id']}", headers=self.h("techsib")).json()
        h = detail["history"][-1]
        self.assertEqual((h["action"], h["reviewer_note"], h["guidance"]), ("validated", NOTE, "Check again in a week."))
        # The farmer sees the guidance; the reviewer note stays in the staff history.
        farmer_view = self.client.get(f"/sync/scans/{e['id']}", headers=self.h("farmer")).json()
        self.assertNotIn("history", farmer_view)
        self.assertEqual(farmer_view["guidance"], "Check again in a week.")

    def test_recommendations_are_kept_apart_from_applied_treatments(self):
        e = self.submit()
        r = self.validate(e["id"], recommended_library_ids=[self.draft_option])
        self.assertEqual(r.status_code, 400)                       # drafts can't be recommended
        r = self.validate(e["id"], recommended_library_ids=[self.rice_bug_option])
        self.assertEqual(r.status_code, 200, r.text)
        rec = self.client.get(f"/sync/scans/{e['id']}", headers=self.h("farmer")).json()
        self.assertEqual([x["library_id"] for x in rec["recommended"]], [self.rice_bug_option])
        self.assertEqual(rec["treatments"], [])                    # recommended != applied
        flagged = [o for g in rec["recommendations"]["groups"].values() for o in g if o.get("recommended")]
        self.assertEqual([o["id"] for o in flagged], [self.rice_bug_option])
        note = next(n for n in self.client.get("/sync/notifications", headers=self.h("farmer")).json()["items"]
                    if n["scan_id"] == e["id"])
        self.assertIn("recommended", note["body"])
        # The farmer records what was actually done, with the date.
        r = self.client.post(f"/sync/scans/{e['id']}/treatments", headers=self.h("farmer"), json={
            "client_uuid": uuid.uuid4().hex, "library_id": self.rice_bug_option, "applied_at": "2026-11-21"})
        self.assertEqual(r.status_code, 200, r.text)
        t = r.json()["treatments"][0]
        self.assertEqual((t["applied_at"][:10], t["follow_up_due"]), ("2026-11-21", "2026-11-28"))
        items = self.client.get("/analytics/treatments", headers=self.h("agri")).json()["items"]
        mine = next(i for i in items if i["id"] == t["id"])
        self.assertTrue(mine["was_recommended"])
        self.assertEqual(mine["outcome"], "overdue" if mine["follow_up_due"] < "2026-11-27" else "awaiting follow-up")

    def test_follow_up_date_change_needs_staff(self):
        e = self.submit()
        self.assertEqual(self.validate(e["id"]).status_code, 200)
        r = self.client.post(f"/sync/scans/{e['id']}/treatments", headers=self.h("farmer"), json={
            "client_uuid": uuid.uuid4().hex, "custom_text": "Hand-picked the bugs", "applied_at": "2026-11-22"})
        tid = r.json()["treatments"][0]["id"]
        self.assertEqual(self.client.patch(f"/dashboard/treatments/{tid}", headers=self.h("farmer"),
                                           json={"follow_up_due": "2026-12-05"}).status_code, 403)
        self.assertEqual(self.client.patch(f"/dashboard/treatments/{tid}", headers=self.h("techham"),
                                           json={"follow_up_due": "2026-12-05"}).status_code, 404)  # not their area
        r = self.client.patch(f"/dashboard/treatments/{tid}", headers=self.h("techsib"), json={"follow_up_due": "2026-12-05"})
        self.assertEqual((r.status_code, r.json()["follow_up_due"]), (200, "2026-12-05"))

    # ---------------------------------------------------------------- outcomes

    def test_pest_free_follow_up_photo_is_not_counted_as_improved(self):
        e = self.submit()
        self.assertEqual(self.validate(e["id"], level="HIGH", count=12).status_code, 200)
        t = self.client.post(f"/sync/scans/{e['id']}/treatments", headers=self.h("farmer"), json={
            "client_uuid": uuid.uuid4().hex, "custom_text": "Drained the field", "applied_at": "2026-11-21"}
        ).json()["treatments"][0]
        f = self.submit(ai=_ai("no_pests_found"), follow_up_of=t["id"])
        self.assertEqual(f["status"], "no_pests")
        item = next(i for i in self.client.get("/analytics/treatments", headers=self.h("agri")).json()["items"]
                    if i["id"] == t["id"])
        self.assertEqual(item["outcome"], "not comparable")
        self.assertIn("not reviewed", item["outcome_basis"])

        # A reviewed follow-up of the same pest at a lower level is "improved".
        t2 = self.client.post(f"/sync/scans/{e['id']}/treatments", headers=self.h("farmer"), json={
            "client_uuid": uuid.uuid4().hex, "custom_text": "Second try", "applied_at": "2026-11-22"}
        ).json()["treatments"][-1]
        f2 = self.submit(follow_up_of=t2["id"])
        pending = next(i for i in self.client.get("/analytics/treatments", headers=self.h("agri")).json()["items"]
                       if i["id"] == t2["id"])
        self.assertEqual(pending["outcome"], "follow-up in review")      # pending stays pending
        self.assertTrue(pending["pending"])
        self.assertEqual(self.validate(f2["id"], level="LOW", count=2).status_code, 200)
        done = next(i for i in self.client.get("/analytics/treatments", headers=self.h("agri")).json()["items"]
                    if i["id"] == t2["id"])
        self.assertEqual((done["outcome"], done["before_level"], done["after_level"]), ("improved", "HIGH", "LOW"))
        self.assertEqual((done["before_count"], done["after_count"]), (12, 2))

    # ---------------------------------------------------------------- queues and paging

    def test_queues_reuse_statuses_and_page(self):
        ids = [self.submit()["id"] for _ in range(3)]
        r = self.client.get("/sync/queue?kind=pest&limit=2", headers=self.h("techsib"))
        self.assertEqual(r.status_code, 200)
        self.assertEqual(len(r.json()), 2)
        self.assertGreaterEqual(int(r.headers["X-Total-Count"]), 3)
        self.assertTrue(all(q["queue"] == "not_validated" for q in r.json()))
        r2 = self.client.get("/sync/queue?kind=pest&limit=2&offset=2", headers=self.h("techsib")).json()
        self.assertFalse({q["id"] for q in r.json()} & {q["id"] for q in r2})
        bad = self.client.post(f"/sync/scans/{ids[0]}/review", headers=self.h("techsib"),
                               json={"action": "escalate", "reason": "help"})
        self.assertEqual(bad.status_code, 400)
        r = self.client.post(f"/sync/scans/{ids[0]}/review", headers=self.h("techsib"),
                             json={"action": "escalate", "reason": "Unusual insect, may be a different pest"})
        self.assertEqual((r.status_code, r.json()["status"], r.json()["queue"]), (200, "escalated", "to_be_validated"))
        q = self.client.get("/sync/queue?kind=pest&queue=to_be_validated", headers=self.h("agri")).json()
        self.assertIn(ids[0], [x["id"] for x in q])
        self.assertTrue(all(x["queue"] == "to_be_validated" for x in q))
        # Resolving an escalation needs diagnosis and guidance.
        r = self.validate(ids[0], tag="agri")
        self.assertEqual(r.status_code, 400)
        r = self.validate(ids[0], tag="agri", diagnosis="Rice bug, early infestation",
                          guidance="Remove weeds around the field.")
        self.assertEqual(r.status_code, 200, r.text)

    def test_records_paging_and_export_cover_the_same_rows(self):
        for _ in range(3):
            self.submit()
        base = "/analytics/records?status=all&municipality=Sibalom&sort=-created_at"
        first = self.client.get(base + "&limit=2&offset=0", headers=self.h("agri")).json()
        second = self.client.get(base + "&limit=2&offset=2", headers=self.h("agri")).json()
        everything = self.client.get(base, headers=self.h("agri")).json()
        self.assertEqual(first["total"], everything["total"])
        self.assertGreaterEqual(first["total"], 3)
        self.assertFalse({r["id"] for r in first["rows"]} & {r["id"] for r in second["rows"]})
        self.assertEqual([r["id"] for r in first["rows"] + second["rows"]],
                         [r["id"] for r in everything["rows"][:4]])
        r = self.client.get("/dashboard/reports/records?status=all&municipality=Sibalom&lang=fil",
                            headers=self.h("agri"))
        self.assertEqual(r.status_code, 200)
        rows = list(csv.reader(io.StringIO(r.text.lstrip("﻿"))))
        self.assertEqual(rows[0][0], "ID ng obserbasyon")
        self.assertEqual(len(rows) - 1, everything["total"])            # every matching row, no paging
        self.assertEqual(self.client.get("/dashboard/reports/records", headers=self.h("techsib")).status_code, 403)

    # ---------------------------------------------------------------- land type

    def test_land_type_corrections_and_permissions(self):
        e = self.submit()
        url = f"/sync/scans/{e['id']}/land-type"
        r = self.client.patch(url, headers=self.h("farmer"), json={"land_type": "rainfed_lowland"})
        self.assertEqual((r.status_code, r.json()["land_type"]), (200, "rainfed_lowland"))
        self.assertEqual(self.client.patch(url, headers=self.h("techham"), json={"land_type": "upland"}).status_code, 404)
        r = self.client.patch(url, headers=self.h("techsib"), json={"land_type": "upland", "reason": "Field is on a slope"})
        self.assertEqual((r.status_code, r.json()["land_type"]), (200, "upland"))
        self.assertEqual(r.json()["land_type_updated_by"], _email("techsib"))
        self.assertEqual(self.validate(e["id"]).status_code, 200)
        r = self.client.patch(url, headers=self.h("farmer"), json={"land_type": "irrigated_lowland"})
        self.assertEqual(r.status_code, 403)                               # after review: staff only
        r = self.client.patch(url, headers=self.h("agri"), json={"land_type": "irrigated_lowland"})
        self.assertEqual(r.status_code, 200)
        hist = self.client.get(f"/sync/scans/{e['id']}", headers=self.h("agri")).json()["history"]
        changes = [h for h in hist if h["action"] == "land_type_changed"]
        self.assertEqual(len(changes), 3)
        self.assertIn("Upland", changes[1]["note"])
        self.assertEqual(self.client.patch(url, headers=self.h("agri"), json={"land_type": "paddy"}).status_code, 422)
        listed = self.client.get("/analytics/records?land_type=irrigated_lowland&status=all",
                                 headers=self.h("agri")).json()["rows"]
        self.assertIn(e["id"], [x["id"] for x in listed])

    # ---------------------------------------------------------------- relevance

    def test_possibly_unrelated_photo_is_flagged_never_pest_free(self):
        before = set(self.files)
        e = self.submit(ai=_ai("uncertain", relevance="possibly_unrelated"))
        self.assertEqual((e["status"], e["image_relevance"], e["image_deleted"]), ("pending", "possibly_unrelated", False))
        self.assertEqual(len(set(self.files) - before), 1)                   # photo kept for review
        # Disease reports get the screen too (no model): a plain grey photo.
        d = self.submit(report_type="disease", image=_grey_jpeg())
        self.assertEqual(d["image_relevance"], "possibly_unrelated")
        flagged = self.client.get("/analytics/records?status=all&relevance=possibly_unrelated",
                                  headers=self.h("agri")).json()["rows"]
        self.assertTrue({e["id"], d["id"]} <= {r["id"] for r in flagged})

    def test_real_model_end_to_end_through_the_upload(self):
        """No mocks on the detector: the deployed ONNX model analyses real
        uploads and its answers are stored with the observation."""
        if not fi.detector.status()["available"]:
            self.skipTest("model not available")
        here = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

        def upload(img_bytes):
            data = {"client_uuid": uuid.uuid4().hex, "report_type": "pest", "crop_stage": "Reproductive",
                    "created_at": "2026-11-20T08:00:00+08:00", "land_type": "irrigated_lowland"}
            r = self.client.post("/sync/scans", data=data, files={"image": ("p.jpg", img_bytes, "image/jpeg")},
                                 headers=self.h("farmer"))
            self.assertEqual(r.status_code, 200, r.text)
            return r.json()

        with open(os.path.join(here, "guide_photos", "brown_planthopper.jpg"), "rb") as f:
            pest = upload(f.read())
        self.assertIn(pest["detection_result"], ("pests_found", "uncertain"))
        self.assertEqual(pest["image_relevance"], "relevant")
        self.assertNotEqual(pest["status"], "no_pests")
        grey = upload(_grey_jpeg())
        self.assertEqual((grey["detection_result"], grey["image_relevance"], grey["status"]),
                         ("uncertain", "possibly_unrelated", "pending"))
        with fi.engine.connect() as c:
            meta = c.execute(sql_text("SELECT detection_metadata FROM scans WHERE id = :i"), {"i": grey["id"]}).scalar()
        self.assertEqual(meta["model"], "rice_pest_yolo26s.onnx")
        self.assertEqual(meta["relevance"]["status"], "possibly_unrelated")

    # ---------------------------------------------------------------- thresholds and roles

    def test_thresholds_are_provisional_until_confirmed(self):
        crit = self.client.get("/dashboard/criteria", headers=self.h("techsib")).json()
        row = next(t for c in crit if c["pest"] == "rice_bug" for t in c["thresholds"] if t["crop_stage"] == "")
        self.assertTrue(row["provisional"])
        url = f"/dashboard/criteria/{row['id']}/confirm"
        body = {"source_reference": "Checked against the provincial IPM guide 2026"}
        self.assertEqual(self.client.post(url, headers=self.h("techsib"), json=body).status_code, 403)
        r = self.client.post(url, headers=self.h("agri"), json=body)
        self.assertEqual((r.status_code, r.json()["provisional"]), (200, False))
        r = self.client.put("/dashboard/criteria", headers=self.h("agri"), json={
            "pest": "rice_bug", "crop_stage": "", "medium_from": row["medium_from"], "high_from": row["high_from"] + 1})
        self.assertEqual((r.status_code, r.json()["provisional"]), (200, True))  # edited = provisional again

    def test_server_enforces_roles(self):
        farmer = self.h("farmer")
        for method, url in (("get", "/analytics/records"), ("get", "/sync/queue"), ("get", "/dashboard/users"),
                            ("get", "/analytics/spread"), ("get", "/dashboard/reports/records")):
            self.assertEqual(getattr(self.client, method)(url, headers=farmer).status_code, 403, url)
        self.assertEqual(self.client.get("/dashboard/users", headers=self.h("techsib")).status_code, 403)
        r = self.client.get("/dashboard/users?role=technician&limit=1", headers=self.h("agri"))
        self.assertEqual((r.status_code, len(r.json())), (200, 1))
        self.assertGreaterEqual(int(r.headers["X-Total-Count"]), 2)
        self.assertEqual(self.client.get("/analytics/records").status_code, 401)

    def test_spread_endpoint_custom_range_and_language(self):
        r = self.client.get("/analytics/spread?start=2026-11-01&end=2026-11-20&lang=krj", headers=self.h("agri"))
        self.assertEqual(r.status_code, 200, r.text)
        body = r.json()
        self.assertTrue(body["custom_range"])
        self.assertEqual(body["language"], "krj")
        self.assertEqual([w["days"] for w in body["windows"]], [10, 10])
        self.assertEqual(self.client.get("/analytics/spread?start=2026-11-20&end=2026-11-20",
                                         headers=self.h("agri")).status_code, 400)

    def test_guide_and_level_reasons_follow_the_language(self):
        g = self.client.get("/guide?lang=fil", headers=self.h("farmer")).json()
        self.assertEqual(g["translation_status"], "machine_assisted_unreviewed")
        self.assertIn("model_detected", g)
        r = self.client.get("/sync/level-suggestion?pest=rice_bug&crop_stage=Ripening&count=3",
                            headers=self.h("techsib", **{"X-Palay-Language": "krj"})).json()
        self.assertEqual(r["language"], "krj")
        self.assertTrue(r["reasons"][0].startswith("Kadamuon 3"))


if __name__ == "__main__":
    unittest.main()
