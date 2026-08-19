"""The delivery list shows the newest order first.

It used to sort oldest first, so an order a driver had just been pushed a
notification about appeared at the *bottom*, under ones already dealt with.
Reported from a real phone: the list read ORD000011 above ORD000023.

The order of a list is easy to change by accident and impossible to notice in
code review, so it is asserted rather than assumed.
"""
import pytest
from mongomock_motor import AsyncMongoMockClient

import routes_admin
from admin_auth import get_current_admin
from main import app

ADMIN = {"id": "a1", "email": "owner@dhanamstore.com", "role": "owner"}


@pytest.fixture
def shop(monkeypatch):
    db = AsyncMongoMockClient()["dhanam_store_test"]
    monkeypatch.setattr(routes_admin, "orders_collection", db["orders"])
    app.dependency_overrides[get_current_admin] = lambda: ADMIN
    yield db
    app.dependency_overrides.clear()


async def _packed(shop, order_id, updated_at):
    await shop["orders"].insert_one({
        "order_id": order_id,
        "order_status": "Packed",
        "updated_at": updated_at,
        "items": [],
    })


@pytest.mark.asyncio
class TestDeliveryListOrder:
    async def test_newest_first(self, client, shop):
        await _packed(shop, "ORD000011", "2026-08-18T09:00:00")
        await _packed(shop, "ORD000023", "2026-08-18T15:00:00")
        await _packed(shop, "ORD000017", "2026-08-18T12:00:00")

        body = client.get("/admin/delivery/orders").json()
        ids = [o["order_id"] for o in body["orders"]]

        assert ids == ["ORD000023", "ORD000017", "ORD000011"], (
            "the order a driver was just notified about is not at the top — "
            f"got {ids}"
        )

    async def test_only_packed_and_out_for_delivery_appear(self, client, shop):
        await _packed(shop, "ORD000001", "2026-08-18T09:00:00")
        await shop["orders"].insert_one({
            "order_id": "ORD000002", "order_status": "Delivered",
            "updated_at": "2026-08-18T18:00:00", "items": [],
        })

        body = client.get("/admin/delivery/orders").json()
        ids = [o["order_id"] for o in body["orders"]]

        assert ids == ["ORD000001"], "a delivered order is still on the run sheet"
        assert body["total"] == 1
