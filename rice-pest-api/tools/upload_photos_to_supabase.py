"""Copies existing photos from a local uploads/ folder into Supabase Storage.

Run once on your own computer after creating the Supabase project and
running supabase/01_schema.sql (which creates the "scans" and "avatars"
buckets). The files keep their names, which are what the database rows
(scans.image_filename, users.avatar_path) refer to, so move the database rows
too (see DEPLOY-VERCEL.md, "Move the existing data").

    set SUPABASE_URL=https://<project-ref>.supabase.co
    set SUPABASE_SERVICE_ROLE_KEY=<service_role key>
    python tools/upload_photos_to_supabase.py "C:\path\to\rice-pest-api\uploads"

Only reads the source folder; never changes or deletes it. Safe to re-run
(existing objects are overwritten with the same bytes).
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from app import storage  # noqa: E402


def upload_dir(folder: str, bucket: str) -> int:
    if not os.path.isdir(folder):
        return 0
    count = 0
    for name in sorted(os.listdir(folder)):
        path = os.path.join(folder, name)
        if not (os.path.isfile(path) and name.lower().endswith(".jpg")):
            continue
        with open(path, "rb") as f:
            storage.put(bucket, name, f.read())
        count += 1
        print(f"{bucket}/{name}")
    return count


def main() -> None:
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    if not storage.using_supabase():
        sys.exit("Set SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY first.")
    src = sys.argv[1]
    scans = upload_dir(src, storage.SCANS)
    avatars = upload_dir(os.path.join(src, "avatars"), storage.AVATARS)
    print(f"Done: {scans} observation photo(s), {avatars} profile picture(s).")


if __name__ == "__main__":
    main()
