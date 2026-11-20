# Pest detection model

`rice_pest.onnx` is the YOLOv8 model from `../best.pt`, exported to ONNX so the
API can run it with `onnxruntime` (no PyTorch on the server). `app/detector.py`
loads it; if the file is missing, uploads still work and observations simply go
to technicians without a model result.

Classes, in order: brown planthopper, green leafhopper, rice bug, rice stem borer.

## Re-exporting after retraining

Do this in a separate virtual environment (ultralytics pulls in PyTorch):

```powershell
py -3.14 -m venv exportenv
exportenv\Scripts\pip install ultralytics onnx onnxslim
exportenv\Scripts\yolo export model=best.pt format=onnx imgsz=640 opset=12 simplify=True
copy best.onnx models\rice_pest.onnx
```

Keep `imgsz=640` and a fixed (non-dynamic) input: `detector.py` letterboxes to
640 x 640. If the class list changes, update `CLASSES` in `app/detector.py` and
`SUPPORTED_PESTS` in `app/levels.py`.

Checked on 2026-09-27: on the photos in `uploads/`, `detector.py` gives the same
detections as `ultralytics` running this ONNX file.
