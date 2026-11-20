import csv
import io
import re
from datetime import date, datetime, timezone
from typing import List, Literal, Optional

from fastapi import APIRouter, Depends, File, HTTPException, Response, UploadFile
from pydantic import BaseModel, Field, field_validator, model_validator
from sqlalchemy import text
from sqlalchemy.orm import Session

from . import avatars, insights, land, levels, observations as obs, schema
from .access import AGRICULTURIST, STAFF, TECHNICIAN, account_is_active, require_viewer
from .database import get_db, get_geo_db, local_today
from .email_service import send_plain_email
from .models import OTPRecord, User
from .schemas import RegisterSchema, check_password_bytes, clean_phone
from .security import hash_password

router = APIRouter(prefix="/dashboard", tags=["Dashboard"])
ROLES = ("farmer", "technician", "agriculturist")
PEST_KEYS = levels.SUPPORTED_PESTS + (levels.OTHER_PEST,)
# The system presents options; it never prescribes a pesticide dose.
DOSE = re.compile(r"\b\d+(?:[.,]\d+)?\s*(?:ml|mL|l|L|liters?|litres?|g|kg|grams?|cc|tbsp|tsp|oz)\b"
                  r"|\bper\s+(?:hectare|ha|liter|litre|tank|knapsack)\b", re.I)


def _iso(value) -> Optional[str]:
    return value.isoformat() if value else None


# ---------------------------------------------------------------- session

@router.get("/me")
def me(db: Session = Depends(get_db), viewer: dict = Depends(require_viewer(*STAFF))):
    user = db.query(User).filter(User.email == viewer["email"]).first()
    return {
        **viewer,
        "id": user.id if user else None,
        "avatar_url": avatars.url_for(user.id, avatars.filename_of(db, user.id)) if user else None,
        "area_label": insights.area_label(viewer),
    }


# ---------------------------------------------------------------- technician: own history

@router.get("/my-reviews")
def my_reviews(
    db: Session = Depends(get_geo_db),
    viewer: dict = Depends(require_viewer(*STAFF)),
):
    rows = db.execute(
        text(
            """
            SELECT r.id, r.scan_id, r.action, r.pest, r.corrected_count, r.countable, r.level,
                   r.note, r.diagnosis, r.created_at, s.report_type, s.ai_pest,
                   COALESCE(NULLIF(btrim(s.municipality), ''), btrim(u.region), '') AS area,
                   COALESCE(NULLIF(btrim(s.barangay), ''), btrim(u.barangay), '') AS brgy,
                   u.full_name AS farmer_name, s.user_email
            FROM scan_reviews r
            JOIN scans s ON s.id = r.scan_id
            LEFT JOIN users_fdw u ON u.email = s.user_email
            WHERE r.reviewer = :me
            ORDER BY r.created_at DESC, r.id DESC
            LIMIT 500
            """
        ),
        {"me": viewer["email"]},
    ).fetchall()
    return [
        {
            "id": r.id,
            "scan_id": r.scan_id,
            "action": r.action,
            "report_type": r.report_type,
            "ai_pest": obs.pest_name(r.ai_pest),
            "pest": obs.pest_name(r.pest),
            "count": r.corrected_count,
            "countable": r.countable,
            "level": r.level,
            "note": r.note or r.diagnosis or "",
            "municipality": r.area,
            "barangay": r.brgy,
            "farmer": r.farmer_name or r.user_email,
            "created_at": _iso(r.created_at),
        }
        for r in rows
    ]


# ---------------------------------------------------------------- treatment library

class LibraryIn(BaseModel):
    pest: Literal[PEST_KEYS]  # type: ignore[valid-type]
    option_type: Literal["cultural", "biological", "ecological", "chemical"]
    crop_stages: List[Literal["Vegetative", "Reproductive", "Ripening"]] = []  # [] = every stage
    levels: List[Literal["LOW", "MEDIUM", "HIGH"]] = []                        # [] = every level
    title: str = Field(min_length=1, max_length=200)
    recommendation: str = Field(min_length=1, max_length=4000)
    source_reference: str = Field(min_length=3, max_length=500)

    @model_validator(mode="after")
    def _no_doses(self):
        if DOSE.search(self.title) or DOSE.search(self.recommendation):
            raise ValueError(
                "Leave out product amounts and doses. The app presents approaches only and tells "
                "farmers to consult their technician before using any pesticide."
            )
        return self


