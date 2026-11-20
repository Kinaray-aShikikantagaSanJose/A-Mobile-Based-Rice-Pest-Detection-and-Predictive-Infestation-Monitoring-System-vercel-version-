"""Mobile app API: observations, records, treatments, notifications, and the
technician / agriculturist review queue."""
import json
import os
from datetime import date, datetime, timedelta, timezone
from typing import List, Literal, Optional
from uuid import uuid4

from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile
from fastapi.responses import Response
from pydantic import BaseModel, Field
from sqlalchemy import text
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from . import detector, land, levels, observations as obs, schema, storage
from .access import AGRICULTURIST, EVERYONE, STAFF, TECHNICIAN, require_role
from .database import get_geo_db, local_today

router = APIRouter(prefix="/sync", tags=["Mobile"])

# Photos live in Supabase Storage (bucket "scans"), see app/storage.py.
# Vercel refuses request bodies over 4.5 MB before they reach this code; the
# apps send photos of at most 2048 px, which stay well under that.
MAX_UPLOAD_BYTES = 15 * 1024 * 1024
CROP_STAGES = levels.CROP_STAGES


def _parse_time(value: str) -> datetime:
    try:
        dt = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        raise HTTPException(status_code=400, detail="created_at must be an ISO date-time.")
    # Older builds sent local time without an offset; the phones are in the Philippines.
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone(timedelta(hours=8)))
    return dt


def _record_for_owner(db: Session, scan_id: int, viewer: dict) -> dict:
    row = obs.load(db, scan_id)
    if row is None:
        raise HTTPException(status_code=404, detail="Observation not found.")
    staff_view = viewer["role"] in STAFF and (
        obs.in_scope(viewer, row.area, row.brgy) or row.user_email == viewer["email"]
    )
    if row.user_email != viewer["email"] and not staff_view:
        raise HTTPException(status_code=404, detail="Observation not found.")
    rec = obs.shape(row, staff=staff_view)
    rec["treatments"] = obs.treatments_for(db, [row.id]).get(row.id, [])
    rec["recommendations"] = (
        obs.recommendations(db, row.confirmed_pest, row.crop_phase or "", row.infestation_level,
                            owner_email=row.user_email)
        if rec["confirmed"] else None
    )
    rec["is_mine"] = row.user_email == viewer["email"]
    return rec


# ---------------------------------------------------------------- observations

