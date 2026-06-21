"""
Download real images for each product category.

Usage:
  python scripts/download_category_images.py
"""

import asyncio
import re
import sys
import time
from pathlib import Path

import httpx

sys.path.insert(0, str(Path(__file__).parent.parent))

try:
    from ddgs import DDGS
except ImportError:
    from duckduckgo_search import DDGS

from database import products_collection

OUT_DIR = Path(__file__).parent.parent / "static" / "images" / "categories"
OUT_DIR.mkdir(parents=True, exist_ok=True)

SEARCH_HINTS = {
    "Baby Care": "baby care products diapers",
    "Bakery & Snacks": "bakery snacks biscuits cookies",
    "Beverages": "juice soft drinks beverages bottles",
    "Chocolates & Candies": "chocolates candies sweets",
    "Cooking Oils": "cooking oil sunflower mustard oil bottles",
    "Dairy & Fats": "dairy milk butter cheese products",
    "Dry Fruits & Nuts": "dry fruits almonds cashews nuts",
    "Electronics": "small electronics batteries accessories",
    "Health & Nutrition": "health supplements nutrition products",
    "Healthcare": "healthcare medicines first aid",
    "Household": "household cleaning products",
    "Kitchen Accessories": "kitchen utensils accessories",
    "Miscellaneous": "grocery store miscellaneous items",
    "Pasta & Noodles": "pasta noodles instant noodles",
    "Personal Care": "personal care soap shampoo",
    "Pooja & Religious": "pooja items agarbatti religious",
    "Pulses & Grains": "pulses dal lentils grains",
    "Ready to Cook": "ready to cook instant food packets",
    "Rice & Cereals": "rice basmati cereals",
    "Salt & Condiments": "salt condiments vinegar sauces",
    "Spices & Masalas": "indian spices masala turmeric",
    "Sweeteners": "sugar jaggery honey sweeteners",
    "Tea & Coffee": "tea coffee powder packets",
    "Toys & Stationery": "toys stationery pens pencils",
    "Vegetables & Fruits": "fresh vegetables fruits grocery",
}


def slug(name: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", name.lower()).strip("-")


def search_image(query: str) -> str | None:
    try:
        with DDGS() as ddgs:
            results = ddgs.images(query, max_results=5)
            for r in results:
                url = r.get("image", "")
                if url and any(url.lower().endswith(e) for e in (".jpg", ".jpeg", ".png", ".webp")):
                    if "placeholder" not in url.lower() and "logo" not in url.lower():
                        return url
            if results:
                return results[0].get("image", "")
    except Exception as e:
        print(f"    Search error: {e}")
    return None


async def download(url: str, filepath: Path) -> bool:
    try:
        async with httpx.AsyncClient(timeout=20, follow_redirects=True) as client:
            resp = await client.get(url, headers={"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64)"})
            if resp.status_code != 200 or len(resp.content) < 1000:
                return False
            filepath.write_bytes(resp.content)
            return True
    except Exception as e:
        print(f"    Download error: {e}")
        return False


async def main():
    categories = await products_collection.distinct("category")
    categories = sorted(c for c in categories if c)

    print(f"Downloading images for {len(categories)} categories...\n")

    success = 0
    for i, cat in enumerate(categories, 1):
        s = slug(cat)
        existing = any((OUT_DIR / f"{s}{ext}").exists() for ext in [".jpg", ".jpeg", ".png", ".webp"])
        if existing:
            print(f"[{i}/{len(categories)}] SKIP {cat} (already has image)")
            success += 1
            continue

        query = SEARCH_HINTS.get(cat, f"{cat} grocery products india")
        print(f"[{i}/{len(categories)}] Searching: {cat}...", end=" ", flush=True)

        url = search_image(query)
        if not url:
            print("NO RESULTS")
            continue

        content_type = url.rsplit(".", 1)[-1].lower()
        ext = ".jpg" if content_type not in ("png", "webp", "jpeg") else f".{content_type}"
        filepath = OUT_DIR / f"{s}{ext}"

        if await download(url, filepath):
            success += 1
            print(f"OK -> {filepath.name}")
        else:
            print("FAILED")

        time.sleep(3)

    print(f"\nDone: {success}/{len(categories)} categories have images.")


if __name__ == "__main__":
    asyncio.run(main())
