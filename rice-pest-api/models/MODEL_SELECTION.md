# Model selection: YOLO26s deployment variants (2026-11-27)

**Selected: `deployment_models/best.onnx` → `models/rice_pest_yolo26s.onnx`**
(fp32 ONNX, 36.4 MB, ONNX Runtime on CPU).

Source bundle:
`palay_patrol_yolo26_rice_pest_yolo26s_final_20261125_232339_067864_utc_EVERYTHING/palay_patrol_yolo26s/palay_patrol_complete_20261125_232339_067864_utc/deployment_models/`
(training run `rice_pest_yolo26s_final_20261125_232339_067864_utc`, YOLO26s,
640 px, 100 epochs, best epoch 99).

> **Read §4 first.** The class names embedded in this model (and in the
> previous one) do not match what outputs 2 and 3 actually detect. That
> problem lies in the training data, not in the choice of file. It is why the
> API does not name `rice_bug` / `rice_stem_borer` automatically.

## 1. What was evaluated

Every file in `deployment_models/`:

| File | Format | Size | Input | Runtime needed |
|---|---|---:|---|---|
| `best.onnx` | ONNX fp32, opset 18 | 36.4 MB | 1×3×640×640 | onnxruntime (already used by the API) |
| `best.tflite` | TFLite fp32 | 36.4 MB | 1×3×640×640 (NCHW) | LiteRT (`ai-edge-litert`) |
| `best_saved_model/best_float32.tflite` | TFLite fp32 | 36.3 MB | 1×640×640×3 (NHWC) | LiteRT |
| `best_saved_model/best_float16.tflite` | TFLite fp16 weights | 18.2 MB | NHWC | LiteRT |
| `best_w8a32.tflite` | 8-bit weights, fp32 activations | 9.6 MB | NCHW | LiteRT |
| `best_w8a16.tflite` | 8-bit weights, 16-bit activations | 9.8 MB | NCHW | LiteRT |
| `best_int8.tflite` | int8 weights/activations (fp32 I/O) | 9.8 MB | NCHW | LiteRT |

All of them were exported from the same checkpoint. They have the same 4
outputs (`[1, 8, 8400]`: 4 box values + 4 class scores, **not** end-to-end).
So `app/detector.py`'s post-processing (letterbox, NMS, mirror check,
naming/counting rules) works for every variant unchanged, and so did the
previous model's.

## 2. How

* **Accuracy:** the bundle's own held-out test list
  (`runs/detect/.../latency_benchmark.csv`, 774 images) was rebuilt from the
  local copies of the source data (`unified_dataset/6k.zip`, `9k.zip`); all
  774 files were matched. Each image was preprocessed exactly like
  `detector.py`, and every variant ran on the same tensor. mAP50 /
  mAP50-95 follow Ultralytics' method: confidence 0.001, NMS IoU 0.7, 101-point
  interpolation. Precision and recall were also measured at the API's own
  operating point (confidence 0.40, NMS IoU 0.45). "Agreement" is the share
  of images where a variant reports exactly the same set of classes as
  `best.onnx` at 0.40.
* **Speed / memory:** single image, 2 CPU threads, laptop CPU (Windows,
  Python 3.13, onnxruntime 1.32, ai-edge-litert 2.4.1). Load time and the
  memory added by loading were measured too.
* **Vercel size:** the API's `requirements.txt` was installed from the Linux
  wheels (`manylinux`, CPython 3.12, what `.python-version` pins) into an
  empty folder and measured. Then the same with `ai-edge-litert` in place of
  `onnxruntime`.
* Scripts: `tools/eval_deployment_models.py` (accuracy/speed; `REMAP=astrained`
  for §3a) and `tools/relevance_calibration.py` (§6). The numbers below are
  copied from their output.

## 3. Results

### 3a. Accuracy, as trained (labels mapped by index)

Indices 0–3 of the source labels were used as the model was trained (see §4).
774 images; ground-truth boxes per output index: 200 / 223 / 395 / 308.