@router.post("/scans")
def submit_observation(
    image: UploadFile = File(...),
    client_uuid: str = Form(..., min_length=8, max_length=64),
    report_type: Literal["pest", "disease"] = Form(...),
    crop_stage: str = Form(...),
    created_at: str = Form(...),
    # Required: upland | rainfed_lowland | irrigated_lowland (see app/land.py).
    land_type: str = Form(""),
    # The elevation the phone looked up for the land type suggestion, if any.
    elevation_m: Optional[float] = Form(None),
    lat: Optional[float] = Form(None),
    lng: Optional[float] = Form(None),
    monitoring_method: Literal["direct", "trap"] = Form("direct"),
    trap_type: str = Form("", max_length=50),
    target_pest: str = Form("", max_length=50),
    target_sex: str = Form("", max_length=30),
    notes: str = Form("", max_length=4000),
    follow_up_of: Optional[int] = Form(None),
    resubmission_of: Optional[int] = Form(None),
    db: Session = Depends(get_geo_db),
    user: dict = Depends(require_role(*EVERYONE)),
):
    # A retried upload (lost response, flaky signal) returns the first copy.
    existing = db.execute(
        text("SELECT id, user_email FROM scans WHERE client_uuid = :u"), {"u": client_uuid}
    ).first()
    if existing:
        if existing.user_email != user["email"]:
            raise HTTPException(status_code=409, detail="Duplicate upload id.")
        return _record_for_owner(db, existing.id, user)

    if crop_stage not in CROP_STAGES:
        raise HTTPException(status_code=400, detail=f"crop_stage must be one of {', '.join(CROP_STAGES)}.")
    if land_type not in land.LAND_TYPES:
        raise HTTPException(status_code=400,
                            detail="Choose the land type: upland, rainfed lowland or irrigated lowland.")
    if elevation_m is not None and not (-500 <= elevation_m <= 9000):
        elevation_m = None
    notes = notes.strip()
    if report_type == "disease" and not notes:
        raise HTTPException(status_code=400, detail="Describe what you observed for a disease report.")
    if (lat is None) != (lng is None) or (lat is not None and not (-90 <= lat <= 90 and -180 <= lng <= 180)):
        raise HTTPException(status_code=400, detail="Invalid location.")
    if lat == 0 and lng == 0:  # old builds' "no GPS" sentinel
        lat = lng = None
    if follow_up_of is not None:
        owner = db.execute(
            text("SELECT s.user_email FROM treatments t JOIN scans s ON s.id = t.scan_id WHERE t.id = :t"),
            {"t": follow_up_of},
        ).first()
        if owner is None or owner.user_email != user["email"]:
            raise HTTPException(status_code=400, detail="That treatment isn't one of yours.")

    if resubmission_of is not None:
        # A retake after the technician returned the photo (photo unclear).
        original = db.execute(
            text("SELECT user_email, validation_status FROM scans WHERE id = :i"), {"i": resubmission_of}
        ).first()
        if original is None or original.user_email != user["email"]:
            raise HTTPException(status_code=400, detail="That observation isn't one of yours.")
        if original.validation_status != "returned":
            raise HTTPException(status_code=400, detail="Only a returned observation can be retaken.")

    raw = image.file.read(MAX_UPLOAD_BYTES + 1)
    if len(raw) > MAX_UPLOAD_BYTES:
        raise HTTPException(status_code=413, detail="Photo is too large (15 MB at most).")
    # Never build the path from image.filename: a name like "../../app/x.py"
    # would be written outside uploads/.
    filename = f"{datetime.now(timezone.utc).strftime('%Y%m%d%H%M%S%f')}_{uuid4().hex}.jpg"
    try:
        photo, jpeg = detector.normalize_photo(raw)
    except Exception:
        raise HTTPException(status_code=400, detail="The photo could not be read. Please retake it.")
    try:
        storage.put(storage.SCANS, filename, jpeg)
    except Exception:
        raise HTTPException(status_code=503, detail="The photo could not be stored right now. Please try again.")

    # The model runs here, after upload, and only for pest reports.
    ai = detector.analyze(photo) if report_type == "pest" else None
    try:
        row = _insert_scan(db, user, filename, notes, lat, lng, created_at, client_uuid, report_type,
                           crop_stage, monitoring_method, trap_type, target_pest, target_sex,
                           follow_up_of, resubmission_of, ai, land_type, elevation_m)
    except IntegrityError:
        # A retry that raced the first upload (slow signal): keep the first copy.
        db.rollback()
        storage.delete(storage.SCANS, filename)
        existing = db.execute(
            text("SELECT id, user_email FROM scans WHERE client_uuid = :u"), {"u": client_uuid}
        ).first()
        if existing is None:
            raise HTTPException(status_code=400, detail="The observation could not be saved. Please try again.")
        if existing.user_email != user["email"]:
            raise HTTPException(status_code=409, detail="Duplicate upload id.")
        return _record_for_owner(db, existing.id, user)
    return _record_for_owner(db, row.id, user)


