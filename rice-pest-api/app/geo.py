"""Antique geofencing: which municipality and barangay a GPS point is in.

Reads app/data/antique_barangays.geojson (18 municipalities, 590 barangays,
PSGC codes; built by tools/build_antique_geojson.py from
faeldon/philippines-json-maps). The mobile app does the same lookup offline
from its own copy (mobile-app/assets/geo/), and the database has the same
data and rules in palay_locate() (supabase/01_schema.sql). Rules:

* The source maps are simplified one municipality at a time, so along
  municipal borders neighbouring polygons overlap slightly or leave thin
  gaps. Inside several polygons -> the one the point is deepest inside.
  Inside none but within MAX_GAP_M of one -> that one, as "nearest".
  Farther -> outside Antique.
* GPS accuracy (metres, from the phone) decides how sure the answer is:
  worse than MAX_ACCURACY_M -> "inaccurate" (ask the person to pick); a
  point closer to a boundary than the accuracy -> "near_boundary" (suggest,
  but ask to confirm).

Pure Python, no extra packages: 590 polygons answer in about a millisecond.
"""
import json
import math
import os
import re
import threading
import unicodedata
from typing import List, Optional

from fastapi import APIRouter, HTTPException, Query, Response

DATA_PATH = os.path.join(os.path.dirname(__file__), "data", "antique_barangays.geojson")
MAX_GAP_M = 300.0
MAX_ACCURACY_M = float(os.getenv("GEO_MAX_ACCURACY_M", "150"))
# Box around Antique incl. Caluya's islands, with a margin.
BBOX = (121.2, 10.35, 122.4, 12.3)

_M_PER_DEG_LAT = 110_574.0

_lock = threading.Lock()
_data: Optional[dict] = None


class _Barangay:
    __slots__ = ("psgc", "name", "municipality", "municipality_psgc", "polygons", "bbox")

    def __init__(self, props: dict, geometry: dict):
        self.psgc = props["psgc"]
        self.name = props["barangay"]
        self.municipality = props["municipality"]
        self.municipality_psgc = props["municipality_psgc"]
        polys = [geometry["coordinates"]] if geometry["type"] == "Polygon" else geometry["coordinates"]
        self.polygons = [[[(float(x), float(y)) for x, y in ring] for ring in poly] for poly in polys]
        xs = [x for poly in self.polygons for x, _ in poly[0]]
        ys = [y for poly in self.polygons for _, y in poly[0]]
        self.bbox = (min(xs), min(ys), max(xs), max(ys))

    def as_dict(self) -> dict:
        return {"psgc": self.psgc, "barangay": self.name, "municipality": self.municipality,
                "municipality_psgc": self.municipality_psgc}


def _norm(name: str) -> str:
    """Lowercase, accents and punctuation removed: "Egaña" == "egana", "Laua-an" == "laua an"."""
    s = unicodedata.normalize("NFKD", name or "").encode("ascii", "ignore").decode("ascii").lower()
    s = re.sub(r"\b(brgy|bgy|barangay)\b\.?", " ", s)
    return re.sub(r"[^a-z0-9]+", " ", s).strip()


def _load() -> dict:
    global _data
    if _data is not None:
        return _data
    with _lock:
        if _data is None:
            with open(DATA_PATH, encoding="utf-8") as f:
                fc = json.load(f)
            items = [_Barangay(ft["properties"], ft["geometry"]) for ft in fc["features"]]
            by_psgc = {b.psgc: b for b in items}
            municipalities: dict = {}
            for b in items:
                m = municipalities.setdefault(b.municipality_psgc, {
                    "psgc": b.municipality_psgc, "name": b.municipality, "barangays": []})
                m["barangays"].append(b)
            by_name = {(_norm(b.municipality), _norm(b.name)): b for b in items}
            mun_by_name = {_norm(m["name"]): m for m in municipalities.values()}
            # Older spellings people may have saved.
            mun_by_name.setdefault("san jose", mun_by_name.get(_norm("San Jose de Buenavista")))
            mun_by_name.setdefault("dao", mun_by_name.get(_norm("Tobias Fornier")))
            _data = {"items": items, "by_psgc": by_psgc, "municipalities": municipalities,
                     "by_name": by_name, "mun_by_name": mun_by_name, "metadata": fc.get("metadata", {})}
    return _data