| Variant | mAP50 | mAP50-95 | P @0.40 | R @0.40 | Agreement with best.onnx | AP50 per output (0 / 1 / 2 / 3) |
|---|---:|---:|---:|---:|---:|---|
| **best.onnx** | **0.989** | **0.735** | 0.984 | 0.984 | 100 % | 0.975 / 0.994 / 0.992 / 0.995 |
| best.tflite | 0.989 | 0.735 | 0.984 | 0.984 | 100 % | identical to best.onnx |
| best_float32.tflite | 0.989 | 0.735 | 0.984 | 0.984 | 100 % | identical |
| best_float16.tflite | 0.989 | 0.735 | 0.984 | 0.985 | 100 % | 0.975 / 0.994 / 0.992 / 0.995 |
| best_w8a32.tflite | 0.989 | 0.732 | 0.981 | 0.985 | 99.9 % | 0.974 / 0.994 / 0.993 / 0.995 |
| best_int8.tflite | 0.987 | 0.723 | 0.974 | 0.982 | 99.5 % | 0.973 / 0.993 / 0.988 / 0.993 |
| best_w8a16.tflite (1-in-12 subset, 65 images) | ≈ best.onnx on the same subset (mAP50 0.660 vs 0.660 by name mapping) | | | | 100 % on the subset | |
| previous rice_pest.onnx (YOLOv8) | 0.983 | 0.713 | 0.966 | 0.981 | 98.7 % | 0.960 / 0.994 / 0.986 / 0.994 |

These reproduce the bundle's reported test metrics (mAP50 0.988, mAP50-95
0.725). That confirms the reconstruction, and also that the reported numbers
measure the labels **as trained** (output 2 = leaf folder, output 3 = the
dataset's "rice bug"). With labels mapped by **name**
(rice bug → output 2, stem borer → output 3), every variant scores AP50 ≈ 0
for output 2, and no stem-borer boxes remain at all. So the overall mAP50 is
only 0.656 for every variant. The new model is better than the previous one
on every metric (+0.006 mAP50, +0.022 mAP50-95), mostly on brown planthopper.

### 3b. Speed, memory and size

| Variant | Median / p95 latency per run | Load time | Memory added | Notes |
|---|---:|---:|---:|---|
| best.onnx (ORT) | 174 / 278 ms | 0.33 s | 149 MB | same runtime as today |
| best.tflite | 195 / 293 ms | 0.15 s | 139 MB | |
| best_float32.tflite | 195 / 299 ms | 0.07 s | 140 MB | |
| best_float16.tflite | 192 / 302 ms | 0.09 s | 124 MB | |
| best_w8a32.tflite | 162 / 278 ms | 0.04 s | 90 MB | |
| best_int8.tflite | 97 / 188 ms | 0.03 s | 56 MB | fastest |
| best_w8a16.tflite | **8 775 / 15 391 ms** | 0.06 s | 41 MB | measured on a 1-in-12 subset; 16-bit activation kernels are not optimised on CPU |
| previous rice_pest.onnx (YOLOv8) | 67 / 116 ms | 0.06 s | 48 MB | for reference |

The detector runs the model twice per photo (photo + mirror image).

### 3c. Vercel bundle (Linux wheels, apparent size, without `__pycache__`)

| Runtime set | Dependencies | + model | Total |
|---|---:|---:|---:|
| onnxruntime (current) + `best.onnx` | 204.9 MB | 36.4 MB | ≈ 243 MB |
| ai-edge-litert + `best_int8.tflite` | 174.8 MB | 9.8 MB | ≈ 186 MB |
| ai-edge-litert + `best_float16.tflite` | 174.8 MB | 18.2 MB | ≈ 194 MB |

Vercel's limit for **Python** functions is 500 MB uncompressed (its generic
function limit is 250 MB). Every option fits. Hobby functions get 2 GB of
memory and 1 vCPU, so all options also fit in memory.

## 4. Class label check (important)

Running the models on the source categories (25 test images each, top class
at 0.40) gave:

| Photos labelled (source folder) | New YOLO26s | Previous YOLOv8 |
|---|---|---|
| brown planthopper | output 0 "brown-planthopper" 6/6 | 6/6 |
| green leafhopper | output 1 "green-leafhopper" 25/25 | 25/25 |
| **leaf folder** (not one of the 4 pests) | output 2 **"rice-bug"** 25/25 | 25/25 |
| **rice bug** | output 3 **"stem-borer"** 25/25 | 23/25 |
| **stem borer** | no consistent class (0: 11, 1: 9, none: 3, 2: 2) | similar |
| whorl maggot (not one of the 4) | mostly none, some output 2 | similar |

