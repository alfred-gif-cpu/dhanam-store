"""Cancelling an order has to put the goods back — by every route that cancels.

Stock is decremented the moment an order is filed. Three handlers can cancel,
and for months only two returned the units:

    PUT /orders/{id}/cancel        (customer)  released
    PUT /orders/{id}/status        (admin)     released
    PUT /admin/orders/{id}/status  (panel)     did not

The one that was missed is the one the panel calls, and the panel is the only
way to cancel anything: the customer app has no cancel button. So in practice
every cancellation leaked its stock, and the shop drifted towards phantom
out-of-stocks with nothing sold. Found by placing a real order against
production on 2026-08-18 and watching stock stay at 99 after cancelling.

These run against mongomock-motor, because "the number went back up" is a
claim about the database and cannot be checked by reading the handler.
"""
import pytest
from bson import ObjectId
from mongomock_motor import AsyncMongoMockClient

import inventory
import routes_admin
from admin_auth import get_current_admin
from main import app

ADMIN = {"id": "admin-1", "email": "owner@dhanamstore.com", "role": "owner"}
PRODUCT_ID = ObjectId()


@pytest.fixture
def shop(monkeypatch):
    db = AsyncMongoMockClient()["dhanam_store_test"]
    monkeypatch.setattr(routes_admin, "orders_collection", db["orders"])
    monkeypatch.setattr(routes_admin, "audit_logs_collection", db["audit_logs"], raising=False)
    monkeypatch.setattr(inventory, "products_collection", db["products"])
    app.dependency_overrides[get_current_admin] = lambda: ADMIN
    yield db
    app.dependency_overrides.clear()


async def _order(shop, status="Confirmed", qty=1, stock=99):
    await shop["products"].insert_one(
        {"_id": PRODUCT_ID, "name": "A2B 10Rs", "stock": stock}
    )
    await shop["orders"].insert_one({
        "order_id": "ORD000020",
        "order_status": status,
        "items": [{"product_id": str(PRODUCT_ID), "name": "A2B 10Rs", "quantity": qty}],
    })


async def _stock(shop):
    return (await shop["products"].find_one({"_id": PRODUCT_ID}))["stock"]


def _set_status(client, status):
    return client.put("/admin/orders/ORD000020/status", json={"status": status})


@pytest.mark.asyncio
class TestPanelCancellation:
    async def test_cancelling_returns_the_units(self, client, shop):
        await _order(shop)
        assert _set_status(client, "Cancelled").status_code == 200
        assert await _stock(shop) == 100, (
            "the panel cancelled the order without returning the stock — the "
            "shop loses a unit for every cancellation, with nothing sold"
        )

    async def test_cancelling_twice_does_not_credit_twice(self, client, shop):
        await _order(shop)
        _set_status(client, "Cancelled")
        _set_status(client, "Cancelled")
        assert await _stock(shop) == 100, "a second cancel invented stock"

    async def test_an_already_refunded_order_is_not_credited_again(self, client, shop):
        await _order(shop, status="Refund Completed", stock=100)
        _set_status(client, "Cancelled")
        assert await _stock(shop) == 100

    async def test_other_statuses_leave_stock_alone(self, client, shop):
        await _order(shop)
        for s in ("Packed", "Out For Delivery", "Delivered"):
            _set_status(client, s)
        assert await _stock(shop) == 99, "a non-cancel status handed stock back"

    async def test_an_unknown_order_is_refused(self, client, shop):
        await _order(shop)
        r = client.put("/admin/orders/ORD999999/status", json={"status": "Cancelled"})
        assert r.status_code == 404
        assert await _stock(shop) == 99


class TestTheSharedRule:
    def test_every_released_status_counts_as_already_released(self):
        for s in inventory.RELEASED_STATUSES:
            assert not inventory.should_release({"order_status": s}, "Cancelled"), (
                f"an order already in {s} would be credited again"
            )

    def test_a_live_order_releases_once(self):
        assert inventory.should_release({"order_status": "Confirmed"}, "Cancelled")

    def test_a_missing_order_status_still_releases(self):
        assert inventory.should_release({}, "Cancelled")
