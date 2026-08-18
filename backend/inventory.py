"""Putting reserved stock back on the shelf.

Stock is decremented the moment an order is filed, so every path that cancels
an order has to hand those units back. There are three such paths, and for
months only two of them did:

  PUT /orders/{id}/cancel          (customer)  released stock
  PUT /orders/{id}/status          (admin)     released stock
  PUT /admin/orders/{id}/status    (panel)     did not

Not shadowed routes — the route table has no duplicates. Three sibling
handlers that drifted, and the one that was missed is the one the admin panel
calls, which is the only way to cancel an order at all: the customer app has
no cancel button. So in practice every cancellation leaked its stock
permanently, and the shop would have drifted towards phantom out-of-stocks
with nothing sold.

This module exists so the rule lives in one place. It is a separate module
rather than an import between the two route files for the same reason
rate_limit.py is: neither imports the other today, and it should stay that way.
"""
import logging

from bson import ObjectId

from database import products_collection

log = logging.getLogger(__name__)

# Statuses that mean the units have already been returned. Re-applying any of
# them must not credit the stock a second time.
RELEASED_STATUSES = ("Cancelled", "Refund Initiated", "Refund Completed")


async def release_stock(items: list) -> None:
    """Give an order's reserved units back."""
    for item in items or []:
        product_id = item.get("product_id")
        qty = item.get("quantity", 0)
        if not product_id or not qty:
            continue
        if not ObjectId.is_valid(product_id):
            log.warning("Cannot return stock for malformed product id %r", product_id)
            continue
        await products_collection.update_one(
            {"_id": ObjectId(product_id)}, {"$inc": {"stock": qty}}
        )


def should_release(order: dict, new_status: str) -> bool:
    """Whether this status change is the moment stock goes back.

    True only on the *first* transition into a cancelled state, so setting
    Cancelled twice does not hand out the units twice.
    """
    if new_status not in RELEASED_STATUSES:
        return False
    return (order or {}).get("order_status") not in RELEASED_STATUSES