class LibraryStatusIn(BaseModel):
    status: Literal["draft", "approved"]


def _library_row(r) -> dict:
    return {
        "id": r.id,
        "pest": r.pest,
        "pest_name": obs.pest_name(r.pest),
        "option_type": r.option_type,
        "crop_stages": list(r.crop_stages or []),
        "levels": list(r.levels or []),
        "title": r.title,
        "recommendation": r.recommendation,
        "source_reference": r.source_reference,
        "status": r.status,
        "created_by": r.created_by,
        "updated_by": r.updated_by,
        "approved_by": r.approved_by,
        "approved_at": _iso(r.approved_at),
        "updated_at": _iso(r.updated_at),
    }


@router.get("/library")
def library(
    db: Session = Depends(get_geo_db),
    viewer: dict = Depends(require_viewer(*STAFF)),
):
    # Technicians see approved entries only; drafts are the agriculturist's work in progress.
    where = "" if viewer["role"] == AGRICULTURIST else "WHERE status = 'approved'"
    rows = db.execute(text(f"SELECT * FROM treatment_library {where} ORDER BY pest, option_type, title")).fetchall()
    return [_library_row(r) for r in rows]


def _library_params(p: LibraryIn, viewer: dict) -> dict:
    return {"p": p.pest, "t": p.option_type, "stages": list(p.crop_stages), "levels": list(p.levels),
            "title": p.title.strip(), "rec": p.recommendation.strip(),
            "src": p.source_reference.strip(), "by": viewer["email"]}


@router.post("/library")
def create_library_entry(
    payload: LibraryIn,
    db: Session = Depends(get_geo_db),
    viewer: dict = Depends(require_viewer(AGRICULTURIST)),
):
    row = db.execute(
        text(
            """
            INSERT INTO treatment_library (pest, option_type, crop_stages, levels, title,
                                           recommendation, source_reference, status,
                                           created_by, updated_by)
            VALUES (:p, :t, :stages, :levels, :title, :rec, :src, 'draft', :by, :by)
            RETURNING *
            """
        ),
        _library_params(payload, viewer),
    ).first()
    db.commit()
    return _library_row(row)


@router.put("/library/{entry_id}")
def update_library_entry(
    entry_id: int,
    payload: LibraryIn,
    db: Session = Depends(get_geo_db),
    viewer: dict = Depends(require_viewer(AGRICULTURIST)),
):
    row = db.execute(
        text(
            """
            UPDATE treatment_library
            SET pest = :p, option_type = :t, crop_stages = :stages, levels = :levels,
                title = :title, recommendation = :rec, source_reference = :src,
                updated_by = :by, updated_at = now()
            WHERE id = :i
            RETURNING *
            """
        ),
        {**_library_params(payload, viewer), "i": entry_id},
    ).first()
    if row is None:
        raise HTTPException(status_code=404, detail="Recommendation not found.")
    db.commit()
    return _library_row(row)


@router.post("/library/{entry_id}/status")
def set_library_status(
    entry_id: int,
    payload: LibraryStatusIn,
    db: Session = Depends(get_geo_db),
    viewer: dict = Depends(require_viewer(AGRICULTURIST)),
):
    ok = payload.status == "approved"
    row = db.execute(
        text(
            """
            UPDATE treatment_library
            SET status = :st,
                approved_by = CASE WHEN :ok THEN :by ELSE NULL END,
                approved_at = CASE WHEN :ok THEN now() ELSE NULL END,
                updated_by = :by, updated_at = now()
            WHERE id = :i
            RETURNING *
            """
        ),
        {"st": payload.status, "ok": ok, "by": viewer["email"], "i": entry_id},
    ).first()
    if row is None:
        raise HTTPException(status_code=404, detail="Recommendation not found.")
    db.commit()
    return _library_row(row)


