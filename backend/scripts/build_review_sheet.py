"""Rebuild the image review sheet with the thumbnails embedded.

The first version linked straight to Open Food Facts, and loading 364 remote
images at once meant their CDN throttled the burst — most cards showed no
picture, which makes the sheet useless for judging photos.

Each thumbnail is fetched once, shrunk, and embedded in the HTML, so the file
opens instantly, works offline, and can be sent around as a single file.
"""
import base64
import io
import json
import sys
import time
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import html as html_mod  # noqa: E402

from PIL import Image  # noqa: E402

import argparse

PROPOSALS = Path("image_proposals.json")
OUT = Path("review.html")
UA = "DhanamStore/1.0 (alfreddhanam@gmail.com) catalogue image matching"
THUMB = (150, 150)


def thumbnail(url: str) -> str | None:
    """Fetch and shrink one image to an inline data URI."""
    try:
        req = urllib.request.Request(url, headers={"User-Agent": UA})
        with urllib.request.urlopen(req, timeout=25) as r:
            raw = r.read()
        im = Image.open(io.BytesIO(raw))
        im.load()
        if im.mode not in ("RGB", "L"):
            im = im.convert("RGB")
        im.thumbnail(THUMB, Image.LANCZOS)
        buf = io.BytesIO()
        im.save(buf, "JPEG", quality=72, optimize=True)
        return "data:image/jpeg;base64," + base64.b64encode(buf.getvalue()).decode()
    except Exception:
        return None


def main() -> None:
    global PROPOSALS, OUT
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--file", help="proposals JSON to render")
    ap.add_argument("--out", help="HTML file to write")
    args = ap.parse_args()
    if args.file:
        PROPOSALS = Path(args.file)
    if args.out:
        OUT = Path(args.out)

    proposals = json.loads(PROPOSALS.read_text(encoding="utf-8"))
    print(f"fetching {len(proposals)} thumbnails\n")

    cards, embedded, failed = [], 0, 0
    for i, p in enumerate(proposals, 1):
        uri = thumbnail(p["image_url"])
        if uri:
            embedded += 1
        else:
            failed += 1
        if i % 50 == 0:
            print(f"  {i}/{len(proposals)}", flush=True)

        img = (f'<img src="{uri}" alt="">' if uri
               else '<div class="noimg">no preview</div>')
        cards.append(f"""
<label class="card">
  <input type="checkbox" checked value="{html_mod.escape(p['product_id'])}">
  {img}
  <div class="names">
    <div class="ours">{html_mod.escape(p['our_name'])}</div>
    <div class="theirs">{html_mod.escape(p['their_name'])} <span>{html_mod.escape(p['brands'])}</span></div>
  </div>
</label>""")
        time.sleep(0.15)

    OUT.write_text(f"""<!doctype html><meta charset="utf-8">
<title>Image proposals — {len(proposals)}</title>
<style>
 body{{font:14px system-ui;margin:0;background:#fafafa;color:#111}}
 .bar{{position:sticky;top:0;background:#fff;padding:14px 20px;border-bottom:1px solid #ddd;
       display:flex;gap:12px;align-items:center;flex-wrap:wrap;z-index:5}}
 .bar b{{font-size:15px}} .hint{{color:#666}}
 button{{padding:8px 14px;font-size:14px;cursor:pointer;border:1px solid #bbb;background:#fff;border-radius:6px}}
 button.primary{{background:#0d47a1;color:#fff;border-color:#0d47a1;font-weight:600}}
 #count{{margin-left:auto;font-weight:600}}
 .grid{{display:grid;grid-template-columns:repeat(auto-fill,minmax(300px,1fr));gap:10px;padding:16px 20px}}
 .card{{background:#fff;border:1px solid #ddd;border-radius:8px;padding:10px;display:flex;
        gap:10px;align-items:center;cursor:pointer}}
 .card:has(input:not(:checked)){{opacity:.4;background:#f0f0f0}}
 input{{width:18px;height:18px;flex:none}}
 img,.noimg{{width:72px;height:72px;object-fit:contain;background:#fff;flex:none;border:1px solid #eee;border-radius:4px}}
 .noimg{{display:flex;align-items:center;justify-content:center;color:#aaa;font-size:11px;text-align:center}}
 .ours{{font-weight:600;line-height:1.25}}
 .theirs{{color:#666;font-size:12.5px;margin-top:2px}} .theirs span{{color:#999}}
</style>
<div class="bar">
  <b>{len(proposals)} proposed photos</b>
  <span class="hint">Untick a photo if it is the wrong product, or too poor quality to show a customer.</span>
  <button class="primary" onclick="save()">Save approved list</button>
  <button onclick="setAll(true)">Tick all</button>
  <button onclick="setAll(false)">Untick all</button>
  <span id="count"></span>
</div>
<div class="grid">{''.join(cards)}</div>
<script>
 const boxes=[...document.querySelectorAll('input')];
 const tally=()=>document.getElementById('count').textContent =
   boxes.filter(b=>b.checked).length + ' of {len(proposals)} kept';
 boxes.forEach(b=>b.addEventListener('change',tally));
 function setAll(v){{boxes.forEach(b=>b.checked=v);tally();}}
 function save(){{
   const ids=boxes.filter(b=>b.checked).map(b=>b.value).join('\\n');
   const a=document.createElement('a');
   a.href=URL.createObjectURL(new Blob([ids],{{type:'text/plain'}}));
   a.download='approved.txt'; a.click();
 }}
 tally();
</script>""", encoding="utf-8")

    size = OUT.stat().st_size / 1024 / 1024
    print(f"\n{embedded} thumbnails embedded, {failed} unavailable")
    print(f"wrote {OUT} ({size:.1f} MB) — opens instantly, no network needed")


if __name__ == "__main__":
    main()
