"""Observations (the `scans` table) as the mobile app and dashboard see them.

Status flow: pending -> validated | returned | escalated; escalated -> validated.
The two review queues are views of these same statuses (no extra status):
  "Not Validated"    = pending   (initial review: technician of the area, or an
                                  agriculturist where no technician covers it)
  "To Be Validated"  = escalated (escalated review: agriculturist)
Pest reports get a model result on upload; disease reports never do. A pest
report on which the model confidently found no insect at all is closed at
once as "no_pests" (its photo is deleted; see sync_router.submit_observation).
"""
from datetime import date, timedelta
from typing import Optional

from sqlalchemy import text
from sqlalchemy.orm import Session

from . import i18n, land, schema
from .detector import PEST_NAMES

FOLLOW_UP_DAYS = 7  # "How is the field now?" appears this long after a treatment
OPTION_TYPES = ("cultural", "biological", "ecological", "chemical")
CHEMICAL_NOTE = (
    "Chemical control is a last resort. Talk to your agricultural technician or "
    "municipal agriculture office before using any pesticide, and always follow the label."
)
METHOD_DIRECT = "Direct field observation"
METHOD_TRAP = "Trap-based"

# Review queues (labels only; the statuses stay pending / escalated).
QUEUE_NOT_VALIDATED, QUEUE_TO_BE_VALIDATED = "not_validated", "to_be_validated"
QUEUE_OF_STATUS = {"pending": QUEUE_NOT_VALIDATED, "escalated": QUEUE_TO_BE_VALIDATED}
QUEUE_LABELS = {QUEUE_NOT_VALIDATED: "Not Validated", QUEUE_TO_BE_VALIDATED: "To Be Validated"}


def queue_of(status: Optional[str]) -> Optional[str]:
    return QUEUE_OF_STATUS.get(status or "")

SELECT = """
    SELECT s.*, ST_Y(s.geom::geometry) AS lat, ST_X(s.geom::geometry) AS lng,
           u.full_name AS submitter_name, u.phone AS submitter_phone,
           COALESCE(NULLIF(btrim(s.municipality), ''), btrim(u.region), '') AS area,
           COALESCE(NULLIF(btrim(s.barangay), ''), btrim(u.barangay), '') AS brgy,
           v.full_name AS validator_name,
           (SELECT t.scan_id FROM treatments t WHERE t.id = s.follow_up_of) AS follow_up_treated_scan_id,
           (SELECT n.id FROM scans n WHERE n.resubmission_of = s.id ORDER BY n.created_at DESC LIMIT 1)
               AS resubmitted_as
    FROM scans s
    LEFT JOIN users_fdw u ON u.email = s.user_email
    LEFT JOIN users_fdw v ON v.email = s.validated_by
"""


def pest_name(key: Optional[str]) -> Optional[str]:
    if not key:
        return None
    return PEST_NAMES.get(key, key.replace("_", " ").title())


def _iso(v) -> Optional[str]:
    return v.isoformat() if v else None


def scope_sql(viewer: dict, params: dict, alias: str = "s", user_alias: str = "u") -> Optional[str]:
    """SQL limiting rows to a technician's coverage. '' = no limit (agriculturist),
    None = nothing visible (technician with no area)."""
    if viewer["role"] != "technician":
        return ""
    if not viewer["area"]:
        return None
    params["scope_area"] = viewer["area"]
    area = f"COALESCE(NULLIF(btrim({alias}.municipality), ''), btrim({user_alias}.region), '')"
    clause = f"lower({area}) = lower(:scope_area)"
    if viewer["coverage"]:
        params["scope_brgys"] = [b.lower() for b in viewer["coverage"]]
        brgy = f"COALESCE(NULLIF(btrim({alias}.barangay), ''), btrim({user_alias}.barangay), '')"
        clause += f" AND lower({brgy}) = ANY(:scope_brgys)"
    return clause


def in_scope(viewer: dict, area: str, barangay: str) -> bool:
    if viewer["role"] != "technician":
        return True
    if not viewer["area"] or area.lower() != viewer["area"].lower():
        return False
    return not viewer["coverage"] or barangay.lower() in {b.lower() for b in viewer["coverage"]}