def _insert_scan(db, user, filename, notes, lat, lng, created_at, client_uuid, report_type, crop_stage,
                 monitoring_method, trap_type, target_pest, target_sex, follow_up_of, resubmission_of, ai,
                 land_type="", elevation_m=None):
    trap = report_type == "pest" and monitoring_method == "trap"
    # Stored once sql/011 has run; until then the land type is accepted but not kept.
    with_land = schema.land_type_ready(db)
    land_cols = ", land_type, elevation_m" if with_land else ""
    land_vals = ", :land_type, :elevation_m" if with_land else ""
    row = db.execute(
        text(
            f"""
            INSERT INTO scans (user_email, image_filename, notes, geom, created_at, client_uuid,
                               report_type, crop_phase, monitoring_method, trap_type, target_pest,
                               target_sex, symptoms, municipality, barangay, submitted_by_role,
                               follow_up_of, resubmission_of, ai_status, ai_pest, ai_confidence, ai_count,
                               ai_countable, ai_detections, ai_message,
                               total_count, dominant_class, validation_status{land_cols})
            VALUES (:email, :filename, :notes,
                    CASE WHEN CAST(:lat AS double precision) IS NULL THEN NULL
                         ELSE ST_SetSRID(ST_MakePoint(:lng, :lat), 4326) END,
                    :created, :uuid, :type, :stage, :method, :trap_type, :target_pest,
                    :target_sex, :symptoms, :area, :brgy, :role, :follow_up, :resubmission_of,
                    :ai_status, :ai_pest, :ai_conf, :ai_count, :ai_countable,
                    CAST(:ai_detections AS jsonb), :ai_message,
                    :total, :dominant, 'pending'{land_vals})
            RETURNING id
            """
        ),
        {
            "email": user["email"], "filename": filename, "notes": notes,
            "lat": lat, "lng": lng, "created": _parse_time(created_at), "uuid": client_uuid,
            "type": report_type, "stage": crop_stage,
            "method": "" if report_type == "disease" else (obs.METHOD_TRAP if trap else obs.METHOD_DIRECT),
            "trap_type": trap_type.strip() if trap else "",
            "target_pest": target_pest.strip() if trap else "",
            "target_sex": target_sex.strip() if trap else "",
            "symptoms": notes if report_type == "disease" else "",
            "area": user["area"], "brgy": user["barangay"], "role": user["role"],
            "follow_up": follow_up_of,
            "resubmission_of": resubmission_of,
            "ai_status": ai["status"] if ai else "skipped",
            "ai_pest": ai["pest"] if ai else None,
            "ai_conf": ai["confidence"] if ai else None,
            "ai_count": ai["count"] if ai else None,
            "ai_countable": bool(ai and ai["countable"]),
            "ai_detections": json.dumps(ai["detections"] if ai else []),
            "ai_message": (ai["message"] or "") if ai else "",
            # Legacy columns kept filled for older reports.
            "total": (ai["count"] or 0) if ai else 0,
            "dominant": (ai["pest"] or "") if ai else "",
            "land_type": land_type,
            "elevation_m": elevation_m,
        },
    ).first()
    db.commit()
    return row


@router.get("/scans/mine")
def my_observations(
    db: Session = Depends(get_geo_db),
    user: dict = Depends(require_role(*EVERYONE)),
):
    rows = db.execute(
        text(f"{obs.SELECT} WHERE s.user_email = :e ORDER BY s.created_at DESC, s.id DESC"),
        {"e": user["email"]},
    ).fetchall()
    treatments = obs.treatments_for(db, [r.id for r in rows])
    out = []
    for r in rows:
        rec = obs.shape(r)
        rec["treatments"] = treatments.get(r.id, [])
        out.append(rec)
    return out


@router.get("/scans/{scan_id}")
def observation_detail(
    scan_id: int,
    db: Session = Depends(get_geo_db),
    user: dict = Depends(require_role(*EVERYONE)),
):
    rec = _record_for_owner(db, scan_id, user)
    if user["role"] in STAFF:
        rec["history"] = [
            {
                "action": h.action, "reviewer": h.reviewer, "reviewer_name": h.reviewer_name or h.reviewer,
                "reviewer_role": h.reviewer_role,
                "pest": h.pest, "count": h.corrected_count, "countable": h.countable,
                "level": h.level, "note": h.note or h.diagnosis, "created_at": obs._iso(h.created_at),
            }
            for h in db.execute(
                text("SELECT r.*, u.full_name AS reviewer_name FROM scan_reviews r "
                     "LEFT JOIN users_fdw u ON u.email = r.reviewer "
                     "WHERE r.scan_id = :i ORDER BY r.created_at, r.id"), {"i": scan_id}
            ).fetchall()
        ]
    if user["role"] == AGRICULTURIST and rec.get("status") in ("pending", "escalated"):
        # Same routing as the queue: escalations, and pending work from places
        # no technician covers, are the agriculturist's to decide.
        if rec["status"] == "escalated":
            rec["queue_reason"] = "escalated"
        else:
            covered = obs.has_technician(obs.technician_coverage(db), rec.get("municipality"), rec.get("barangay"))
            rec["queue_reason"] = "pending" if covered else "no_technician"
    return rec


