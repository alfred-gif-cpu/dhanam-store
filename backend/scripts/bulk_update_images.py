"""
Bulk update image_url fields in MongoDB products collection.

Usage:
  python scripts/bulk_update_images.py

How it works:
  1. Fetches all products from MongoDB.
  2. For each product, generates an image filename from the product name
     (e.g. "Aashirvaad Atta" -> "aashirvaad-atta.jpg").
  3. If the image file exists in static/images/, sets image_url to the filename.
  4. If not, sets image_url to "" (Flutter shows a placeholder).

To use:
  1. Place product images in backend/static/images/ named as:
     - lowercase, hyphens instead of spaces
     - e.g. "tata-salt.jpg", "maggi-noodles.png"
  2. Run this script to update MongoDB.
"""

import asyncio
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent))

from database import products_collection

IMAGES_DIR = Path(__file__).parent.parent / "static" / "images"


def name_to_filename(name: str) -> str:
    slug = re.sub(r"[^a-z0-9]+", "-", name.lower()).strip("-")
    for ext in (".jpg", ".jpeg", ".png", ".webp"):
        if (IMAGES_DIR / f"{slug}{ext}").exists():
            return f"{slug}{ext}"
    return ""


async def main():
    total = 0
    updated = 0
    skipped = 0

    async for product in products_collection.find():
        total += 1
        name = product.get("name", "")
        filename = name_to_filename(name)

        if filename:
            await products_collection.update_one(
                {"_id": product["_id"]},
                {"$set": {"image_url": filename}},
            )
            updated += 1
            print(f"  [OK] {name} -> {filename}")
        else:
            await products_collection.update_one(
                {"_id": product["_id"]},
                {"$set": {"image_url": ""}},
            )
            skipped += 1

    print(f"\nDone: {total} products, {updated} matched images, {skipped} no image found.")


if __name__ == "__main__":
    asyncio.run(main())
