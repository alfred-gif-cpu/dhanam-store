"""Find photographs that do not show the product they are attached to.

A wrong photo is the most expensive kind of catalogue error. A missing one
costs a little confidence; a wrong one takes an order, a delivery run and a
phone call before anyone notices. The filenames cannot tell you — they are
generated from the product name, so they always agree with it — which means
the only honest check is to look at what is in the picture.

For packaged groceries the brand is printed on the pack in large type, so
reading it back with OCR and comparing it to the product name catches the
mismatches that matter. Three verdicts:

  wrong brand   the pack names a brand the product does not — a Knorr line
                showing a Maggi pack. The strongest signal here, and the one
                worth acting on first.
  no overlap    nothing in the product name appears anywhere on the pack.
                Suspicious, but read it yourself before believing it.
  unreadable    too little text to judge. Loose goods, produce and anything
                sold from a sack land here, and it is not a fault — a photo
                of cumin has nothing written on it.

The last bucket is why this reports rather than deletes. OCR misses curved
labels, foil, low light and stylised logos, so a flag is a reason to look,
never a verdict.

    python scripts/find_mismatched_images.py            # every product with a photo
    python scripts/find_mismatched_images.py --limit 50 # a quick taste

Writes image_mismatches.csv and image_mismatches.html, worst first.
"""
import argparse
import asyncio
import csv
import html
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from database import products_collection  # noqa: E402
from search_utils import BRAND_SYNONYMS  # noqa: E402
from storage import STATIC_DIR  # noqa: E402

IMAGES_DIR = STATIC_DIR / "images"
CSV_OUT = Path("image_mismatches.csv")
HTML_OUT = Path("image_mismatches.html")

# Brands the shop actually stocks. A pack naming one of these while the
# product names another is the case worth chasing.
KNOWN_BRANDS = {
    "britannia", "parle", "sunfeast", "maggi", "knorr", "kissan", "nestle",
    "cadbury", "amul", "nescafe", "bru", "horlicks", "boost", "complan",
    "colgate", "closeup", "pepsodent", "sensodyne", "oral-b", "himalaya",
    "dove", "lux", "lifebuoy", "santoor", "cinthol", "medimix", "hamam",
    "ponds", "nivea", "vaseline", "lakme", "garnier", "loreal", "yardley",
    "gillette", "axe", "rexona", "sunsilk", "clinic", "head", "pantene",
    "dabur", "patanjali", "vim", "surf", "rin", "wheel", "ariel", "tide",
    "harpic", "lizol", "domex", "colin", "sakthi", "aachi", "everest",
    "mtr", "gemini", "fortune", "saffola", "sundrop", "dhara", "kellogg",
    "quaker", "pepsi", "coca", "sprite", "fanta", "thumbs", "7up", "mirinda",
    "bingo", "lays", "kurkure", "haldiram", "bikano", "tata", "brooke",
    "redlabel", "taj", "3roses", "society", "wagh", "tetley", "twinings",
}
_ALIAS_TO_BRAND = {a: full for full, aliases in BRAND_SYNONYMS.items() for a in aliases}

# Abbreviations the catalogue uses that the search module does not know about.
# Without these the product claims no brand at all, so a pack correctly
# showing GARNIER reads as a foreign brand and gets reported.
_ALIAS_TO_BRAND.update({
    "gar": "garnier", "nes": "nestle", "cad": "cadbury", "sun": "sunfeast",
    "oral": "oralb", "orala": "oralb", "hor": "horlicks", "cls": "closeup",
    "pon": "ponds", "lif": "lifebuoy", "vas": "vaseline", "pat": "patanjali",
})

