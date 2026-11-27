"""'What to look for': the pest and symptom guide shown in the mobile app and
on the dashboard. This file is the only copy of the guide's English content (translations: app/i18n_guide.py); both
apps fetch it from GET /guide. Rules and limits: docs/MONITORING.md.

Example photos live in guide_photos/<key>.jpg (or .png). A missing photo
shows a placeholder in the apps until the group adds one.
"""
import os

from fastapi import APIRouter, Depends, HTTPException, Request
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


CONFIRM_NOTE = "A model result is a suggestion. A technician confirms every pest, count and level."
TRANSLATION_NOTE = "Translations are machine-assisted and have not been reviewed by an expert."

# What the deployed model is (models/MODEL_SELECTION.md). Test-split figures
# come from the training run's own held-out split; field photos differ.
MODEL_FACTS = {
    "architecture": "YOLO26s object detector, 640 x 640 input",
    "file": "rice_pest_yolo26s.onnx",
    "trained": "2026-11-25",
    "test_split_images": 774,
    "classes": len(CLASSES),
    "note": "Accuracy figures were measured on photos from the training dataset. Photos taken in Antique fields "
            "may look different, so every result is checked by a technician.",
}

GLOSSARY = [
    ("Observation", "A photo and details sent from one field on one day."),
    ("Not Validated", "Waiting for the first review by a technician (or an agriculturist where no technician covers the area)."),
    ("To Be Validated", "Sent up by a technician for an agriculturist to decide (escalated)."),
    ("Validated", "A technician or agriculturist checked the observation and confirmed the pest, count and level."),
    ("Infestation level", "LOW, MEDIUM or HIGH, confirmed by the reviewer from the count, the crop stage and the damage seen."),
    ("Provisional", "Not yet confirmed by an expert; may change."),
    ("Recommendation", "An option from the approved treatment list that the reviewer suggests. It is not something you did yet."),
    ("Treatment applied", "What you actually did in the field, and the date you did it."),
    ("Follow-up", "A new photo of the same field after a treatment, normally 7 days later, to see how it changed."),
    ("Hotspot", "A barangay with validated cases in the last 30 days."),
    ("Direction of spread", "Where validated cases moved between two periods. It describes what was reported, not a forecast."),
    ("Land type", "Upland, rainfed lowland or irrigated lowland. The 100 m elevation hint is provisional."),
    ("Possibly unrelated photo", "The photo may not show a rice plant or field; a technician checks it. "
                                 "It is not the same as \"no pests found\"."),
]


def content(lang: str = "en") -> dict:
    """The guide in `lang`, with `photo` = the photo's URL path (None when
    missing). `model_detected` lists what the photo model can find (the four
    insect classes it was trained on); `observed_symptoms` lists damage that
    only people check in the field. Older keys (pests, symptoms,
    model_classes) are kept for older app builds."""
    from . import i18n

    L = i18n.clean(lang)

    def tr(text_):
        return i18n.t(text_, L)

    def photo(key):
        return f"/guide/photos/{key}" if _photo_path(key) else None

    def stage_labels(stages):
        return [tr(s) for s in stages]

    pests = [
        {**p, "name": tr(PEST_NAMES[p["key"]]), "name_en": PEST_NAMES[p["key"]],
         "model_label": MODEL_LABELS[p["key"]], "model_class_index": CLASSES.index(p["key"]),
         "signs": [tr(s) for s in p["signs"]], "stage_note": tr(p["stage_note"]),
         "stage_labels": stage_labels(p["stages"]), "detected_by": "model", "photo": photo(p["key"])}
        for p in PESTS
    ]
    symptoms = [
        {**s, "name": tr(s["name"]), "name_en": s["name"], "signs": tr(s["signs"]),
         "indicator_label": tr(s["indicator"]), "pest_name": tr(PEST_NAMES[s["pest"]]),
         "stage_labels": stage_labels(s["stages"]), "detected_by": "people", "photo": photo(s["key"])}
        for s in SYMPTOMS
    ]
    return {
        "title": tr("What to look for"),
        "language": L,
        # Not reviewed by a language expert (see app/i18n_guide.py).
        "translation_status": "source" if L == "en" else "machine_assisted_unreviewed",
        "translation_note": None if L == "en" else tr(TRANSLATION_NOTE),
        "model_note": tr(MODEL_NOTE),
        "confirm_note": tr(CONFIRM_NOTE),
        "sections": {"model_detected": tr("Detected by the photo model"),
                     "observed_symptoms": tr("Checked by people in the field")},
        "model_detected": pests,
        "observed_symptoms": symptoms,
        "model": MODEL_FACTS,
        "glossary": [{"term": tr(term), "term_en": term, "meaning": tr(meaning)} for term, meaning in GLOSSARY],
        "pests": pests,
        "symptoms": symptoms,
        "model_classes": [{"key": c, "name": tr(PEST_NAMES[c]), "model_label": MODEL_LABELS[c]} for c in CLASSES],
    }


@router.get("")
def guide(request: Request, lang: str = "", user: dict = Depends(require_role(*EVERYONE))):
    """The guide in ?lang= / X-Palay-Language / the account's language."""
    from . import i18n

    return content(i18n.request_language(request, user, lang))


@router.get("/photos/{key}")
def guide_photo(key: str, user: dict = Depends(require_role(*EVERYONE))):
    known = {p["key"] for p in PESTS} | {s["key"] for s in SYMPTOMS}
    path = _photo_path(key) if key in known else None  # only known keys: no path tricks
    if path is None:
        raise HTTPException(status_code=404, detail="No example photo yet.")
    return FileResponse(path, media_type=_PHOTO_TYPES[os.path.splitext(path)[1]])
