"""Builds the Antique-only barangay GeoJSON used for GPS geofencing.

Source: https://github.com/faeldon/philippines-json-maps (latest/, PSGC
2026-3Q), folder latest/geojson/municities/medres/: one file per
municipality, "bgysubmuns-municity-<adm3_psgc>.0.01.json", holding that
municipality's barangay polygons. Antique has 18 municipalities
(adm3_psgc 600601000 ... 600618000) and 590 barangays.

    # download the 18 files (and, optionally, the municipality outlines
    # municities-provdist-600600000.0.01.json from latest/geojson/provdists/medres/)
    python tools/build_antique_geojson.py <download folder>

Writes (all identical copies of one FeatureCollection, plus the SQL seed):
    rice-pest-api/app/data/antique_barangays.geojson       (API lookups)
    mobile-app/assets/geo/antique_barangays.geojson        (offline lookups in the app)
    supabase/antique_barangays.geojson                     (reference copy)
    supabase/02_antique_locations.sql                      (provinces/municipalities/barangays seed)

Each feature keeps the barangay geometry and has these properties:
    psgc               10-digit barangay PSGC code (string, leading zero kept)
    barangay           barangay name as published
    municipality       municipality name as used by the apps (e.g. "San Jose de Buenavista")
    municipality_psgc  10-digit municipality PSGC code
    province, province_psgc, region_psgc

Coordinates are rounded to 5 decimals (about 1 m), which keeps the file
small without moving boundaries noticeably. The script refuses to write
anything if a check fails (wrong province, missing or extra municipality,
duplicate PSGC, barangay outside its municipality, ...).
"""
import json
import os
import re
import sys
from datetime import date

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

REGION_PSGC = 600000000      # Region VI (Western Visayas)
PROVINCE_PSGC = 600600000    # Antique
PSGC_RELEASE = "2026-3Q"
SOURCE_REPO = "faeldon/philippines-json-maps"
SOURCE_PATH = "latest/geojson/municities/medres"
DECIMALS = 5

# adm3_psgc -> municipality name as the apps store it (same list as
# mobile-app/lib/utils/places.dart and web-dashboard/src/lib.js).
MUNICIPALITIES = {
    600601000: "Anini-y",
    600602000: "Barbaza",
    600603000: "Belison",
    600604000: "Bugasong",
    600605000: "Caluya",
    600606000: "Culasi",
    600607000: "Tobias Fornier",
    600608000: "Hamtic",
    600609000: "Laua-an",
    600610000: "Libertad",
    600611000: "Pandan",
    600612000: "Patnongon",
    600613000: "San Jose de Buenavista",
    600614000: "San Remigio",
    600615000: "Sebaste",
    600616000: "Sibalom",
    600617000: "Tibiao",
    600618000: "Valderrama",
}
EXPECTED_TOTAL = 590
# Antique, with Caluya's islands (Semirara reaches 121.28 E, Sibay/Caluya
# 12.21 N), lies inside this box.
BBOX = (121.2, 10.35, 122.4, 12.3)  # min lon, min lat, max lon, max lat

FILE_RE = re.compile(r"^bgysubmuns-municity-(\d+)\.0\.01\.json$")


def psgc10(code: int) -> str:
    return f"{int(code):010d}"


def _round_ring(ring):
    out = []
    for x, y in ring:
        pt = [round(float(x), DECIMALS), round(float(y), DECIMALS)]
        if not out or out[-1] != pt:
            out.append(pt)
    if out and out[0] != out[-1]:
        out.append(list(out[0]))
    return out


def _round_polygon(rings):
    rings = [_round_ring(r) for r in rings]
    return [r for r in rings if len(r) >= 4]


def round_geometry(geom: dict) -> dict:
    if geom["type"] == "Polygon":
        return {"type": "Polygon", "coordinates": _round_polygon(geom["coordinates"])}
    if geom["type"] == "MultiPolygon":
        polys = [p for p in (_round_polygon(p) for p in geom["coordinates"]) if p]
        return {"type": "MultiPolygon", "coordinates": polys}
    raise ValueError(f"Unexpected geometry type {geom['type']}")


