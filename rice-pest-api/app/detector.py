"""Server-side pest detection (YOLO26s, ONNX Runtime) and image relevance.

Analysis runs after upload, never on the phone: an offline farmer gets no
result until the observation reaches the server.

The model file is models/rice_pest_yolo26s.onnx (the fp32 ONNX export of the
YOLO26s run of 2026-11-25; why this file was chosen over the TFLite variants
is in models/MODEL_SELECTION.md). DETECTOR_MODEL_PATH may point elsewhere. If
the file or onnxruntime is missing, or its embedded class list does not match
CLASSES, uploads still succeed and the observation goes to plain technician
review ("failed").

Two separate questions are answered for every photo:
  1. relevance  - does the photo look like a crop/field photo at all?
                  (image_relevance(); a screening aid, not a classifier)
  2. detection  - which of the four supported insects are visible?
"No pests found" needs both a relevant-looking photo and no insect signal, so
an unrelated photo (a wall, a person, a printed page) is never recorded as
pest-free.
"""
import os
import threading
from typing import Optional

import numpy as np
from PIL import Image, ImageOps

MODEL_FILE = "rice_pest_yolo26s.onnx"
MODEL_PATH = os.getenv("DETECTOR_MODEL_PATH") or os.path.join(
    os.path.dirname(os.path.dirname(__file__)), "models", MODEL_FILE)

# Same order as the training data (data.yaml). The model's own metadata
# ("names") is checked against MODEL_LABELS when it loads.
CLASSES = ["brown_planthopper", "green_leafhopper", "rice_bug", "rice_stem_borer"]
MODEL_LABELS = {
    "brown_planthopper": "brown-planthopper",
    "green_leafhopper": "green-leafhopper",
    "rice_bug": "rice-bug",
    "rice_stem_borer": "stem-borer",
}
PEST_NAMES = {
    "brown_planthopper": "Brown Planthopper",
    "green_leafhopper": "Green Leafhopper",
    "rice_bug": "Rice Bug",
    "rice_stem_borer": "Rice Stem Borer",
    "other": "Outside the supported pests",
}

INPUT_SIZE = 640
CANDIDATE_CONF = 0.25   # boxes considered at all (before the checks below)
REPORT_CONF = 0.40      # a detection must reach this to be reported or counted
STRONG_CONF = 0.65      # kept even if the mirrored photo doesn't confirm it
IOU_THRESHOLD = 0.45    # NMS within a class
CROSS_CLASS_IOU = 0.60  # same spot labelled as two pests -> keep the more confident
MIRROR_MATCH_IOU = 0.45 # a detection must reappear at the same spot in the mirrored photo
MIN_BOX_AREA = 0.0002   # boxes smaller than this share of the photo are noise
MAX_BOX_AREA = 0.60     # boxes larger than this aren't one insect
# The pest is only named when the evidence is solid: two or more agreeing
# boxes that are confident on average, three or more boxes, or a single box
# that is very confident. A lone middling box is only "possible".
NAME_MIN_MEAN_CONF = 0.45
NAME_MIN_BOXES = 3
NAME_SINGLE_CONF = 0.70
NAME_MIN_SHARE = 0.60       # and it clearly outweighs the other classes
# "Countable" = individual insects are clear enough to tell apart:
COUNT_MIN_MEAN_CONF = 0.50
COUNT_MAX_CROWDED = 0.25     # at most a quarter of the boxes overlap a neighbour
CROWDED_IOU = 0.20
COUNT_MAX_BOXES = 150
# Photo quality, measured on a 640 px grey copy:
BLUR_MIN = 60.0          # variance of the Laplacian below this = blurry
DARK_MAX = 40.0          # mean brightness below this = too dark
BRIGHT_MIN = 225.0       # mean brightness above this = washed out
MAX_IMAGE_SIDE = 2048    # stored photos are downscaled to this
# "No pests found" is only concluded when the evidence is strong: a clear,
# reasonably sharp photo of at least NO_PEST_MIN_SIDE px on its short side,
# on which NO box of ANY class reaches NO_PEST_MAX_SCORE in either the photo
# or its mirror image. Anything in between is "uncertain" (a technician
# checks it); a failed model run is "failed". Never the other way round.
# Calibration on the bundled photos (models/rice_pest.onnx): pest-free rice
# fields scored 0.06-0.13, but a real rice bug photo the model misses scored
# 0.178, so the default stays well below that. Raise it only after testing
# on local photos.
NO_PEST_MAX_SCORE = float(os.getenv("NO_PEST_MAX_SCORE", "0.12"))
NO_PEST_MIN_SIDE = int(os.getenv("NO_PEST_MIN_SIDE", "480"))
MODEL_VERSION = os.path.basename(MODEL_PATH)