# Who owns what. A Munch wrapper says Nestlé and a Good Day packet says
# Britannia — the parent company's name on the pack is the pack being
# correct, not the photo being wrong. Compared by family, so only a genuine
# crossing of families is reported.
BRAND_FAMILY = {
    "nestle": {"nestle", "munch", "milkmaid", "maggi", "nescafe", "kitkat", "milkybar", "everyday"},
    "britannia": {"britannia", "goodday", "good", "bourbon", "marie", "bikis", "treat",
                  "hearts", "nutrichoice", "tiger", "jimjam", "50-50", "rusk"},
    "parle": {"parle", "hide", "seek", "monaco", "krackjack", "melody", "kismi", "poppins", "20-20"},
    "itc": {"itc", "sunfeast", "fantasy", "bingo", "yippee", "aashirvaad", "dark"},
    "pepsico": {"pepsico", "pepsi", "kurkure", "lays", "doritos", "7up", "mirinda", "slice", "tropicana"},
    "cadbury": {"cadbury", "dairymilk", "oreo", "bournvita", "fivestar", "gems", "perk", "silk"},
    "unilever": {"unilever", "hul", "surf", "rin", "wheel", "lux", "lifebuoy", "dove", "ponds",
                 "vim", "comfort", "bru", "horlicks", "boost", "knorr", "kissan", "lakme",
                 "axe", "sunsilk", "closeup", "pepsodent", "vaseline", "hamam", "brooke"},
    "cocacola": {"cocacola", "coca", "sprite", "fanta", "thumbs", "maaza", "limca"},
    "oralb": {"oralb", "oral"},
    "3roses": {"3roses", "roses"},
}
_TO_FAMILY = {member: fam for fam, members in BRAND_FAMILY.items() for member in members}

# Words that are brands but are also ordinary English found on any label.
# "Slice" is a Pepsi drink and also what a cheese pack calls its contents;
# treating those as brand evidence produces confident nonsense.
AMBIGUOUS = {"good", "dark", "slice", "treat", "tiger", "gems", "silk", "marie",
             "boost", "comfort", "everyday", "hearts", "seek", "hide", "coca",
             "fantasy", "rusk", "bikis", "head", "clinic", "tide", "wheel"}


def _family(brand: str) -> str:
    return _TO_FAMILY.get(brand, brand)


def _with_joins(toks: list[str]) -> list[str]:
    """Add adjacent pairs joined up, because the catalogue splits brand names.

    "Milk Maid" is Milkmaid, "Kur Kure" is Kurkure, "Dairy Milk" is Dairy
    Milk. Without the joined form each of those looks like a product whose
    pack names a company it has nothing to do with.
    """
    return toks + [a + b for a, b in zip(toks, toks[1:])]

PACK_SIZE = re.compile(r"\b\d+\s*(g|kg|ml|l|gm|rs|pc|pcs|ltr)\b|\b\d+rs\b|\(s\)|\d+\+\d+", re.I)
STOP = {"the", "and", "with", "for", "new", "spl", "special", "pack", "packet",
        "loose", "combo", "offer", "free", "no", "size", "pouch", "box", "jar",
        "bottle", "tin", "refill", "value", "family"}


def _norm(s: str) -> str:
    return re.sub(r"[^a-z0-9 ]", " ", (s or "").lower())


def _tokens(name: str) -> list[str]:
    words = PACK_SIZE.sub(" ", _norm(name)).split()
    out = []
    for w in words:
        # "maid190g" is Maid with a pack size welded on — the catalogue often
        # omits the space, and the size never helps identify the brand.
        w = re.sub(r"\d+\s*(g|kg|ml|l|gm|rs|pc|pcs|ltr)?$", "", w)
        w = _ALIAS_TO_BRAND.get(w, w)  # brit -> britannia, col -> colgate
        if len(w) > 2 and w not in STOP:
            out.append(w)
    return out


def _close(a: str, b: str) -> bool:
    """Whether two words are the same word, allowing for OCR mangling.

    OCR reads Britannia off a curved foil pack as "BRITANDBA". Requiring an
    exact match would report that as a wrong photo, which is how a checking
    tool becomes noise that gets ignored.
    """
    from difflib import SequenceMatcher
    if a == b:
        return True
    # Fuzziness earns its place only on long names, where a misread letter
    # still leaves the word recognisable. On anything shorter it mostly
    # invents matches: "compan" scored 0.92 against "complan" and flagged
    # every pack with a company name printed on it.
    if len(a) < 8 or abs(len(a) - len(b)) > 2:
        return False
    return SequenceMatcher(None, a, b).ratio() >= 0.90