@router.get("/scans/{scan_id}/image")
def scan_image(
    scan_id: int,
    db: Session = Depends(get_geo_db),
    user: dict = Depends(require_role(*EVERYONE)),
):
    row = db.execute(
        text(
            f"""SELECT s.image_filename, s.user_email,
                       COALESCE(NULLIF(btrim(s.municipality), ''), btrim(u.region), '') AS area,
                       COALESCE(NULLIF(btrim(s.barangay), ''), btrim(u.barangay), '') AS brgy
                FROM scans s LEFT JOIN users_fdw u ON u.email = s.user_email WHERE s.id = :i"""
        ),
        {"i": scan_id},
    ).first()
    # Owners see their photos; staff see photos in their area. Same 404 otherwise.
    if row is None or (
        row.user_email != user["email"]
        and not (user["role"] in STAFF and obs.in_scope(user, row.area, row.brgy))
    ):
        raise HTTPException(status_code=404, detail="Scan not found.")
    # storage.get refuses unsafe names (rows saved before the upload fix may
    # hold names like "../../x").
    data = storage.get(storage.SCANS, row.image_filename)
    if data is None:
        raise HTTPException(status_code=404, detail="Image file missing.")
    return Response(content=data, media_type="image/jpeg",
                    headers={"Cache-Control": "private, max-age=86400"})


@router.get("/land-type-suggestion")
def land_type_suggestion(
    lat: float,
    lng: float,
    user: dict = Depends(require_role(*EVERYONE)),
):
    """A land type to start from, based on the field's elevation (free
    elevation service). The person always confirms or corrects it."""
    if not (-90 <= lat <= 90 and -180 <= lng <= 180) or (lat == 0 and lng == 0):
        raise HTTPException(status_code=400, detail="Invalid location.")
    return {**land.suggest(land.lookup_elevation(lat, lng)),
            "upland_min_elevation_m": land.UPLAND_MIN_ELEVATION_M}


# ---------------------------------------------------------------- treatments

class TreatmentIn(BaseModel):
    client_uuid: str = Field(min_length=8, max_length=64)
    library_id: Optional[int] = None
    custom_text: str = Field("", max_length=500)
    applied_at: date


@router.post("/scans/{scan_id}/treatments")
def log_treatment(
    scan_id: int,
    payload: TreatmentIn,
    db: Session = Depends(get_geo_db),
    user: dict = Depends(require_role(*EVERYONE)),
):
    existing = db.execute(
        text("SELECT id FROM treatments WHERE client_uuid = :u"), {"u": payload.client_uuid}
    ).first()
    if existing:
        return _record_for_owner(db, scan_id, user)
    row = obs.load(db, scan_id)
    if row is None or row.user_email != user["email"]:
        raise HTTPException(status_code=404, detail="Observation not found.")
    if row.report_type != "pest" or row.validation_status != "validated":
        raise HTTPException(status_code=409, detail="Treatments can be logged once a pest observation is validated.")
    if payload.applied_at > local_today():
        raise HTTPException(status_code=400, detail="The date can't be in the future.")
    option_type, name = "own", payload.custom_text.strip()
    if payload.library_id is not None:
        entry = db.execute(
            text("SELECT title, option_type FROM treatment_library WHERE id = :i AND status = 'approved'"),
            {"i": payload.library_id},
        ).first()
        if entry is None:
            raise HTTPException(status_code=400, detail="That option is no longer in the approved list.")
        option_type, name = entry.option_type, entry.title
    if not name:
        raise HTTPException(status_code=400, detail="Pick an option or describe what you did.")
    db.execute(
        text(
            """
            INSERT INTO treatments (scan_id, submitted_by, treatment, applied_at, pre_count,
                                    client_uuid, library_id, option_type, follow_up_due)
            VALUES (:scan, :by, :name, :applied, :pre, :uuid, :lib, :type, :due)
            """
        ),
        {
            "scan": scan_id, "by": user["email"], "name": name,
            "applied": datetime.combine(payload.applied_at, datetime.min.time(), tzinfo=timezone.utc),
            "pre": row.confirmed_count or 0, "uuid": payload.client_uuid,
            "lib": payload.library_id, "type": option_type,
            "due": obs.follow_up_due(payload.applied_at),
        },
    )
    db.commit()
    return _record_for_owner(db, scan_id, user)


