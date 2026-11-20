"""Queries and calculations behind the dashboard (analytics, reports).

Only validated observations count as official records. Pest, count and
infestation level are the technician's (or agriculturist's) confirmed values;
the dashboard never computes a level itself. Technicians see their coverage
area; agriculturists see everything.
"""
import math
import os
import re
from collections import defaultdict
from datetime import date, datetime, timedelta, timezone
from typing import Iterable, Optional

from sqlalchemy import text
from sqlalchemy.orm import Session

from . import land, observations as obs, schema
from .database import local_today

VALIDATED = ("validated",)
STATUSES = ("pending", "validated", "returned", "escalated")
LEVELS = ("LOW", "MEDIUM", "HIGH")
LEVEL_RANK = {lv: i for i, lv in enumerate(LEVELS)}
CROP_STAGES = ("Vegetative", "Reproductive", "Ripening")
TREND_STATUSES = ("increasing", "decreasing", "stable")
# Quarter-on-quarter change before activity counts as increasing/decreasing.
TREND_THRESHOLD_PCT = 25.0
# A barangay is an active hotspot if it had a validated observation this recently.
HOTSPOT_DAYS = 30
# Follow-up vs treated observation: counts must change this much to count as a change.
COUNT_CHANGE_PCT = 30.0
DISEASE = "Disease report"

ANTIQUE_MUNICIPALITIES = [
    "Anini-y", "Barbaza", "Belison", "Bugasong", "Caluya", "Culasi", "Hamtic",
    "Laua-an", "Libertad", "Pandan", "Patnongon", "San Jose de Buenavista",
    "San Remigio", "Sebaste", "Sibalom", "Tibiao", "Tobias Fornier", "Valderrama",
]
UNASSIGNED = "Unassigned"


def parse_day(value: str) -> Optional[date]:
    try:
        return date.fromisoformat(value) if value else None
    except ValueError:
        return None


def area_label(viewer: dict) -> Optional[str]:
    """What a technician's views are limited to (None for agriculturists)."""
    if viewer["role"] != "technician":
        return None
    if not viewer["area"]:
        return ""
    return viewer["area"] + (f" ({', '.join(viewer['coverage'])})" if viewer["coverage"] else "")


# ---------------------------------------------------------------- records

def _shape(r) -> dict:
    is_disease = r.report_type == "disease"
    validated = r.validation_status == "validated"
    if is_disease:
        pest_key, pest = "disease", DISEASE
    elif validated:
        pest_key, pest = r.confirmed_pest, obs.pest_name(r.confirmed_pest) or "Unidentified"
    else:
        pest_key, pest = r.ai_pest, obs.pest_name(r.ai_pest) or "Not identified yet"
    count = r.confirmed_count if validated else r.ai_count
    return {
        "id": r.id,
        "user_email": r.user_email,
        "farmer_name": r.submitter_name or "",
        "submitted_by_role": r.submitted_by_role,
        "municipality": r.area or UNASSIGNED,
        "barangay": r.brgy or "",
        "lat": r.lat,
        "lng": r.lng,
        "created_at": r.created_at.isoformat() if r.created_at else "",
        "report_type": r.report_type,
        "is_disease": is_disease,
        "pest_key": pest_key,
        "pest": pest,
        "count": count,  # None = not countable
        "ai_pest": obs.pest_name(r.ai_pest),
        "ai_confidence": r.ai_confidence,
        "ai_count": r.ai_count,
        "level": r.infestation_level if validated else None,
        "suggested_level": r.suggested_level,
        "crop_stage": r.crop_phase or "",
        "land_type": getattr(r, "land_type", "") or "",
        "land_type_label": land.label(getattr(r, "land_type", "")),
        "status": r.validation_status,
        "validated_by": r.validated_by,
        "validated_at": r.validated_at.isoformat() if r.validated_at else None,
        "diagnosis": (r.diagnosis or "").strip(),
        "guidance": (r.guidance or "").strip(),
        "return_reason": r.return_reason or "",
        "escalation_reason": r.escalation_reason or "",
        "monitoring_method": r.monitoring_method or "",
        "trap_type": r.trap_type or "",
        "notes": (r.notes or "").strip(),
        "follow_up_of": r.follow_up_of,
    }