@router.delete("/library/{entry_id}")
def delete_library_entry(
    entry_id: int,
    db: Session = Depends(get_geo_db),
    viewer: dict = Depends(require_viewer(AGRICULTURIST)),
):
    result = db.execute(text("DELETE FROM treatment_library WHERE id = :i"), {"i": entry_id})
    if result.rowcount == 0:
        raise HTTPException(status_code=404, detail="Recommendation not found.")
    db.commit()
    return {"message": "Recommendation deleted.", "id": entry_id}


# ---------------------------------------------------------------- infestation criteria

class CriteriaIn(BaseModel):
    pest: Literal[PEST_KEYS]  # type: ignore[valid-type]
    crop_stage: Literal["", "Vegetative", "Reproductive", "Ripening"] = ""  # '' = any stage
    medium_from: float = Field(ge=0)
    high_from: float = Field(gt=0)

    @model_validator(mode="after")
    def _ordered(self):
        if self.medium_from >= self.high_from:
            raise ValueError("The HIGH threshold must be above the MEDIUM threshold.")
        return self


@router.get("/criteria")
def criteria(
    db: Session = Depends(get_geo_db),
    viewer: dict = Depends(require_viewer(*STAFF)),
):
    thresholds = levels.load_thresholds(db)
    return [
        {
            "pest": p,
            "pest_name": obs.pest_name(p),
            "indicators": levels.indicators_for(p),
            "thresholds": sorted(
                (row for (pest, _), row in thresholds.items() if pest == p),
                key=lambda r: ("", *levels.CROP_STAGES).index(r["crop_stage"]),
            ),
        }
        for p in PEST_KEYS
    ]


@router.put("/criteria")
def save_criteria(
    payload: CriteriaIn,
    db: Session = Depends(get_geo_db),
    viewer: dict = Depends(require_viewer(AGRICULTURIST)),
):
    db.execute(
        text(
            """
            INSERT INTO level_criteria (pest, crop_stage, medium_from, high_from, updated_by)
            VALUES (:p, :s, :mf, :hf, :by)
            ON CONFLICT (pest, crop_stage) DO UPDATE
            SET medium_from = EXCLUDED.medium_from, high_from = EXCLUDED.high_from,
                updated_by = EXCLUDED.updated_by, updated_at = now()
            """
        ),
        {"p": payload.pest, "s": payload.crop_stage, "mf": payload.medium_from,
         "hf": payload.high_from, "by": viewer["email"]},
    )
    db.commit()
    return levels.load_thresholds(db)[(payload.pest, payload.crop_stage)]


@router.delete("/criteria/{criteria_id}")
def delete_criteria(
    criteria_id: int,
    db: Session = Depends(get_geo_db),
    viewer: dict = Depends(require_viewer(AGRICULTURIST)),
):
    result = db.execute(
        text("DELETE FROM level_criteria WHERE id = :i AND crop_stage <> ''"), {"i": criteria_id}
    )
    if result.rowcount == 0:
        raise HTTPException(status_code=400, detail="The any-stage thresholds can be edited but not removed.")
    db.commit()
    return {"message": "Stage thresholds removed.", "id": criteria_id}


# ---------------------------------------------------------------- users & areas

