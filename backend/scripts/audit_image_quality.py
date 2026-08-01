"""Rank catalogue photographs worst-first, so reshooting starts where it pays.

Nothing here changes an image. It measures them and sorts them, because the
useful question is not "is this photo good" but "which fifty should I redo
first with the camera I already own".

Six things are measured, each one a way a product photo actually fails on a
phone screen:

  small        the long side is short enough that the card renders it soft
  soft         low edge energy — out of focus, or upscaled from a thumbnail
  flat         little contrast, the washed-out look of a flash-lit shelf
  dark / blown badly exposed either way
  lost         the pack occupies a small part of the frame, so it reads tiny
  crushed      very few bytes per pixel, i.e. JPEG artefacts around the text
  awkward      an aspect ratio that will letterbox badly in a square card

Sharpness is measured after resizing every image to the same width. Edge
energy scales with resolution, so without that a big blurry photo scores
better than a small sharp one, which is backwards.

    python scripts/audit_image_quality.py

Writes image_quality.csv for working through, and image_quality.html to look
at — worst first, with the reasons on each card.
"""
import asyncio
import csv
import html
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import cv2  # noqa: E402
import numpy as np  # noqa: E402

from database import products_collection  # noqa: E402
from storage import STATIC_DIR  # noqa: E402

IMAGES_DIR = STATIC_DIR / "images"
CSV_OUT = Path("image_quality.csv")
HTML_OUT = Path("image_quality.html")

# Each threshold is a point where the flaw becomes visible on a product card,
# not a point where the number looks bad.
MIN_LONG_SIDE = 500
SOFT_BELOW = 90.0        # variance of Laplacian at a normalised 512px width
FLAT_BELOW = 38.0        # standard deviation of luminance
DARK_BELOW, BLOWN_ABOVE = 62.0, 224.0
LOST_BELOW = 0.22        # fraction of the frame the pack occupies
CRUSHED_BELOW = 0.075    # bytes per pixel
AWKWARD_RATIO = 2.2


def _subject_fill(gray: np.ndarray) -> float:
    """Roughly how much of the frame the product occupies.

    Background is taken as the modal border value, so this works whether the
    shot is on white, on wood, or on a shop counter.
    """
    h, w = gray.shape
    border = np.concatenate([gray[:4].ravel(), gray[-4:].ravel(),
                             gray[:, :4].ravel(), gray[:, -4:].ravel()])
    bg = float(np.median(border))
    mask = (np.abs(gray.astype(np.int16) - bg) > 22).astype(np.uint8)
    mask = cv2.morphologyEx(mask, cv2.MORPH_CLOSE,
                            cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (9, 9)))
    n, labels, stats, _ = cv2.connectedComponentsWithStats(mask, 8)
    if n <= 1:
        return float(mask.mean())
    return float(stats[1:, cv2.CC_STAT_AREA].max() / (h * w))


def measure(path: Path) -> dict | None:
    img = cv2.imread(str(path))
    if img is None:
        return None
    h, w = img.shape[:2]
    gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)

    scale = 512 / max(h, w)
    norm = cv2.resize(gray, None, fx=scale, fy=scale, interpolation=cv2.INTER_AREA) if scale < 1 else gray
    sharpness = float(cv2.Laplacian(norm, cv2.CV_64F).var())

    bytes_px = path.stat().st_size / (w * h)
    ratio = max(w / h, h / w)
    fill = _subject_fill(gray)

    reasons = []
    if max(w, h) < MIN_LONG_SIDE:
        reasons.append(f"small ({w}x{h})")
    if sharpness < SOFT_BELOW:
        reasons.append(f"soft ({sharpness:.0f})")
    if float(gray.std()) < FLAT_BELOW:
        reasons.append("flat")
    if float(gray.mean()) < DARK_BELOW:
        reasons.append("dark")
    elif float(gray.mean()) > BLOWN_ABOVE:
        reasons.append("blown out")
    if fill < LOST_BELOW:
        reasons.append(f"pack fills {fill:.0%}")
    if bytes_px < CRUSHED_BELOW:
        reasons.append("heavily compressed")
    if ratio > AWKWARD_RATIO:
        reasons.append(f"awkward shape ({ratio:.1f}:1)")

    # Weighted so the flaws you cannot design around cost most. A soft or tiny
    # photo is unfixable without reshooting; an awkward crop is a nuisance.
    score = (
        3.0 * (max(w, h) < MIN_LONG_SIDE)
        + 3.0 * (sharpness < SOFT_BELOW)
        + 2.0 * (fill < LOST_BELOW)
        + 1.5 * (float(gray.std()) < FLAT_BELOW)
        + 1.5 * (bytes_px < CRUSHED_BELOW)
        + 1.0 * (float(gray.mean()) < DARK_BELOW or float(gray.mean()) > BLOWN_ABOVE)
        + 0.5 * (ratio > AWKWARD_RATIO)
    )
    return {
        "file": path.name, "w": w, "h": h, "sharpness": round(sharpness, 1),
        "contrast": round(float(gray.std()), 1), "brightness": round(float(gray.mean()), 1),
        "fill": round(fill, 3), "bytes_px": round(bytes_px, 4),
        "score": score, "reasons": reasons,
    }


