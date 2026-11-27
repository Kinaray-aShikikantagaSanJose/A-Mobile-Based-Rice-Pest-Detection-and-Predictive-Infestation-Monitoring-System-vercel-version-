"""End-to-end checks of the 2026-11 update against a real PostgreSQL + PostGIS
database that has supabase/01_schema.sql and supabase/02_antique_locations.sql.

Skipped unless TEST_DATABASE_URL is set. Use a throwaway database, never the
live one, e.g. (local PostgreSQL with PostGIS; see supabase/README or the
deployment notes for the small Supabase stand-in the schema expects):

    set TEST_DATABASE_URL=postgresql://postgres@localhost:55432/palay_it
    python -m pytest tests/test_feature_update_integration.py -q

Connect as a role like Supabase's postgres (not a superuser, BYPASSRLS,
member of palay_rls_actor) so the row level security path is the real one.
Email sending and photo storage are replaced by in-memory fakes.
"""
import io
import os
import unittest
import uuid
from unittest.mock import patch

os.environ.setdefault("DATABASE_URL", "postgresql+psycopg2://user:pass@localhost:5432/unused")
os.environ.setdefault("JWT_SECRET_KEY", "integration-test-key-that-is-never-used-anywhere-else")

TEST_DB = os.getenv("TEST_DATABASE_URL", "")

from PIL import Image  # noqa: E402
from sqlalchemy import create_engine, text  # noqa: E402
from sqlalchemy.orm import sessionmaker  # noqa: E402
from sqlalchemy.pool import NullPool  # noqa: E402

# The app is imported only when the tests run (setUpClass), so importing this
# module never changes how other test modules configure the app.
engine = TestSession = app = auth = database = detector = storage = sync_router = None
create_access_token = hash_password = TestClient = None


def _load_app():
    global engine, TestSession, app, auth, database, detector, storage, sync_router
    global create_access_token, hash_password, TestClient
    from fastapi.testclient import TestClient as _TestClient

    from app import auth as _auth, database as _database, detector as _detector
    from app import storage as _storage, sync_router as _sync_router
    from app.main import app as _app
    from app.security import create_access_token as _cat, hash_password as _hp

    TestClient, auth, database, detector, storage, sync_router = (
        _TestClient, _auth, _database, _detector, _storage, _sync_router)
    app, create_access_token, hash_password = _app, _cat, _hp
    engine = create_engine(TEST_DB, poolclass=NullPool)
    TestSession = sessionmaker(bind=engine, autocommit=False, autoflush=False)

    def _db():
        db = TestSession()
        try:
            yield db
        finally:
            db.close()

    app.dependency_overrides[database.get_db] = _db
    app.dependency_overrides[database.get_geo_db] = _db

RUN = uuid.uuid4().hex[:8]
PASSWORD = "Correct-horse-9"
SIBALOM_EGANA = "0600616024"     # Egaña, Sibalom
# A point well inside Egaña, Sibalom (its own interior point), and one in Iloilo City.
INSIDE_SIBALOM = None
ILOILO_CITY = (10.7202, 122.5621)


def _email(tag: str) -> str:
    return f"{tag}.{RUN}@it-palaypatrol.ph"


def _jpeg(seed: int = 1) -> bytes:
    import random

    rnd = random.Random(seed)
    img = Image.new("RGB", (800, 600))
    img.putdata([(rnd.randrange(256), rnd.randrange(256), rnd.randrange(256)) for _ in range(800 * 600)])
    out = io.BytesIO()
    img.save(out, "JPEG", quality=85)
    return out.getvalue()


def _ai(result: str) -> dict:
    meta = {"model": "rice_pest.onnx", "max_score": 0.03, "max_score_mirrored": 0.02, "image_width": 800,
            "image_height": 600, "quality_issue": None}
    if result == "no_pests_found":
        return {"status": "done", "result": result, "pest": None, "confidence": None, "count": 0,
                "countable": False, "detections": [], "message": detector.NO_PESTS_MESSAGE, "metadata": meta}
    if result == "failed":
        return {"status": "failed", "result": "failed", "pest": None, "confidence": None, "count": None,
                "countable": False, "detections": [], "message": "Automatic analysis is unavailable.",
                "metadata": {"model": "rice_pest.onnx", "error": "test"}}
    return {"status": "done", "result": "uncertain", "pest": None, "confidence": None, "count": None,
            "countable": False, "detections": [], "message": "Not sure.", "metadata": {**meta, "max_score": 0.3}}


