"""The ordering flow, end to end, against a real database engine.

Everything else in this suite is a unit test. Ordering cannot be: its two
most important properties are things a database does, not things a function
returns. Stock is reserved by a conditional update, so that two customers
racing for the last unit cannot both win; the order number comes from an
atomic counter, because the old read-then-increment handed the same number to
two checkouts and the second one got a 500. Neither is observable without
actually running the queries.

The database here is mongomock-motor — a real query engine running in
process. No server, no container, no network, so these run in CI and on a
laptop with no MongoDB installed. It is not Atlas, and it does not prove
behaviour under genuine concurrency, but it does execute the same update
documents against the same semantics, which is what these properties turn on.
"""
import pytest
from bson import ObjectId
from mongomock_motor import AsyncMongoMockClient

import routes_orders
from main import app
from auth import get_current_user

CUSTOMER = {"id": "user-1", "phone": "+919876543210", "name": "Test", "is_active": True}
HOSUR = {"pincode": "635109", "full_name": "Test", "phone": "+919876543210",
         "house_no": "1", "street": "Main", "city": "Hosur", "state": "TN"}


@pytest.fixture
def shop(monkeypatch):
    """A fresh, empty shop for each test.

    Every collection routes_orders reaches for is swapped, so nothing here can
    touch the real database even if a query is added later.
    """
    db = AsyncMongoMockClient()["dhanam_store_test"]
    for name in ("orders_collection", "products_collection",
                 "customers_collection", "users_collection", "counters_collection"):
        monkeypatch.setattr(routes_orders, name,
                            db[name.replace("_collection", "")], raising=True)

    # The shop owner's push notification would reach for Firebase credentials.
    monkeypatch.setattr(routes_orders, "notify_new_order", lambda order: None)
    # Ten orders a minute is right in production and wrong in a test that
    # places eleven.
    monkeypatch.setattr(routes_orders.limiter, "enabled", False)

    app.dependency_overrides[get_current_user] = lambda: CUSTOMER
    yield db
    app.dependency_overrides.clear()


async def _stock(shop, product_id) -> int:
    doc = await shop["products"].find_one({"_id": ObjectId(product_id)})
    return doc["stock"]


@pytest.fixture
def add_product(shop):
    async def _add(name="Dds Raw Rice 1kg", price=50.0, stock=10, gst=5):
        result = await shop["products"].insert_one(
            {"name": name, "price": price, "stock": stock, "gst": gst})
        return str(result.inserted_id)
    return _add


def _order(product_id, quantity=1, **overrides):
    body = {
        "user_id": "user-1",
        "items": [{"product_id": product_id, "name": "Rice", "quantity": quantity}],
        "address": HOSUR,
        "delivery_slot": "today-evening",
    }
    body.update(overrides)
    return body


@pytest.mark.asyncio
class TestPriceComesFromTheCatalogue:
    """The bug: the endpoint trusted the client's price, so a modified app
    could buy anything for a rupee."""

    async def test_total_uses_the_database_price(self, client, shop, add_product):
        pid = await add_product(price=50.0, stock=10)
        response = client.post("/orders/create", json=_order(pid, quantity=2))

        assert response.status_code == 200, response.text
        # 2 x Rs 50 = Rs 100, plus Rs 30 delivery because it is under Rs 499.
        assert response.json()["total_amount"] == 130.0

    async def test_a_price_in_the_payload_is_ignored(self, client, shop, add_product):
        pid = await add_product(price=50.0, stock=10)
        body = _order(pid, quantity=2)
        body["items"][0]["price"] = 1  # what an attacker would send
        body["items"][0]["subtotal"] = 2

        response = client.post("/orders/create", json=body)

        assert response.status_code == 200, response.text
        assert response.json()["total_amount"] == 130.0, (
            "the client's price reached the total — this is the tampering bug"
        )

    async def test_a_product_with_no_price_is_refused(self, client, shop, add_product):
        pid = await add_product(price=0, stock=10)
        assert client.post("/orders/create", json=_order(pid)).status_code == 400


