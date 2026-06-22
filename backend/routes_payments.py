import hmac
import hashlib
import razorpay
from fastapi import APIRouter, HTTPException, Body
from pydantic import BaseModel
from config import settings

router = APIRouter(prefix="/payments", tags=["Payments"])

_client = razorpay.Client(auth=(settings.razorpay_key_id, settings.razorpay_key_secret))


class CreateOrderRequest(BaseModel):
    amount: float
    currency: str = "INR"
    receipt: str = ""


class VerifyRequest(BaseModel):
    razorpay_order_id: str
    razorpay_payment_id: str
    razorpay_signature: str


@router.post("/create-order")
async def create_razorpay_order(req: CreateOrderRequest):
    amount_paise = int(round(req.amount * 100))
    if amount_paise < 100:
        raise HTTPException(status_code=400, detail="Minimum amount is ₹1")

    try:
        order = _client.order.create({
            "amount": amount_paise,
            "currency": req.currency,
            "receipt": req.receipt,
            "payment_capture": 1,
        })
        return {
            "order_id": order["id"],
            "amount": order["amount"],
            "currency": order["currency"],
            "key_id": settings.razorpay_key_id,
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/verify")
async def verify_payment(req: VerifyRequest):
    message = f"{req.razorpay_order_id}|{req.razorpay_payment_id}"
    expected = hmac.new(
        settings.razorpay_key_secret.encode(),
        message.encode(),
        hashlib.sha256,
    ).hexdigest()

    if not hmac.compare_digest(expected, req.razorpay_signature):
        raise HTTPException(status_code=400, detail="Invalid payment signature")

    return {"verified": True, "payment_id": req.razorpay_payment_id}