@router.get("/areas")
def areas(
    geo: Session = Depends(get_geo_db),
    viewer: dict = Depends(require_viewer(AGRICULTURIST)),
):
    users = geo.execute(
        text("SELECT email, full_name, role, region, coverage_barangays, status FROM users_fdw "
             "WHERE is_verified")
    ).fetchall()
    users = [u for u in users if account_is_active(u.status, u.role)]
    scans = geo.execute(
        text(
            """
            SELECT COALESCE(NULLIF(btrim(s.municipality), ''), btrim(u.region), '') AS area,
                   COUNT(*) AS total,
                   COUNT(*) FILTER (WHERE s.validation_status = 'validated') AS validated,
                   COUNT(*) FILTER (WHERE s.validation_status = 'pending') AS pending,
                   COUNT(*) FILTER (WHERE s.validation_status = 'escalated') AS escalated
            FROM scans s LEFT JOIN users_fdw u ON u.email = s.user_email
            GROUP BY 1
            """
        )
    ).fetchall()
    known = {m.lower(): m for m in insights.ANTIQUE_MUNICIPALITIES}
    table: dict = {}

    def slot(name: Optional[str]) -> dict:
        clean = (name or "").strip()
        label = known.get(clean.lower(), clean) or insights.UNASSIGNED
        return table.setdefault(label, {"area": label, "technicians": [], "agriculturists": [],
                                        "farmers": 0, "observations": 0, "validated": 0,
                                        "pending": 0, "escalated": 0})

    for m in insights.ANTIQUE_MUNICIPALITIES:
        slot(m)
    for u in users:
        s = slot(u.region)
        person = {"email": u.email, "full_name": u.full_name,
                  "coverage": [b.strip() for b in (u.coverage_barangays or "").split(",") if b.strip()]}
        if u.role == "technician":
            s["technicians"].append(person)
        elif u.role == "agriculturist":
            s["agriculturists"].append(person)
        else:
            s["farmers"] += 1
    for r in scans:
        s = slot(r.area)
        s["observations"] += r.total
        s["validated"] += r.validated
        s["pending"] += r.pending
        s["escalated"] += r.escalated
    return sorted(table.values(), key=lambda a: (a["area"] == insights.UNASSIGNED, a["area"]))


def _user_row(u: User, viewer: dict, scan_counts: dict, avatar_files: Optional[dict] = None) -> dict:
    return {
        "id": u.id,
        "avatar_url": avatars.url_for(u.id, (avatar_files or {}).get(u.id)),
        "full_name": u.full_name,
        "email": u.email,
        "phone": u.phone or "",
        "role": u.role,
        "status": u.status,
        "municipality": (u.region or "").strip(),
        "barangay": (u.barangay or "").strip(),
        "coverage_barangays": [b.strip() for b in (u.coverage_barangays or "").split(",") if b.strip()],
        "is_verified": bool(u.is_verified),
        "created_at": _iso(u.created_at),
        "reviewed_by": u.reviewed_by,
        "reviewed_at": _iso(u.reviewed_at),
        "observations": scan_counts.get(u.email, 0),
        "is_you": u.email == viewer["email"],
    }


@router.get("/users")
def users(
    db: Session = Depends(get_db),
    geo: Session = Depends(get_geo_db),
    viewer: dict = Depends(require_viewer(AGRICULTURIST)),
):
    scan_counts = {
        r.user_email: r.c
        for r in geo.execute(text("SELECT user_email, COUNT(*) AS c FROM scans GROUP BY 1")).fetchall()
    }
    rows = db.query(User).order_by(User.created_at.desc()).all()
    # Verified accounts waiting for approval come first.
    rows.sort(key=lambda u: not (u.status == "pending" and u.is_verified))
    files = avatars.all_filenames(db)
    return [_user_row(u, viewer, scan_counts, files) for u in rows]


def _clean_coverage(v):
    if v is None:
        return v
    seen, out = set(), []
    for b in v:
        b = b.strip().replace(",", " ")
        if b and b.lower() not in seen:
            seen.add(b.lower())
            out.append(b[:100])
    return out


