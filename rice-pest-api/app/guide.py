"""'What to look for': the pest and symptom guide shown in the mobile app and
on the dashboard. This file is the only copy of the guide's content; both
apps fetch it from GET /guide. It must match docs/model-classes-and-guide.md.

Example photos live in guide_photos/<key>.jpg (or .png). A missing photo
shows a placeholder in the apps until the group adds one.
"""
import os

from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import FileResponse

from .access import EVERYONE, require_role
from .detector import CLASSES, PEST_NAMES

router = APIRouter(prefix="/guide", tags=["Guide"])

PHOTO_DIR = os.path.join(os.path.dirname(os.path.dirname(__file__)), "guide_photos")
_PHOTO_TYPES = {".jpg": "image/jpeg", ".jpeg": "image/jpeg", ".png": "image/png"}

# The training labels (data.yaml) for each pest key the API uses.
MODEL_LABELS = {
    "brown_planthopper": "brown-planthopper",
    "green_leafhopper": "green-leafhopper",
    "rice_bug": "rice-bug",
    "rice_stem_borer": "stem-borer",
}

# Crop stages use the app's three stages: Vegetative (seedling to tillering),
# Reproductive (booting to flowering), Ripening (grain filling to harvest).
PESTS = [
    {
        "key": "brown_planthopper",
        "signs": [
            "Small brown insects, 3-4 mm, packed at the base of the plants near the water.",
            "Long-winged and short-winged adults; young ones (nymphs) are creamy white to light brown.",
            "They move sideways or drop into the water when the plant is tapped.",
        ],
        "stages": ["Vegetative", "Reproductive", "Ripening"],
        "stage_note": "Can appear at any stage; numbers build up from tillering, and damage is worst from booting to ripening.",
        "symptoms": ["hopperburn", "honeydew_sooty_mold", "wilting_lodging"],
    },
    {
        "key": "green_leafhopper",
        "signs": [
            "Bright green, wedge-shaped insects, 3-5 mm, on the upper leaves.",
            "Many have black spots or a black band on the wing tips.",
            "They jump or fly off quickly when disturbed.",
        ],
        "stages": ["Vegetative", "Reproductive"],
        "stage_note": "Most important on young plants (seedling to tillering), when they spread tungro.",
        "symptoms": ["tungro_discoloration", "stunted_plants", "reduced_tillering"],
    },
    {
        "key": "rice_bug",
        "signs": [
            "Slender green-to-brown bugs, 14-17 mm, with long legs and long antennae.",
            "Usually on the panicles, sucking the developing grains.",
            "A strong, unpleasant smell in the field.",
        ],
        "stages": ["Reproductive", "Ripening"],
        "stage_note": "From flowering to the milk and dough stages, when the grains are soft.",
        "symptoms": ["empty_grains", "grain_spots", "rice_bug_odor"],
    },
    {
        "key": "rice_stem_borer",
        "signs": [
            "Moths: pale yellow to white; the female yellow stem borer has a black dot on each forewing.",
            "Egg masses on the leaf tips, covered with light brown hairs.",
            "Larvae (caterpillars) feed inside the stem, so they are rarely seen.",
        ],
        "stages": ["Vegetative", "Reproductive"],
        "stage_note": "Deadhearts during the vegetative stage, whiteheads after the panicle forms.",
        "symptoms": ["deadhearts", "whiteheads", "bore_holes_frass"],
    },
]

