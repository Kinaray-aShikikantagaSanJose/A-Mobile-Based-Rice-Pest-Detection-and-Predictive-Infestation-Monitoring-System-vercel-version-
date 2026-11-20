# Palay Patrol API

> **Vercel + Supabase copy.** For hosting, follow `../DEPLOY-VERCEL.md`.
> For local runs install `requirements-local.txt` (adds uvicorn); leave
> `SUPABASE_URL` empty to keep photos in `uploads/`.

FastAPI service for authentication, observation synchronization, analytics,
and technician/agriculturist workflows. PostgreSQL/PostGIS connection
settings are read from `rice-pest-api/.env`; do not commit that file.

## Install and run locally

```powershell
cd rice-pest-api
python -m venv venv
.\venv\Scripts\Activate.ps1
pip install -r requirements-local.txt
Copy-Item env.example .env
# Set DATABASE_URL, GEO_DATABASE_URL, and a random JWT_SECRET_KEY in .env.
python run_server.py
```

`run_server.py` serves HTTP on `0.0.0.0:8000` and answers LAN discovery
broadcasts on UDP 8001 (`app/discovery.py`). The mobile app finds it on
Wi-Fi, Ethernet (same router), either device's hotspot or USB tethering with
no IP address to enter: it broadcasts on every network it is on, falls back
to probing its /24 subnet, and only accepts a host whose `/openapi.json` is
this API. Allow inbound TCP 8000 and UDP 8001 for Python in the host firewall.

The phone and the server must share a network that lets devices talk to each
other. Campus/guest Wi-Fi with client isolation blocks that; use a phone
hotspot instead.

Check the API on the server computer at `http://localhost:8000/docs`. The web
dashboard's dev server forwards `/api` to the API.

## HTTPS deployment

Set `APP_ENV=production` (or `HTTPS_ONLY=true`) and choose one:

* Direct TLS: set both `SSL_CERTFILE` and `SSL_KEYFILE` to a trusted
  certificate and private key. Start with `python run_server.py`.
* TLS-terminating reverse proxy: set `TLS_TERMINATED_BY_PROXY=true` and
  `FORWARDED_ALLOW_IPS` to the proxy's trusted source address(es). The proxy
  must forward `X-Forwarded-Proto: https` and serve a valid trusted certificate.

The server refuses production startup without TLS configuration, rejects
plain HTTP when HTTPS is required, and returns HSTS on HTTPS responses. Never
disable certificate verification or expose the development HTTP listener to
the public internet.

Or build the app against a stable HTTPS API hostname:

```powershell
flutter build apk --release --dart-define=API_URL=https://api.example.org
```

HTTPS is currently off for local use: the app tries HTTPS first and falls
back to HTTP. Build with `--dart-define=API_REQUIRE_HTTPS=true` to refuse HTTP.

## Authentication and prediction

Passwords are stored with bcrypt (passwords over 72 UTF-8 bytes are rejected).
Access and refresh tokens are signed JWTs; role and approval are rechecked
against the database for protected operations. Generate `JWT_SECRET_KEY` with
a cryptographically secure random value of at least 32 characters.

`/analytics/trends/prediction` is limited to the authorized staff coverage
area. It forecasts weekly validated pest counts with scikit-learn
`LinearRegression` once at least four weeks contain observations; sparse data
uses a historical-mean baseline.