def technician_coverage(db: Session) -> list:
    """[(municipality, {barangays} or None)] for every active technician
    (None = the whole municipality)."""
    from .access import account_is_active  # avoid an import cycle at module load

    rows = db.execute(
        text("SELECT role, status, region, coverage_barangays FROM users_fdw "
             "WHERE role = 'technician' AND is_verified")
    ).fetchall()
    out = []
    for r in rows:
        if not account_is_active(r.status, r.role) or not (r.region or "").strip():
            continue
        brgys = {b.strip().lower() for b in (r.coverage_barangays or "").split(",") if b.strip()}
        out.append(((r.region or "").strip().lower(), brgys or None))
    return out


def has_technician(coverage: list, area: str, barangay: str) -> bool:
    """Whether some technician's queue receives observations from this place.
    If none does, the observation goes to the agriculturists instead."""
    a, b = (area or "").strip().lower(), (barangay or "").strip().lower()
    return any(m == a and (brgys is None or b in brgys) for m, brgys in coverage)


def shape(r, *, staff: bool = False) -> dict:
    """One observation. `staff` adds detection boxes, submitter contact and history-only fields."""
    is_pest = r.report_type == "pest"
    out = {
        "id": r.id,
        "client_uuid": r.client_uuid,
        "report_type": r.report_type,
        "created_at": _iso(r.created_at),
        "lat": r.lat,
        "lng": r.lng,
        "crop_stage": r.crop_phase or "",
        # '' = recorded before the land type field existed.
        "land_type": getattr(r, "land_type", "") or "",
        "land_type_label": land.label(getattr(r, "land_type", "")),
        "monitoring_method": r.monitoring_method or "",
        "trap_type": r.trap_type or "",
        "target_pest": r.target_pest or "",
        "target_sex": r.target_sex or "",
        "notes": (r.notes or "").strip(),
        "municipality": r.area,
        "barangay": r.brgy,
        "status": r.validation_status,
        "ai": None,
        "confirmed": None,
        "diagnosis": r.diagnosis or "",
        "guidance": r.guidance or "",
        "return_reason": r.return_reason or "",
        "escalation_reason": r.escalation_reason or "",
        "follow_up_of": r.follow_up_of,
        # The observation that was treated, for a follow-up (links the pair).
        "follow_up_treated_scan_id": r.follow_up_treated_scan_id,
        "validated_by": r.validated_by,
        "validated_by_name": r.validator_name or r.validated_by,
        "validated_at": _iso(r.validated_at),
        # Confirmed infestation level (pest and disease reports), once validated.
        "level": r.infestation_level if r.validation_status == "validated" else None,
        # A retake of a returned observation, and the retake of this one (if any).
        "resubmission_of": r.resubmission_of,
        "resubmitted_as": r.resubmitted_as,
    }
    detection = getattr(r, "detection_result", "") or ""
    out["detection_result"] = detection
    # True when the photo was removed from storage (no pests found).
    out["image_deleted"] = getattr(r, "image_deleted_at", None) is not None
    out["location_status"] = getattr(r, "location_status", "") or ""
    out["gps_barangay_psgc"] = getattr(r, "gps_barangay_psgc", None)
    # Relevance screen ('' = checked before it existed). "possibly_unrelated"
    # asks the reviewer to make sure the photo shows a crop at all.
    out["image_relevance"] = getattr(r, "image_relevance", "") or ""
    out["queue"] = queue_of(r.validation_status)
    out["land_type_updated_by"] = getattr(r, "land_type_updated_by", None)
    out["land_type_updated_at"] = _iso(getattr(r, "land_type_updated_at", None))
    if is_pest:
        out["ai"] = {
            "status": r.ai_status,
            "result": detection,
            "pest": r.ai_pest,
            "pest_name": pest_name(r.ai_pest),
            "confidence": r.ai_confidence,
            "count": r.ai_count,
            "countable": bool(r.ai_countable),
            "message": r.ai_message or "",
        }
        if r.validation_status == "validated":
            out["confirmed"] = {
                "pest": r.confirmed_pest,
                "pest_name": pest_name(r.confirmed_pest),
                "count": r.confirmed_count,
                "countable": r.countable is not False and r.confirmed_count is not None,
                "level": r.infestation_level,
                "indicators": list(r.damage_indicators or []),
            }
    if staff:
        out["submitter"] = {
            "email": r.user_email,
            "name": r.submitter_name or r.user_email,
            "phone": r.submitter_phone or "",
            "role": r.submitted_by_role,
        }
        out["suggested_level"] = r.suggested_level
        if is_pest:
            out["ai"]["detections"] = r.ai_detections or []
    return out


def load(db: Session, scan_id: int):
    return db.execute(text(f"{SELECT} WHERE s.id = :i"), {"i": scan_id}).first()


