"""Mirror the uploaded product photographs off the Railway volume.

backup_db.py dumps every MongoDB collection, which preserves the *filename* of
each product photo and none of the pixels. The photographs themselves exist in
exactly one place: the volume mounted at /data/uploads. Lose it — a detached
volume, a deleted project — and the catalogue points at hundreds of 404s with
no way back but re-photographing the shop.

This pulls every referenced upload down to backend/backups/uploads-mirror/ and
writes a manifest recording which product each file belongs to, so a restore
knows what it is looking at. Everything is fetched over plain HTTP from the
public /static path, so it needs no admin token and cannot alter anything.

It is a mirror, not a snapshot: re-running skips files whose size already
matches and fetches the rest. 85MB of dated copies would multiply for no gain,
and the manifest carries a hash per file so drift is still detectable.

What it cannot see: files on the volume that no product references — orphans
left by a rename or a deleted image. StaticFiles does not list directories, so
there is no way to enumerate them from outside. Nothing in the catalogue points
at them, so nothing is lost by not having them.

Usage:
  python scripts/backup_uploads.py            # fetch anything missing or changed
  python scripts/backup_uploads.py --verify   # check the mirror, download nothing
  python scripts/backup_uploads.py --full     # re-fetch everything
"""

import argparse
import asyncio
import hashlib
import io
import json
import os
import sys
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent))

import httpx
from PIL import Image

from database import products_collection

BASE = os.environ.get("DH_BASE_URL", "https://dhanam-store-production.up.railway.app")
MIRROR = Path(__file__).parent.parent / "backups" / "uploads-mirror"
MANIFEST = MIRROR / "manifest.json"
CONCURRENCY = 10


async def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--verify", action="store_true",
                    help="report drift between the mirror and production, download nothing")
    ap.add_argument("--full", action="store_true", help="re-fetch every file")
    args = ap.parse_args()

    # Hidden products are included deliberately: hidden means off the shelf,
    # not withdrawn, and bringing one back should not need a new photograph.
    targets = []
    async for p in products_collection.find(
        {"image_url": {"$regex": "^uploads/"}},
        {"name": 1, "image_url": 1, "category": 1, "is_active": 1},
    ):
        targets.append(p)

    print(f"{len(targets)} products reference an uploaded photo")
    if not args.verify:
        MIRROR.mkdir(parents=True, exist_ok=True)

    old = {}
    if MANIFEST.exists():
        old = json.loads(MANIFEST.read_text(encoding="utf-8")).get("files", {})

    manifest, fetched, skipped, drifted, failed, corrupt = {}, 0, 0, [], [], []
    sem = asyncio.Semaphore(CONCURRENCY)

    async with httpx.AsyncClient(timeout=120, follow_redirects=True) as client:

        async def one(p):
            nonlocal fetched, skipped
            stored = p["image_url"]
            name = Path(stored).name
            dest = MIRROR / name
            url = f"{BASE}/static/{stored}"

            async with sem:
                # A HEAD first means an unchanged mirror costs 993 tiny requests
                # instead of 85MB.
                remote_size = None
                try:
                    h = await client.head(url)
                    if h.status_code != 200:
                        failed.append((h.status_code, stored, p["name"]))
                        return
                    remote_size = int(h.headers.get("content-length") or 0)
                except Exception as e:
                    failed.append((type(e).__name__, stored, p["name"]))
                    return

                have = dest.exists() and dest.stat().st_size == remote_size
                if args.verify:
                    if not dest.exists():
                        drifted.append(("missing locally", name))
                    elif not have:
                        drifted.append((f"size {dest.stat().st_size} vs {remote_size}", name))
                    else:
                        skipped += 1
                    if dest.exists():
                        manifest[name] = {**old.get(name, {}), "bytes": dest.stat().st_size}
                    return

                if have and not args.full:
                    skipped += 1
                    entry = old.get(name)
                    if entry:
                        manifest[name] = entry
                        return
                    data = dest.read_bytes()
                else:
                    for attempt in range(3):
                        try:
                            r = await client.get(url)
                            r.raise_for_status()
                            data = r.content
                            break
                        except Exception as e:
                            if attempt == 2:
                                failed.append((type(e).__name__, stored, p["name"]))
                                return
                            await asyncio.sleep(1 + attempt)
                    dest.write_bytes(data)
                    fetched += 1

                # A backup nobody has opened is a backup nobody knows works.
                try:
                    im = Image.open(io.BytesIO(data))
                    im.load()
                    dims = list(im.size)
                except Exception:
                    corrupt.append(name)
                    dims = None

                manifest[name] = {
                    "product_id": str(p["_id"]),
                    "product": p.get("name", ""),
                    "category": p.get("category", ""),
                    "visible": bool(p.get("is_active", True)),
                    "image_url": stored,
                    "bytes": len(data),
                    "sha1": hashlib.sha1(data).hexdigest(),
                    "size": dims,
                }

        await asyncio.gather(*(one(p) for p in targets))

    if args.verify:
        print(f"\nin sync   {skipped}")
        print(f"drifted   {len(drifted)}")
        for why, n in drifted[:30]:
            print(f"   {why:28} {n}")
        print(f"failed    {len(failed)}")
        for code, stored, pname in failed[:20]:
            print(f"   {code}  {stored}  <- {pname}")
        return

    MANIFEST.write_text(
        json.dumps(
            {
                "source": BASE,
                "taken": datetime.now(timezone.utc).isoformat(),
                "count": len(manifest),
                "bytes": sum(f.get("bytes", 0) for f in manifest.values()),
                "files": manifest,
            },
            indent=2,
        ),
        encoding="utf-8",
    )

    total = sum(f.get("bytes", 0) for f in manifest.values())
    print(f"\ndownloaded {fetched}")
    print(f"already had {skipped}")
    print(f"failed      {len(failed)}")
    for code, stored, pname in failed[:20]:
        print(f"   {code}  {stored}  <- {pname}")
    print(f"unreadable  {len(corrupt)}")
    for n in corrupt[:10]:
        print(f"   {n}")
    print(f"\nmirror: {len(manifest)} files, {total/1e6:.1f} MB in {MIRROR}")
    print(f"manifest: {MANIFEST}")


if __name__ == "__main__":
    asyncio.run(main())
