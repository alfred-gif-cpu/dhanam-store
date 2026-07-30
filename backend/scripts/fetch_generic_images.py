"""Propose generic photographs for loose and commodity goods.

Branded packaged products need a picture of that pack. Loose goods do not:
a photograph of cumin seeds honestly represents any 50g packet of jeera, and
these lines will never appear in a product database because they are packed
in the shop.

Images come from Openverse, which indexes openly licensed photographs from
Flickr, Wikimedia and others, filtered to licences that permit commercial
use. No API key is needed.

Two things make this work for an Indian grocery:

  * the catalogue names ingredients in Tamil and Hindi — jeera, pattai,
    soumf — and an English image search finds nothing for those, so they are
    translated before searching;
  * the shop's own packing prefixes (Dds, Kr) are stripped, since the photo
    should show the ingredient, not a brand.

As with the packaged-goods importer, nothing is applied automatically.

    python scripts/fetch_generic_images.py --propose
    python scripts/fetch_generic_images.py --apply approved_generic.txt
"""
import argparse
import asyncio
import io
import json
import re
import sys
import urllib.parse
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from PIL import Image  # noqa: E402

from database import products_collection  # noqa: E402
from storage import STATIC_DIR  # noqa: E402

API = "https://api.openverse.org/v1/images/"
UA = "DhanamStore/1.0 (alfreddhanam@gmail.com) catalogue image matching"
IMAGES_DIR = STATIC_DIR / "images"
PROPOSALS = Path("generic_proposals.json")

# Only categories where a photograph of the ingredient is an honest
# representation of what arrives in the bag.
COMMODITY_CATEGORIES = {
    "Rice & Cereals", "Pulses & Grains", "Spices & Masalas",
    "Salt & Condiments", "Vegetables", "Fruits", "Dry Fruits & Nuts",
    "Oils & Ghee", "Flours & Sooji",
}

# Shop packing prefixes and generic words that should not reach the search.
STRIP_WORDS = {
    "dds", "kr", "sak", "aachi", "annai", "darling", "gokulam", "bullet",
    "loose", "pkt", "packet", "pack", "no", "new", "spl", "special",
}

# The catalogue names ingredients as customers ask for them. An English
# photo search needs the English name.
GLOSSARY = {
    "jeera": "cumin seeds", "seeragam": "cumin seeds",
    "soumf": "fennel seeds", "sombu": "fennel seeds", "saunf": "fennel seeds",
    "pattai": "cinnamon sticks", "lavangam": "cloves spice",
    "elaichi": "green cardamom", "ealakai": "green cardamom",
    "milagu": "black peppercorns", "milagai": "dried red chilli",
    "manjal": "turmeric root", "kothamalli": "coriander seeds",
    "vellam": "jaggery", "sarkarai": "sugar",
    "aval": "flattened rice poha", "poha": "flattened rice",
    "appalam": "papad", "vadagam": "papad",
    "kadalai": "chickpeas", "kondakadalai": "chickpeas",
    "thuvaram": "toor dal", "toor": "toor dal", "thuvaramparuppu": "toor dal",
    "ulundhu": "urad dal", "ulutham": "urad dal",
    "payaru": "moong dal", "pasiparuppu": "moong dal",
    "kadugu": "mustard seeds", "vendhayam": "fenugreek seeds",
    "perungayam": "asafoetida", "asafoetida": "asafoetida",
    "badam": "almonds", "munthiri": "cashew nuts", "cashew": "cashew nuts",
    "draksha": "raisins", "graphes": "raisins", "kismis": "raisins",
    "rava": "semolina", "sooji": "semolina", "maida": "refined flour",
    "atta": "wheat flour", "besan": "gram flour",
    "arisi": "rice grains", "pachai": "green",
    "ellu": "sesame seeds", "kasakasa": "poppy seeds",
    "sundal": "chickpeas", "puttu": "rice flour",
    "millet": "millet grains", "ragi": "finger millet",
    "dates": "dates fruit", "dhal": "lentils", "dal": "lentils",
    # Plain English commodity words, listed so they count as a recognised
    # ingredient rather than being treated as an unknown brand name.
    "chilli": "dried red chilli", "chillies": "dried red chilli",
    "pepper": "black peppercorns", "coriander": "coriander seeds",
    "cardamom": "green cardamom", "clove": "cloves spice",
    "cinnamon": "cinnamon sticks", "mustard": "mustard seeds",
    "fenugreek": "fenugreek seeds", "sesame": "sesame seeds",
    "tamarind": "tamarind", "groundnut": "peanuts", "peanut": "peanuts",
    "rice": "rice grains", "sugar": "sugar", "salt": "salt",
    "wheat": "wheat grains", "oats": "rolled oats", "jaggery": "jaggery",
    "turmeric": "turmeric powder", "cumin": "cumin seeds",
    "raisin": "raisins", "almond": "almonds", "pista": "pistachios",
}

PACK = re.compile(r"\b\d+\s*(g|kg|ml|l|gm|rs|no|p|pc|pcs|s)\b|\d+", re.I)