# Image relevance (screening only). Share of pixels whose colour is plant-like
# (hue 35-170 degrees: yellow-green to green, saturation >= 0.18, brightness
# >= 0.12) on a 256 px copy. PROVISIONAL cut-off, measured on the photos we
# have (models/MODEL_SELECTION.md, "Image relevance"): rice field and symptom
# photos mostly 0.13-1.00, unrelated test shots (walls, people, printed pages,
# black frames) 0.00-0.05, desktop wallpapers mostly below 0.01. Close-ups of
# insects on a hand or a plain background can also score low, so a low score
# never rejects a photo: it only rules out "no pests found" and asks a
# technician to look. A pest detection always counts as evidence that the
# photo is relevant.
RELEVANCE_MIN_PLANT_FRACTION = float(os.getenv("RELEVANCE_MIN_PLANT_FRACTION", "0.10"))
RELEVANT, POSSIBLY_UNRELATED = "relevant", "possibly_unrelated"
UNRELATED_MESSAGE = "This photo may not show a rice plant or field. A technician will check it."

# Classes whose names have NOT been verified against what the model actually
# detects. Evaluation (models/MODEL_SELECTION.md, "Class label check") found
# that, for this model family, output 2 ("rice-bug") fires on leaf-folder
# caterpillars and output 3 ("stem-borer") on the dataset's "rice bug"
# photos, while stem-borer moths get no consistent class. Until the training
# labels are fixed and re-checked, these outputs are never used to NAME the
# pest: the boxes are kept for the technician, who identifies it. Set
# DETECTOR_UNVERIFIED_CLASSES="" only after that check.
UNVERIFIED_CLASSES = frozenset(
    c.strip() for c in os.getenv("DETECTOR_UNVERIFIED_CLASSES", "rice_bug,rice_stem_borer").split(",") if c.strip()
)
UNVERIFIED_MESSAGE = ("The model found insects, but its labels for this pest have not been verified yet. "
                      "A technician will identify them.")

_session = None
_session_error: Optional[str] = None
_model_info: dict = {}
_lock = threading.Lock()


def _check_model(session) -> dict:
    """The file must be a 640x640 detector for exactly our four classes, in
    our order, with the raw (not end-to-end) output that _run() decodes."""
    import ast

    meta = session.get_modelmeta().custom_metadata_map or {}
    names = ast.literal_eval(meta["names"]) if meta.get("names") else None
    expected = {i: MODEL_LABELS[c] for i, c in enumerate(CLASSES)}
    if names is not None and {int(k): v for k, v in names.items()} != expected:
        raise ValueError(f"model classes {names} do not match {expected}")
    shape = session.get_inputs()[0].shape
    if list(shape[2:]) != [INPUT_SIZE, INPUT_SIZE]:
        raise ValueError(f"model input {shape} is not {INPUT_SIZE}x{INPUT_SIZE}")
    out = session.get_outputs()[0].shape
    if 4 + len(CLASSES) not in (out[1], out[2]):
        raise ValueError(f"unexpected model output {out} (end-to-end exports are not supported)")
    return {"description": meta.get("description", ""), "ultralytics_version": meta.get("version", ""),
            "exported": meta.get("date", ""), "end2end": meta.get("end2end", "")}


