"""
Set image_url for a single product or by category.

Usage:
  python scripts/set_image_url.py --name "Tata Salt" --url "tata-salt.jpg"
  python scripts/set_image_url.py --category "Snacks" --url "snacks-default.jpg"
  python scripts/set_image_url.py --all --url "placeholder.jpg"
"""

import argparse
import asyncio
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent))

from database import products_collection


async def main():
    parser = argparse.ArgumentParser(description="Set image_url for products")
    parser.add_argument("--name", help="Product name (exact match)")
    parser.add_argument("--category", help="Update all products in a category")
    parser.add_argument("--all", action="store_true", help="Update all products")
    parser.add_argument("--url", required=True, help="Image filename or full URL")
    args = parser.parse_args()

    if args.name:
        query = {"name": args.name}
    elif args.category:
        query = {"category": args.category}
    elif args.all:
        query = {}
    else:
        parser.error("Provide --name, --category, or --all")
        return

    result = await products_collection.update_many(query, {"$set": {"image_url": args.url}})
    print(f"Updated {result.modified_count} product(s).")


if __name__ == "__main__":
    asyncio.run(main())
