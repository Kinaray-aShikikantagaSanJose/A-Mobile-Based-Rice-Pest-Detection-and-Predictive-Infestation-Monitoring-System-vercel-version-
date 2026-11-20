"""Photo storage: Supabase Storage when configured, else the local uploads/ folder.

Vercel functions have a read-only filesystem that is wiped between requests,
so observation photos and profile pictures go to two private Supabase Storage
buckets (created by supabase/01_schema.sql):

    scans    observation photos, key = scans.image_filename
    avatars  profile pictures,   key = users.avatar_path

Set SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY to use Supabase. Without them
(local development) files are kept in uploads/ and uploads/avatars/ like the
original server. The buckets are private: the API reads the bytes with the
service key and serves them after its own permission checks, so the apps keep
calling the same endpoints.
"""
import logging
import os
import re
import urllib.error
import urllib.parse
import urllib.request
from typing import Optional

log = logging.getLogger(__name__)

SCANS = "scans"
AVATARS = "avatars"

SUPABASE_URL = os.getenv("SUPABASE_URL", "").strip().rstrip("/")
SUPABASE_KEY = os.getenv("SUPABASE_SERVICE_ROLE_KEY", "").strip()
TIMEOUT_S = float(os.getenv("STORAGE_TIMEOUT_S", "20"))

_ROOT = os.path.join(os.path.dirname(os.path.dirname(__file__)), "uploads")
_LOCAL_DIRS = {SCANS: _ROOT, AVATARS: os.path.join(_ROOT, "avatars")}
# Our own generated names only: no slashes, no "..".
_SAFE_KEY = re.compile(r"^[A-Za-z0-9_.-]{1,200}$")


def using_supabase() -> bool:
    return bool(SUPABASE_URL and SUPABASE_KEY)


def _check(bucket: str, key: str) -> bool:
    return bucket in _LOCAL_DIRS and bool(key) and bool(_SAFE_KEY.match(key)) and ".." not in key


def _url(bucket: str, key: str) -> str:
    return f"{SUPABASE_URL}/storage/v1/object/{bucket}/{urllib.parse.quote(key)}"


def _request(method: str, bucket: str, key: str, data: Optional[bytes] = None,
             content_type: Optional[str] = None) -> Optional[bytes]:
    headers = {"Authorization": f"Bearer {SUPABASE_KEY}", "apikey": SUPABASE_KEY}
    if content_type:
        headers["Content-Type"] = content_type
        headers["x-upsert"] = "true"
    req = urllib.request.Request(_url(bucket, key), data=data, method=method, headers=headers)
    with urllib.request.urlopen(req, timeout=TIMEOUT_S) as res:
        return res.read()


def put(bucket: str, key: str, data: bytes, content_type: str = "image/jpeg") -> None:
    """Stores the file. Raises on failure (the caller turns it into an error reply)."""
    if not _check(bucket, key):
        raise ValueError(f"Unsafe storage key: {key!r}")
    if using_supabase():
        _request("POST", bucket, key, data, content_type)
        return
    folder = _LOCAL_DIRS[bucket]
    os.makedirs(folder, exist_ok=True)
    with open(os.path.join(folder, key), "wb") as f:
        f.write(data)


def get(bucket: str, key: Optional[str]) -> Optional[bytes]:
    """The file's bytes, or None if it doesn't exist (or the key is unsafe)."""
    if not key or not _check(bucket, key):
        return None
    if using_supabase():
        try:
            return _request("GET", bucket, key)
        except urllib.error.HTTPError as e:
            if e.code not in (400, 404):
                log.warning("Storage read %s/%s failed: HTTP %s", bucket, key, e.code)
            return None
        except Exception as e:  # network trouble: same as missing, logged
            log.warning("Storage read %s/%s failed: %s", bucket, key, e)
            return None
    path = os.path.join(_LOCAL_DIRS[bucket], key)
    if not os.path.isfile(path):
        return None
    with open(path, "rb") as f:
        return f.read()


def delete(bucket: str, key: Optional[str]) -> None:
    """Removes the file; never raises (a leftover file is harmless)."""
    if not key or not _check(bucket, key):
        return
    try:
        if using_supabase():
            _request("DELETE", bucket, key)
        else:
            os.remove(os.path.join(_LOCAL_DIRS[bucket], key))
    except Exception as e:
        log.warning("Could not delete %s/%s: %s", bucket, key, e)