def treatments_for(db: Session, scan_ids: list) -> dict:
    """{scan_id: [treatment, ...]} with each treatment's follow-up observation."""
    if not scan_ids:
        return {}
    extra = ("t.recommend_again, t.follow_up_set_by" if schema.treatment_rules_ready(db)
             else "FALSE AS recommend_again, NULL AS follow_up_set_by")
    rows = db.execute(
        text(
            f"""
            SELECT t.id, t.scan_id, t.client_uuid, t.treatment, t.option_type, t.library_id,
                   t.applied_at, t.follow_up_due, t.pre_count, {extra},
                   (SELECT f.id FROM scans f WHERE f.follow_up_of = t.id ORDER BY f.created_at LIMIT 1)
                       AS follow_up_scan_id
            FROM treatments t
            WHERE t.scan_id = ANY(:ids)
            ORDER BY t.applied_at, t.id
            """
        ),
        {"ids": scan_ids},
    ).fetchall()
    out: dict = {}
    for t in rows:
        out.setdefault(t.scan_id, []).append({
            "id": t.id,
            "client_uuid": t.client_uuid,
            "treatment": t.treatment,
            "option_type": t.option_type,
            "library_id": t.library_id,
            "applied_at": _iso(t.applied_at),
            "follow_up_due": _iso(t.follow_up_due),
            "follow_up_scan_id": t.follow_up_scan_id,
            "before_count": t.pre_count,
            # Staff re-allowed this option after the farmer reported back on it.
            "recommend_again": bool(t.recommend_again),
            # Set when a technician or agriculturist chose the follow-up date.
            "follow_up_set_by": t.follow_up_set_by,
        })
    return out


def tried_options(db: Session, owner_email: Optional[str]) -> dict:
    """{library_id: treatment name} the farmer already applied AND reported back
    on (a follow-up observation is linked to the treatment), unless a
    technician or agriculturist re-allowed it. These are not recommended to
    that farmer again."""
    if not owner_email:
        return {}
    allowed = "AND NOT t.recommend_again" if schema.treatment_rules_ready(db) else ""
    rows = db.execute(
        text(
            f"""
            SELECT DISTINCT t.library_id, t.treatment
            FROM treatments t JOIN scans s ON s.id = t.scan_id
            WHERE s.user_email = :e AND t.library_id IS NOT NULL {allowed}
              AND EXISTS (SELECT 1 FROM scans f WHERE f.follow_up_of = t.id)
            """
        ),
        {"e": owner_email},
    ).fetchall()
    return {r.library_id: r.treatment for r in rows}


def recommendations(db: Session, pest: Optional[str], crop_stage: str, level: Optional[str],
                    owner_email: Optional[str] = None, recommended: Optional[list] = None) -> dict:
    """Approved library options for a validated pest record, grouped by type.
    The app lists them; it never picks one or prescribes a product or dose.
    Options the owner already applied and reported back on are left out (and
    listed in "already_tried") unless staff re-allowed them."""
    groups = {t: [] for t in OPTION_TYPES}
    if not pest or not level:
        return {"groups": groups, "chemical_note": CHEMICAL_NOTE, "already_tried": [],
                "recommended": recommended or []}
    rows = db.execute(
        text(
            """
            SELECT id, option_type, title, recommendation, source_reference
            FROM treatment_library
            WHERE status = 'approved' AND pest = :p
              AND (cardinality(crop_stages) = 0 OR :stage = ANY(crop_stages))
              AND (cardinality(levels) = 0 OR :level = ANY(levels))
            ORDER BY option_type, title
            """
        ),
        {"p": pest, "stage": crop_stage, "level": level},
    ).fetchall()
    tried = tried_options(db, owner_email)
    chosen = {c["library_id"] for c in (recommended or [])}
    already_tried = []
    for r in rows:
        if r.id in tried:
            already_tried.append({"id": r.id, "title": r.title, "option_type": r.option_type})
            continue
        groups.setdefault(r.option_type, []).append({
            "id": r.id,
            "title": r.title,
            "description": r.recommendation,
            "source_reference": r.source_reference,
            # Picked by the reviewer for this observation (see scan_recommendations).
            "recommended": r.id in chosen,
        })
    # A reviewer may pick an approved option outside the stage/level tags;
    # their pick is always listed (still approved ones only).
    listed = {o["id"] for g in groups.values() for o in g}
    for c in recommended or []:
        if c["library_id"] not in listed and c.get("still_approved"):
            groups.setdefault(c["option_type"], []).append({
                "id": c["library_id"], "title": c["title"], "description": c["description"],
                "source_reference": c["source_reference"], "recommended": True})
    return {"groups": groups, "chemical_note": CHEMICAL_NOTE, "already_tried": already_tried,
            "recommended": recommended or []}


