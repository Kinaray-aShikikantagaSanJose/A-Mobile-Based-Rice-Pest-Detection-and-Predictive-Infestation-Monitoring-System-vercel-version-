import os
import bcrypt
from datetime import datetime, timedelta, timezone
from dotenv import load_dotenv
from jose import jwt, JWTError

# Load .env here too, so the secret is found no matter which module is imported first.
load_dotenv()

# Remove the passlib CryptContext entirely
# pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")

JWT_SECRET_KEY = os.getenv("JWT_SECRET_KEY", "").strip()
# Anyone who knows the secret can mint a technician token, so refuse to start
# without a real one. Generate with: openssl rand -hex 32
if (
    len(JWT_SECRET_KEY) < 32
    or JWT_SECRET_KEY.lower().startswith(("replace", "change", "dev-secret"))
):
    raise RuntimeError(
        "JWT_SECRET_KEY is missing or still a placeholder. "
        "Set it in .env to a random value, e.g. the output of `openssl rand -hex 32`."
    )
JWT_ALGORITHM = os.getenv("JWT_ALGORITHM", "HS256")
if JWT_ALGORITHM not in {"HS256", "HS384", "HS512"}:
    raise RuntimeError("JWT_ALGORITHM must be one of HS256, HS384, or HS512.")
ACCESS_TOKEN_EXPIRE_MINUTES = int(os.getenv("ACCESS_TOKEN_EXPIRE_MINUTES", "60"))
# Farmers stay signed in: the app swaps this for a fresh pair before it expires,
# so only 90 days without opening the app ends the session.
REFRESH_TOKEN_EXPIRE_DAYS = int(os.getenv("REFRESH_TOKEN_EXPIRE_DAYS", "90"))

def hash_password(password: str) -> str:
    if len(password.encode("utf-8")) > 72:
        raise ValueError("Password must be at most 72 UTF-8 bytes for bcrypt.")
    salt = bcrypt.gensalt()
    # bcrypt requires bytes, so we encode before hashing and decode for the DB
    hashed = bcrypt.hashpw(password.encode('utf-8'), salt)
    return hashed.decode('utf-8')

def verify_password(plain_password: str, password_hash: str) -> bool:
    if len(plain_password.encode("utf-8")) > 72:
        return False
    try:
        return bcrypt.checkpw(
            plain_password.encode('utf-8'),
            password_hash.encode('utf-8')
        )
    except ValueError:  # bcrypt 5 rejects passwords over 72 bytes
        return False

def create_access_token(subject: str, role: str, sid: str | None = None) -> str:
    """`sid`: the sign-in session (user_sessions.id); signing out ends it."""
    expire = datetime.now(timezone.utc) + timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES)
    payload = {"sub": subject, "role": role, "exp": expire, "type": "access"}
    if sid:
        payload["sid"] = sid
    return jwt.encode(payload, JWT_SECRET_KEY, algorithm=JWT_ALGORITHM)

def create_refresh_token(subject: str, sid: str | None = None) -> str:
    expire = datetime.now(timezone.utc) + timedelta(days=REFRESH_TOKEN_EXPIRE_DAYS)
    payload = {"sub": subject, "exp": expire, "type": "refresh"}
    if sid:
        payload["sid"] = sid
    return jwt.encode(payload, JWT_SECRET_KEY, algorithm=JWT_ALGORITHM)

def decode_access_token(token: str):
    try:
        return jwt.decode(token, JWT_SECRET_KEY, algorithms=[JWT_ALGORITHM])
    except JWTError:
        return None

def decode_refresh_token(token: str):
    payload = decode_access_token(token)
    return payload if payload and payload.get("type") == "refresh" else None