def _get_session():
    global _session, _session_error, _model_info
    if _session is not None or _session_error is not None:
        return _session
    with _lock:
        if _session is None and _session_error is None:
            try:
                import onnxruntime as ort

                if not os.path.exists(MODEL_PATH):
                    raise FileNotFoundError(f"{MODEL_PATH} not found")
                opts = ort.SessionOptions()
                # Vercel Hobby functions get 1 vCPU; more threads only add overhead there.
                opts.intra_op_num_threads = int(os.getenv("DETECTOR_THREADS", "1" if os.getenv("VERCEL") else "2"))
                session = ort.InferenceSession(MODEL_PATH, opts, providers=["CPUExecutionProvider"])
                _model_info = _check_model(session)
                _session = session
            except Exception as e:  # missing package or model: degrade, don't crash uploads
                _session_error = f"{type(e).__name__}: {e}"
    return _session


def status() -> dict:
    _get_session()
    return {"available": _session is not None, "error": _session_error, "model": MODEL_VERSION,
            "info": _model_info}


def plant_fraction(img: Image.Image) -> float:
    """Share of plant-coloured pixels (see RELEVANCE_MIN_PLANT_FRACTION)."""
    g = img.convert("RGB")
    g.thumbnail((256, 256))
    hsv = np.asarray(g.convert("HSV"), dtype=np.int16)
    h, s, v = hsv[..., 0], hsv[..., 1], hsv[..., 2]
    # PIL's HSV is 0-255: hue 25-120 = 35-170 degrees; 46 = 0.18; 31 = 0.12.
    return round(float(((h >= 25) & (h <= 120) & (s >= 46) & (v >= 31)).mean()), 4)


def image_relevance(img: Image.Image, pest_evidence: bool = False) -> dict:
    """{"status": "relevant" | "possibly_unrelated", "plant_fraction", "basis", ...}.

    A screening aid, not a classifier: "possibly_unrelated" only means a
    technician should look before the photo counts as an observation."""
    frac = plant_fraction(img)
    if pest_evidence:
        state, basis = RELEVANT, "pest_detected"
    elif frac >= RELEVANCE_MIN_PLANT_FRACTION:
        state, basis = RELEVANT, "plant_colour"
    else:
        state, basis = POSSIBLY_UNRELATED, "little_plant_colour"
    return {"status": state, "plant_fraction": frac, "basis": basis,
            "min_plant_fraction": RELEVANCE_MIN_PLANT_FRACTION, "provisional": True}


def normalize_photo(raw: bytes):
    """Applies the phone's EXIF rotation and downscales, so the stored photo
    and the detection boxes line up on every screen. Returns the image and its
    JPEG bytes (the caller stores them; see app/storage.py)."""
    import io

    img = Image.open(io.BytesIO(raw))
    img = ImageOps.exif_transpose(img).convert("RGB")
    if max(img.size) > MAX_IMAGE_SIDE:
        img.thumbnail((MAX_IMAGE_SIDE, MAX_IMAGE_SIDE))
    out = io.BytesIO()
    img.save(out, "JPEG", quality=90)
    return img, out.getvalue()


def _resize_bilinear(a: np.ndarray, nw: int, nh: int) -> np.ndarray:
    """Plain bilinear resize with half-pixel centres, like OpenCV's INTER_LINEAR
    used in training. (Pillow's BILINEAR also smooths when shrinking, which
    shifts borderline detections.)"""
    h, w = a.shape[:2]
    xs = np.clip((np.arange(nw) + 0.5) * (w / nw) - 0.5, 0, w - 1)
    ys = np.clip((np.arange(nh) + 0.5) * (h / nh) - 0.5, 0, h - 1)
    x0, y0 = np.floor(xs).astype(int), np.floor(ys).astype(int)
    x1, y1 = np.minimum(x0 + 1, w - 1), np.minimum(y0 + 1, h - 1)
    fx, fy = (xs - x0)[None, :, None], (ys - y0)[:, None, None]
    top = a[y0][:, x0] * (1 - fx) + a[y0][:, x1] * fx
    bottom = a[y1][:, x0] * (1 - fx) + a[y1][:, x1] * fx
    return top * (1 - fy) + bottom * fy


