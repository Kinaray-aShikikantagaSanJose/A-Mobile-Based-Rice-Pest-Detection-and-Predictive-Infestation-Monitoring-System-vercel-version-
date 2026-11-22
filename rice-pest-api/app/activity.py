"""User sessions and the activity log (supabase/01_schema.sql, section E).

* A session starts at sign-in. Its id ("sid") travels inside the access and
  refresh tokens; each request moves last_seen_at forward (at most every
  TOUCH_SECONDS), sign-out closes it and its tokens stop working.
* log() records sign-ins (also failed ones), sign-outs and important actions.
  It never raises and never blocks the action itself: before the migration
  has run (tables missing) it does nothing.

The request's IP address, user agent and app ("mobile", "web", "dashboard",
from the X-Palay-Client header) are taken from a per-request context filled
by the middleware in main.py; the signed-in account is added by
access.require_role.
"""
import contextvars
import json
import logging
import uuid
from typing import Optional

from sqlalchemy import text
from sqlalchemy.orm import Session

from . import schema

log_ = logging.getLogger(__name__)

TOUCH_SECONDS = 120

# What the dashboard filters on. Keys are stored in user_activity_logs.action_type.
ACTIONS = (
    "login", "login_failed", "logout", "session_resumed",
    "account_registered", "email_verified", "otp_resent", "account_deleted",
    "profile_updated", "password_changed", "avatar_changed", "language_changed", "location_updated",
    "observation_submitted", "observation_no_pests", "observation_reviewed", "observation_deleted",
    "treatment_logged", "treatment_updated",
    "user_created", "user_updated", "user_deleted",
    "library_changed", "criteria_changed", "report_exported",
)

_REQUEST: contextvars.ContextVar = contextvars.ContextVar("palay_request", default=None)


# ---------------------------------------------------------------- request context

def begin_request(request) -> contextvars.Token:
    """Called by the middleware. The dict is shared by reference, so the
    account added later by a dependency (another thread) is seen everywhere."""
    headers = request.headers
    forwarded = headers.get("x-forwarded-for", "").split(",")[0].strip()
    ip = forwarded or headers.get("x-real-ip", "") or (request.client.host if request.client else "")
    ua = headers.get("user-agent", "")
    client = headers.get("x-palay-client", "").strip().lower()[:20]
    if not client:
        client = "mobile" if "dart" in ua.lower() else ("web" if ua else "")
    return _REQUEST.set({"ip": ip[:64], "ua": ua[:300], "client": client, "actor": None})


def end_request(token: contextvars.Token) -> None:
    _REQUEST.reset(token)


def context() -> dict:
    return _REQUEST.get() or {"ip": "", "ua": "", "client": "", "actor": None}


def set_actor(actor: dict) -> None:
    ctx = _REQUEST.get()
    if ctx is not None:
        ctx["actor"] = actor


# ---------------------------------------------------------------- sessions

def start_session(db: Session, *, email: str, role: str, user_id: Optional[int] = None) -> Optional[str]:
    """New session row; returns its id (None before the migration). The caller commits."""
    if not schema.activity_ready(db):
        return None
    sid = str(uuid.uuid4())
    ctx = context()
    try:
        with db.begin_nested():
            db.execute(
                text("INSERT INTO user_sessions (id, user_id, user_email, user_role, client, ip_address, user_agent, "
                     "request_count) VALUES (CAST(:id AS uuid), :uid, :e, :r, :c, :ip, :ua, 1)"),
                {"id": sid, "uid": user_id, "e": email, "r": role or "", "c": ctx["client"],
                 "ip": ctx["ip"], "ua": ctx["ua"]},
            )
    except Exception as e:
        log_.warning("Could not start a session row: %s", e)
        return None
    return sid


def session_ended(db: Session, sid: Optional[str]) -> bool:
    """True when the session was signed out (its tokens no longer work)."""
    if not sid or not schema.activity_ready(db):
        return False
    try:
        row = db.execute(
            text("SELECT ended_at FROM user_sessions WHERE id = CAST(:id AS uuid)"), {"id": sid}
        ).first()
    except Exception:
        db.rollback()
        return False
    return bool(row and row.ended_at is not None)


