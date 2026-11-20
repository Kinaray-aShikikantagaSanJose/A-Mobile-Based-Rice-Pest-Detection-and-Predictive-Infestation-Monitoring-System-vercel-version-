from datetime import datetime, timezone
from sqlalchemy import Boolean, Column, DateTime, Integer, String, Text, func
from .database import Base

def get_utc_now():
    return datetime.now(timezone.utc)

class User(Base):
    __tablename__ = "users"

    id = Column(Integer, primary_key=True, index=True)
    full_name = Column(String(100), nullable=False)
    email = Column(String(255), unique=True, nullable=False, index=True)
    password_hash = Column(String(255), nullable=False)
    region = Column(String(100), nullable=False)  # municipality
    barangay = Column(String(100), nullable=False, default="")
    phone = Column(String(30), nullable=False, default="")
    role = Column(String(20), nullable=False, default="farmer")  # Added
    is_verified = Column(Boolean, default=False)
    # pending -> approved | rejected, decided by an agriculturist on the dashboard.
    status = Column(String(20), nullable=False, default="pending")
    # Technicians: barangays covered inside `region`, comma-separated ('' = all).
    coverage_barangays = Column(Text, nullable=False, default="")
    reviewed_by = Column(String(255))
    reviewed_at = Column(DateTime(timezone=True))
    created_at = Column(DateTime(timezone=True), server_default=func.now())

class OTPRecord(Base):
    __tablename__ = "otps"

    id = Column(Integer, primary_key=True, index=True)
    email = Column(String(255), index=True, nullable=False)
    otp_code = Column(String(6), nullable=False)
    expires_at = Column(DateTime(timezone=True), nullable=False)
    created_at = Column(DateTime(timezone=True), default=get_utc_now)
    # Wrong guesses against this code; see MAX_OTP_ATTEMPTS in auth.py.
    attempts = Column(Integer, nullable=False, default=0, server_default="0")