def _letterbox(img: Image.Image):
    w, h = img.size
    scale = min(INPUT_SIZE / w, INPUT_SIZE / h)
    nw, nh = round(w * scale), round(h * scale)
    pad_x, pad_y = (INPUT_SIZE - nw) // 2, (INPUT_SIZE - nh) // 2
    canvas = np.full((INPUT_SIZE, INPUT_SIZE, 3), 114.0, dtype=np.float32)
    canvas[pad_y:pad_y + nh, pad_x:pad_x + nw] = _resize_bilinear(np.asarray(img, dtype=np.float32), nw, nh)
    x = np.round(canvas) / 255.0
    return x.transpose(2, 0, 1)[None].astype(np.float32), scale, pad_x, pad_y


def _iou(box: np.ndarray, boxes: np.ndarray) -> np.ndarray:
    x1 = np.maximum(box[0], boxes[:, 0])
    y1 = np.maximum(box[1], boxes[:, 1])
    x2 = np.minimum(box[2], boxes[:, 2])
    y2 = np.minimum(box[3], boxes[:, 3])
    inter = np.clip(x2 - x1, 0, None) * np.clip(y2 - y1, 0, None)
    area = (box[2] - box[0]) * (box[3] - box[1])
    areas = (boxes[:, 2] - boxes[:, 0]) * (boxes[:, 3] - boxes[:, 1])
    return inter / np.maximum(area + areas - inter, 1e-9)


def _nms(boxes: np.ndarray, scores: np.ndarray) -> list:
    order = scores.argsort()[::-1]
    keep = []
    while order.size:
        i = order[0]
        keep.append(i)
        if order.size == 1:
            break
        rest = order[1:]
        order = rest[_iou(boxes[i], boxes[rest]) < IOU_THRESHOLD]
    return keep


def photo_metrics(img: Image.Image) -> dict:
    """Brightness and sharpness (variance of the Laplacian) on a 640 px grey copy."""
    g = img.convert("L")
    g.thumbnail((INPUT_SIZE, INPUT_SIZE))
    a = np.asarray(g, dtype=np.float32)
    lap = a[1:-1, 2:] + a[1:-1, :-2] + a[2:, 1:-1] + a[:-2, 1:-1] - 4 * a[1:-1, 1:-1]
    return {"brightness": round(float(a.mean()), 1), "sharpness": round(float(lap.var()), 1)}


def photo_quality(img: Image.Image, metrics: Optional[dict] = None) -> Optional[str]:
    """A short reason when the photo is probably too poor to judge, else None."""
    m = metrics or photo_metrics(img)
    if m["brightness"] < DARK_MAX:
        return "too dark"
    if m["brightness"] > BRIGHT_MIN:
        return "washed out by light"
    if m["sharpness"] < BLUR_MIN:
        return "blurry"
    return None


def _run(session, img: Image.Image):
    """Candidate boxes as (x1, y1, x2, y2) in photo pixels, confidences,
    classes, and the highest score of any box of any class (for "no pests")."""
    w, h = img.size
    x, scale, pad_x, pad_y = _letterbox(img)
    out = session.run(None, {session.get_inputs()[0].name: x})[0]
    pred = out[0].T if out.shape[1] == 4 + len(CLASSES) else out[0]  # (N, 4 + classes)
    scores = pred[:, 4:]
    top = float(scores.max()) if scores.size else 0.0
    cls = scores.argmax(axis=1)
    conf = scores[np.arange(len(cls)), cls]
    keep = conf >= CANDIDATE_CONF
    pred, cls, conf = pred[keep], cls[keep], conf[keep]
    if not len(pred):
        return np.zeros((0, 4)), np.zeros(0), np.zeros(0, dtype=int), top
    cx, cy, bw, bh = pred[:, 0], pred[:, 1], pred[:, 2], pred[:, 3]
    boxes = np.stack([cx - bw / 2, cy - bh / 2, cx + bw / 2, cy + bh / 2], axis=1)
    boxes = (boxes - np.array([pad_x, pad_y, pad_x, pad_y])) / scale  # undo the letterbox
    boxes = np.clip(boxes, 0, [w, h, w, h])
    kept = []
    for c in np.unique(cls):
        idx = np.where(cls == c)[0]
        kept.extend(idx[k] for k in _nms(boxes[idx], conf[idx]))
    kept = np.array(kept, dtype=int)
    return boxes[kept], conf[kept], cls[kept], top


NO_PESTS_MESSAGE = "No pests were found in this photo."


