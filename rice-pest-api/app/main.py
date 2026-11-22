import os
from contextlib import asynccontextmanager

from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse
from fastapi.middleware.cors import CORSMiddleware

# Flat structure: routers live directly inside app/
from . import auth
from . import sync_router
from . import analytics_router
from . import dashboard_router
from . import discovery
from . import guide
from . import geo
from . import activity


ON_VERCEL = bool(os.getenv("VERCEL"))


@asynccontextmanager
async def lifespan(_app: FastAPI):
    # Lets the mobile app find this machine on any LAN (see app/discovery.py).
    # Not on Vercel: there is no LAN and no UDP there; the apps are built with
    # the fixed HTTPS address instead (API_URL / VITE_API_URL).
    if not ON_VERCEL:
        discovery.start(
            api_port=int(os.getenv("PORT", "8000")),
            scheme=os.getenv("API_SCHEME", "http"),
        )
    yield


app = FastAPI(title="Crop Protection API", version="0.1.0", lifespan=lifespan)

APP_ENV = os.getenv("APP_ENV", "development").strip().lower()
HTTPS_ONLY = os.getenv("HTTPS_ONLY", str(APP_ENV == "production")).strip().lower() in {
    "1", "true", "yes", "on",
}

app.add_middleware(
    CORSMiddleware,
    allow_origins=[
        origin.strip()
        for origin in os.getenv(
            "CORS_ALLOWED_ORIGINS",
            "http://localhost:5173,https://rice-pest-dashboard.vercel.app",
        ).split(",")
        if origin.strip()
    ],
    # Production: CORS_ALLOWED_ORIGINS lists the deployed dashboard and mobile
    # web app; CORS_ALLOWED_ORIGIN_REGEX may add e.g. Vercel preview URLs.
    # Development: the dashboard opened from another device on the same Wi-Fi
    # (http://192.168.x.x:5173) and Flutter web's random localhost port.
    allow_origin_regex=(
        (os.getenv("CORS_ALLOWED_ORIGIN_REGEX", "").strip() or None)
        if APP_ENV == "production"
        else r"https?://(localhost|127\.0\.0\.1|192\.168\.\d{1,3}\.\d{1,3}|10\.\d{1,3}\.\d{1,3}\.\d{1,3})(:\d+)?"
    ),
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(auth.router)
app.include_router(sync_router.router)
app.include_router(analytics_router.router)
app.include_router(dashboard_router.router)
app.include_router(guide.router)
app.include_router(geo.router)


def _is_https(request: Request) -> bool:
    # Vercel terminates TLS and forwards the original scheme in this header.
    forwarded = request.headers.get("x-forwarded-proto", "").split(",")[0].strip().lower()
    return request.url.scheme == "https" or (ON_VERCEL and forwarded == "https")


@app.middleware("http")
async def activity_context(request: Request, call_next):
    """IP address, user agent and app of this request, for the activity log
    (app/activity.py). Never changes the response."""
    token = activity.begin_request(request)
    try:
        return await call_next(request)
    finally:
        activity.end_request(token)


@app.middleware("http")
async def transport_security_headers(request: Request, call_next):
    https = _is_https(request)
    if HTTPS_ONLY and not https:
        return JSONResponse(
            status_code=426,
            content={"detail": "HTTPS is required for this server."},
        )
    response = await call_next(request)
    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["X-Frame-Options"] = "DENY"
    response.headers["Referrer-Policy"] = "no-referrer"
    if https:
        response.headers["Strict-Transport-Security"] = "max-age=31536000; includeSubDomains"
    return response


@app.get("/")
def read_root():
    return {"message": "Rice Pest API is running."}