"""Compare every deployable model variant on the reconstructed held-out test split
(models/MODEL_SELECTION.md). Needs: pip install onnxruntime ai-edge-litert numpy pillow psutil.

Usage: evalenv/Scripts/python -I eval_models.py <testset_dir> <latency_csv> <out_json> <model>...
Each <model> is "label=path". Preprocessing copies app/detector.py (letterbox,
bilinear with half-pixel centres, pad 114, /255).
"""
import csv, json, os, re, sys, time
import numpy as np
from PIL import Image, ImageOps
import psutil

INPUT = 640
REMAP = {0: 0, 1: 1, 2: 2, 3: 3} if os.environ.get("REMAP") == "astrained" else {0: 0, 1: 1, 3: 2, 4: 3}
NC = 4


def resize_bilinear(a, nw, nh):
    h, w = a.shape[:2]
    xs = np.clip((np.arange(nw) + 0.5) * (w / nw) - 0.5, 0, w - 1)
    ys = np.clip((np.arange(nh) + 0.5) * (h / nh) - 0.5, 0, h - 1)
    x0, y0 = np.floor(xs).astype(int), np.floor(ys).astype(int)
    x1, y1 = np.minimum(x0 + 1, w - 1), np.minimum(y0 + 1, h - 1)
    fx, fy = (xs - x0)[None, :, None], (ys - y0)[:, None, None]
    top = a[y0][:, x0] * (1 - fx) + a[y0][:, x1] * fx
    bot = a[y1][:, x0] * (1 - fx) + a[y1][:, x1] * fx
    return top * (1 - fy) + bot * fy


def letterbox(img):
    w, h = img.size
    s = min(INPUT / w, INPUT / h)
    nw, nh = round(w * s), round(h * s)
    px, py = (INPUT - nw) // 2, (INPUT - nh) // 2
    c = np.full((INPUT, INPUT, 3), 114.0, dtype=np.float32)
    c[py:py + nh, px:px + nw] = resize_bilinear(np.asarray(img, dtype=np.float32), nw, nh)
    return (np.round(c) / 255.0).astype(np.float32), s, px, py


def iou_mat(a, b):
    tl = np.maximum(a[:, None, :2], b[None, :, :2]); br = np.minimum(a[:, None, 2:], b[None, :, 2:])
    inter = np.prod(np.clip(br - tl, 0, None), axis=2)
    aa = np.prod(a[:, 2:] - a[:, :2], 1); ab = np.prod(b[:, 2:] - b[:, :2], 1)
    return inter / np.maximum(aa[:, None] + ab[None] - inter, 1e-9)


def nms(boxes, scores, thr):
    order = scores.argsort()[::-1]; keep = []
    while order.size:
        i = order[0]; keep.append(i)
        if order.size == 1: break
        r = order[1:]; order = r[iou_mat(boxes[i:i + 1], boxes[r])[0] < thr]
    return keep


class OnnxModel:
    def __init__(self, path):
        import onnxruntime as ort
        o = ort.SessionOptions(); o.intra_op_num_threads = 2; o.inter_op_num_threads = 1
        self.s = ort.InferenceSession(path, o, providers=["CPUExecutionProvider"])
        self.name = self.s.get_inputs()[0].name

    def __call__(self, x):  # x HWC float
        return self.s.run(None, {self.name: x.transpose(2, 0, 1)[None]})[0]


class TfliteModel:
    def __init__(self, path):
        from ai_edge_litert.interpreter import Interpreter
        self.i = Interpreter(model_path=path, num_threads=2); self.i.allocate_tensors()
        self.inp = self.i.get_input_details()[0]; self.out = self.i.get_output_details()[0]
        print("  tflite io", path.split("/")[-1], self.inp["shape"].tolist(), self.inp["dtype"].__name__, self.inp["quantization"],
              "->", self.out["shape"].tolist(), self.out["dtype"].__name__, self.out["quantization"], flush=True)

    def __call__(self, x):
        d = self.inp
        if d["dtype"] in (np.int8, np.uint8):
            sc, zp = d["quantization"]; x = np.clip(np.round(x / sc + zp), np.iinfo(d["dtype"]).min, np.iinfo(d["dtype"]).max).astype(d["dtype"])
        else:
            x = x.astype(d["dtype"])
        x = x[None]
        if list(d["shape"][1:]) == [3, INPUT, INPUT]:
            x = x.transpose(0, 3, 1, 2)
        self.i.set_tensor(d["index"], np.ascontiguousarray(x)); self.i.invoke()
        y = self.i.get_tensor(self.out["index"])
        if self.out["dtype"] in (np.int8, np.uint8):
            sc, zp = self.out["quantization"]; y = (y.astype(np.float32) - zp) * sc
        return y.astype(np.float32)


