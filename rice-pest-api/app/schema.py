"""Which optional columns exist in the geo database.

New columns ship as SQL files that someone runs as postgres (the API's login
can't ALTER tables). Until then the features that need them switch off
instead of failing every request. A missing column is checked again after a
minute, so running the migration takes effect without restarting the API.
"""
import time

from sqlalchemy import text
from sqlalchemy.orm import Session

_RECHECK_SECONDS = 60
_present: set = set()
_missing: dict = {}  # (kind, name, column) -> time it was last found missing


def _cached(key: tuple, probe) -> bool:
    if key in _present:
        return True
    checked = _missing.get(key)
    if checked is not None and time.monotonic() - checked < _RECHECK_SECONDS:
        return False
    try:
        found = bool(probe())
    except Exception:  # never break a request over a feature check
        found = False
    if found:
        _present.add(key)
        _missing.pop(key, None)
    else:
        _missing[key] = time.monotonic()
    return found


def has_column(db: Session, table: str, column: str) -> bool:
    # table_schema: Supabase also has auth.users, which must not count.
    return _cached(("column", table, column), lambda: db.execute(
        text("SELECT 1 FROM information_schema.columns "
             "WHERE table_schema = 'public' AND table_name = :t AND column_name = :c"),
        {"t": table, "c": column},
    ).first() is not None)


def has_table(db: Session, table: str) -> bool:
    return _cached(("table", table, ""), lambda: db.execute(
        text("SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = :t"),
        {"t": table},
    ).first() is not None)


def has_role(db: Session, role: str) -> bool:
    return _cached(("role", role, ""), lambda: db.execute(
        text("SELECT 1 FROM pg_roles WHERE rolname = :r"), {"r": role},
    ).first() is not None)


def land_type_ready(db: Session) -> bool:
    return has_column(db, "scans", "land_type")


def treatment_rules_ready(db: Session) -> bool:
    return has_column(db, "treatments", "recommend_again")


# ---- supabase/01_schema.sql, section 2026-11

def language_ready(db: Session) -> bool:
    return has_column(db, "users", "preferred_language")


def user_location_ready(db: Session) -> bool:
    return has_column(db, "users", "barangay_psgc")


def scan_location_ready(db: Session) -> bool:
    return has_column(db, "scans", "location_status")


def detection_ready(db: Session) -> bool:
    """detection_result / detection_metadata / image_deleted_at on scans. The
    "no pests found" clean-up only runs once these exist, so a photo is never
    deleted without its result being saved."""
    return has_column(db, "scans", "image_deleted_at")


def activity_ready(db: Session) -> bool:
    return has_table(db, "user_activity_logs") and has_table(db, "user_sessions")


def deleted_records_ready(db: Session) -> bool:
    return has_table(db, "deleted_records")


def permissions_ready(db: Session) -> bool:
    return has_table(db, "role_permissions")
