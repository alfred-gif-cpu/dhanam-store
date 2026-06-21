"""
Download product images from the internet and update MongoDB.

Usage:
  pip install duckduckgo-search httpx
  python scripts/download_images.py
  python scripts/download_images.py --limit 50
  python scripts/download_images.py --overwrite
  python scripts/download_images.py --category "Snacks"
  python scripts/download_images.py --from-csv product_images.csv
"""

import argparse
import asyncio
import csv
import re
import sys
import time
from pathlib import Path

import httpx
try:
    from ddgs import DDGS
except ImportError:
    from duckduckgo_search import DDGS

sys.path.insert(0, str(Path(__file__).parent.parent))

from database import products_collection

IMAGES_DIR = Path(__file__).parent.parent / "static" / "images"
IMAGES_DIR.mkdir(parents=True, exist_ok=True)


def name_to_slug(name: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", name.lower()).strip("-")


def find_existing(slug: str) -> str | None:
    for ext in (".jpg", ".jpeg", ".png", ".webp"):
        if (IMAGES_DIR / f"{slug}{ext}").exists():
            return f"{slug}{ext}"
    return None


def search_image_url(query: str) -> str | None:
    try:
        with DDGS() as ddgs:
            results = ddgs.images(query, max_results=8)
            for r in results:
                url = r.get("image", "")
                if not url:
                    continue
                if any(url.lower().endswith(e) for e in (".jpg", ".jpeg", ".png", ".webp")):
                    if "placeholder" not in url.lower() and "logo" not in url.lower():
                        return url
            if results:
                return results[0].get("image", "")
    except Exception as e:
        print(f"    Search error: {e}")
    return None


async def download_image(url: str, slug: str) -> str | None:
    try:
        async with httpx.AsyncClient(timeout=20, follow_redirects=True) as client:
            resp = await client.get(url, headers={
                "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"
            })
            if resp.status_code != 200:
                return None

            content = resp.content
            if len(content) < 1000:
                return None

            content_type = resp.headers.get("content-type", "")
            if "png" in content_type:
                ext = ".png"
            elif "webp" in content_type:
                ext = ".webp"
            else:
                ext = ".jpg"

            filename = f"{slug}{ext}"
            (IMAGES_DIR / filename).write_bytes(content)
            return filename
    except Exception as e:
        print(f"    Download error: {e}")
        return None


async def process_from_db(args):
    query = {}
    if args.category:
        query["category"] = args.category

    cursor = products_collection.find(query)
    products = [p async for p in cursor]

    if args.limit:
        products = products[:args.limit]

    total = len(products)
    downloaded = 0
    skipped = 0
    failed = 0

    print(f"Processing {total} products...\n")

    for i, product in enumerate(products, 1):
        name = product.get("name", "")
        brand = product.get("brand", "")
        category = product.get("category", "")
        slug = name_to_slug(name)

        existing = find_existing(slug)
        if existing and not args.overwrite:
            if not product.get("image_url"):
                await products_collection.update_one(
                    {"_id": product["_id"]},
                    {"$set": {"image_url": existing}},
                )
                print(f"[{i}/{total}] DB-FIX {name} -> {existing}")
            else:
                print(f"[{i}/{total}] SKIP {name}")
            skipped += 1
            continue

        search_query = f"{name} {brand} {category} product grocery india".strip()
        print(f"[{i}/{total}] Searching: {name}...", end=" ", flush=True)

        image_url = search_image_url(search_query)
        if not image_url:
            failed += 1
            print("NO RESULTS")
            continue

        filename = await download_image(image_url, slug)
        if filename:
            await products_collection.update_one(
                {"_id": product["_id"]},
                {"$set": {"image_url": filename}},
            )
            downloaded += 1
            print(f"OK -> {filename}")
        else:
            failed += 1
            print("DOWNLOAD FAILED")

        time.sleep(3)

    print(f"\nDone: {downloaded} downloaded, {skipped} skipped, {failed} failed out of {total}.")


async def process_from_csv(csv_path: str, args):
    rows = []
    with open(csv_path, newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row in reader:
            rows.append(row)

    if args.limit:
        rows = rows[:args.limit]

    total = len(rows)
    downloaded = 0
    skipped = 0
    failed = 0

    print(f"Processing {total} products from CSV...\n")

    for i, row in enumerate(rows, 1):
        pid = row["product_id"]
        name = row["product_name"]
        slug = name_to_slug(name)
        search_query = row.get("image_search_query", f"{name} product grocery india")

        existing = find_existing(slug)
        if existing and not args.overwrite:
            skipped += 1
            print(f"[{i}/{total}] SKIP {name}")
            continue

        print(f"[{i}/{total}] Searching: {name}...", end=" ", flush=True)

        image_url = search_image_url(search_query)
        if not image_url:
            failed += 1
            print("NO RESULTS")
            continue

        filename = await download_image(image_url, slug)
        if filename:
            from bson import ObjectId
            if ObjectId.is_valid(pid):
                await products_collection.update_one(
                    {"_id": ObjectId(pid)},
                    {"$set": {"image_url": filename}},
                )
            downloaded += 1
            print(f"OK -> {filename}")
        else:
            failed += 1
            print("DOWNLOAD FAILED")

        time.sleep(3)

    print(f"\nDone: {downloaded} downloaded, {skipped} skipped, {failed} failed out of {total}.")


async def main():
    parser = argparse.ArgumentParser(description="Download product images")
    parser.add_argument("--limit", type=int, default=0)
    parser.add_argument("--overwrite", action="store_true")
    parser.add_argument("--category", type=str, default="")
    parser.add_argument("--from-csv", type=str, default="")
    args = parser.parse_args()

    if args.from_csv:
        await process_from_csv(args.from_csv, args)
    else:
        await process_from_db(args)


if __name__ == "__main__":
    asyncio.run(main())
