"""
Generate colored SVG placeholder images for each product category.

Usage:
  python scripts/generate_category_placeholders.py

Creates one SVG per category in static/images/categories/
"""

import asyncio
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent))

from database import products_collection

OUT_DIR = Path(__file__).parent.parent / "static" / "images" / "categories"
OUT_DIR.mkdir(parents=True, exist_ok=True)

COLORS = [
    ("#4CAF50", "#E8F5E9"), ("#FF9800", "#FFF3E0"), ("#2196F3", "#E3F2FD"),
    ("#9C27B0", "#F3E5F5"), ("#F44336", "#FFEBEE"), ("#00BCD4", "#E0F7FA"),
    ("#FF5722", "#FBE9E7"), ("#795548", "#EFEBE9"), ("#607D8B", "#ECEFF1"),
    ("#E91E63", "#FCE4EC"), ("#3F51B5", "#E8EAF6"), ("#009688", "#E0F2F1"),
    ("#CDDC39", "#F9FBE7"), ("#FFC107", "#FFF8E1"), ("#8BC34A", "#F1F8E9"),
]

ICONS = {
    "fruit":       "🍎", "vegetable":   "🥬", "dairy":       "🥛",
    "bakery":      "🍞", "beverage":    "🥤", "drink":       "🥤",
    "snack":       "🍪", "meat":        "🥩", "fish":        "🐟",
    "seafood":     "🦐", "frozen":      "❄️", "ice cream":   "🍦",
    "spice":       "🌶️", "masala":      "🌶️", "oil":         "🫒",
    "rice":        "🍚", "grain":       "🌾", "dal":         "🫘",
    "pulse":       "🫘", "flour":       "🌾", "atta":        "🌾",
    "sugar":       "🍬", "tea":         "🍵", "coffee":      "☕",
    "chocolate":   "🍫", "biscuit":     "🍪", "noodle":      "🍜",
    "pasta":       "🍝", "sauce":       "🫙", "pickle":      "🫙",
    "jam":         "🫙", "honey":       "🍯", "egg":         "🥚",
    "bread":       "🍞", "cake":        "🎂", "butter":      "🧈",
    "cheese":      "🧀", "paneer":      "🧀", "ghee":        "🧈",
    "soap":        "🧼", "shampoo":     "🧴", "detergent":   "🧹",
    "clean":       "🧹", "personal":    "🧴", "baby":        "👶",
    "pet":         "🐾", "health":      "💊", "pooja":       "🪔",
    "dry fruit":   "🥜", "nut":         "🥜", "canned":      "🥫",
    "ready":       "🍱", "instant":     "⚡", "organic":     "🌿",
    "salt":        "🧂", "condiment":   "🧂",
}


def get_icon(category: str) -> str:
    cat_lower = category.lower()
    for keyword, icon in ICONS.items():
        if keyword in cat_lower:
            return icon
    return "🛒"


def slug(name: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", name.lower()).strip("-")


def generate_svg(category: str, fg: str, bg: str, icon: str) -> str:
    safe_name = category.replace("&", "&amp;").replace("<", "&lt;")
    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="200" height="200" viewBox="0 0 200 200">
  <rect width="200" height="200" rx="24" fill="{bg}"/>
  <text x="100" y="95" text-anchor="middle" font-size="64">{icon}</text>
  <text x="100" y="145" text-anchor="middle" font-family="Arial, sans-serif"
        font-size="14" font-weight="bold" fill="{fg}">{safe_name}</text>
</svg>'''


async def main():
    categories = await products_collection.distinct("category")
    categories = sorted(c for c in categories if c)

    print(f"Found {len(categories)} categories\n")

    for i, cat in enumerate(categories):
        fg, bg = COLORS[i % len(COLORS)]
        icon = get_icon(cat)
        filename = f"{slug(cat)}.svg"
        svg = generate_svg(cat, fg, bg, icon)
        (OUT_DIR / filename).write_text(svg, encoding="utf-8")
        print(f"  {cat} -> {filename}")

    print(f"\nGenerated {len(categories)} category images in {OUT_DIR}")


if __name__ == "__main__":
    asyncio.run(main())