# ---------------------------------------------------------------- geometry

def _point_in_ring(x: float, y: float, ring) -> bool:
    inside = False
    j = len(ring) - 1
    for i in range(len(ring)):
        xi, yi = ring[i]
        xj, yj = ring[j]
        if (yi > y) != (yj > y) and x < (xj - xi) * (y - yi) / (yj - yi) + xi:
            inside = not inside
        j = i
    return inside


def _covers(b: _Barangay, x: float, y: float) -> bool:
    for poly in b.polygons:
        if _point_in_ring(x, y, poly[0]) and not any(_point_in_ring(x, y, h) for h in poly[1:]):
            return True
    return False


def _edge_distance_m(b: _Barangay, lng: float, lat: float) -> float:
    """Metres from the point to the nearest edge of the barangay (local flat projection)."""
    kx = 111_320.0 * math.cos(math.radians(lat))
    best = math.inf
    for poly in b.polygons:
        for ring in poly:
            for (x1, y1), (x2, y2) in zip(ring, ring[1:]):
                ax, ay = (x1 - lng) * kx, (y1 - lat) * _M_PER_DEG_LAT
                bx, by = (x2 - lng) * kx, (y2 - lat) * _M_PER_DEG_LAT
                dx, dy = bx - ax, by - ay
                seg = dx * dx + dy * dy
                t = 0.0 if seg == 0 else max(0.0, min(1.0, -(ax * dx + ay * dy) / seg))
                px, py = ax + t * dx, ay + t * dy
                d = px * px + py * py
                if d < best:
                    best = d
    return math.sqrt(best)


def _near_bbox(b: _Barangay, x: float, y: float, margin_deg: float) -> bool:
    return (b.bbox[0] - margin_deg <= x <= b.bbox[2] + margin_deg
            and b.bbox[1] - margin_deg <= y <= b.bbox[3] + margin_deg)


# ---------------------------------------------------------------- lookups

def locate(lat: float, lng: float, accuracy_m: Optional[float] = None) -> dict:
    """{"status", "match", ... barangay fields ..., "distance_m", "depth_m",
    "accuracy_m", "alternatives"}.

    status: "inside" (sure), "near_boundary" (in a barangay, but the GPS
    error could put it in a neighbour), "nearest" (in a gap between map
    polygons, within MAX_GAP_M), "inaccurate" (GPS too imprecise to be
    sure; best guess included), "outside" (not in Antique) or "invalid"."""
    if lat is None or lng is None or not (-90 <= lat <= 90 and -180 <= lng <= 180) or (lat == 0 and lng == 0):
        return {"status": "invalid", "match": None, "accuracy_m": accuracy_m, "alternatives": []}
    out = {"accuracy_m": accuracy_m, "alternatives": []}
    if not (BBOX[0] <= lng <= BBOX[2] and BBOX[1] <= lat <= BBOX[3]):
        return {**out, "status": "outside", "match": None}

    data = _load()
    inside = [b for b in data["items"] if _near_bbox(b, lng, lat, 0) and _covers(b, lng, lat)]
    if inside:
        ranked = sorted(((_edge_distance_m(b, lng, lat), b) for b in inside), key=lambda t: (-t[0], t[1].psgc))
        depth, best = ranked[0]
        result = {**out, "match": "inside", **best.as_dict(), "distance_m": 0.0, "depth_m": round(depth, 1)}
        margin = max(accuracy_m or 0.0, 25.0)
        # Neighbours the GPS error could also put the person in.
        near = [b for b in data["items"]
                if b is not best and _near_bbox(b, lng, lat, margin / 90_000)
                and (_covers(b, lng, lat) or _edge_distance_m(b, lng, lat) <= margin)]
        result["alternatives"] = [b.as_dict() for b in near[:4]]
        if accuracy_m is not None and accuracy_m > MAX_ACCURACY_M:
            result["status"] = "inaccurate"
        elif accuracy_m is not None and depth < accuracy_m and near:
            result["status"] = "near_boundary"
        else:
            result["status"] = "inside"
        return result

    margin_deg = MAX_GAP_M / 90_000
    near = [(_edge_distance_m(b, lng, lat), b) for b in data["items"] if _near_bbox(b, lng, lat, margin_deg)]
    near = sorted((t for t in near if t[0] <= MAX_GAP_M), key=lambda t: (t[0], t[1].psgc))
    if near:
        dist, best = near[0]
        status = "inaccurate" if accuracy_m is not None and accuracy_m > MAX_ACCURACY_M else "nearest"
        return {**out, "status": status, "match": "nearest", **best.as_dict(), "distance_m": round(dist, 1),
                "depth_m": 0.0, "alternatives": [b.as_dict() for _, b in near[1:4]]}
    return {**out, "status": "outside", "match": None}


