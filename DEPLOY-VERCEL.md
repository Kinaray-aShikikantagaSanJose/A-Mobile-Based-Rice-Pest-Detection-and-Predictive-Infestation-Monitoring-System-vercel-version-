# Palay Patrol on Vercel + Supabase

This folder is a copy of the capstone prepared for hosting. Three Vercel
projects are created from the same Git repository, each with its own
**Root Directory**:

| Vercel project | Root Directory  | What it is                                   |
|----------------|-----------------|----------------------------------------------|
| API            | `rice-pest-api` | FastAPI backend as a Python serverless function |
| Dashboard      | `web-dashboard` | React/Vite web dashboard (static site)      |
| Mobile web app | `mobile-app`    | Flutter app built for the web (static site) |

Supabase provides the PostgreSQL database (with PostGIS) and Storage for
photos. The Android APK is not hosted by Vercel; you build it pointing at the
deployed API (see step 5).

Order: Supabase → API → Dashboard → Mobile web app → update the API's CORS.

---

## 1. Supabase

1. Create a project at supabase.com. **Region: Southeast Asia (Singapore)**,
   the same region as the API (`rice-pest-api/vercel.json` uses `sin1`).
   Save the database password.
2. **SQL Editor → New query**: paste and run `supabase/01_schema.sql`.
   It creates every table (accounts and observations together in one
   database), the `users_fdw` view, row level security, and the two private
   storage buckets `scans` and `avatars`.
3. Then either:
   * **Fresh start:** run `SQL/01_level_criteria_data.sql` and
     `SQL/02_treatment_library_data.sql` (reference data; needed). Demo data:
     `SQL/03_...` and `SQL/04_...` (optional; 04 is kept out of Git).
   * **Keep your current data:** see "Move the existing data" below instead.
4. Collect, for the API:
   * **Connect** (top bar) → **Shared Pooler** → **Transaction** connection
     string (port `6543`) → `DATABASE_URL`. Percent-encode any special
     characters in the database password before inserting it.
   * **Project Settings → API**: Project URL → `SUPABASE_URL`;
     `service_role` secret → `SUPABASE_SERVICE_ROLE_KEY`.

## 2. API (`rice-pest-api`)

1. Vercel → Add New → Project → import the repository → **Root Directory:
   `rice-pest-api`**, Framework Preset: Other. Leave build settings empty.
2. Environment Variables (all listed in `rice-pest-api/env.example`):

   | Name | Value |
   |------|-------|
   | `DATABASE_URL` | Supabase shared transaction pooler URI (port `6543`) |
   | `SUPABASE_URL` | `https://<ref>.supabase.co` |
   | `SUPABASE_SERVICE_ROLE_KEY` | service_role key |
   | `JWT_SECRET_KEY` | 64 random hex chars (`python -c "import secrets;print(secrets.token_hex(32))"`) |
   | `APP_ENV` | `production` |
   | `HTTPS_ONLY` | `true` |
   | `CORS_ALLOWED_ORIGINS` | dashboard and mobile web URLs, comma-separated (fill in after steps 3-4) |
   | `SMTP_USERNAME` / `SMTP_PASSWORD` | Gmail address + App Password (OTP emails) |
   | `REQUIRE_ACCOUNT_APPROVAL`, `APP_TIMEZONE` | as before (`false`, `Asia/Manila`) |

3. Deploy, then open `https://<api>.vercel.app/docs`: the Swagger page
   should load. `/` answers `{"message": "Rice Pest API is running."}`.

## 3. Web dashboard (`web-dashboard`)

1. New Vercel project, same repository, **Root Directory: `web-dashboard`**
   (Vite is detected; `vercel.json` sets the rest).
2. Environment Variable `VITE_API_URL` = `https://<api>.vercel.app`
   (no trailing slash). It is baked in at build time: redeploy after changing it.

## 4. Mobile web app (`mobile-app`)

1. New Vercel project, **Root Directory: `mobile-app`**. `vercel.json`
   downloads Flutter during the build and runs `flutter build web`.
2. Environment Variable `API_URL` = `https://<api>.vercel.app`.
3. Details and limits: `mobile-app/README-VERCEL.md`.

## 5. Finish

* Put the dashboard and mobile web URLs in the API's `CORS_ALLOWED_ORIGINS`
  (e.g. `https://palay-dashboard.vercel.app,https://palay-app.vercel.app`)
  and **redeploy the API**. Until then browsers block the requests.
