"""Uploaded photos must be cacheable for a week without going stale.

Uploads expired in five minutes, because a replacement reuses the same
filename and there was no other way to make the new photograph appear. That was
cheap when uploads were a few dozen hand-made exceptions. They are now 637 of
the catalogue's 993 photographs, so nearly every product image cost a round
trip every five minutes of browsing — and for customers in Hosur that round
trip is most of the perceived load time, which is the whole reason the
Cache-Control middleware exists.

The fix is to make the URL specific to the bytes: stamp it with the file's
mtime, so replacing a photo changes the URL and a week-long cache is safe.
Both halves have to hold, so both are tested here — a version that does not
change on replacement would serve a stale photo for a week, and a long
Cache-Control without the version would do the same.
"""
import time

import pytest

import storage
from storage import UPLOAD_PREFIX, resolve_image_url

BASE = "https://dhanam-store-production.up.railway.app"


@pytest.fixture
def upload(tmp_path, monkeypatch):
    """Point the upload directory at a temp dir and hand back a writer."""
    monkeypatch.setattr(storage, "UPLOAD_DIR", tmp_path)
    storage._version_cache.clear()

    def write(filename: str, content: bytes = b"photo") -> str:
        return storage.save_image(content, filename)

    return write


class TestUploadUrlsCarryAVersion:
    def test_an_upload_is_stamped(self, upload):
        stored = upload("parle-g-10rs.jpg")
        assert f"/static/{UPLOAD_PREFIX}/parle-g-10rs.jpg?v=" in resolve_image_url(stored, BASE)

    def test_the_stamp_changes_when_the_photo_is_replaced(self, upload):
        stored = upload("parle-g-10rs.jpg")
        before = resolve_image_url(stored, BASE)

        # mtime has one-second resolution, and a replacement the same second
        # would otherwise be indistinguishable.
        time.sleep(1.1)
        upload("parle-g-10rs.jpg", b"a different photograph")
        after = resolve_image_url(stored, BASE)

        assert before != after, (
            "the replaced photograph resolved to the same URL — customers "
            "holding a week-long cached copy would keep seeing the old one"
        )

    def test_the_stamp_is_stable_while_the_photo_is_not_touched(self, upload):
        stored = upload("parle-g-10rs.jpg")
        assert resolve_image_url(stored, BASE) == resolve_image_url(stored, BASE)

    def test_a_missing_file_resolves_without_a_version(self, upload):
        url = resolve_image_url(f"{UPLOAD_PREFIX}/never-uploaded.jpg", BASE)
        assert "?v=" not in url, (
            "a token invented for a missing file would change per request and "
            "make the URL uncacheable"
        )
        assert url.endswith("/never-uploaded.jpg")

    def test_legacy_and_absolute_references_are_untouched(self, upload):
        assert resolve_image_url("parle-g.jpg", BASE) == f"{BASE}/static/images/parle-g.jpg"
        assert resolve_image_url("https://example.com/x.jpg", BASE) == "https://example.com/x.jpg"
        assert resolve_image_url("", BASE) == ""


class TestCacheHeaders:
    def test_a_versioned_upload_is_cached_for_a_week(self, client):
        r = client.get(f"/static/{UPLOAD_PREFIX}/anything.jpg?v=123")
        assert r.headers["Cache-Control"] == "public, max-age=604800"

    def test_an_unversioned_upload_keeps_the_short_life(self, client):
        r = client.get(f"/static/{UPLOAD_PREFIX}/anything.jpg")
        assert r.headers["Cache-Control"] == "public, max-age=300"

    def test_build_time_images_are_still_cached_for_a_week(self, client):
        r = client.get("/static/images/parle-g.jpg")
        assert r.headers["Cache-Control"] == "public, max-age=604800"
