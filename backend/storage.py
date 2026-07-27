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
    return "/".join(parts)


def resolve_image_url(stored: str, base_url: str) -> str:
    """Turn a stored image reference into a public URL.

    Handles three shapes, since existing rows use all of them:
      - absolute URL          -> returned as-is
      - "uploads/x.jpg"       -> served from the upload volume
      - bare "x.jpg" (legacy) -> served from the build-time images/ directory
    """
    if not stored:
        return ""
    if stored.startswith("http"):
        return stored
    path = stored if "/" in stored else f"images/{stored}"
    url = f"{base_url}/static/{path}"
    # Railway terminates TLS upstream; base_url can come back as http.
    return url.replace("http://", "https://", 1) if "railway.app" in url else url
