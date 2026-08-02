"""Replacing a product photo must not leave the old photo's credit behind.

254 products carry `image_credit: "Open Food Facts (...), CC-BY-SA"`, and the
Photo Credits screen renders whatever is in that field. Nothing about an
upload used to clear it, so a shop's own photograph replacing an imported one
inherited the credit — the screen would attribute Alfred's picture to Open
Food Facts and publish it as CC-BY-SA. Wrong in both directions, and silent.

The credit describes the photograph, so it leaves with the photograph.
"""
import pytest
from bson import ObjectId
from mongomock_motor import AsyncMongoMockClient

import routes_admin
from main import app
from admin_auth import get_current_admin

ADMIN = {"id": "admin-1", "email": "owner@dhanamstore.com", "role": "owner"}
# The smallest valid PNG: upload validation checks type, extension and size.
ONE_PIXEL_PNG = bytes.fromhex(
    "89504e470d0a1a0a0000000d49484452000000010000000108060000001f15c4"
    "890000000a49444154789c6360000002000100ffff03000006000557bfabd400"
    "00000049454e44ae426082"
)


@pytest.fixture
def shop(monkeypatch):
    db = AsyncMongoMockClient()["dhanam_store_test"]
    monkeypatch.setattr(routes_admin, "products_collection", db["products"])
    monkeypatch.setattr(routes_admin, "audit_logs_collection", db["audit_logs"],
                        raising=False)
    # Keep the bytes off the disk; where the file lands is not what is on trial.
    monkeypatch.setattr(routes_admin, "save_image",
                        lambda content, filename, subdir="": f"uploads/{filename}")
    app.dependency_overrides[get_current_admin] = lambda: ADMIN
    yield db
    app.dependency_overrides.clear()


async def _product(shop, **fields):
    doc = {"name": "Parle-G 10Rs", "price": 10.0, "stock": 5,
           "image_url": "parle-g-10rs.jpg",
           "image_credit": "Open Food Facts (8901719100956), CC-BY-SA"}
    doc.update(fields)
    result = await shop["products"].insert_one(doc)
    return str(result.inserted_id)


def _upload(client, product_id):
    return client.post(
        f"/admin/products/{product_id}/image",
        files={"file": ("photo.png", ONE_PIXEL_PNG, "image/png")},
    )


@pytest.mark.asyncio
class TestUploadingReplacesTheCredit:
    async def test_the_new_photo_is_recorded(self, client, shop):
        pid = await _product(shop)
        assert _upload(client, pid).status_code == 200

        stored = await shop["products"].find_one({"_id": ObjectId(pid)})
        assert stored["image_url"].startswith("uploads/")

    async def test_the_old_credit_is_removed(self, client, shop):
        pid = await _product(shop)
        _upload(client, pid)

        stored = await shop["products"].find_one({"_id": ObjectId(pid)})
        assert not stored.get("image_credit"), (
            "the replaced photograph's credit survived — the Photo Credits "
            "screen would attribute this shop's own picture to Open Food Facts, "
            "and publish it under CC-BY-SA"
        )

    async def test_a_product_that_never_had_a_credit_is_unharmed(self, client, shop):
        pid = await _product(shop, image_credit=None)
        assert _upload(client, pid).status_code == 200

    async def test_nothing_else_about_the_product_changes(self, client, shop):
        pid = await _product(shop)
        _upload(client, pid)

        stored = await shop["products"].find_one({"_id": ObjectId(pid)})
        assert stored["name"] == "Parle-G 10Rs"
        assert stored["price"] == 10.0
        assert stored["stock"] == 5


@pytest.mark.asyncio
class TestUploadValidation:
    async def test_a_non_image_is_refused(self, client, shop):
        pid = await _product(shop)
        response = client.post(
            f"/admin/products/{pid}/image",
            files={"file": ("payload.exe", b"MZ\x90\x00", "application/octet-stream")},
        )
        assert response.status_code == 400

    async def test_an_empty_file_is_refused(self, client, shop):
        pid = await _product(shop)
        response = client.post(
            f"/admin/products/{pid}/image",
            files={"file": ("empty.png", b"", "image/png")},
        )
        assert response.status_code == 400

    async def test_an_unknown_product_is_refused(self, client, shop):
        response = _upload(client, "000000000000000000000000")
        assert response.status_code == 404
