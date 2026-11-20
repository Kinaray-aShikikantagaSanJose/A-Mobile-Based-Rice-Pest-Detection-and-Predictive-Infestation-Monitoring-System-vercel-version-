"""Counts training images and labelled boxes per class in a YOLO dataset.

The model's dataset is not stored in this project (it was trained on Colab
from /content/data.yaml). Run this on the dataset folder to fill in the
"Training images per class" table in docs/model-classes-and-guide.md:

    python tools/count_dataset.py path/to/data.yaml
    python tools/count_dataset.py path/to/data.yaml --markdown

It reads `path`, `train`, `val`, `test` and `names` from data.yaml, then
for each split counts, per class: images that contain at least one box of
that class, and the number of boxes (insects). Images with no label file or
an empty one are counted as background images.
"""
import os
import sys
from collections import Counter

IMAGE_EXT = {".jpg", ".jpeg", ".png", ".bmp", ".webp"}


def read_yaml(path: str) -> dict:
    """Just enough YAML for data.yaml (no PyYAML needed)."""
    out = {}
    for line in open(path, encoding="utf-8"):
        line = line.split("#", 1)[0].rstrip()
        if ":" not in line:
            continue
        key, value = line.split(":", 1)
        value = value.strip()
        if value.startswith("["):
            out[key.strip()] = [v.strip().strip("'\"") for v in value.strip("[]").split(",") if v.strip()]
        else:
            out[key.strip()] = value.strip("'\"")
    return out


def label_dir_for(image_dir: str) -> str:
    # YOLO convention: .../images/... -> .../labels/...
    parts = image_dir.replace("\\", "/").split("/")
    for i in range(len(parts) - 1, -1, -1):
        if parts[i] == "images":
            parts[i] = "labels"
            return "/".join(parts)
    return image_dir


def count_split(image_dir: str, names: list) -> tuple:
    images_with = Counter()
    boxes = Counter()
    total = background = 0
    labels = label_dir_for(image_dir)
    for root, _, files in os.walk(image_dir):
        for f in files:
            stem, ext = os.path.splitext(f)
            if ext.lower() not in IMAGE_EXT:
                continue
            total += 1
            rel = os.path.relpath(root, image_dir)
            label_path = os.path.join(labels, rel, stem + ".txt")
            seen = set()
            if os.path.exists(label_path):
                for row in open(label_path, encoding="utf-8"):
                    cols = row.split()
                    if not cols:
                        continue
                    k = int(float(cols[0]))
                    name = names[k] if 0 <= k < len(names) else f"class {k}"
                    boxes[name] += 1
                    seen.add(name)
            if not seen:
                background += 1
            for name in seen:
                images_with[name] += 1
    return total, background, images_with, boxes


def main(argv: list) -> None:
    if not argv:
        sys.exit(__doc__)
    data_yaml = argv[0]
    markdown = "--markdown" in argv
    cfg = read_yaml(data_yaml)
    names = cfg.get("names") or []
    base = os.path.join(os.path.dirname(os.path.abspath(data_yaml)), cfg.get("path", "."))
    rows = []
    for split in ("train", "val", "test"):
        if not cfg.get(split):
            continue
        image_dir = os.path.normpath(os.path.join(base, cfg[split]))
        if not os.path.isdir(image_dir):
            print(f"{split}: {image_dir} not found, skipped")
            continue
        rows.append((split, *count_split(image_dir, names)))

    if markdown:
        print("| Class | " + " | ".join(f"{s} images (boxes)" for s, *_ in rows) + " |")
        print("|---|" + "---|" * len(rows))
        for name in names:
            cells = [f"{imgs[name]} ({bx[name]})" for _, _, _, imgs, bx in rows]
            print(f"| {name} | " + " | ".join(cells) + " |")
        print("| background (no boxes) | " + " | ".join(str(bg) for _, _, bg, _, _ in rows) + " |")
        print("| **all images** | " + " | ".join(str(t) for _, t, _, _, _ in rows) + " |")
        return
    for split, total, bg, imgs, bx in rows:
        print(f"\n{split}: {total} images ({bg} with no boxes)")
        for name in names:
            print(f"  {name:20s} {imgs[name]:6d} images  {bx[name]:7d} boxes")


if __name__ == "__main__":
    main(sys.argv[1:])
