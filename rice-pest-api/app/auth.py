import secrets
from datetime import datetime, timedelta, timezone
from typing import Literal, Optional

from fastapi import APIRouter, Depends, File, HTTPException, UploadFile, status
from fastapi.responses import Response
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from pydantic import BaseModel, EmailStr, Field, field_validator
from sqlalchemy import text
from sqlalchemy.orm import Session

from . import activity, avatars, geo, i18n, schema
from .access import FARMER, REQUIRE_ACCOUNT_APPROVAL, account_is_active, initial_account_status
from .database import get_db
from .email_service import send_otp_email
from .models import OTPRecord, User
from .schemas import (
    RefreshSchema,
    RegisterSchema,
    ResendOtpSchema,
    VerifyOtpSchema,
    check_password_bytes,
    clean_phone,
)
from .security import (
    create_access_token,
    create_refresh_token,
    decode_access_token,
    decode_refresh_token,
    hash_password,
    verify_password,
)

router = APIRouter(prefix="/auth", tags=["Authentication"])
_bearer = HTTPBearer(auto_error=False)

RESEND_COOLDOWN_SECONDS = 45
MAX_OTP_ATTEMPTS = 5


class DeleteAccountSchema(BaseModel):
    email: EmailStr
    password: str


class LoginSchema(BaseModel):
    email: EmailStr
    password: str


class LogoutSchema(BaseModel):
    # Lets an app sign out even when its access token has already expired.
    refresh_token: Optional[str] = None


def _extra(db: Session, user_id: int) -> dict:
    """Language and location codes (supabase/01_schema.sql section 2026-11),
    read with plain SQL so accounts keep working before that migration."""
    cols = []
    if schema.language_ready(db):
        cols.append("preferred_language")
    if schema.user_location_ready(db):
        cols += ["municipality_psgc", "barangay_psgc", "location_source"]
    out = {"preferred_language": "en", "municipality_psgc": None, "barangay_psgc": None,
           "location_source": "manual"}
    if not cols:
        return out
    row = db.execute(text(f"SELECT {', '.join(cols)} FROM users WHERE id = :i"), {"i": user_id}).first()
    if row is not None:
        for c in cols:
            out[c] = getattr(row, c)
    out["preferred_language"] = i18n.clean(out["preferred_language"])
    return out


def _save_location(db: Session, user: User, barangay_psgc: Optional[str], source: str) -> None:
    """Stores the official codes for the account's municipality and barangay
    (from the code the app sent, else by matching the typed names). The names
    themselves are kept exactly as saved. The caller commits."""
    if not schema.user_location_ready(db):
        return
    try:
        found = geo.resolve_profile_location(user.region or "", user.barangay or "", barangay_psgc)
    except Exception:  # location data missing on the server: keep the names only
        found = {"municipality_psgc": None, "barangay_psgc": None}
    db.execute(
        text("UPDATE users SET municipality_psgc = :m, barangay_psgc = :b, location_source = :s, "
             "location_updated_at = now() WHERE id = :i"),
        {"m": found["municipality_psgc"], "b": found["barangay_psgc"],
         "s": source if source in ("manual", "gps") else "manual", "i": user.id},
    )


def _save_language(db: Session, user_id: int, code: Optional[str]) -> None:
    if code and schema.language_ready(db):
        db.execute(text("UPDATE users SET preferred_language = :l WHERE id = :i"),
                   {"l": i18n.clean(code), "i": user_id})


def _generate_otp() -> str:
    return f"{secrets.randbelow(900000) + 100000}"


