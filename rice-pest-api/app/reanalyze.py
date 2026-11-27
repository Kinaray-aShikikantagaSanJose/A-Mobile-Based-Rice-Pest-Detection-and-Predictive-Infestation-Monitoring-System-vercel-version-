"""Re-runs the pest detector on observations nobody has reviewed yet.

Use after changing the model or the detector settings (run on your own
computer with the same DATABASE_URL / SUPABASE_* values as the Vercel API):
    python -m app.reanalyze            # pending pest reports
    python -m app.reanalyze --dry-run  # show what would change

Reviewed observations are never touched: the technician's decision stands.
A pending photo that now comes out "no pests found" stays pending here (this
tool never deletes photos or closes observations); its detection result and
metadata are updated so a technician can decide.
"""
import io
import json
import sys

from PIL import Image
from sqlalchemy import text

from . import detector, schema, storage
from .database import GeoSessionLocal


def main(dry_run: bool) -> None:
    status = detector.status()
    if not status["available"]:
        sys.exit(f"Detector unavailable: {status['error']}")
    db = GeoSessionLocal()
    try:
        rows = db.execute(
            text("SELECT id, image_filename, ai_pest, ai_count FROM scans "
                 "WHERE report_type = 'pest' AND validation_status = 'pending' ORDER BY id")
        ).fetchall()
        for r in rows:
            data = storage.get(storage.SCANS, r.image_filename)
            if data is None:
                print(f"#{r.id}: photo missing, skipped")
                continue
            ai = detector.analyze(Image.open(io.BytesIO(data)).convert("RGB"))
            print(f"#{r.id}: {r.ai_pest} / {r.ai_count}  ->  {ai['pest']} / {ai['count']}"
                  f"  ({len(ai['detections'])} boxes) {ai['message'] or ''}")
            if dry_run:
                continue
            if schema.detection_ready(db):
                db.execute(
                    text("UPDATE scans SET detection_result = :r, detection_metadata = CAST(:m AS jsonb) "
                         "WHERE id = :i AND validation_status = 'pending'"),
                    {"r": ai.get("result") or "uncertain", "m": json.dumps(ai.get("metadata") or {}), "i": r.id},
                )
            if schema.relevance_ready(db) and ai.get("relevance"):
                db.execute(
                    text("UPDATE scans SET image_relevance = :rel WHERE id = :i AND validation_status = 'pending'"),
                    {"rel": ai["relevance"], "i": r.id},
                )
            db.execute(
                text(
                    """
                    UPDATE scans
                    SET ai_status = :status, ai_pest = :pest, ai_confidence = :conf, ai_count = :count,
                        ai_countable = :countable, ai_detections = CAST(:dets AS jsonb),
                        ai_message = :msg, total_count = :total, dominant_class = :dominant
                    WHERE id = :i AND validation_status = 'pending'
                    """
                ),
                {"status": ai["status"], "pest": ai["pest"], "conf": ai["confidence"], "count": ai["count"],
                 "countable": bool(ai["countable"]), "dets": json.dumps(ai["detections"]),
                 "msg": ai["message"] or "", "total": ai["count"] or 0, "dominant": ai["pest"] or "",
                 "i": r.id},
            )
        if not dry_run:
            db.commit()
        print(f"{len(rows)} pending pest observation(s) {'checked' if dry_run else 're-analysed'}.")
    finally:
        db.close()


if __name__ == "__main__":
    main("--dry-run" in sys.argv)
