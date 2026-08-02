"""Order rules that cost money when they are wrong.

Each of these was a real defect: a client-supplied price that was trusted, an
order accepted from anywhere in the country, and unbounded quantities. They
are cheap to assert and expensive to rediscover.
"""
import pytest
from pydantic import ValidationError

from routes_orders import (
    MAX_ITEM_QUANTITY,
    MAX_ITEMS_PER_ORDER,
    CreateOrderRequest,
    OrderItem,
    _check_serviceable,
)
from fastapi import HTTPException


def _order(**overrides):
    body = {
        "user_id": "u1",
        "items": [{"product_id": "p1", "name": "Rice", "quantity": 1}],
        "address": {"pincode": "635109"},
        "delivery_slot": "today-evening",
    }
    body.update(overrides)
    return body


class TestPriceCannotComeFromTheClient:
    """The order endpoint once trusted whatever price the client sent, so a
    modified app could buy anything for a rupee. The fix was to remove price
    from the request shape entirely and read it from the database."""

    def test_item_model_has_no_price_field(self):
        assert "price" not in OrderItem.model_fields, (
            "OrderItem accepts a price again — the server must read it from the catalogue"
        )

    def test_a_price_sent_anyway_is_discarded(self):
        item = OrderItem(product_id="p1", name="Rice", quantity=1, price=1)
        assert not hasattr(item, "price"), "a client-supplied price survived validation"


class TestQuantityLimits:
    def test_accepts_the_maximum(self):
        CreateOrderRequest(**_order(
            items=[{"product_id": "p1", "quantity": MAX_ITEM_QUANTITY}]))

    def test_rejects_one_over(self):
        with pytest.raises(ValidationError):
            CreateOrderRequest(**_order(
                items=[{"product_id": "p1", "quantity": MAX_ITEM_QUANTITY + 1}]))

    def test_rejects_zero_and_negative(self):
        for bad in (0, -1, -50):
            with pytest.raises(ValidationError):
                CreateOrderRequest(**_order(items=[{"product_id": "p1", "quantity": bad}]))

    def test_rejects_too_many_lines(self):
        many = [{"product_id": f"p{i}", "quantity": 1} for i in range(MAX_ITEMS_PER_ORDER + 1)]
        with pytest.raises(ValidationError):
            CreateOrderRequest(**_order(items=many))

    def test_rejects_an_empty_basket(self):
        with pytest.raises(ValidationError):
            CreateOrderRequest(**_order(items=[]))


class TestDeliveryArea:
    """Cash on delivery makes an out-of-area order expensive: it is discovered
    when someone has already driven there."""

    @pytest.mark.parametrize("pincode", ["635109", "635110", "635126"])
    def test_hosur_pincodes_are_served(self, pincode):
        _check_serviceable(pincode)

    @pytest.mark.parametrize("pincode", ["110001", "600001", "560001", ""])
    def test_everywhere_else_is_refused(self, pincode):
        with pytest.raises(HTTPException) as excinfo:
            _check_serviceable(pincode)
        assert excinfo.value.status_code == 400

    def test_whitespace_does_not_smuggle_one_through(self):
        _check_serviceable("  635109  ")


class TestPaymentMethod:
    def test_only_cash_on_delivery(self):
        with pytest.raises(ValidationError):
            CreateOrderRequest(**_order(payment_method="card"))

    def test_delivery_slot_is_required(self):
        with pytest.raises(ValidationError):
            CreateOrderRequest(**_order(delivery_slot=""))
