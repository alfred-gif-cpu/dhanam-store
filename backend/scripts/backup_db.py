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


async def restore_all(dump_dir: Path, target_uri: str, database_name: str, assume_yes: bool) -> None:
    """Load a whole dump into another cluster — used to move between Atlas
    clusters, since a free M0 cannot change region in place."""
    from motor.motor_asyncio import AsyncIOMotorClient

    files = sorted(dump_dir.glob("*.json"))
    if not files:
        print(f"No .json files in {dump_dir}")
        return

    target = AsyncIOMotorClient(target_uri)[database_name]
    await target.command("ping")
    print(f"Connected to target database '{database_name}'\n")

    plan = [(f, len(json.loads(f.read_text(encoding='utf-8')))) for f in files]
    occupied = {}
    for f, _ in plan:
        n = await target[f.stem].count_documents({})
        if n:
            occupied[f.stem] = n

    for f, count in plan:
        existing = occupied.get(f.stem)
        note = f"  (target already has {existing} — will be replaced)" if existing else ""
        print(f"  {f.stem:26} {count:>7}{note}")

    if occupied and not assume_yes:
        print(f"\n{len(occupied)} target collection(s) already contain data and will be overwritten.")
        if input("Type 'overwrite' to continue: ").strip() != "overwrite":
            print("Aborted.")
            return

    print()
    for f, _ in plan:
        docs = [_decode(d) for d in json.loads(f.read_text(encoding="utf-8"))]
        if not docs:
            continue
        await target[f.stem].delete_many({})
        await target[f.stem].insert_many(docs)
        print(f"  restored {f.stem} ({len(docs)})")

    print(
        "\nDone. Indexes are not copied — they are recreated by ensure_indexes()"
        "\nthe first time the app starts against this cluster."
    )


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", default="backups", help="destination directory")
    parser.add_argument("--keep", type=int, default=10, help="how many backups to retain (0 = keep all)")
    parser.add_argument("--restore", metavar="FILE", help="restore a single collection JSON file")
    parser.add_argument("--restore-all", metavar="DIR", help="restore a whole dump (use with --uri to migrate clusters)")
    parser.add_argument("--uri", help="target MongoDB URI for --restore-all (defaults to the configured one)")
    parser.add_argument("--db", help="target database name (defaults to the configured one)")
    parser.add_argument("--yes", action="store_true", help="skip the overwrite confirmation")
    args = parser.parse_args()

    if args.restore_all:
        from config import settings
        asyncio.run(restore_all(
            Path(args.restore_all),
            args.uri or settings.mongodb_uri,
            args.db or settings.database_name,
            args.yes,
        ))
    elif args.restore:
        asyncio.run(restore(Path(args.restore)))
    else:
        asyncio.run(backup(Path(args.out), args.keep))


if __name__ == "__main__":
    main()
