"""
Export a CSV of all products with image info for tracking/bulk editing.

Usage:
  python scripts/export_image_csv.py

Output: backend/product_images.csv
"""

import asyncio
import csv
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent))

from database import products_collection

IMAGES_DIR = Path(__file__).parent.parent / "static" / "images"
OUT_FILE = Path(__file__).parent.parent / "product_images.csv"


def name_to_slug(name: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", name.lower()).strip("-")


def find_existing(slug: str) -> str:
    for ext in (".jpg", ".jpeg", ".png", ".webp"):
        if (IMAGES_DIR / f"{slug}{ext}").exists():
            return f"{slug}{ext}"
    return ""


def build_search_query(name: str, brand: str, category: str) -> str:
    parts = [name]
    if brand:
        parts.append(brand)
    parts.append(category)
    parts.append("product grocery india")
    return " ".join(parts)


async def main():
    rows = []

    async for p in products_collection.find().sort("category", 1):
        pid = str(p["_id"])
        name = p.get("name", "")
        brand = p.get("brand", "")
        category = p.get("category", "")
        slug = name_to_slug(name)
        db_image = p.get("image_url", "")
        local_file = find_existing(slug)
        has_image = "yes" if (db_image or local_file) else "no"

        rows.append({
            "product_id": pid,
            "product_name": name,
            "brand": brand,
            "category": category,
            "image_filename": local_file or f"{slug}.jpg",
            "image_url_in_db": db_image,
            "has_local_file": "yes" if local_file else "no",
            "has_image": has_image,
            "image_search_query": build_search_query(name, brand, category),
        })

    with open(OUT_FILE, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=rows[0].keys())
        writer.writeheader()
        writer.writerows(rows)

    total = len(rows)
    with_image = sum(1 for r in rows if r["has_image"] == "yes")
    missing = total - with_image

    print(f"Exported {total} products to {OUT_FILE}")
    print(f"  {with_image} have images, {missing} missing")


if __name__ == "__main__":
    asyncio.run(main())