def search_term(name: str) -> str | None:
    """Turn a catalogue name into something an English photo search understands."""
    words = re.sub(r"[^a-z ]", " ", PACK.sub(" ", name.lower())).split()
    words = [w for w in words if w not in STRIP_WORDS and len(w) > 1]
    if not words:
        return None

    translated, hit = [], False
    for w in words:
        if w in GLOSSARY:
            translated.append(GLOSSARY[w])
            hit = True
        else:
            translated.append(w)

    # Without a glossary hit we are searching the raw words, which for a local
    # brand name returns something unrelated. Skip rather than guess.
    if not hit:
        return None
    return " ".join(dict.fromkeys(" ".join(translated).split()))[:60]


def search(term: str) -> dict | None:
    url = API + "?" + urllib.parse.urlencode({
        "q": term, "license_type": "commercial", "page_size": 3,
    })
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=30) as r:
        results = json.loads(r.read().decode("utf-8")).get("results", [])
    for hit in results:
        if hit.get("url"):
            return hit
    return None


async def propose(delay: float) -> None:
    todo = []
    async for p in products_collection.find(
        {"$and": [
            {"$or": [{"image_url": ""}, {"image_url": {"$exists": False}}]},
            {"category": {"$in": list(COMMODITY_CATEGORIES)}},
        ]},
        {"name": 1, "category": 1},
    ):
        term = search_term(p.get("name", ""))
        if term:
            todo.append((p, term))

    print(f"{len(todo)} products have a translatable ingredient name\n", flush=True)

    proposals = []
    for i, (p, term) in enumerate(todo, 1):
        try:
            hit = search(term)
        except Exception as e:
            print(f"  [{i}/{len(todo)}] error {type(e).__name__}", flush=True)
            await asyncio.sleep(delay * 2)
            continue

        if hit:
            proposals.append({
                "product_id": str(p["_id"]),
                "our_name": p.get("name", ""),
                "category": p.get("category", ""),
                "their_name": hit.get("title", "")[:60],
                "brands": f"searched: {term}",
                "image_url": hit["url"],
                "code": hit.get("id", ""),
                "source": "openverse",
                "licence": hit.get("license", ""),
                "creator": hit.get("creator", "") or "",
                "score": 1.0,
            })
            print(f"  [{i}/{len(todo)}] {p.get('name','')[:30]:<32} -> {term}", flush=True)
            PROPOSALS.write_text(json.dumps(proposals, indent=1, ensure_ascii=False), encoding="utf-8")
        await asyncio.sleep(delay)

    PROPOSALS.write_text(json.dumps(proposals, indent=1, ensure_ascii=False), encoding="utf-8")
    print(f"\n{len(proposals)} proposals written to {PROPOSALS}")
    print("Build the review sheet with:")
    print("  python scripts/build_review_sheet.py --file generic_proposals.json --out generic_review.html")


async def apply(approved_file: str) -> None:
    from bson import ObjectId

    ids = {ln.strip() for ln in Path(approved_file).read_text(encoding="utf-8").splitlines() if ln.strip()}
    proposals = {p["product_id"]: p for p in json.loads(PROPOSALS.read_text(encoding="utf-8"))}
    chosen = [proposals[i] for i in ids if i in proposals]
    print(f"{len(chosen)} approved of {len(proposals)} proposed\n")

    saved = 0
    for p in chosen:
        slug = re.sub(r"[^a-z0-9]+", "-", p["our_name"].lower()).strip("-")
        raw = None
        for attempt in range(3):
            try:
                req = urllib.request.Request(p["image_url"], headers={"User-Agent": UA})
                with urllib.request.urlopen(req, timeout=45) as r:
                    raw = r.read()
                break
            except Exception:
                await asyncio.sleep(2 * (attempt + 1))
        if raw is None:
            print(f"  failed {p['our_name'][:32]}", flush=True)
            continue

        try:
            im = Image.open(io.BytesIO(raw))
            im.load()
            if im.mode not in ("RGB", "L"):
                im = im.convert("RGB")
            im.thumbnail((1000, 1000), Image.LANCZOS)
            buf = io.BytesIO()
            im.save(buf, "JPEG", quality=88, optimize=True, progressive=True)
            (IMAGES_DIR / f"{slug}.jpg").write_bytes(buf.getvalue())
        except Exception as e:
            print(f"  failed {p['our_name'][:32]}: {type(e).__name__}", flush=True)
            continue

        credit = f"Openverse / {p.get('creator') or 'unknown'} ({p.get('licence','')})"
        await products_collection.update_one(
            {"_id": ObjectId(p["product_id"])},
            {"$set": {"image_url": f"{slug}.jpg", "image_credit": credit}},
        )
        saved += 1
        print(f"  saved {slug}.jpg", flush=True)
        await asyncio.sleep(0.4)

    print(f"\n{saved} images saved. Credits are recorded per product in image_credit.")


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--propose", action="store_true")
    ap.add_argument("--apply", metavar="APPROVED_TXT")
    ap.add_argument("--delay", type=float, default=0.6)
    args = ap.parse_args()

    if args.apply:
        asyncio.run(apply(args.apply))
    elif args.propose:
        asyncio.run(propose(args.delay))
    else:
        ap.print_help()


if __name__ == "__main__":
    main()
