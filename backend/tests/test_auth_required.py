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


def _guards(route) -> set:
    """Every dependency a route resolves, by name, walked recursively."""
    found, stack = set(), list(getattr(route.dependant, "dependencies", []))
    while stack:
        dep = stack.pop()
        if dep.call is not None:
            # Security schemes like HTTPBearer are instances, not functions,
            # so fall back to the class name.
            found.add(getattr(dep.call, "__name__", type(dep.call).__name__))
        stack.extend(dep.dependencies)
    return found


def test_public_endpoints_stay_public():
    """The catalogue must not start demanding a login.

    Asserted against the dependency graph rather than by calling the routes,
    because browsing hits the database and these tests do not have one. What
    matters is that no auth guard has crept onto them.
    """
    from main import app

    public = {"/health", "/products", "/categories", "/image-credits", "/search", "/banners"}
    for route in app.routes:
        if getattr(route, "path", None) in public:
            guards = _guards(route)
            assert "get_current_user" not in guards and "get_current_admin" not in guards, (
                f"{route.path} now requires auth — customers cannot browse the shop"
            )


def test_protected_endpoints_carry_a_guard():
    """The mirror of the above: every path in PROTECTED resolves an auth
    dependency, so a future refactor cannot quietly drop one and leave the
    403 coming from somewhere incidental."""
    from main import app

    # Only the paths with no paramaters, matched exactly. Templated routes are
    # covered by the request tests above; trying to match them by shape here
    # matched /orders/{order_id}/invoice, which authenticates with a
    # short-lived token in the URL rather than a bearer header — different
    # mechanism, deliberately.
    targets = {"/orders/create", "/addresses", "/cart", "/cart/add",
               "/notifications/send", "/admin/orders/all", "/auth/me"}
    seen = set()
    for route in app.routes:
        path = getattr(route, "path", "")
        if path in targets:
            guards = _guards(route)
            assert guards & {"get_current_user", "get_current_admin"}, (
                f"{path} has no auth dependency"
            )
            seen.add(path)
    missing = targets - seen
    assert not missing, f"these routes have disappeared from the app: {sorted(missing)}"