@pytest.mark.asyncio
class TestStockIsReserved:
    """The bug: stock was never decremented at all, so the shop could sell the
    same last packet to everybody."""

    async def test_stock_falls_by_the_quantity_ordered(self, client, shop, add_product):
        pid = await add_product(stock=10)
        client.post("/orders/create", json=_order(pid, quantity=3))
        assert await _stock(shop, pid) == 7

    async def test_ordering_more_than_exists_is_refused(self, client, shop, add_product):
        pid = await add_product(stock=2)
        response = client.post("/orders/create", json=_order(pid, quantity=3))

        assert response.status_code == 409
        assert await _stock(shop, pid) == 2, "stock moved on a refused order"

    async def test_the_last_unit_goes_to_one_customer_only(self, client, shop, add_product):
        pid = await add_product(stock=1)

        first = client.post("/orders/create", json=_order(pid, quantity=1))
        second = client.post("/orders/create", json=_order(pid, quantity=1))

        assert first.status_code == 200
        assert second.status_code == 409, "the same last unit was sold twice"
        assert await _stock(shop, pid) == 0

    async def test_a_short_second_item_gives_back_the_first(self, client, shop, add_product):
        """Reserve-or-take-none. Without this the first item stays reserved on
        a failed order and quietly disappears from the shelf."""
        plenty = await add_product(name="Rice", stock=10)
        scarce = await add_product(name="Dhal", stock=1)

        body = _order(plenty, quantity=2)
        body["items"].append({"product_id": scarce, "name": "Dhal", "quantity": 5})
        response = client.post("/orders/create", json=body)

        assert response.status_code == 409
        assert await _stock(shop, plenty) == 10, "the first item stayed reserved"
        assert await _stock(shop, scarce) == 1

    async def test_no_stock_is_taken_for_an_undeliverable_address(self, client, shop, add_product):
        pid = await add_product(stock=10)
        body = _order(pid, quantity=2)
        body["address"] = {**HOSUR, "pincode": "110001"}

        assert client.post("/orders/create", json=body).status_code == 400
        assert await _stock(shop, pid) == 10


@pytest.mark.asyncio
class TestOrderNumbers:
    """The bug: order ids were read-then-incremented, so two checkouts landing
    together resolved to the same number and the second insert hit the unique
    index and returned a 500 with no order."""

    async def test_each_order_gets_its_own_number(self, client, shop, add_product):
        pid = await add_product(stock=50)
        numbers = [client.post("/orders/create", json=_order(pid)).json()["order_id"]
                   for _ in range(5)]

        assert len(set(numbers)) == 5, f"order numbers repeated: {numbers}"

    async def test_numbers_increase(self, client, shop, add_product):
        pid = await add_product(stock=50)
        numbers = [client.post("/orders/create", json=_order(pid)).json()["order_id"]
                   for _ in range(3)]

        assert numbers == sorted(numbers)
        assert all(n.startswith("ORD") for n in numbers)

    async def test_counting_continues_past_existing_orders(self, client, shop, add_product):
        """A shop with orders placed before the counter existed must not start
        again from one and collide with them."""
        await shop["orders"].insert_one({"order_id": "ORD000041"})
        pid = await add_product(stock=10)

        number = client.post("/orders/create", json=_order(pid)).json()["order_id"]

        assert int(number[3:]) > 41, f"{number} would collide with an existing order"


@pytest.mark.asyncio
class TestTheOrderThatGetsStored:
    async def test_filed_against_the_authenticated_caller(self, client, shop, add_product):
        """A client-supplied user_id would let anyone order in someone else's
        name, and read that order afterwards."""
        pid = await add_product(stock=10)
        body = _order(pid)
        body["user_id"] = "somebody-else"

        client.post("/orders/create", json=body)

        stored = await shop["orders"].find_one({})
        assert stored["user_id"] == CUSTOMER["id"]
        assert stored["customer_id"] == CUSTOMER["id"]

    async def test_delivery_is_free_above_the_threshold(self, client, shop, add_product):
        pid = await add_product(price=500.0, stock=10)
        assert client.post("/orders/create", json=_order(pid)).json()["total_amount"] == 500.0

    async def test_delivery_is_charged_below_it(self, client, shop, add_product):
        pid = await add_product(price=498.0, stock=10)
        assert client.post("/orders/create", json=_order(pid)).json()["total_amount"] == 528.0

    async def test_gst_is_broken_out_not_added_on(self, client, shop, add_product):
        """Prices are already GST-inclusive. Adding the tax again would
        overcharge every customer by five percent."""
        pid = await add_product(price=105.0, stock=10, gst=5)
        client.post("/orders/create", json=_order(pid))

        stored = await shop["orders"].find_one({})
        assert stored["subtotal"] == 105.0
        assert stored["gst"] == 5.0, "GST is not the portion already inside the price"
        assert stored["total_amount"] == 135.0  # 105 + 30 delivery, tax not added again

    async def test_the_name_stored_is_the_catalogue_name(self, client, shop, add_product):
        """So a renamed product does not appear on the invoice under whatever
        the app had cached."""
        pid = await add_product(name="Dds Raw Rice 1kg", stock=10)
        body = _order(pid)
        body["items"][0]["name"] = "whatever the client felt like"

        client.post("/orders/create", json=body)

        stored = await shop["orders"].find_one({})
        assert stored["items"][0]["name"] == "Dds Raw Rice 1kg"
