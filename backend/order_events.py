"""Things that must happen when an order changes hands.

Three handlers can mark an order Delivered — the panel's status update, the
admin status route, and the driver's Delivered button — which is exactly the
shape that let cancellation lose stock for months: two of three siblings did
the right thing and nobody noticed the third. So the rule lives here and all
three call it.

Separate from push_service.py because reaching one customer needs the token
store, and push_service deliberately has no database.
"""
import logging

from database import db
from push_service import notify_order_delivered_owner, send_to_tokens

log = logging.getLogger(__name__)

fcm_tokens_collection = db["fcm_tokens"]

# One customer, a handful of devices. The cap stops a runaway token store from
# turning one delivery into a thousand pushes.
MAX_DEVICES_PER_CUSTOMER = 10


async def order_delivered(order: dict) -> None:
    """Tell the owner and the customer that an order arrived.

    Never raises: a delivery is complete whether or not a notification lands,
    and the driver tapping Delivered must not see an error because Firebase
    was slow.
    """
    order_id = order.get("order_id", "")

    try:
        notify_order_delivered_owner(order)
    except Exception as e:
        log.warning("Owner delivered-notify failed for %s: %s", order_id, e)

    user_id = order.get("user_id") or order.get("customer_id")
    if not user_id:
        log.warning("Order %s has no customer id; cannot notify them", order_id)
        return

    try:
        docs = await fcm_tokens_collection.find(
            {"user_id": user_id}
        ).to_list(MAX_DEVICES_PER_CUSTOMER)
        tokens = [d["token"] for d in docs if d.get("token")]
        if not tokens:
            return

        dead = send_to_tokens(
            tokens,
            "\u2705 Order Delivered",
            f"Your order {order_id} has been delivered. Thank you for shopping "
            "with Dhanam Stores!",
            {"type": "order_delivered", "order_id": order_id},
        )
        for token in dead:
            await fcm_tokens_collection.delete_one({"token": token})
        if dead:
            log.info("Pruned %d dead token(s) for %s", len(dead), user_id)
    except Exception as e:
        log.warning("Customer delivered-notify failed for %s: %s", order_id, e)