class UserUpdate(BaseModel):
    status: Optional[Literal["approved", "rejected", "pending"]] = None
    role: Optional[Literal["farmer", "technician", "agriculturist"]] = None
    full_name: Optional[str] = Field(None, min_length=2, max_length=100)
    phone: Optional[str] = None
    municipality: Optional[str] = Field(None, min_length=1, max_length=100)
    barangay: Optional[str] = Field(None, max_length=100)
    coverage_barangays: Optional[List[str]] = None
    # Sets a new password for someone who forgot theirs.
    new_password: Optional[str] = Field(None, min_length=8, max_length=72)

    @field_validator("coverage_barangays")
    @classmethod
    def _clean(cls, v):
        return _clean_coverage(v)

    @field_validator("full_name")
    @classmethod
    def _name(cls, v):
        if v is None:
            return v
        v = v.strip()
        if len(v) < 2:
            raise ValueError("Enter the full name.")
        return v

    @field_validator("phone")
    @classmethod
    def _phone(cls, v):
        # An empty phone is allowed here: older accounts have none.
        return None if v is None else (clean_phone(v) if v.strip() else "")

    @field_validator("new_password")
    @classmethod
    def _bytes(cls, v):
        return None if v is None else check_password_bytes(v)


class UserCreate(RegisterSchema):
    """An account an agriculturist adds on the dashboard: active right away
    (no email code), with the role and coverage set here."""

    coverage_barangays: List[str] = []

    @field_validator("coverage_barangays")
    @classmethod
    def _clean(cls, v):
        return _clean_coverage(v)


def _tell(geo: Session, email: str, title: str, body: str) -> None:
    """In-app notification about an account change (best effort)."""
    try:
        obs.notify(geo, email, None, "account", title, body)
        geo.commit()
    except Exception:
        geo.rollback()


def _get_user(db: Session, user_id: int) -> User:
    user = db.query(User).filter(User.id == user_id).first()
    if user is None:
        raise HTTPException(status_code=404, detail="Account not found.")
    return user


@router.post("/users", status_code=201)
def create_user(
    payload: UserCreate,
    db: Session = Depends(get_db),
    viewer: dict = Depends(require_viewer(AGRICULTURIST)),
):
    email = payload.email.strip().lower()
    if db.query(User).filter(User.email == email).first():
        raise HTTPException(status_code=400, detail="An account with this email already exists.")
    user = User(
        full_name=payload.full_name,
        email=email,
        password_hash=hash_password(payload.password),
        region=payload.municipality,
        barangay=payload.barangay,
        phone=payload.phone,
        role=payload.role,
        status="approved",
        is_verified=True,
        coverage_barangays=",".join(payload.coverage_barangays) if payload.role == "technician" else "",
        reviewed_by=viewer["email"],
        reviewed_at=datetime.now(timezone.utc),
    )
    db.add(user)
    db.commit()
    db.refresh(user)
    try:  # best effort; the agriculturist gives the password in person
        send_plain_email(
            user.email,
            "Your Palay Patrol account is ready",
            f"Hi {user.full_name},\n\nAn agriculturist created a Palay Patrol account for you "
            f"({user.role}). Sign in with this email and the password they gave you.\n",
        )
    except Exception:
        pass
    return _user_row(user, viewer, {})


