from datetime import datetime
from fastapi import APIRouter, Query, HTTPException, Body
from bson import ObjectId
from database import db

router = APIRouter(tags=["Cart"])

carts_col = db["carts"]

GST_RATE = 0.18
FREE_DELIVERY_THRESHOLD = 499
DELIVERY_FEE = 30


def serialize(doc: dict) -> dict:
    doc["id"] = str(doc.pop("_id"))
    return doc


def _now() -> str:
    return datetime.utcnow().isoformat()


def _recalculate(cart: dict) -> dict:
    items = cart.get("items", [])
    for item in items:
        item["subtotal"] = round(item["price"] * item["quantity"], 2)

    subtotal = round(sum(i["subtotal"] for i in items), 2)
    gst = round(subtotal * GST_RATE, 2)
    delivery_fee = 0 if subtotal >= FREE_DELIVERY_THRESHOLD else DELIVERY_FEE
    discount = cart.get("discount", 0)
    grand_total = round(subtotal + gst + delivery_fee - discount, 2)

    cart.update({
        "items": items,
        "subtotal": subtotal,
        "gst": gst,
        "delivery_fee": delivery_fee,
        "discount": discount,
        "grand_total": grand_total,
        "item_count": sum(i["quantity"] for i in items),
        "unique_count": len(items),
        "savings": round(sum(
            (i.get("original_price", i["price"]) - i["price"]) * i["quantity"]
            for i in items if i.get("original_price", 0) > i["price"]
        ), 2),
        "free_delivery_remaining": max(0, round(FREE_DELIVERY_THRESHOLD - subtotal, 2)) if subtotal < FREE_DELIVERY_THRESHOLD else 0,
        "updated_at": _now(),
    })
    return cart


async def _get_or_create_cart(customer_id: str) -> dict:
    cart = await carts_col.find_one({"customer_id": customer_id})
    if not cart:
        cart = {
            "customer_id": customer_id,
            "items": [],
            "subtotal": 0, "gst": 0, "delivery_fee": 0,
            "discount": 0, "grand_total": 0,
            "item_count": 0, "unique_count": 0, "savings": 0,
            "free_delivery_remaining": FREE_DELIVERY_THRESHOLD,
            "created_at": _now(), "updated_at": _now(),
        }
        result = await carts_col.insert_one(cart)
        cart["_id"] = result.inserted_id
    return cart


@router.get("/cart")
async def get_cart(customer_id: str = Query(...)):
    cart = await _get_or_create_cart(customer_id)
    return serialize(_recalculate(cart))


@router.post("/cart/add")
async def add_to_cart(
    customer_id: str = Body(...),
    product_id: str = Body(...),
    product_name: str = Body(""),
    price: float = Body(...),
    original_price: float = Body(0),
    quantity: int = Body(1),
    image: str = Body(""),
    category: str = Body(""),
):
    if quantity < 1:
        raise HTTPException(status_code=400, detail="Quantity must be at least 1")

    cart = await _get_or_create_cart(customer_id)
    items = cart.get("items", [])

    existing = next((i for i in items if i["product_id"] == product_id), None)
    if existing:
        existing["quantity"] += quantity
    else:
        items.append({
            "product_id": product_id,
            "product_name": product_name,
            "price": price,
            "original_price": original_price if original_price > 0 else price,
            "quantity": quantity,
            "image": image,
            "category": category,
            "subtotal": 0,
        })

    cart["items"] = items
    cart = _recalculate(cart)
    await carts_col.update_one({"customer_id": customer_id}, {"$set": cart})
    return serialize(cart)


@router.put("/cart/update")
async def update_cart_item(
    customer_id: str = Body(...),
    product_id: str = Body(...),
    quantity: int = Body(...),
):
    cart = await _get_or_create_cart(customer_id)
    items = cart.get("items", [])

    if quantity <= 0:
        items = [i for i in items if i["product_id"] != product_id]
    else:
        item = next((i for i in items if i["product_id"] == product_id), None)
        if not item:
            raise HTTPException(status_code=404, detail="Product not in cart")
        item["quantity"] = quantity

    cart["items"] = items
    cart = _recalculate(cart)
    await carts_col.update_one({"customer_id": customer_id}, {"$set": cart})
    return serialize(cart)


@router.delete("/cart/remove/{product_id}")
async def remove_from_cart(product_id: str, customer_id: str = Query(...)):
    cart = await _get_or_create_cart(customer_id)
    cart["items"] = [i for i in cart.get("items", []) if i["product_id"] != product_id]
    cart = _recalculate(cart)
    await carts_col.update_one({"customer_id": customer_id}, {"$set": cart})
    return serialize(cart)


@router.delete("/cart/clear")
async def clear_cart(customer_id: str = Query(...)):
    cart = await _get_or_create_cart(customer_id)
    cart["items"] = []
    cart["discount"] = 0
    cart = _recalculate(cart)
    await carts_col.update_one({"customer_id": customer_id}, {"$set": cart})
    return serialize(cart)


@router.post("/cart/sync")
async def sync_cart(customer_id: str = Body(...), items: list = Body(...)):
    cart = await _get_or_create_cart(customer_id)
    cart["items"] = items
    cart = _recalculate(cart)
    await carts_col.update_one({"customer_id": customer_id}, {"$set": cart})
    return serialize(cart)
