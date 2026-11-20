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
_missing: dict = {}  # (table, column) -> time it was last found missing


def has_column(db: Session, table: str, column: str) -> bool:
    key = (table, column)
    if key in _present:
        return True
    checked = _missing.get(key)
    if checked is not None and time.monotonic() - checked < _RECHECK_SECONDS:
        return False
    found = db.execute(
        text("SELECT 1 FROM information_schema.columns WHERE table_name = :t AND column_name = :c"),
        {"t": table, "c": column},
    ).first() is not None
    if found:
        _present.add(key)
        _missing.pop(key, None)
    else:
        _missing[key] = time.monotonic()
    return found


def land_type_ready(db: Session) -> bool:
    return has_column(db, "scans", "land_type")


def treatment_rules_ready(db: Session) -> bool:
    return has_column(db, "treatments", "recommend_again")
