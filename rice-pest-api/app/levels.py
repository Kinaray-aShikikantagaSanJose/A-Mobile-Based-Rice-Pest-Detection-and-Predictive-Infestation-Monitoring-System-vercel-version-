"""Suggested infestation level for the technician to confirm or override.

The suggestion is never computed from the pest count alone: it combines the
pest, the crop stage, the count (only when the photo was countable) and the
damage indicators the technician saw. The confirmed level is always the
technician's (or agriculturist's) decision, stored on the observation.
"""
from typing import Iterable, Optional

from sqlalchemy import text
from sqlalchemy.orm import Session

LEVELS = ("LOW", "MEDIUM", "HIGH")
CROP_STAGES = ("Vegetative", "Reproductive", "Ripening")
SUPPORTED_PESTS = ("brown_planthopper", "green_leafhopper", "rice_bug", "rice_stem_borer")
OTHER_PEST = "other"  # outside the four the model knows

# Visible damage a technician can tick during review, per pest.
DAMAGE_INDICATORS = {
    "brown_planthopper": [
        "Hopperburn (yellowing and drying patches)",
        "Honeydew or sooty mold at the plant base",
        "Plants wilting or lodging",
    ],
    "green_leafhopper": [
        "Yellow-orange leaf discoloration (possible tungro)",
        "Stunted plants",
        "Reduced tillering",
    ],
    "rice_bug": [
        "Empty or unfilled grains",
        "Brown spots on grains",
        "Offensive rice-bug odor in the field",
    ],
    "rice_stem_borer": [
        "Deadhearts (dead central tiller)",
        "Whiteheads (empty white panicles)",
        "Bore holes or frass on stems",
    ],
    OTHER_PEST: [
        "Visible feeding damage on leaves",
        "Plants wilting or dying",
        "Damage spread across much of the field",
    ],
}


def indicators_for(pest: Optional[str]) -> list:
    return DAMAGE_INDICATORS.get(pest or OTHER_PEST, DAMAGE_INDICATORS[OTHER_PEST])


def load_thresholds(db: Session) -> dict:
    """{(pest, stage): row}. Stage '' means 'any stage' for that pest."""
    rows = db.execute(
        text(
            "SELECT id, pest, crop_stage, medium_from, high_from, updated_by, updated_at "
            "FROM level_criteria ORDER BY pest, crop_stage"
        )
    ).fetchall()
    return {
        (r.pest, r.crop_stage): {
            "id": r.id,
            "pest": r.pest,
            "crop_stage": r.crop_stage,
            "medium_from": r.medium_from,
            "high_from": r.high_from,
            "updated_by": r.updated_by,
            "updated_at": r.updated_at.isoformat() if r.updated_at else None,
        }
        for r in rows
    }


def _bump(level: str, steps: int) -> str:
    return LEVELS[min(LEVELS.index(level) + steps, len(LEVELS) - 1)]


def suggest(
    thresholds: dict,
    pest: Optional[str],
    crop_stage: str,
    count: Optional[int],
    indicators: Iterable[str],
) -> dict:
    """Returns {"level", "reasons"} so the technician sees why."""
    reasons = []
    row = thresholds.get((pest, crop_stage)) or thresholds.get((pest, ""))
    if count is not None and row:
        if count >= row["high_from"]:
            base = "HIGH"
        elif count >= row["medium_from"]:
            base = "MEDIUM"
        else:
            base = "LOW"
        stage = crop_stage or "any stage"
        reasons.append(
            f"Count {count}: {base} for {stage} (MEDIUM from {row['medium_from']:g}, HIGH from {row['high_from']:g})"
        )
    else:
        base = "LOW"
        if count is None:
            reasons.append("No reliable count, so the suggestion starts at LOW and rests on the damage you saw")
        else:
            reasons.append("No thresholds set for this pest, so the suggestion starts at LOW")

    known = set(indicators_for(pest))
    seen = [i for i in indicators if i in known]
    level = _bump(base, len(seen))
    for i in seen:
        reasons.append(f"+1 level: {i}")
    return {"level": level, "reasons": reasons}