@router.patch("/users/{user_id}")
def update_user(
    user_id: int,
    payload: UserUpdate,
    db: Session = Depends(get_db),
    geo: Session = Depends(get_geo_db),
    viewer: dict = Depends(require_viewer(AGRICULTURIST)),
):
    user = _get_user(db, user_id)
    is_self = user.email == viewer["email"]
    if is_self and ((payload.role and payload.role != user.role) or (payload.status and payload.status != "approved")):
        # Stops the last agriculturist from locking everyone out of this page.
        raise HTTPException(status_code=400, detail="You can't change your own role or approval.")
    newly_approved = payload.status == "approved" and user.status != "approved"
    changed = []
    if payload.status is not None and payload.status != user.status:
        if payload.status == "approved" and not user.is_verified:
            raise HTTPException(status_code=400, detail="This person hasn't verified their email yet.")
        user.status = payload.status
        user.reviewed_by = viewer["email"]
        user.reviewed_at = datetime.now(timezone.utc)
    if payload.role is not None and payload.role != user.role:
        user.role = payload.role
        changed.append("role")
    if payload.full_name is not None and payload.full_name != user.full_name:
        user.full_name = payload.full_name
        changed.append("name")
    if payload.phone is not None and payload.phone != (user.phone or ""):
        user.phone = payload.phone
        changed.append("mobile number")
    if payload.municipality is not None and payload.municipality.strip() != (user.region or "").strip():
        user.region = payload.municipality.strip()
        changed.append("municipality")
    if payload.barangay is not None and payload.barangay.strip() != (user.barangay or "").strip():
        user.barangay = payload.barangay.strip()
        changed.append("barangay")
    if payload.coverage_barangays is not None:
        coverage = ",".join(payload.coverage_barangays)
        if coverage != (user.coverage_barangays or ""):
            user.coverage_barangays = coverage
            changed.append("coverage area")
    if payload.new_password:
        user.password_hash = hash_password(payload.new_password)
        changed.append("password")
    db.commit()
    if changed and not is_self:
        _tell(
            geo,
            user.email,
            "Your account details were updated",
            f"An agriculturist updated your {', '.join(changed)}. Pull down on Home to see the changes.",
        )
    if newly_approved:
        try:  # best effort; the app also shows the new status on its next check
            send_plain_email(
                user.email,
                "Your Rice Pest Detection account is approved",
                f"Hi {user.full_name},\n\nAn agriculturist approved your account. "
                "Open the app to start sending field observations.\n",
            )
        except Exception:
            pass
    return _user_row(user, viewer, {}, {user.id: avatars.filename_of(db, user.id)})


@router.delete("/users/{user_id}")
def delete_user(
    user_id: int,
    db: Session = Depends(get_db),
    geo: Session = Depends(get_geo_db),
    viewer: dict = Depends(require_viewer(AGRICULTURIST)),
):
    """Removes the account. Its observations stay in the records and reports
    (they were validated field data); its notifications are removed."""
    user = _get_user(db, user_id)
    if user.email == viewer["email"]:
        raise HTTPException(status_code=400, detail="You can't delete your own account.")
    filename = avatars.filename_of(db, user.id)
    email = user.email
    db.query(OTPRecord).filter(OTPRecord.email == email).delete()
    db.delete(user)
    db.commit()
    avatars.delete_files_of(filename)
    try:
        geo.execute(text("DELETE FROM notifications WHERE user_email = :e"), {"e": email})
        geo.commit()
    except Exception:
        geo.rollback()
    return {"ok": True}


@router.post("/users/{user_id}/avatar")
def set_user_avatar(
    user_id: int,
    image: UploadFile = File(...),
    db: Session = Depends(get_db),
    viewer: dict = Depends(require_viewer(AGRICULTURIST)),
):
    user = _get_user(db, user_id)
    filename = avatars.save(db, user.id, image)
    db.commit()
    return _user_row(user, viewer, {}, {user.id: filename})


@router.delete("/users/{user_id}/avatar")
def clear_user_avatar(
    user_id: int,
    db: Session = Depends(get_db),
    viewer: dict = Depends(require_viewer(AGRICULTURIST)),
):
    user = _get_user(db, user_id)
    avatars.remove(db, user.id)
    db.commit()
    return _user_row(user, viewer, {})


# ---------------------------------------------------------------- reports

def _cell(v):
    """Text starting with = + - @ (or a tab/CR) would run as a formula in Excel,
    e.g. a name like =HYPERLINK(...). Numbers are left alone."""
    if isinstance(v, str) and v[:1] in ("=", "+", "-", "@", "\t", "\r"):
        return "'" + v
    return v


def _csv(filename: str, header: list, rows: list) -> Response:
    buf = io.StringIO()
    buf.write("﻿")  # lets Excel open the UTF-8 file correctly
    writer = csv.writer(buf)
    writer.writerow(header)
    writer.writerows([_cell(v) for v in row] for row in rows)
    return Response(
        content=buf.getvalue(),
        media_type="text/csv; charset=utf-8",
        headers={"Content-Disposition": f'attachment; filename="{filename}"'},
    )


