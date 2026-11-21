import os
from datetime import date, datetime, timedelta, timezone

from dotenv import load_dotenv
from sqlalchemy import create_engine, event
from sqlalchemy.orm import declarative_base, sessionmaker
from sqlalchemy.pool import NullPool

load_dotenv()

# Dates (months, quarters, "today", date filters) follow the farmers' local time,
# whatever timezone the server or the database runs in.
APP_TIMEZONE = os.getenv("APP_TIMEZONE", "Asia/Manila")
try:
    from zoneinfo import ZoneInfo

    LOCAL_TZ = ZoneInfo(APP_TIMEZONE)
except Exception:  # no tz database (Windows without tzdata); the Philippines has no DST
    LOCAL_TZ = timezone(timedelta(hours=8))


def local_today() -> date:
    return datetime.now(LOCAL_TZ).date()


# On Vercel every request may run in a fresh, short-lived function instance,
# so keeping a connection pool open in the function is pointless and only
# exhausts Supabase's connection limit. Supabase's own pooler (Supavisor) does
# the pooling instead; each request opens and closes one pooled connection.
SERVERLESS = bool(os.getenv("VERCEL")) or os.getenv("DB_NULL_POOL", "").strip().lower() in {"1", "true", "yes", "on"}

DATABASE_URL = os.getenv("DATABASE_URL")
if not DATABASE_URL:
    raise RuntimeError(
        "DATABASE_URL is not set. Use the Supabase connection string "
        "(Transaction pooler on Vercel, or a direct PostgreSQL URL locally), e.g. "
        "postgresql://postgres.<project-ref>:<password>@aws-1-<region>.pooler.supabase.com:6543/postgres"
    )
# The original system used two databases (rice_pest_db2 for accounts,
# rice_pest_geo for observations). On Supabase both live in one database, so
# GEO_DATABASE_URL defaults to DATABASE_URL (users_fdw becomes a view).
GEO_DATABASE_URL = os.getenv("GEO_DATABASE_URL") or DATABASE_URL


def _normalize_url(url: str) -> str:
    # Supabase shows "postgres://" in some places; SQLAlchemy needs "postgresql://".
    if url.startswith("postgres://"):
        url = "postgresql://" + url[len("postgres://"):]
    return url


def _make_engine(url: str):
    url = _normalize_url(url)
    connect_args = {}
    if "supabase." in url and "sslmode=" not in url:
        connect_args["sslmode"] = "require"
    engine = create_engine(
        url,
        pool_pre_ping=not SERVERLESS,
        connect_args=connect_args,
        **({"poolclass": NullPool} if SERVERLESS else {}),
    )

    # Transaction pooling cannot guarantee session state survives between
    # transactions. The Supabase schema sets the database default timezone;
    # direct PostgreSQL connections can still set it per connection.
    if not SERVERLESS:
        @event.listens_for(engine, "connect")
        def _set_timezone(dbapi_conn, _record):
            cur = dbapi_conn.cursor()
            try:
                cur.execute("SET TIME ZONE %s", (APP_TIMEZONE,))
            finally:
                cur.close()
            dbapi_conn.commit()

    return engine


engine = _make_engine(DATABASE_URL)

SessionLocal = sessionmaker(
    autocommit=False,
    autoflush=False,
    bind=engine,
)

Base = declarative_base()


def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


geo_engine = engine if _normalize_url(GEO_DATABASE_URL) == _normalize_url(DATABASE_URL) else _make_engine(GEO_DATABASE_URL)
GeoSessionLocal = sessionmaker(bind=geo_engine, autocommit=False, autoflush=False)


def get_geo_db():
    db = GeoSessionLocal()
    try:
        yield db
    finally:
        db.close()
