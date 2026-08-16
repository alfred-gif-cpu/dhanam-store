"""Resize and re-encode oversized panel uploads, in place.

Photographs uploaded through the panel are stored exactly as they arrived. Ones
saved from a manufacturer's site arrive at print resolution — 2000-3800px, up to
4MB — and the app never draws them larger than a few hundred pixels. Customers
here are on mobile data, and image weight is the one thing measured to matter
for Hosur latency (see HANDOFF.md), so this trades pixels nobody sees for bytes
everybody pays for.

The upload endpoint names a file `slugify(product name) + ext`, so re-uploading
with the *same extension* overwrites the same file and `image_url` does not
change. That is the whole reason this can run against a live catalogue: no
customer's saved cart, no wishlist, and no cached page points anywhere new.
A product renamed since its photo was uploaded would land on a new filename
instead — those are detected and skipped unless --allow-rename.

Originals are copied to backend/backups/ before anything is overwritten. The
volume is the only copy that exists; without that, this is not reversible.

Usage:
  python scripts/recompress_uploads.py                  # report only
  python scripts/recompress_uploads.py --apply          # do it
  python scripts/recompress_uploads.py --apply --limit 5

Needs an admin token in DH_ADMIN_TOKEN (the panel keeps one in localStorage
under 'dh_admin_token'); --apply refuses to start without it.
"""

import argparse
import asyncio
import io
import os
import struct
import sys
from datetime import datetime
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent))

import httpx
from PIL import Image, ImageOps

from database import products_collection
from storage import slugify

BASE = os.environ.get("DH_BASE_URL", "https://dhanam-store-production.up.railway.app")
BACKUP_ROOT = Path(__file__).parent.parent / "backups"
TOKEN_FILE = Path(__file__).parent.parent / ".admin_token"

# The app's largest on-screen use is a full-width product image on a tall phone.
# 1200 leaves room for a 3x device pixel ratio and still fits any zoom view.
MAX_SIDE = 1200
# Above this, re-encode even if the dimensions are already sensible: it means
# the file is carrying quality or metadata that buys nothing at display size.
HEAVY_BYTES = 300_000
# Never write a replacement that saves less than this; the churn is not worth it.
MIN_SAVING = 8_000

QUALITY = {"JPEG": 85, "WEBP": 82}
VISIBLE = {"$or": [{"is_active": {"$exists": False}}, {"is_active": True}]}

PNG_MAGIC = b"\x89PNG\r\n\x1a\n"
# Chunks safe to drop: metadata only, nothing the decoder needs to draw pixels.
PNG_DROPPABLE = {b"iTXt", b"tEXt", b"zTXt", b"tIME", b"eXIf"}


def repair_png(data: bytes) -> bytes | None:
    """Strip ancillary metadata chunks from a PNG whose CRCs are broken.

    A file saved half-way from a website can carry a corrupt iTXt block while
    the image data behind it is perfectly intact. Browsers ignore ancillary
    chunk CRCs and show it anyway; stricter decoders refuse the whole file.
    Dropping the metadata makes it readable everywhere without touching a
    pixel. Returns None if the damage is somewhere that matters.
    """
    if not data.startswith(PNG_MAGIC):
        return None
    out, i = bytearray(PNG_MAGIC), 8
    while i + 8 <= len(data):
        length = struct.unpack(">I", data[i : i + 4])[0]
        ctype = data[i + 4 : i + 8]
        end = i + 12 + length
        if end > len(data):
            return None
        if ctype not in PNG_DROPPABLE:
            out += data[i:end]
        i = end
        if ctype == b"IEND":
            break
    try:
        im = Image.open(io.BytesIO(bytes(out)))
        im.load()
    except Exception:
        return None
    return bytes(out)


def load(data: bytes) -> tuple[Image.Image | None, bytes, bool]:
    """Decode image bytes, repairing a broken PNG if that is what is wrong.

    Returns (image, possibly-repaired bytes, was_repaired).
    """
    try:
        im = Image.open(io.BytesIO(data))
        im.load()
        return im, data, False
    except Exception:
        fixed = repair_png(data)
        if fixed is None:
            return None, data, False
        im = Image.open(io.BytesIO(fixed))
        im.load()
        return im, fixed, True


