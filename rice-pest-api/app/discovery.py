"""LAN discovery: lets the mobile app find this server without an IP address.

The app broadcasts DISCOVERY_REQUEST on UDP DISCOVERY_PORT. Every interface
of this machine (Wi-Fi, Ethernet, a phone's hotspot, USB tethering) hears it,
and the reply goes back to the phone from the address it can reach, so
subnet size and router addressing don't matter.

The reply only says where to look; the app still checks that the host
serves this API (GET /openapi.json) before using it.
"""

import json
import logging
import os
import socket
import threading

DISCOVERY_PORT = int(os.getenv("DISCOVERY_PORT", "8001"))
DISCOVERY_REQUEST = b"PALAY_PATROL_DISCOVER_V1"
SERVICE_NAME = "palay-patrol"

log = logging.getLogger(__name__)
_started = False


def reply_payload(api_port: int, scheme: str) -> bytes:
    return json.dumps(
        {"service": SERVICE_NAME, "port": api_port, "scheme": scheme}
    ).encode("utf-8")


def _serve(sock: socket.socket, payload: bytes) -> None:
    while True:
        try:
            data, addr = sock.recvfrom(512)
        except OSError:
            return
        if data.strip() == DISCOVERY_REQUEST:
            try:
                sock.sendto(payload, addr)
            except OSError as exc:  # e.g. the phone left the network
                log.debug("discovery reply to %s failed: %s", addr, exc)


def start(api_port: int, scheme: str) -> bool:
    """Answers discovery broadcasts on a daemon thread. Safe to call twice."""
    global _started
    if _started or os.getenv("DISCOVERY_ENABLED", "true").strip().lower() in {"0", "false", "no", "off"}:
        return False
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
    try:
        sock.bind(("0.0.0.0", DISCOVERY_PORT))
    except OSError as exc:
        sock.close()
        log.warning("LAN discovery disabled: UDP port %s is busy (%s)", DISCOVERY_PORT, exc)
        return False
    threading.Thread(
        target=_serve,
        args=(sock, reply_payload(api_port, scheme)),
        name="lan-discovery",
        daemon=True,
    ).start()
    _started = True
    log.info("LAN discovery listening on UDP %s", DISCOVERY_PORT)
    return True