def _rings(geom):
    polys = [geom["coordinates"]] if geom["type"] == "Polygon" else geom["coordinates"]
    for poly in polys:
        yield from poly


def _point_in_ring(x, y, ring) -> bool:
    inside = False
    j = len(ring) - 1
    for i in range(len(ring)):
        xi, yi = ring[i]
        xj, yj = ring[j]
        if (yi > y) != (yj > y) and x < (xj - xi) * (y - yi) / ((yj - yi) or 1e-15) + xi:
            inside = not inside
        j = i
    return inside


def point_in_geometry(x, y, geom) -> bool:
    polys = [geom["coordinates"]] if geom["type"] == "Polygon" else geom["coordinates"]
    for poly in polys:
        if poly and _point_in_ring(x, y, poly[0]) and not any(_point_in_ring(x, y, h) for h in poly[1:]):
            return True
    return False


def interior_point(geom):
    """A point inside the geometry (shapely's representative point when
    available, else the centre of the largest ring's bounding box)."""
    try:
        from shapely.geometry import shape

        p = shape(geom).representative_point()
        return p.x, p.y
    except ImportError:
        ring = max(_rings(geom), key=len)
        xs, ys = [c[0] for c in ring], [c[1] for c in ring]
        return (min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2


def load_features(src: str):
    files = {}
    for name in os.listdir(src):
        m = FILE_RE.match(name)
        if m:
            files[int(m.group(1))] = os.path.join(src, name)
    missing = sorted(set(MUNICIPALITIES) - set(files))
    extra = sorted(c for c in files if c not in MUNICIPALITIES)
    if missing:
        raise SystemExit(f"Missing municipality files: {missing}")
    if extra:
        raise SystemExit(f"Files for municipalities outside Antique: {extra}")

    features = []
    for mun_code in sorted(MUNICIPALITIES):
        with open(files[mun_code], encoding="utf-8") as f:
            data = json.load(f)
        if data.get("type") != "FeatureCollection":
            raise SystemExit(f"{files[mun_code]}: not a FeatureCollection")
        for feat in data["features"]:
            p = feat["properties"]
            if p.get("adm1_psgc") != REGION_PSGC or p.get("adm2_psgc") != PROVINCE_PSGC:
                raise SystemExit(f"{p.get('adm4_psgc')}: not in Antique ({p})")
            if p.get("adm3_psgc") != mun_code:
                raise SystemExit(f"{p.get('adm4_psgc')}: municipality {p.get('adm3_psgc')} != file {mun_code}")
            if p.get("geo_level") not in ("Bgy", "SubMun"):
                raise SystemExit(f"{p.get('adm4_psgc')}: unexpected level {p.get('geo_level')}")
            code = int(p["adm4_psgc"])
            if code // 1000 != mun_code // 1000:
                raise SystemExit(f"{code}: PSGC does not belong to municipality {mun_code}")
            name = (p.get("adm4_en") or "").strip()
            if not name:
                raise SystemExit(f"{code}: no barangay name")
            if not feat.get("geometry"):
                raise SystemExit(f"{code} {name}: no geometry")
            geom = round_geometry(feat["geometry"])
            if not geom["coordinates"]:
                raise SystemExit(f"{code} {name}: geometry vanished after rounding")
            features.append({
                "type": "Feature",
                "properties": {
                    "psgc": psgc10(code),
                    "barangay": name,
                    "municipality": MUNICIPALITIES[mun_code],
                    "municipality_psgc": psgc10(mun_code),
                    "province": "Antique",
                    "province_psgc": psgc10(PROVINCE_PSGC),
                    "region_psgc": psgc10(REGION_PSGC),
                },
                "geometry": geom,
            })
    return features


def verify(features, outlines_path=None) -> dict:
    codes = [f["properties"]["psgc"] for f in features]
    if len(codes) != len(set(codes)):
        dupes = sorted({c for c in codes if codes.count(c) > 1})
        raise SystemExit(f"Duplicate barangay PSGC codes: {dupes}")
    if len(features) != EXPECTED_TOTAL:
        raise SystemExit(f"Expected {EXPECTED_TOTAL} barangays, found {len(features)}")
    per_mun = {}
    for f in features:
        per_mun.setdefault(f["properties"]["municipality"], 0)
        per_mun[f["properties"]["municipality"]] += 1
        for ring in _rings(f["geometry"]):
            for x, y in ring:
                if not (BBOX[0] <= x <= BBOX[2] and BBOX[1] <= y <= BBOX[3]):
                    raise SystemExit(f"{f['properties']['psgc']}: point {x},{y} outside Antique")
    if set(per_mun) != set(MUNICIPALITIES.values()):
        raise SystemExit("Municipality set mismatch")

    report = {"barangays": len(features), "municipalities": len(per_mun), "per_municipality": per_mun}
    try:
        from shapely.geometry import shape

        invalid = [f["properties"]["psgc"] for f in features if not shape(f["geometry"]).is_valid]
        report["invalid_geometries_after_rounding"] = invalid
    except ImportError:
        report["invalid_geometries_after_rounding"] = "not checked (shapely missing)"

    if outlines_path and os.path.exists(outlines_path):
        with open(outlines_path, encoding="utf-8") as f:
            outlines = {int(o["properties"]["adm3_psgc"]): o["geometry"] for o in json.load(f)["features"]}
        if set(outlines) != set(MUNICIPALITIES):
            raise SystemExit("Municipality outlines file does not list exactly the 18 municipalities")
        # Each barangay must lie mostly in its own municipality: catches
        # mislabelled barangays. (The municipal outlines are simplified
        # separately from the barangays, so border barangays overlap a
        # neighbour slightly; area shares are compared, not a single point.)
        misplaced = []
        try:
            from shapely.geometry import shape

            shapes = {c: shape(g) for c, g in outlines.items()}
            worst = 1.0
            for f in features:
                g = shape(f["geometry"])
                own = int(f["properties"]["municipality_psgc"])
                shares = {c: g.intersection(m).area / g.area for c, m in shapes.items()}
                best = max(shares, key=shares.get)
                worst = min(worst, shares[own])
                if best != own or shares[own] < 0.5:
                    misplaced.append((f["properties"]["psgc"], f["properties"]["barangay"], round(shares[own], 3)))
            report["containment_check"] = (
                f"every barangay lies mostly in its own municipality (lowest share {worst:.1%})"
            )
        except ImportError:
            for f in features:
                x, y = interior_point(f["geometry"])
                own = int(f["properties"]["municipality_psgc"])
                hits = [c for c, g in outlines.items() if point_in_geometry(x, y, g)]
                if not hits:
                    continue
                if own not in hits:
                    misplaced.append((f["properties"]["psgc"], f["properties"]["barangay"], hits))
            report["containment_check"] = "interior points checked (install shapely for the area check)"
        if misplaced:
            raise SystemExit(f"Barangays outside their municipality: {misplaced[:10]}")
    return report


def collection(features) -> dict:
    return {
        "type": "FeatureCollection",
        "name": "antique_barangays",
        "metadata": {
            "description": "Barangays of Antique, Philippines (18 municipalities) for GPS geofencing",
            "source": f"https://github.com/{SOURCE_REPO} ({SOURCE_PATH})",
            "psgc_release": PSGC_RELEASE,
            "built": date.today().isoformat(),
            "barangays": len(features),
            "municipalities": len(MUNICIPALITIES),
            "coordinate_decimals": DECIMALS,
            "crs": "EPSG:4326 (longitude, latitude)",
        },
        "features": features,
    }


def _sql_text(s: str) -> str:
    return "'" + s.replace("'", "''") + "'"


def seed_sql(features, outlines) -> str:
    lines = [
        "-- ==============================================================================",
        "-- Palay Patrol - Antique locations (province, 18 municipalities, 590 barangays)",
        "-- ==============================================================================",
        f"-- Generated by rice-pest-api/tools/build_antique_geojson.py from {SOURCE_REPO}",
        f"-- ({SOURCE_PATH}), PSGC {PSGC_RELEASE}. Do not edit by hand: re-run the script.",
        "--",
        "-- Run AFTER supabase/01_schema.sql (it creates the tables). Safe to run again:",
        "-- rows are upserted by PSGC code.",
        "-- ==============================================================================",
        "",
        "BEGIN;",
        "",
        "INSERT INTO provinces (psgc, name, region_psgc)",
        f"VALUES ({_sql_text(psgc10(PROVINCE_PSGC))}, 'Antique', {_sql_text(psgc10(REGION_PSGC))})",
        "ON CONFLICT (psgc) DO UPDATE SET name = EXCLUDED.name, region_psgc = EXCLUDED.region_psgc;",
        "",
        "INSERT INTO municipalities (psgc, name, province_psgc, geom) VALUES",
    ]
    rows = []
    for code, name in sorted(MUNICIPALITIES.items()):
        g = outlines.get(code)
        geom_sql = (
            f"ST_Multi(ST_SetSRID(ST_GeomFromGeoJSON({_sql_text(json.dumps(round_geometry(g), separators=(',', ':')))}), 4326))"
            if g else "NULL"
        )
        rows.append(f"  ({_sql_text(psgc10(code))}, {_sql_text(name)}, {_sql_text(psgc10(PROVINCE_PSGC))}, {geom_sql})")
    lines.append(",\n".join(rows))
    lines += [
        "ON CONFLICT (psgc) DO UPDATE SET name = EXCLUDED.name, province_psgc = EXCLUDED.province_psgc,",
        "    geom = COALESCE(EXCLUDED.geom, municipalities.geom);",
        "",
    ]
    for start in range(0, len(features), 50):
        chunk = features[start:start + 50]
        lines.append("INSERT INTO barangays (psgc, name, municipality_psgc, geom) VALUES")
        vals = []
        for f in chunk:
            p = f["properties"]
            gj = json.dumps(f["geometry"], separators=(",", ":"))
            vals.append(
                f"  ({_sql_text(p['psgc'])}, {_sql_text(p['barangay'])}, {_sql_text(p['municipality_psgc'])}, "
                f"ST_Multi(ST_SetSRID(ST_GeomFromGeoJSON({_sql_text(gj)}), 4326)))"
            )
        lines.append(",\n".join(vals))
        lines.append("ON CONFLICT (psgc) DO UPDATE SET name = EXCLUDED.name, "
                     "municipality_psgc = EXCLUDED.municipality_psgc, geom = EXCLUDED.geom;")
        lines.append("")
    lines += [
        "-- Self-check: the seed must leave exactly 18 municipalities and 590 barangays.",
        "DO $$",
        "BEGIN",
        "    IF (SELECT count(*) FROM municipalities WHERE province_psgc = '0600600000') <> 18",
        "       OR (SELECT count(*) FROM barangays b JOIN municipalities m ON m.psgc = b.municipality_psgc",
        "           WHERE m.province_psgc = '0600600000') <> 590 THEN",
        "        RAISE EXCEPTION 'Antique location seed is incomplete';",
        "    END IF;",
        "END",
        "$$;",
        "",
        "COMMIT;",
        "",
    ]
    return "\n".join(lines)


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit(__doc__)
    src = sys.argv[1]
    features = load_features(src)
    outlines_path = os.path.join(src, "municities-provdist-600600000.0.01.json")
    report = verify(features, outlines_path)
    outlines = {}
    if os.path.exists(outlines_path):
        with open(outlines_path, encoding="utf-8") as f:
            outlines = {int(o["properties"]["adm3_psgc"]): o["geometry"] for o in json.load(f)["features"]}

    text = json.dumps(collection(features), ensure_ascii=False, separators=(",", ":"))
    targets = [
        os.path.join(ROOT, "rice-pest-api", "app", "data", "antique_barangays.geojson"),
        os.path.join(ROOT, "mobile-app", "assets", "geo", "antique_barangays.geojson"),
        os.path.join(ROOT, "supabase", "antique_barangays.geojson"),
    ]
    for path in targets:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8", newline="\n") as f:
            f.write(text)
    with open(os.path.join(ROOT, "supabase", "02_antique_locations.sql"), "w", encoding="utf-8", newline="\n") as f:
        f.write(seed_sql(features, outlines))
    print(json.dumps({**report, "bytes": len(text.encode("utf-8")), "written": targets}, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
