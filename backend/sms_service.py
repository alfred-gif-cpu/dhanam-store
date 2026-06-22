import httpx
from config import settings

FAST2SMS_URL = "https://www.fast2sms.com/dev/bulkV2"


def _clean_phone(phone: str) -> str:
    """Strip +91 / spaces and return 10-digit number."""
    p = phone.replace("+91", "").replace(" ", "").strip()
    if p.startswith("91") and len(p) == 12:
        p = p[2:]
    return p


def send_sms(phone: str, message: str) -> bool:
    number = _clean_phone(phone)
    if not settings.sms_api_key:
        print(f"[SMS] (no API key) to {number}:\n{message}")
        return False
    try:
        params = {
            "authorization": settings.sms_api_key,
            "route": "q",
            "message": message,
            "language": "english",
            "flash": 0,
            "numbers": number,
        }
        resp = httpx.get(FAST2SMS_URL, params=params, timeout=15)
        ok = resp.status_code == 200 and resp.json().get("return") is True
        if not ok:
            print(f"[SMS] Failed to {number}: {resp.text}")
        return ok
    except Exception as e:
        print(f"[SMS] Error sending to {number}: {e}")
        return False


def send_otp_sms(phone: str, otp: str) -> bool:
    message = f"Your Dhanam Store OTP is {otp}. Valid for 5 minutes."
    if not settings.sms_api_key:
        print(f"[SMS] (no API key) to {_clean_phone(phone)}:\n{message}")
        return False

    number = _clean_phone(phone)

    # Try the dedicated OTP route first (needs DLT-approved account)
    try:
        params = {
            "authorization": settings.sms_api_key,
            "route": "otp",
            "variables_values": otp,
            "flash": 0,
            "numbers": number,
        }
        resp = httpx.get(FAST2SMS_URL, params=params, timeout=15)
        if resp.status_code == 200 and resp.json().get("return") is True:
            return True
        print(f"[SMS] OTP route failed to {number}, falling back to quick route: {resp.text}")
    except Exception as e:
        print(f"[SMS] OTP route error to {number}, falling back to quick route: {e}")

    # Fallback to the quick (q) route which works without DLT setup
    return send_sms(phone, message)


def send_order_receipt_sms(phone: str, order: dict) -> bool:
    order_id = order.get("order_id", order.get("order_number", ""))
    total = order.get("grand_total", order.get("total_amount", 0))
    item_count = len(order.get("items", []))
    payment = order.get("payment_method", "cod").upper()
    slot = order.get("delivery_slot", "")

    message = (
        f"Dhanam Store - Order Confirmed!\n"
        f"Order: {order_id}\n"
        f"Items: {item_count}\n"
        f"Total: Rs.{total:.2f}\n"
        f"Payment: {payment}\n"
        f"Delivery: {slot}\n"
        f"Thank you for shopping with us!"
    )
    return send_sms(phone, message)