def find_barangay(psgc: Optional[str]) -> Optional[dict]:
    if not psgc:
        return None
    b = _load()["by_psgc"].get(str(psgc).strip())
    return b.as_dict() if b else None


def match_names(municipality: str, barangay: str) -> Optional[dict]:
    """The official barangay for names typed by a person (accents, case,
    "Brgy." and punctuation ignored), or None."""
    data = _load()
    m = data["mun_by_name"].get(_norm(municipality))
    if not m:
        return None
    b = data["by_name"].get((_norm(m["name"]), _norm(barangay)))
    return b.as_dict() if b else None


def municipality_psgc(name: str) -> Optional[str]:
    m = _load()["mun_by_name"].get(_norm(name))
    return m["psgc"] if m else None


def resolve_profile_location(municipality: str, barangay: str, barangay_psgc: Optional[str] = None) -> dict:
    """PSGC codes for a profile. A code sent by the app (from GPS or the
    picker) is used when it belongs to the chosen municipality; otherwise the
    typed names are matched. Unknown names keep None (still saved as typed)."""
    hit = find_barangay(barangay_psgc)
    if hit and _norm(hit["municipality"]) != _norm(municipality) \
            and municipality_psgc(municipality) != hit["municipality_psgc"]:
        hit = None
    hit = hit or match_names(municipality, barangay)
    if hit:
        return {"municipality_psgc": hit["municipality_psgc"], "barangay_psgc": hit["psgc"],
                "barangay": hit["barangay"], "municipality": hit["municipality"]}
    return {"municipality_psgc": municipality_psgc(municipality), "barangay_psgc": None,
            "barangay": None, "municipality": None}


def places() -> List[dict]:
    """[{psgc, name, barangays: [{psgc, name}]}] for pickers (no geometry)."""
    data = _load()
    return [
        {"psgc": m["psgc"], "name": m["name"],
         "barangays": [{"psgc": b.psgc, "name": b.name} for b in sorted(m["barangays"], key=lambda b: b.name)]}
        for m in sorted(data["municipalities"].values(), key=lambda m: m["name"])
    ]


# ---------------------------------------------------------------- HTTP

router = APIRouter(prefix="/geo", tags=["Geofencing"])


@router.get("/locate")
def locate_point(
    lat: float = Query(..., ge=-90, le=90),
    lng: float = Query(..., ge=-180, le=180),
    accuracy: Optional[float] = Query(None, ge=0, le=100000),
):
    """Barangay and municipality at a GPS point (public: no personal data)."""
    return locate(lat, lng, accuracy)


@router.get("/places")
def list_places(response: Response):
    """Municipalities and barangays of Antique with PSGC codes (no geometry)."""
    response.headers["Cache-Control"] = "public, max-age=86400"
    try:
        return {"metadata": _load()["metadata"], "municipalities": places()}
    except FileNotFoundError:
        raise HTTPException(status_code=503, detail="Location data is missing on the server.")
