"""Report on catalog data quality, and fix what can be fixed safely.

Three separate problems, only one of which a script can solve:

  * image_url pointing at a file that no longer exists. The app requests it,
    gets a 404, and falls back to the placeholder — so the customer sees the
    same thing either way, but every one of those products costs a wasted
    round trip on every screen it appears on. Clearing the field is safe and
    is what --fix-dead-images does.

  * products with no photo at all. Nothing to automate: the images have to be
    taken or licensed. --worklist exports a CSV ordered by category so the
    shelves can be photographed in one pass.

  * stock levels that were bulk-set rather than counted. Now that ordering
    decrements stock, these drift further from reality with every sale, and
    the low-stock warnings are meaningless until they are counted once.

Usage:
    python scripts/catalog_health.py                    # report only
    python scripts/catalog_health.py --fix-dead-images  # clear dead image_url
    python scripts/catalog_health.py --worklist photos.csv
"""
import argparse
import asyncio
import collections
import csv
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from pymongo import UpdateOne  # noqa: E402

from database import products_collection  # noqa: E402

IMAGES_DIR = Path(__file__).resolve().parent.parent / "static" / "images"
FIELDS = {"name": 1, "brand": 1, "category": 1, "image_url": 1, "image": 1, "stock": 1}


def _stored_image(p: dict) -> str:
    return (p.get("image_url") or p.get("image") or "").strip()


async def _scan():
    on_disk = {f.name for f in IMAGES_DIR.iterdir() if f.is_file()}
    have, missing, dead = [], [], []
    no_brand = 0
    stock = collections.Counter()

    async for p in products_collection.find({}, FIELDS):
        url = _stored_image(p)
        if not url:
            missing.append(p)
        elif url.startswith("http") or url.split("/")[-1] in on_disk:
            have.append(p)
        else:
            dead.append(p)
        if not (p.get("brand") or "").strip():
            no_brand += 1
        stock[p.get("stock")] += 1
    return have, missing, dead, no_brand, stock


async def run(fix_dead: bool, worklist: str | None) -> None:
    have, missing, dead, no_brand, stock = await _scan()
    total = len(have) + len(missing) + len(dead)

    print(f"products                  {total}")
    print(f"  photo present           {len(have)}  ({100*len(have)/total:.0f}%)")
    print(f"  no photo                {len(missing)}")
    print(f"  photo missing from disk {len(dead)}")
    print(f"  no brand recorded       {no_brand}  ({100*no_brand/total:.0f}%)")

    common = stock.most_common(3)
    print(f"\nstock levels (most common): {dict(common)}")
    if common and common[0][1] > total * 0.5:
        print(f"  {common[0][1]} products share the same stock value — these were set in bulk,")
        print("  not counted. Ordering now decrements stock, so they drift further each sale.")

    by_cat = collections.Counter(p.get("category", "Uncategorised") for p in missing)
    if by_cat:
        print("\nproducts needing a photo, by category:")
        for cat, n in by_cat.most_common(10):
            print(f"  {n:>5}  {cat}")

    if dead:
        print(f"\n{len(dead)} products point at a deleted image file, e.g.")
        for p in dead[:5]:
            print(f"  {p.get('name','')[:38]:<40} {_stored_image(p)}")
        if fix_dead:
            ops = [UpdateOne({"_id": p["_id"]}, {"$set": {"image_url": ""}}) for p in dead]
            result = await products_collection.bulk_write(ops, ordered=False)
            print(f"\ncleared image_url on {result.modified_count} products "
                  f"— they now show the placeholder without a failed request first")
        else:
            print("\n  Re-run with --fix-dead-images to clear these.")

    if worklist:
        rows = sorted(
            missing + dead,
            key=lambda p: (p.get("category", ""), p.get("name", "")),
        )
        out = Path(worklist)
        with out.open("w", newline="", encoding="utf-8") as fh:
            w = csv.writer(fh)
            w.writerow(["category", "product_name", "suggested_filename", "done"])
            for p in rows:
                slug = "".join(
                    c if c.isalnum() else "-" for c in (p.get("name") or "").lower()
                ).strip("-")
                while "--" in slug:
                    slug = slug.replace("--", "-")
                w.writerow([p.get("category", ""), p.get("name", ""), f"{slug}.jpg", ""])
        print(f"\nwrote {len(rows)} rows to {out} — ordered by category so a shelf")
        print("can be photographed in one pass. Save each photo under the suggested")
        print("filename, drop them in backend/static/images/, then run:")
        print("  python scripts/bulk_update_images.py")


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--fix-dead-images", action="store_true",
                    help="clear image_url where the file no longer exists")
    ap.add_argument("--worklist", metavar="CSV",
                    help="export the products needing a photo")
    args = ap.parse_args()
    asyncio.run(run(args.fix_dead_images, args.worklist))


if __name__ == "__main__":
    main()
