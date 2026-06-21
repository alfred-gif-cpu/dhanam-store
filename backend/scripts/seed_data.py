"""
Seed banners and mark some products as featured/bestsellers.

Usage:
  python scripts/seed_data.py
"""

import asyncio
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent))

from database import banners_collection, products_collection


async def main():
    # Seed banners
    existing = await banners_collection.count_documents({})
    if existing == 0:
        await banners_collection.insert_many([
            {"title": "Fresh Groceries Delivered Fast", "image": "", "action_url": "", "active": True, "order": 1},
            {"title": "Flat 20% Off on Dairy Products", "image": "", "action_url": "", "active": True, "order": 2},
            {"title": "Buy 2 Get 1 Free on Snacks", "image": "", "action_url": "", "active": True, "order": 3},
        ])
        print("Inserted 3 banners")
    else:
        print(f"Banners already seeded ({existing} exist)")

    # Mark first 10 products as featured
    cursor = products_collection.find().limit(10)
    count = 0
    async for p in cursor:
        await products_collection.update_one({"_id": p["_id"]}, {"$set": {"featured": True}})
        count += 1
    print(f"Marked {count} products as featured")

    # Set sold_count on random products for bestsellers
    cursor = products_collection.find().skip(5).limit(10)
    count = 0
    async for p in cursor:
        await products_collection.update_one({"_id": p["_id"]}, {"$set": {"sold_count": 100 + count * 10}})
        count += 1
    print(f"Set sold_count on {count} products for bestsellers")

    print("\nDone!")


if __name__ == "__main__":
    asyncio.run(main())