def load_scans(
    db: Session,
    viewer: dict,
    statuses: Optional[Iterable[str]] = VALIDATED,
    start: Optional[date] = None,
    end: Optional[date] = None,
    scan_id: Optional[int] = None,
) -> list:
    """Observations the viewer may see, newest first. statuses=None = every status; end inclusive."""
    params: dict = {}
    clauses = []
    scope = obs.scope_sql(viewer, params)
    if scope is None:
        return []
    if scope:
        clauses.append(scope)
    if statuses is not None:
        clauses.append("s.validation_status = ANY(:statuses)")
        params["statuses"] = list(statuses)
    if start:
        clauses.append("s.created_at >= :start")
        params["start"] = start
    if end:
        clauses.append("s.created_at < :end")
        params["end"] = end + timedelta(days=1)
    if scan_id is not None:
        clauses.append("s.id = :scan_id")
        params["scan_id"] = scan_id
    where = f"WHERE {' AND '.join(clauses)}" if clauses else ""
    rows = db.execute(text(f"{obs.SELECT} {where} ORDER BY s.created_at DESC, s.id DESC"), params).fetchall()
    return [_shape(r) for r in rows]


def filter_scans(rows: list, pest: str = "", level: str = "", municipality: str = "",
                 crop_stage: str = "", q: str = "", land_type: str = "") -> list:
    q = q.strip().lower().lstrip("#")
    out = []
    for r in rows:
        if pest and r["pest"] != pest:
            continue
        if level and r["level"] != level.upper():
            continue
        if municipality and r["municipality"].lower() != municipality.strip().lower():
            continue
        if crop_stage and r["crop_stage"] != crop_stage:
            continue
        if land_type and r["land_type"] != land_type:
            continue
        if q:
            haystack = " ".join(
                str(r[k]) for k in ("id", "user_email", "farmer_name", "municipality", "barangay",
                                    "pest", "diagnosis", "status", "notes")
            ).lower()
            if q not in haystack:
                continue
        out.append(r)
    return out


def facets(rows: list) -> dict:
    return {
        "pests": sorted({r["pest"] for r in rows}),
        "municipalities": sorted({r["municipality"] for r in rows}),
        "crop_stages": [s for s in CROP_STAGES if any(r["crop_stage"] == s for r in rows)],
        "land_types": [[k, land.LAND_TYPE_LABELS[k]] for k in land.LAND_TYPES],
    }


# ---------------------------------------------------------------- map & home

def hotspots(points: list, since: Optional[date] = None) -> list:
    """One hotspot per barangay: its validated observations' centre and the
    highest confirmed level. `since` limits to recent activity."""
    groups: dict = defaultdict(list)
    for p in points:
        if p["lat"] is None or p["level"] is None:
            continue
        if since and p["created_at"][:10] < since.isoformat():
            continue
        groups[(p["municipality"], p["barangay"] or p["municipality"])].append(p)
    out = []
    for (muni, brgy), pts in groups.items():
        level = max((p["level"] for p in pts), key=LEVEL_RANK.get)
        out.append({
            "municipality": muni,
            "barangay": brgy,
            "lat": sum(p["lat"] for p in pts) / len(pts),
            "lng": sum(p["lng"] for p in pts) / len(pts),
            "records": len(pts),
            "level": level,
            "latest": max(p["created_at"] for p in pts),
            "pests": sorted({p["pest"] for p in pts}),
        })
    out.sort(key=lambda h: (-LEVEL_RANK[h["level"]], -h["records"], h["municipality"], h["barangay"]))
    return out


def _treatment_count(db: Session, viewer: dict, since: Optional[date] = None) -> int:
    params: dict = {}
    scope = obs.scope_sql(viewer, params)
    if scope is None:
        return 0
    clauses = [scope] if scope else []
    if since:
        clauses.append("t.applied_at >= :since")
        params["since"] = since
    where = f"WHERE {' AND '.join(clauses)}" if clauses else ""
    return db.execute(
        text(f"SELECT COUNT(*) FROM treatments t JOIN scans s ON s.id = t.scan_id "
             f"LEFT JOIN users_fdw u ON u.email = s.user_email {where}"),
        params,
    ).scalar()