def judge(name: str, ocr_text: str) -> tuple[str, float, str]:
    """Compare a product name against whatever the pack says."""
    # Match on whole words. Searching a de-spaced blob finds "rin" inside
    # "drink" and "fanta" inside "fantasy", which is not brand detection.
    words = [w for w in _norm(ocr_text).split() if len(w) > 2]
    if len(" ".join(words)) < 6:
        return "unreadable", 0.0, ""

    toks = _tokens(name)
    if not toks:
        return "unreadable", 0.0, ""

    # Joins are built from the unfiltered words, so a brand written as "3
    # Roses" still forms "3roses" — the "3" is dropped from the tokens for
    # being short, but it is half the brand name.
    raw = [w for w in PACK_SIZE.sub(" ", _norm(name)).split() if w]

    hits = [t for t in toks if any(_close(t, w) for w in words)]
    overlap = len(hits) / len(toks)

    # The ambiguity only cuts one way. A product actually named "Hide & Seek"
    # is entitled to claim Parle; a cheese pack that happens to say "slices"
    # is not evidence of a Pepsi drink. So ambiguous words count as the
    # product's own brand, but never as the pack's.
    full_vocab = KNOWN_BRANDS | set(_TO_FAMILY)
    vocabulary = full_vocab - AMBIGUOUS
    joined = _with_joins(toks) + [a + b for a, b in zip(raw, raw[1:])]
    ours = {_family(_ALIAS_TO_BRAND.get(t, t)) for t in joined if
            _ALIAS_TO_BRAND.get(t, t) in full_vocab}
    # The pack's own words, plus adjacent pairs, since OCR splits a wordmark
    # across two boxes as readily as the catalogue splits it across two words.
    pack = words + [a + b for a, b in zip(words, words[1:])]
    theirs = {_family(b) for b in vocabulary if any(_close(b, w) for w in pack)}
    conflicting = theirs - ours

    # Only a crossing of brand families counts: a pack naming a brand we did
    # not ask for, and naming nothing we did.
    if conflicting and not (ours & theirs):
        return "wrong brand", overlap, ", ".join(sorted(conflicting)[:3])
    # The pack and the product agree on the brand family. That is the thing
    # being checked, so it settles the question even when no single word
    # matched — "Oral-B" against a pack reading ORAL-B shares no token, since
    # the hyphen splits it, but nobody would call that the wrong photo.
    if ours & theirs:
        return "ok", max(overlap, 1.0), ""
    if overlap == 0:
        return "no overlap", 0.0, ", ".join(sorted(theirs)[:3])
    return "ok", overlap, ""