# ---------------------------------------------------------------- notifications

@router.get("/notifications")
def notifications(
    db: Session = Depends(get_geo_db),
    user: dict = Depends(require_role(*EVERYONE)),
):
    rows = db.execute(
        text(
            "SELECT id, scan_id, kind, title, body, created_at, read_at FROM notifications "
            "WHERE user_email = :e ORDER BY created_at DESC, id DESC LIMIT 50"
        ),
        {"e": user["email"]},
    ).fetchall()
    unread = db.execute(
        text("SELECT COUNT(*) FROM notifications WHERE user_email = :e AND read_at IS NULL"),
        {"e": user["email"]},
    ).scalar()
    return {
        "unread": unread,
        "items": [
            {"id": r.id, "scan_id": r.scan_id, "kind": r.kind, "title": r.title, "body": r.body,
             "created_at": obs._iso(r.created_at), "read": r.read_at is not None}
            for r in rows
        ],
    }


class ReadIn(BaseModel):
    ids: List[int] = []
    all: bool = False


@router.post("/notifications/read")
def mark_read(
    payload: ReadIn,
    db: Session = Depends(get_geo_db),
    user: dict = Depends(require_role(*EVERYONE)),
):
    if payload.all:
        db.execute(
            text("UPDATE notifications SET read_at = now() WHERE user_email = :e AND read_at IS NULL"),
            {"e": user["email"]},
        )
    elif payload.ids:
        db.execute(
            text(
                "UPDATE notifications SET read_at = now() "
                "WHERE user_email = :e AND read_at IS NULL AND id = ANY(:ids)"
            ),
            {"e": user["email"], "ids": payload.ids},
        )
    db.commit()
    return {"ok": True}


# ---------------------------------------------------------------- review queue

@router.get("/queue")
def review_queue(
    kind: Literal["pest", "disease"] = "pest",
    db: Session = Depends(get_geo_db),
    user: dict = Depends(require_role(*STAFF)),
):
    """Technicians: pending observations in their coverage area, oldest first.
    Agriculturists: escalated cases, plus pending observations from places no
    technician covers (so nothing waits forever unseen)."""
    params: dict = {"kind": kind}
    if user["role"] == TECHNICIAN:
        scope = obs.scope_sql(user, params)
        # Their own observations too, even from outside their coverage.
        params["me"] = user["email"]
        mine = "s.user_email = :me"
        where = "s.validation_status = 'pending' AND s.report_type = :kind AND " + (
            f"({scope} OR {mine})" if scope else mine
        )
        rows = db.execute(text(f"{obs.SELECT} WHERE {where} ORDER BY s.created_at ASC, s.id ASC"), params).fetchall()
        return [{**obs.shape(r, staff=True), "queue_reason": "pending"} for r in rows]

    rows = db.execute(
        text(f"{obs.SELECT} WHERE s.validation_status IN ('escalated', 'pending') AND s.report_type = :kind "
             "ORDER BY s.created_at ASC, s.id ASC"),
        params,
    ).fetchall()
    coverage = obs.technician_coverage(db)
    out = []
    for r in rows:
        if r.validation_status == "escalated":
            out.append({**obs.shape(r, staff=True), "queue_reason": "escalated"})
        elif not obs.has_technician(coverage, r.area, r.brgy):
            out.append({**obs.shape(r, staff=True), "queue_reason": "no_technician"})
    return out


