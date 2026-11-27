from datetime import date, timedelta

from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Query, Request
from sqlalchemy.orm import Session

from . import i18n, insights
from .access import STAFF, require_viewer
from .database import get_geo_db, local_today
from .trend_service import MIN_WEEKS_FOR_MODEL, predict_weekly_pests

router = APIRouter(prefix="/analytics", tags=["Analytics"])

# Technicians see their coverage area; agriculturists see every area.
# Only validated observations appear on the map and in the summaries.


@router.get("/overview")
def overview(
    db: Session = Depends(get_geo_db),
    viewer: dict = Depends(require_viewer(*STAFF)),
):
    return insights.overview(db, viewer)


@router.get("/hotspots")
def hotspots(
    pest: str = "",
    level: str = "",
    municipality: str = "",
    crop_stage: str = "",
    start: str = "",
    end: str = "",
    land_type: str = "",
    db: Session = Depends(get_geo_db),
    viewer: dict = Depends(require_viewer(*STAFF)),
):
    rows = insights.load_scans(db, viewer, start=insights.parse_day(start), end=insights.parse_day(end))
    # The heatmap layer is drawn from these same points, so it shows exactly
    # what the markers show: validated records, limited to the viewer's area.
    points = [
        r for r in insights.filter_scans(rows, pest=pest, level=level, municipality=municipality,
                                         crop_stage=crop_stage, land_type=land_type)
        if r["lat"] is not None
    ]
    return {
        "area": insights.area_label(viewer),
        "points": points,
        "hotspots": insights.hotspots(points),
        "facets": insights.facets(rows),
    }


@router.get("/spread")
def spread(
    request: Request,
    pest: str = "",
    level: str = "",
    municipality: str = "",
    crop_stage: str = "",
    land_type: str = "",
    start: str = "",
    end: str = "",
    window: int = Query(7, description="Days per window: 7 (week to week), 14 or 30."),
    lang: str = "",
    db: Session = Depends(get_geo_db),
    viewer: dict = Depends(require_viewer(*STAFF)),
):
    """Directional spread: for each pest, the centre of its validated cases
    with a reliable location in two consecutive periods, the direction and
    distance between them, and the barangay of each centre where the boundary
    data supports it ("cannot be determined" otherwise).

    Periods: two windows of `window` days ending on `end` (default today), or,
    with both `start` and `end`, the custom range split into two halves
    (at least 2 days, at most 366). Observed movement only, not a forecast.
    Texts are in ?lang= / X-Palay-Language / the account's language."""
    window = window if window in insights.SPREAD_WINDOWS else 7
    last = insights.parse_day(end) or local_today()
    first_custom = insights.parse_day(start) if start and end else None
    if first_custom and not (1 <= (last - first_custom).days <= 365):
        raise HTTPException(status_code=400, detail="Choose a date range of 2 to 366 days.")
    w1_start, _, _, _ = insights.spread_windows(first_custom, last, window)
    rows = insights.load_scans(db, viewer, start=w1_start, end=last)
    points = [
        r for r in insights.filter_scans(rows, pest=pest, level=level, municipality=municipality,
                                         crop_stage=crop_stage, land_type=land_type)
        if r["lat"] is not None
    ]
    language = i18n.request_language(request, viewer, lang)
    return {"area": insights.area_label(viewer),
            **insights.spread(points, last, window, start=first_custom, lang=language)}