# Every damage indicator the system handles (app/levels.py DAMAGE_INDICATORS
# for the four pests), with what to look for. `indicator` is the exact text a
# reviewer ticks.
SYMPTOMS = [
    {
        "key": "hopperburn", "pest": "brown_planthopper",
        "indicator": "Hopperburn (yellowing and drying patches)", "name": "Hopperburn",
        "signs": "Round patches of plants that turn yellow, then brown and dry, as if burned. "
                 "The patches grow outward and plants in the middle collapse.",
        "stages": ["Reproductive", "Ripening"],
    },
    {
        "key": "honeydew_sooty_mold", "pest": "brown_planthopper",
        "indicator": "Honeydew or sooty mold at the plant base", "name": "Honeydew or sooty mold",
        "signs": "Sticky, shiny honeydew on the lower stems; later a black, powdery mold grows on it.",
        "stages": ["Vegetative", "Reproductive", "Ripening"],
    },
    {
        "key": "wilting_lodging", "pest": "brown_planthopper",
        "indicator": "Plants wilting or lodging", "name": "Wilting or lodging",
        "signs": "Plants droop and fall over, starting from the base where the planthoppers feed.",
        "stages": ["Reproductive", "Ripening"],
    },
    {
        "key": "tungro_discoloration", "pest": "green_leafhopper",
        "indicator": "Yellow-orange leaf discoloration (possible tungro)", "name": "Yellow-orange leaves (possible tungro)",
        "signs": "Leaves turn yellow to orange starting from the tip; young leaves may look mottled. "
                 "A sign of tungro virus, which green leafhoppers spread.",
        "stages": ["Vegetative"],
    },
    {
        "key": "stunted_plants", "pest": "green_leafhopper",
        "indicator": "Stunted plants", "name": "Stunted plants",
        "signs": "Plants clearly shorter than their neighbours, often in patches.",
        "stages": ["Vegetative"],
    },
    {
        "key": "reduced_tillering", "pest": "green_leafhopper",
        "indicator": "Reduced tillering", "name": "Reduced tillering",
        "signs": "Hills with fewer tillers (shoots) than healthy hills nearby.",
        "stages": ["Vegetative"],
    },
    {
        "key": "empty_grains", "pest": "rice_bug",
        "indicator": "Empty or unfilled grains", "name": "Empty or unfilled grains",
        "signs": "Grains that stay light, empty or only partly filled; panicles stay upright.",
        "stages": ["Reproductive", "Ripening"],
    },
    {
        "key": "grain_spots", "pest": "rice_bug",
        "indicator": "Brown spots on grains", "name": "Brown spots on grains",
        "signs": "Small brown or black spots on the hulls where the bugs fed (pecky rice).",
        "stages": ["Ripening"],
    },
    {
        "key": "rice_bug_odor", "pest": "rice_bug",
        "indicator": "Offensive rice-bug odor in the field", "name": "Rice bug odor",
        "signs": "A strong, unpleasant smell when walking through the field.",
        "stages": ["Reproductive", "Ripening"],
    },
    {
        "key": "deadhearts", "pest": "rice_stem_borer",
        "indicator": "Deadhearts (dead central tiller)", "name": "Deadhearts",
        "signs": "The central leaf of a tiller dries and turns brown while the outer leaves stay green. "
                 "It pulls out easily and the base is chewed.",
        "stages": ["Vegetative"],
    },
    {
        "key": "whiteheads", "pest": "rice_stem_borer",
        "indicator": "Whiteheads (empty white panicles)", "name": "Whiteheads",
        "signs": "Panicles that stay white or straw-coloured, upright and empty. "
                 "They pull out easily because the stem below was cut by the larva.",
        "stages": ["Reproductive", "Ripening"],
    },
    {
        "key": "bore_holes_frass", "pest": "rice_stem_borer",
        "indicator": "Bore holes or frass on stems", "name": "Bore holes or frass",
        "signs": "Small holes in the stems, sometimes with sawdust-like droppings (frass).",
        "stages": ["Vegetative", "Reproductive"],
    },
]

MODEL_NOTE = (
    "The model looks for the four insects only. It does not detect symptoms such as deadhearts, "
    "whiteheads or hopperburn; your technician checks those in the field and in the photo."
)


def _photo_path(key: str):
    for ext in _PHOTO_TYPES:
        path = os.path.join(PHOTO_DIR, f"{key}{ext}")
        if os.path.isfile(path):
            return path
    return None


def content() -> dict:
    """The guide, with `photo` = the photo's URL path (None when missing)."""
    def photo(key):
        return f"/guide/photos/{key}" if _photo_path(key) else None

    return {
        "title": "What to look for",
        "model_note": MODEL_NOTE,
        "pests": [
            {**p, "name": PEST_NAMES[p["key"]], "model_label": MODEL_LABELS[p["key"]], "photo": photo(p["key"])}
            for p in PESTS
        ],
        "symptoms": [{**s, "pest_name": PEST_NAMES[s["pest"]], "photo": photo(s["key"])} for s in SYMPTOMS],
        "model_classes": [{"key": c, "name": PEST_NAMES[c], "model_label": MODEL_LABELS[c]} for c in CLASSES],
    }


@router.get("")
def guide(user: dict = Depends(require_role(*EVERYONE))):
    return content()


@router.get("/photos/{key}")
def guide_photo(key: str, user: dict = Depends(require_role(*EVERYONE))):
    known = {p["key"] for p in PESTS} | {s["key"] for s in SYMPTOMS}
    path = _photo_path(key) if key in known else None  # only known keys: no path tricks
    if path is None:
        raise HTTPException(status_code=404, detail="No example photo yet.")
    return FileResponse(path, media_type=_PHOTO_TYPES[os.path.splitext(path)[1]])
