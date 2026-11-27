# Pest detection model

`rice_pest_yolo26s.onnx` is the fp32 ONNX export of the YOLO26s training run
`rice_pest_yolo26s_final_20261125_232339_067864_utc`, copied unchanged from
`deployment_models/best.onnx` in the model bundle (SHA-256
`bfd0c057d003ab945fb530be4d3a46fa3c3734e99030bef2f15c78793105731a`).
`app/detector.py` runs it with `onnxruntime`; PyTorch is not needed on the
server. Why this file and not one of the TFLite variants:
[MODEL_SELECTION.md](MODEL_SELECTION.md).

* Input: `images`, 1×3×640×640 float32 (RGB, letterboxed with grey 114, /255).
* Output: `output0`, 1×8×8400 (4 box values + 4 class scores; not end-to-end).
  `detector.py` runs its own NMS.
* Embedded class names, in order: `brown-planthopper`, `green-leafhopper`,
  `rice-bug`, `stem-borer`. `detector.py` refuses a file whose names, input
  size or output layout differ, and then marks observations "failed" (they go
  to technicians).

**Important:** outputs 2 (`rice-bug`) and 3 (`stem-borer`) do not reliably
match those pests. See "Class label check" in MODEL_SELECTION.md. Until the
training labels are fixed and re-checked, `DETECTOR_UNVERIFIED_CLASSES`
(default `rice_bug,rice_stem_borer`) keeps their boxes but stops them from
naming the pest.

The previous model (`rice_pest.onnx`, YOLOv8, 12 MB) was removed from this
folder. It is still in the Git history and in `CAPSTONE (MAIN)`.

## Replacing the model after retraining

1. Export with a fixed 640×640 input and the default (non-end-to-end) head:
   `yolo export model=best.pt format=onnx imgsz=640 simplify=True`
   (in a separate virtual environment; ultralytics pulls in PyTorch).
2. Check that the class names and order in the export match `MODEL_LABELS`
   in `app/detector.py`, and that each output really detects the pest it is
   named after (MODEL_SELECTION.md shows how this was checked).
3. Copy it here as `rice_pest_yolo26s.onnx` (or set `DETECTOR_MODEL_PATH`),
   update the exception in the root `.gitignore` if the name changes, and run
   `python -m pytest tests/test_detection_no_pests.py`.
4. Re-measure the image-relevance and "no pests" cut-offs on local photos
   before changing `RELEVANCE_MIN_PLANT_FRACTION` or `NO_PEST_MAX_SCORE`.