def _n(v) -> str:
    return "" if v is None else v


@router.get("/reports/{kind}")
def report(
    kind: Literal["records", "monthly", "quarterly", "treatments"],
    start: str = "",
    end: str = "",
    month: str = "",
    quarter: str = "",
    municipality: str = "",
    land_type: str = "",
    db: Session = Depends(get_geo_db),
    viewer: dict = Depends(require_viewer(AGRICULTURIST)),
):
    today = local_today().isoformat()
    if kind == "records":
        rows = insights.filter_scans(
            insights.load_scans(db, viewer, start=insights.parse_day(start), end=insights.parse_day(end)),
            municipality=municipality, land_type=land_type,
        )
        return _csv(
            f"validated-observations-{today}.csv",
            ["Observation ID", "Date", "Municipality", "Barangay", "Submitted by", "Type", "Pest",
             "Count", "Infestation level", "Crop stage", "Land type", "Monitoring method", "Validated by",
             "Validated at", "Diagnosis", "Guidance", "Latitude", "Longitude"],
            [[r["id"], r["created_at"][:10], r["municipality"], r["barangay"], r["farmer_name"] or r["user_email"],
              r["report_type"], r["pest"], _n(r["count"]) if r["count"] is not None else "not countable",
              _n(r["level"]), r["crop_stage"], r["land_type_label"], r["monitoring_method"], _n(r["validated_by"]),
              (r["validated_at"] or "")[:10], r["diagnosis"], r["guidance"], _n(r["lat"]), _n(r["lng"])]
             for r in rows],
        )
    if kind == "monthly":
        data = insights.monthly_summary(db, viewer, month, strict=True)
        body = [[data["month"], dim, g["name"], g["records"], g["pests"], g["LOW"], g["MEDIUM"], g["HIGH"]]
                for dim, key in (("Municipality", "by_area"), ("Pest", "by_pest"), ("Land type", "by_land_type"))
                for g in data[key]]
        return _csv(
            f"monthly-summary-{data['month'] or today}.csv",
            ["Month", "Breakdown", "Name", "Validated observations", "Pests counted", "LOW", "MEDIUM", "HIGH"],
            body,
        )
    if kind == "quarterly":
        data = insights.quarterly_patterns(db, viewer, quarter, strict=True)
        return _csv(
            f"quarterly-patterns-{data['quarter'] or today}.csv",
            ["Quarter", "Municipality", "Pest", "Compared by", "This quarter", "Previous quarter",
             "Same quarter last year", "Change %", "Pattern", "Recurring", "Note"],
            [[data["quarter"], r["area"], r["pest"], r["basis"], r["current"][r["basis"]],
              r["previous"][r["basis"]], r["last_year"][r["basis"]], _n(r["change_pct"]), r["status"],
              "yes" if r["recurring"] else "no", "Pattern in past records, not a forecast"]
             for r in data["rows"]],
        )
    data = insights.treatment_followups(db, viewer)
    s, e = insights.parse_day(start), insights.parse_day(end)
    items = [i for i in data["items"]
             if (not s or i["applied_at"][:10] >= s.isoformat()) and (not e or i["applied_at"][:10] <= e.isoformat())]
    return _csv(
        f"treatment-followups-{today}.csv",
        ["Treatment ID", "Observation ID", "Municipality", "Barangay", "Farmer", "Pest", "Crop stage",
         "Land type", "Treatment", "Type", "Applied", "Follow-up due", "Level before", "Count before",
         "Follow-up observation", "Level after", "Count after", "Change %", "Outcome"],
        [[i["id"], i["scan_id"], i["municipality"], i["barangay"], i["farmer_name"], i["pest"], i["crop_stage"],
          i["land_type_label"], i["treatment"], i["option_type"], i["applied_at"][:10], _n(i["follow_up_due"]), _n(i["before_level"]),
          _n(i["before_count"]), _n(i["follow_up_scan_id"]), _n(i["after_level"]), _n(i["after_count"]),
          _n(i["reduction_pct"]), i["outcome"]] for i in items],
    )