@router.get("/records")
def records(
    status: str = "validated",
    q: str = "",
    pest: str = "",
    level: str = "",
    municipality: str = "",
    crop_stage: str = "",
    start: str = "",
    end: str = "",
    land_type: str = "",
    relevance: str = "",
    sort: str = insights.DEFAULT_SORT,
    limit: Optional[int] = Query(None, ge=1, le=500),
    offset: int = Query(0, ge=0),
    db: Session = Depends(get_geo_db),
    viewer: dict = Depends(require_viewer(*STAFF)),
):
    """Observations the viewer may see, filtered and sorted on the server.
    `limit`/`offset` page the result; `total` is the number of matching
    rows, so every page (and the CSV export, which uses the same filters)
    covers the same set. Without `limit` every matching row is returned."""
    statuses = None if status == "all" else ((status,) if status in insights.STATUSES else insights.VALIDATED)
    rows = insights.load_scans(db, viewer, statuses=statuses, start=insights.parse_day(start),
                               end=insights.parse_day(end))
    matching = insights.sort_rows(
        insights.filter_scans(rows, pest=pest, level=level, municipality=municipality,
                              crop_stage=crop_stage, q=q, land_type=land_type, relevance=relevance),
        sort,
    )
    return {
        "area": insights.area_label(viewer),
        "total": len(matching),
        "limit": limit,
        "offset": offset,
        "sort": sort if sort.lstrip("-") in insights.SORTS else insights.DEFAULT_SORT,
        "rows": insights.page(matching, limit, offset),
        "facets": insights.facets(rows),
    }


@router.get("/treatments")
def treatments(
    outcome: str = "",
    limit: Optional[int] = Query(None, ge=1, le=500),
    offset: int = Query(0, ge=0),
    db: Session = Depends(get_geo_db),
    viewer: dict = Depends(require_viewer(*STAFF)),
):
    """Treatments with their follow-ups (before/after). `outcome` filters;
    `limit`/`offset` page the items (newest application first); `summary`
    and `overdue` always cover everything the viewer may see."""
    data = insights.treatment_followups(db, viewer)
    items = [i for i in data["items"] if not outcome or i["outcome"] == outcome
             or (outcome == "pending" and i["pending"])]
    return {**data, "total": len(items), "limit": limit, "offset": offset,
            "items": insights.page(items, limit, offset)}


@router.get("/monthly")
def monthly(
    month: str = "",
    db: Session = Depends(get_geo_db),
    viewer: dict = Depends(require_viewer(*STAFF)),
):
    return insights.monthly_summary(db, viewer, month)


@router.get("/quarterly")
def quarterly(
    quarter: str = "",
    db: Session = Depends(get_geo_db),
    viewer: dict = Depends(require_viewer(*STAFF)),
):
    return insights.quarterly_patterns(db, viewer, quarter)


@router.get("/trends/prediction")
def trend_prediction(
    weeks: int = Query(26, ge=4, le=104),
    ahead: int = Query(4, ge=1, le=12),
    db: Session = Depends(get_geo_db),
    viewer: dict = Depends(require_viewer(*STAFF)),
):
    """Forecast weekly confirmed pest counts for the viewer's authorized area."""
    today = local_today()
    last_week = today - timedelta(days=today.weekday())
    first_week = last_week - timedelta(weeks=weeks - 1)
    rows = insights.load_scans(db, viewer, start=first_week)
    totals: dict[date, dict[str, int]] = {}

    for row in rows:
        if row["report_type"] != "pest" or row["count"] is None:
            continue
        observed_day = date.fromisoformat(row["created_at"][:10])
        week = observed_day - timedelta(days=observed_day.weekday())
        if first_week <= week <= last_week:
            bucket = totals.setdefault(week, {"pests": 0, "observations": 0})
            bucket["pests"] += max(0, int(row["count"]))
            bucket["observations"] += 1

    history = [
        {
            "week": (first_week + timedelta(weeks=i)).isoformat(),
            **totals.get(first_week + timedelta(weeks=i), {"pests": 0, "observations": 0}),
        }
        for i in range(weeks)
    ]
    has_history = any(row["observations"] for row in history)
    predictions = predict_weekly_pests(history, ahead) if has_history else []
    observed_weeks = sum(row["observations"] > 0 for row in history)
    return {
        "history": history,
        "predictions": predictions,
        "method": "linear_regression" if observed_weeks >= MIN_WEEKS_FOR_MODEL else "historical_mean",
        "weeks_ahead": ahead,
        "observed_weeks": observed_weeks,
    }