def whiten_transparency(im: Image.Image) -> Image.Image:
    """Put white *behind* transparent pixels, keeping the alpha channel intact.

    A transparent pixel still carries a colour, and nothing displays it — until
    something flattens the image instead of compositing it, and then that hidden
    colour is what shows. These photos arrive with white hidden under the
    transparency; resampling replaces it with black, because the resampler
    averages colour and alpha separately and there is no colour to average where
    everything is transparent. Composited on the app's white card both look
    identical, so the damage is invisible right up until whatever flattens it
    (a share sheet, a PDF, a thumbnailer) rings the product in black.

    Compositing onto white and then restoring the original alpha gives back the
    shape the file arrived with, and makes it safe either way.
    """
    if im.mode not in ("RGBA", "LA") and "transparency" not in im.info:
        return im
    rgba = im.convert("RGBA")
    alpha = rgba.getchannel("A")
    if alpha.getextrema() == (255, 255):  # nothing actually transparent
        return im
    flat = Image.alpha_composite(Image.new("RGBA", rgba.size, (255, 255, 255, 255)), rgba)
    flat.putalpha(alpha)
    return flat


def recompress(im: Image.Image, fmt: str) -> bytes:
    """Fit the image inside MAX_SIDE and re-encode it in its own format.

    Format is deliberately preserved: changing it changes the file extension,
    which changes the filename the upload endpoint writes, which changes
    image_url and orphans the old file. Not worth the extra saving here.
    """
    # Do this before metadata is dropped, or a phone-camera photo tagged
    # "rotate 90" silently comes out on its side.
    im = ImageOps.exif_transpose(im)

    if max(im.size) > MAX_SIDE:
        im.thumbnail((MAX_SIDE, MAX_SIDE), Image.LANCZOS)

    im = whiten_transparency(im)

    buf = io.BytesIO()
    if fmt == "JPEG":
        if im.mode not in ("RGB", "L"):
            im = im.convert("RGB")
        im.save(buf, "JPEG", quality=QUALITY["JPEG"], optimize=True, progressive=True)
    elif fmt == "WEBP":
        if im.mode == "P":
            im = im.convert("RGBA" if "transparency" in im.info else "RGB")
        im.save(buf, "WEBP", quality=QUALITY["WEBP"], method=6)
    elif fmt == "PNG":
        im.save(buf, "PNG", optimize=True)
    else:
        return b""
    return buf.getvalue()