def touch_session(db: Session, sid: Optional[str]) -> str:
    """'ended' (signed out), 'unknown' or 'active'. Moves last_seen_at forward
    at most every TOUCH_SECONDS and commits that on its own."""
    if not sid or not schema.activity_ready(db):
        return "unknown"
    try:
        row = db.execute(
            text("SELECT ended_at, last_seen_at < now() - make_interval(secs => :s) AS stale "
                 "FROM user_sessions WHERE id = CAST(:id AS uuid)"),
            {"id": sid, "s": TOUCH_SECONDS},
        ).first()
        if row is None:
            return "unknown"
        if row.ended_at is not None:
            return "ended"
        if row.stale:
            db.execute(
                text("UPDATE user_sessions SET last_seen_at = now(), request_count = request_count + 1 "
                     "WHERE id = CAST(:id AS uuid)"),
                {"id": sid},
            )
            db.commit()
        return "active"
    except Exception as e:  # never fail a request over bookkeeping
        log_.warning("Session touch failed: %s", e)
        db.rollback()
        return "unknown"


def end_session(db: Session, sid: Optional[str], reason: str = "logout") -> bool:
    """Closes the session (the caller commits). True if it was open."""
    if not sid or not schema.activity_ready(db):
        return False
    try:
        with db.begin_nested():
            res = db.execute(
                text("UPDATE user_sessions SET ended_at = now(), end_reason = :r, last_seen_at = now() "
                     "WHERE id = CAST(:id AS uuid) AND ended_at IS NULL"),
                {"id": sid, "r": reason},
            )
        return res.rowcount > 0
    except Exception as e:
        log_.warning("Could not end session: %s", e)
        return False


def end_all_sessions(db: Session, email: str, reason: str) -> None:
    if not schema.activity_ready(db):
        return
    try:
        with db.begin_nested():
            db.execute(
                text("UPDATE user_sessions SET ended_at = now(), end_reason = :r "
                     "WHERE user_email = :e AND ended_at IS NULL"),
                {"e": email, "r": reason},
            )
    except Exception as e:
        log_.warning("Could not end sessions: %s", e)


# ---------------------------------------------------------------- log

def log(db: Session, action: str, *, email: Optional[str] = None, role: Optional[str] = None,
        name: Optional[str] = None, user_id: Optional[int] = None, session_id: Optional[str] = None,
        target_type: str = "", target_id="", outcome: str = "success",
        details: Optional[dict] = None, commit: bool = False) -> None:
    """Adds one activity row (in the caller's transaction unless commit=True).
    The signed-in account and session come from the request context when not
    given. Never raises."""
    if not schema.activity_ready(db):
        return
    ctx = context()
    actor = ctx.get("actor") or {}
    try:
        with db.begin_nested():
            db.execute(
                text(
                    """
                    INSERT INTO user_activity_logs (user_id, user_email, user_name, user_role, session_id,
                                                    action_type, target_type, target_id, outcome, client,
                                                    ip_address, user_agent, details)
                    VALUES (COALESCE(:uid, (SELECT id FROM users WHERE email = :e)), :e, :n, :r,
                            CAST(:sid AS uuid), :a, :tt, :ti, :o, :c, :ip, :ua, CAST(:d AS jsonb))
                    """
                ),
                {
                    "uid": user_id,
                    "e": (email if email is not None else actor.get("email", "")) or "",
                    "n": (name if name is not None else actor.get("full_name", "")) or "",
                    "r": (role if role is not None else actor.get("role", "")) or "",
                    "sid": session_id if session_id is not None else actor.get("sid"),
                    "a": action[:40],
                    "tt": target_type[:30],
                    "ti": str(target_id or "")[:64],
                    "o": outcome if outcome in ("success", "failure") else "success",
                    "c": ctx["client"],
                    "ip": ctx["ip"],
                    "ua": ctx["ua"],
                    "d": json.dumps(details or {}, default=str),
                },
            )
        if commit:
            db.commit()
    except Exception as e:
        log_.warning("Activity log %s not saved: %s", action, e)
