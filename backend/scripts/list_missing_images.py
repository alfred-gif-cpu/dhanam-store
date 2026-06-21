"""
List products that have no image or a missing image file.

Usage:
  python scripts/list_missing_images.py
"""

import asyncio
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent))

from database import products_collection

IMAGES_DIR = Path(__file__).parent.parent / "static" / "images"


async def main():
    missing = []
    async for product in products_collection.find({}, {"name": 1, "image_url": 1, "category": 1}):
        image_url = product.get("image_url", "")
        if not image_url:
            missing.append(product)
        elif not image_url.startswith("http") and not (IMAGES_DIR / image_url).exists():
            missing.append(product)

    if not missing:
        print("All products have valid images!")
        return

    print(f"{len(missing)} products missing images:\n")
    for p in missing:
        print(f"  - {p['name']} [{p.get('category', '?')}]")


if __name__ == "__main__":
    asyncio.run(main())
