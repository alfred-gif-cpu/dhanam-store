"""Propose images for one brand's products, at a match bar you choose.

The catalogue-wide importer (`fetch_open_images.py`) searches everything at a
match score of 0.75, which is where a loose match stopped being right more
often than wrong across the whole catalogue. That bar is too strict when you
already know the brand: "Ponds Dreamflower Talc" against "Pond's Dream Flower
Talcum Powder" scores below it and is obviously the same product.

This runs the same search and scoring against a named brand only, at a lower
threshold, and writes to its own files so the pending catalogue-wide review
sheet is left alone.

    python scripts/fetch_brand_images.py --brand unilever --min-score 0.5
    # open brand_review.html, untick the wrong ones, save the approved list
    python scripts/fetch_brand_images.py --apply approved_brand.txt

Lowering the bar means more wrong matches reach the sheet, not fewer checks —
every proposal still has to be looked at. Images are CC-BY-SA and the credit
is recorded per product, the same as the catalogue-wide importer.
"""
import argparse
import asyncio
import html
import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
sys.path.insert(0, str(Path(__file__).resolve().parent))

from database import products_collection  # noqa: E402
import fetch_open_images as base  # noqa: E402

PROPOSALS = Path("brand_proposals.json")
REVIEW_HTML = Path("brand_review.html")
APPROVED_NAME = "approved_brand.txt"  # deliberately not approved.txt

# Brand families worth sweeping in one pass. The catalogue writes these in
# several forms, so match on word boundaries rather than substrings — "lux"
# should not catch "deluxe", and "glow" should not catch every face cream.
BRANDS = {
    "unilever": [
        "surf", "rin", "wheel", "lifebuoy", "lux", "dove", "ponds", "pond's",
        "vaseline", "sunsilk", "clinic plus", "closeup", "close up", "pepsodent",
        "bru", "red label", "taj mahal", "3 roses", "knorr", "kissan", "kwality",
        "horlicks", "boost", "comfort", "vim", "domex", "cif", "axe", "rexona",
        "tresemme", "lakme", "indulekha", "hamam", "liril", "breeze", "annapurna",
        "magnum", "brooke bond", "glow and lovely", "glow & lovely",
    ],
}


def _matcher(tokens: list[str]):
    pattern = "|".join(re.escape(t) for t in sorted(tokens, key=len, reverse=True))
    # The alternation must be grouped. Without the (?:...), `|` binds looser
    # than the lookarounds, so the boundary checks apply only to the first and
    # last token and everything between matches mid-word: "rin" inside "Drink",
    # "Bru" inside "Brunch", "lux" inside "Deluxe".
    return re.compile(rf"(?<![a-z])(?:{pattern})(?![a-z])", re.I)


async def propose(tokens: list[str], min_score: float, delay: float, limit: int) -> None:
    match = _matcher(tokens)
    todo = []
    async for p in products_collection.find(
        {"$or": [{"image_url": ""}, {"image_url": {"$exists": False}}]},
        {"name": 1, "category": 1},
    ):
        if match.search(p.get("name", "")):
            todo.append(p)
    todo = todo[:limit]

    print(f"{len(todo)} products without a photo match this brand")
    print(f"searching at min score {min_score} "
          f"(~{len(todo)*delay/60:.0f} min at {delay}s between calls)\n", flush=True)

    proposals, misses = [], 0
    for i, p in enumerate(todo, 1):
        name = p.get("name", "")
        source = base.SOURCE_BY_CATEGORY.get(p.get("category", ""), "food")
        try:
            hits = base._search(base.query_for(name), source)
        except Exception as e:
            print(f"  [{i}/{len(todo)}] error {type(e).__name__} on {name[:34]}", flush=True)
            await asyncio.sleep(delay * 2)
            continue

        best, best_score = None, 0.0
        for h in hits:
            if not h.get("image_front_url"):
                continue
            s = base._score(name, f"{h.get('product_name') or ''} {' '.join(h.get('brands') or [])}")
            if s > best_score:
                best, best_score = h, s

        if best and best_score >= min_score:
            proposals.append({
                "product_id": str(p["_id"]),
                "our_name": name,
                "category": p.get("category", ""),
                "their_name": best.get("product_name") or "",
                "brands": ", ".join(best.get("brands") or []),
                "image_url": best["image_front_url"],
                "code": best.get("code", ""),
                "source": source,
                "score": round(best_score, 2),
            })
            print(f"  [{i}/{len(todo)}] {best_score:.2f} {name[:32]:<34} -> {(best.get('product_name') or '')[:34]}", flush=True)
        else:
            misses += 1

        if i % 10 == 0:
            PROPOSALS.write_text(json.dumps(proposals, indent=1, ensure_ascii=False), encoding="utf-8")
        await asyncio.sleep(delay)

    PROPOSALS.write_text(json.dumps(proposals, indent=1, ensure_ascii=False), encoding="utf-8")
    _write_review(proposals, min_score)
    print(f"\n{len(proposals)} proposals, {misses} still with nothing")
    print(f"Open {REVIEW_HTML} — a lower bar means more wrong matches, so read every one.")
    print(f"Ticked ones save to {APPROVED_NAME}, then: --apply {APPROVED_NAME}")


def _write_review(proposals: list, min_score: float) -> None:
    cards = []
    for p in sorted(proposals, key=lambda x: x["score"]):
        # Weakest matches first: those are the ones that need a real look, and
        # putting them last means they get skimmed.
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
<title>Brand image proposals — {len(proposals)}</title>
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
 .warn{{background:#fff8e1;border:1px solid #ffe082;padding:10px;border-radius:8px;margin-top:10px}}
</style>
<h1>{len(proposals)} proposed images</h1>
<div class="bar">
  Untick anything where the photo does not match the product on the left.
  <button onclick="save()">Save approved list</button>
  <button onclick="document.querySelectorAll('input').forEach(i=>i.checked=false)">Untick all</button>
  <div class="warn">Matched down to {min_score}, below the catalogue-wide bar of {base.MIN_SCORE} —
  weakest matches are shown first because those are the ones that need a real look.</div>
</div>
<div class="grid">{''.join(cards)}</div>
<script>
function save() {{
  const ids=[...document.querySelectorAll('input:checked')].map(i=>i.value).join('\\n');
  const a=document.createElement('a');
  a.href=URL.createObjectURL(new Blob([ids],{{type:'text/plain'}}));
  a.download='{APPROVED_NAME}'; a.click();
}}
</script>""", encoding="utf-8")


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--brand", default="unilever", choices=sorted(BRANDS), help="brand family to sweep")
    ap.add_argument("--min-score", type=float, default=0.5, help="match threshold (catalogue-wide default is 0.75)")
    ap.add_argument("--delay", type=float, default=1.2, help="seconds between searches")
    ap.add_argument("--limit", type=int, default=500)
    ap.add_argument("--apply", metavar="APPROVED_TXT", help="download the approved images")
    args = ap.parse_args()

    if args.apply:
        # Reuse the catalogue-wide downloader — it already handles the CDN's
        # burst limit, prefers the full-resolution original, and records the
        # CC-BY-SA credit — just pointed at this run's proposals.
        base.PROPOSALS = PROPOSALS
        asyncio.run(base.apply(args.apply))
    else:
        asyncio.run(propose(BRANDS[args.brand], args.min_score, args.delay, args.limit))


if __name__ == "__main__":
    main()
