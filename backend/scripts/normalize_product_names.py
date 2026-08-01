"""Make pack sizes read the same way across the catalogue.

The name audit found two mechanical problems worth fixing in bulk: the size
welded onto the last word (`Aachi Curry Leaf Paste200g`), and the same unit
spelled four ways (`G`, `g`, `Gm`, `gm`). Neither is anyone's mistake — they
are what a catalogue built over time looks like — but together they make the
shop read as unattended, and they split search: someone typing "500g" and
someone typing "500 G" are running different queries.

One convention, applied everywhere:

    number and unit joined, no space   500g   1kg   750ml   2L   10Rs
    grams        g      (from G, Gm, gm)
    kilograms    kg     (from Kg, KG)
    millilitres  ml     (from Ml, ML)
    litres       L      (from Lt, ltr, l) — capital, because a lowercase l
                        next to a digit reads as a 1
    rupees       Rs     (from rs)
    pieces       pc     (from Pc, Pcs, pcs)

Only spacing and unit spelling change. No word is added, removed, shortened
or expanded, so a customer searching for what they saw last week still finds
it — and `search_text` is rebuilt as part of applying, so the search index
agrees with the new names.

    python scripts/normalize_product_names.py --propose
    python scripts/normalize_product_names.py --apply approved_names.txt

Nothing is renamed until you approve it.
"""
import argparse
import asyncio
import html
import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from database import products_collection  # noqa: E402
from search_utils import build_search_text, build_search_words  # noqa: E402

PROPOSALS = Path("name_changes.json")
REVIEW_HTML = Path("name_changes.html")
APPROVED_NAME = "approved_names.txt"

UNIT_CANON = {
    "g": "g", "gm": "g", "gms": "g", "gram": "g", "grams": "g",
    "kg": "kg", "kgs": "kg",
    "ml": "ml", "mls": "ml",
    "l": "L", "lt": "L", "ltr": "L", "ltrs": "L", "litre": "L", "litres": "L",
    "rs": "Rs",
    "pc": "pc", "pcs": "pc", "pkt": "pkt",
}
# A number followed by a unit, however it is currently spaced or spelled.
SIZE = re.compile(r"(?<![a-zA-Z0-9])(\d+(?:\.\d+)?)\s*(g|gm|gms|gram|grams|kg|kgs|ml|mls|"
                  r"l|lt|ltr|ltrs|litre|litres|rs|pc|pcs|pkt)(?![a-zA-Z])", re.I)
# A word running straight into a size: "Paste200g".
RUN_ON = re.compile(r"([a-zA-Z]{3,})(?=\d+(?:\.\d+)?\s*(?:g|gm|kg|ml|l|lt|ltr|rs|pc|pcs|pkt)"
                    r"(?![a-zA-Z]))", re.I)


def normalize(name: str) -> str:
    s = name or ""
    s = RUN_ON.sub(r"\1 ", s)                       # Paste200g -> Paste 200g
    s = SIZE.sub(lambda m: f"{m.group(1)}{UNIT_CANON[m.group(2).lower()]}", s)
    return re.sub(r"\s+", " ", s).strip()


async def propose() -> None:
    changes = []
    async for p in products_collection.find({}, {"name": 1, "category": 1}):
        old = p.get("name") or ""
        new = normalize(old)
        if new and new != old:
            changes.append({"id": str(p["_id"]), "old": old, "new": new,
                            "category": p.get("category", "")})

    changes.sort(key=lambda c: c["old"])
    PROPOSALS.write_text(json.dumps(changes, indent=1, ensure_ascii=False), encoding="utf-8")
    _write_review(changes)
    print(f"{len(changes)} names would change")
    print(f"Open {REVIEW_HTML}; ticked ones save to {APPROVED_NAME}, then --apply it")


def _diff(old: str, new: str) -> str:
    """Mark up what actually moved, so a skim catches a wrong change."""
    import difflib
    out = []
    for tag, i1, i2, j1, j2 in difflib.SequenceMatcher(None, old, new).get_opcodes():
        if tag == "equal":
            out.append(html.escape(old[i1:i2]))
        elif tag in ("replace", "insert"):
            out.append(f"<mark>{html.escape(new[j1:j2])}</mark>")
    return "".join(out)