def _metadata(img: Image.Image, metrics: dict, quality: Optional[str], top: float, mtop: float,
              boxes: int, relevance: Optional[dict] = None) -> dict:
    """What the decision was based on (saved with the observation)."""
    return {
        "model": MODEL_VERSION,
        "relevance": relevance,
        "input_size": INPUT_SIZE,
        "image_width": img.size[0],
        "image_height": img.size[1],
        "brightness": metrics["brightness"],
        "sharpness": metrics["sharpness"],
        "quality_issue": quality,
        "max_score": round(top, 4),
        "max_score_mirrored": round(mtop, 4),
        "reported_boxes": boxes,
        "thresholds": {"no_pest_max_score": NO_PEST_MAX_SCORE, "no_pest_min_side": NO_PEST_MIN_SIDE,
                       "report_conf": REPORT_CONF, "candidate_conf": CANDIDATE_CONF,
                       "relevance_min_plant_fraction": RELEVANCE_MIN_PLANT_FRACTION},
    }


def analyze(img: Image.Image) -> dict:
    """Returns {status, result, pest, confidence, count, countable, detections,
    message, metadata, relevance}.
    detections: [{"x1","y1","x2","y2" (0-1 of the stored photo), "conf", "pest"}].
    result: "pests_found" | "no_pests_found" | "uncertain" | "failed".
    relevance: "relevant" | "possibly_unrelated" (image_relevance()).

    Prefers "not sure" over a wrong answer: detections must be confident,
    reappear in the mirrored photo and look like single insects, and the pest
    is only named on solid evidence. "no_pests_found" needs a clear,
    relevant-looking photo on which the model saw nothing at all (see
    NO_PEST_MAX_SCORE and RELEVANCE_MIN_PLANT_FRACTION). "Unrelated photo" and
    "no pests" are never the same answer."""
    out = _detect(img)
    rel = (out.get("metadata") or {}).get("relevance") or image_relevance(img, bool(out.get("detections")))
    out["metadata"] = {**(out.get("metadata") or {}), "relevance": rel}
    out["relevance"] = rel["status"]
    return out


def screen_only(img: Image.Image) -> dict:
    """Relevance for reports the model does not analyse (disease reports)."""
    return image_relevance(img)