def overview(db: Session, viewer: dict) -> dict:
    rows = load_scans(db, viewer, statuses=None)
    today = local_today()
    month_start = today.replace(day=1)
    validated = [r for r in rows if r["status"] == "validated"]
    by_status = {s: sum(1 for r in rows if r["status"] == s) for s in STATUSES}
    active = hotspots(validated, since=today - timedelta(days=HOTSPOT_DAYS))
    # Pending observations from places no technician covers: they go to the
    # agriculturists' queue instead of waiting unseen.
    no_technician = 0
    if viewer["role"] != "technician":
        coverage = obs.technician_coverage(db)
        no_technician = sum(
            1 for r in rows
            if r["status"] == "pending" and not obs.has_technician(coverage, r["municipality"], r["barangay"])
        )
    return {
        "area": area_label(viewer),
        "pending_without_technician": no_technician,
        "waiting_for_agriculturist": by_status["escalated"] + no_technician,
        "validated_this_month": sum(1 for r in validated if r["created_at"][:10] >= month_start.isoformat()),
        "hotspots": {lv: sum(1 for h in active if h["level"] == lv) for lv in LEVELS},
        "hotspot_days": HOTSPOT_DAYS,
        "escalations_waiting": by_status["escalated"],
        "treatments_this_month": _treatment_count(db, viewer, since=month_start),
        "treatments_total": _treatment_count(db, viewer),
        "total_observations": len(rows),
        **by_status,
    }


# ---------------------------------------------------------------- monthly

def _breakdown(rows: list, key: str) -> list:
    groups: dict = {}
    for r in rows:
        g = groups.setdefault(r[key], {"name": r[key], "records": 0, "pests": 0,
                                       "LOW": 0, "MEDIUM": 0, "HIGH": 0})
        g["records"] += 1
        g["pests"] += r["count"] or 0
        if r["level"] in LEVELS:
            g[r["level"]] += 1
    return sorted(groups.values(), key=lambda g: (-g["records"], g["name"]))


def monthly_summary(db: Session, viewer: dict, month: str = "", strict: bool = False) -> dict:
    """strict: use `month` even if it has no records (exports), instead of the latest month."""
    rows = load_scans(db, viewer, statuses=None)
    validated = [r for r in rows if r["status"] == "validated"]
    months: dict = {}
    for r in rows:
        m = months.setdefault(r["created_at"][:7], {"month": r["created_at"][:7], "observations": 0,
                                                     "validated": 0, "pests": 0})
        m["observations"] += 1
        if r["status"] == "validated":
            m["validated"] += 1
            m["pests"] += r["count"] or 0
    month_list = sorted(months.values(), key=lambda m: m["month"], reverse=True)
    if strict and re.fullmatch(r"\d{4}-\d{2}", month or ""):
        selected = month
    else:
        selected = month if month in months else (month_list[0]["month"] if month_list else "")
    in_month = [r for r in validated if r["created_at"][:7] == selected]
    return {
        "area": area_label(viewer),
        "months": month_list,
        "month": selected,
        "totals": {
            "observations": months.get(selected, {}).get("observations", 0),
            "validated": len(in_month),
            "pests": sum(r["count"] or 0 for r in in_month),
        },
        "by_level": {lv: sum(1 for r in in_month if r["level"] == lv) for lv in LEVELS},
        "by_area": _breakdown(in_month, "municipality"),
        "by_pest": _breakdown(in_month, "pest"),
        "by_land_type": _breakdown(in_month, "land_type_label"),
    }


# ---------------------------------------------------------------- quarterly patterns

def quarter_of(iso: str) -> str:
    return f"{iso[:4]}-Q{(int(iso[5:7]) - 1) // 3 + 1}"


def shift_quarter(q: str, n: int) -> str:
    idx = int(q[:4]) * 4 + (int(q[-1]) - 1) + n
    return f"{idx // 4}-Q{idx % 4 + 1}"


def _trend(current: float, previous: float):
    if previous == 0:
        return (None, "increasing") if current > 0 else (None, "stable")
    pct = (current - previous) / previous * 100
    if pct >= TREND_THRESHOLD_PCT:
        return round(pct, 1), "increasing"
    if pct <= -TREND_THRESHOLD_PCT:
        return round(pct, 1), "decreasing"
    return round(pct, 1), "stable"


