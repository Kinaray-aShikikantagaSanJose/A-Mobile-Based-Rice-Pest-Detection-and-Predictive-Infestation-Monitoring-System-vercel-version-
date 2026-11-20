"""Launch the API on every LAN interface.

Plain HTTP unless SSL_CERTFILE/SSL_KEYFILE are set (HTTPS is off for now).
The mobile app finds this machine by itself (see app/discovery.py), on
Wi-Fi, Ethernet or a hotspot, without typing an IP address.
"""

import os

from dotenv import load_dotenv
import uvicorn


def _flag(name: str, default: str = "") -> bool:
    return os.getenv(name, default).strip().lower() in {"1", "true", "yes", "on"}


def main() -> None:
    load_dotenv()
    production = os.getenv("APP_ENV", "development").strip().lower() == "production"
    https_only = _flag("HTTPS_ONLY", str(production))
    certfile = os.getenv("SSL_CERTFILE")
    keyfile = os.getenv("SSL_KEYFILE")
    behind_proxy = _flag("TLS_TERMINATED_BY_PROXY")

    if bool(certfile) != bool(keyfile):
        raise RuntimeError("Set both SSL_CERTFILE and SSL_KEYFILE to enable direct HTTPS.")
    if https_only and not (certfile and keyfile) and not behind_proxy:
        raise RuntimeError(
            "HTTPS_ONLY requires SSL_CERTFILE/SSL_KEYFILE or TLS_TERMINATED_BY_PROXY=true."
        )

    port = int(os.getenv("PORT", "8000"))
    scheme = "https" if (certfile and keyfile) or behind_proxy else "http"
    # Read by app.main at startup for the LAN discovery reply.
    os.environ["PORT"] = str(port)
    os.environ["API_SCHEME"] = scheme

    options = {
        "app": "app.main:app",
        "host": "0.0.0.0",
        "port": port,
        "proxy_headers": behind_proxy,
        "forwarded_allow_ips": os.getenv("FORWARDED_ALLOW_IPS", "127.0.0.1"),
    }
    if certfile and keyfile:
        options["ssl_certfile"] = certfile
        options["ssl_keyfile"] = keyfile
    print(f"Palay Patrol API: {scheme}://0.0.0.0:{port} (LAN discovery on UDP "
          f"{os.getenv('DISCOVERY_PORT', '8001')})")
    uvicorn.run(**options)


if __name__ == "__main__":
    main()
