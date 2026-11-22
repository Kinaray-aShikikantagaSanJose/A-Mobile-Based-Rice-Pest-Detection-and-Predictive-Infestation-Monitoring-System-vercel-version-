import re
from typing import Literal, Optional

from pydantic import BaseModel, EmailStr, Field, field_validator

PHONE = re.compile(r"\+?[0-9][0-9 \-]{5,28}")
PHONE_ERROR = "Enter a valid mobile number, e.g. 0917 123 4567."


def clean_phone(v: str) -> str:
    v = v.strip()
    if not PHONE.fullmatch(v):
        raise ValueError(PHONE_ERROR)
    return v


def check_password_bytes(v: str) -> str:
    if len(v.encode("utf-8")) > 72:
        raise ValueError("Password is too long (72 bytes at most).")
    return v


class RegisterSchema(BaseModel):
    full_name: str = Field(min_length=2, max_length=100)
    email: EmailStr
    # bcrypt only uses the first 72 bytes; longer passwords are rejected, not cut.
    password: str = Field(min_length=8, max_length=72)
    phone: str = Field(min_length=7, max_length=30)
    municipality: str = Field(min_length=1, max_length=100)
    barangay: str = Field(min_length=1, max_length=100)
    # The role the person asks for. A technician or agriculturist request stays
    # 'pending' (no access) until an agriculturist approves it and confirms or
    # changes the role. Farmers need approval only while REQUIRE_ACCOUNT_APPROVAL is on.
    role: Literal["farmer", "technician", "agriculturist"] = "farmer"
    # Optional (newer apps): the barangay's PSGC code when it was picked from
    # the official list or found from GPS, how it was found, and the language
    # chosen in the app (en, fil = Filipino, krj = Kinaray-a).
    barangay_psgc: Optional[str] = Field(None, max_length=10, pattern=r"^[0-9]{10}$")
    location_source: Literal["manual", "gps"] = "manual"
    preferred_language: Optional[Literal["en", "fil", "krj"]] = None

    @field_validator("phone")
    @classmethod
    def _phone(cls, v: str) -> str:
        return clean_phone(v)

    @field_validator("full_name", "municipality", "barangay")
    @classmethod
    def _strip(cls, v: str) -> str:
        v = v.strip()
        if not v:
            raise ValueError("This field is required.")
        return v

    @field_validator("password")
    @classmethod
    def _bytes(cls, v: str) -> str:
        return check_password_bytes(v)


class VerifyOtpSchema(BaseModel):
    email: EmailStr
    code: str


class ResendOtpSchema(BaseModel):
    email: EmailStr


class RefreshSchema(BaseModel):
    refresh_token: str