@router.get("/level-suggestion")
def level_suggestion(
    pest: str,
    crop_stage: str = "",
    count: Optional[int] = None,
    indicators: str = "",
    db: Session = Depends(get_geo_db),
    user: dict = Depends(require_role(*STAFF)),
):
    chosen = [i for i in indicators.split("|") if i]
    result = levels.suggest(levels.load_thresholds(db), pest, crop_stage, count, chosen)
    return {**result, "available_indicators": levels.indicators_for(pest)}


class ReviewIn(BaseModel):
    """The reviewer first confirms or corrects the result, then decides:
    return (photo unclear), validate (level confirmed) or escalate (complex case)."""
    action: Literal["validate", "return", "escalate"]
    # validate, pest report: the pest (the model result's or corrected), count or not countable
    pest: Optional[str] = None
    count: Optional[int] = Field(None, ge=0, le=100000)
    countable: bool = True
    damage_indicators: List[str] = []
    # validate, any report: the confirmed infestation level
    level: Optional[Literal["LOW", "MEDIUM", "HIGH"]] = None
    # diagnosis + guidance: required when an agriculturist resolves an escalated
    # case, optional otherwise
    diagnosis: str = Field("", max_length=2000)
    guidance: str = Field("", max_length=4000)
    # return / escalate
    reason: str = Field("", max_length=1000)


