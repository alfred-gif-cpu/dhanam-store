"""Propose product images from Open Food Facts, for review before use.

Open Food Facts publishes product photos under open Creative Commons
licences, so unlike search-engine results they can legitimately be reused.
Coverage of a Tamil Nadu grocery is partial — many local brands are simply
not in the database.

Matching is by product name, and name matching is unreliable in a way that
matters: a measured sample proposed "Himalaya Baby Powder" for a baby
shampoo and a snack called "Lunch Box Sticks" for a lunch box. A wrong photo
is worse than the placeholder, because the customer orders the wrong thing.

Nothing is therefore applied automatically. The run writes a contact sheet
you tick through, and only ticked products are downloaded.

    python scripts/fetch_open_images.py --propose        # search, build review.html
    # open review.html, untick anything wrong, save the approved list
    python scripts/fetch_open_images.py --apply approved.txt

Attribution: images are CC-BY-SA. The uploader is recorded on each product in
image_credit, and that credit must appear somewhere in the app or site.
"""
import argparse
import asyncio
import html
import json
import re
import sys
import urllib.parse
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from PIL import Image  # noqa: E402
import io  # noqa: E402

from database import products_collection  # noqa: E402
from search_utils import BRAND_SYNONYMS, normalize  # noqa: E402
from storage import STATIC_DIR  # noqa: E402

SEARCH_URL = "https://search.openfoodfacts.org/search"
UA = "DhanamStore/1.0 (alfreddhanam@gmail.com) catalogue image matching"
IMAGES_DIR = STATIC_DIR / "images"
PROPOSALS = Path("image_proposals.json")
REVIEW_HTML = Path("review.html")
SEARCHED = Path("image_search_done.txt")  # product ids already searched

# Expand the catalogue's abbreviations so the search sees the real brand name.
EXPAND = {alias: full for full, aliases in BRAND_SYNONYMS.items() for alias in aliases}
PACK_SIZE = re.compile(r"\b(\d+\s*(g|kg|ml|l|gm|rs|pc|pcs)\b|\d+rs|\(s\)|\d+\+\d+)", re.I)

# Below this, matches were wrong more often than right in sampling.
MIN_SCORE = 0.75


def query_for(name: str) -> str:
    words = [EXPAND.get(w, w) for w in re.sub(r"[^a-z0-9 ]", " ", name.lower()).split()]
    return " ".join(PACK_SIZE.sub(" ", " ".join(words)).split())[:60]


def _search(q: str) -> list:
    url = f"{SEARCH_URL}?" + urllib.parse.urlencode({"q": q, "page_size": 5})
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.loads(r.read().decode("utf-8")).get("hits", [])


def _score(mine: str, theirs: str) -> float:
    words = [w for w in query_for(mine).split() if len(w) > 2]
    if not words:
        return 0.0
    hay = normalize(theirs)
    return sum(1 for w in words if w in hay) / len(words)


