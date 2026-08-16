"""Upload storage and image URL resolution.

Railway containers have an ephemeral filesystem — anything written at runtime
is gone on the next deploy. Runtime uploads therefore go to UPLOAD_DIR, which
in production is a mounted volume.

UPLOAD_DIR is deliberately *not* static/images/: that directory holds the
product photos committed to the repo and baked into the image at build time,
and mounting a volume over it would hide every one of them.
"""
import os
import re
import time
from pathlib import Path

from fastapi import HTTPException, UploadFile

STATIC_DIR = Path(__file__).parent / "static"

# Public path segment; also the prefix stored in the DB (e.g. "uploads/x.jpg").
UPLOAD_PREFIX = "uploads"
UPLOAD_DIR = Path(os.environ.get("UPLOAD_DIR") or (STATIC_DIR / UPLOAD_PREFIX))
UPLOAD_DIR.mkdir(parents=True, exist_ok=True)

ALLOWED_IMAGE_TYPES = {"image/jpeg", "image/png", "image/webp", "image/gif"}
ALLOWED_IMAGE_EXTS = {".jpg", ".jpeg", ".png", ".webp", ".gif"}
MAX_IMAGE_SIZE = 5 * 1024 * 1024  # 5MB


def slugify(value: str, fallback: str = "file") -> str:
    return re.sub(r"[^a-z0-9]+", "-", (value or "").lower()).strip("-") or fallback


async def read_image_upload(file: UploadFile) -> tuple[bytes, str]:
    """Validate an uploaded image and return (content, extension).

    Raises HTTPException on anything not a small, plain image.
    """
    if file.content_type not in ALLOWED_IMAGE_TYPES:
        raise HTTPException(
            status_code=400,
            detail=f"Invalid file type. Allowed: {', '.join(sorted(ALLOWED_IMAGE_TYPES))}",
        )
    ext = (Path(file.filename or "img.jpg").suffix or ".jpg").lower()
    if ext not in ALLOWED_IMAGE_EXTS:
        raise HTTPException(status_code=400, detail="Invalid file extension")
    content = await file.read()
    if len(content) > MAX_IMAGE_SIZE:
        raise HTTPException(status_code=400, detail="File too large. Maximum 5MB.")
    if not content:
        raise HTTPException(status_code=400, detail="Empty file")
    return content, ext


def save_image(content: bytes, filename: str, subdir: str = "") -> str:
    """Persist an image and return the reference to store in the DB —
    a path relative to /static/, e.g. "uploads/tata-salt.jpg"."""
    dest_dir = UPLOAD_DIR / subdir if subdir else UPLOAD_DIR
    dest_dir.mkdir(parents=True, exist_ok=True)
    (dest_dir / filename).write_bytes(content)
    parts = [UPLOAD_PREFIX, subdir, filename] if subdir else [UPLOAD_PREFIX, filename]
    stored = "/".join(parts)
    # The version token is cached for a minute; the one moment it must not be
    # is right after the file it describes was rewritten.
    _version_cache.pop(stored, None)
    return stored


# How long a resolved version token is reused before the file is stat'd again.
# A product list resolves a hundred of these in one response and the answer
# only changes when an admin uploads, so re-checking per image is waste. The
# cost of the cache is that a replacement can take this long to reach the URL.
_VERSION_TTL_SECONDS = 60
_version_cache: dict[str, tuple[float, str]] = {}


def upload_version(stored: str) -> str:
    """A short token that changes when the file behind `stored` changes.

    An upload keeps its filename when it is replaced — that is deliberate, and
    it is what lets a photo be swapped without moving `image_url` or breaking a
    saved cart. The cost is that the URL alone gives a browser no way to tell a
    new photograph from the one it already has. The file's mtime does, so it
    goes in the query string and the URL becomes specific to the bytes.

    Returns "" if the file cannot be stat'd, which leaves the URL unversioned
    rather than inventing a token that would change on every request.
    """
    now = time.monotonic()
    cached = _version_cache.get(stored)
    if cached and now - cached[0] < _VERSION_TTL_SECONDS:
        return cached[1]
    try:
        relative = stored[len(UPLOAD_PREFIX) + 1:]
        token = str(int((UPLOAD_DIR / relative).stat().st_mtime))
    except OSError:
        token = ""
    _version_cache[stored] = (now, token)
    return token


def resolve_image_url(stored: str, base_url: str) -> str:
    """Turn a stored image reference into a public URL.

    Handles three shapes, since existing rows use all of them:
      - absolute URL          -> returned as-is
      - "uploads/x.jpg"       -> served from the upload volume, version-stamped
      - bare "x.jpg" (legacy) -> served from the build-time images/ directory

    Uploads carry a version token because they are now most of the catalogue's
    photographs, and without one they could only be cached for as long as the
    shop is willing to show a stale photo after a replacement. With one, the
    URL changes the moment the file does, so it can be cached for a week — see
    the Cache-Control middleware in main.py, which is the other half of this.
    """
    if not stored:
        return ""
    if stored.startswith("http"):
        return stored
    path = stored if "/" in stored else f"images/{stored}"
    url = f"{base_url}/static/{path}"
    if stored.startswith(f"{UPLOAD_PREFIX}/"):
        token = upload_version(stored)
        if token:
            url = f"{url}?v={token}"
    # Railway terminates TLS upstream; base_url can come back as http.
    return url.replace("http://", "https://", 1) if "railway.app" in url else url