def _create_and_send_otp(db: Session, email: str) -> None:
    """Deletes stale OTPs, creates a new one, and sends it.
    Rolls back and raises if the email fails to send, so a caller
    never ends up with an invalidated code and no new email in hand.
    Enforces a cooldown so a second call can't silently invalidate
    a code that was just emailed a moment ago.
    """
    latest = (
        db.query(OTPRecord)
        .filter(OTPRecord.email == email)
        .order_by(OTPRecord.created_at.desc())
        .first()
    )

    if latest and latest.created_at:
        created_at = latest.created_at
        if created_at.tzinfo is None:
            created_at = created_at.replace(tzinfo=timezone.utc)

        elapsed = (datetime.now(timezone.utc) - created_at).total_seconds()
        if elapsed < RESEND_COOLDOWN_SECONDS:
            remaining = RESEND_COOLDOWN_SECONDS - int(elapsed)
            raise HTTPException(
                status_code=429,
                detail=f"Please wait {remaining} seconds before requesting another code.",
            )

    db.query(OTPRecord).filter(OTPRecord.email == email).delete()

    otp_code = _generate_otp()
    expires_at = datetime.now(timezone.utc) + timedelta(minutes=10)

    otp_entry = OTPRecord(
        email=email,
        otp_code=otp_code,
        expires_at=expires_at,
    )
    db.add(otp_entry)
    # Flush, not commit: the delete and insert stay uncommitted until the
    # email is sent, so the rollback below restores the previous code.
    db.flush()

    try:
        send_otp_email(email, otp_code)
    except Exception as e:
        db.rollback()
        raise HTTPException(
            status_code=500,
            detail=f"Could not send verification email: {e}",
        )

    db.commit()


@router.post("/register")
def register(
    payload: RegisterSchema,
    db: Session = Depends(get_db),
):
    clean_email = payload.email.strip().lower()

    # The requested role is stored. Technician and agriculturist requests always
    # stay 'pending' (no access) until an agriculturist approves them on the
    # dashboard. Farmers start 'approved' while REQUIRE_ACCOUNT_APPROVAL is off.
    user = db.query(User).filter(User.email == clean_email).first()

    if user:
        if user.is_verified:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Email is already registered.",
            )
        user.full_name = payload.full_name
        user.password_hash = hash_password(payload.password)
        user.region = payload.municipality
        user.barangay = payload.barangay
        user.phone = payload.phone
        user.role = payload.role
        user.status = initial_account_status(payload.role)
    else:
        user = User(
            full_name=payload.full_name,
            email=clean_email,
            password_hash=hash_password(payload.password),
            region=payload.municipality,
            barangay=payload.barangay,
            phone=payload.phone,
            role=payload.role,
            status=initial_account_status(payload.role),
            is_verified=False,
        )
        db.add(user)

    db.commit()
    db.refresh(user)
    _save_location(db, user, payload.barangay_psgc, payload.location_source)
    _save_language(db, user.id, payload.preferred_language)
    activity.log(db, "account_registered", email=clean_email, role=payload.role, name=payload.full_name,
                 user_id=user.id, target_type="user", target_id=user.id,
                 details={"municipality": payload.municipality, "location_source": payload.location_source})
    db.commit()

    _create_and_send_otp(db, clean_email)

    return {
        "message": "Registration successful. Verification code sent.",
        "email": clean_email,
    }


@router.post("/verify-otp")
def verify_otp(payload: VerifyOtpSchema, db: Session = Depends(get_db)):
    clean_email = payload.email.strip().lower()
    clean_code = payload.code.strip()

    record = (
        db.query(OTPRecord)
        .filter(OTPRecord.email == clean_email)
        .order_by(OTPRecord.created_at.desc())
        .first()
    )

    if not record:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid verification code.",
        )

    # Cap wrong guesses per code so the 6 digits can't be brute-forced.
    if not secrets.compare_digest(record.otp_code, clean_code):
        record.attempts = (record.attempts or 0) + 1
        activity.log(db, "email_verified", email=clean_email, outcome="failure",
                     details={"reason": "wrong_code", "attempt": record.attempts})
        if record.attempts >= MAX_OTP_ATTEMPTS:
            db.delete(record)
            db.commit()
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Too many incorrect attempts. Please request a new code.",
            )
        db.commit()
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid verification code.",
        )

    # Timezone-aware expiration check (Python 3.13+)
    now_utc = datetime.now(timezone.utc)
    expiry = record.expires_at
    if expiry.tzinfo is None:
        expiry = expiry.replace(tzinfo=timezone.utc)

    if now_utc > expiry:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Verification code has expired.",
        )

    user = db.query(User).filter(User.email == clean_email).first()
    if not user:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="User record not found.",
        )

    user.is_verified = True
    db.query(OTPRecord).filter(OTPRecord.email == clean_email).delete()
    activity.log(db, "email_verified", email=clean_email, role=user.role, name=user.full_name, user_id=user.id)
    db.commit()

    return {
        "message": "Email verified. You can now log in."
        if account_is_active(user.status, user.role)
        else "Email verified. An agriculturist will review and approve your account.",
        "status": user.status,
    }