def quarterly_patterns(db: Session, viewer: dict, quarter: str = "", strict: bool = False) -> dict:
    """Recurring / increasing / decreasing / stable per location and pest.
    These describe past records; they are not forecasts of outbreaks."""
    rows = load_scans(db, viewer)
    totals: dict = {}
    cells: dict = defaultdict(lambda: defaultdict(lambda: {"records": 0, "pests": 0}))
    for r in rows:
        q = quarter_of(r["created_at"])
        t = totals.setdefault(q, {"quarter": q, "records": 0, "pests": 0})
        t["records"] += 1
        t["pests"] += r["count"] or 0
        c = cells[(r["municipality"], r["pest"])][q]
        c["records"] += 1
        c["pests"] += r["count"] or 0
    quarter_list = []
    if totals:
        q, last = min(totals), max(totals)
        while q <= last:  # include quarters with no records
            quarter_list.append(totals.get(q, {"quarter": q, "records": 0, "pests": 0}))
            q = shift_quarter(q, 1)
    known = {t["quarter"] for t in quarter_list}
    if strict and re.fullmatch(r"\d{4}-Q[1-4]", quarter or ""):
        selected = quarter
    else:
        selected = quarter if quarter in known else (quarter_list[-1]["quarter"] if quarter_list else "")
    previous = shift_quarter(selected, -1) if selected else ""
    last_year = shift_quarter(selected, -4) if selected else ""
    empty = {"records": 0, "pests": 0}
    out = []
    for (area, pest), by_q in cells.items():
        cur, prev, ly = by_q.get(selected, empty), by_q.get(previous, empty), by_q.get(last_year, empty)
        if not cur["records"] and not prev["records"]:
            continue
        # Pest counts when there are any; otherwise (disease, not countable) the number of records.
        basis = "pests" if (cur["pests"] or prev["pests"]) else "records"
        change, status = _trend(cur[basis], prev[basis])
        out.append({
            "area": area, "pest": pest, "basis": basis, "current": cur, "previous": prev,
            "last_year": ly, "change_pct": change, "status": status,
            "recurring": bool(cur["records"] and ly["records"]),
        })
    order = {"increasing": 0, "stable": 1, "decreasing": 2}
    out.sort(key=lambda r: (order[r["status"]], -r["current"]["records"], r["area"], r["pest"]))
    summary = {s: sum(1 for r in out if r["status"] == s) for s in TREND_STATUSES}
    summary["recurring"] = sum(1 for r in out if r["recurring"])
    return {
        "area": area_label(viewer),
        "quarters": quarter_list[-8:],
        "quarter": selected,
        "previous": previous,
        "last_year": last_year,
        "threshold_pct": TREND_THRESHOLD_PCT,
        "summary": summary,
        "rows": out,
    }


# ---------------------------------------------------------------- treatments & follow-ups

def _outcome(before_level, after_level, before, after) -> str:
    if before_level in LEVEL_RANK and after_level in LEVEL_RANK and before_level != after_level:
        return "improved" if LEVEL_RANK[after_level] < LEVEL_RANK[before_level] else "worse"
    if before and after is not None:
        pct = (before - after) / before * 100
        if pct >= COUNT_CHANGE_PCT:
            return "improved"
        if pct <= -COUNT_CHANGE_PCT:
            return "worse"
    return "no change"


