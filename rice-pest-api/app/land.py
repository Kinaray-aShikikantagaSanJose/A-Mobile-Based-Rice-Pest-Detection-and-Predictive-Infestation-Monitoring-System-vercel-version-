"""Land type of the field where an observation was taken.

Definitions (see docs/MONITORING.md section 9; to be confirmed by the
agriculturist, who may change the elevation cut-off below):

  upland            - rice on sloping or high ground with naturally drained
                      soil; no bunds and no standing water; rain is the only
                      water source.
  rainfed_lowland   - bunded, level paddies that hold standing water for part
                      of the season, from rain or run-off only (no irrigation
                      system).
  irrigated_lowland - bunded, level paddies with an irrigation supply (canal,
                      NIA/communal system, pump) that keeps water in the field.

Elevation can only hint at upland vs lowland; it can't tell rainfed from
irrigated. The suggestion is a starting point the farmer or technician
always confirms or corrects.
"""
import json
import os
import urllib.parse
import urllib.request
from typing import Optional

LAND_TYPES = ("upland", "rainfed_lowland", "irrigated_lowland")
LAND_TYPE_LABELS = {
    "upland": "Upland",
    "rainfed_lowland": "Rainfed lowland",
    "irrigated_lowland": "Irrigated lowland",
}
NOT_RECORDED = "Not recorded"

# Fields at or above this elevation (metres above sea level) are suggested as
# upland. PROVISIONAL until an agriculturist confirms it (docs/MONITORING.md).
UPLAND_MIN_ELEVATION_M = float(os.getenv("UPLAND_MIN_ELEVATION_M", "100"))

# Free elevation service (Copernicus 90 m DEM), no API key.
ELEVATION_URL = os.getenv("ELEVATION_API_URL", "https://api.open-meteo.com/v1/elevation")
ELEVATION_TIMEOUT_S = 6


def label(key: Optional[str]) -> str:
    return LAND_TYPE_LABELS.get(key or "", NOT_RECORDED)


def lookup_elevation(lat: float, lng: float) -> Optional[float]:
    """Metres above sea level, or None when the service can't be reached."""
    query = urllib.parse.urlencode({"latitude": f"{lat:.5f}", "longitude": f"{lng:.5f}"})
    try:
        with urllib.request.urlopen(f"{ELEVATION_URL}?{query}", timeout=ELEVATION_TIMEOUT_S) as res:
            data = json.loads(res.read().decode("utf-8"))
        value = (data.get("elevation") or [None])[0]
        return float(value) if value is not None else None
    except Exception:
        return None


def suggest(elevation_m: Optional[float]) -> dict:
    """{"elevation_m", "suggested", "group", "reason"}. `suggested` is a land
    type key; for lowland it is None because elevation can't tell rainfed from
    irrigated (the person picks one of the two)."""
    if elevation_m is None:
        return {"elevation_m": None, "suggested": None, "group": None,
                "reason": "Elevation could not be looked up. Pick the land type yourself."}
    if elevation_m >= UPLAND_MIN_ELEVATION_M:
        return {"elevation_m": round(elevation_m), "suggested": "upland", "group": "upland",
                "reason": f"About {round(elevation_m)} m above sea level, which suggests upland. "
                          "Change it if the field is a flooded paddy."}
    return {"elevation_m": round(elevation_m), "suggested": None, "group": "lowland",
            "reason": f"About {round(elevation_m)} m above sea level, which suggests lowland. "
                      "Pick rainfed or irrigated depending on where the water comes from."}
