"""The endpoints that were once open must stay closed.

A route audit found five live holes: a login that issued a session for any
phone number, an order endpoint that trusted the client's price, addresses
with no auth at all, unauthenticated push to every device, and order status,
refunds and the full order list open to anyone. All were closed.

This is the regression test for that. Each case here is a hole that was real,
and the assertion is only that an anonymous caller is turned away — which is
the property that was actually missing. No database is needed, because the
rejection happens in the dependency before any handler runs.
"""
import pytest

# (method, path, what it would expose)
PROTECTED = [
    ("POST", "/orders/create", "place an order as anyone"),
    ("GET", "/addresses", "read every customer's address"),
    ("POST", "/addresses", "write an address to any account"),
    ("GET", "/addresses/000000000000000000000000", "read one address by id"),
    ("PUT", "/addresses/000000000000000000000000", "edit any address"),
    ("DELETE", "/addresses/000000000000000000000000", "delete any address"),
    ("POST", "/notifications/send", "push to every device"),
    ("PUT", "/orders/ORD000001/refund", "refund any order"),
    ("PUT", "/orders/ORD000001/refund-complete", "mark any refund complete"),
    ("GET", "/admin/orders/all", "list every order placed"),
    ("GET", "/auth/me", "read the signed-in account"),
    ("GET", "/cart", "read a cart"),
    ("POST", "/cart/add", "write to a cart"),
    ("GET", "/customers/CUS000001/wishlist", "read a wishlist"),
]


@pytest.mark.parametrize("method,path,exposure", PROTECTED)
def test_rejects_anonymous(client, method, path, exposure):
    response = client.request(method, path, json={})
    assert response.status_code in (401, 403), (
        f"{method} {path} answered {response.status_code} without a token — "
        f"this would let anyone {exposure}"
    )


@pytest.mark.parametrize("method,path,exposure", PROTECTED)
def test_rejects_a_forged_token(client, method, path, exposure):
    response = client.request(
        method, path, json={}, headers={"Authorization": "Bearer not.a.real.token"}
    )
    assert response.status_code in (401, 403), (
        f"{method} {path} accepted a forged token ({response.status_code})"
    )


PUBLIC = ["/health", "/products?limit=1", "/categories", "/image-credits",
          "/search?q=tea", "/banners"]


@pytest.mark.parametrize("path", PUBLIC)
def test_public_endpoints_stay_public(tolerant_client, path):
    """The catalogue must not start demanding a login.

    Asserted by asking, not by reading the route table. An earlier version of
    this file inspected FastAPI's internals, which passed here and failed in
    CI because CI resolved a newer Starlette that arranges routes differently
    — and worse, the public half of that check would have passed vacuously by
    matching nothing at all.

    These paths do reach for the database, which these tests do not have, so
    they answer 500 or 503. That is fine: the question is only whether the
    answer is 401, and an auth guard rejects before the handler runs.
    """
    assert tolerant_client.get(path).status_code != 401, (
        f"{path} now requires a login — customers cannot browse the shop"
    )