def reviewer_recommendations(db: Session, scan_id: int) -> list:
    """Library options a reviewer recommended for this observation (not what
    the farmer applied; that is in `treatments`)."""
    if not schema.recommendations_ready(db):
        return []
    rows = db.execute(
        text(
            """
            SELECT r.library_id, r.recommended_by, r.recommended_by_role, r.created_at,
                   l.title, l.option_type, l.recommendation, l.source_reference, l.status,
                   u.full_name AS recommended_by_name
            FROM scan_recommendations r
            JOIN treatment_library l ON l.id = r.library_id
            LEFT JOIN users_fdw u ON u.email = r.recommended_by
            WHERE r.scan_id = :i
            ORDER BY l.option_type, l.title
            """
        ),
        {"i": scan_id},
    ).fetchall()
    return [
        {"library_id": r.library_id, "title": r.title, "option_type": r.option_type,
         "description": r.recommendation, "source_reference": r.source_reference,
         "still_approved": r.status == "approved", "recommended_by_role": r.recommended_by_role,
         "recommended_by_name": r.recommended_by_name or r.recommended_by, "created_at": _iso(r.created_at)}
        for r in rows
    ]


def notify(db: Session, email: str, scan_id: Optional[int], kind: str, title: str, body: str = "") -> None:
    db.execute(
        text(
            "INSERT INTO notifications (user_email, scan_id, kind, title, body) "
            "VALUES (:e, :s, :k, :t, :b)"
        ),
        {"e": email, "s": scan_id, "k": kind, "t": title, "b": body},
    )


def notify_t(db: Session, email: str, scan_id: Optional[int], kind: str, title_key: str,
             body_key: Optional[str] = None, body_text: Optional[str] = None, **params) -> None:
    """A notification written in the recipient's language (app/i18n.py).
    `body_text` (free text typed by a person, e.g. a return reason) is used
    as is. {level} and {pest} params are translated too."""
    lang = i18n.language_of(db, email)
    if params.get("level"):
        params["level"] = i18n.render(f"level.{str(params['level']).upper()}", lang)
    if params.get("pest"):
        params["pest"] = i18n.t(params["pest"], lang)
    title = i18n.render(title_key, lang, **params)
    body = body_text if body_text is not None else (i18n.render(body_key, lang, **params) if body_key else "")
    notify(db, email, scan_id, kind, title, body)


def follow_up_due(applied: date) -> date:
    return applied + timedelta(days=FOLLOW_UP_DAYS)


def log_review(db: Session, scan_id: int, viewer: dict, action: str, **fields) -> int:
    """One row in the review history; returns its id. `note` is the system's
    summary of what changed; `reviewer_note` is what the reviewer wrote."""
    with_note = schema.reviewer_note_ready(db)
    return db.execute(
        text(
            f"""
            INSERT INTO scan_reviews (scan_id, reviewer, reviewer_role, action, corrected_count,
                                      diagnosis, guidance, library_id, pest, countable, level,
                                      indicators, note{", reviewer_note" if with_note else ""})
            VALUES (:scan_id, :by, :role, :action, :count, :diag, :guid, :lib, :pest, :countable,
                    :level, :indicators, :note{", :reviewer_note" if with_note else ""})
            RETURNING id
            """
        ),
        {
            "scan_id": scan_id, "by": viewer["email"], "role": viewer["role"], "action": action,
            "count": fields.get("count"), "diag": fields.get("diagnosis", ""),
            "guid": fields.get("guidance", ""), "lib": fields.get("library_id"),
            "pest": fields.get("pest"), "countable": fields.get("countable"),
            "level": fields.get("level"), "indicators": fields.get("indicators") or [],
            "note": fields.get("note", ""),
            "reviewer_note": fields.get("reviewer_note", ""),
        },
    ).scalar()


def meaningful(text_: str, min_chars: int = 10) -> bool:
    """A reviewer note worth keeping: at least `min_chars` characters and two
    words with letters (rejects "ok", "...", "aaaaaaaaaa")."""
    t = " ".join((text_ or "").split())
    words = [w for w in t.split(" ") if any(ch.isalpha() for ch in w)]
    return len(t) >= min_chars and len(words) >= 2 and len(set(t.replace(" ", "").lower())) > 2
