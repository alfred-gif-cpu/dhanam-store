"""Delivering an order tells the owner and the customer — by every route.

Three handlers can set Delivered: the panel's status update, the admin status
route, and the driver's Delivered button. That is the same shape that let
cancellation lose stock for months, where two of three siblings did the right
thing and nobody noticed the third. The rule lives in order_events.py and this
asserts each route reaches it.

The customer half matters most and is the easiest to get wrong: a topic would
tell every customer in the shop that *their* order arrived, so it has to go to
that one customer's device tokens.
"""
import pytest
from bson import ObjectId
from mongomock_motor import AsyncMongoMockClient

import order_events
import routes_admin
from admin_auth import get_current_admin
from main import app

ADMIN = {"id": "a1", "email": "owner@dhanamstore.com", "role": "owner"}
CUSTOMER_ID = "6a39091ed6850eb0af27c55c"


@pytest.fixture
def shop(monkeypatch):
    db = AsyncMongoMockClient()["dhanam_store_test"]
    monkeypatch.setattr(routes_admin, "orders_collection", db["orders"])
    monkeypatch.setattr(routes_admin, "audit_logs_collection", db["audit_logs"], raising=False)
    monkeypatch.setattr(order_events, "fcm_tokens_collection", db["fcm_tokens"])

    sent = {"owner": [], "tokens": []}
    monkeypatch.setattr(order_events, "notify_order_delivered_owner",
                        lambda order: sent["owner"].append(order.get("order_id")) or True)
    monkeypatch.setattr(order_events, "send_to_tokens",
                        lambda tokens, title, body, data=None: sent["tokens"].extend(tokens) or [])

    app.dependency_overrides[get_current_admin] = lambda: ADMIN
    yield db, sent
    app.dependency_overrides.clear()


async def _order(db, status="Out For Delivery"):
    await db["orders"].insert_one({
        "_id": ObjectId(),
        "order_id": "ORD000021",
        "order_status": status,
        "user_id": CUSTOMER_ID,
        "items": [],
        "grand_total": 40,
    })
    await db["fcm_tokens"].insert_one({"token": "tok-phone", "user_id": CUSTOMER_ID})
    await db["fcm_tokens"].insert_one({"token": "tok-other", "user_id": "someone-else"})


@pytest.mark.asyncio
class TestDeliveredNotification:
    async def test_the_panel_status_update_notifies_both(self, client, shop):
        db, sent = shop
        await _order(db)

        r = client.put("/admin/orders/ORD000021/status", json={"status": "Delivered"})

        assert r.status_code == 200
        assert sent["owner"] == ["ORD000021"], "the owner was not told"
        assert sent["tokens"] == ["tok-phone"], (
            f"expected only this customer's device, got {sent['tokens']}"
        )

    async def test_the_drivers_delivered_button_notifies_both(self, client, shop):
        db, sent = shop
        await _order(db)

        r = client.put("/admin/delivery/orders/ORD000021/delivered")

        assert r.status_code == 200
        assert sent["owner"] == ["ORD000021"]
        assert sent["tokens"] == ["tok-phone"]

    async def test_other_customers_are_not_told(self, client, shop):
        db, sent = shop
        await _order(db)

        client.put("/admin/orders/ORD000021/status", json={"status": "Delivered"})

        assert "tok-other" not in sent["tokens"], (
            "another customer was told that their order arrived"
        )

    async def test_redelivering_does_not_notify_twice(self, client, shop):
        db, sent = shop
        await _order(db, status="Delivered")

        client.put("/admin/orders/ORD000021/status", json={"status": "Delivered"})

        assert sent["owner"] == [], "a repeated status change re-notified everyone"

    async def test_other_statuses_say_nothing(self, client, shop):
        db, sent = shop
        await _order(db, status="Packed")

        client.put("/admin/orders/ORD000021/status", json={"status": "Out For Delivery"})

        assert sent["owner"] == []
        assert sent["tokens"] == []


@pytest.mark.asyncio
class TestItNeverBreaksTheDelivery:
    async def test_a_push_failure_does_not_fail_the_request(self, client, shop, monkeypatch):
        db, _ = shop
        await _order(db)

        def boom(*a, **k):
            raise RuntimeError("Firebase is down")

        monkeypatch.setattr(order_events, "notify_order_delivered_owner", boom)
        monkeypatch.setattr(order_events, "send_to_tokens", boom)

        r = client.put("/admin/delivery/orders/ORD000021/delivered")

        assert r.status_code == 200, (
            "a driver tapping Delivered saw an error because a notification "
            "failed — the goods are already at the door"
        )

    async def test_a_customer_with_no_device_is_not_an_error(self, client, shop):
        db, sent = shop
        await db["orders"].insert_one({
            "_id": ObjectId(), "order_id": "ORD000099",
            "order_status": "Out For Delivery", "user_id": "no-devices",
            "items": [], "grand_total": 10,
        })

        r = client.put("/admin/orders/ORD000099/status", json={"status": "Delivered"})

        assert r.status_code == 200
        assert sent["owner"] == ["ORD000099"], "the owner should still be told"
