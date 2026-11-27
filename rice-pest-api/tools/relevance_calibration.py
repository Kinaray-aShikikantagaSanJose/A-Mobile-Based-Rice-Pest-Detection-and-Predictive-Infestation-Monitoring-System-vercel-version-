"""Plant-colour fraction on groups of images (calibration for the relevance screen).
Usage: python -I relevance_calib.py label=dir_or_glob ...   (prints percentiles per group)"""
import glob, os, sys
import numpy as np
from PIL import Image, ImageOps

H_MIN, H_MAX, S_MIN, V_MIN = 25, 120, 46, 31  # PIL HSV units (0-255): hue 35-170 deg, S>=0.18, V>=0.12


def plant_fraction(img):
    g = img.convert("RGB"); g.thumbnail((256, 256))
    hsv = np.asarray(g.convert("HSV"), dtype=np.int16)
    h, s, v = hsv[..., 0], hsv[..., 1], hsv[..., 2]
    return float(((h >= H_MIN) & (h <= H_MAX) & (s >= S_MIN) & (v >= V_MIN)).mean())


for arg in sys.argv[1:]:
    label, pat = arg.split("=", 1)
    files = sorted(glob.glob(os.path.join(pat, "*")) if os.path.isdir(pat) else glob.glob(pat))
    files = [f for f in files if f.lower().endswith((".jpg", ".jpeg", ".png", ".webp"))]
    if "STRIDE" in os.environ:
        files = files[::int(os.environ["STRIDE"])]
    vals = []
    for f in files:
        try:
            vals.append((plant_fraction(ImageOps.exif_transpose(Image.open(f))), os.path.basename(f)))
        except Exception as e:
            print("  skip", f, e)
    vals.sort()
    a = np.array([v for v, _ in vals])
    print(f"{label}: n={len(a)} min={a.min():.3f} p5={np.percentile(a,5):.3f} p25={np.percentile(a,25):.3f} "
          f"median={np.median(a):.3f} max={a.max():.3f}")
    print("   lowest:", ", ".join(f"{n}={v:.3f}" for v, n in vals[:5]))
