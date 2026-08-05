"""The panel's controls for hiding a product.

Hiding was applied to 1,651 products by a script, with no way to see or undo
it from the browser — the only route back was a MongoDB client. These cover
the three things that fixed that: the dashboard says how many are actually in
the shop, the product list can be filtered to hidden ones, and a product can
be put back with one call.
"""
import pytest
from bson import ObjectId
from mongomock_motor import AsyncMongoMockClient

import main
import routes_admin
from main import app
from admin_auth import get_current_admin

ADMIN = {"id": "admin-1", "email": "owner@dhanamstore.com", "role": "owner"}


@pytest.fixture
def shop(monkeypatch):
    db = AsyncMongoMockClient()["dhanam_store_test"]
    for module in (main, routes_admin):
        monkeypatch.setattr(module, "products_collection", db["products"])
    # /admin/stats also counts orders and customers. Left unpatched they reach
    # the real client, which binds to whichever event loop touched it first
    # and fails on the next test with "Event loop is closed" — a confusing
    # symptom for a missing patch.
    monkeypatch.setattr(main, "orders_collection", db["orders"])
    monkeypatch.setattr(main, "users_collection", db["users"])
    monkeypatch.setattr(routes_admin, "audit_logs_collection", db["audit_logs"], raising=False)
    app.dependency_overrides[get_current_admin] = lambda: ADMIN
    yield db
    app.dependency_overrides.clear()


async def _add(shop, name, **fields):
    doc = {"name": name, "price": 50.0, "stock": 10, "category": "Rice & Cereals"}
    doc.update(fields)
    return str((await shop["products"].insert_one(doc)).inserted_id)


@pytest.mark.asyncio
class TestTheListShowsEverything:
    """The panel is where a hidden product gets brought back, so it has to
    show what is not on sale — unlike the shop."""

    async def test_hidden_products_are_still_listed(self, client, shop):
        await _add(shop, "Visible Rice")
        await _add(shop, "Hidden Notebook", is_active=False)

        names = {p["name"] for p in client.get("/admin/products").json()["products"]}
        assert names == {"Visible Rice", "Hidden Notebook"}

    async def test_the_flag_is_sent_so_the_row_can_be_marked(self, client, shop):
        await _add(shop, "Hidden Notebook", is_active=False)
        product = client.get("/admin/products").json()["products"][0]
        assert product["is_active"] is False, "the panel cannot show a badge it is not told about"


@pytest.mark.asyncio
class TestFiltering:
    async def test_visible_only(self, client, shop):
        await _add(shop, "Visible Rice")
        await _add(shop, "Hidden Notebook", is_active=False)

        body = client.get("/admin/products?status=visible").json()
        assert [p["name"] for p in body["products"]] == ["Visible Rice"]
        assert body["total"] == 1

    async def test_hidden_only(self, client, shop):
        await _add(shop, "Visible Rice")
        await _add(shop, "Hidden Notebook", is_active=False)

        body = client.get("/admin/products?status=hidden").json()
        assert [p["name"] for p in body["products"]] == ["Hidden Notebook"]

    async def test_no_filter_means_everything(self, client, shop):
        await _add(shop, "Visible Rice")
        await _add(shop, "Hidden Notebook", is_active=False)
        assert client.get("/admin/products").json()["total"] == 2

    async def test_a_product_with_no_flag_counts_as_visible(self, client, shop):
        """Same rule as the shop uses. If these disagreed, the filter would
        describe a different catalogue from the one customers see."""
        await _add(shop, "Legacy Rice")  # no is_active at all
        assert client.get("/admin/products?status=visible").json()["total"] == 1
        assert client.get("/admin/products?status=hidden").json()["total"] == 0


@pytest.mark.asyncio
class TestTheToggle:
    async def test_hiding_a_product(self, client, shop):
        pid = await _add(shop, "Notebook")
        r = client.put(f"/admin/products/{pid}/visibility", json={"visible": False})

        assert r.status_code == 200
        stored = await shop["products"].find_one({"_id": ObjectId(pid)})
        assert stored["is_active"] is False

    async def test_showing_it_again(self, client, shop):
        pid = await _add(shop, "Notebook", is_active=False)
        client.put(f"/admin/products/{pid}/visibility", json={"visible": True})

        stored = await shop["products"].find_one({"_id": ObjectId(pid)})
        assert stored["is_active"] is True

    async def test_price_stock_and_photo_survive(self, client, shop):
        """Hiding is not deleting — everything about the product stays, which
        is the whole reason it beats removing the record."""
        pid = await _add(shop, "Notebook", image_url="notebook.jpg")
        client.put(f"/admin/products/{pid}/visibility", json={"visible": False})

        stored = await shop["products"].find_one({"_id": ObjectId(pid)})
        assert stored["price"] == 50.0
        assert stored["stock"] == 10
        assert stored["image_url"] == "notebook.jpg"

    async def test_it_is_written_to_the_audit_log(self, client, shop):
        pid = await _add(shop, "Notebook")
        client.put(f"/admin/products/{pid}/visibility", json={"visible": False})

        entry = await shop["audit_logs"].find_one({})
        assert entry and "Notebook" in entry.get("details", "")

    async def test_an_unknown_product_is_refused(self, client, shop):
        r = client.put("/admin/products/000000000000000000000000/visibility",
                       json={"visible": False})
        assert r.status_code == 404


@pytest.mark.asyncio
class TestTheDashboardSplit:
    async def test_reports_visible_and_hidden(self, client, shop):
        await _add(shop, "Visible Rice")
        await _add(shop, "Another Rice")
        await _add(shop, "Hidden Notebook", is_active=False)

        stats = client.get("/admin/stats").json()
        assert stats["total_products"] == 3
        assert stats["visible_products"] == 2
        assert stats["hidden_products"] == 1

    async def test_the_split_adds_up(self, client, shop):
        for i in range(4):
            await _add(shop, f"Product {i}", is_active=(i % 2 == 0))

        stats = client.get("/admin/stats").json()
        assert stats["visible_products"] + stats["hidden_products"] == stats["total_products"]
