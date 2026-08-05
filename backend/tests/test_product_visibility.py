"""Hidden products stay out of the shop, and the shop still works.

`is_active` sat on all 2,871 products and was read by nothing, so it hid
nothing. These assert both halves of making it mean something: a hidden
product disappears from every way a customer could come across it, and a
product without the field — which is most of them, and every one an import
script creates — still appears.

That second half is the one that would hurt. A filter written as
`{"is_active": True}` rather than `{"$ne": False}` would empty the shop for
every product that predates the field, and it would do it silently.
"""
import pytest
from bson import ObjectId
from mongomock_motor import AsyncMongoMockClient

import main
from main import app

DISCOVERY = [
    "/products?limit=100",
    "/products/featured?limit=100",
    "/products/trending?limit=100",
    "/products/bestsellers?limit=100",
    "/products/flash-deals?limit=100",
    "/search?q=rice&limit=100",
]


@pytest.fixture
def shop(monkeypatch):
    db = AsyncMongoMockClient()["dhanam_store_test"]
    monkeypatch.setattr(main, "products_collection", db["products"])
    monkeypatch.setattr(main.limiter, "enabled", False)
    return db


async def _add(shop, name, **fields):
    doc = {"name": name, "price": 50.0, "stock": 10, "category": "Rice & Cereals",
           "search_text": name.lower().replace(" ", ""), "sold_count": 1}
    doc.update(fields)
    return str((await shop["products"].insert_one(doc)).inserted_id)


def _names(response) -> set:
    body = response.json()
    return {p["name"] for p in body.get("products", [])}


@pytest.mark.asyncio
class TestHiddenProductsDisappear:
    @pytest.mark.parametrize("path", DISCOVERY)
    async def test_gone_from_every_way_in(self, client, shop, path):
        await _add(shop, "Visible Rice 1kg")
        await _add(shop, "Hidden Rice 1kg", is_active=False)

        found = _names(client.get(path))
        assert "Hidden Rice 1kg" not in found, f"a hidden product is still listed by {path}"

    async def test_the_rest_of_the_shop_is_unaffected(self, client, shop):
        await _add(shop, "Visible Rice 1kg")
        await _add(shop, "Hidden Rice 1kg", is_active=False)

        assert "Visible Rice 1kg" in _names(client.get("/products?limit=100"))

    async def test_hidden_products_do_not_count_toward_the_total(self, client, shop):
        await _add(shop, "Visible Rice 1kg")
        await _add(shop, "Hidden Rice 1kg", is_active=False)

        assert client.get("/products?limit=100").json()["total"] == 1

    async def test_a_category_with_nothing_visible_is_not_offered(self, client, shop):
        await _add(shop, "Hidden Torch", category="Electronics", is_active=False)
        await _add(shop, "Visible Rice 1kg")

        categories = {c["name"] for c in client.get("/categories").json()["categories"]}
        assert "Electronics" not in categories
        assert "Rice & Cereals" in categories


@pytest.mark.asyncio
class TestProductsWithoutTheFieldStayVisible:
    """Most of the catalogue has never had the field set either way."""

    async def test_a_product_with_no_flag_is_shown(self, client, shop):
        await _add(shop, "Legacy Rice 1kg")  # no is_active at all
        assert "Legacy Rice 1kg" in _names(client.get("/products?limit=100"))

    async def test_explicitly_active_is_shown(self, client, shop):
        await _add(shop, "Active Rice 1kg", is_active=True)
        assert "Active Rice 1kg" in _names(client.get("/products?limit=100"))

    async def test_the_shop_is_not_empty_when_nothing_sets_the_field(self, client, shop):
        for i in range(5):
            await _add(shop, f"Legacy Product {i}")
        assert client.get("/products?limit=100").json()["total"] == 5, (
            "the filter emptied the shop for products that predate the field"
        )


@pytest.mark.asyncio
class TestHidingIsNotDeleting:
    """Hidden means off the shelf, not withdrawn. A cart or wishlist saved
    before the product was hidden must not break, and an order already placed
    for it has to keep working."""

    async def test_still_reachable_by_id(self, client, shop):
        pid = await _add(shop, "Hidden Rice 1kg", is_active=False)
        assert client.get(f"/products/{pid}").status_code == 200

    async def test_still_resolvable_in_bulk(self, client, shop):
        pid = await _add(shop, "Hidden Rice 1kg", is_active=False)
        assert "Hidden Rice 1kg" in _names(client.get(f"/products/by-ids?ids={pid}"))

    async def test_unhiding_brings_it_straight_back(self, client, shop):
        pid = await _add(shop, "Seasonal Notebook", is_active=False)
        assert "Seasonal Notebook" not in _names(client.get("/products?limit=100"))

        await shop["products"].update_one({"_id": ObjectId(pid)},
                                          {"$set": {"is_active": True}})
        assert "Seasonal Notebook" in _names(client.get("/products?limit=100"))