@router.post("/resend-otp")
def resend_otp(
    payload: ResendOtpSchema,
    db: Session = Depends(get_db),
):
    clean_email = payload.email.strip().lower()

    user = db.query(User).filter(User.email == clean_email).first()
    if not user:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="User account not found.",
        )

    if user.is_verified:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Account is already verified.",
        )

    _create_and_send_otp(db, clean_email)
    activity.log(db, "otp_resent", email=clean_email, role=user.role, name=user.full_name, user_id=user.id,
                 commit=True)

    return {"message": "New verification code sent successfully."}


@router.post("/login")
def login(payload: LoginSchema, db: Session = Depends(get_db)):
    clean_email = payload.email.strip().lower()
    user = db.query(User).filter(User.email == clean_email).first()

    if not user or not verify_password(payload.password, user.password_hash):
        activity.log(db, "login_failed", email=clean_email, role=user.role if user else "",
                     name=user.full_name if user else "", user_id=user.id if user else None,
                     outcome="failure", details={"reason": "wrong_password" if user else "unknown_account"},
                     commit=True)
        raise HTTPException(status_code=401, detail="Invalid email or password.")

    if not user.is_verified:
        activity.log(db, "login_failed", email=clean_email, role=user.role, name=user.full_name,
                     user_id=user.id, outcome="failure", details={"reason": "email_not_verified"}, commit=True)
        raise HTTPException(
            status_code=403,
            detail="Please verify your email before logging in.",
        )

    _activate_if_approval_off(user, db)
    # Pending and rejected accounts still get a session so the app can show
    # "Waiting for approval" and check /auth/me; every other endpoint refuses
    # them (access.py checks the status on each request).
    sid = activity.start_session(db, email=user.email, role=user.role, user_id=user.id)
    activity.log(db, "login", email=user.email, role=user.role, name=user.full_name, user_id=user.id,
                 session_id=sid, details={"status": user.status})
    db.commit()
    return _session_for(user, db, sid)


def _activate_if_approval_off(user: User, db: Session) -> None:
    """Accounts registered while approval was required stay 'pending'. With
    approval off, activate them on their next sign-in so nobody is stuck."""
    # Only farmers: a requested technician/agriculturist role always needs an agriculturist.
    if not REQUIRE_ACCOUNT_APPROVAL and user.status == "pending" and user.role == "farmer":
        user.status = "approved"
        db.commit()


def _profile(user: User, db: Session) -> dict:
    return {
        **_extra(db, user.id),
        "id": user.id,
        "email": user.email,
        "full_name": user.full_name,
        "role": user.role,
        "status": user.status,
        "municipality": user.region or "",
        "barangay": user.barangay or "",
        "phone": user.phone or "",
        "coverage_barangays": [b.strip() for b in (user.coverage_barangays or "").split(",") if b.strip()],
        "avatar_url": avatars.url_for(user.id, avatars.filename_of(db, user.id)),
    }


def _session_for(user: User, db: Session, sid: Optional[str] = None) -> dict:
    return {
        "access_token": create_access_token(subject=user.email, role=user.role, sid=sid),
        "refresh_token": create_refresh_token(subject=user.email, sid=sid),
        **_profile(user, db),
    }


def _signed_in_user(
    creds: Optional[HTTPAuthorizationCredentials] = Depends(_bearer),
    db: Session = Depends(get_db),
) -> User:
    """The account behind the access token, whatever its approval status."""
    payload = decode_access_token(creds.credentials) if creds else None
    if not payload or payload.get("type") != "access":
        raise HTTPException(status_code=401, detail="Session expired. Please log in again.")
    user = db.query(User).filter(User.email == payload.get("sub", "")).first()
    if user is None:
        raise HTTPException(status_code=401, detail="Account not found. Please log in again.")
    sid = payload.get("sid")
    if activity.touch_session(db, sid) == "ended":
        raise HTTPException(status_code=401, detail="Session expired. Please log in again.")
    activity.set_actor({"email": user.email, "role": user.role, "full_name": user.full_name, "sid": sid})
    return user