def decode(out, s, px, py, w, h, conf_thr, iou_thr=0.7, max_det=300):
    pred = out[0]
    if pred.shape[0] == 4 + NC: pred = pred.T
    if pred[:, :4].max() <= 2.0: pred = pred.copy(); pred[:, :4] *= INPUT  # TF exports emit normalized xywh
    sc = pred[:, 4:]; cls = sc.argmax(1); conf = sc[np.arange(len(cls)), cls]
    k = conf >= conf_thr; pred, cls, conf = pred[k], cls[k], conf[k]
    if not len(pred): return np.zeros((0, 4)), np.zeros(0), np.zeros(0, int), float(sc.max())
    cx, cy, bw, bh = pred[:, 0], pred[:, 1], pred[:, 2], pred[:, 3]
    b = np.stack([cx - bw / 2, cy - bh / 2, cx + bw / 2, cy + bh / 2], 1)
    b = np.clip((b - [px, py, px, py]) / s, 0, [w, h, w, h])
    keep = []
    for c in np.unique(cls):
        idx = np.where(cls == c)[0]; keep += [idx[j] for j in nms(b[idx], conf[idx], iou_thr)]
    keep = np.array(keep, int); keep = keep[conf[keep].argsort()[::-1]][:max_det]
    return b[keep], conf[keep], cls[keep], float(sc.max())


def ap(rec, prec):
    mrec = np.concatenate(([0.0], rec, [1.0])); mpre = np.concatenate(([1.0], prec, [0.0]))
    mpre = np.flip(np.maximum.accumulate(np.flip(mpre)))
    x = np.linspace(0, 1, 101)
    return np.trapezoid(np.interp(x, mrec, mpre), x)


def map_scores(stats, n_gt):
    tps, confs, pcls = [np.concatenate(z) if z else np.zeros((0,)) for z in zip(*stats)] if stats else ([], [], [])
    iouv = np.linspace(0.5, 0.95, 10)
    aps = np.zeros((NC, 10))
    o = np.argsort(-confs); tps, confs, pcls = tps[o], confs[o], pcls[o]
    for c in range(NC):
        m = pcls == c; ng = n_gt[c]
        if ng == 0 or m.sum() == 0: continue
        tpc = tps[m].cumsum(0); fpc = (1 - tps[m]).cumsum(0)
        for j in range(10):
            aps[c, j] = ap(tpc[:, j] / ng, tpc[:, j] / (tpc[:, j] + fpc[:, j]))
    valid = [c for c in range(NC) if n_gt[c] > 0]
    return float(aps[valid, 0].mean()), float(aps[valid].mean()), {c: round(float(aps[c, 0]), 4) for c in valid}


def match(pb, pc, gb, gc):
    iouv = np.linspace(0.5, 0.95, 10); tp = np.zeros((len(pb), 10), bool)
    if not len(pb) or not len(gb): return tp
    io = iou_mat(gb, pb)
    for j, t in enumerate(iouv):
        x = np.argwhere((io >= t) & (gc[:, None] == pc[None, :]))
        if len(x):
            m = np.concatenate((x, io[x[:, 0], x[:, 1]][:, None]), 1)
            m = m[m[:, 2].argsort()[::-1]]
            m = m[np.unique(m[:, 1], return_index=True)[1]]
            m = m[np.unique(m[:, 0], return_index=True)[1]]
            tp[m[:, 1].astype(int), j] = True
    return tp