def _write_review(changes: list) -> None:
    rows = "".join(f"""
<label class="row">
  <input type="checkbox" checked value="{html.escape(c['id'])}">
  <span class="old">{html.escape(c['old'])}</span>
  <span class="arrow">→</span>
  <span class="new">{_diff(c['old'], c['new'])}</span>
  <span class="cat">{html.escape(c['category'])}</span>
</label>""" for c in changes)

    REVIEW_HTML.write_text(f"""<!doctype html><meta charset="utf-8">
<title>Name changes — {len(changes)}</title>
<style>
 body{{font:14px/1.5 system-ui;margin:24px;background:#fafafa}}
 h1{{font-size:19px;margin-bottom:2px}}
 .bar{{position:sticky;top:0;background:#fafafa;padding:12px 0;border-bottom:1px solid #ddd;z-index:2}}
 button{{padding:8px 14px;font-size:14px;cursor:pointer;margin-right:6px}}
 .note{{background:#e8f5e9;border:1px solid #a5d6a7;padding:10px 12px;border-radius:8px;margin-top:10px;max-width:80ch}}
 .row{{display:grid;grid-template-columns:24px 1fr 20px 1fr 150px;gap:10px;align-items:center;
      background:#fff;border:1px solid #e0e0e0;border-radius:6px;padding:7px 10px;margin-top:6px;cursor:pointer}}
 .row:has(input:not(:checked)){{opacity:.4}}
 .old{{color:#777}} .arrow{{color:#bbb;text-align:center}} .new{{font-weight:500}}
 mark{{background:#fff59d;padding:0 1px;border-radius:2px}}
 .cat{{color:#999;font-size:12px;text-align:right}}
</style>
<h1>{len(changes)} names would change</h1>
<div class="bar">
  <button onclick="save()">Save approved list</button>
  <button onclick="document.querySelectorAll('input').forEach(i=>i.checked=false)">Untick all</button>
  <div class="note">Only spacing and unit spelling change — highlighted on the right. No word is
  added, removed or shortened, so anything a customer already searches for still matches. Untick any
  line where the highlight has landed somewhere it should not.</div>
</div>
{rows}
<script>
function save() {{
  const ids=[...document.querySelectorAll('input:checked')].map(i=>i.value).join('\\n');
  const a=document.createElement('a');
  a.href=URL.createObjectURL(new Blob([ids],{{type:'text/plain'}}));
  a.download='{APPROVED_NAME}'; a.click();
}}
</script>""", encoding="utf-8")


async def apply(approved_file: str) -> None:
    from bson import ObjectId

    ids = {ln.strip() for ln in Path(approved_file).read_text().splitlines() if ln.strip()}
    changes = {c["id"]: c for c in json.loads(PROPOSALS.read_text(encoding="utf-8"))}
    chosen = [changes[i] for i in ids if i in changes]
    print(f"{len(chosen)} approved of {len(changes)} proposed\n")

    done = 0
    for c in chosen:
        product = await products_collection.find_one({"_id": ObjectId(c["id"])})
        if not product:
            continue
        product["name"] = c["new"]
        # Rebuilt here rather than left to a later backfill: a renamed product
        # whose search fields still hold the old name is findable by a name
        # nobody can see and unfindable by the one on the card.
        await products_collection.update_one(
            {"_id": ObjectId(c["id"])},
            {"$set": {"name": c["new"],
                      "search_text": build_search_text(product),
                      "search_words": build_search_words(product)}},
        )
        done += 1
        if done % 50 == 0:
            print(f"  {done}/{len(chosen)}", flush=True)

    print(f"\n{done} products renamed, search fields rebuilt with them")


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--propose", action="store_true")
    ap.add_argument("--apply", metavar="APPROVED_TXT")
    args = ap.parse_args()

    if args.apply:
        asyncio.run(apply(args.apply))
    elif args.propose:
        asyncio.run(propose())
    else:
        ap.print_help()


if __name__ == "__main__":
    main()
