"""Profile pictures. Stored as square JPEGs in the "avatars" storage bucket
(Supabase Storage, or uploads/avatars/ locally; see app/storage.py), the file
name kept in users.avatar_path (sql/010_profiles.sql).

The column is read with plain SQL, not through the User model: until the
migration runs, every account still signs in normally and only pictures are
unavailable (the API answers 503 for uploads)."""
import io
import logging
import os
import secrets
import time
from typing import Dict, Optional

from fastapi import HTTPException, UploadFile
from PIL import Image, ImageOps, UnidentifiedImageError
from sqlalchemy import text
from sqlalchemy.orm import Session

from . import storage

log = logging.getLogger(__name__)

MAX_AVATAR_BYTES = 8 * 1024 * 1024
SIDE = 512

_enabled: Optional[bool] = None
_checked_at = 0.0


def enabled(db: Session) -> bool:
    """True once users.avatar_path exists. A missing column is checked again
    every minute, so running the migration works without a restart."""
    global _enabled, _checked_at
    if _enabled or (_enabled is False and time.monotonic() - _checked_at < 60):
        return bool(_enabled)
    try:
        _enabled = db.execute(
            text(
                "SELECT 1 FROM information_schema.columns "
                "WHERE table_name = 'users' AND column_name = 'avatar_path'"
            )
        ).first() is not None
    except Exception as e:  # never break sign-in over a picture
        log.warning("Could not check users.avatar_path: %s", e)
        db.rollback()
        _enabled = False
    _checked_at = time.monotonic()
    if not _enabled:
        log.warning("users.avatar_path is missing: run sql/010_profiles.sql to enable profile pictures.")
    return bool(_enabled)


def url_for(user_id: int, filename: Optional[str]) -> Optional[str]:
    """Path (no host) the apps load the picture from; changes with each upload."""
    if not filename:
        return None
    return f"/auth/avatar/{user_id}?v={os.path.splitext(filename)[0].rsplit('_', 1)[-1]}"


def filename_of(db: Session, user_id: int) -> Optional[str]:
    if not enabled(db):
        return None
    return db.execute(text("SELECT avatar_path FROM users WHERE id = :i"), {"i": user_id}).scalar()


def all_filenames(db: Session) -> Dict[int, str]:
    if not enabled(db):
        return {}
    rows = db.execute(text("SELECT id, avatar_path FROM users WHERE avatar_path IS NOT NULL")).fetchall()
    return {r.id: r.avatar_path for r in rows}


def read(filename: Optional[str]) -> Optional[bytes]:
    """The picture's JPEG bytes, or None if it's missing."""
    return storage.get(storage.AVATARS, filename)


def _delete_file(filename: Optional[str]) -> None:
    storage.delete(storage.AVATARS, filename)


def save(db: Session, user_id: int, image: UploadFile) -> str:
    """Crops the upload to a square, stores it and returns the new file name.
    The caller commits."""
    if not enabled(db):
        raise HTTPException(status_code=503, detail="Profile pictures aren't set up on the server yet (run sql/010_profiles.sql).")
    raw = image.file.read(MAX_AVATAR_BYTES + 1)
    if len(raw) > MAX_AVATAR_BYTES:
        raise HTTPException(status_code=413, detail="That picture is too large (8 MB at most).")
    try:
        img = Image.open(io.BytesIO(raw))
        img = ImageOps.exif_transpose(img).convert("RGB")
    except (UnidentifiedImageError, OSError, ValueError):
        raise HTTPException(status_code=400, detail="That file isn't a picture. Choose a JPG or PNG photo.")
    img = ImageOps.fit(img, (SIDE, SIDE), Image.Resampling.LANCZOS)
    filename = f"{user_id}_{secrets.token_hex(6)}.jpg"
    out = io.BytesIO()
    img.save(out, "JPEG", quality=88)
    try:
        storage.put(storage.AVATARS, filename, out.getvalue())
    except Exception as e:
        log.warning("Could not store avatar %s: %s", filename, e)
        raise HTTPException(status_code=503, detail="The picture could not be stored right now. Please try again.")
    old = filename_of(db, user_id)
    db.execute(text("UPDATE users SET avatar_path = :f WHERE id = :i"), {"f": filename, "i": user_id})
    _delete_file(old)
    return filename


def remove(db: Session, user_id: int) -> None:
    """Clears the picture (the caller commits)."""
    if not enabled(db):
        return
    old = filename_of(db, user_id)
    db.execute(text("UPDATE users SET avatar_path = NULL WHERE id = :i"), {"i": user_id})
    _delete_file(old)


def delete_files_of(filename: Optional[str]) -> None:
    """For a deleted account."""
    _delete_file(filename)
