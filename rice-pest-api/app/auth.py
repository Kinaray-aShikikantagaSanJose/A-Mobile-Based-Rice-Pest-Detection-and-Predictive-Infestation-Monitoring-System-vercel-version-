import secrets
from datetime import datetime, timedelta, timezone
from typing import Optional

from fastapi import APIRouter, Depends, File, HTTPException, UploadFile, status
from fastapi.responses import Response
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from pydantic import BaseModel, EmailStr, Field, field_validator
from sqlalchemy.orm import Session

from . import avatars
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

    return {"message": "New verification code sent successfully."}


@router.post("/login")
def login(payload: LoginSchema, db: Session = Depends(get_db)):
    clean_email = payload.email.strip().lower()
    user = db.query(User).filter(User.email == clean_email).first()

    if not user or not verify_password(payload.password, user.password_hash):
        raise HTTPException(status_code=401, detail="Invalid email or password.")

    if not user.is_verified:
        raise HTTPException(
            status_code=403,
            detail="Please verify your email before logging in.",
        )

    _activate_if_approval_off(user, db)
    # Pending and rejected accounts still get a session so the app can show
    # "Waiting for approval" and check /auth/me; every other endpoint refuses
    # them (access.py checks the status on each request).
    return _session_for(user, db)


def _activate_if_approval_off(user: User, db: Session) -> None:
    """Accounts registered while approval was required stay 'pending'. With
    approval off, activate them on their next sign-in so nobody is stuck."""
    # Only farmers: a requested technician/agriculturist role always needs an agriculturist.
    if not REQUIRE_ACCOUNT_APPROVAL and user.status == "pending" and user.role == "farmer":
        user.status = "approved"
        db.commit()


def _profile(user: User, db: Session) -> dict:
    return {
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


def _session_for(user: User, db: Session) -> dict:
    return {
        "access_token": create_access_token(subject=user.email, role=user.role),
        "refresh_token": create_refresh_token(subject=user.email),
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
            raise HTTPException(status_code=400, detail="Your current password is not correct.")
        user.password_hash = hash_password(payload.new_password)
    if payload.full_name is not None:
        user.full_name = payload.full_name
    if payload.phone is not None:
        user.phone = payload.phone
    if payload.municipality is not None:
        user.region = payload.municipality
    if payload.barangay is not None:
        user.barangay = payload.barangay
    db.commit()
    return _profile(user, db)


@router.post("/me/avatar")
def upload_my_avatar(
    image: UploadFile = File(...),
    user: User = Depends(_signed_in_user),
    db: Session = Depends(get_db),
):
    avatars.save(db, user.id, image)
    db.commit()
    return _profile(user, db)


@router.delete("/me/avatar")
def delete_my_avatar(user: User = Depends(_signed_in_user), db: Session = Depends(get_db)):
    avatars.remove(db, user.id)
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
    _activate_if_approval_off(user, db)
    return _session_for(user, db)


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
    db.query(OTPRecord).filter(OTPRecord.email == clean_email).delete()
    db.delete(user)
    db.commit()
    avatars.delete_files_of(filename)

    return {"message": "Account deleted."}