async def main() -> None:
    files = sorted(IMAGES_DIR.glob("*.jpg")) + sorted(IMAGES_DIR.glob("*.png"))
    print(f"measuring {len(files)} images\n", flush=True)

    rows = []
    for i, f in enumerate(files, 1):
        m = measure(f)
        if m:
            rows.append(m)
        if i % 200 == 0:
            print(f"  {i}/{len(files)}", flush=True)

    # Which products each file is actually used by — a bad photo shared by six
    # products is six bad cards, and should be reshot before a one-off.
    used_by: dict[str, list[str]] = {}
    async for p in products_collection.find(
        {"image_url": {"$nin": ["", None]}}, {"name": 1, "image_url": 1, "category": 1}
    ):
        used_by.setdefault(p["image_url"], []).append(p.get("name", ""))

    for r in rows:
        names = used_by.get(r["file"], [])
        r["products"] = names
        r["uses"] = len(names)
        r["category"] = ""
        r["score"] += 0.4 * max(0, len(names) - 1)  # shared photos matter more

    rows.sort(key=lambda r: (-r["score"], -r["uses"], r["file"]))
    bad = [r for r in rows if r["reasons"]]

    with CSV_OUT.open("w", newline="", encoding="utf-8") as fh:
        wr = csv.writer(fh)
        wr.writerow(["file", "score", "used_by", "width", "height", "sharpness",
                     "contrast", "brightness", "fill", "bytes_per_px", "problems", "products"])
        for r in bad:
            wr.writerow([r["file"], r["score"], r["uses"], r["w"], r["h"], r["sharpness"],
                         r["contrast"], r["brightness"], r["fill"], r["bytes_px"],
                         "; ".join(r["reasons"]), " | ".join(r["products"][:6])])

    _write_sheet(bad[:150], len(rows), len(bad))

    print(f"\n{len(rows)} measured, {len(bad)} have at least one problem\n")
    import re as _re
    tally: dict[str, int] = {}
    for r in bad:
        for reason in r["reasons"]:
            # Group by the kind of problem, not the measurement: "pack fills
            # 18%" and "pack fills 21%" are one line in a summary, not two.
            kind = _re.sub(r"\s*\(.*\)$|\s+\d+%$", "", reason)
            tally[kind] = tally.get(kind, 0) + 1
    for k, v in sorted(tally.items(), key=lambda x: -x[1]):
        print(f"  {k:<20} {v}")
    print(f"\nfull list: {CSV_OUT}   worst 150 to look at: {HTML_OUT}")


def _write_sheet(rows: list, total: int, bad: int) -> None:
    import base64

    cards = []
    for r in rows:
        uri = "data:image/jpeg;base64," + base64.b64encode((IMAGES_DIR / r["file"]).read_bytes()).decode("ascii")
        tags = "".join(f'<span class="tag">{html.escape(x)}</span>' for x in r["reasons"])
        used = f'<span class="uses">used by {r["uses"]} products</span>' if r["uses"] > 1 else ""
        cards.append(f"""
<div class="card">
  <img src="{uri}" alt="">
  <div class="meta">
    <div class="file">{html.escape(r['file'])} {used}</div>
    <div class="prod">{html.escape(' · '.join(r['products'][:3]) or '(not used by any product)')}</div>
    <div>{tags}</div>
    <div class="nums">{r['w']}x{r['h']} · sharp {r['sharpness']} · contrast {r['contrast']} · fills {r['fill']:.0%}</div>
  </div>
</div>""")

    HTML_OUT.write_text(f"""<!doctype html><meta charset="utf-8">
<title>Photo quality — worst {len(rows)}</title>
<style>
 body{{font:14px system-ui;margin:24px;background:#fafafa}}
 h1{{font-size:18px;margin-bottom:4px}} .sub{{color:#666;margin-bottom:16px}}
 .grid{{display:grid;grid-template-columns:repeat(auto-fill,minmax(300px,1fr));gap:14px}}
 .card{{background:#fff;border:1px solid #ddd;border-radius:8px;padding:12px}}
 .card img{{width:100%;height:180px;object-fit:contain;background:#f4f4f4;border-radius:4px}}
 .file{{font-weight:600;font-size:12px;margin-top:8px;word-break:break-all}}
 .prod{{color:#555;font-size:12px;margin:3px 0 6px}}
 .tag{{display:inline-block;background:#ffebee;color:#c62828;border-radius:4px;padding:2px 6px;font-size:11px;margin:2px 3px 0 0}}
 .uses{{background:#e3f2fd;color:#1565c0;border-radius:4px;padding:1px 5px;font-size:11px;font-weight:400}}
 .nums{{color:#999;font-size:11px;margin-top:6px}}
</style>
<h1>The {len(rows)} worst photographs</h1>
<div class="sub">{bad} of {total} images have at least one problem. Ranked worst first; photos used by
several products are pushed up, since one bad file is several bad cards. Full list in image_quality.csv.</div>
<div class="grid">{''.join(cards)}</div>""", encoding="utf-8")


if __name__ == "__main__":
    asyncio.run(main())