@router.post("/scans/{scan_id}/review")
def review(
    scan_id: int,
    payload: ReviewIn,
    db: Session = Depends(get_geo_db),
    user: dict = Depends(require_role(*STAFF)),
):
    row = obs.load(db, scan_id)
    if row is None or not (obs.in_scope(user, row.area, row.brgy) or row.user_email == user["email"]):
        raise HTTPException(status_code=404, detail="Observation not found.")
    # Technicians review pending work in their area (their own submissions are
    # validated by themselves). Agriculturists resolve escalations and can act on
    # pending work too (e.g. from a place no technician covers).
    allowed = ("pending", "escalated") if user["role"] == AGRICULTURIST else ("pending",)
    if row.validation_status not in allowed:
        raise HTTPException(status_code=409, detail="This observation has already been handled.")
    is_pest = row.report_type == "pest"
    escalated = row.validation_status == "escalated"
    notify_owner = row.user_email != user["email"]
    reason = payload.reason.strip()
    diagnosis, guidance = payload.diagnosis.strip(), payload.guidance.strip()

    if payload.action == "return":
        # Photo unclear: the farmer retakes it and the new photo goes through again.
        if not reason:
            raise HTTPException(status_code=400, detail="Tell the farmer why (e.g. photo too blurry).")
        db.execute(
            text("UPDATE scans SET validation_status = 'returned', return_reason = :r, "
                 "validated_by = :by, validated_at = now() WHERE id = :i"),
            {"r": reason, "by": user["email"], "i": scan_id},
        )
        obs.log_review(db, scan_id, user, "returned", note=reason)
        if notify_owner:
            obs.notify(db, row.user_email, scan_id, "returned", "Please retake the photo", reason)
        db.commit()
        return _record_for_owner(db, scan_id, user)

    if payload.action == "escalate":
        if user["role"] == AGRICULTURIST:
            raise HTTPException(status_code=400, detail="Agriculturists resolve escalations; they can't escalate.")
        if not reason:
            raise HTTPException(status_code=400, detail="Say why it needs an agriculturist.")
        db.execute(
            text("UPDATE scans SET validation_status = 'escalated', escalation_reason = :r, "
                 "validated_by = :by, validated_at = now() WHERE id = :i"),
            {"r": reason, "by": user["email"], "i": scan_id},
        )
        obs.log_review(db, scan_id, user, "escalated", note=reason)
        if notify_owner:
            obs.notify(db, row.user_email, scan_id, "escalated", "Sent to an agriculturist",
                       "Your observation needs a closer look. An agriculturist will review it.")
        db.commit()
        return _record_for_owner(db, scan_id, user)

    # ---- validate: the level is confirmed
    if not payload.level:
        raise HTTPException(status_code=400, detail="Confirm the infestation level.")
    if escalated and (not diagnosis or not guidance):
        raise HTTPException(status_code=400, detail="Record the diagnosis and the guidance for the farmer.")

    if is_pest:
        pest = payload.pest
        if pest not in levels.SUPPORTED_PESTS and pest != levels.OTHER_PEST:
            raise HTTPException(status_code=400, detail="Pick one of the four pests, or 'outside the supported set'.")
        count = payload.count if payload.countable else None
        if payload.countable and count is None:
            raise HTTPException(status_code=400, detail="Enter the count, or mark it not countable.")
        indicators = [i for i in payload.damage_indicators if i in levels.indicators_for(pest)]
        suggestion = levels.suggest(levels.load_thresholds(db), pest, row.crop_phase or "", count, indicators)
        db.execute(
            text(
                """
                UPDATE scans
                SET validation_status = 'validated', confirmed_pest = :pest, confirmed_count = :count,
                    countable = :countable, infestation_level = :level, suggested_level = :suggested,
                    damage_indicators = :indicators,
                    diagnosis = CASE WHEN :diag = '' THEN diagnosis ELSE :diag END,
                    guidance = CASE WHEN :guid = '' THEN guidance ELSE :guid END,
                    corrected_count = :count, validated_by = :by, validated_at = now()
                WHERE id = :i
                """
            ),
            {"pest": pest, "count": count, "countable": count is not None, "level": payload.level,
             "suggested": suggestion["level"], "indicators": indicators, "diag": diagnosis,
             "guid": guidance, "by": user["email"], "i": scan_id},
        )
        changes = []
        if row.ai_pest and pest != row.ai_pest:
            changes.append(f"pest corrected from {obs.pest_name(row.ai_pest)} to {obs.pest_name(pest)}")
        elif not row.ai_pest:
            changes.append(f"pest identified as {obs.pest_name(pest)}")
        if row.ai_count != count:
            changes.append("marked not countable" if count is None else f"count set to {count}")
        if payload.level != suggestion["level"]:
            changes.append(f"level {payload.level} (suggested {suggestion['level']})")
        obs.log_review(db, scan_id, user, "validated", pest=pest, count=count, countable=count is not None,
                       level=payload.level, indicators=indicators, diagnosis=diagnosis, guidance=guidance,
                       note="; ".join(changes) or "confirmed the model result")
        title = f"Validated: {obs.pest_name(pest)}, {payload.level.lower()} infestation"
        body = "Open the record to see the guidance and your treatment options." if guidance \
            else "Open the record to see your treatment options."
    else:  # disease report: no model result; the level is confirmed, diagnosis optional unless escalated
        db.execute(
            text(
                """
                UPDATE scans
                SET validation_status = 'validated', infestation_level = :level,
                    diagnosis = CASE WHEN :diag = '' THEN diagnosis ELSE :diag END,
                    guidance = CASE WHEN :guid = '' THEN guidance ELSE :guid END,
                    validated_by = :by, validated_at = now()
                WHERE id = :i
                """
            ),
            {"level": payload.level, "diag": diagnosis, "guid": guidance, "by": user["email"], "i": scan_id},
        )
        obs.log_review(db, scan_id, user, "validated", level=payload.level, diagnosis=diagnosis,
                       guidance=guidance, note=f"disease report, {payload.level.lower()} level")
        title = (f"Disease report reviewed: {payload.level.lower()} level" if not diagnosis
                 else "Diagnosis and guidance are ready")
        body = diagnosis or "Open the record to see what the technician found."
    if notify_owner:
        obs.notify(db, row.user_email, scan_id, "guidance" if escalated or diagnosis else "validated", title, body)
    db.commit()
    return _record_for_owner(db, scan_id, user)