* Android APK against the deployed API (on your computer):
  `flutter build apk --release --dart-define=API_URL=https://<api>.vercel.app`
  (cap Gradle's memory as usual). The APK can be shared directly, or put
  in `web-dashboard/public/` to be downloadable from the dashboard's site.

---

## Move the existing data (optional)

Your current data is in two local databases (`rice_pest_db2`, `rice_pest_geo`)
and photos in `rice-pest-api/uploads/`. Run `supabase/01_schema.sql` first and
**skip** the SQL/01-04 seed files (the dump brings that data along).

PowerShell, on the computer that has the local databases (PostgreSQL 18 tools):

```powershell
$pg = "C:\Program Files\PostgreSQL\18\bin"
& "$pg\pg_dump.exe" --data-only --no-owner --no-privileges -t users -t otps `
    -d "postgresql://postgres@localhost:5432/rice_pest_db2" -f accounts.sql
& "$pg\pg_dump.exe" --data-only --no-owner --no-privileges `
    -t scans -t treatment_library -t treatments -t level_criteria -t scan_reviews -t notifications `
    -d "postgresql://postgres@localhost:5432/rice_pest_geo" -f field.sql

$supa = "<Supabase session pooler or direct PostgreSQL URI>"
& "$pg\psql.exe" $supa -v ON_ERROR_STOP=1 -c "SET session_replication_role = replica" -f accounts.sql -f field.sql
```

(`session_replication_role = replica` lets the rows load regardless of
foreign-key order; scans and treatments reference each other.) If psql stops
at `unrecognized configuration parameter`, delete that `SET` line at the top of
the .sql file and run it again. Use a session pooler or direct connection for
this migration command; do not use the transaction pooler because it does not
preserve session-level settings such as `session_replication_role`.

Photos (reads the original folder only, never changes it):

```powershell
cd rice-pest-api
pip install -r requirements.txt
$env:SUPABASE_URL = "https://<ref>.supabase.co"
$env:SUPABASE_SERVICE_ROLE_KEY = "<service_role key>"
python tools\upload_photos_to_supabase.py "C:\Users\user\Downloads\CAPSTONE (MAIN)\rice-pest-api\uploads"
```

---

## What changed compared with the original

API (`rice-pest-api`)
* `app/storage.py` (new): photos and profile pictures go to Supabase Storage
  (private buckets; the API still checks permissions and serves the bytes,
  so app and dashboard URLs are unchanged). Without `SUPABASE_URL` it falls
  back to the local `uploads/` folder for local development.
* `app/database.py`: one Supabase database (`GEO_DATABASE_URL` now defaults
  to `DATABASE_URL`), no connection pool on Vercel, SSL, timezone from the
  database default on Vercel (the schema sets `Asia/Manila`) and via `SET` for
  direct local connections.
* `app/main.py`: no LAN discovery on Vercel; HTTPS detected from Vercel's
  proxy header; optional `CORS_ALLOWED_ORIGIN_REGEX`.
* `app/sync_router.py`, `app/avatars.py`, `app/auth.py`, `app/reanalyze.py`,
  `app/detector.py`: read/write photos through `app/storage.py`.
* `app/trend_service.py`: the same least-squares line computed with numpy
  instead of scikit-learn (identical predictions; scikit-learn + SciPy would
  push the function past Vercel's size limit).
* New: `api/index.py`, `vercel.json`, `.vercelignore`, `.python-version`,
  `requirements-local.txt` (adds uvicorn for `python run_server.py`),
  `tools/upload_photos_to_supabase.py`. `env.example` rewritten.

Database: `supabase/01_schema.sql` (new; merges both databases and all
migrations up to 011). `SQL/01_level_criteria_data.sql`: fixed the duplicate
`rice_bug` row that was meant to be `rice_stem_borer` (the file failed on a
fresh database).

Dashboard: `vercel.json`, `.env.example`, and a comment in `src/api.js`.

Root `.gitignore`: commits `rice-pest-api/models/rice_pest.onnx` (the API
needs it on Vercel) and the `rice-pest-api/sql/` files; ignores `.vercel/`.

---

## Limits to know about

* **Uploads are capped at 4.5 MB per request** (Vercel). The app's camera
  photos are about 0.3 MB and gallery picks are reduced to 2048 px first, so
  this only matters for unusual files; Vercel then answers 413.
* **No LAN discovery.** On Vercel there is no local network or UDP; the apps
  use the fixed HTTPS address they are built with.
* **Cold starts:** the first request after a few idle minutes takes a few
  seconds longer (Python start + loading the 12 MB detection model).
* **Function time limit:** 60 s per request (set in `vercel.json`); uploads
  with detection take a few seconds.
* **Email:** OTP codes are sent through Gmail SMTP from Vercel. This
  normally works; if Gmail blocks sign-ins from Vercel's servers, switch to an
  email API (e.g. Resend, SendGrid).
* **`python -m app.reanalyze`** is a command-line tool: run it on your own
  computer with the Supabase variables set, not on Vercel.
* **Supabase free tier:** 500 MB database, 1 GB storage, and the project
  pauses after a week without activity (open the dashboard to resume).
* **Single region:** keep the Supabase project and the Vercel function in
  the same region (Singapore) or every query crosses the Pacific.