async def propose(limit: int, delay: float) -> None:
    todo = []
    async for p in products_collection.find(
        {"$or": [{"image_url": ""}, {"image_url": {"$exists": False}}]},
        {"name": 1, "category": 1, "slug": 1},
    ):
        todo.append(p)

    # A full pass takes the best part of an hour, which is long enough that a
    # laptop lid will close on it. Everything is written as it goes and
    # already-searched products are skipped, so a re-run picks up where it
    # stopped instead of starting over.
    seen = set()
    if SEARCHED.exists():
        seen = {ln.strip() for ln in SEARCHED.read_text(encoding="utf-8").splitlines() if ln.strip()}
    proposals = []
    if PROPOSALS.exists():
        try:
            proposals = json.loads(PROPOSALS.read_text(encoding="utf-8"))
        except Exception:
            proposals = []

    remaining = [p for p in todo if str(p["_id"]) not in seen][:limit]
    if seen:
        print(f"resuming: {len(seen)} already searched, {len(proposals)} proposals kept")
    print(f"searching Open Food Facts for {len(remaining)} products "
          f"(~{len(remaining)*delay/60:.0f} min at {delay}s between calls)", flush=True)
    print("safe to interrupt — progress is saved after every product\n", flush=True)
    todo = remaining
    for i, p in enumerate(todo, 1):
        name = p.get("name", "")
        try:
            hits = _search(query_for(name))
        except Exception as e:
            print(f"  [{i}/{len(todo)}] error {type(e).__name__} on {name[:34]}", flush=True)
            await asyncio.sleep(delay * 2)
            continue

        best, best_score = None, 0.0
        for h in hits:
            if not h.get("image_front_url"):
                continue
            s = _score(name, f"{h.get('product_name') or ''} {' '.join(h.get('brands') or [])}")
            if s > best_score:
                best, best_score = h, s

        if best and best_score >= MIN_SCORE:
            proposals.append({
                "product_id": str(p["_id"]),
                "our_name": name,
                "category": p.get("category", ""),
                "their_name": best.get("product_name") or "",
                "brands": ", ".join(best.get("brands") or []),
                "image_url": best["image_front_url"],
                "code": best.get("code", ""),
                "score": round(best_score, 2),
            })
            print(f"  [{i}/{len(todo)}] {best_score:.2f} {name[:32]:<34} -> {(best.get('product_name') or '')[:34]}", flush=True)

        # Persist after each product so an interrupted run loses at most one.
        with SEARCHED.open("a", encoding="utf-8") as fh:
            fh.write(str(p["_id"]) + "\n")
        if i % 10 == 0 or best:
            PROPOSALS.write_text(json.dumps(proposals, indent=1, ensure_ascii=False), encoding="utf-8")
        await asyncio.sleep(delay)

    PROPOSALS.write_text(json.dumps(proposals, indent=1, ensure_ascii=False), encoding="utf-8")
    _write_review(proposals)
    print(f"\n{len(proposals)} proposals written to {PROPOSALS}")
    print(f"Open {REVIEW_HTML} — every match is shown with the photo. Untick the wrong")
    print("ones (there will be some), save the approved list, then run --apply on it.")


def _write_review(proposals: list) -> None:
    cards = []
    for p in proposals:
        cards.append(f"""
<label class="card">
  <input type="checkbox" checked value="{html.escape(p['product_id'])}">
  <img src="{html.escape(p['image_url'])}" loading="lazy" alt="">
  <div class="names">
    <div class="ours">{html.escape(p['our_name'])}</div>
    <div class="theirs">{html.escape(p['their_name'])} <span>{html.escape(p['brands'])}</span></div>
    <div class="score">match {p['score']}</div>
  </div>
</label>""")

    REVIEW_HTML.write_text(f"""<!doctype html><meta charset="utf-8">
<title>Image proposals — {len(proposals)}</title>
<style>
 body{{font:14px system-ui;margin:24px;background:#fafafa}}
 h1{{font-size:18px}} .bar{{position:sticky;top:0;background:#fafafa;padding:12px 0;border-bottom:1px solid #ddd}}
 button{{padding:8px 14px;font-size:14px;cursor:pointer}}
 .grid{{display:grid;grid-template-columns:repeat(auto-fill,minmax(260px,1fr));gap:12px;margin-top:16px}}
 .card{{background:#fff;border:1px solid #ddd;border-radius:8px;padding:10px;display:flex;gap:10px;align-items:flex-start;cursor:pointer}}
 .card:has(input:not(:checked)){{opacity:.35;background:#f3f3f3}}
 img{{width:76px;height:76px;object-fit:contain;background:#fff;flex:none}}
 .ours{{font-weight:600}} .theirs{{color:#555;font-size:13px}} .theirs span{{color:#888}}
 .score{{color:#888;font-size:12px;margin-top:3px}}
</style>
<h1>{len(proposals)} proposed images</h1>
<div class="bar">
  Untick anything where the photo does not match the product on the left.
  <button onclick="save()">Save approved list</button>
  <button onclick="document.querySelectorAll('input').forEach(i=>i.checked=false)">Untick all</button>
</div>
<div class="grid">{''.join(cards)}</div>
<script>
function save() {{
  const ids=[...document.querySelectorAll('input:checked')].map(i=>i.value).join('\\n');
  const a=document.createElement('a');
  a.href=URL.createObjectURL(new Blob([ids],{{type:'text/plain'}}));
  a.download='approved.txt'; a.click();
}}
</script>""", encoding="utf-8")