async def main(limit: int | None) -> None:
    from rapidocr_onnxruntime import RapidOCR

    products = []
    async for p in products_collection.find(
        {"image_url": {"$nin": ["", None]}}, {"name": 1, "image_url": 1, "category": 1}
    ):
        products.append(p)
    if limit:
        products = products[:limit]

    print(f"reading text off {len(products)} product photographs\n", flush=True)
    ocr = RapidOCR()
    rows = []
    for i, p in enumerate(products, 1):
        path = IMAGES_DIR / p["image_url"]
        if not path.exists():
            rows.append({"name": p.get("name", ""), "file": p["image_url"], "verdict": "file missing",
                         "overlap": 0.0, "found": "", "text": "", "category": p.get("category", "")})
            continue
        try:
            res, _ = ocr(str(path))
            text = " ".join(r[1] for r in (res or []))
        except Exception:
            text = ""
        verdict, overlap, found = judge(p.get("name", ""), text)
        rows.append({"name": p.get("name", ""), "file": p["image_url"], "verdict": verdict,
                     "overlap": round(overlap, 2), "found": found,
                     "text": text[:300], "category": p.get("category", "")})
        if i % 50 == 0:
            print(f"  {i}/{len(products)}", flush=True)

    order = {"wrong brand": 0, "file missing": 1, "no overlap": 2, "unreadable": 3, "ok": 4}
    rows.sort(key=lambda r: (order[r["verdict"]], r["overlap"]))

    with CSV_OUT.open("w", newline="", encoding="utf-8") as fh:
        wr = csv.writer(fh)
        wr.writerow(["verdict", "product", "file", "category", "overlap", "brand_on_pack", "text_found"])
        for r in rows:
            wr.writerow([r["verdict"], r["name"], r["file"], r["category"],
                         r["overlap"], r["found"], r["text"]])

    suspect = [r for r in rows if r["verdict"] in ("wrong brand", "no overlap", "file missing")]
    _write_sheet(suspect[:200], rows)

    tally: dict[str, int] = {}
    for r in rows:
        tally[r["verdict"]] = tally.get(r["verdict"], 0) + 1
    print(f"\n{len(rows)} checked\n")
    for k in ("wrong brand", "file missing", "no overlap", "unreadable", "ok"):
        if tally.get(k):
            print(f"  {k:<14} {tally[k]}")
    print(f"\nfull results: {CSV_OUT}   the {min(200,len(suspect))} to look at: {HTML_OUT}")


def _write_sheet(suspect: list, allrows: list) -> None:
    import base64

    cards = []
    for r in suspect:
        path = IMAGES_DIR / r["file"]
        img = ('<div class="missing">file missing</div>' if not path.exists() else
               f'<img src="data:image/jpeg;base64,{base64.b64encode(path.read_bytes()).decode("ascii")}" alt="">')
        found = f'<div class="found">pack says: <b>{html.escape(r["found"])}</b></div>' if r["found"] else ""
        cards.append(f"""
<div class="card {r['verdict'].replace(' ','-')}">
  {img}
  <div class="verdict">{html.escape(r['verdict'])}</div>
  <div class="prod">{html.escape(r['name'])}</div>
  {found}
  <div class="text">{html.escape(r['text'][:150]) or '<em>no text read</em>'}</div>
</div>""")

    HTML_OUT.write_text(f"""<!doctype html><meta charset="utf-8">
<title>Possible wrong photos — {len(suspect)}</title>
<style>
 body{{font:14px system-ui;margin:24px;background:#fafafa}}
 h1{{font-size:18px;margin-bottom:4px}} .sub{{color:#666;margin-bottom:16px;max-width:70ch;line-height:1.5}}
 .grid{{display:grid;grid-template-columns:repeat(auto-fill,minmax(290px,1fr));gap:14px}}
 .card{{background:#fff;border:1px solid #ddd;border-radius:8px;padding:12px}}
 .card.wrong-brand{{border-color:#c62828;background:#fff5f5}}
 .card img{{width:100%;height:175px;object-fit:contain;background:#f4f4f4;border-radius:4px}}
 .missing{{height:175px;display:flex;align-items:center;justify-content:center;background:#f4f4f4;color:#999;border-radius:4px}}
 .verdict{{font-size:11px;text-transform:uppercase;letter-spacing:.04em;color:#c62828;margin-top:8px;font-weight:700}}
 .prod{{font-weight:600;margin:2px 0 4px}}
 .found{{font-size:12px;color:#c62828}}
 .text{{font-size:11px;color:#888;margin-top:6px;line-height:1.35}}
</style>
<h1>{len(suspect)} photographs worth checking</h1>
<div class="sub">Of {len(allrows)} products with a photo. Red cards name a brand on the pack that the
product does not — those are the ones to fix first. The rest had nothing in common between the
product name and the text on the pack, which is often a stylised logo OCR could not read rather
than a wrong photo. Look before you act.</div>
<div class="grid">{''.join(cards)}</div>""", encoding="utf-8")


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--limit", type=int)
    asyncio.run(main(ap.parse_args().limit))