def treatment_followups(db: Session, viewer: dict) -> dict:
    """Each treatment with the follow-up observation linked to it (if any)."""
    params: dict = {}
    scope = obs.scope_sql(viewer, params)
    if scope is None:
        return {"area": area_label(viewer), "items": [], "summary": [], "overdue": []}
    where = f"WHERE {scope}" if scope else ""
    rules = ("t.recommend_again, t.follow_up_set_by" if schema.treatment_rules_ready(db)
             else "FALSE AS recommend_again, NULL AS follow_up_set_by")
    land_col = "s.land_type" if schema.land_type_ready(db) else "'' AS land_type"
    rows = db.execute(
        text(
            f"""
            SELECT t.id, t.scan_id, t.treatment, t.option_type, t.applied_at, t.follow_up_due,
                   t.pre_count, t.library_id, {rules}, {land_col}, s.user_email, u.full_name AS farmer_name, u.phone AS farmer_phone,
                   COALESCE(NULLIF(btrim(s.municipality), ''), btrim(u.region), '') AS area,
                   COALESCE(NULLIF(btrim(s.barangay), ''), btrim(u.barangay), '') AS brgy,
                   s.confirmed_pest, s.confirmed_count, s.infestation_level, s.crop_phase,
                   f.id AS f_id, f.created_at AS f_at, f.validation_status AS f_status,
                   f.confirmed_count AS f_count, f.infestation_level AS f_level
            FROM treatments t
            JOIN scans s ON s.id = t.scan_id
            LEFT JOIN users_fdw u ON u.email = s.user_email
            LEFT JOIN LATERAL (
                SELECT * FROM scans f WHERE f.follow_up_of = t.id ORDER BY f.created_at LIMIT 1
            ) f ON TRUE
            {where}
            ORDER BY t.applied_at DESC, t.id DESC
            """
        ),
        params,
    ).fetchall()
    today = local_today()
    items = []
    for t in rows:
        before = t.pre_count if t.pre_count else t.confirmed_count
        if t.f_id is None:
            outcome = "overdue" if t.follow_up_due and t.follow_up_due < today else "awaiting follow-up"
            after = reduction = None
        elif t.f_status != "validated":
            outcome, after, reduction = "follow-up in review", None, None
        else:
            after = t.f_count
            reduction = round((before - after) / before * 100, 1) if before and after is not None else None
            outcome = _outcome(t.infestation_level, t.f_level, before, after)
        items.append({
            "id": t.id,
            "scan_id": t.scan_id,
            "user_email": t.user_email,
            "farmer_name": t.farmer_name or t.user_email,
            "farmer_phone": t.farmer_phone or "",
            "municipality": t.area or UNASSIGNED,
            "barangay": t.brgy,
            "pest": obs.pest_name(t.confirmed_pest) or "Unidentified",
            "crop_stage": t.crop_phase or "",
            "land_type": t.land_type or "",
            "land_type_label": land.label(t.land_type),
            "treatment": t.treatment,
            "library_id": t.library_id,
            # Feedback rule: once a follow-up is linked, this library option is no
            # longer recommended to the farmer unless staff re-allow it.
            "recommend_again": bool(t.recommend_again),
            "follow_up_set_by": t.follow_up_set_by,
            "option_type": t.option_type,
            "applied_at": t.applied_at.isoformat() if t.applied_at else "",
            "follow_up_due": t.follow_up_due.isoformat() if t.follow_up_due else None,
            "before_count": before,
            "before_level": t.infestation_level,
            "follow_up_scan_id": t.f_id,
            "follow_up_at": t.f_at.isoformat() if t.f_at else None,
            "after_count": after,
            "after_level": t.f_level if t.f_status == "validated" else None,
            "reduction_pct": reduction,
            "outcome": outcome,
        })
    groups: dict = {}
    for it in items:
        g = groups.setdefault(it["treatment"].lower(), {
            "treatment": it["treatment"], "option_type": it["option_type"], "applications": 0,
            "compared": 0, "improved": 0, "no_change": 0, "worse": 0})
        g["applications"] += 1
        if it["outcome"] in ("improved", "no change", "worse"):
            g["compared"] += 1
            g[it["outcome"].replace(" ", "_")] += 1
    summary = sorted(groups.values(), key=lambda g: (-g["compared"], -g["improved"], g["treatment"]))
    overdue = [i for i in items if i["outcome"] == "overdue"]
    return {"area": area_label(viewer), "items": items, "summary": summary, "overdue": overdue}


# ---------------------------------------------------------------- directional spread

# Fewer validated records with GPS than this in either window: no direction is shown.
SPREAD_MIN_RECORDS = int(os.getenv("SPREAD_MIN_RECORDS", "3"))
# Centres closer than this count as "about the same area" (GPS noise, not movement).
SPREAD_STILL_KM = 0.1
SPREAD_WINDOWS = (7, 14, 30)
SPREAD_NOTE = "Based on reported cases only. It shows observed movement, not a forecast."
NOT_ENOUGH = "Not enough data to show direction."
_COMPASS = [("N", "north"), ("NE", "northeast"), ("E", "east"), ("SE", "southeast"),
            ("S", "south"), ("SW", "southwest"), ("W", "west"), ("NW", "northwest")]


def _bearing(lat1, lng1, lat2, lng2) -> float:
    """Initial great-circle bearing, degrees clockwise from north."""
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dl = math.radians(lng2 - lng1)
    x = math.sin(dl) * math.cos(p2)
    y = math.cos(p1) * math.sin(p2) - math.sin(p1) * math.cos(p2) * math.cos(dl)
    return (math.degrees(math.atan2(x, y)) + 360) % 360