async def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", action="store_true", help="upload the results")
    ap.add_argument("--limit", type=int, help="stop after N products")
    ap.add_argument("--allow-rename", action="store_true",
                    help="also process photos whose filename no longer matches the product name")
    args = ap.parse_args()

    # Either env var or a scratch file. The file exists because pasting a token
    # into a command line puts it in shell history; Get-Clipboard into a
    # gitignored file does not. Delete it when you are done — it is a live
    # admin credential for 24 hours.
    token = os.environ.get("DH_ADMIN_TOKEN", "").strip()
    if not token and TOKEN_FILE.exists():
        token = TOKEN_FILE.read_text(encoding="utf-8-sig").strip().strip('"').strip("'")
    if args.apply and not token:
        sys.exit(
            "--apply needs an admin token: set DH_ADMIN_TOKEN, or put one in "
            f"{TOKEN_FILE} (the panel keeps it in localStorage 'dh_admin_token')"
        )

    targets = []
    async for p in products_collection.find(
        VISIBLE, {"name": 1, "image_url": 1, "category": 1}
    ):
        url = (p.get("image_url") or "").strip()
        if url.startswith("uploads/"):
            targets.append(p)

    print(f"{len(targets)} visible products with a panel upload\n")

    backup_dir = BACKUP_ROOT / f"uploads-{datetime.now():%Y%m%d-%H%M%S}"
    if args.apply:
        backup_dir.mkdir(parents=True, exist_ok=True)

    saved = before_total = after_total = 0
    done = skipped_ok = repaired = failed = renamed = 0
    results = []

    async with httpx.AsyncClient(timeout=120, follow_redirects=True) as client:
        for p in targets:
            if args.limit and done >= args.limit:
                break
            stored = p["image_url"]
            name = p["name"]
            ext = Path(stored).suffix.lower()
            src = f"{BASE}/static/{stored}"

            try:
                r = await client.get(src, headers={"Cache-Control": "no-cache"})
                r.raise_for_status()
                original = r.content
            except Exception as e:
                print(f"  FETCH FAILED  {stored}: {e}")
                failed += 1
                continue

            im, data, was_repaired = load(original)
            if im is None:
                print(f"  UNREADABLE    {stored}  <- {name}")
                failed += 1
                continue

            fmt = im.format or Image.open(io.BytesIO(data)).format
            oversized = max(im.size) > MAX_SIDE or len(original) > HEAVY_BYTES
            if not oversized and not was_repaired:
                skipped_ok += 1
                continue

            # Re-uploading writes to slugify(name)+ext. If the product was
            # renamed after its photo went up, that is a different file: the
            # old one is orphaned and image_url moves. Skip rather than
            # quietly rearrange the volume.
            expected = f"{slugify(name, 'product')}{ext}"
            if expected != Path(stored).name:
                renamed += 1
                if not args.allow_rename:
                    print(f"  NAME MOVED    {Path(stored).name} -> would become {expected}  ({name})")
                    continue

            try:
                new = recompress(im, fmt)
            except Exception as e:
                print(f"  ENCODE FAILED {stored}: {e}")
                failed += 1
                continue

            if not new:
                print(f"  UNKNOWN FMT   {stored} ({fmt})")
                failed += 1
                continue

            gain = len(original) - len(new)
            # A repair is worth doing at any size — the point is that strict
            # decoders can read the file at all, not that it got smaller.
            if gain < MIN_SAVING and not was_repaired:
                skipped_ok += 1
                continue

            done += 1
            if was_repaired:
                repaired += 1
            before_total += len(original)
            after_total += len(new)
            saved += gain
            tag = " (repaired)" if was_repaired else ""
            print(f"  {len(original)//1024:6} KB -> {len(new)//1024:5} KB  "
                  f"{im.size[0]}x{im.size[1]:<5} {Path(stored).name}{tag}")
            results.append((p, stored, original, new, ext))

            if not args.apply:
                continue

            (backup_dir / Path(stored).name).write_bytes(original)

            try:
                up = await client.post(
                    f"{BASE}/admin/products/{p['_id']}/image",
                    headers={"Authorization": f"Bearer {token}"},
                    files={"file": (Path(stored).name, new, f"image/{ 'jpeg' if ext in ('.jpg', '.jpeg') else ext.lstrip('.') }")},
                )
                up.raise_for_status()
            except Exception as e:
                body = getattr(e, "response", None)
                print(f"     UPLOAD FAILED {stored}: {e} {getattr(body, 'text', '')[:200]}")
                failed += 1
                continue

            # Confirm the volume really holds a readable image now. The cache
            # header is 5 minutes and the filename did not change, so ask for
            # a fresh copy explicitly or this verifies the old bytes.
            try:
                v = await client.get(f"{src}?v={datetime.now().timestamp()}",
                                     headers={"Cache-Control": "no-cache"})
                v.raise_for_status()
                check = Image.open(io.BytesIO(v.content))
                check.load()
                if abs(len(v.content) - len(new)) > 2048:
                    print(f"     served {len(v.content)} bytes, uploaded {len(new)} — check {stored}")
            except Exception as e:
                print(f"     VERIFY FAILED {stored}: {e}")
                failed += 1

    print("\n" + "-" * 60)
    print(f"processed        {done}")
    print(f"already fine     {skipped_ok}")
    print(f"corrupt, fixed   {repaired}")
    print(f"filename moved   {renamed}" + ("" if args.allow_rename else " (skipped)"))
    print(f"failed           {failed}")
    if done:
        print(f"\n{before_total/1e6:.1f} MB -> {after_total/1e6:.1f} MB "
              f"({saved/1e6:.1f} MB saved, {saved/before_total:.0%})")
    if args.apply:
        print(f"originals backed up to {backup_dir}")
    else:
        print("\nreport only — nothing uploaded. Re-run with --apply.")


if __name__ == "__main__":
    asyncio.run(main())