# ---------------------------------------------------------------- treatment feedback rule

class TreatmentRuleIn(BaseModel):
    """Staff control over one applied treatment.

    follow_up_due: the day the farmer is asked "How is the field now?" (the
    treatment feedback). reset_follow_up: back to the automatic date
    (FOLLOW_UP_DAYS after applying). recommend_again: True re-allows a
    library option the farmer already applied and reported back on, so it is
    recommended to them again; False hides it again."""
    follow_up_due: Optional[date] = None
    reset_follow_up: bool = False
    recommend_again: Optional[bool] = None


def _nice_day(d: date) -> str:
    return f"{d:%b} {d.day}, {d.year}"


@router.patch("/treatments/{treatment_id}")
def update_treatment(
    treatment_id: int,
    payload: TreatmentRuleIn,
    db: Session = Depends(get_geo_db),
    viewer: dict = Depends(require_viewer(*STAFF)),
):
    if not schema.treatment_rules_ready(db):
        raise HTTPException(
            status_code=503,
            detail="This needs a database update first (sql/011_land_type_and_treatment_feedback.sql).",
        )
    row = db.execute(
        text(
            """
            SELECT t.id, t.treatment, t.applied_at, t.library_id, t.follow_up_due, s.user_email,
                   COALESCE(NULLIF(btrim(s.municipality), ''), btrim(u.region), '') AS area,
                   COALESCE(NULLIF(btrim(s.barangay), ''), btrim(u.barangay), '') AS brgy,
                   EXISTS (SELECT 1 FROM scans f WHERE f.follow_up_of = t.id) AS has_follow_up
            FROM treatments t
            JOIN scans s ON s.id = t.scan_id
            LEFT JOIN users_fdw u ON u.email = s.user_email
            WHERE t.id = :i
            """
        ),
        {"i": treatment_id},
    ).first()
    if row is None or not obs.in_scope(viewer, row.area, row.brgy):
        raise HTTPException(status_code=404, detail="Treatment not found.")
    notify_farmer = row.user_email != viewer["email"]
    who = "Your technician" if viewer["role"] == TECHNICIAN else "Your agriculturist"

    if payload.reset_follow_up or payload.follow_up_due is not None:
        if row.has_follow_up:
            raise HTTPException(status_code=409, detail="The farmer already sent the follow-up for this treatment.")
        applied = row.applied_at.date()
        due = obs.follow_up_due(applied) if payload.reset_follow_up else payload.follow_up_due
        if due < applied:
            raise HTTPException(status_code=400, detail="The follow-up date can't be before the treatment was applied.")
        db.execute(
            text("UPDATE treatments SET follow_up_due = :d, follow_up_set_by = :by WHERE id = :i"),
            {"d": due, "by": None if payload.reset_follow_up else viewer["email"], "i": treatment_id},
        )
        if notify_farmer and due != row.follow_up_due:
            obs.notify(db, row.user_email, None, "follow_up", "Follow-up date changed",
                       f'{who} asks you to check the field after "{row.treatment}" on {_nice_day(due)}.')

    if payload.recommend_again is not None:
        if payload.recommend_again and row.library_id is None:
            raise HTTPException(status_code=400,
                                detail="Only options from the treatment library can be recommended again.")
        db.execute(
            text("UPDATE treatments SET recommend_again = :a, recommend_again_by = :by WHERE id = :i"),
            {"a": payload.recommend_again, "by": viewer["email"] if payload.recommend_again else None,
             "i": treatment_id},
        )
        if notify_farmer and payload.recommend_again:
            obs.notify(db, row.user_email, None, "guidance", "Treatment recommended again",
                       f'{who} put "{row.treatment}" back in your treatment options.')
    db.commit()
    item = next((i for i in insights.treatment_followups(db, viewer)["items"] if i["id"] == treatment_id), None)
    if item is None:
        raise HTTPException(status_code=404, detail="Treatment not found.")
    return item
