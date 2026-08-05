"""Expand the shop's shorthand into names a customer would recognise.

The catalogue is written for someone standing behind the counter who already
knows what `Brit Nc Digestive` is. A customer searching the app does not, and
a name they cannot read is a product they will not buy.

Only the shorthand changes. No product is renamed to something it is not, no
size is touched, and nothing is invented — where a name is ambiguous it is
left exactly as it is and reported instead.

Ambiguity is the whole difficulty here, so the rules are context-aware rather
than a blanket find-and-replace:

    Cl   Cleaner in `Domex Toilet Cl Pow`, but Clear in `Him Cl Com Br Fc`
    Com  Complete in `Gar Bright Com Fw`, but Complexion in the Himalaya line
    Gin  Gingelly in `Gin Oil`, but Ginger in `Gin Gar Paste`
    Cho  Chocolate in `Hershey's Cho Syrup`, but Choco in Britannia's own
         product names — so it is left alone rather than guessed

`Dds` (135 products) and `Kr` (13) are skipped entirely: they are the shop's
own prefixes and nobody outside the shop knows what they stand for. Guessing
at a house brand across 135 customer-facing products is the kind of confident
error that is hard to spot and tedious to undo.

    python scripts/expand_product_names.py --propose
    python scripts/expand_product_names.py --apply approved_expand.txt
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

sys.path.insert(0, str(Path(__file__).resolve().parent))
from normalize_product_names import normalize as normalize_size  # noqa: E402

PROPOSALS = Path("name_expansions.json")
REVIEW_HTML = Path("name_expansions.html")
APPROVED_NAME = "approved_expand.txt"

# Prefixes nobody outside the shop can expand. Left untouched until someone
# says what they stand for.
HOUSE_PREFIXES = ("dds", "kr")

# First word only — these are brands, and only ever appear at the front.
BRANDS = {
    "brit": "Britannia", "sak": "Sakthi", "par": "Parle", "col": "Colgate",
    "him": "Himalaya", "gil": "Gillette", "gar": "Garnier", "sun": "Sunfeast",
    "yard": "Yardley", "pon": "Ponds", "hor": "Horlicks", "cad": "Cadbury",
}

# Safe anywhere in the name: one meaning, no competing reading.
WORDS = {
    "nc": "NutriChoice",       # Britannia NutriChoice, verified
    "pow": "Powder",
    "mas": "Masala",
    "liq": "Liquid",
    "fw": "Face Wash",
    "fc": "Face Cream",        # the catalogue distinguishes Fw from Fc
    "hw": "Hand Wash",
    "bik": "Bikis",
    "spl": "Special",
    "coriender": "Coriander",  # plain misspelling
    "chick": "Chicken",
    "lem": "Lemon",
    "lemen": "Lemon",
    "flo": "Floral",
    "jagg": "Jaggery",
    "tamato": "Tomato",     # plain misspelling; "Pazzta" is the real brand name
    "ic": "Ice Cream",      # Arun is an ice cream brand
    "adv": "Advanced",
    "van": "Vanilla",
    "reg": "Regular",
    "nat": "Natural",
    "cas": "Cashew",
}

# Phrases, applied before single words, because the longer match is the
# correct one: "Gin Gar" is Ginger Garlic, not Gingelly Garlic.
PHRASES = [
    (r"\bgin\s+gar\b", "Ginger Garlic"),
    (r"\bgin\s+oil\b", "Gingelly Oil"),
    (r"\bsurf\s+xl\b", "Surf Excel"),
    (r"\bact\s+ii\b", "ACT II"),
    (r"\bbath\s+r\s+cl\b", "Bathroom Cleaner"),
    (r"\btoilet\s+cl\b", "Toilet Cleaner"),
    (r"\bcl\s+com\s+br\b", "Clear Complexion Brightening"),  # Himalaya, verified
    (r"\bbright\s+com\b", "Bright Complete"),                # Garnier, verified
    (r"\btreat\s+cr\b", "Treat Cream"),
    (r"\bmilk\s+bik\b", "Milk Bikis"),
    (r"\banti\s+bac\b", "Anti Bacterial"),
    (r"\bair\s+fr\b", "Air Freshener"),
    (r"\bjack\s+fr\b", "Jack Fruit"),
    (r"\bg\s+nut\s+oil\b", "Groundnut Oil"),
    (r"\bfr\s+tom\s+ket\b", "Fresh Tomato Ketchup"),
    (r"\bstayfree\s+reg\s+sec\b", "Stayfree Secure Regular"),
    (r"\bstayfree\s+sec\s+reg\b", "Stayfree Secure Regular"),
    (r"\bensure\s+dia\b", "Ensure Diabetes Care"),
    # "Mat" is Matic in a detergent and a floor mat on its own — "Mat-225-250"
    # is a doormat priced by range. Only expand it next to the liquid.
    (r"\bmat\s+liquid\b", "Matic Liquid"),
    # Packet only when it stands alone. Welded to a size — "500pkt" — it is a
    # unit, and "500Packet" is not an improvement on anything.
    (r"(?<=\s)pkt\b", "Packet"),
]

# Front Load and Top Load washing machines take different detergent, and the
# catalogue writes them Fl and Tl. Confined to detergent brands, because two
# letters that short mean nothing reliable anywhere else.
MACHINE_BRANDS = re.compile(r"\b(surf|tide|henko|matic|rin|ariel)\b", re.I)
MACHINE_TYPES = [
    (r"\bfr\s+l\b", "Front Load"),  # the catalogue writes it both ways
    (r"\bfl\b", "Front Load"),
    (r"\btl\b", "Top Load"),
]


def expand(name: str) -> str:
    if not name or name.strip().lower().startswith(HOUSE_PREFIXES):
        return name

    s = name.replace("`", "'")  # Hershey`s -> Hershey's

    for pattern, replacement in PHRASES:
        s = re.sub(pattern, replacement, s, flags=re.I)

    if MACHINE_BRANDS.search(s):
        for pattern, replacement in MACHINE_TYPES:
            s = re.sub(pattern, replacement, s, flags=re.I)

    def word(m):
        w = m.group(0)
        full = WORDS.get(w.lower())
        return full if full else w

    s = re.sub(r"[A-Za-z]+", word, s)

    first = s.split(" ", 1)
    head = BRANDS.get(first[0].lower())
    if head:
        s = head + (" " + first[1] if len(first) > 1 else "")

    # Expanding a word can leave the size welded to it — "Fc100G" becomes
    # "Face Cream100G". Reuse the size rules rather than restating them.
    return normalize_size(re.sub(r"\s+", " ", s).strip())


async def propose() -> None:
    changes = []
    async for p in products_collection.find(
        {"is_active": {"$ne": False}}, {"name": 1, "category": 1}
    ):
        old = p.get("name") or ""
        new = expand(old)
        if new and new != old:
            changes.append({"id": str(p["_id"]), "old": old, "new": new,
                            "category": p.get("category", "")})

    changes.sort(key=lambda c: c["old"])
    PROPOSALS.write_text(json.dumps(changes, indent=1, ensure_ascii=False), encoding="utf-8")
    _write_review(changes)
    print(f"{len(changes)} of the visible names would change")
    print(f"Open {REVIEW_HTML}; ticked ones save to {APPROVED_NAME}")


def _diff(old: str, new: str) -> str:
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
  <span class="arrow">&rarr;</span>
  <span class="new">{_diff(c['old'], c['new'])}</span>
  <span class="cat">{html.escape(c['category'])}</span>
</label>""" for c in changes)

    REVIEW_HTML.write_text(f"""<!doctype html><meta charset="utf-8">
<title>Name expansions &mdash; {len(changes)}</title>
<style>
 body{{font:14px/1.5 system-ui;margin:24px;background:#fafafa}}
 h1{{font-size:19px;margin-bottom:2px}}
 .bar{{position:sticky;top:0;background:#fafafa;padding:12px 0;border-bottom:1px solid #ddd;z-index:2}}
 button{{padding:8px 14px;font-size:14px;cursor:pointer;margin-right:6px}}
 .note{{background:#e8f5e9;border:1px solid #a5d6a7;padding:10px 12px;border-radius:8px;margin-top:10px;max-width:82ch}}
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
  <div class="note">Shorthand expanded into what a customer would recognise &mdash; the change is
  highlighted on the right. Sizes are untouched. <b>Dds and Kr products are not here</b>, since
  nobody outside the shop knows what those stand for. Untick anything where the expansion is wrong:
  you know these products and I am reading abbreviations.</div>
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
        # Rebuilt with the rename, or the product stays findable only by a name
        # nobody can see any more.
        await products_collection.update_one(
            {"_id": ObjectId(c["id"])},
            {"$set": {"name": c["new"],
                      "search_text": build_search_text(product),
                      "search_words": build_search_words(product)}},
        )
        done += 1
    print(f"{done} products renamed, search fields rebuilt with them")


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
