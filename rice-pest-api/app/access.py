import os
from typing import Optional

from fastapi import Depends, HTTPException
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy import text
from sqlalchemy.orm import Session

from . import activity, schema
from .database import get_geo_db
from .security import decode_access_token

_bearer = HTTPBearer(auto_error=False)

FARMER, TECHNICIAN, AGRICULTURIST = "farmer", "technician", "agriculturist"

# Account approval by an agriculturist / OPA. Off until an approving office
# account exists: a new account is active as soon as its email is verified.
# Set REQUIRE_ACCOUNT_APPROVAL=true in .env to turn the approval step back on.
REQUIRE_ACCOUNT_APPROVAL = os.getenv("REQUIRE_ACCOUNT_APPROVAL", "false").strip().lower() in (
    "1", "true", "yes", "on",
)


def initial_account_status(role: str = "farmer") -> str:
    """Status for a newly registered account. Technician and agriculturist
    accounts always wait for an agriculturist, even with approval off:
    otherwise anyone could sign up as an agriculturist and manage users."""
    if REQUIRE_ACCOUNT_APPROVAL or role != "farmer":
        return "pending"
    return "approved"


def account_block_reason(status: str, role: str = "farmer") -> Optional[str]:
    """Why an account can't use the API, or None. A rejected (deactivated)
    account is always blocked; a pending one while approval is on, and a
    pending technician/agriculturist always."""
    if status == "rejected":
        return "Your account was not approved."
    if status != "approved" and (REQUIRE_ACCOUNT_APPROVAL or role != "farmer"):
        return "Your account is waiting for approval by an agriculturist."
    return None


def account_is_active(status: str, role: str) -> bool:
    return account_block_reason(status, role) is None
STAFF = (TECHNICIAN, AGRICULTURIST)
EVERYONE = (FARMER, TECHNICIAN, AGRICULTURIST)

# Defaults for role_permissions (supabase/01_schema.sql); the table, when
# present, is the source of truth (an agriculturist can change it in SQL).
DEFAULT_PERMISSIONS = {
    "records.delete": (TECHNICIAN, AGRICULTURIST),
    "activity_logs.view": (AGRICULTURIST,),
}


def has_permission(db: Session, role: str, permission: str) -> bool:
    if schema.permissions_ready(db):
        try:
            return db.execute(
                text("SELECT 1 FROM role_permissions WHERE role = :r AND permission = :p"),
                {"r": role, "p": permission},
            ).first() is not None
        except Exception:
            db.rollback()
    return role in DEFAULT_PERMISSIONS.get(permission, ())


def _access_payload(creds: Optional[HTTPAuthorizationCredentials]) -> dict:
    if creds is None:
        raise HTTPException(status_code=401, detail="Not authenticated.")
    payload = decode_access_token(creds.credentials)
    # 401 (not 403) for a bad or expired token so clients refresh or log the user out.
    # Refresh tokens are rejected too: they carry no role and aren't for API calls.
    if payload is None or payload.get("type") != "access":
        raise HTTPException(status_code=401, detail="Session expired. Please log in again.")
    return payload


def require_role(*roles: str):
    """The signed-in account, read from the users table on every request, so an
    approval, role change or new coverage area applies without a new login.

    Returns {"sub", "email", "full_name", "role", "area", "barangay",
    "coverage", "phone", "sid", "language"}. "area" is the municipality;
    "coverage" lists the barangays a technician covers ([] = the whole
    municipality); "sid" is the sign-in session (None for tokens issued
    before sessions existed)."""
    def dep(
        creds: Optional[HTTPAuthorizationCredentials] = Depends(_bearer),
        db: Session = Depends(get_geo_db),
    ):
        payload = _access_payload(creds)
        lang = ", preferred_language" if schema.language_ready(db) else ""
        row = db.execute(
            text(
                "SELECT email, full_name, role, region, barangay, phone, status, coverage_barangays"
                f"{lang} FROM users_fdw WHERE email = :e"
            ),
            {"e": payload.get("sub", "")},
        ).first()
        if row is None:
            raise HTTPException(status_code=401, detail="Account not found. Please log in again.")
        sid = payload.get("sid")
        # A signed-out session's tokens stop working at once.
        if activity.touch_session(db, sid) == "ended":
            raise HTTPException(status_code=401, detail="Session expired. Please log in again.")
        user = {
            "sub": row.email,
            "email": row.email,
            "full_name": row.full_name,
            "role": row.role,
            "area": (row.region or "").strip(),
            "barangay": (row.barangay or "").strip(),
            "phone": row.phone or "",
            "coverage": [b.strip() for b in (row.coverage_barangays or "").split(",") if b.strip()],
            "sid": sid,
            "language": getattr(row, "preferred_language", None) or "en",
        }
        activity.set_actor(user)
        reason = account_block_reason(row.status, row.role)
        if reason:
            raise HTTPException(status_code=403, detail=reason)
        if row.role not in roles:
            raise HTTPException(status_code=403, detail="Insufficient role.")
        return user
    return dep


# The dashboard uses the same check.
require_viewer = require_role