@router.get("/me")
def me(user: User = Depends(_signed_in_user), db: Session = Depends(get_db)):
    """Profile and approval status. Works for pending accounts too."""
    _activate_if_approval_off(user, db)
    return _profile(user, db)


class ProfileUpdate(BaseModel):
    """Changes a person makes to their own account (mobile Profile screen)."""

    full_name: Optional[str] = Field(None, min_length=2, max_length=100)
    phone: Optional[str] = None
    municipality: Optional[str] = Field(None, min_length=1, max_length=100)
    barangay: Optional[str] = Field(None, min_length=1, max_length=100)
    current_password: Optional[str] = None
    new_password: Optional[str] = Field(None, min_length=8, max_length=72)
    # en | fil (Filipino) | krj (Kinaray-a)
    preferred_language: Optional[Literal["en", "fil", "krj"]] = None
    # Official code of the barangay when it was picked from the list or found
    # from GPS (and confirmed by the person).
    barangay_psgc: Optional[str] = Field(None, max_length=10, pattern=r"^[0-9]{10}$")
    location_source: Optional[Literal["manual", "gps"]] = None

    @field_validator("full_name", "municipality", "barangay")
    @classmethod
    def _strip(cls, v):
        if v is None:
            return v
        v = v.strip()
        if not v:
            raise ValueError("This field is required.")
        return v

    @field_validator("phone")
    @classmethod
    def _phone(cls, v):
        return None if v is None else clean_phone(v)

    @field_validator("new_password")
    @classmethod
    def _bytes(cls, v):
        return None if v is None else check_password_bytes(v)


@router.put("/me")
def update_me(payload: ProfileUpdate, user: User = Depends(_signed_in_user), db: Session = Depends(get_db)):
    # A technician's municipality decides which queue they work, so only an
    # agriculturist changes it (dashboard, User management).
    if (
        payload.municipality is not None
        and payload.municipality.lower() != (user.region or "").strip().lower()
        and user.role != FARMER
    ):
        raise HTTPException(
            status_code=400,
            detail="Your municipality sets your coverage area. Ask an agriculturist to change it.",
        )
    if payload.new_password:
        if not payload.current_password or not verify_password(payload.current_password, user.password_hash):
            activity.log(db, "password_changed", outcome="failure", details={"reason": "wrong_current_password"},
                         commit=True)
            raise HTTPException(status_code=400, detail="Your current password is not correct.")
        user.password_hash = hash_password(payload.new_password)
        activity.log(db, "password_changed", target_type="user", target_id=user.id)
    changed = []
    if payload.full_name is not None and payload.full_name != user.full_name:
        user.full_name = payload.full_name
        changed.append("full_name")
    if payload.phone is not None and payload.phone != (user.phone or ""):
        user.phone = payload.phone
        changed.append("phone")
    location_changed = False
    if payload.municipality is not None and payload.municipality != (user.region or ""):
        user.region = payload.municipality
        location_changed = True
    if payload.barangay is not None and payload.barangay != (user.barangay or ""):
        user.barangay = payload.barangay
        location_changed = True
    # Accounts saved before PSGC codes existed get them the next time the
    # person saves their area (same names), without logging a change.
    codes_missing = (
        (payload.municipality is not None or payload.barangay is not None)
        and schema.user_location_ready(db)
        and _extra(db, user.id)["barangay_psgc"] is None
    )
    if location_changed or payload.barangay_psgc is not None or codes_missing:
        db.flush()
        _save_location(db, user, payload.barangay_psgc, payload.location_source or "manual")
    if location_changed or payload.barangay_psgc is not None:
        activity.log(db, "location_updated", target_type="user", target_id=user.id,
                     details={"municipality": user.region, "barangay": user.barangay,
                              "source": payload.location_source or "manual"})
    if payload.preferred_language is not None:
        before = _extra(db, user.id)["preferred_language"]
        if before != payload.preferred_language:
            _save_language(db, user.id, payload.preferred_language)
            activity.log(db, "language_changed", target_type="user", target_id=user.id,
                         details={"from": before, "to": payload.preferred_language})
    if changed:
        activity.log(db, "profile_updated", target_type="user", target_id=user.id, details={"fields": changed})
    db.commit()
    return _profile(user, db)