async def apply(approved_file: str) -> None:
    ids = {line.strip() for line in Path(approved_file).read_text(encoding="utf-8").splitlines() if line.strip()}
    proposals = {p["product_id"]: p for p in json.loads(PROPOSALS.read_text(encoding="utf-8"))}
    chosen = [proposals[i] for i in ids if i in proposals]
    print(f"{len(chosen)} approved of {len(proposals)} proposed\n")

    from bson import ObjectId
    saved = 0
    for p in chosen:
        slug = re.sub(r"[^a-z0-9]+", "-", p["our_name"].lower()).strip("-")

        # The search returns a 400px preview. The original upload sits at the
        # same path with "full" in place of the size, and is usually 1500px or
        # more — worth having, since a 400px image looks soft on a phone's
        # product page. Falls back to the preview if there is no original.
        candidates = [p["image_url"].replace(".400.jpg", ".full.jpg"), p["image_url"]]

        # The image CDN throttles a fast burst — an unpaced run downloaded 62
        # files and then failed the remaining 192. Pace the requests and back
        # off on refusal rather than skipping the product.
        raw = None
        for url in candidates:
            for attempt in range(3):
                try:
                    req = urllib.request.Request(url, headers={"User-Agent": UA})
                    with urllib.request.urlopen(req, timeout=45) as r:
                        raw = r.read()
                    break
                except Exception:
                    await asyncio.sleep(2 * (attempt + 1))
            if raw is not None:
                break
        if raw is None:
            print(f"  failed {p['our_name'][:34]}: could not download", flush=True)
            continue

        try:
            im = Image.open(io.BytesIO(raw))
            im.load()
            if im.mode not in ("RGB", "L"):
                im = im.convert("RGB")
            source_w = im.size[0]
            im.thumbnail((1000, 1000), Image.LANCZOS)
            buf = io.BytesIO()
            im.save(buf, "JPEG", quality=88, optimize=True, progressive=True)
            (IMAGES_DIR / f"{slug}.jpg").write_bytes(buf.getvalue())
        except Exception as e:
            print(f"  failed {p['our_name'][:34]}: {type(e).__name__}", flush=True)
            continue

        await products_collection.update_one(
            {"_id": ObjectId(p["product_id"])},
            {"$set": {
                "image_url": f"{slug}.jpg",
                # CC-BY-SA requires attribution; keep the source with the product.
                "image_credit": f"Open Food Facts ({p['code']}), CC-BY-SA",
            }},
        )
        saved += 1
        print(f"  saved {slug}.jpg  ({source_w}px source -> {im.size[0]}x{im.size[1]})", flush=True)
        await asyncio.sleep(0.4)  # stay under the image CDN's burst limit

    print(f"\n{saved} images downloaded into {IMAGES_DIR}")
    print("These are CC-BY-SA: credit Open Food Facts somewhere in the app or site.")
    print("Commit the new files so they deploy with the next push.")


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--propose", action="store_true", help="search and build the review sheet")
    ap.add_argument("--limit", type=int, default=400, help="how many products to search (default 400)")
    ap.add_argument("--delay", type=float, default=1.2, help="seconds between searches")
    ap.add_argument("--apply", metavar="APPROVED_TXT", help="download the approved images")
    args = ap.parse_args()

    if args.apply:
        asyncio.run(apply(args.apply))
    elif args.propose:
        asyncio.run(propose(args.limit, args.delay))
    else:
        ap.print_help()


if __name__ == "__main__":
    main()
