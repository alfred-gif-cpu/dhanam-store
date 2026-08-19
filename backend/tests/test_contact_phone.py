"""A Google customer's delivery number is recorded, but never as identity.

Signing in with Google proves an email, not a phone. The shop is cash on
delivery and has to ring somebody, and the address form already requires a
number — so the order path records it rather than asking twice.

Where it is recorded is the whole point. OTP login finds an existing account
with users_collection.find_one({"phone": ...}). Writing an unverified number
into `phone` would therefore hand this account to whoever actually owns that
number, the next time they signed in with an OTP. Claimed and verified are
different things and live in different fields.
"""
import pytest
from bson import ObjectId
from mongomock_motor import AsyncMongoMockClient

import inventory
import routes_orders
from auth import get_current_user
from main import app

USER_ID = str(ObjectId())
CUSTOMER = {"id": USER_ID, "phone": "", "name": "Felcia"}

ADDRESS = {
    "name": "Felcia", "phone": "9489630602", "house_no": "h-131A",
    "street": "dhanam street", "landmark": "opp railway station",
    "area": "hosur", "city": "hosur", "state": "Tamil Nadu",
    "pincode": "635109", "label": "Home",
}


@pytest.fixture
def shop(monkeypatch):
    db = AsyncMongoMockClient()["dhanam_store_test"]
    for name in ("orders_collection", "products_collection",
                 "customers_collection", "users_collection", "counters_collection"):
        monkeypatch.setattr(routes_orders, name, db[name.replace("_collection", "")], raising=True)
    monkeypatch.setattr(inventory, "products_collection", db["products"], raising=True)
    monkeypatch.setattr(routes_orders, "notify_new_order", lambda o: None)
    monkeypatch.setattr(routes_orders.limiter, "enabled", False)
    app.dependency_overrides[get_current_user] = lambda: CUSTOMER
    yield db
    app.dependency_overrides.clear()


async def _setup(db, user_phone=""):
    pid = ObjectId()
    await db["products"].insert_one(
        {"_id": pid, "name": "A2B 10Rs", "price": 10.0, "stock": 50, "is_active": True})
    await db["users"].insert_one({"_id": ObjectId(USER_ID), "phone": user_phone, "email": "f@g.com"})
    return str(pid)


def _order(client, pid):
    return client.post("/orders/create", json={
        "user_id": USER_ID,
        "items": [{"product_id": pid, "quantity": 1}],
        "address": ADDRESS,
        "delivery_slot": "Today 9 AM - 12 PM",
        "payment_method": "cod",
    })


@pytest.mark.asyncio
class TestContactPhone:
    async def test_it_is_recorded_for_a_customer_with_no_verified_phone(self, client, shop):
        pid = await _setup(shop)

        assert _order(client, pid).status_code in (200, 201)

        user = await shop["users"].find_one({"_id": ObjectId(USER_ID)})
        assert user["contact_phone"] == "9489630602"

    async def test_it_never_lands_in_the_field_login_matches_on(self, client, shop):
        pid = await _setup(shop)

        _order(client, pid)

        user = await shop["users"].find_one({"_id": ObjectId(USER_ID)})
        assert user.get("phone", "") == "", (
            "an unverified number was written to `phone` — the next OTP login "
            "by whoever really owns that number would land in this account"
        )

    async def test_a_verified_number_is_never_overwritten(self, client, shop):
        pid = await _setup(shop, user_phone="+919000000001")

        _order(client, pid)

        user = await shop["users"].find_one({"_id": ObjectId(USER_ID)})
        assert user["phone"] == "+919000000001", "a verified number was replaced"
        assert "contact_phone" not in user, (
            "this customer already has a verified number; a second one only "
            "creates a question about which to ring"
        )
