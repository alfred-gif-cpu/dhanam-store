"""Firebase Cloud Messaging push helper with graceful fallback.

Activates when a Firebase service account is configured via either:
  - FIREBASE_CREDENTIALS env var containing the service-account JSON, or
  - a firebase-credentials.json file next to this module.
Otherwise it logs to console (dev mode) so the app flow still works.
"""
import os
import json
import logging
from pathlib import Path

log = logging.getLogger(__name__)

_app = None
_messaging = None
_ready = False


def _init():
    global _app, _messaging, _ready
    if _ready:
        return
    _ready = True
    try:
        import firebase_admin
        from firebase_admin import credentials, messaging

        cred = None
        raw = os.environ.get("FIREBASE_CREDENTIALS", "").strip()
        if raw:
            cred = credentials.Certificate(json.loads(raw))
        else:
            path = Path(__file__).parent / "firebase-credentials.json"
            if path.exists():
                cred = credentials.Certificate(str(path))

        if cred is None:
            log.info("No Firebase credentials configured — running in console mode")
            return

        _app = firebase_admin.initialize_app(cred)
        _messaging = messaging
        log.info("Firebase Admin initialized")
    except Exception as e:
        log.warning("Firebase init failed, console mode: %s", e)


def send_to_topic(topic: str, title: str, body: str, data: dict | None = None) -> bool:
    _init()
    if not _messaging:
        log.debug("(console) topic=%s | %s — %s", topic, title, body)
        return False
    try:
        msg = _messaging.Message(
            notification=_messaging.Notification(title=title, body=body),
            topic=topic,
            data={k: str(v) for k, v in (data or {}).items()},
            android=_messaging.AndroidConfig(priority="high"),
        )
        _messaging.send(msg)
        return True
    except Exception as e:
        log.warning("Send to topic %s failed: %s", topic, e)
        return False


def notify_new_order(order: dict) -> bool:
    order_id = order.get("order_id", "")
    total = order.get("grand_total", order.get("total_amount", 0))
    items = len(order.get("items", []))
    return send_to_topic(
        "owner",
        "🛒 New Order Received",
        f"Order {order_id} — ₹{total:.0f} · {items} item(s)",
        {"type": "new_order", "order_id": order_id},
    )


def notify_delivery_ready(order: dict) -> bool:
    order_id = order.get("order_id", "")
    addr = order.get("delivery_address", {}) or {}
    area = addr.get("city") or addr.get("area") or addr.get("label") or "customer"
    return send_to_topic(
        "delivery",
        "📦 Order Ready for Delivery",
        f"Order {order_id} — deliver to {area}",
        {"type": "delivery_ready", "order_id": order_id},
    )