def main():
    root, lat_csv, out_json = sys.argv[1:4]
    models = [a.split("=", 1) for a in sys.argv[4:]]
    src = {"6k": os.path.join(root, "6k/test"), "9k": os.path.join(root, "Images/test")}
    files = {k: sorted(os.listdir(os.path.join(v, "images"))) for k, v in src.items()}
    items, missing, ambiguous = [], 0, 0
    stride = int(os.environ.get("STRIDE", "1"))
    for r in list(csv.DictReader(open(lat_csv, encoding="utf-8-sig")))[::stride]:
        base = r["image"].replace("\\", "/").split("/")[-1]
        m = re.match(r"^([0-9a-z]+)_[0-9a-f]{12}_(.*)\.jpg$", base)
        stem = m.group(2)
        hits = [f for f in files[m.group(1)] if f.startswith(stem)]
        if len(hits) == 1:
            items.append((hits[0], src[m.group(1)]))
        elif not hits:
            missing += 1
        else:
            ambiguous += 1
    print(f"test list matched {len(items)}, missing {missing}, ambiguous {ambiguous}", flush=True)

    proc = psutil.Process(); loaded = []
    for label, path in models:
        before = proc.memory_info().rss; t = time.perf_counter()
        m = TfliteModel(path) if path.endswith(".tflite") else OnnxModel(path)
        lt = time.perf_counter() - t; m(np.zeros((INPUT, INPUT, 3), np.float32))  # warm-up
        loaded.append(dict(label=label, path=path, m=m, load_s=lt, rss_mb=(proc.memory_info().rss - before) / 2**20,
                           size_mb=os.path.getsize(path) / 2**20, stats=[], op=[], lat=[], top=[]))
        print(f"loaded {label} in {lt:.2f}s", flush=True)

    n_gt = np.zeros(NC, int); gts = []
    for k, (n, d) in enumerate(items):
        img = ImageOps.exif_transpose(Image.open(os.path.join(d, "images", n))).convert("RGB"); w, h = img.size
        g = []
        lp = os.path.join(d, "labels", os.path.splitext(n)[0] + ".txt")
        for line in (open(lp).read().split("\n") if os.path.exists(lp) else []):
            p = line.split()
            if len(p) >= 5 and int(p[0]) in REMAP:
                c = REMAP[int(p[0])]; x, y, bw, bh = map(float, p[1:5])
                g.append([c, (x - bw / 2) * w, (y - bh / 2) * h, (x + bw / 2) * w, (y + bh / 2) * h])
        g = np.array(g).reshape(-1, 5); gc = g[:, 0].astype(int); gb = g[:, 1:]
        for c in gc: n_gt[c] += 1
        gts.append(set(gc.tolist()))
        x, s, px, py = letterbox(img)
        for L in loaded:
            t = time.perf_counter(); out = L["m"](x); L["lat"].append(time.perf_counter() - t)
            b, cf, cl, top = decode(out, s, px, py, w, h, 0.001)
            L["stats"].append((match(b, cl, gb, gc), cf, cl))
            ob, oc, ocl, _ = decode(out, s, px, py, w, h, 0.40, iou_thr=0.45)  # app REPORT_CONF / IOU_THRESHOLD
            L["op"].append((ob, oc, ocl, gb, gc)); L["top"].append(top)
        if k % 100 == 0: print(k, flush=True)

    res = {"images": len(items), "gt_boxes_per_class": n_gt.tolist(), "models": []}
    ref = loaded[0]
    for L in loaded:
        m50, m5095, per = map_scores(L["stats"], n_gt)
        tp = fp = fn = 0; agree = 0
        for i, (ob, oc, ocl, gb, gc) in enumerate(L["op"]):
            t = match(ob, ocl, gb, gc)[:, 0]; tp += int(t.sum()); fp += int((~t).sum()); fn += len(gb) - int(t.sum())
            mine = set(ocl.tolist()); theirs = set(ref["op"][i][2].tolist()); agree += mine == theirs
        lat = np.array(L["lat"]) * 1000
        res["models"].append(dict(label=L["label"], file=os.path.basename(L["path"]), size_mb=round(L["size_mb"], 1),
            load_s=round(L["load_s"], 3), rss_mb=round(L["rss_mb"], 1), mAP50=round(m50, 4), mAP50_95=round(m5095, 4),
            ap50_per_class=per, precision_at_0_40=round(tp / max(tp + fp, 1), 4), recall_at_0_40=round(tp / max(tp + fn, 1), 4),
            same_classes_as_reference_at_0_40=round(agree / len(items), 4),
            latency_ms_median=round(float(np.median(lat)), 1), latency_ms_p95=round(float(np.percentile(lat, 95)), 1)))
        print(json.dumps(res["models"][-1]), flush=True)
    json.dump(res, open(out_json, "w"), indent=2)


if __name__ == "__main__":
    main()
