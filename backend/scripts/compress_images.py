"""Resize and re-encode product images in place.

The catalog shipped with camera-resolution source images — several are over
3000px and a few exceed 1.5 MB each. Nothing in the app displays a product
larger than roughly full phone width, so the extra pixels cost bandwidth
(billed egress, and the customer's mobile data) and buy nothing.

Filenames and formats are preserved deliberately: products reference images
by filename in the database, so keeping .jpg as .jpg means no data migration
and no risk of a name drifting out of sync with its row.

Originals are committed to git, so `git checkout -- backend/static/images`
reverts everything if a result looks wrong.

Usage:
    python scripts/compress_images.py                 # dry run, reports savings
    python scripts/compress_images.py --apply         # actually rewrite files
    python scripts/compress_images.py --max-dim 800 --quality 78 --apply
"""
import argparse
import sys
from io import BytesIO
from pathlib import Path

from PIL import Image, ImageOps

IMAGES_DIR = Path(__file__).resolve().parent.parent / "static" / "images"
RASTER_EXTS = {".jpg", ".jpeg", ".png", ".webp"}


def _encode(im: Image.Image, ext: str, quality: int) -> bytes:
    """Re-encode an image to the same format it came in as."""
    buf = BytesIO()
    if ext in {".jpg", ".jpeg"}:
        if im.mode not in ("RGB", "L"):
            im = im.convert("RGB")
        im.save(buf, "JPEG", quality=quality, optimize=True, progressive=True)
    elif ext == ".png":
        # Drop a fully-opaque alpha channel — it is a quarter of the pixel
        # data carrying no information.
        if im.mode == "RGBA":
            alpha = im.getchannel("A")
            if alpha.getextrema() == (255, 255):
                im = im.convert("RGB")
        im.save(buf, "PNG", optimize=True)
    elif ext == ".webp":
        im.save(buf, "WEBP", quality=quality, method=6)
    return buf.getvalue()


def process(path: Path, max_dim: int, quality: int, apply: bool) -> tuple[int, int, str]:
    """Return (original_size, new_size, note). new_size == original when skipped."""
    original = path.stat().st_size
    try:
        with Image.open(path) as im:
            im = ImageOps.exif_transpose(im)  # honour camera rotation before resizing
            w, h = im.size
            ext = path.suffix.lower()

            if max(w, h) > max_dim:
                im.thumbnail((max_dim, max_dim), Image.LANCZOS)
                note = f"{w}x{h} -> {im.size[0]}x{im.size[1]}"
            else:
                note = f"{w}x{h} re-encoded"

            data = _encode(im, ext, quality)
    except Exception as e:
        return original, original, f"SKIPPED ({type(e).__name__}: {e})"

    # Never write a result that is larger than what we started with.
    if len(data) >= original:
        return original, original, "skipped (no gain)"

    if apply:
        path.write_bytes(data)
    return original, len(data), note


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--max-dim", type=int, default=1000, help="longest edge in pixels (default 1000)")
    ap.add_argument("--quality", type=int, default=82, help="JPEG/WebP quality (default 82)")
    ap.add_argument("--apply", action="store_true", help="write changes (default is a dry run)")
    ap.add_argument("--dir", default=str(IMAGES_DIR), help="directory to process")
    args = ap.parse_args()

    root = Path(args.dir)
    files = sorted(p for p in root.iterdir() if p.is_file() and p.suffix.lower() in RASTER_EXTS)
    if not files:
        print(f"No images found in {root}")
        return

    mode = "APPLYING" if args.apply else "DRY RUN — nothing will be written"
    print(f"{mode}\n{root}\n{len(files)} images | max edge {args.max_dim}px | quality {args.quality}\n")

    before = after = 0
    changed = []
    for p in files:
        o, n, note = process(p, args.max_dim, args.quality, args.apply)
        before += o
        after += n
        if n < o:
            changed.append((o - n, o, n, p.name, note))

    changed.sort(reverse=True)
    print("biggest reductions:")
    for saved, o, n, name, note in changed[:15]:
        print(f"  {o/1024:>7.0f} KB -> {n/1024:>6.0f} KB  ({100*(1-n/o):>4.1f}% off)  {name[:38]:<40} {note}")

    print(
        f"\n{len(changed)} of {len(files)} files reduced"
        f"\nbefore {before/1024/1024:.1f} MB  ->  after {after/1024/1024:.1f} MB"
        f"  ({100*(1-after/before):.1f}% smaller, {(before-after)/1024/1024:.1f} MB saved)"
    )
    if not args.apply:
        print("\nRe-run with --apply to write these changes.")


if __name__ == "__main__":
    sys.exit(main())