The bundle's own test list fits this pattern: 261 leaf-folder images and 237
rice-bug images, but only 1 stem-borer image. The source zips use 6 classes
(0 brown planthopper, 1 green leafhopper, 2 leaf folder, 3 rice bug,
4 stem borer, 5 whorl maggot). The training config uses 4 names (0 brown
planthopper, 1 green leafhopper, 2 rice bug, 3 stem borer). The most likely
explanation: indices 0–3 were kept as they were, boxes with 4–5 were dropped,
and the names were then applied by position. A visual check confirmed that
the source folders contain what their names say. The "rice bug" source
photos also look like weevil-type beetles rather than the slender
*Leptocorisa* rice bug, which is a separate data-quality concern.

On the repository's own guide photos the new model gave: true rice bug →
"green-leafhopper" 0.76; stem borer → "brown-planthopper" 0.74 (named
automatically); brown planthopper → "stem-borer" 0.60. Even outputs 0 and 1
can be wrong on field-style photos. That is why every model result stays a
suggestion that a technician confirms.

The bundle reports test mAP50 0.988 / mAP50-95 0.725 (standard settings).
Those numbers hold **for the labels as trained** (§3a reproduces them). They
do **not** mean the model recognises rice bugs and stem borers.

**What the API does now:** `DETECTOR_UNVERIFIED_CLASSES=rice_bug,rice_stem_borer`
(the default). Boxes from those outputs are kept and shown to the
technician, but the observation is "uncertain" and the pest is not named.
Outputs 0 and 1 work as before, still subject to technician review.

**What needs a decision (not changed here):** fix the class mapping in the
training data and retrain. If leaf folder should become a supported pest,
that needs changes to the database keys, criteria, treatment library and
guide; an agronomist should confirm those. After retraining, repeat the
check above, then clear `DETECTOR_UNVERIFIED_CLASSES`.

## 5. Why `best.onnx`

* **Accuracy:** it is numerically the reference checkpoint (fp32, the export
  the bundle's metrics were taken from). The TFLite fp32/fp16 files give the
  same results. The 8-bit files lose a little (§3a) and agree with fp32 on
  99.5–99.9 % of images.
* **Compatibility and risk:** the API already runs ONNX Runtime on Vercel, so
  no runtime change is needed. The input and output contract is unchanged,
  and `detector.py` checks the embedded class names, input size and output
  layout when it loads the model. Moving to LiteRT would add a new native
  dependency on Vercel with no accuracy gain.
* **Size:** ≈ 243 MB total, inside the 500 MB Python limit with room to spare.
* **Cold start:** about 0.3 s to load. The model loads lazily on the first
  photo of an instance, so other requests don't pay for it. At ~0.2 s per
  run, a photo is analysed in roughly 0.5–1 s on one vCPU, far below the
  60 s function limit.

Alternatives not chosen:
* `best_int8.tflite`: about twice as fast and 26 MB smaller, but it needs a
  new runtime, and int8 costs some mAP50-95. Worth reconsidering if cold
  starts or cost become a problem. Benchmark it on the real Vercel runtime
  first.
* `best_w8a16.tflite`: about 9 s per run on CPU, so ~18 s per photo.
  Unsuitable for serverless.
* TFLite fp32/fp16: no accuracy or speed advantage over ONNX, and a runtime
  change.

## 6. Thresholds re-checked with the new model

* **"No pests found" (`NO_PEST_MAX_SCORE = 0.12`, kept):** on the guide
  photos, pest-free symptom/field photos scored 0.001–0.10 (outliers: stunted
  plants 0.22, reduced tillering 0.64; those stay "uncertain"). The lowest
  real insect photo scored 0.33. 0.12 stays conservative. **Provisional**:
  re-measure on local field photos.
* **Image relevance (`RELEVANCE_MIN_PLANT_FRACTION = 0.10`, new,
  provisional):** share of plant-coloured pixels. Measured:

  | Group | n | min | p5 | median |
  |---|---:|---:|---:|---:|
  | guide photos (field / symptoms / pests) | 16 | 0.000 (an odour illustration) | 0.10 | 0.79 |
  | test-set pest photos (6k) | 505 | 0.000 | 0.018 | 0.64 |
  | test-set pest photos (9k) | 766 | 0.000 | 0.015 | 0.65 |
  | app test uploads (walls, a person, a printed page, black frames, photos of a monitor) | 42 | 0.000 | 0.000 | 0.13 |
  | Windows wallpapers / lock-screen images | 26 | 0.000 | 0.000 | 0.00 |

  Pest close-ups on plain backgrounds can score low, so a low score never
  rejects a photo. Combined with "no insect detected", it marks the photo
  `possibly_unrelated` for a technician and rules out "no pests found".
