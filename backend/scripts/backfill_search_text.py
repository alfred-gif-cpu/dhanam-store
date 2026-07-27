"""Populate `search_text` on existing products.

Search matches against a normalized form of each product's name, brand and
category so that spacing and punctuation stop mattering ("3roses" finding
"3 Roses 100 G (S)"). Products created before that field existed need it
filled in once; new and edited products get it written by the admin routes.

Safe to re-run — it only writes where the stored value differs from what the
current normalizer produces, so a change to the normalizer can be rolled out
by simply running this again.

Usage:
    python scripts/backfill_search_text.py            # dry run
    python scripts/backfill_search_text.py --apply
"""
import argparse
import asyncio
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from pymongo import UpdateOne  # noqa: E402

from database import products_collection  # noqa: E402
from search_utils import build_search_text  # noqa: E402


async def run(apply: bool) -> None:
    ops = []
    unchanged = 0
    empty = []
    samples = []

    async for p in products_collection.find({}, {"name": 1, "brand": 1, "category": 1, "search_text": 1}):
        want = build_search_text(p)
        if not want:
            empty.append(p.get("name", str(p["_id"])))
            continue
        if p.get("search_text") == want:
            unchanged += 1
            continue
        ops.append(UpdateOne({"_id": p["_id"]}, {"$set": {"search_text": want}}))
        if len(samples) < 8:
            samples.append((p.get("name", ""), want))

    print(f"needs update : {len(ops)}")
    print(f"already ok   : {unchanged}")
    print(f"no text      : {len(empty)}")
    if empty[:5]:
        print(f"  e.g. {empty[:5]}")
    print("\nsamples:")
    for name, want in samples:
        print(f"  {name[:44]:<46} -> {want[:52]}")

    if not apply:
        print("\nDry run. Re-run with --apply to write.")
        return

    if ops:
        result = await products_collection.bulk_write(ops, ordered=False)
        print(f"\nmodified {result.modified_count} documents")

    await products_collection.create_index("search_text")
    print("index on search_text ensured")


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--apply", action="store_true", help="write changes (default is a dry run)")
    args = ap.parse_args()
    asyncio.run(run(args.apply))


if __name__ == "__main__":
    main()
