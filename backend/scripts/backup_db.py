"""Dump every MongoDB collection to timestamped JSON files.

Atlas' free M0 tier has no automated backups or point-in-time recovery, so
this is the only safety net against a bad bulk-update script or an accidental
drop. Run it before any script that writes to production, and on a schedule.

Usage:
    python scripts/backup_db.py                  # writes to ./backups/<timestamp>/
    python scripts/backup_db.py --out D:/dumps   # custom destination
    python scripts/backup_db.py --keep 14        # prune older than 14 backups

Restore a single collection with:
    python scripts/backup_db.py --restore backups/2026-07-27T10-00-00/orders.json
"""
import argparse
import asyncio
import json
import shutil
import sys
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from bson import ObjectId
from database import db  # noqa: E402


def _encode(value):
    """Make BSON JSON-serializable while keeping ObjectIds restorable."""
    if isinstance(value, ObjectId):
        return {"$oid": str(value)}
    if isinstance(value, datetime):
        return {"$date": value.isoformat()}
    if isinstance(value, dict):
        return {k: _encode(v) for k, v in value.items()}
    if isinstance(value, list):
        return [_encode(v) for v in value]
    return value


def _decode(value):
    if isinstance(value, dict):
        if set(value) == {"$oid"}:
            return ObjectId(value["$oid"])
        if set(value) == {"$date"}:
            return datetime.fromisoformat(value["$date"])
        return {k: _decode(v) for k, v in value.items()}
    if isinstance(value, list):
        return [_decode(v) for v in value]
    return value


async def backup(out_root: Path, keep: int) -> Path:
    stamp = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H-%M-%S")
    dest = out_root / stamp
    dest.mkdir(parents=True, exist_ok=True)

    names = await db.list_collection_names()
    total = 0
    for name in sorted(names):
        docs = [_encode(d) async for d in db[name].find()]
        (dest / f"{name}.json").write_text(
            json.dumps(docs, ensure_ascii=False, indent=1), encoding="utf-8"
        )
        total += len(docs)
        print(f"  {name}: {len(docs)} docs")

    print(f"\nBacked up {total} documents across {len(names)} collections to {dest}")

    if keep > 0:
        existing = sorted(p for p in out_root.iterdir() if p.is_dir())
        for old in existing[:-keep]:
            shutil.rmtree(old)
            print(f"Pruned old backup {old.name}")
    return dest


async def restore(path: Path) -> None:
    collection_name = path.stem
    docs = [_decode(d) for d in json.loads(path.read_text(encoding="utf-8"))]
    if not docs:
        print(f"{path} is empty — nothing to restore")
        return

    existing = await db[collection_name].count_documents({})
    print(f"About to replace collection '{collection_name}' ({existing} docs) with {len(docs)} docs from {path.name}.")
    if input("Type the collection name to confirm: ").strip() != collection_name:
        print("Aborted.")
        return

    await db[collection_name].delete_many({})
    await db[collection_name].insert_many(docs)
    print(f"Restored {len(docs)} documents into '{collection_name}'")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", default="backups", help="destination directory")
    parser.add_argument("--keep", type=int, default=10, help="how many backups to retain (0 = keep all)")
    parser.add_argument("--restore", metavar="FILE", help="restore a single collection JSON file")
    args = parser.parse_args()

    if args.restore:
        asyncio.run(restore(Path(args.restore)))
    else:
        asyncio.run(backup(Path(args.out), args.keep))


if __name__ == "__main__":
    main()