def _km(lat1, lng1, lat2, lng2) -> float:
    p1, p2 = math.radians(lat1), math.radians(lat2)
    a = math.sin((p2 - p1) / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(math.radians(lng2 - lng1) / 2) ** 2
    return 2 * 6371.0 * math.asin(math.sqrt(a))


def compass(bearing: float) -> tuple:
    """("NE", "northeast") for a bearing in degrees."""
    return _COMPASS[int((bearing + 22.5) // 45) % 8]


def _span(a: date, b: date) -> str:
    if a.month == b.month:
        return f"{a:%b} {a.day}-{b.day}"
    return f"{a:%b} {a.day} - {b:%b} {b.day}"


def spread(points: list, end: date, window_days: int = 7, min_records: int = SPREAD_MIN_RECORDS) -> dict:
    """For each pest, where its validated cases cluster in two consecutive
    windows (e.g. the week before vs the latest week) and how the centre moved.

    `points`: validated observations with GPS, already filtered and limited to
    the viewer's area. Centres are plain averages of the coordinates, which is
    accurate at municipal or provincial scale. A pest needs `min_records` in
    BOTH windows; otherwise its direction is "not enough data"."""
    w2_start = end - timedelta(days=window_days - 1)
    w1_end = w2_start - timedelta(days=1)
    w1_start = w1_end - timedelta(days=window_days - 1)
    unit = "Week" if window_days == 7 else "Period"
    names = (f"{unit} 1", f"{unit} 2")
    windows = [
        {"name": names[0], "start": w1_start.isoformat(), "end": w1_end.isoformat(), "label": _span(w1_start, w1_end)},
        {"name": names[1], "start": w2_start.isoformat(), "end": end.isoformat(), "label": _span(w2_start, end)},
    ]
    by_pest: dict = defaultdict(lambda: ([], []))
    for p in points:
        if p.get("lat") is None or p.get("lng") is None:
            continue
        day = p["created_at"][:10]
        if w1_start.isoformat() <= day <= w1_end.isoformat():
            by_pest[p["pest"]][0].append(p)
        elif w2_start.isoformat() <= day <= end.isoformat():
            by_pest[p["pest"]][1].append(p)

    def centre(pts):
        if not pts:
            return None
        return {"lat": sum(p["lat"] for p in pts) / len(pts), "lng": sum(p["lng"] for p in pts) / len(pts),
                "records": len(pts)}

    out = []
    for pest in sorted(by_pest):
        first, second = by_pest[pest]
        c1, c2 = centre(first), centre(second)
        used = len(first) + len(second)
        span = f"between {names[0]} ({windows[0]['label']}) and {names[1]} ({windows[1]['label']})"
        records_text = (f"{used} record{'s' if used != 1 else ''} used "
                        f"({len(first)} in {names[0]}, {len(second)} in {names[1]}).")
        item = {"pest": pest, "from": c1, "to": c2, "records_used": used,
                "records": [len(first), len(second)], "direction": None, "direction_word": None,
                "bearing": None, "distance_km": None}
        if len(first) < min_records or len(second) < min_records:
            item.update(status="insufficient", message=NOT_ENOUGH,
                        detail=f"Needs at least {min_records} validated records with a location in each "
                               f"{unit.lower()}. {records_text}")
        else:
            km = _km(c1["lat"], c1["lng"], c2["lat"], c2["lng"])
            item["distance_km"] = round(km, 2)
            if km < SPREAD_STILL_KM:
                item.update(status="still",
                            message=f"Reported cases stayed in about the same area {span}.",
                            detail=records_text)
            else:
                b = _bearing(c1["lat"], c1["lng"], c2["lat"], c2["lng"])
                short, word = compass(b)
                dist = f"{round(km * 1000)} m" if km < 1 else f"{km:.1f} km"
                item.update(status="moved", direction=short, direction_word=word, bearing=round(b, 1),
                            message=f"Reported cases moved toward the {word} {span}.",
                            detail=f"About {dist}. {records_text}")
        out.append(item)
    order = {"moved": 0, "still": 1, "insufficient": 2}
    out.sort(key=lambda i: (order[i["status"]], -i["records_used"], i["pest"]))
    return {"window_days": window_days, "windows": windows, "min_records": min_records,
            "note": SPREAD_NOTE, "not_enough_message": NOT_ENOUGH, "pests": out}