def _detect(img: Image.Image) -> dict:
    session = _get_session()
    if session is None:
        return {"status": "failed", "result": "failed", "pest": None, "confidence": None, "count": None,
                "countable": False, "detections": [],
                "message": "Automatic analysis is unavailable. A technician will identify the pest.",
                "metadata": {"model": MODEL_VERSION, "error": _session_error,
                             "relevance": image_relevance(img)}}

    w, h = img.size
    metrics = photo_metrics(img)
    quality = photo_quality(img, metrics)
    boxes, conf, cls, top = _run(session, img)
    # Test-time check: the same insect has to be found again in the mirrored photo.
    mboxes, mconf, mcls, mtop = _run(session, ImageOps.mirror(img))
    if len(mboxes):
        mboxes = np.stack([w - mboxes[:, 2], mboxes[:, 1], w - mboxes[:, 0], mboxes[:, 3]], axis=1)

    candidates = []
    for b, c, k in zip(boxes, conf, cls):
        area = (b[2] - b[0]) * (b[3] - b[1]) / (w * h)
        if not (MIN_BOX_AREA <= area <= MAX_BOX_AREA):
            continue
        same = mcls == k
        ious = _iou(b, mboxes[same]) if same.any() else np.zeros(0)
        if len(ious) and float(ious.max()) >= MIRROR_MATCH_IOU:
            score = (float(c) + float(mconf[same][int(ious.argmax())])) / 2
        elif c >= STRONG_CONF:
            score = float(c)
        else:
            continue
        if score >= REPORT_CONF:
            candidates.append((b, score, int(k)))

    # One spot, one pest: drop the weaker of overlapping boxes with different labels.
    candidates.sort(key=lambda t: -t[1])
    detections = []
    for b, score, k in candidates:
        if detections and float(_iou(b, np.array([d[0] for d in detections])).max()) >= CROSS_CLASS_IOU:
            continue
        detections.append((b, score, k))

    boxes_out = [
        {"x1": round(float(b[0] / w), 4), "y1": round(float(b[1] / h), 4),
         "x2": round(float(b[2] / w), 4), "y2": round(float(b[3] / h), 4),
         "conf": round(score, 3), "pest": CLASSES[k]}
        for b, score, k in detections
    ]
    retake = f"The photo looks {quality}; the technician may ask for a new one." if quality else None
    relevance = image_relevance(img, pest_evidence=bool(boxes_out))
    meta = _metadata(img, metrics, quality, top, mtop, len(boxes_out), relevance)

    if not boxes_out and relevance["status"] == POSSIBLY_UNRELATED:
        # Not "no pests": the photo may not show a field at all.
        return {"status": "done", "result": "uncertain", "pest": None, "confidence": None, "count": None,
                "countable": False, "detections": [], "message": UNRELATED_MESSAGE, "metadata": meta}

    if not boxes_out:
        clear_nothing = (
            quality is None
            and min(w, h) >= NO_PEST_MIN_SIDE
            and max(top, mtop) < NO_PEST_MAX_SCORE
        )
        if clear_nothing:
            return {"status": "done", "result": "no_pests_found", "pest": None, "confidence": None,
                    "count": 0, "countable": False, "detections": [], "message": NO_PESTS_MESSAGE,
                    "metadata": meta}
        return {"status": "done", "result": "uncertain", "pest": None, "confidence": None, "count": None,
                "countable": False, "detections": [],
                "message": retake or "No supported pest was recognized with confidence. A technician will check the photo.",
                "metadata": meta}

    totals: dict = {}
    for d in boxes_out:
        totals[d["pest"]] = totals.get(d["pest"], 0.0) + d["conf"]
    pest = max(totals, key=totals.get)
    mine = [d for d in boxes_out if d["pest"] == pest]
    mean_conf = sum(d["conf"] for d in mine) / len(mine)
    share = totals[pest] / sum(totals.values())
    if len(mine) == 1:
        enough = mean_conf >= NAME_SINGLE_CONF
    else:
        enough = mean_conf >= NAME_MIN_MEAN_CONF or len(mine) >= NAME_MIN_BOXES
    solid = enough and share >= NAME_MIN_SHARE
    if not solid:
        return {"status": "done", "result": "uncertain", "pest": None, "confidence": round(mean_conf, 3),
                "count": None, "countable": False, "detections": boxes_out,
                "message": retake or "Possible pests were found, but not clearly enough to name one. A technician will identify it.",
                "metadata": meta}
    if pest in UNVERIFIED_CLASSES:
        # Insects were found, but this output's name is not trustworthy (see
        # UNVERIFIED_CLASSES): keep the boxes, don't name or count.
        return {"status": "done", "result": "uncertain", "pest": None, "confidence": round(mean_conf, 3),
                "count": None, "countable": False, "detections": boxes_out, "message": UNVERIFIED_MESSAGE,
                "metadata": {**meta, "unverified_class": pest}}

    arr = np.array([[d["x1"] * w, d["y1"] * h, d["x2"] * w, d["y2"] * h] for d in mine])
    crowded = sum(
        1 for i in range(len(arr))
        if len(arr) > 1 and (_iou(arr[i], np.delete(arr, i, axis=0)) >= CROWDED_IOU).any()
    )
    countable = (
        quality is None
        and mean_conf >= COUNT_MIN_MEAN_CONF
        and crowded / len(mine) <= COUNT_MAX_CROWDED
        and len(mine) <= COUNT_MAX_BOXES
    )
    if countable:
        message = "Other pests may also be in the photo; the technician will check." if len(totals) > 1 else None
    elif retake:
        message = retake
    elif crowded / len(mine) > COUNT_MAX_CROWDED or len(mine) > COUNT_MAX_BOXES:
        message = "The insects are too close together to count reliably."
    else:
        message = "The insects are not clear enough to count reliably."
    return {
        "status": "done",
        "result": "pests_found",
        "pest": pest,
        "confidence": round(mean_conf, 3),
        "count": len(mine) if countable else None,
        "countable": countable,
        "detections": boxes_out,
        "message": message,
        "metadata": meta,
    }