@unittest.skipUnless(TEST_DB, "TEST_DATABASE_URL not set (needs a throwaway PostgreSQL + PostGIS database)")
class FeatureUpdateIntegration(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        _load_app()
        cls.client = TestClient(app, base_url="https://testserver")
        cls.files = {}
        cls.patches = [
            patch.object(storage, "put", side_effect=lambda b, k, d, content_type="image/jpeg": cls.files.__setitem__((b, k), d)),
            patch.object(storage, "get", side_effect=lambda b, k: cls.files.get((b, k))),
            patch.object(storage, "delete", side_effect=lambda b, k: cls.files.pop((b, k), None) is not None or True),
        ]
        for p in cls.patches:
            p.start()
        with engine.begin() as c:
            global INSIDE_SIBALOM
            row = c.execute(text("SELECT ST_Y(p), ST_X(p) FROM (SELECT ST_PointOnSurface(geom) p FROM barangays "
                                 "WHERE psgc = :p) x"), {"p": SIBALOM_EGANA}).first()
            INSIDE_SIBALOM = (row[0], row[1])
            for tag, role, muni, brgy, cov in (
                ("agri", "agriculturist", "San Jose de Buenavista", "Atabay", ""),
                ("techsib", "technician", "Sibalom", "Poblacion", ""),
                ("techham", "technician", "Hamtic", "Poblacion 1", ""),
                ("farmer", "farmer", "Sibalom", "Egaña", ""),
            ):
                c.execute(
                    text("INSERT INTO users (email, password_hash, full_name, role, region, barangay, phone, "
                         "status, is_verified, coverage_barangays) VALUES (:e, :h, :n, :r, :m, :b, '09171234567', "
                         "'approved', true, :c)"),
                    {"e": _email(tag), "h": hash_password(PASSWORD), "n": f"IT {tag}", "r": role, "m": muni,
                     "b": brgy, "c": cov},
                )

    @classmethod
    def tearDownClass(cls):
        for p in cls.patches:
            p.stop()
        app.dependency_overrides.clear()

    # ---------------------------------------------------------------- helpers

    def login(self, tag: str) -> dict:
        r = self.client.post("/auth/login", json={"email": _email(tag), "password": PASSWORD})
        self.assertEqual(r.status_code, 200, r.text)
        return r.json()

    def h(self, session: dict) -> dict:
        return {"Authorization": f"Bearer {session['access_token']}", "X-Palay-Client": "test"}

    def submit(self, session: dict, result: str = "uncertain", lat=None, lng=None, accuracy=None) -> dict:
        data = {"client_uuid": uuid.uuid4().hex, "report_type": "pest", "crop_stage": "Vegetative",
                "created_at": "2026-11-20T08:00:00+08:00", "land_type": "irrigated_lowland"}
        if lat is not None:
            data.update(lat=str(lat), lng=str(lng))
        if accuracy is not None:
            data["gps_accuracy"] = str(accuracy)
        with patch.object(detector, "analyze", return_value=_ai(result)):
            r = self.client.post("/sync/scans", data=data, files={"image": ("p.jpg", _jpeg(), "image/jpeg")},
                                 headers=self.h(session))
        self.assertEqual(r.status_code, 200, r.text)
        return r.json()

    def scalar(self, sql: str, **params):
        with engine.connect() as c:
            return c.execute(text(sql), params).scalar()

    # ---------------------------------------------------------------- OTP, sessions, language, location

    def test_otp_registration_login_logout_and_sessions(self):
        email = _email("newfarmer")
        sent = {}
        with patch.object(auth, "send_otp_email", side_effect=lambda to, code: sent.__setitem__(to, code)):
            r = self.client.post("/auth/register", json={
                "full_name": "New Farmer", "email": email, "password": PASSWORD, "phone": "0917 123 4567",
                "municipality": "Sibalom", "barangay": "Egaña", "role": "farmer",
                "barangay_psgc": SIBALOM_EGANA, "location_source": "gps", "preferred_language": "krj"})
            self.assertEqual(r.status_code, 200, r.text)
            self.assertRegex(sent[email], r"^\d{6}$")
            # A second code right away is refused (cooldown), the first stays valid.
            self.assertEqual(self.client.post("/auth/resend-otp", json={"email": email}).status_code, 429)
        bad = "000000" if sent[email] != "000000" else "111111"
        r = self.client.post("/auth/verify-otp", json={"email": email, "code": bad})
        self.assertEqual((r.status_code, r.json()["detail"]), (400, "Invalid verification code."))
        r = self.client.post("/auth/verify-otp", json={"email": email, "code": sent[email]})
        self.assertEqual(r.status_code, 200, r.text)

        self.assertEqual(self.client.post("/auth/login", json={"email": email, "password": "wrong-pass-1"}).status_code, 401)
        r = self.client.post("/auth/login", json={"email": email, "password": PASSWORD},
                             headers={"X-Palay-Client": "mobile", "User-Agent": "Dart/3.13 (dart:io)"})
        self.assertEqual(r.status_code, 200, r.text)
        s = r.json()
        self.assertEqual(s["preferred_language"], "krj")
        self.assertEqual(s["barangay_psgc"], SIBALOM_EGANA)
        self.assertEqual(s["municipality_psgc"], "0600616000")
        self.assertEqual(s["location_source"], "gps")
        self.assertEqual(self.client.get("/auth/me", headers=self.h(s)).status_code, 200)

        # Refresh keeps the same session; logout ends it and both tokens stop working.
        r = self.client.post("/auth/refresh", json={"refresh_token": s["refresh_token"]})
        self.assertEqual(r.status_code, 200)
        s2 = r.json()
        self.assertEqual(self.client.post("/auth/logout", headers=self.h(s2)).status_code, 200)
        self.assertEqual(self.client.get("/auth/me", headers=self.h(s2)).status_code, 401)
        self.assertEqual(self.client.get("/sync/scans/mine", headers=self.h(s)).status_code, 401)
        self.assertEqual(self.client.post("/auth/refresh", json={"refresh_token": s["refresh_token"]}).status_code, 401)
        self.assertEqual(self.client.post("/auth/logout", headers=self.h(s2)).status_code, 200)  # idempotent

        actions = [r[0] for r in engine.connect().execute(text(
            "SELECT action_type || ':' || outcome FROM user_activity_logs WHERE user_email = :e ORDER BY id"),
            {"e": email}).fetchall()]
        for expected in ("account_registered:success", "email_verified:failure", "email_verified:success",
                         "login_failed:failure", "login:success", "logout:success"):
            self.assertIn(expected, actions)
        st = engine.connect().execute(text(
            "SELECT client, ended_at IS NOT NULL AS ended, end_reason FROM user_sessions WHERE user_email = :e"),
            {"e": email}).fetchall()
        self.assertEqual(len(st), 1)
        self.assertEqual((st[0].client, st[0].ended, st[0].end_reason), ("mobile", True, "logout"))

    def test_location_codes_from_typed_names_and_profile_update(self):
        s = self.login("farmer")
        self.assertEqual(s["barangay_psgc"], None)  # created directly in SQL
        r = self.client.put("/auth/me", json={"barangay": "Egaña", "municipality": "Sibalom",
                                              "preferred_language": "fil"}, headers=self.h(s))
        self.assertEqual(r.status_code, 200, r.text)
        self.assertEqual((r.json()["barangay_psgc"], r.json()["preferred_language"]), (SIBALOM_EGANA, "fil"))
        # The saved names are kept exactly as typed.
        self.assertEqual(r.json()["barangay"], "Egaña")

    def test_legacy_token_without_session_still_works(self):
        token = create_access_token(_email("farmer"), "farmer")  # issued before sessions existed
        self.assertEqual(self.client.get("/sync/scans/mine", headers={"Authorization": f"Bearer {token}"}).status_code, 200)

    # ---------------------------------------------------------------- deletion

    def test_delete_permissions_and_farmer_sees_deletion(self):
        farmer, techsib, techham, agri = (self.login(t) for t in ("farmer", "techsib", "techham", "agri"))
        a = self.submit(farmer)
        b = self.submit(farmer)
        self.assertEqual(a["status"], "pending")

        r = self.client.delete(f"/sync/scans/{a['id']}", headers=self.h(farmer))
        self.assertEqual(r.status_code, 403)                     # farmers never delete
        r = self.client.delete(f"/sync/scans/{a['id']}", headers=self.h(techham))
        self.assertEqual(r.status_code, 404)                     # outside the technician's area
        stored = len(self.files)
        r = self.client.delete(f"/sync/scans/{a['id']}?reason=Duplicate photo", headers=self.h(techsib))
        self.assertEqual(r.status_code, 200, r.text)
        self.assertEqual(len(self.files), stored - 1)            # its photo was removed from storage

        self.assertEqual(self.client.get(f"/sync/scans/{a['id']}", headers=self.h(farmer)).status_code, 410)
        mine = [x["id"] for x in self.client.get("/sync/scans/mine", headers=self.h(farmer)).json()]
        self.assertNotIn(a["id"], mine)
        self.assertIn(b["id"], mine)
        self.assertEqual(self.scalar("SELECT deleted_by FROM deleted_records WHERE scan_id = :i", i=a["id"]),
                         _email("techsib"))
        note = self.client.get("/sync/notifications", headers=self.h(farmer)).json()["items"][0]
        self.assertEqual(note["kind"], "record_deleted")
        self.assertIn(f"#{a['id']}", note["body"])
        self.assertIn("Duplicate photo", note["body"])
        self.assertEqual(self.scalar(
            "SELECT count(*) FROM user_activity_logs WHERE action_type = 'observation_deleted' AND target_id = :i",
            i=str(a["id"])), 1)

        self.assertEqual(self.client.delete(f"/sync/scans/{b['id']}", headers=self.h(agri)).status_code, 200)
        self.assertEqual(self.client.delete(f"/sync/scans/{b['id']}", headers=self.h(agri)).status_code, 410)

    def test_role_permission_table_controls_deletion(self):
        farmer, techsib = self.login("farmer"), self.login("techsib")
        c = self.submit(farmer)
        with engine.begin() as conn:
            conn.execute(text("DELETE FROM role_permissions WHERE role = 'technician' AND permission = 'records.delete'"))
        try:
            self.assertEqual(self.client.delete(f"/sync/scans/{c['id']}", headers=self.h(techsib)).status_code, 403)
        finally:
            with engine.begin() as conn:
                conn.execute(text("INSERT INTO role_permissions (role, permission) VALUES ('technician', 'records.delete') "
                                  "ON CONFLICT DO NOTHING"))
        self.assertEqual(self.client.delete(f"/sync/scans/{c['id']}", headers=self.h(techsib)).status_code, 200)

    def test_database_policy_refuses_even_without_the_api_checks(self):
        farmer = self.login("farmer")
        d = self.submit(farmer)
        db = TestSession()
        try:
            outsider = {"email": _email("techham"), "role": "technician"}
            self.assertIsNone(sync_router._delete_scan_row(db, outsider, d["id"]))
            db.rollback()
            insider = {"email": _email("techsib"), "role": "technician"}
            self.assertIsNotNone(sync_router._delete_scan_row(db, insider, d["id"]))
            db.rollback()  # keep the row
        finally:
            db.close()
        self.assertEqual(self.scalar("SELECT count(*) FROM scans WHERE id = :i", i=d["id"]), 1)

    # ---------------------------------------------------------------- no pests found

    def test_no_pests_found_saves_result_then_deletes_photo(self):
        farmer, techsib = self.login("farmer"), self.login("techsib")
        before = set(self.files)
        r = self.submit(farmer, result="no_pests_found")
        self.assertEqual((r["status"], r["detection_result"], r["image_deleted"]), ("no_pests", "no_pests_found", True))
        self.assertEqual(r["ai"]["result"], "no_pests_found")
        self.assertEqual(set(self.files), before)          # the uploaded photo was removed again
        with engine.connect() as c:
            row = c.execute(text("SELECT validation_status, detection_result, detection_metadata, image_deleted_at "
                                 "FROM scans WHERE id = :i"), {"i": r["id"]}).first()
        self.assertEqual((row.validation_status, row.detection_result), ("no_pests", "no_pests_found"))
        self.assertIsNotNone(row.image_deleted_at)
        self.assertTrue(row.detection_metadata["image_deleted"])
        self.assertEqual(row.detection_metadata["max_score"], 0.03)
        img = self.client.get(f"/sync/scans/{r['id']}/image", headers=self.h(farmer))
        self.assertEqual(img.status_code, 404)
        self.assertIn("no pests", img.json()["detail"])
        queue = self.client.get("/sync/queue?kind=pest", headers=self.h(techsib)).json()
        self.assertNotIn(r["id"], [q["id"] for q in queue])

    def test_uncertain_and_failed_detections_are_never_pest_free(self):
        farmer = self.login("farmer")
        for result in ("uncertain", "failed"):
            before = set(self.files)
            r = self.submit(farmer, result=result)
            self.assertEqual(r["status"], "pending", result)
            self.assertEqual(r["detection_result"], result)
            self.assertFalse(r["image_deleted"])
            self.assertEqual(len(set(self.files) - before), 1)  # photo kept for the technician

    # ---------------------------------------------------------------- GPS location of observations

    def test_observation_gps_location_never_overwrites_profile(self):
        farmer = self.login("farmer")
        r = self.submit(farmer, lat=INSIDE_SIBALOM[0], lng=INSIDE_SIBALOM[1], accuracy=12)
        self.assertEqual((r["location_status"], r["gps_barangay_psgc"]), ("inside", SIBALOM_EGANA))
        r = self.submit(farmer, lat=ILOILO_CITY[0], lng=ILOILO_CITY[1])
        self.assertEqual((r["location_status"], r["gps_barangay_psgc"]), ("outside_antique", None))
        self.assertEqual(r["municipality"], "Sibalom")              # filed under the saved area
        r = self.submit(farmer)
        self.assertEqual(r["location_status"], "no_gps")
        self.assertEqual(self.scalar("SELECT barangay FROM users WHERE email = :e", e=_email("farmer")), "Egaña")

    # ---------------------------------------------------------------- notifications in the farmer's language

    def test_validation_notification_in_kinaray_a(self):
        farmer, techsib = self.login("farmer"), self.login("techsib")
        self.client.put("/auth/me", json={"preferred_language": "krj"}, headers=self.h(farmer))
        e = self.submit(farmer)
        r = self.client.post(f"/sync/scans/{e['id']}/review", headers=self.h(techsib), json={
            "action": "validate", "pest": "rice_bug", "count": 4, "countable": True, "level": "LOW",
            "reviewer_note": "Four rice bugs visible on the panicle, no grain damage yet"})
        self.assertEqual(r.status_code, 200, r.text)
        note = next(n for n in self.client.get("/sync/notifications", headers=self.h(farmer)).json()["items"]
                    if n["scan_id"] == e["id"])
        self.assertEqual(note["title"], "Na-validate: Tiyangaw (rice bug), manubo nga lebel it peste")

    # ---------------------------------------------------------------- activity log endpoints

    def test_activity_log_filters_and_access(self):
        agri, techsib = self.login("agri"), self.login("techsib")
        self.client.post("/auth/login", json={"email": _email("farmer"), "password": "nope-nope-1"})
        self.assertEqual(self.client.get("/dashboard/activity", headers=self.h(techsib)).status_code, 403)

        def get(**params):
            r = self.client.get("/dashboard/activity", params=params, headers=self.h(agri))
            self.assertEqual(r.status_code, 200, r.text)
            return r.json()

        everyone = get(q=RUN, limit=500)
        self.assertGreater(everyone["total"], 0)
        farmers = get(q=RUN, role="farmer", limit=500)
        self.assertTrue(farmers["items"] and all(i["user_role"] == "farmer" for i in farmers["items"]))
        failed = get(q=RUN, action="login_failed", limit=500)
        self.assertTrue(failed["items"] and all(i["action"] == "login_failed" and i["outcome"] == "failure"
                                                for i in failed["items"]))
        active = get(q=RUN, session_status="active", limit=500)
        self.assertTrue(active["items"] and all(i["session_status"] == "active" for i in active["items"]))
        none = get(q=RUN, session_status="none", limit=500)
        self.assertTrue(all(i["session_id"] is None for i in none["items"]))
        self.assertEqual(get(q=RUN, start="2000-01-01", end="2000-01-02")["total"], 0)
        one = get(email=_email("techsib"), limit=500)
        self.assertTrue(all(i["user_email"] == _email("techsib") for i in one["items"]))

        sessions = self.client.get("/dashboard/activity/sessions", params={"q": RUN}, headers=self.h(agri)).json()
        self.assertTrue(sessions["items"])
        self.assertTrue({s["status"] for s in sessions["items"]} <= {"active", "ended", "expired"})
        csv = self.client.get("/dashboard/activity/export", params={"q": RUN}, headers=self.h(agri))
        self.assertEqual(csv.status_code, 200)
        self.assertIn("Session status", csv.text.splitlines()[0])

    def test_dashboard_me_reports_permissions(self):
        me = self.client.get("/dashboard/me", headers=self.h(self.login("techsib"))).json()
        self.assertEqual((me["can_delete_records"], me["can_view_activity"]), (True, False))
        me = self.client.get("/dashboard/me", headers=self.h(self.login("agri"))).json()
        self.assertEqual((me["can_delete_records"], me["can_view_activity"]), (True, True))


if __name__ == "__main__":
    unittest.main()