@router.post("/me/avatar")
def upload_my_avatar(
    image: UploadFile = File(...),
    user: User = Depends(_signed_in_user),
    db: Session = Depends(get_db),
):
    avatars.save(db, user.id, image)
    activity.log(db, "avatar_changed", target_type="user", target_id=user.id, details={"action": "upload"})
    db.commit()
    return _profile(user, db)


@router.delete("/me/avatar")
def delete_my_avatar(user: User = Depends(_signed_in_user), db: Session = Depends(get_db)):
    avatars.remove(db, user.id)
    activity.log(db, "avatar_changed", target_type="user", target_id=user.id, details={"action": "remove"})
    db.commit()
    return _profile(user, db)


@router.get("/avatar/{user_id}")
def avatar(user_id: int, _: User = Depends(_signed_in_user), db: Session = Depends(get_db)):
    """Anyone signed in may load a profile picture (they appear next to names)."""
    data = avatars.read(avatars.filename_of(db, user_id))
    if data is None:
        raise HTTPException(status_code=404, detail="No profile picture.")
    # The URL changes with every upload (?v=), so it can be cached for long.
    return Response(content=data, media_type="image/jpeg", headers={"Cache-Control": "private, max-age=86400"})


@router.post("/refresh")
def refresh(payload: RefreshSchema, db: Session = Depends(get_db)):
    """Swaps a refresh token for a new access + refresh pair (sliding session)."""
    data = decode_refresh_token(payload.refresh_token)
    if data is None:
        raise HTTPException(status_code=401, detail="Session expired. Please log in again.")
    user = db.query(User).filter(User.email == data.get("sub", "")).first()
    if user is None or not user.is_verified:
        raise HTTPException(status_code=401, detail="Session expired. Please log in again.")
    sid = data.get("sid")
    if activity.session_ended(db, sid):
        # Signed out (or ended by an agriculturist): the refresh token is dead.
        raise HTTPException(status_code=401, detail="Session expired. Please log in again.")
    _activate_if_approval_off(user, db)
    if not sid:
        # Signed in before sessions were recorded: start one now.
        sid = activity.start_session(db, email=user.email, role=user.role, user_id=user.id)
        activity.log(db, "session_resumed", email=user.email, role=user.role, name=user.full_name,
                     user_id=user.id, session_id=sid)
        db.commit()
    else:
        activity.touch_session(db, sid)
    return _session_for(user, db, sid)


@router.post("/logout")
def logout(
    payload: Optional[LogoutSchema] = None,
    creds: Optional[HTTPAuthorizationCredentials] = Depends(_bearer),
    db: Session = Depends(get_db),
):
    """Ends the sign-in session: its access and refresh tokens stop working.
    Always answers 200 (signing out twice, or with an expired token, is fine)."""
    data = decode_access_token(creds.credentials) if creds else None
    if not data and payload and payload.refresh_token:
        data = decode_refresh_token(payload.refresh_token)
    if not data:
        return {"message": "Signed out."}
    email = data.get("sub", "")
    user = db.query(User).filter(User.email == email).first()
    sid = data.get("sid")
    ended = activity.end_session(db, sid, "logout")
    if user is not None:
        activity.log(db, "logout", email=user.email, role=user.role, name=user.full_name, user_id=user.id,
                     session_id=sid, details={"session_was_open": ended})
    db.commit()
    return {"message": "Signed out."}


@router.delete("/account")
def delete_account(payload: DeleteAccountSchema, db: Session = Depends(get_db)):
    clean_email = payload.email.strip().lower()

    user = db.query(User).filter(User.email == clean_email).first()
    if not user:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Account not found.",
        )

    if not verify_password(payload.password, user.password_hash):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid email or password.",
        )

    filename = avatars.filename_of(db, user.id)
    activity.end_all_sessions(db, clean_email, "account_deleted")
    activity.log(db, "account_deleted", email=clean_email, role=user.role, name=user.full_name,
                 target_type="user", target_id=user.id, details={"by": "self"})
    db.query(OTPRecord).filter(OTPRecord.email == clean_email).delete()
    db.delete(user)
    db.commit()
    avatars.delete_files_of(filename)

    return {"message": "Account deleted."}